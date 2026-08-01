extends Control
class_name AudioSettings
## The four volume sliders, worked with a direction and a button.
##
## Built like the tuning overlay on purpose — same rows, same left/right to turn,
## same reset — because a player who has learned one of these has learned both.
## The difference is what the numbers are: these are MIX values with a slider
## each, not feel values, so they are the author's to move whenever and are
## exempt from the playtest gate (NEXT.md 2026-07-31.2 item 5).
##
## Controller-first (CLAUDE.md): no Slider node anywhere in here. A Godot
## HSlider wants a grab and a drag, which is a mouse gesture wearing a keyboard
## costume; a focusable row that answers left and right is the same value and
## works on a d-pad without apologising.

signal closed()

const C_TEXT := Color("#ece2d0")
const C_DIM := Color("#82558a")
const C_ACCENT := Color("#f2c14e")
const C_CHANGED := Color("#d2603f")

## One notch. Ten steps end to end is enough to find "a bit quieter" and few
## enough to cross the whole range without a long hold.
const STEP := 0.1

## How the level is drawn. Eight cells of block, because a number from 0 to 100
## tells you less at a glance than a bar does.
const METER_CELLS := 8

@onready var _rows: VBoxContainer = %Rows
@onready var _hint: Label = %Hint
@onready var _note: Label = %Note

var _prefix := ""
var _open := false
var _cards: Array[Button] = []

func _ready() -> void:
	visible = false
	Audio.volumes_changed.connect(_on_volumes_changed)

func is_open() -> bool:
	return _open

func open(input_prefix: String) -> void:
	_prefix = input_prefix
	_rebuild()
	visible = true
	_open = true
	EventBus.ui_modal_changed.emit(true)
	if not _cards.is_empty():
		_cards[0].grab_focus()
	print("%.3f [audio-ui] opened: %s" % [Time.get_unix_time_from_system(), Audio.summary()])

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	EventBus.ui_modal_changed.emit(false)
	print("%.3f [audio-ui] closed: %s" % [Time.get_unix_time_from_system(), Audio.summary()])
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("p2_cancel") \
			or event.is_action_pressed("ui_cancel"):
		accept_event()
		close()
		return
	var bus := _focused_bus()
	if bus == "":
		return
	if event.is_action_pressed("ui_right"):
		accept_event()
		_nudge(bus, 1)
	elif event.is_action_pressed("ui_left"):
		accept_event()
		_nudge(bus, -1)
	elif event.is_action_pressed(_prefix + "use_tool"):
		accept_event()
		for name in Audio.DEFAULTS:
			Audio.set_volume(name, float(Audio.DEFAULTS[name]))

func _nudge(bus: String, direction: int) -> void:
	Audio.set_volume(bus, Audio.get_volume(bus) + STEP * float(direction))
	# Say it out loud on the bus you just moved, or a slider for a channel that
	# happens to be quiet right now gives no feedback at all.
	if bus == "SFX" or bus == "Master":
		Audio.play("radial_tick")

func _focused_bus() -> String:
	var focused := get_viewport().gui_get_focus_owner()
	return String(focused.get_meta("bus", "")) if focused != null else ""

func _on_volumes_changed() -> void:
	if _open:
		_refresh_labels()

func _rebuild() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_cards.clear()
	for bus in Audio.BUSES:
		var row := Button.new()
		row.custom_minimum_size = Vector2(0, 16)
		row.focus_mode = Control.FOCUS_ALL
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_font_size_override("font_size", 8)
		row.add_theme_color_override("font_color", C_TEXT)
		row.add_theme_color_override("font_focus_color", C_ACCENT)
		row.set_meta("bus", bus)
		_rows.add_child(row)
		_cards.append(row)
	_refresh_labels()

func _meter(value: float) -> String:
	var filled := roundi(value * float(METER_CELLS))
	return "█".repeat(filled) + "░".repeat(METER_CELLS - filled)

func _refresh_labels() -> void:
	for row in _cards:
		var bus := String(row.get_meta("bus"))
		var value := Audio.get_volume(bus)
		var is_default := is_equal_approx(value, float(Audio.DEFAULTS[bus]))
		row.text = "%s%-10s ‹ %s › %3d%%" % [
			"  " if is_default else "· ", bus, _meter(value), roundi(value * 100.0),
		]
		row.add_theme_color_override("font_color", C_TEXT if is_default else C_CHANGED)
	_hint.text = "%s %s  change      %s  reset all      %s  close" % [
		ButtonGlyphs.label_for("page_prev"), ButtonGlyphs.label_for("page_next"),
		ButtonGlyphs.label_for("use_tool"), ButtonGlyphs.label_for("cancel"),
	]
	_note.text = "left/right sets the level · saved as you go"
