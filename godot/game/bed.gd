extends Interactable
class_name Bed
## Turning in for the night. Asks the world to write the evening down.

func verb() -> String:
	return "Turn in for the night"

func interact(keeper: Keeper) -> void:
	Net.send_command(Command.log_session(keeper.slot))
	EventBus.log_book_requested.emit(keeper.slot, keeper.input_prefix)
