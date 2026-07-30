extends Node
## Debug only — never part of play. Added by boot.gd solely for `--autowalk`.
##
## Synthesises pad input through the REAL input actions rather than poking the
## keeper directly, so what the milestone verifiers exercise is the same path a
## thumbstick takes: action names, device prefixes, accel/decel and all.
##
## Routes are lists of STEPS. A step is either a place to walk to, named by its
## TestMarker, or a button to work. Movement is never timed (CLAUDE.md Testing
## law): a timed leg encodes the distance between two props, so moving either
## one breaks a test that has nothing to do with what changed — sometimes by
## arriving somewhere else that also happens to work, which passes and teaches
## you nothing.

const DIRS: PackedStringArray = ["move_right", "move_down", "move_left", "move_up"]

## How close counts as arrived. Markers sit ~20px from what they are for, so this
## has to be tight enough that ARRIVE_RADIUS + that offset stays inside
## Interactable.reach (34) — otherwise a keeper can "arrive" out of reach and the
## step after it fails for no visible reason.
const ARRIVE_RADIUS := 8.0
## Steps give up rather than hang forever. A marker you cannot reach is a real
## failure and should surface as one.
const WALK_TIMEOUT := 16.0
## A panel that never closes is a real failure; give up and let the verifier's
## own assertion be the one that reports it.
const READ_TIMEOUT := 12.0
## Long enough for is_action_just_pressed, short enough not to read as a hold.
const TAP_TIME := 0.25
## Stations want a hold rather than a tap.
const HOLD_TIME := 0.8

# Step kinds.
const GO := "go"            # [GO, marker_id]                 walk keeper A there
const GO_BOTH := "go_both"  # [GO_BOTH, a_marker, b_marker]   walk both (couch)
const TAP := "tap"          # [TAP]                           press interact once
const TAP_BOTH := "tap_both"
const AIM := "aim"          # [AIM, "up", seconds?]           hold interact AND a direction
const DPAD := "dpad"        # [DPAD, "right"]                 the same via a real d-pad button
const MASH := "mash"        # [MASH, seconds?]                press/release every frame
const UI := "ui"            # [UI, "ui_down"]                 send a UI action as an event
const WAIT := "wait"        # [WAIT, seconds]                 the only timed step there is
const HOLD_DIR := "hold_dir"  # [HOLD_DIR, a_dir, b_dir, seconds]
## [READ] — tap until the open panel closes itself.
##
## Letters and dialogue are as long as the author wrote them. A fixed number of
## taps, or a timed wait, would encode the length of the prose into the test:
## write one more paragraph and an unrelated assertion starts failing. Same
## reasoning as the no-timed-legs law, applied to text.
const READ := "read"

