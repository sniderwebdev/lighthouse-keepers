extends Resource
class_name NpcDef
## A neighbour, in stages. Author under res://content/npcs/.
##
## Each stage is a small ask, a reveal, and something you can now do (DESIGN §4,
## axis 3). The server holds the same stage list and is what actually advances
## it; this copy is what the dialogue box reads from.
@export var id: String
@export var display_name: String
## One entry per stage. `TODO_CONTENT` until the author writes them — dialogue is
## hers, not ours (CLAUDE.md).
@export var stage_lines: PackedStringArray
## Said when a stage is waiting on something that has not happened yet.
@export var idle_line: String = "TODO_CONTENT"
