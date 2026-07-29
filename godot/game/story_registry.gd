extends RefCounted
class_name StoryRegistry
## Bottles and neighbours, by id.
##
## The server holds the same rows and decides everything that matters — when a
## bottle washes in, whether it has already been read, which stage a neighbour is
## on. This copy is what the reader and the dialogue box put on screen.
##
## The letters and the crab's lines are TODO_CONTENT on purpose: they are the
## personal ones, and CLAUDE.md reserves them for the author.

const BOTTLE_DIR := "res://content/bottles"
const NPC_DIR := "res://content/npcs"

static var _bottles: Dictionary = {}
static var _npcs: Dictionary = {}
static var _loaded := false

static func bottle(bottle_id: String) -> BottleDef:
	_ensure_loaded()
	return _bottles.get(bottle_id)

static func npc(npc_id: String) -> NpcDef:
	_ensure_loaded()
	return _npcs.get(npc_id)

static func bottle_ids() -> PackedStringArray:
	_ensure_loaded()
	var ids: PackedStringArray = PackedStringArray(_bottles.keys())
	ids.sort()
	return ids

## What the crab has to say right now: the line for the stage you are about to
## have, or the idle line when they are waiting on something.
static func npc_line(npc_id: String) -> String:
	var def := npc(npc_id)
	if def == null:
		return ""
	var stage := WorldState.npc_stage(npc_id)
	if stage < def.stage_lines.size():
		return def.stage_lines[stage]
	return def.idle_line

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_into(BOTTLE_DIR, _bottles)
	_load_into(NPC_DIR, _npcs)

static func _load_into(dir_path: String, into: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("StoryRegistry: no %s" % dir_path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var name := entry.trim_suffix(".remap")
		if name.ends_with(".tres"):
			var def := load(dir_path.path_join(name))
			if def != null and def.id != "":
				into[def.id] = def
		entry = dir.get_next()
	dir.list_dir_end()
