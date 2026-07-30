extends CharacterBody2D
class_name Keeper
## Keeper — one of the world's two identities, on screen.
##
## The same scene plays both roles. A LOCAL keeper reads a pad and sends its pose
## up at 10Hz; a REMOTE keeper is a mirror, replaying poses that arrive from the
## other connection. Which one it is depends only on whether this client claimed
## the slot — that is the whole couch/online difference on the client, exactly as
## it is on the server.
##
## Nothing here touches shared state. Movement is presentation; anything the
## world is held to goes through Net.send_command().

## Cozy, not twitchy: about a second and a half to cross the short side of the
## screen, and a short slide into and out of motion. The number itself lives in
## Tuning, because how fast this feels is a thing two people decide by playing,
## not a thing anybody decides by reading (CLAUDE.md Testing law).
const ACCEL_TO_TOP := 0.15
const ACCEL := 600.0
const DECEL := 900.0
## Wading home wet. Slow enough to feel like a consequence, fast enough that it
## never becomes a punishment you sit through (DESIGN §1, pillar 1).
const SOAKED_SPEED_SCALE := 0.5
## How long the keeper is faded out while the water carries them home.
const CATCH_FADE := 0.45

## How much of the sky's darkening a keeper resists. The eye must always be able
## to find the human thing by finding the warmth (DESIGN §6) — and that law is
## worth least at noon and most at high tide, which is exactly when a plain
## multiply was making both keepers disappear into the ground.
const AMBIENT_RESISTANCE := 0.6

const POSE_HZ := 10.0
const POSE_INTERVAL := 1.0 / POSE_HZ
## Replay runs this far behind the newest sample, so there is almost always a
## later one to interpolate toward. One packet of slack absorbs ordinary jitter;
## more would just be lag you can see.
const INTERP_DELAY := 0.15
## How hard the playback clock is pulled back onto that delay. Sender and
## receiver clocks drift; correcting gently keeps the mirror from lurching.
const RESYNC_RATE := 2.0
const POSE_BUFFER_MAX := 16

## Sprite frames in the placeholder sheets.
const FRAME_DOWN := 0
const FRAME_SIDE := 1
const FRAME_UP := 2

@export var slot: String = Command.SLOT_A
## Action prefix for this keeper's pad: "" is device 0, "p2_" is device 1.
## Couch play gives keeper_a the first and keeper_b the second; online play always
## uses the first, whichever slot you claimed.
@export var input_prefix: String = ""
@export var is_local: bool = false
## Which placeholder sheet this keeper wears. Set by the world when it spawns.
@export var sheet: Texture2D

## Where the water puts you down again. The yard is safe at every phase the beach
## is not, so it is always somewhere you can stand.
@export var safe_return: NodePath
## Which room this keeper is standing in. Set by the world that spawned them.
@export var room: String = ""

@onready var _sprite: Sprite2D = %Sprite
@onready var _interactor: Interactor = %Interactor
@onready var _prompt: Node2D = %Prompt
@onready var _prompt_label: Label = %Prompt/Label

var facing: int = 6          ## 8-dir index; see _facing_from()
var is_soaked := false
var _ui_blocked := false
var _hold_timer := 0.0
var _hold_fired := false
## Set when a menu closes while interact is still down. The same press that
## dismissed a panel must not also re-open it — the world has not even confirmed
## what the panel did yet.
var _interact_latched := false
var _fade: Tween
var _pose_timer := 0.0
var _last_sent := Vector2.INF

## Remote replay state. Samples are ordered by the SENDER's clock, not arrival:
## arrival times carry the network's jitter, sender times carry the motion.
## Differences within one sender's stream are all that is ever used, so the
## offset between the two machines' clocks cancels and never needs syncing.
var _buffer: Array[Dictionary] = []
var _play_head := 0.0
var _has_pose := false
var _elsewhere := false

func _ready() -> void:
	if sheet != null:
		_sprite.texture = sheet
	if not is_local:
		EventBus.keeper_pose_received.connect(_on_pose_received)
		EventBus.keeper_presence_changed.connect(_on_presence_changed)
	EventBus.keeper_caught.connect(_on_caught)
	EventBus.keeper_released.connect(_on_released)
	_interactor.target_changed.connect(_on_target_changed)
	EventBus.ui_modal_changed.connect(_on_ui_modal_changed)
	EventBus.ambient_changed.connect(_on_ambient_changed)
	_apply_facing()
	_update_visibility()

func _physics_process(delta: float) -> void:
	if is_local:
		_drive(delta)
	else:
		_replay(delta)

