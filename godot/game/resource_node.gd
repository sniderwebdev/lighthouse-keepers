extends Interactable
class_name ResourceNode
## Something the sea left on the shore.
##
## The scene says a driftwood pile is HERE. The server says what it gives, how
## much, and when it comes back (NODES in match_handler.ts). This node never
## decides it has been emptied — it waits to be told, like everything else.

## Must match a key in the server's NODES table.
@export var node_id: String = ""
## Which item this looks like. Presentation only: the yield is the server's.
@export var item_id: String = "driftwood"

@onready var _sprite: Sprite2D = %Icon

func _ready() -> void:
	EventBus.node_changed.connect(_on_node_changed)
	if _sprite.texture == null:
		_sprite.texture = ItemRegistry.icon(item_id)
	_refresh()

func can_interact() -> bool:
	return WorldState.node_ready(node_id)

func verb() -> String:
	return "Gather %s" % ItemRegistry.display_name(item_id)

func interact(_keeper: Keeper) -> void:
	# An intent, not a change. The pile stays exactly as it looks until the world
	# confirms it is gone — no local prediction, so the two keepers can never
	# disagree about whether it was taken.
	Net.send_command(Command.gather(node_id))

func _on_node_changed(p_node_id: String, _ready_now: bool) -> void:
	if p_node_id == node_id:
		_refresh()

func _refresh() -> void:
	var here := WorldState.node_ready(node_id)
	_sprite.visible = here
	print("%.3f [node] %s visible=%s" % [Time.get_unix_time_from_system(), node_id, here])
	# Keep the area itself alive so the prompt can still explain why there is
	# nothing to take; can_interact() is what actually gates the button.
	modulate.a = 1.0 if here else 0.0
