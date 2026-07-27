extends Node
## Net — thin wrapper over the Nakama Godot client.
##
## Responsibilities:
##   - authenticate the keeper
##   - join the single shared world match (authoritative)
##   - SEND commands (intents) up to the match
##   - RECEIVE authoritative state diffs and hand them to WorldState
##
## Opcodes for *outgoing* commands live in Command (game/command.gd).
## One reserved *incoming* opcode carries the authoritative state diff:
const OP_STATE_DIFF := 100   # server -> client: { changes... }  (mirror in match_handler.ts)

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

## Authenticate, open the socket, resolve the world code to a match, and claim
## keeper slot(s). `slots` is one of SLOTS_A / SLOTS_B / SLOTS_BOTH.
## Returns true once the match is joined.
func connect_and_join(p_world_code: String, slots: String = SLOTS_A) -> bool:
	if status == "connecting":
		return _fail("already connecting")
	world_code = p_world_code.to_upper().strip_edges()
	last_error = ""
	claimed_slots = []
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

	_set_status("online")
	return true

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

# --- incoming ---

## Authoritative state diff arrived. We do NOT trust local prediction here for
## v1 — just apply what the server says. (Add prediction later if needed.)
func _on_match_state(state: NakamaRTAPI.MatchData) -> void:
	if state.op_code != OP_STATE_DIFF:
		return
	var parsed: Variant = JSON.parse_string(state.data)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Net: undecodable state diff")
		return
	var diff: Dictionary = parsed

	# "you" is per-CONNECTION, not shared world state, so it stops here rather
	# than flowing into WorldState (which mirrors the world, not this client).
	if diff.has("you"):
		var you: Dictionary = diff["you"]
		claimed_slots = PackedStringArray(you.get("slots", []))
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
