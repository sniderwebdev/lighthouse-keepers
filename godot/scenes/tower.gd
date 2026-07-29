extends PlayableWorld
## The tower interior — the room the whole game is about putting back together.
##
## Every layer in here is driven by an authoritative flag through VisualState, so
## the tower is never showing a state the world has not agreed to. Warm ramps
## appear only where something is actually alight: the lit hearth, the restored
## lens, the lamp. Everything unrestored stays on the cool and neutral ramps,
## which is what makes the warmth mean something when it arrives (DESIGN §6).

func _ready() -> void:
	super()
	print("%.3f [tower] entered; %d/%d sealed" % [
		Time.get_unix_time_from_system(),
		MilestoneRegistry.sealed_count(), MilestoneRegistry.chain().size(),
	])
