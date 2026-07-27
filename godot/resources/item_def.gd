extends Resource
class_name ItemDef
## A single inventory item type. Author one .tres per item under res://content/items/.
## Adding items = adding files. No code changes.
@export var id: String
@export var display_name: String
@export var icon: Texture2D
@export var max_stack: int = 99
@export var tags: PackedStringArray   # e.g. ["salvage"], ["food"], ["fuel"]
