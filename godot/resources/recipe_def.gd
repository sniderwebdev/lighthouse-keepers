extends Resource
class_name RecipeDef
## A craftable. Author one .tres per recipe under res://content/recipes/.
## NOTE: the server re-validates inputs/outputs authoritatively — this client copy
## is for showing the recipe book and predicting affordability only.
@export var id: String
@export var inputs: Dictionary        # item_id (String) -> count (int)
@export var output_id: String
@export var output_count: int = 1
@export var station: String           # "" = anywhere, else "stove" | "workbench"
@export var unlock_flag: String       # "" = available from start, else gated on this flag
