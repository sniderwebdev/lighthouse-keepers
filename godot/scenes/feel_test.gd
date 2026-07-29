extends PlayableWorld
## The room the two of you tune in.
##
## Deliberately story-free: no bottles, no milestones, no crab, nothing that
## belongs to Sessions 1–5. Feel is worth several passes and story is worth one
## first time, so tuning happens somewhere that spends neither.
##
## What it does have is everything feel is made of — room to walk, a shore that
## floods on the tide, props to weave between, and a crank to find out how a
## tandem gate reads when you are both reaching for it.

func _ready() -> void:
	super()
	print("%.3f [feeltest] room open · %s" % [
		Time.get_unix_time_from_system(), Tuning.summary(),
	])
