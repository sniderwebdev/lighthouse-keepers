extends Control
class_name InventoryPanel
## The shared basket, as a controller grid.
##
## One inventory belongs to the world, not to a keeper (DESIGN §5), so this shows
## the same counts on both screens and updates the moment the server says so.
##
## Controller-first (CLAUDE.md): every cell is reachable by direction, focus is
## visible, cancel closes, and nothing in here knows what a mouse is. Test it by
## unplugging one.

const COLUMNS := 4
const CELL := Vector2(56, 40)

signal closed()

@onready var _grid: GridContainer = %Grid
@onready var _empty_label: Label = %EmptyLabel

var _cells: Dictionary = {}   ## item_id -> Button

func _ready() -> void:
	visible = false
	_grid.columns = COLUMNS
	%CloseHint.text = ButtonGlyphs.prompt("cancel", "close")
	EventBus.inventory_changed.connect(_on_inventory_changed)

func open() -> void:
	_rebuild()
	visible = true
	_log("opened with %d kinds" % _cells.size())
	# Focus has to land somewhere, or the first press of a direction goes nowhere
	# and the panel feels broken on a pad.
	var first := _first_cell()
	if first != null:
		first.grab_focus()

func close() -> void:
	visible = false
	_log("closed")
	closed.emit()

func is_open() -> bool:
	return visible

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("p2_cancel") \
			or event.is_action_pressed("ui_cancel") \
			or event.is_action_pressed("menu_pause") or event.is_action_pressed("p2_menu_pause"):
		accept_event()
		close()

## Rebuilt from the mirror rather than patched in place: the set of items you own
## changes rarely, and a grid that is always built the same way cannot drift out
## of step with the world.
func _rebuild() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_cells.clear()

	var shown := 0
	for item_id in ItemRegistry.all_ids():
		var count := WorldState.count(item_id)
		if count <= 0:
			continue
		_grid.add_child(_make_cell(item_id, count))
		shown += 1
	# Anything the server has sent that has no def yet still deserves to be seen.
	for item_id in WorldState.inventory:
		if _cells.has(item_id) or WorldState.count(item_id) <= 0:
			continue
		_grid.add_child(_make_cell(item_id, WorldState.count(item_id)))
		shown += 1

	_empty_label.visible = shown == 0
	_grid.visible = shown > 0

func _make_cell(item_id: String, count: int) -> Button:
	var cell := Button.new()
	cell.custom_minimum_size = CELL
	cell.focus_mode = Control.FOCUS_ALL
	# No mouse: the grid is reached by direction or not at all.
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.icon = ItemRegistry.icon(item_id)
	cell.text = "%d" % count
	cell.tooltip_text = ""
	cell.expand_icon = false
	cell.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	cell.add_theme_font_size_override("font_size", 8)
	cell.add_theme_color_override("font_color", Color("#ece2d0"))
	cell.add_theme_color_override("font_focus_color", Color("#f6c752"))
	cell.set_meta("item_id", item_id)
	# Focus is the only selection there is here, so it is worth saying out loud:
	# it is what proves the grid is navigable without a mouse.
	cell.focus_entered.connect(func() -> void: _log("focus -> %s" % item_id))
	_cells[item_id] = cell
	return cell

func _log(line: String) -> void:
	print("%.3f [inventory] %s" % [Time.get_unix_time_from_system(), line])

func _first_cell() -> Button:
	for child in _grid.get_children():
		var button := child as Button
		if button != null:
			return button
	return null

func _on_inventory_changed(item_id: String, new_count: int) -> void:
	if not visible:
		return
	var cell: Button = _cells.get(item_id)
	if cell == null:
		# A kind of thing we did not have before; the grid has a new shape.
		var focused := get_viewport().gui_get_focus_owner()
		var keep: String = focused.get_meta("item_id", "") if focused != null else ""
		_rebuild()
		var restore: Button = _cells.get(keep, _first_cell())
		if restore != null:
			restore.grab_focus()
		return
	cell.text = "%d" % new_count
	if new_count <= 0:
		_rebuild()
