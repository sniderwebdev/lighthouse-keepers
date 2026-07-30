extends Node
## Net — thin wrapper over the Nakama Godot client.
##
## Responsibilities:
##   - authenticate the keeper
##   - join the single shared world match (authoritative)
##   - SEND commands (intents) up to the match
##   - RECEIVE authoritative state diffs and hand them to WorldState
##
## Every opcode lives in Command (game/command.gd), mirrored in match_handler.ts.

## Keeper slot claims a connection can request. "both" is couch play: one
## machine, two pads, one connection driving both keepers.
const SLOTS_A := "keeper_a"
const SLOTS_B := "keeper_b"
const SLOTS_BOTH := "both"

# --- config ---
@export var server_key := "defaultkey"
@export var host := "127.0.0.1"
@export var port := 7350
@export var use_ssl := false
## The addon defaults to DEBUG, which dumps session tokens and every frame to
## stdout. Raise it with `--net-verbose` when you actually need the wire trace.
@export var log_level := NakamaLogger.LOG_LEVEL.WARNING

var _client: NakamaClient
var _session: NakamaSession
var _socket: NakamaSocket
var _match: NakamaRTAPI.Match

var status := "offline"          ## "offline" | "connecting" | "online" | "error"
var last_error := ""
var world_code := ""             ## the human code this connection joined
var match_id := ""
var claimed_slots: PackedStringArray = []   ## authoritative — the server confirms these
var _claim_confirmed := false
## True when this machine is allowed to pick up the OTHER keeper mid-session —
## couch play, where the second player may not be sitting down yet. Set by boot
## from --couch; it never grants a slot, it only permits the asking.
var couch_dropin := false

## How long to wait for the match to confirm the slot claim after joining.
const CLAIM_TIMEOUT := 5.0

func _ready() -> void:
	_set_status("offline")

func _set_status(s: String) -> void:
	status = s
	EventBus.net_status_changed.emit(s)

func _fail(message: String) -> bool:
	last_error = message
	push_warning("Net: %s" % message)
	_set_status("error")
	EventBus.net_error.emit(message)
	return false

## True while this connection is driving both keepers from one machine.
func is_couch() -> bool:
	return claimed_slots.size() == 2

## The slot a single-slot (online) connection owns, or "" in couch mode.
func primary_slot() -> String:
	return claimed_slots[0] if claimed_slots.size() > 0 else ""

func has_slot(slot: String) -> bool:
	return claimed_slots.has(slot)

## The keeper this machine has NOT claimed yet, or "" if it holds both. Only
## meaningful while couch_dropin is on.
func unclaimed_slot() -> String:
	if not couch_dropin or claimed_slots.size() != 1:
		return ""
	return Command.SLOT_B if claimed_slots[0] == Command.SLOT_A else Command.SLOT_A

## Ask the match for a slot mid-session. The answer arrives as a state diff
## carrying a new `you.slots`, which is what actually changes claimed_slots.
func send_claim(slot: String) -> void:
	if slot == "" or has_slot(slot):
		return
	send_command(Command.claim(slot))

## Authenticate, open the socket, resolve the world code to a match, and claim
## keeper slot(s). `slots` is one of SLOTS_A / SLOTS_B / SLOTS_BOTH.
## Returns true once the match is joined.
func connect_and_join(p_world_code: String, slots: String = SLOTS_A) -> bool:
	if status == "connecting":
		return _fail("already connecting")
	world_code = p_world_code.to_upper().strip_edges()
	last_error = ""
	claimed_slots = []
	_claim_confirmed = false
	_set_status("connecting")

	var scheme := "https" if use_ssl else "http"
	_client = Nakama.create_client(server_key, host, port, scheme, Nakama.DEFAULT_TIMEOUT, log_level)

	_session = await _client.authenticate_device_async(_device_id(slots), _username(slots))
	if _session.is_exception():
		return _fail("auth failed: %s" % _session.get_exception().message)

	_socket = Nakama.create_socket_from(_client)
	var connected: NakamaAsyncResult = await _socket.connect_async(_session)
	if connected.is_exception():
		return _fail("socket failed: %s" % connected.get_exception().message)

	if not _socket.received_match_state.is_connected(_on_match_state):
		_socket.received_match_state.connect(_on_match_state)
		_socket.received_match_presence.connect(_on_presence)
		_socket.closed.connect(_on_socket_closed)

	# The world code is resolved server-side: one code -> exactly one live match.
	var rpc_result: NakamaAPI.ApiRpc = await _socket.rpc_async(
		"join_world", JSON.stringify({"world_code": world_code})
	)
	if rpc_result.is_exception():
		return _fail("join_world failed: %s" % rpc_result.get_exception().message)
	var resolved: Variant = JSON.parse_string(rpc_result.payload)
	if typeof(resolved) != TYPE_DICTIONARY or not (resolved as Dictionary).has("match_id"):
		return _fail("join_world returned no match id")
	match_id = String((resolved as Dictionary)["match_id"])

	# Slots are requested here; the match validates and confirms them back in the
	# join snapshot under "you". We never assume the claim succeeded.
	_match = await _socket.join_match_async(match_id, {"slots": slots})
	if _match.is_exception():
		return _fail("join refused: %s" % _match.get_exception().message)

	# A successful join is not a granted claim. The match confirms slots in the
	# snapshot that follows, on a separate message — returning before it lands
	# leaves callers believing they drive nobody, which silently turns couch mode
	# into two mirrors and nothing to move.
	if not await _await_claim():
		return _fail("the match never confirmed a slot claim")
	if claimed_slots.is_empty():
		return _fail("the match granted no keeper slot")

	_set_status("online")
	return true

