extends Control
class_name RadialMenu
## The crafting wheel, built to design/ui/radial_crafting.png.
##
## Eight compass slots around the keeper. Direction maps 1:1 to a slot — no
## wrap, no cursor, nothing to aim at with a pointer. Releasing the stick back to
## centre keeps the last slot selected, which is what makes a quick flick usable.
##
## The gesture is PLAN.md's: hold interact at the bench to open, aim, release to
## craft. The mock's footer reads "[A] CRAFT"; the wording here says what the
## button actually does, but the bar, its glyphs and its position are the mock's.
##
## Nothing here decides anything. Affordability is drawn from the mirror as a
## prediction, and the server refuses independently — selecting something you
## cannot afford sends nothing at all.

## Compass order: cardinals first, then diagonals, matching the mock's d-pad note
## ("▲ ROPE COIL, ▸ GLASS PANE, ▾ CRAB TRAP, ◂ KELP NET, diagonals for the rest").
## Written out rather than normalised in place: a call is not a constant
## expression, and these never change.
const D := 0.70710678
const SLOT_DIRS: Array[Vector2] = [
	Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0),
	Vector2(D, -D), Vector2(D, D), Vector2(-D, D), Vector2(-D, -D),
]
const SLOT_COUNT := 8

## Where the wheel sits and how big its cells are, at 640x360 inside the 5%
## overscan margin. The mock's 1280x720 proportions, halved.
const WHEEL_CENTRE := Vector2(320, 132)
const WHEEL_RADIUS := Vector2(74, 56)
const CELL := Vector2(60, 34)

## Past this the stick counts as aimed. Below it, the last slot stays selected.
const AIM_DEADZONE := 0.45

# Palette, straight off the mock (DESIGN §6 ramps).
const C_TEXT := Color("#ece2d0")
const C_DIM := Color("#82558a")
const C_ACCENT := Color("#f2c14e")
const C_ACCENT_HI := Color("#ffd97a")
const C_SHORT := Color("#c14a3d")
const C_FRAME := Color("#4d4560")
const C_SLOT_BG := Color("#2a2534")
const C_LOCKED := Color("#3a3347")

signal closed()

@onready var _wheel: Control = %Wheel
@onready var _header_left: Label = %HeaderLeft
@onready var _header_right: Label = %HeaderRight
@onready var _title: Label = %RecipeTitle
@onready var _batch: Label = %BatchLabel
@onready var _desc: Label = %RecipeDesc
@onready var _costs: HBoxContainer = %Costs
@onready var _shortfall: Label = %Shortfall
@onready var _hint: Label = %Hint

var _station: Station = null
var _slot: String = ""
var _prefix: String = ""
var _recipes: Array = []          ## slot index -> RecipeDef or null
var _selected := -1
var _cells: Array[Control] = []
var _open := false

func _ready() -> void:
	visible = false
	_build_cells()

func is_open() -> bool:
	return _open

func open(station: Station, slot: String, input_prefix: String) -> void:
	_station = station
	_slot = slot
	_prefix = input_prefix
	_selected = -1
	_load_recipes()
	_refresh_all()
	visible = true
	_open = true
	EventBus.ui_modal_changed.emit(true)
	_log("opened at %s for %s" % [station.station_id, slot])

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	EventBus.ui_modal_changed.emit(false)
	_log("closed")
	closed.emit()

# --- input: aim while held, craft on release ---

func _process(_delta: float) -> void:
	if not _open:
		return

	var aim := Input.get_vector(
		_prefix + "move_left", _prefix + "move_right",
		_prefix + "move_up", _prefix + "move_down",
	)
	if aim.length() >= AIM_DEADZONE:
		var picked := _slot_for(aim)
		if picked != _selected:
			_selected = picked
			_refresh_all()

	# Release confirms (PLAN.md M4). Letting go without ever aiming just closes:
	# crafting whatever happened to be under the thumb would be a surprise, and
	# surprises are the opposite of what this game is.
	if not Input.is_action_pressed(_prefix + "interact"):
		_confirm()

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed(_prefix + "cancel") or event.is_action_pressed("ui_cancel"):
		accept_event()
		_log("cancelled")
		close()

## The nearest of eight, by angle. Nothing between slots, so a stick that is
## almost-diagonal still lands somewhere definite.
func _slot_for(aim: Vector2) -> int:
	var best := -1
	var best_dot := -INF
	for i in SLOT_COUNT:
		var dot := aim.normalized().dot(SLOT_DIRS[i])
		if dot > best_dot:
			best_dot = dot
			best = i
	return best

func _confirm() -> void:
	var def := _selected_recipe()
	if def == null:
		_log("released with nothing aimed at")
		close()
		return
	if not RecipeRegistry.is_unlocked(def):
		_log("released on a locked recipe (%s); sending nothing" % def.id)
		close()
		return
	if not RecipeRegistry.can_afford(def):
		# The server would refuse this anyway. Not sending it is the same answer,
		# arrived at without a round trip.
		_log("released on unaffordable %s; sending nothing" % def.id)
		close()
		return
	_log("crafting %s at %s" % [def.id, _station.station_id])
	Net.send_command(Command.craft(def.id, _station.station_id))
	close()

func _selected_recipe() -> RecipeDef:
	if _selected < 0 or _selected >= _recipes.size():
		return null
	return _recipes[_selected]

# --- contents ---

