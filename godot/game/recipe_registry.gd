extends RefCounted
class_name RecipeRegistry
## Every RecipeDef in the project, by id and by station.
##
## Content is data (CLAUDE.md): adding a recipe is adding a .tres under
## res://content/recipes/. This copy exists to draw the wheel and predict
## affordability — the server re-validates all of it and its answer is the one
## that counts (see recipe_def.gd).

const RECIPE_DIR := "res://content/recipes"

static var _by_id: Dictionary = {}
static var _loaded := false

static func get_def(recipe_id: String) -> RecipeDef:
	_ensure_loaded()
	return _by_id.get(recipe_id)

## Recipes for a station, in a stable order so the wheel never reshuffles.
## "" matches recipes craftable anywhere.
static func for_station(station: String) -> Array[RecipeDef]:
	_ensure_loaded()
	var ids: PackedStringArray = PackedStringArray(_by_id.keys())
	ids.sort()
	var out: Array[RecipeDef] = []
	for id in ids:
		var def: RecipeDef = _by_id[id]
		if def.station == "" or def.station == station:
			out.append(def)
	return out

## A recipe you have not been shown how to make yet. It still occupies its slot
## on the wheel — as a "???" — so the shape of what is coming is visible.
static func is_unlocked(def: RecipeDef) -> bool:
	return def.unlock_flag == "" or WorldState.has_flag(def.unlock_flag)

## Prediction only. The server decides; this just greys out what it will refuse.
static func can_afford(def: RecipeDef) -> bool:
	return WorldState.can_afford(def.inputs)

## Which inputs are short, and by how many — the panel names them rather than
## just refusing (DESIGN §5: the other keeper is the answer to most shortages).
static func missing(def: RecipeDef) -> Dictionary:
	var short: Dictionary = {}
	for item_id in def.inputs:
		var need := int(def.inputs[item_id])
		var have := WorldState.count(item_id)
		if have < need:
			short[item_id] = need - have
	return short

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var dir := DirAccess.open(RECIPE_DIR)
	if dir == null:
		push_warning("RecipeRegistry: no %s" % RECIPE_DIR)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var name := entry.trim_suffix(".remap")
		if name.ends_with(".tres"):
			var def := load(RECIPE_DIR.path_join(name)) as RecipeDef
			if def != null and def.id != "":
				_by_id[def.id] = def
		entry = dir.get_next()
	dir.list_dir_end()
