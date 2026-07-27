extends SceneTree
## Dev tool: regenerates the [input] section of project.godot in Godot's own
## serialization format. The hand-written dictionary form does NOT parse (actions
## register with zero events), so bindings are authored here and saved by the
## engine. Run: godot --headless --path godot --script tools/gen_inputmap.gd

const JOY_A := JOY_BUTTON_A
const JOY_B := JOY_BUTTON_B
const JOY_X := JOY_BUTTON_X
const JOY_Y := JOY_BUTTON_Y
const JOY_BACK := JOY_BUTTON_BACK

func _init() -> void:
	# device 0 = the slot picked at session start, device 1 = the other keeper.
	_build_for_device(0, "")
	_build_for_device(1, "p2_")
	_add_keyboard_adaptation()
	var err := ProjectSettings.save()
	print("ProjectSettings.save() -> %d" % err)
	quit(err)

func _build_for_device(device: int, prefix: String) -> void:
	_axis(prefix + "move_left", device, JOY_AXIS_LEFT_X, -1.0)
	_axis(prefix + "move_right", device, JOY_AXIS_LEFT_X, 1.0)
	_axis(prefix + "move_up", device, JOY_AXIS_LEFT_Y, -1.0)
	_axis(prefix + "move_down", device, JOY_AXIS_LEFT_Y, 1.0)
	# D-pad must be equal to the stick (controller-first law).
	_button(prefix + "move_left", device, JOY_BUTTON_DPAD_LEFT)
	_button(prefix + "move_right", device, JOY_BUTTON_DPAD_RIGHT)
	_button(prefix + "move_up", device, JOY_BUTTON_DPAD_UP)
	_button(prefix + "move_down", device, JOY_BUTTON_DPAD_DOWN)

	_button(prefix + "interact", device, JOY_A)
	_button(prefix + "cancel", device, JOY_B)
	_button(prefix + "use_tool", device, JOY_X)
	_button(prefix + "menu_radial", device, JOY_Y)
	_button(prefix + "menu_pause", device, JOY_BACK)

func _add_keyboard_adaptation() -> void:
	# Keyboard is the adaptation, never the design target. Player 1 only.
	_key("move_left", KEY_A)
	_key("move_right", KEY_D)
	_key("move_up", KEY_W)
	_key("move_down", KEY_S)
	_key("interact", KEY_E)
	_key("cancel", KEY_ESCAPE)
	_key("use_tool", KEY_Q)
	_key("menu_radial", KEY_TAB)
	_key("menu_pause", KEY_F1)

# --- setting plumbing ---

var _fresh: Dictionary = {}

func _slot(action: String) -> Dictionary:
	# First touch of an action in this run wipes whatever was there — the old
	# dictionary-form events are unparsed junk we must not append to.
	if not _fresh.has(action):
		_fresh[action] = {"deadzone": 0.3, "events": []}
	return _fresh[action]

func _store(action: String, cfg: Dictionary) -> void:
	ProjectSettings.set_setting("input/" + action, cfg)
	# Keep the actions out of the "engine default" bucket so they persist.
	ProjectSettings.set_initial_value("input/" + action, {"deadzone": 0.3, "events": []})

func _axis(action: String, device: int, axis: int, value: float) -> void:
	var cfg := _slot(action)
	var ev := InputEventJoypadMotion.new()
	ev.device = device
	ev.axis = axis
	ev.axis_value = value
	cfg["events"].append(ev)
	_store(action, cfg)

func _button(action: String, device: int, index: int) -> void:
	var cfg := _slot(action)
	var ev := InputEventJoypadButton.new()
	ev.device = device
	ev.button_index = index
	cfg["events"].append(ev)
	_store(action, cfg)

func _key(action: String, keycode: int) -> void:
	var cfg := _slot(action)
	var ev := InputEventKey.new()
	ev.device = -1
	ev.keycode = keycode
	ev.physical_keycode = 0
	cfg["events"].append(ev)
	_store(action, cfg)
