extends Interactable
class_name Npc
## A neighbour you can walk up to and talk to.
##
## Talking is an intent: whether there is anything new to say is the server's
## call, because the stage is part of the shared world and both keepers advance
## the same crab.

@export var npc_id: String = "hermit_crab"

func verb() -> String:
	var def := StoryRegistry.npc(npc_id)
	return "Talk to %s" % (def.display_name.to_lower() if def != null else npc_id)

func interact(keeper: Keeper) -> void:
	EventBus.dialogue_requested.emit(npc_id, keeper.slot, keeper.input_prefix)
