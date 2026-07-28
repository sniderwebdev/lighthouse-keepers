extends Area2D
class_name Interactable
## Something a keeper can walk up to and press one button at.
##
## No cursors and no click targets (CLAUDE.md): the target is chosen by where you
## are and which way you are looking, and a prompt tells you what the button will
## do before you press it.
##
## Subclasses decide what the verb is and what pressing it sends. This base only
## answers "can I be used right now" and "what should the prompt say".

## How far away the keeper can still reach this.
@export var reach := 34.0
## Where the prompt floats, relative to this node.
@export var prompt_offset := Vector2(0, -22)

func can_interact() -> bool:
	return true

## Shown above the object when it is the chosen target.
func prompt_text() -> String:
	return ButtonGlyphs.prompt("interact", verb())

func verb() -> String:
	return "Use"

## Do the thing. Whatever this is, it is an INTENT: it sends a Command and waits
## for the world to confirm. Nothing here may touch shared state directly.
func interact(_keeper: Keeper) -> void:
	pass

## True when this wants the button held rather than tapped. A wheel is a gesture
## — hold, aim, release — so it cannot share a tap with "pick up the driftwood".
func requires_hold() -> bool:
	return false

func prompt_position() -> Vector2:
	return global_position + prompt_offset
