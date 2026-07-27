extends Node
## Net — thin wrapper over the Nakama Godot client.
##
## Responsibilities:
##   - authenticate the keeper
##   - join the single shared world match (authoritative)
##   - SEND commands (intents) up to the match
##   - RECEIVE authoritative state diffs and hand them to WorldState
##
## This is a SKELETON. Install the Nakama Godot client addon and fill the TODOs.
##   addon: https://github.com/heroiclabs/nakama-godot  (Nakama.tscn singleton)
##
## Opcodes for *outgoing* commands live in Command (game/command.gd).
## One reserved *incoming* opcode carries the authoritative state diff:
const OP_STATE_DIFF := 100   # server -> client: { changes... }  (mirror in match_handler.ts)

# --- config ---
@export var server_key := "defaultkey"
@export var host := "127.0.0.1"
@export var port := 7350
@export var use_ssl := false
@export var world_match_id := ""   # the shared lighthouse; resolve via matchmaker/RPC

var _client                # NakamaClient
var _session               # NakamaSession
var _socket                # NakamaSocket
var _match                 # NakamaRTAPI.Match
var status := "offline"

func _ready() -> void:
	_set_status("offline")

func _set_status(s: String) -> void:
	status = s
	EventBus.net_status_changed.emit(s)

## Authenticate + open socket + join the shared world match.
func connect_and_join(world_id: String) -> void:
	_set_status("connecting")
	# TODO (Nakama addon):
	#   _client  = Nakama.create_client(server_key, host, port, "http" if not use_ssl else "https")
	#   _session = await _client.authenticate_device_async(_device_id())
	#   _socket  = Nakama.create_socket_from(_client)
	#   await _socket.connect_async(_session)
	#   _socket.received_match_state.connect(_on_match_state)
	#   _socket.received_match_presence.connect(_on_presence)
	#   _match = await _socket.join_match_async(world_id)   # or create via RPC if absent
	#   _set_status("online")
	push_warning("Net.connect_and_join: wire up the Nakama addon here.")

## Send an intent to the authoritative match. Build dicts with Command.* helpers.
##   Net.send_command(Command.gather("driftwood_01"))
func send_command(cmd: Dictionary) -> void:
	if status != "online":
		push_warning("send_command while offline; intent dropped: %s" % cmd)
		return
	var op: int = cmd.get("op", 0)
	var payload := JSON.stringify(cmd.get("data", {}))
	# TODO: _socket.send_match_state_async(_match.match_id, op, payload)

# --- incoming ---

## Authoritative state diff arrived. We do NOT trust local prediction here for
## v1 — just apply what the server says. (Add prediction later if needed.)
func _on_match_state(state) -> void:
	if state.op_code != OP_STATE_DIFF:
		return
	var diff: Dictionary = JSON.parse_string(state.data)
	WorldState.apply_diff(diff)

func _on_presence(presences) -> void:
	# TODO: translate joins/leaves -> EventBus.keeper_presence_changed
	pass

func _device_id() -> String:
	return OS.get_unique_id()
