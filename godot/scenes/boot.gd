extends Node
## Session bootstrap + debug readout.
##
## Owns the connection, then hosts the world under itself once the join lands.
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
##   --scene=beach|room   which space to enter (default beach)
##   --autowalk[=route]   synthesise pad input along a named debug route
##   --debug-gather=a,b   gather these node ids straight away (debug seeding)
##   --ui-selftest        drive the basket with synthesised pad input and report
##   --shot=/abs/path.png grab the 640x360 viewport, then quit
##   --shot-at=SECONDS    when to grab it (default 6)
##
## Every line is also printed to stdout, and the state is echoed on a heartbeat,
## so a headless run is verifiable without a window.

const DEFAULT_WORLD := "TEST01"
const HEARTBEAT_SECONDS := 2.0
## The beach is where the game is; the plain room is kept because M1's movement
## and camera evidence is measured against its geometry.
const SCENES := {
	"beach": "res://scenes/beach.tscn",
	"room": "res://scenes/world.tscn",
}
const DEFAULT_SCENE := "beach"

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
var _shot_at := 6.0
var _autowalk := false
var _autowalk_route := "tour"
var _debug_gather: PackedStringArray = []
var _ui_selftest := false
var _scene := DEFAULT_SCENE
var _world: Node2D = null

func _ready() -> void:
	_parse_flags()
	EventBus.net_status_changed.connect(_on_status_changed)
	EventBus.net_slots_claimed.connect(_on_slots_claimed)
	EventBus.net_error.connect(_on_net_error)
	EventBus.keeper_presence_changed.connect(_on_presence_changed)
	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.node_changed.connect(_on_node_changed)

	_world_label.text = "world:    %s" % _world_code
	_hint_label.text = "requesting: %s" % _slots
	_log("boot: world=%s slots=%s host=%s:%d" % [_world_code, _slots, Net.host, Net.port])
	if _shot_path != "":
		_grab_screenshot.call_deferred()
	await _join()

## Debug affordance: prove the 640x360 viewport actually renders what the labels
## say. Windowed only — headless has no framebuffer.
func _grab_screenshot() -> void:
	await get_tree().create_timer(_shot_at).timeout
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
		elif arg.begins_with("--shot-at="):
			_shot_at = float(arg.split("=", true, 1)[1])
		elif arg == "--autowalk":
			_autowalk = true
		elif arg.begins_with("--autowalk="):
			_autowalk = true
			_autowalk_route = arg.split("=", true, 1)[1]
		elif arg.begins_with("--debug-gather="):
			_debug_gather = arg.split("=", true, 1)[1].split(",")
		elif arg == "--ui-selftest":
			_ui_selftest = true
		elif arg.begins_with("--scene="):
			var wanted := arg.split("=", true, 1)[1]
			if SCENES.has(wanted):
				_scene = wanted
			else:
				push_warning("unknown --scene=%s; using %s" % [wanted, _scene])

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
	if joined:
		_enter_world()

## The world is hosted UNDER boot rather than swapping scenes, so the debug
## readout and its stdout heartbeat survive into play — that heartbeat is how the
## milestone verifiers see what a headless client is doing.
func _enter_world() -> void:
	if _world != null:
		return
	_world = (load(SCENES[_scene]) as PackedScene).instantiate()
	%WorldHost.add_child(_world)
	var menus: GameMenus = preload("res://ui/game_menus.tscn").instantiate()
	add_child(menus)
	menus.debug_toggle_requested.connect(_toggle_debug_readout)
	if _autowalk:
		var walker := preload("res://tools/autowalk.gd").new()
		walker.name = "AutoWalk"
		walker.route = _autowalk_route
		add_child(walker)
		_log("autowalk engaged: route '%s' (debug input synthesis)" % _autowalk_route)
	for node_id in _debug_gather:
		Net.send_command(Command.gather(node_id))
	if not _debug_gather.is_empty():
		_log("debug: gathered %s" % ", ".join(_debug_gather))
	if _ui_selftest:
		_run_ui_selftest(menus)
	_log("world entered: %s (%s)" % [_scene, "couch" if Net.is_couch() else "online"])

