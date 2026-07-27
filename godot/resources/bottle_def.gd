extends Resource
class_name BottleDef
## A message-in-a-bottle: one fragment of the missing-keeper mystery. Author under
## res://content/bottles/. The tide spawns these from a weighted table; reading one
## sets a story flag that can gate the next. This is where the gift's personal
## notes live — swap text_key contents for ones she'll recognize.
@export var id: String
@export var chapter: int = 1
@export var text_key: String          # localization / content key for the letter
@export var sets_flag: String         # story flag set on read
@export var requires_flag: String     # "" or a flag that must be set to spawn
@export var spawn_weight: float = 1.0
@export var min_tide_cycle: int = 0   # don't appear before this cycle