func _load_recipes() -> void:
	_recipes = []
	_recipes.resize(SLOT_COUNT)
	var available := RecipeRegistry.for_station(_station.station_id)
	for i in available.size():
		if i >= SLOT_COUNT:
			push_warning("station %s has more recipes than the wheel has slots" % _station.station_id)
			break
		_recipes[i] = available[i]

func _build_cells() -> void:
	for i in SLOT_COUNT:
		var cell := PanelContainer.new()
		cell.custom_minimum_size = CELL
		cell.size = CELL
		cell.position = WHEEL_CENTRE + SLOT_DIRS[i] * WHEEL_RADIUS - CELL * 0.5
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var label := Label.new()
		label.name = "Name"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 8)
		cell.add_child(label)

		_wheel.add_child(cell)
		_cells.append(cell)

func _refresh_all() -> void:
	_refresh_header()
	_refresh_cells()
	_refresh_panel()

func _refresh_header() -> void:
	var who := "keeper a" if _slot == Command.SLOT_A else "keeper b"
	_header_left.text = "CRAFTING   %s · at %s" % [who.to_upper(), _station.display_name]
	# The mock keeps a running count of what the visible recipes actually need,
	# so the wheel answers "can we?" without opening the basket.
	var needed: Array[String] = []
	for def in _recipes:
		if def == null:
			continue
		for item_id in (def as RecipeDef).inputs:
			if not needed.has(item_id):
				needed.append(item_id)
	var parts: PackedStringArray = []
	for item_id in needed:
		parts.append("%s %d" % [ItemRegistry.display_name(item_id).to_upper(), WorldState.count(item_id)])
	_header_right.text = "   ".join(parts)

func _refresh_cells() -> void:
	for i in SLOT_COUNT:
		var cell: PanelContainer = _cells[i]
		var label: Label = cell.get_node("Name")
		var def: RecipeDef = _recipes[i]
		var selected := i == _selected

		if def == null:
			label.text = ""
			_style_cell(cell, C_LOCKED, C_FRAME, selected)
			continue
		if not RecipeRegistry.is_unlocked(def):
			# Locked recipes keep their slot so the shape of what is coming is
			# visible — the mock draws them as "???" rather than hiding them.
			label.text = "???"
			label.add_theme_color_override("font_color", C_DIM)
			_style_cell(cell, C_LOCKED, C_FRAME, selected)
			continue

		label.text = ItemRegistry.display_name(def.output_id).to_upper()
		# Affordability is carried by the LABEL, selection by the border. Letting
		# both speak through the border made every affordable slot look chosen.
		var affordable := RecipeRegistry.can_afford(def)
		label.add_theme_color_override("font_color", C_TEXT if affordable else C_DIM)
		_style_cell(cell, C_SLOT_BG, C_FRAME, selected)

func _style_cell(cell: PanelContainer, bg: Color, border: Color, selected: bool) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	var width := 2 if selected else 1
	box.border_width_left = width
	box.border_width_top = width
	box.border_width_right = width
	box.border_width_bottom = width
	box.border_color = C_ACCENT_HI if selected else border
	cell.add_theme_stylebox_override("panel", box)

func _refresh_panel() -> void:
	for child in _costs.get_children():
		child.queue_free()

	var def := _selected_recipe()
	if def == null:
		_title.text = "—"
		_batch.visible = false
		_desc.text = "aim with the stick or d-pad"
		_shortfall.text = ""
		_hint.text = "%s  release to craft      %s  close wheel" % [
			ButtonGlyphs.label_for("interact"), ButtonGlyphs.label_for("cancel"),
		]
		return

	var locked := not RecipeRegistry.is_unlocked(def)
	_title.text = "???" if locked else ItemRegistry.display_name(def.output_id).to_upper()
	_batch.visible = def.output_count > 1
	_batch.text = "x%d PER BATCH" % def.output_count
	_desc.text = "not learned yet" if locked else "made at %s" % _station.display_name

	if not locked:
		for item_id in def.inputs:
			_costs.add_child(_cost_chip(item_id, int(def.inputs[item_id])))

	# Shortfalls are phrased as an invitation, not a refusal — the other keeper is
	# the answer to most of them (DESIGN §5, and the mock's own wording).
	var short := RecipeRegistry.missing(def) if not locked else {}
	if short.is_empty():
		_shortfall.text = ""
	else:
		var bits: PackedStringArray = []
		for item_id in short:
			bits.append("%d %s" % [short[item_id], ItemRegistry.display_name(item_id).to_lower()])
		var other := "keeper b" if _slot == Command.SLOT_A else "keeper a"
		_shortfall.text = "needs %s · ask %s" % [", ".join(bits), other]

	_hint.text = "%s  release to craft      %s  close wheel" % [
		ButtonGlyphs.label_for("interact"), ButtonGlyphs.label_for("cancel"),
	]

func _cost_chip(item_id: String, need: int) -> Control:
	var have := WorldState.count(item_id)
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 2)

	var icon := TextureRect.new()
	icon.texture = ItemRegistry.icon(item_id)
	icon.custom_minimum_size = Vector2(12, 12)
	icon.stretch_mode = TextureRect.STRETCH_KEEP
	chip.add_child(icon)

	var count := Label.new()
	count.text = "%d" % need
	count.add_theme_font_size_override("font_size", 8)
	count.add_theme_color_override("font_color", C_TEXT if have >= need else C_SHORT)
	chip.add_child(count)

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(8, 0)
	chip.add_child(pad)
	return chip

func _log(line: String) -> void:
	print("%.3f [radial] %s" % [Time.get_unix_time_from_system(), line])