## Drives the basket with the REAL actions a pad would send, so what it proves is
## that the grid answers a d-pad rather than that some method could be called.
func _run_ui_selftest(menus: GameMenus) -> void:
	await get_tree().create_timer(2.0).timeout
	_log("uitest: holding menu_radial")
	Input.action_press("menu_radial")
	await get_tree().create_timer(0.5).timeout
	Input.action_release("menu_radial")
	await get_tree().create_timer(0.4).timeout
	_log("uitest: inventory open=%s" % menus.any_open())

	# Focus navigation is EVENT driven, so poking the action state the way the
	# movement autowalk does would prove nothing — these have to travel the same
	# path a real button press does.
	for step in ["ui_right", "ui_right", "ui_left"]:
		_send_action(step)
		await get_tree().create_timer(0.35).timeout
		_log("uitest: pressed %s" % step)

	_log("uitest: cancelling")
	_send_action("cancel")
	await get_tree().create_timer(0.5).timeout
	_log("uitest: inventory open=%s (expected false)" % menus.any_open())

func _send_action(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)

func _toggle_debug_readout() -> void:
	%DebugLayer.visible = not %DebugLayer.visible

func _process(delta: float) -> void:
	# WorldState is a read-only mirror; reading it every frame is the intended use.
	var tide: Dictionary = WorldState.tide
	_tide_label.text = "tide:     %s  t=%.4f  cycle=%d" % [
		tide.get("phase", "?"), float(tide.get("t", 0.0)), int(tide.get("cycle", 0)),
	]
	_heartbeat += delta
	if _heartbeat >= HEARTBEAT_SECONDS:
		_heartbeat = 0.0
		_log("HEARTBEAT status=%s claimed=[%s] %s presence=[a=%s b=%s] caught=%s inv=%s" % [
			Net.status, ", ".join(Net.claimed_slots), _tide_label.text.replace("tide:     ", "tide="),
			WorldState.presence.get("keeper_a", false), WorldState.presence.get("keeper_b", false),
			JSON.stringify(WorldState.caught), JSON.stringify(WorldState.inventory),
		])

## Prompts show the glyph for whatever the player last actually touched, so the
## whole game asks one helper and one place watches the input stream.
func _input(event: InputEvent) -> void:
	ButtonGlyphs.note_event(event)

func _unhandled_input(event: InputEvent) -> void:
	# Controller-first: buttons only, no cursor anywhere in this path.
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
	_hint_label.text = "%s  ·  hold %s for the basket" % [
		ButtonGlyphs.prompt("menu_pause", "menu"), ButtonGlyphs.label_for("menu_radial"),
	]
	_log("claimed slots %s (%s)" % [", ".join(slots), mode])

func _on_inventory_changed(item_id: String, new_count: int) -> void:
	_log("inventory %s=%d" % [item_id, new_count])

func _on_node_changed(node_id: String, ready: bool) -> void:
	_log("node %s %s" % [node_id, "restocked" if ready else "emptied"])

func _on_net_error(message: String) -> void:
	_hint_label.text = "error: %s — press interact to retry" % message
	_log("error: %s" % message)

func _on_presence_changed(keeper_id: String, present: bool) -> void:
	var parts: PackedStringArray = []
	for slot in ["keeper_a", "keeper_b"]:
		parts.append("%s=%s" % [slot, "yes" if WorldState.presence.get(slot, false) else "no"])
	_presence_label.text = "presence: %s" % " ".join(parts)
	_log("presence %s=%s" % [keeper_id, present])

## Wall-clock stamped: the milestone verifiers compare WHEN two clients reacted
## to the same broadcast, which needs a clock both processes share.
func _log(line: String) -> void:
	print("%.3f [boot:%s] %s" % [Time.get_unix_time_from_system(), _slots, line])