## Couch drop-in: this keeper was a mirror waiting for a partner who has now sat
## down at THIS machine. Stop replaying poses, start reading a pad.
##
## Deliberately one-way. A keeper never goes back to being remote, because the
## only thing that could take the slot away is losing it — and losing it drops
## the connection, which rebuilds the world from scratch anyway.
func become_local(prefix: String) -> void:
	if is_local:
		return
	is_local = true
	input_prefix = prefix
	if EventBus.keeper_pose_received.is_connected(_on_pose_received):
		EventBus.keeper_pose_received.disconnect(_on_pose_received)
	if EventBus.keeper_presence_changed.is_connected(_on_presence_changed):
		EventBus.keeper_presence_changed.disconnect(_on_presence_changed)
	# A local keeper is always here; it is the source of poses, not a consumer.
	_buffer.clear()
	_has_pose = true
	_elsewhere = false
	_update_visibility()

# --- local: read the pad, move, publish ---

func _drive(delta: float) -> void:
	var wish := Vector2.ZERO
	if not _ui_blocked:
		wish = Input.get_vector(
			input_prefix + "move_left", input_prefix + "move_right",
			input_prefix + "move_up", input_prefix + "move_down",
		)
	# Direction stays analog so a stick feels like a stick; only FACING is
	# quantised to eight. Snapping movement itself would make diagonals fight the
	# thumbstick for no gain at this speed.
	if wish.length() > 1.0:
		wish = wish.normalized()

	var speed := Tuning.get_value("walk_speed") * (SOAKED_SPEED_SCALE if is_soaked else 1.0)
	var wanted_velocity := wish * speed
	var rate := ACCEL if wish != Vector2.ZERO else DECEL
	velocity = velocity.move_toward(wanted_velocity, rate * delta)
	move_and_slide()

	if wish != Vector2.ZERO:
		var next := _facing_from(wish)
		if next != facing:
			facing = next
			_apply_facing()

	_pose_timer += delta
	if _pose_timer >= POSE_INTERVAL:
		_pose_timer = 0.0
		_publish_pose()

	_read_interact(delta)
	_place_prompt()

## One context-sensitive button. What it does is whatever the prompt says it will
## do, which is whatever the interactor picked from where you are standing and
## which way you are looking. Some things want a tap, some want a hold.
func _read_interact(delta: float) -> void:
	var reachable := _interactor.target
	if _ui_blocked or reachable == null or not reachable.can_interact():
		_hold_timer = 0.0
		_hold_fired = false
		return

	var action := input_prefix + "interact"
	# Wait for a clean release before believing the button again.
	if _interact_latched:
		if Input.is_action_pressed(action):
			return
		_interact_latched = false

	if not reachable.requires_hold():
		if Input.is_action_just_pressed(action):
			reachable.interact(self)
		return

	if Input.is_action_pressed(action):
		if not _hold_fired:
			_hold_timer += delta
			if _hold_timer >= Station.HOLD_SECONDS:
				_hold_fired = true
				reachable.interact(self)
	else:
		_hold_timer = 0.0
		_hold_fired = false

func _publish_pose() -> void:
	# Standing still costs nothing to say once, then nothing at all.
	if position.is_equal_approx(_last_sent):
		return
	_last_sent = position
	Net.send_pose(slot, position, facing, room)

# --- remote: replay what arrived ---

func _on_pose_received(
	p_slot: String, pos: Vector2, p_facing: int, sent_at: float, p_room: String,
) -> void:
	if p_slot != slot:
		return
	# Somewhere else entirely: still present, just not in this room to be drawn.
	if p_room != room:
		if _elsewhere != true:
			_elsewhere = true
			_update_visibility()
		return
	if _elsewhere:
		_elsewhere = false
		_update_visibility()
	# Out-of-order arrivals are stale by definition; the newer sample already
	# says everything they would.
	if not _buffer.is_empty() and sent_at <= float(_buffer[-1]["st"]):
		return
	_buffer.append({"st": sent_at, "pos": pos, "f": p_facing})
	if _buffer.size() > POSE_BUFFER_MAX:
		_buffer.pop_front()

	if not _has_pose:
		# First word of where they actually are. Placing them anywhere before
		# this would be a guess, so the keeper simply is not drawn until now.
		_has_pose = true
		_play_head = sent_at - INTERP_DELAY
		_set_pose(pos, p_facing)
		_update_visibility()

func _replay(delta: float) -> void:
	if not _has_pose or _buffer.is_empty():
		return

	var newest := float(_buffer[-1]["st"])
	_play_head += delta
	# Ease back toward the intended delay rather than snapping to it: a hard
	# correction every time the network breathes is exactly the stutter the
	# buffer exists to prevent.
	var target := newest - INTERP_DELAY
	_play_head = lerpf(_play_head, target, clampf(delta * RESYNC_RATE, 0.0, 1.0))
	# Never run past the newest sample — that would be guessing where they went,
	# and a keeper who slides through a wall and snaps back is worse than one who
	# waits a frame.
	_play_head = minf(_play_head, newest)

	while _buffer.size() >= 2 and float(_buffer[1]["st"]) <= _play_head:
		_buffer.pop_front()

	var from: Dictionary = _buffer[0]
	if _buffer.size() == 1:
		_set_pose(from["pos"], int(from["f"]))
		return

	var to: Dictionary = _buffer[1]
	var span := float(to["st"]) - float(from["st"])
	var alpha := 1.0 if span <= 0.0 else clampf((_play_head - float(from["st"])) / span, 0.0, 1.0)
	_set_pose((from["pos"] as Vector2).lerp(to["pos"] as Vector2, alpha), int(to["f"]))

