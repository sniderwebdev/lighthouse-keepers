extends Control
class_name MilestoneBoard
## The restoration chain, built to design/ui/milestone_board.png.
##
## Five cards on a rope, top to bottom, in the order the tower has to be put back
## together. Sealed cards are behind you, one card is current, the rest are
## locked — readable but not confirmable, exactly as the mock's d-pad note says.
##
## Focus opens on the current card, and BEGIN fires with interact from the card
## itself rather than from a separate button, so the chain is one list of five
## stops rather than a form to tab through.

signal closed()

const C_TEXT := Color("#ece2d0")
const C_DIM := Color("#82558a")
const C_ACCENT := Color("#f2c14e")
const C_SEALED := Color("#c0473b")
const C_SHORT := Color("#c14a3d")
const C_FRAME := Color("#4d4560")

@onready var _rows: VBoxContainer = %Rows
@onready var _header: Label = %Header
@onready var _progress: Label = %Progress
@onready var _detail: Label = %DetailLabel
@onready var _costs: HBoxContainer = %Costs
@onready var _shortfall: Label = %Shortfall
@onready var _hint: Label = %Hint

var _slot := ""
var _prefix := ""
var _cards: Array[Button] = []
var _open := false

func _ready() -> void:
	visible = false
	EventBus.milestone_changed.connect(_on_world_changed)
	EventBus.flag_changed.connect(_on_world_changed)
	EventBus.inventory_changed.connect(_on_world_changed)

func is_open() -> bool:
	return _open

func open(slot: String, input_prefix: String) -> void:
	_slot = slot
	_prefix = input_prefix
	_rebuild()
	visible = true
	_open = true
	EventBus.ui_modal_changed.emit(true)
	_focus_current()
	_log("opened; %d/%d sealed" % [
		MilestoneRegistry.sealed_count(), MilestoneRegistry.chain().size(),
	])

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	EventBus.ui_modal_changed.emit(false)
	_log("closed")
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("p2_cancel") \
			or event.is_action_pressed("ui_cancel"):
		accept_event()
		close()
		return
	# BEGIN is fired from the focused card, not from a separate button — the
	# mock's note is explicit that there is no second focus stop.
	if event.is_action_pressed(_prefix + "interact") or event.is_action_pressed("ui_accept"):
		var focused := get_viewport().gui_get_focus_owner() as Button
		if focused != null and focused.has_meta("milestone_id"):
			accept_event()
			_begin(String(focused.get_meta("milestone_id")))

## Funding a step is an intent like any other. Sealed and locked cards send
## nothing: the server would refuse them, and saying so twice is not needed.
func _begin(milestone_id: String) -> void:
	var def := MilestoneRegistry.get_def(milestone_id)
	if def == null:
		return
	if MilestoneRegistry.is_done(def):
		_log("%s is already sealed; sending nothing" % milestone_id)
		return
	if not MilestoneRegistry.is_available(def):
		_log("%s is locked behind an earlier step; sending nothing" % milestone_id)
		return
	if not MilestoneRegistry.can_afford(def):
		_log("%s is unaffordable; sending nothing" % milestone_id)
		return
	_log("beginning %s" % milestone_id)
	Net.send_command(Command.advance_step(milestone_id))

# --- contents ---

func _on_world_changed(_a: Variant = null, _b: Variant = null) -> void:
	if _open:
		var keep := _focused_id()
		_rebuild()
		_restore_focus(keep)

func _rebuild() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_cards.clear()

	var chain := MilestoneRegistry.chain()
	_header.text = "ACT ONE · THE RELIGHTING"
	_progress.text = "%d / %d SEALED" % [MilestoneRegistry.sealed_count(), chain.size()]

	for def in chain:
		var card := Button.new()
		card.custom_minimum_size = Vector2(0, 18)
		card.focus_mode = Control.FOCUS_ALL
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.add_theme_font_size_override("font_size", 8)
		card.set_meta("milestone_id", def.id)

		var state := ""
		var colour := C_DIM
		if MilestoneRegistry.is_done(def):
			state = "SEALED"
			colour = C_SEALED
		elif MilestoneRegistry.is_available(def):
			state = "CURRENT"
			colour = C_ACCENT
		else:
			state = "LOCKED"
		card.text = "  %s      %s" % [def.display_name.to_upper(), state]
		card.add_theme_color_override("font_color", colour)
		card.add_theme_color_override("font_focus_color", C_TEXT)
		card.focus_entered.connect(_on_card_focused.bind(def.id))

		_rows.add_child(card)
		_cards.append(card)

	_show_detail(MilestoneRegistry.current())

func _on_card_focused(milestone_id: String) -> void:
	_show_detail(MilestoneRegistry.get_def(milestone_id))
	_log("focus -> %s" % milestone_id)

func _show_detail(def: MilestoneDef) -> void:
	for child in _costs.get_children():
		child.queue_free()
	_hint.text = "%s  begin      %s  back" % [
		ButtonGlyphs.label_for("interact"), ButtonGlyphs.label_for("cancel"),
	]

	if def == null:
		_detail.text = "every step is sealed"
		_shortfall.text = ""
		return

	# Board flavour is authored per milestone (CONTENT.md) and lives on the
	# MilestoneDef, not here.
	var note: String = def.description if def.description != "" else def.display_name
	if def.is_lamp_relight:
		note += "   ·   NEEDS BOTH KEEPERS"
	_detail.text = note

	for item_id in def.cost:
		_costs.add_child(_cost_chip(item_id, int(def.cost[item_id])))

	if MilestoneRegistry.is_done(def):
		_shortfall.text = ""
	elif not MilestoneRegistry.is_available(def):
		_shortfall.text = "the step before this one comes first"
	else:
		var short := MilestoneRegistry.missing(def)
		if short.is_empty():
			_shortfall.text = ""
		else:
			var bits: PackedStringArray = []
			for item_id in short:
				bits.append("%d %s" % [short[item_id], ItemRegistry.display_name(item_id).to_lower()])
			var other := "keeper b" if _slot == Command.SLOT_A else "keeper a"
			_shortfall.text = "needs %s · ask %s" % [", ".join(bits), other]

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

# --- focus ---

## Opens on the step you are actually on, so the first thing under the thumb is
## the thing you came to do.
func _focus_current() -> void:
	var current := MilestoneRegistry.current()
	if current != null and _restore_focus(current.id):
		return
	if not _cards.is_empty():
		_cards[0].grab_focus()

func _focused_id() -> String:
	var focused := get_viewport().gui_get_focus_owner() as Button
	return String(focused.get_meta("milestone_id", "")) if focused != null else ""

func _restore_focus(milestone_id: String) -> bool:
	for card in _cards:
		if String(card.get_meta("milestone_id", "")) == milestone_id:
			card.grab_focus()
			return true
	return false

func _log(line: String) -> void:
	print("%.3f [board] %s" % [Time.get_unix_time_from_system(), line])
