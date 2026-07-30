extends Resource
class_name LogTemplates
## The keeper's log, in the author's words.
##
## The server records what happened as bare event ids ("milestone:clear_hearth");
## this turns them into sentences. Content is data (CLAUDE.md), so the sentences
## live in res://content/log/entries.tres and never in the UI script.
##
## Voice, per CONTENT.md: neutral-warm "we", one to three sentences per entry.
##
## SOLO variants exist because a line written for two people is wrong when only
## one of you played. A key with a "_SOLO" twin uses it when the session had a
## single keeper.
##
## Placeholders the renderer fills: {items} {keeper} {item} {count}.
@export var highlights: Dictionary = {}
## Optional colour, zero to two per entry.
@export var flavor: Dictionary = {}
## Occasional sign-off, roughly every third entry.
@export var closers: PackedStringArray = []
## Used when a session had one keeper in it.
@export var closer_solo: String = ""
