extends Node2D
class_name VisualState
## A piece of the tower that only looks finished once the world says it is.
##
## Restoration is visible or it is nothing (DESIGN §4): each milestone swaps a
## layer in. Which layer is showing is read straight from the authoritative
## flags — never from "I just pressed the button" — so both keepers watch the
## hearth catch at the same moment.

## Shown while the flag is false. The tower before.
@export var before: NodePath
## Shown once the flag is true. The tower after.
@export var after: NodePath
## The flag that decides. Set by the milestone that seals this step.
@export var flag: String = ""

func _ready() -> void:
	EventBus.flag_changed.connect(_on_flag_changed)
	_apply()

func _on_flag_changed(changed: String, _value: bool) -> void:
	if changed == flag:
		_apply()

func _apply() -> void:
	var done := WorldState.has_flag(flag)
	var b := get_node_or_null(before)
	var a := get_node_or_null(after)
	if b != null:
		(b as CanvasItem).visible = not done
	if a != null:
		(a as CanvasItem).visible = done
	print("%.3f [visual] %s -> %s" % [
		Time.get_unix_time_from_system(), flag, "after" if done else "before",
	])
