extends Control
class_name TuningOverlay
## The four feel values, turnable from a pad, mid-session.
##
## This is the playtest instrument. It exists so the two people playing can say
## "a bit faster" and try it in the same breath, instead of somebody stopping to
## edit a constant. Directions step the list, left and right turn the value under
## the cursor, and everything applies on the next frame.
##
## Nothing found here ships on its own: the committed answer is what ends up in
## Tuning.DEFAULTS after a playtest is logged in PLAYTESTS.md (CLAUDE.md Testing
## law). The overlay writes `user://tuning.cfg`, which is one evening's
## experiment.

signal closed()

const C_TEXT := Color("#ece2d0")
const C_DIM := Color("#82558a")
const C_ACCENT := Color("#f2c14e")
const C_CHANGED := Color("#d2603f")

@onready var _rows: VBoxContainer = %Rows
@onready var _hint: Label = %Hint
@onready var _note: Label = %Note

var _prefix := ""
var _open := false
var _cards: Array[Button] = []

func _ready() -> void:
	visible = false
	Tuning.changed.connect(_on_tuning_changed)

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
	print("%.3f [tuning-ui] opened: %s" % [Time.get_unix_time_from_system(), Tuning.summary()])

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	EventBus.ui_modal_changed.emit(false)
	print("%.3f [tuning-ui] closed: %s" % [Time.get_unix_time_from_system(), Tuning.summary()])
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("p2_cancel") \
			or event.is_action_pressed("ui_cancel"):
		accept_event()
		close()
		return
	var key := _focused_key()
	if key == "":
		return
	# Left and right turn the value the cursor is on. Up and down are left to the
	# focus system, which is already walking the list.
	if event.is_action_pressed("ui_right"):
		accept_event()
		_nudge(key, 1)
	elif event.is_action_pressed("ui_left"):
		accept_event()
		_nudge(key, -1)
	elif event.is_action_pressed(_prefix + "use_tool"):
		accept_event()
		Tuning.reset_all()

func _nudge(key: String, direction: int) -> void:
	Tuning.nudge(key, direction)
	# The tide's length is the world's, not this client's, so that one has to ask.
	if key == "tide_cycle_seconds":
		Net.request_cycle_seconds(Tuning.get_value(key))

func _focused_key() -> String:
	var focused := get_viewport().gui_get_focus_owner()
	return String(focused.get_meta("key", "")) if focused != null else ""

func _on_tuning_changed(_key: String, _value: float) -> void:
	if _open:
		_refresh_labels()

func _rebuild() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_cards.clear()
	for key in Tuning.DEFAULTS:
		var row := Button.new()
		row.custom_minimum_size = Vector2(0, 16)
		row.focus_mode = Control.FOCUS_ALL
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_font_size_override("font_size", 8)
		row.add_theme_color_override("font_color", C_TEXT)
		row.add_theme_color_override("font_focus_color", C_ACCENT)
		row.set_meta("key", key)
		_rows.add_child(row)
		_cards.append(row)
	_refresh_labels()

func _refresh_labels() -> void:
	for row in _cards:
		var key := String(row.get_meta("key"))
		# A changed value is marked, so a playtest note can say what was actually
		# different rather than what somebody meant to change.
		var mark := "  " if Tuning.is_default(key) else "· "
		row.text = "%s%-16s  ‹ %s ›" % [mark, Tuning.label_for(key), Tuning.format(key)]
		row.add_theme_color_override(
			"font_color", C_TEXT if Tuning.is_default(key) else C_CHANGED
		)
	_hint.text = "%s %s  change      %s  reset all      %s  close" % [
		ButtonGlyphs.label_for("page_prev"), ButtonGlyphs.label_for("page_next"),
		ButtonGlyphs.label_for("use_tool"), ButtonGlyphs.label_for("cancel"),
	]
	_note.text = "left/right turns the value · findings go in PLAYTESTS.md"
