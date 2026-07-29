extends Control
class_name TitleScreen
## Title and session flow, built to design/ui/title_session.png.
##
## Seven stops, walked with a direction and no wrap, exactly as the mock's note
## says: CONTINUE → NEW VOYAGE → SETTINGS → WORLD CODE → PLAY MODE → KEEPER A ↔
## KEEPER B, and cancel returns focus to CONTINUE. Nothing here needs a pointer,
## and the world code is entered with the stick rather than a keyboard, because
## a console has no keyboard and this is the screen that would otherwise assume
## one.

signal start_requested(world_code: String, slots: String)

const CODE_LENGTH := 5
const ALPHABET := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

const C_TEXT := Color("#ece2d0")
const C_DIM := Color("#82558a")
const C_ACCENT := Color("#f2c14e")

@onready var _rows: VBoxContainer = %Rows
@onready var _code_label: Label = %CodeLabel
@onready var _mode_label: Label = %ModeLabel
@onready var _keeper_label: Label = %KeeperLabel
@onready var _hint: Label = %Hint
@onready var _continue_note: Label = %ContinueNote

## The last world this machine played, so CONTINUE means something.
const SAVE_PATH := "user://last_session.cfg"

var _code: PackedByteArray = PackedByteArray()
var _cursor := 0
var _couch := false
var _slot := Command.SLOT_A
var _stops: Array[Button] = []

func _ready() -> void:
	_code.resize(CODE_LENGTH)
	_load_last()
	_build_stops()
	_refresh()

func focus_first() -> void:
	if not _stops.is_empty():
		_stops[0].grab_focus()

# --- the seven stops ---

func _build_stops() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_stops.clear()
	_stops.append(_stop("CONTINUE", _on_continue))
	_stops.append(_stop("NEW VOYAGE", _on_new_voyage))
	_stops.append(_stop("SETTINGS", _on_settings))
	_stops.append(_stop("WORLD CODE", _on_code_stop))
	_stops.append(_stop("PLAY MODE", _on_mode_stop))
	_stops.append(_stop("KEEPER A", func() -> void: _pick_keeper(Command.SLOT_A)))
	_stops.append(_stop("KEEPER B", func() -> void: _pick_keeper(Command.SLOT_B)))

func _stop(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = "  " + text
	button.custom_minimum_size = Vector2(0, 16)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 8)
	button.add_theme_color_override("font_color", C_TEXT)
	button.add_theme_color_override("font_focus_color", C_ACCENT)
	button.pressed.connect(on_press)
	button.focus_entered.connect(func() -> void: _log("focus -> %s" % text))
	_rows.add_child(button)
	return button

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# Cancel walks focus home rather than leaving the screen: there is nowhere
	# above the title to go back to.
	if event.is_action_pressed("cancel") or event.is_action_pressed("ui_cancel"):
		accept_event()
		focus_first()
		return
	# The world code is edited in place: up and down change the letter under the
	# cursor, left and right move it. No keyboard anywhere.
	if _focused_index() == 3:
		if event.is_action_pressed("ui_up"):
			accept_event(); _bump_letter(1)
		elif event.is_action_pressed("ui_down"):
			accept_event(); _bump_letter(-1)
		elif event.is_action_pressed("ui_right"):
			accept_event(); _move_cursor(1)
		elif event.is_action_pressed("ui_left"):
			accept_event(); _move_cursor(-1)

func _focused_index() -> int:
	var focused := get_viewport().gui_get_focus_owner()
	return _stops.find(focused)

# --- world code ---

func _bump_letter(by: int) -> void:
	_code[_cursor] = posmod(_code[_cursor] + by, ALPHABET.length())
	_refresh()

func _move_cursor(by: int) -> void:
	_cursor = clampi(_cursor + by, 0, CODE_LENGTH - 1)
	_refresh()

func _code_string() -> String:
	var out := ""
	for i in CODE_LENGTH:
		out += ALPHABET[_code[i]]
	return out

# --- choices ---

func _on_continue() -> void:
	_start()

func _on_new_voyage() -> void:
	# A new voyage is a new world, so it gets a code you did not have before.
	for i in CODE_LENGTH:
		_code[i] = randi() % ALPHABET.length()
	_cursor = 0
	_refresh()
	_log("new voyage: %s" % _code_string())

func _on_settings() -> void:
	# Deferred on purpose (PLAN.md "open items"): remapping and audio are not in
	# the slice, and a settings screen with nothing in it is worse than none.
	_log("settings are not in this slice")

func _on_code_stop() -> void:
	_start()

func _on_mode_stop() -> void:
	_couch = not _couch
	_refresh()
	_log("play mode -> %s" % ("couch" if _couch else "online"))

func _pick_keeper(slot: String) -> void:
	_slot = slot
	_refresh()
	_log("keeper -> %s" % slot)
	_start()

func _start() -> void:
	var slots := Net.SLOTS_BOTH if _couch else _slot
	_save_last()
	_log("starting %s as %s" % [_code_string(), slots])
	start_requested.emit(_code_string(), slots)

# --- presentation ---

func _refresh() -> void:
	var boxes: PackedStringArray = []
	for i in CODE_LENGTH:
		boxes.append("[%s]" % ALPHABET[_code[i]] if i == _cursor else " %s " % ALPHABET[_code[i]])
	_code_label.text = "WORLD CODE   %s" % "".join(boxes)
	_mode_label.text = "PLAY MODE    %s" % (
		"together on this couch" if _couch else "across the sea"
	)
	_keeper_label.text = "YOUR KEEPER  %s" % (
		"both, one each pad" if _couch else ("A · lamp" if _slot == Command.SLOT_A else "B · rope")
	)
	_continue_note.text = "last played %s" % _code_string()
	_hint.text = "%s  confirm      %s  back      up/down letter · left/right slot" % [
		ButtonGlyphs.label_for("interact"), ButtonGlyphs.label_for("cancel"),
	]

# --- remembering ---

func _load_last() -> void:
	var cfg := ConfigFile.new()
	var code := "HARBO"
	if cfg.load(SAVE_PATH) == OK:
		code = String(cfg.get_value("session", "world_code", code))
		_couch = bool(cfg.get_value("session", "couch", false))
		_slot = String(cfg.get_value("session", "slot", Command.SLOT_A))
	for i in CODE_LENGTH:
		var letter := code[i] if i < code.length() else "A"
		_code[i] = maxi(0, ALPHABET.find(letter))

func _save_last() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("session", "world_code", _code_string())
	cfg.set_value("session", "couch", _couch)
	cfg.set_value("session", "slot", _slot)
	cfg.save(SAVE_PATH)

func _log(line: String) -> void:
	print("%.3f [title] %s" % [Time.get_unix_time_from_system(), line])
