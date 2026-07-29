extends RefCounted
class_name ItemRegistry
## Every ItemDef in the project, by id.
##
## Content is data (CLAUDE.md): adding an item is adding a .tres under
## res://content/items/, not editing this file. Nothing here decides anything —
## the authoritative counts live on the server; this is only how the client knows
## what "driftwood" should be called and what it looks like.

const ITEM_DIR := "res://content/items"

static var _by_id: Dictionary = {}
static var _loaded := false

static func get_def(item_id: String) -> ItemDef:
	_ensure_loaded()
	return _by_id.get(item_id)

## Ids in a stable order, so the inventory grid never reshuffles itself between
## frames just because a dictionary iterated differently.
static func all_ids() -> PackedStringArray:
	_ensure_loaded()
	var ids: PackedStringArray = PackedStringArray(_by_id.keys())
	ids.sort()
	return ids

## Display name for anything, including items with no def yet — a count the
## server sends for an unknown id should still be visible rather than vanish.
static func display_name(item_id: String) -> String:
	var def := get_def(item_id)
	return def.display_name if def != null else item_id

static func icon(item_id: String) -> Texture2D:
	var def := get_def(item_id)
	return def.icon if def != null else null

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var dir := DirAccess.open(ITEM_DIR)
	if dir == null:
		push_warning("ItemRegistry: no %s" % ITEM_DIR)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		# Exported builds serve .tres as .remap; strip it so both run the same.
		var name := entry.trim_suffix(".remap")
		if name.ends_with(".tres"):
			var def := load(ITEM_DIR.path_join(name)) as ItemDef
			if def != null and def.id != "":
				_by_id[def.id] = def
		entry = dir.get_next()
	dir.list_dir_end()
