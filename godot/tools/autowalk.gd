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
}

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
			_hold("", String(step[1]))
			_hold("p2_", String(step[2]))
			return
		t -= span

	_release_all("")
	_release_all("p2_")
	_finished = true
	print("[autowalk] route '%s' complete after %.1fs" % [route, _elapsed])

func _hold(prefix: String, action: String) -> void:
	for dir in DIRS:
		var full := prefix + dir
		if dir == action:
			if not Input.is_action_pressed(full):
				Input.action_press(full)
		elif Input.is_action_pressed(full):
			Input.action_release(full)

func _release_all(prefix: String) -> void:
	for dir in DIRS:
		Input.action_release(prefix + dir)
