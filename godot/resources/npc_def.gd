extends Resource
class_name NpcDef
## A neighbour, in stages. Author under res://content/npcs/.
##
## Each stage is a small ask, a reveal, and something you can now do (DESIGN §4,
## axis 3). The server holds the same stage list and is what actually advances
## it; this copy is what the dialogue box reads from.
##
## Every beat is a PackedStringArray because these people talk in short lines and
## the box advances one press at a time (CLAUDE.md: text advances on a button).
##
## SHAPE NOTE: CONTENT.md authors four conversational beats (ask / delivery,
## twice) but the server's Act 1 stage machine has two stages, so `first_meeting`
## and `stage_deliveries[1]` are what actually play. The unplayed beats are
## authored here rather than dropped — growing the stage machine is gameplay
## work, not a content fill, and the words should be waiting when it happens.
@export var id: String
@export var display_name: String

## Stage 0: the first time you talk to them at all.
@export var first_meeting: PackedStringArray
## What they ask for, per stage. Index matches the server's stage index.
@export var stage_asks: Array[PackedStringArray] = []
## What they say when the asking is over, per stage. Index matches the server's.
@export var stage_deliveries: Array[PackedStringArray] = []
## A one-time aside. Not wired to a stage.
@export var name_exchange: PackedStringArray
## Said when a stage is waiting on something that has not happened. Rotates.
@export var idle_lines: PackedStringArray
## Replaces the idle rotation once the lamp is burning.
@export var idle_after_lamp_lit: PackedStringArray