const ROUTES: Dictionary = {
	# The camera tour. Distances here ARE the subject — this route measures
	# framing, not interaction — so it is the one place held directions are the
	# honest expression.
	"tour": [
		[HOLD_DIR, "move_right", "move_right", 6.0],
		[HOLD_DIR, "move_down", "move_down", 4.0],
		[HOLD_DIR, "move_left", "move_left", 6.0],
		[HOLD_DIR, "move_up", "move_up", 4.0],
		[HOLD_DIR, "move_right", "move_left", 3.6],
		# Stand apart for a beat: the camera eases rather than snapping, so a
		# separation held for an instant never reaches its widest framing.
		[WAIT, 1.4],
		[HOLD_DIR, "move_left", "move_right", 3.6],
	],
	"to_sandbar": [[GO, "sandbar_stand"], [WAIT, 8.0]],
	"gather_once": [[GO, "driftwood_01"], [TAP], [WAIT, 3.0]],
	"gather_spam": [[GO, "driftwood_01"], [MASH, 2.5], [WAIT, 3.0]],
	"craft_at_bench": [[GO, "workbench"], [AIM, "right"], [WAIT, 3.0]],
	"craft_unaffordable": [[GO, "workbench"], [AIM, "up"], [WAIT, 3.0]],
	"craft_dpad": [[GO, "workbench"], [DPAD, "right"], [WAIT, 3.0]],
	"wheel_pose": [[GO, "workbench"], [AIM, "right", 12.0]],
	"wheel_pose_short": [[GO, "workbench"], [AIM, "up", 12.0]],
	"wheel_stove": [[GO, "stove"], [AIM, "up", 10.0]],
	"read_bottle": [[GO, "bottle_01"], [TAP], [WAIT, 0.8], [READ], [WAIT, 4.0]],
	"read_bottle_pose": [[GO, "bottle_01"], [TAP], [WAIT, 12.0]],
	"talk_crab": [[GO, "hermit_crab"], [TAP], [WAIT, 1.2], [READ], [WAIT, 3.0]],
	# Fetch what he asks for, then hand it over. Each TALK advances one stage, so
	# the ask and the delivery are two conversations, not one.
	"crab_stone": [
		[GO, "smooth_stone_01"], [TAP], [WAIT, 1.5],
		[GO, "hermit_crab"],
		[TAP], [WAIT, 1.2], [READ], [WAIT, 1.5],
		[TAP], [WAIT, 1.2], [READ], [WAIT, 2.5],
	],
	"crab_fish": [
		[GO, "fish_stub_01"], [TAP], [WAIT, 1.5],
		[GO, "hermit_crab"],
		[TAP], [WAIT, 1.2], [READ], [WAIT, 1.5],
		[TAP], [WAIT, 1.2], [READ], [WAIT, 2.5],
	],
	"seal_step": [[GO, "milestone_board"], [TAP], [WAIT, 0.7], [TAP], [WAIT, 3.0]],
	"seal_locked": [
		[GO, "milestone_board"], [TAP], [WAIT, 0.7],
		[UI, "ui_down"], [UI, "ui_down"], [WAIT, 0.4], [TAP], [WAIT, 3.0],
	],
	"turn_in": [[GO, "bed"], [TAP], [WAIT, 5.0]],
	"turn_in_b": [[GO, "bed"], [TAP], [WAIT, 5.0]],
	"to_tower": [[GO, "tower_door"], [TAP], [WAIT, 6.0]],
	"to_hearth": [[GO, "hearth"], [WAIT, 12.0]],
	"crank_a": [[GO, "crank"], [TAP], [WAIT, 12.0]],
	"crank_b": [[GO, "crank"], [TAP], [WAIT, 12.0]],
	"crank_alone": [[GO, "crank"], [TAP], [WAIT, 14.0]],
	"crank_couch": [[GO_BOTH, "crank", "crank_b"], [TAP_BOTH], [WAIT, 12.0]],
}

@export var route: String = "tour"

var _steps: Array = []
var _index := 0
var _elapsed := 0.0
var _step_time := 0.0
var _finished := false
## Whether a panel (reader, dialogue, board) currently owns the screen. READ
## steps page until this goes false.
var _modal_open := false

func _ready() -> void:
	_steps = ROUTES.get(route, ROUTES["tour"])
	EventBus.ui_modal_changed.connect(func(open: bool) -> void: _modal_open = open)

func _process(delta: float) -> void:
	if _finished:
		return
	if _index >= _steps.size():
		_release_all("")
		_release_all("p2_")
		_finished = true
		print("[autowalk] route '%s' complete after %.1fs" % [route, _elapsed])
		return

	_elapsed += delta
	_step_time += delta
	if _run_step(_steps[_index], delta):
		print("[autowalk] step %d %s done in %.1fs" % [
			_index, String(_steps[_index][0]), _step_time,
		])
		_release_all("")
		_release_all("p2_")
		_index += 1
		_step_time = 0.0

## Returns true when the step is finished.
func _run_step(step: Array, delta: float) -> bool:
	match String(step[0]):
		GO:
			return _walk_to("", String(step[1]))
		GO_BOTH:
			# Both, and neither is done until both are: the gate needs two
			# keepers standing at it, not one waiting while the other walks.
			var a := _walk_to("", String(step[1]))
			var b := _walk_to("p2_", String(step[2]))
			return a and b
		TAP:
			_press("", true)
			return _step_time >= TAP_TIME
		TAP_BOTH:
			_press("", true)
			_press("p2_", true)
			return _step_time >= TAP_TIME
		AIM:
			# Hold interact AND push a direction: the wheel gesture is one hand
			# doing two things, so a step has to be able to say that.
			_press("", true)
			_hold_dir("", "move_" + String(step[1]))
			return _step_time >= (float(step[2]) if step.size() > 2 else HOLD_TIME + 1.2)
		DPAD:
			_press("", true)
			_send_dpad("move_" + String(step[1]))
			return _step_time >= HOLD_TIME + 1.2
		MASH:
			_press("", not Input.is_action_pressed("interact"))
			return _step_time >= (float(step[1]) if step.size() > 1 else 2.5)
		UI:
			if _step_time <= delta:
				_send_action(String(step[1]), true)
				_send_action(String(step[1]), false)
			return _step_time >= 0.25
		READ:
			if not _modal_open or _step_time >= READ_TIMEOUT:
				_press("", false)
				return true
			# Tap on a cadence: press, release, press. A held button is not a
			# page turn.
			_press("", fmod(_step_time, TAP_TIME * 2.0) < TAP_TIME)
			return false
		WAIT:
			return _step_time >= float(step[1])
		HOLD_DIR:
			_hold_dir("", String(step[1]))
			_hold_dir("p2_", String(step[2]))
			return _step_time >= float(step[3])
	push_warning("autowalk: unknown step %s" % step[0])
	return true

