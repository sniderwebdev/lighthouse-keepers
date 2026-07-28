extends RefCounted
class_name MilestoneRegistry
## The restoration chain, in order.
##
## Files are named `0_clear_hearth.tres`, `1_fix_stairs.tres` and so on: the
## chain has an order and the filenames carry it, so adding a step between two
## others is a rename rather than a code change (CLAUDE.md, content is data).
##
## The server holds the same chain and is the one that enforces it. This copy
## draws the board and says which card is next.

const MILESTONE_DIR := "res://content/milestones"

static var _chain: Array[MilestoneDef] = []
static var _loaded := false

static func chain() -> Array[MilestoneDef]:
	_ensure_loaded()
	return _chain

static func get_def(milestone_id: String) -> MilestoneDef:
	for def in chain():
		if def.id == milestone_id:
			return def
	return null

static func is_done(def: MilestoneDef) -> bool:
	return WorldState.milestones.get(def.id, "todo") == "done"

## Sealed steps are behind you; the first unsealed one whose requirements are met
## is where you are. Everything past that is locked — readable, not confirmable.
static func is_available(def: MilestoneDef) -> bool:
	if is_done(def):
		return false
	for flag in def.required_flags:
		if flag != "" and not WorldState.has_flag(flag):
			return false
	return true

static func current() -> MilestoneDef:
	for def in chain():
		if is_available(def):
			return def
	return null

static func sealed_count() -> int:
	var n := 0
	for def in chain():
		if is_done(def):
			n += 1
	return n

static func can_afford(def: MilestoneDef) -> bool:
	return WorldState.can_afford(def.cost)

static func missing(def: MilestoneDef) -> Dictionary:
	var short: Dictionary = {}
	for item_id in def.cost:
		var need := int(def.cost[item_id])
		var have := WorldState.count(item_id)
		if have < need:
			short[item_id] = need - have
	return short

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var dir := DirAccess.open(MILESTONE_DIR)
	if dir == null:
		push_warning("MilestoneRegistry: no %s" % MILESTONE_DIR)
		return
	var names: PackedStringArray = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var name := entry.trim_suffix(".remap")
		if name.ends_with(".tres"):
			names.append(name)
		entry = dir.get_next()
	dir.list_dir_end()
	names.sort()   # the numeric prefix IS the chain order
	for name in names:
		var def := load(MILESTONE_DIR.path_join(name)) as MilestoneDef
		if def != null and def.id != "":
			_chain.append(def)
