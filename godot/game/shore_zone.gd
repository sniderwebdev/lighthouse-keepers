extends Area2D
class_name ShoreZone
## A stretch of shore the sea takes back on a schedule.
##
## Zones are concentric from the tower (DESIGN.md §2): LOW opens everything, and
## each step of the tide gives one more zone back to the water. A zone that has
## flooded does two things — it raises a barrier so nobody walks in, and it
## reports any keeper still standing in it.
##
## PHASES here mirrors the authoritative table in match_handler.ts. This copy
## places barriers and decides when to *ask*; the server's copy decides whether
## the answer is yes. A client that got this wrong could report a catch that
## never happened, and the server would refuse it.

## Zone id, matching ZONE_PHASES in match_handler.ts.
@export var zone_id: String = "sandbar"
## Phases in which this zone is walkable.
@export var open_phases: PackedStringArray = ["LOW"]
## Raised when the zone floods; the wall that stops you walking in.
@export var barrier: NodePath
## Water drawn over the zone once it is submerged.
@export var water_overlay: NodePath

var is_open := true

var _barrier: CollisionShape2D
var _water: CanvasItem
var _occupants: Array[Keeper] = []

func _ready() -> void:
	_barrier = get_node_or_null(barrier) as CollisionShape2D
	_water = get_node_or_null(water_overlay) as CanvasItem
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func set_phase(phase: String) -> void:
	var open := open_phases.has(phase)
	if open == is_open:
		return
	is_open = open
	_apply_open()
	if not is_open:
		_flood()

func _apply_open() -> void:
	if _barrier != null:
		# Deferred: a collision shape cannot be toggled from inside the physics
		# callback that is querying it.
		_barrier.set_deferred("disabled", is_open)
	if _water != null:
		_water.visible = not is_open

## The water arrives. Anyone still here reports it — for their own keeper only:
## a client never speaks for the keeper it does not drive.
func _flood() -> void:
	for keeper in _occupants:
		if is_instance_valid(keeper) and keeper.is_local:
			Net.send_command(Command.caught(keeper.slot, zone_id))

func _on_body_entered(body: Node2D) -> void:
	var keeper := body as Keeper
	if keeper != null and not _occupants.has(keeper):
		_occupants.append(keeper)

func _on_body_exited(body: Node2D) -> void:
	var keeper := body as Keeper
	if keeper != null:
		_occupants.erase(keeper)
