extends Interactable
class_name BottlePickup
## A bottle on the sand. Only here when the sea has actually brought it.

@export var bottle_id: String = "bottle_01"

@onready var _art: Node2D = %Art

func _ready() -> void:
	EventBus.bottle_changed.connect(_on_bottle_changed)
	_refresh()

func can_interact() -> bool:
	return WorldState.bottle_state(bottle_id) == "washed_up"

func verb() -> String:
	return "Open the bottle"

func interact(keeper: Keeper) -> void:
	EventBus.bottle_reader_requested.emit(bottle_id, keeper.slot, keeper.input_prefix)

func _on_bottle_changed(p_id: String, _state: String) -> void:
	if p_id == bottle_id:
		_refresh()

func _refresh() -> void:
	var here := can_interact()
	_art.visible = here
	print("%.3f [bottle] %s %s" % [
		Time.get_unix_time_from_system(), bottle_id,
		"on the sand" if here else "not here",
	])