# --- walking to a place ---

## Steers the keeper toward a named marker and reports arrival. Facing is part of
## arriving: the interactor picks by facing as well as distance, so a keeper who
## walked past something has not arrived at it.
func _walk_to(prefix: String, marker_id: String) -> bool:
	var keeper := _keeper_for(prefix)
	var marker := _marker(marker_id)
	if keeper == null or marker == null:
		if _step_time > 1.5:
			push_warning("autowalk: no local keeper, or no marker '%s'" % marker_id)
			return true
		return false
	if _step_time >= WALK_TIMEOUT:
		push_warning("autowalk: could not reach '%s' within %ds" % [marker_id, WALK_TIMEOUT])
		return true

	var to := marker.global_position - keeper.global_position
	if to.length() > ARRIVE_RADIUS:
		_steer(prefix, to)
		return false
	# Arrived. Turn to whatever the marker says to face, so the thing we came for
	# is actually selectable.
	if marker.face == Vector2.ZERO or keeper.facing == _dir_index(marker.face):
		return true
	_hold_dir(prefix, _dir_action(marker.face))
	return false

## Moves on whichever axis is furthest out, one at a time: the keeper walks like
## somebody told "over there" rather than on a diagonal that grazes props.
func _steer(prefix: String, to: Vector2) -> void:
	if absf(to.x) > absf(to.y):
		_hold_dir(prefix, "move_right" if to.x > 0.0 else "move_left")
	else:
		_hold_dir(prefix, "move_down" if to.y > 0.0 else "move_up")

func _dir_action(face: Vector2) -> String:
	if absf(face.x) > absf(face.y):
		return "move_right" if face.x > 0.0 else "move_left"
	return "move_down" if face.y > 0.0 else "move_up"

func _dir_index(face: Vector2) -> int:
	return int(round(atan2(-face.y, face.x) / (TAU / 8.0))) & 7

func _keeper_for(prefix: String) -> Keeper:
	var world := _world()
	if world == null:
		return null
	# On the couch the second pad drives keeper_b. Online there is one local
	# keeper and it answers the first column whichever slot it claimed.
	var slot := Command.SLOT_A
	if prefix == "p2_":
		slot = Command.SLOT_B
	elif not Net.is_couch() and not Net.claimed_slots.is_empty():
		slot = Net.claimed_slots[0]
	var keeper: Keeper = world.keeper_for(slot)
	return keeper if keeper != null and keeper.is_local else null

func _world() -> PlayableWorld:
	var host := get_tree().root.find_child("WorldHost", true, false)
	if host == null:
		return null
	for child in host.get_children():
		if child is PlayableWorld:
			return child
	return null

func _marker(marker_id: String) -> TestMarker:
	var world := _world()
	if world == null:
		return null
	for node in world.find_children("*", "TestMarker", true, false):
		var marker := node as TestMarker
		if marker != null and marker.marker_id == marker_id:
			return marker
	return null

# --- input ---

func _hold_dir(prefix: String, action: String) -> void:
	for dir in DIRS:
		var full := prefix + dir
		if dir == action:
			if not Input.is_action_pressed(full):
				Input.action_press(full)
		elif Input.is_action_pressed(full):
			Input.action_release(full)

## Sent as an EVENT rather than by poking action state. Both reach code that
## polls Input, but only an event reaches code that listens for one — and menus
## listen. Poking the state alone opens a panel and then cannot press anything on
## it.
func _press(prefix: String, down: bool) -> void:
	var action := prefix + "interact"
	if Input.is_action_pressed(action) != down:
		_send_action(action, down)

func _send_action(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)

## The physical d-pad button rather than the action, so what is exercised is the
## binding in the input map and not just our own bookkeeping.
func _send_dpad(dir: String) -> void:
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
	if Input.is_action_pressed(prefix + "interact"):
		_send_action(prefix + "interact", false)
