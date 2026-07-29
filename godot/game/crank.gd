extends Interactable
class_name Crank
## The lamp crank. The one thing in Act One that neither of you can do alone.
##
## Reaching for it is an intent like any other; the gate is the server's, and it
## fires only when BOTH slots have reached within the window — whether that is
## two connections or one couch with two pads (CLAUDE.md keeper-slot law).

@export var gate_id: String = "relight_lamp"
## Nothing happens here until the world is ready for it.
@export var requires_flag: String = "lamp_ready"
@export var done_flag: String = "lamp_lit"

func can_interact() -> bool:
	return WorldState.has_flag(requires_flag) and not WorldState.has_flag(done_flag)

func verb() -> String:
	if WorldState.has_flag(done_flag):
		return "The lamp is lit"
	if not WorldState.has_flag(requires_flag):
		return "The lamp has no oil yet"
	return "Take the crank — together"

func interact(keeper: Keeper) -> void:
	Net.send_command(Command.tandem(gate_id, keeper.slot))
	print("%.3f [crank] %s reached for %s" % [
		Time.get_unix_time_from_system(), keeper.slot, gate_id,
	])