func _set_pose(pos: Vector2, p_facing: int) -> void:
	position = pos
	if p_facing != facing:
		facing = p_facing
		_apply_facing()

## Partly undoes the ambient on the keeper alone, so they stay lit while the
## world around them goes to dusk. Alpha is left alone: the catch fade owns it.
func _on_ambient_changed(ambient: Color) -> void:
	var lift := Color(
		lerpf(1.0, 1.0 / maxf(ambient.r, 0.05), AMBIENT_RESISTANCE),
		lerpf(1.0, 1.0 / maxf(ambient.g, 0.05), AMBIENT_RESISTANCE),
		lerpf(1.0, 1.0 / maxf(ambient.b, 0.05), AMBIENT_RESISTANCE),
	)
	lift.a = _sprite.modulate.a
	_sprite.modulate = lift

# --- reaching for things ---

func _on_ui_modal_changed(open: bool) -> void:
	_ui_blocked = open
	if not open and Input.is_action_pressed(input_prefix + "interact"):
		_interact_latched = true
	if open:
		_prompt.visible = false
	elif _interactor.target != null:
		_on_target_changed(_interactor.target)

func _on_target_changed(target: Interactable) -> void:
	if target == null:
		_prompt.visible = false
		return
	_prompt_label.text = target.prompt_text()
	_prompt.visible = true
	_place_prompt()

func _place_prompt() -> void:
	var target := _interactor.target
	if target == null or not _prompt.visible:
		return
	# Rebuilt each frame so the glyph follows the pad-or-keyboard the player just
	# used, and pixel-snapped like everything else or the text crawls as you walk.
	_prompt_label.text = target.prompt_text()
	_prompt.global_position = target.prompt_position().round()

# --- caught by the water ---

## The server has confirmed this keeper was caught. BOTH clients play the fade,
## so the moment reads the same on either screen; only the client that drives the
## keeper moves it, because only its poses are believed. The other side sees them
## reappear at the yard because the pose channel says so, not because it guessed.
func _on_caught(p_slot: String, _slow_seconds: float) -> void:
	if p_slot != slot:
		return
	is_soaked = true
	if is_local:
		velocity = Vector2.ZERO
		_last_sent = Vector2.INF   # the teleport must go out, not be deduplicated
	_play_catch_fade()

func _on_released(p_slot: String) -> void:
	if p_slot == slot:
		is_soaked = false

func _play_catch_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_sprite, "modulate:a", 0.0, CATCH_FADE)
	# Nothing is lost here — no inventory, no progress. The keeper is set down in
	# the yard, wet, and that is the whole of it.
	_fade.tween_callback(_return_to_safety)
	_fade.tween_property(_sprite, "modulate:a", 1.0, CATCH_FADE)

func _return_to_safety() -> void:
	if not is_local:
		return
	var marker := get_node_or_null(safe_return) as Node2D
	if marker == null:
		push_warning("keeper %s has nowhere safe to return to" % slot)
		return
	position = marker.global_position
	_publish_pose()

# --- presence ---

func _on_presence_changed(p_slot: String, _present: bool) -> void:
	if p_slot == slot:
		_update_visibility()

## A local keeper is always drawn — this client is the reason it is present. A
## remote one needs both a keeper on the other end and a pose saying where they
## are; either alone would put a keeper on screen who is not really anywhere.
func _update_visibility() -> void:
	visible = is_local or (
		WorldState.presence.get(slot, false) and _has_pose and not _elsewhere
	)

# --- facing ---

## Eight directions, indexed counter-clockwise from east:
##   0 E, 1 NE, 2 N, 3 NW, 4 W, 5 SW, 6 S, 7 SE
func _facing_from(dir: Vector2) -> int:
	var angle := atan2(-dir.y, dir.x)
	return int(round(angle / (TAU / 8.0))) & 7

func _apply_facing() -> void:
	match facing:
		2:
			_sprite.frame = FRAME_UP
			_sprite.flip_h = false
		6:
			_sprite.frame = FRAME_DOWN
			_sprite.flip_h = false
		_:
			# Everything else is a profile; the sheet draws it facing right.
			_sprite.frame = FRAME_SIDE
			_sprite.flip_h = facing in [3, 4, 5]
