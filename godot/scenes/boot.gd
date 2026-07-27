extends Control
## M0 debug scene — the whole pipe, made visible.
##
## Shows connection status, the keeper slot(s) this connection claimed, and the
## authoritative tide. Everything here is read-only observation of WorldState;
## the only thing this scene sends is the initial join.
##
## Launch flags (either directly or after a `--` separator):
##   --couch              claim BOTH keeper slots (one machine, two pads)
##   --slot=keeper_b      claim a specific slot (default keeper_a)
##   --world=TEST01       world code to join (default TEST01)
##   --host=127.0.0.1 --port=7350
##   --net-verbose        dump the Nakama wire trace (noisy)
##   --shot=/abs/path.png grab the 640x360 viewport after a few seconds, then quit
##
## Every line is also printed to stdout, and the state is echoed on a heartbeat,
## so a headless run is verifiable without a window.

const DEFAULT_WORLD := "TEST01"
const HEARTBEAT_SECONDS := 2.0

@onready var _status_label: Label = %StatusLabel
@onready var _slots_label: Label = %SlotsLabel
@onready var _world_label: Label = %WorldLabel
@onready var _tide_label: Label = %TideLabel
@onready var _presence_label: Label = %PresenceLabel
@onready var _hint_label: Label = %HintLabel

var _world_code := DEFAULT_WORLD
var _slots := Net.SLOTS_A
var _connecting := false
var _heartbeat := 0.0
var _shot_path := ""

func _ready() -> void:
	_parse_flags()
	EventBus.net_status_changed.connect(_on_status_changed)
	EventBus.net_slots_claimed.connect(_on_slots_claimed)
	EventBus.net_error.connect(_on_net_error)
	EventBus.keeper_presence_changed.connect(_on_presence_changed)

	_world_label.text = "world:    %s" % _world_code
	_hint_label.text = "requesting: %s" % _slots
	_log("boot: world=%s slots=%s host=%s:%d" % [_world_code, _slots, Net.host, Net.port])
	if _shot_path != "":
		_grab_screenshot.call_deferred()
	await _join()

## Debug affordance: prove the 640x360 viewport actually renders what the labels
## say. Windowed only — headless has no framebuffer.
func _grab_screenshot() -> void:
	await get_tree().create_timer(6.0).timeout
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_shot_path)
	_log("screenshot %s -> %s (%dx%d)" % [
		"ok" if err == OK else "FAILED", _shot_path, image.get_width(), image.get_height(),
	])
	get_tree().quit(0 if err == OK else 1)

func _parse_flags() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for arg in args:
		if arg == "--couch":
			_slots = Net.SLOTS_BOTH
		elif arg.begins_with("--slot="):
			_slots = _normalize_slot(arg.split("=", true, 1)[1])
		elif arg.begins_with("--world="):
			_world_code = arg.split("=", true, 1)[1].to_upper()
		elif arg.begins_with("--host="):
			Net.host = arg.split("=", true, 1)[1]
		elif arg.begins_with("--port="):
			Net.port = int(arg.split("=", true, 1)[1])
		elif arg == "--net-verbose":
			Net.log_level = NakamaLogger.LOG_LEVEL.DEBUG
		elif arg.begins_with("--shot="):
			_shot_path = arg.split("=", true, 1)[1]

func _normalize_slot(raw: String) -> String:
	match raw.to_lower():
		"b", "keeper_b":
			return Net.SLOTS_B
		"both", "couch":
			return Net.SLOTS_BOTH
		_:
			return Net.SLOTS_A

func _join() -> void:
	if _connecting:
		return
	_connecting = true
	var joined: bool = await Net.connect_and_join(_world_code, _slots)
	_connecting = false
	_log("join %s" % ("ok" if joined else "FAILED: " + Net.last_error))

func _process(delta: float) -> void:
	# WorldState is a read-only mirror; reading it every frame is the intended use.
	var tide: Dictionary = WorldState.tide
	_tide_label.text = "tide:     %s  t=%.4f  cycle=%d" % [
		tide.get("phase", "?"), float(tide.get("t", 0.0)), int(tide.get("cycle", 0)),
	]
	_heartbeat += delta
	if _heartbeat >= HEARTBEAT_SECONDS:
		_heartbeat = 0.0
		_log("HEARTBEAT status=%s claimed=[%s] %s presence=[a=%s b=%s]" % [
			Net.status, ", ".join(Net.claimed_slots), _tide_label.text.replace("tide:     ", "tide="),
			WorldState.presence.get("keeper_a", false), WorldState.presence.get("keeper_b", false),
		])

func _unhandled_input(event: InputEvent) -> void:
	# Controller-first: one button, no cursor. Retry a failed/dropped connection.
	if event.is_action_pressed("interact") or event.is_action_pressed("p2_interact"):
		if Net.status == "offline" or Net.status == "error":
			_log("retry requested")
			await _join()

# --- signal handlers ---

func _on_status_changed(status: String) -> void:
	_status_label.text = "status:   %s" % status
	_log("status -> %s" % status)

func _on_slots_claimed(slots: PackedStringArray) -> void:
	var mode := "couch (both pads)" if slots.size() == 2 else "online"
	_slots_label.text = "claimed:  %s  [%s]" % [", ".join(slots), mode]
	_hint_label.text = "press interact to rejoin if dropped"
	_log("claimed slots %s (%s)" % [", ".join(slots), mode])

func _on_net_error(message: String) -> void:
	_hint_label.text = "error: %s — press interact to retry" % message
	_log("error: %s" % message)

func _on_presence_changed(keeper_id: String, present: bool) -> void:
	var parts: PackedStringArray = []
	for slot in ["keeper_a", "keeper_b"]:
		parts.append("%s=%s" % [slot, "yes" if WorldState.presence.get(slot, false) else "no"])
	_presence_label.text = "presence: %s" % " ".join(parts)
	_log("presence %s=%s" % [keeper_id, present])

func _log(line: String) -> void:
	print("[boot:%s] %s" % [_slots, line])
