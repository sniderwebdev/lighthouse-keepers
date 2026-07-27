extends Resource
class_name MilestoneDef
## A restoration step that visibly improves the tower. Author under
## res://content/milestones/. on_complete_flags drive both story gating and the
## visual swap (set_visual_state) so the lighthouse transforms as you progress.
@export var id: String
@export var display_name: String
@export var required_flags: PackedStringArray   # must all be true to start
@export var cost: Dictionary                     # item_id -> count
@export var on_complete_flags: PackedStringArray # set true when finished
@export var visual_state: String                 # node state to apply ("stairs_fixed")
@export var is_lamp_relight: bool = false        # the co-op-gated climax milestone
