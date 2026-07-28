extends Node
## Debug only — never part of play. Added by boot.gd solely for `--autowalk`.
##
## Synthesises pad input through the REAL input actions rather than poking the
## keeper directly, so what the milestone verifiers exercise is the same path a
## thumbstick takes: action names, device prefixes, accel/decel and all.
##
## The route deliberately does two different things. First it walks both keepers
## together across the whole room, which is what the camera has to follow. Then it
## pulls them apart and back, which is what the zoom-to-fit has to answer.

const DIRS: PackedStringArray = ["move_right", "move_down", "move_left", "move_up"]

## Named routes, each a list of [seconds, keeper_a direction, keeper_b direction].
const ROUTES: Dictionary = {
	# The camera tour: together across the room, then apart and back.
	"tour": [
		[6.0, "move_right", "move_right"],
		[4.0, "move_down", "move_down"],
		[6.0, "move_left", "move_left"],
		[4.0, "move_up", "move_up"],
		[3.0, "move_right", "move_left"],   # separate
		[3.0, "move_left", "move_right"],   # converge
	],
	# Walk keeper_a out onto the sandbar and leave them there to be caught.
	"to_sandbar": [
		[9.0, "move_left", "move_right"],
	],
	# Park keeper_a on driftwood_01 and take it once.
	"gather_once": [
		[6.9, "move_left", ""],
		[1.8, "move_up", ""],
		[0.4, "", ""],
		[0.2, "interact", ""],
		[3.0, "", ""],
	],
	# Walk to the workbench, hold interact to open the wheel, aim north at the
	# first recipe, then release to craft it.
	"craft_at_bench": [
		[1.5, "move_down", ""],
		[0.55, "move_left", ""],
		[0.5, "move_up", ""],
		[0.4, "", ""],
		[0.8, "interact", ""],
		[1.2, "aim_right", ""],
		[3.0, "", ""],
	],
	# Opens the wheel and just holds the aim, so a screenshot can land on it
	# without racing the release.
	"wheel_pose": [
		[1.5, "move_down", ""],
		[0.55, "move_left", ""],
		[0.5, "move_up", ""],
		[0.4, "", ""],
		[0.8, "interact", ""],
		[12.0, "aim_right", ""],
	],
	# The same pose, aimed at something we cannot afford, so the shortfall line
	# can be seen.
	"wheel_pose_short": [
		[1.5, "move_down", ""],
		[0.55, "move_left", ""],
		[0.5, "move_up", ""],
		[0.4, "", ""],
		[0.8, "interact", ""],
		[12.0, "aim_up", ""],
	],
	# Same walk, but aim at a recipe we cannot afford and release on it.
	"craft_unaffordable": [
		[1.5, "move_down", ""],
		[0.55, "move_left", ""],
		[0.5, "move_up", ""],
		[0.4, "", ""],
		[0.8, "interact", ""],
		[1.2, "aim_up", ""],
		[3.0, "", ""],
	],
	# Same, but aim with the d-pad rather than the stick.
	"craft_dpad": [
		[1.5, "move_down", ""],
		[0.55, "move_left", ""],
		[0.5, "move_up", ""],
		[0.4, "", ""],
		[0.8, "interact", ""],
		[1.2, "dpad_right", ""],
		[3.0, "", ""],
	],
	# Same, but mash the button — the world should still only hand it over once.
	"gather_spam": [
		[6.9, "move_left", ""],
		[1.8, "move_up", ""],
		[0.4, "", ""],
		[2.5, "interact_spam", ""],
		[3.0, "", ""],
	],
}

## Actions a route step may hold besides a direction.
const INTERACT := "interact"
const INTERACT_SPAM := "interact_spam"
## Aiming steps hold interact AND a direction at once — the wheel gesture is one
## hand doing two things, so a route step has to be able to say that.
const AIM_PREFIX := "aim_"
## The same gesture with the d-pad button rather than the stick axis, to prove
## the wheel answers both.
const DPAD_PREFIX := "dpad_"

@export var route: String = "tour"

var _elapsed := 0.0
var _finished := false

func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed += delta

	var t := _elapsed
	for step in ROUTES.get(route, ROUTES["tour"]):
		var span: float = step[0]
		if t < span:
			_hold("", String(step[1]), t)
			_hold("p2_", String(step[2]), t)
			return
		t -= span

	_release_all("")
	_release_all("p2_")
	_finished = true
	print("[autowalk] route '%s' complete after %.1fs" % [route, _elapsed])

func _hold(prefix: String, action: String, into_step: float) -> void:
	for dir in DIRS:
		var full := prefix + dir
		if dir == action:
			if not Input.is_action_pressed(full):
				Input.action_press(full)
		elif Input.is_action_pressed(full):
			Input.action_release(full)

	# Aiming: keep interact down and push a direction, which is the actual wheel
	# gesture. The stick form presses the movement action; the d-pad form sends a
	# real joypad button event so the two input paths are tested separately.
	if action.begins_with(AIM_PREFIX) or action.begins_with(DPAD_PREFIX):
		if not Input.is_action_pressed(prefix + "interact"):
			Input.action_press(prefix + "interact")
		var dir := "move_" + action.split("_", true, 1)[1]
		if action.begins_with(DPAD_PREFIX):
			_press_dpad(dir, into_step < 0.1)
		elif not Input.is_action_pressed(prefix + dir):
			Input.action_press(prefix + dir)
		return

	# A single deliberate press: held down, so is_action_just_pressed fires once
	# and only once no matter how long the step lasts.
	if action == INTERACT:
		if not Input.is_action_pressed(prefix + "interact"):
			Input.action_press(prefix + "interact")
	elif action == INTERACT_SPAM:
		# Mashing: released and re-pressed every frame, which is the worst case
		# the server's idempotency has to survive.
		if Input.is_action_pressed(prefix + "interact"):
			Input.action_release(prefix + "interact")
		else:
			Input.action_press(prefix + "interact")
	elif Input.is_action_pressed(prefix + "interact"):
		Input.action_release(prefix + "interact")

## Sends the physical d-pad button rather than poking the action, so what is
## exercised is the binding in the input map and not just our own bookkeeping.
func _press_dpad(dir: String, _first_frame: bool) -> void:
	const BUTTONS := {
		"move_up": JOY_BUTTON_DPAD_UP, "move_down": JOY_BUTTON_DPAD_DOWN,
		"move_left": JOY_BUTTON_DPAD_LEFT, "move_right": JOY_BUTTON_DPAD_RIGHT,
	}
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = BUTTONS[dir]
	ev.pressed = true
	Input.parse_input_event(ev)

func _release_all(prefix: String) -> void:
	for dir in DIRS:
		Input.action_release(prefix + dir)
	Input.action_release(prefix + "interact")
