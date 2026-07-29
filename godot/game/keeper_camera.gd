extends Camera2D
class_name KeeperCamera
## The camera both play modes share.
##
## Online it simply follows the keeper you drive. Couch it has to hold two people
## on one screen, so it sits at their midpoint and backs off as they separate —
## which is the only place the two modes genuinely differ on screen.
##
## Position is rounded to whole pixels every frame (CLAUDE.md rendering law).
## NOTE: zoom is not, and cannot be: PLAN.md M1 asks for continuous zoom-to-fit
## between 1.0x and 1.5x, and no value in that range maps texture pixels onto
## whole screen pixels. Framing was chosen over crispness here; restricting to
## integer zoom steps would trade it back.

const MIN_ZOOM := 1.0
const MAX_ZOOM := 1.5
## Keep keepers off the very edge of the frame when fitting them.
const FIT_MARGIN := Vector2(64, 48)
## How hard the camera chases. Lives in Tuning: whether this reads as "the camera
## is with us" or "the camera is dragging us" is a feel question.
const ZOOM_SMOOTH := 3.0

var targets: Array[Node2D] = []

var _zoom_level := MAX_ZOOM
var _focus := Vector2.ZERO
var _initialised := false

func _ready() -> void:
	position_smoothing_enabled = false   # we smooth ourselves, then snap to pixels

func set_targets(p_targets: Array[Node2D]) -> void:
	targets = p_targets
	_initialised = false
	# Frame them NOW rather than on the first _process. Physics runs before idle,
	# so waiting leaves one frame drawn from the camera's default position — a
	# visible flash of the wrong part of the room on the very first frame.
	_track(0.0)

func _process(delta: float) -> void:
	_track(delta)

func _track(delta: float) -> void:
	var live: Array[Node2D] = []
	for t in targets:
		if is_instance_valid(t):
			live.append(t)
	if live.is_empty():
		return

	var desired_focus := _midpoint(live)
	var desired_zoom := _fit_zoom(live)

	if not _initialised:
		# Don't sweep in from wherever the camera happened to start.
		_focus = desired_focus
		_zoom_level = desired_zoom
		_initialised = true
	else:
		var follow: float = Tuning.get_value("camera_smoothing")
		_focus = _focus.lerp(desired_focus, clampf(delta * follow, 0.0, 1.0))
		_zoom_level = lerpf(_zoom_level, desired_zoom, clampf(delta * ZOOM_SMOOTH, 0.0, 1.0))

	zoom = Vector2(_zoom_level, _zoom_level)
	global_position = _focus.round()

func _midpoint(live: Array[Node2D]) -> Vector2:
	var sum := Vector2.ZERO
	for t in live:
		sum += t.global_position
	return sum / float(live.size())

## One keeper: sit at the closest, cosiest zoom. Two: back off only as far as
## needed to keep both in frame, and never past 1.0x — below that we would be
## showing more world than the game is drawn for.
func _fit_zoom(live: Array[Node2D]) -> float:
	if live.size() < 2:
		return MAX_ZOOM
	var box := Rect2(live[0].global_position, Vector2.ZERO)
	for i in range(1, live.size()):
		box = box.expand(live[i].global_position)
	box = box.grow_individual(FIT_MARGIN.x, FIT_MARGIN.y, FIT_MARGIN.x, FIT_MARGIN.y)

	var view := get_viewport_rect().size
	var fit := minf(view.x / maxf(box.size.x, 1.0), view.y / maxf(box.size.y, 1.0))
	return clampf(fit, MIN_ZOOM, MAX_ZOOM)

## Fence the camera to the room so it never shows the void beyond the walls.
func apply_room_bounds(room: Rect2) -> void:
	limit_left = int(room.position.x)
	limit_top = int(room.position.y)
	limit_right = int(room.end.x)
	limit_bottom = int(room.end.y)
