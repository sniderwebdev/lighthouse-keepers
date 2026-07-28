extends Interactable
class_name MilestonePost
## The board on the tower wall. Reading it is not an act the world is held to;
## funding a step from it is, and that goes through ADVANCE_STEP like everything
## else.

func verb() -> String:
	return "Read the board"

func interact(keeper: Keeper) -> void:
	EventBus.milestone_board_requested.emit(keeper.slot, keeper.input_prefix)
