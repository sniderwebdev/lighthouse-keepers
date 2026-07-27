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

func _release_all(prefix: String) -> void:
	for dir in DIRS:
		Input.action_release(prefix + dir)
	Input.action_release(prefix + "interact")
