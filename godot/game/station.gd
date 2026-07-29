extends Interactable
class_name Station
## A bench you make things at. Holding interact here opens the wheel.
##
## The station makes no decisions: it names itself, and the wheel it opens sends
## that name along with the recipe so the server can check you were standing at
## the right one.

## Matches the `station` field on RecipeDef and in the server's RECIPES table.
@export var station_id: String = "workbench"
## What this bench is called in the prompt and the wheel's header.
@export var display_name: String = "the bench"

## Held rather than tapped, because the wheel is a gesture: hold, aim, release.
const HOLD_SECONDS := 0.2

func verb() -> String:
	return "Craft at %s" % display_name

func prompt_text() -> String:
	return "[%s] hold — %s" % [ButtonGlyphs.label_for("interact"), verb()]

func requires_hold() -> bool:
	return true

## Opening the wheel is not a Command. Nothing about the shared world changes by
## looking at what you could make; only crafting is an intent.
func interact(keeper: Keeper) -> void:
	EventBus.station_wheel_requested.emit(self, keeper.slot, keeper.input_prefix)
