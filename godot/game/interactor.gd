extends Area2D
class_name Interactor
## The keeper's reach. Picks ONE thing to interact with and shows a prompt for it.
##
## Proximity plus facing, exactly as the controller-first law asks: of everything
## in range, prefer what the keeper is looking at, and among equals prefer what is
## closest. No cursor is involved anywhere, and there is nothing to aim.

## How much being looked at counts for, against being near. High enough that
## turning toward a thing picks it, low enough that facing away from something
## you are standing on top of does not pick something across the beach.
const FACING_WEIGHT := 40.0
## Things more than this far off your facing are behind you; ignore them.
const FACING_CUTOFF := -0.35

signal target_changed(target: Interactable)

var target: Interactable = null

var _keeper: Keeper
var _candidates: Array[Interactable] = []

func _ready() -> void:
	_keeper = get_parent() as Keeper
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

func _physics_process(_delta: float) -> void:
	var best := _choose()
	if best != target:
		target = best
		target_changed.emit(target)

## Only the keeper this client drives gets to reach for things; a mirror of
## someone else's keeper has no business picking targets on their behalf.
func _choose() -> Interactable:
	if _keeper == null or not _keeper.is_local:
		return null
	var facing_dir := _facing_vector()
	var best: Interactable = null
	var best_score := -INF
	for candidate in _candidates:
		if not is_instance_valid(candidate) or not candidate.can_interact():
			continue
		var offset: Vector2 = candidate.global_position - _keeper.global_position
		var distance: float = offset.length()
		if distance > candidate.reach:
			continue
		var alignment: float = 1.0 if distance < 1.0 else facing_dir.dot(offset / distance)
		if alignment < FACING_CUTOFF:
			continue
		var score: float = alignment * FACING_WEIGHT - distance
		if score > best_score:
			best_score = score
			best = candidate
	return best

func _facing_vector() -> Vector2:
	var angle := float(_keeper.facing) * TAU / 8.0
	return Vector2(cos(angle), -sin(angle))

func _on_area_entered(area: Area2D) -> void:
	var it := area as Interactable
	if it != null and not _candidates.has(it):
		_candidates.append(it)

func _on_area_exited(area: Area2D) -> void:
	var it := area as Interactable
	if it != null:
		_candidates.erase(it)
