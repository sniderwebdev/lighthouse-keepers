extends RefCounted
class_name StoryRegistry
## Bottles and neighbours, by id.
##
## The server holds the same rows and decides everything that matters — when a
## bottle washes in, whether it has already been read, which stage a neighbour is
## on. This copy is what the reader and the dialogue box put on screen.
##
## The letters and the crab's lines are authored in CONTENT.md and live in the
## .tres files verbatim. The [SWAP]/[PERSONAL] slots inside them are still the
## author's; see STATUS.md for which remain unfilled.

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

## What the crab has to say right now, as a sequence the box steps through.
##
## Stage 0 is meeting them. After that the server's stage index selects the
## delivery beat for the stage just reached. When there is nothing new, they
## idle — and once the lamp is burning the idle changes, because that is the one
## thing in Act 1 the crab admits to noticing.
static func npc_lines(npc_id: String) -> PackedStringArray:
	var def := npc(npc_id)
	if def == null:
		return PackedStringArray()
	var beats := _beats(def)
	if beats.is_empty():
		return PackedStringArray()
	var stage := WorldState.npc_stage(npc_id)
	# The stage index counts beats COMPLETED, so the one that just landed is the
	# one before it. Before the first talk resolves there is nothing behind us,
	# so the meeting stands.
	if stage <= 0:
		return beats[0]
	if stage - 1 < beats.size():
		return beats[stage - 1]
	# Everything said. Now they idle — and the lamp changes what idling sounds
	# like, because it is the one thing in Act 1 the crab admits to noticing.
	if WorldState.flags.get("lamp_lit", false) and not def.idle_after_lamp_lit.is_empty():
		return def.idle_after_lamp_lit
	if def.idle_lines.is_empty():
		return PackedStringArray()
	# Rotates on the tide rather than at random: the same visit says the same
	# thing, and a later one has moved on.
	var idx: int = int(WorldState.tide.get("cycle", 0)) % def.idle_lines.size()
	return PackedStringArray([def.idle_lines[idx]])

## First line only — kept for callers that just want something to show.
static func npc_line(npc_id: String) -> String:
	var lines := npc_lines(npc_id)
	return lines[0] if lines.size() > 0 else ""

## Meeting first, then the ask/deliver pairs in order. Mirrors the server's
## stage list exactly (match_handler.ts NPCS) — the two must not drift.
static func _beats(def: NpcDef) -> Array[PackedStringArray]:
	var beats: Array[PackedStringArray] = []
	if not def.first_meeting.is_empty():
		beats.append(def.first_meeting)
	for i in maxi(def.stage_asks.size(), def.stage_deliveries.size()):
		if i < def.stage_asks.size():
			beats.append(def.stage_asks[i])
		if i < def.stage_deliveries.size():
			beats.append(def.stage_deliveries[i])
	return beats

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