func _await_claim() -> bool:
	var deadline := Time.get_ticks_msec() + int(CLAIM_TIMEOUT * 1000.0)
	while not _claim_confirmed and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return _claim_confirmed

func disconnect_from_world() -> void:
	if _socket != null and _socket.is_connected_to_host():
		if _match != null and not _match.is_exception():
			await _socket.leave_match_async(match_id)
		_socket.close()
	claimed_slots = []
	match_id = ""
	_set_status("offline")

## Send an intent to the authoritative match. Build dicts with Command.* helpers.
##   Net.send_command(Command.gather("driftwood_01"))
func send_command(cmd: Dictionary) -> void:
	if status != "online":
		push_warning("send_command while offline; intent dropped: %s" % cmd)
		return
	var op: int = int(cmd.get("op", 0))
	var payload := JSON.stringify(cmd.get("data", {}))
	_socket.send_match_state_async(match_id, op, payload)

## Where a keeper appears to be. Not a command: no validation, no persistence, no
## WorldState. Dropped silently when offline — a lost pose is a stale frame, and
## the next one is 100ms away.
func send_pose(slot: String, pos: Vector2, facing: int, room: String) -> void:
	if status != "online":
		return
	var cmd := Command.pose(slot, pos, facing, room)
	_socket.send_match_state_async(match_id, int(cmd["op"]), JSON.stringify(cmd["data"]))

## Dev-only, and only meaningful on a dev server: asks the world to change how
## long a tide takes. Used by the tuning overlay during playtests.
func request_cycle_seconds(seconds: float) -> void:
	if status != "online":
		return
	var result: NakamaAPI.ApiRpc = await _socket.rpc_async(
		"debug_set_cycle_seconds",
		JSON.stringify({"world_code": world_code, "seconds": seconds}),
	)
	if result.is_exception():
		push_warning("Net: cycle length not accepted (%s)" % result.get_exception().message)

# --- incoming ---

func _on_match_state(state: NakamaRTAPI.MatchData) -> void:
	match state.op_code:
		Command.OP_STATE_DIFF:
			_apply_state_diff(state.data)
		Command.OP_POSE_ECHO:
			_apply_pose_echo(state.data)

## Presentation channel. Straight to EventBus — deliberately NOT through
## WorldState, which mirrors what the world is, not where people look like they
## are standing.
func _apply_pose_echo(raw: String) -> void:
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var poses: Dictionary = (parsed as Dictionary).get("poses", {})
	for slot in poses:
		# A client that drives this slot already knows where it is, and its own
		# echo is ~100ms stale — applying it would drag the keeper backwards.
		if has_slot(slot):
			continue
		var p: Dictionary = poses[slot]
		EventBus.keeper_pose_received.emit(
			String(slot),
			Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0))),
			int(p.get("f", 0)),
			float(p.get("t", 0.0)) / 1000.0,
			String(p.get("r", "")),
		)

## Authoritative state diff arrived. We do NOT trust local prediction here for
## v1 — just apply what the server says. (Add prediction later if needed.)
func _apply_state_diff(raw: String) -> void:
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Net: undecodable state diff")
		return
	var diff: Dictionary = parsed

	# "you" is per-CONNECTION, not shared world state, so it stops here rather
	# than flowing into WorldState (which mirrors the world, not this client).
	if diff.has("you"):
		var you: Dictionary = diff["you"]
		claimed_slots = PackedStringArray(you.get("slots", []))
		_claim_confirmed = true
		EventBus.net_slots_claimed.emit(claimed_slots)
		diff.erase("you")

	WorldState.apply_diff(diff)

func _on_presence(event: NakamaRTAPI.MatchPresenceEvent) -> void:
	# Slot-level presence is authoritative and arrives in the state diff; this is
	# only connection-level churn, useful for reconnect UI and logs.
	for _p in event.joins:
		EventBus.notification.emit("A keeper connected.")
	for _p in event.leaves:
		EventBus.notification.emit("A keeper disconnected.")

func _on_socket_closed() -> void:
	claimed_slots = []
	couch_dropin = false
	_claim_confirmed = false
	if status != "error":
		_set_status("offline")

# --- identity ---

## Two instances on one machine share `user://`, so the addon's stored device id
## is identical for both. Scoping it by the slot(s) this instance drives makes
## each keeper a distinct account that is still stable across restarts — which is
## what lets a killed instance rejoin and be handed its slot back.
func _device_id(slots: String) -> String:
	return "%s-%s" % [Nakama.get_device_id(), slots]

func _username(slots: String) -> String:
	return "keeper-%s-%s" % [slots, Nakama.get_device_id().substr(0, 8)]
