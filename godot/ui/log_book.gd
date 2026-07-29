extends Control
class_name LogBook
## The keeper's log, built to design/ui/keepers_log.png.
##
## Two pages. The right one is a list of entries and the ONLY thing focus lives
## in; the left one always shows whatever is focused. Directions step the list —
## five stops, no wrap — and the shoulders turn to the previous or next page of
## five. There is no scrolling anywhere, exactly as the mock's note says.
##
## It accumulates and is never pruned: at the end this is a book of your evenings
## (DESIGN §3), so nothing in here is disposable.

signal closed()

const PER_PAGE := 5

const C_TEXT := Color("#ece2d0")
const C_DIM := Color("#82558a")
const C_ACCENT := Color("#f2c14e")

@onready var _title: Label = %EntryTitle
@onready var _body: Label = %EntryBody
@onready var _byline: Label = %Byline
@onready var _header: Label = %Header
@onready var _rows: VBoxContainer = %Rows
@onready var _range_label: Label = %RangeLabel
@onready var _hint: Label = %Hint

var _slot := ""
var _prefix := ""
var _page := 0
var _cards: Array[Button] = []
var _open := false

func _ready() -> void:
	visible = false
	EventBus.log_changed.connect(_on_log_changed)

func is_open() -> bool:
	return _open

func open(slot: String, input_prefix: String) -> void:
	_slot = slot
	_prefix = input_prefix
	# Opens on the newest evening, which is the one you just had.
	_page = maxi(0, _page_count() - 1)
	_rebuild()
	visible = true
	_open = true
	EventBus.ui_modal_changed.emit(true)
	_focus_last()
	_log("opened with %d entries" % WorldState.log_entries.size())

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
	elif event.is_action_pressed(_prefix + "page_prev"):
		accept_event()
		_turn(-1)
	elif event.is_action_pressed(_prefix + "page_next"):
		accept_event()
		_turn(1)

func _turn(by: int) -> void:
	var wanted := clampi(_page + by, 0, maxi(0, _page_count() - 1))
	if wanted == _page:
		return
	_page = wanted
	_rebuild()
	if not _cards.is_empty():
		_cards[0].grab_focus()
	_log("turned to page %d" % (_page + 1))

# --- contents ---

func _page_count() -> int:
	return int(ceil(float(WorldState.log_entries.size()) / float(PER_PAGE)))

func _on_log_changed(entries: Array) -> void:
	if _open:
		# The book can be opened in the same breath as turning in, so the entry
		# often lands while it is already on screen.
		_rebuild()
		_focus_last()
		_log("book now holds %d entries" % entries.size())

func _rebuild() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_cards.clear()

	var entries: Array = WorldState.log_entries
	var total := entries.size()
	var first := _page * PER_PAGE
	var last := mini(first + PER_PAGE, total)

	_header.text = "KEEPER'S LOG   ·   %d ENTR%s" % [total, "Y" if total == 1 else "IES"]
	_range_label.text = "%d – %d OF %d" % [first + 1, last, total] if total > 0 else "EMPTY"
	_hint.text = "%s  read      %s  close      %s %s  turn the page" % [
		ButtonGlyphs.label_for("interact"), ButtonGlyphs.label_for("cancel"),
		ButtonGlyphs.label_for("page_prev"), ButtonGlyphs.label_for("page_next"),
	]

	if total == 0:
		_title.text = "nothing yet"
		_body.text = "the first evening has not been written down"
		_byline.text = ""
		return

	for i in range(first, last):
		var entry: Dictionary = entries[i]
		var card := Button.new()
		card.custom_minimum_size = Vector2(0, 16)
		card.focus_mode = Control.FOCUS_ALL
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.add_theme_font_size_override("font_size", 8)
		card.add_theme_color_override("font_color", C_DIM)
		card.add_theme_color_override("font_focus_color", C_ACCENT)
		card.text = "  Day %d      %d event%s" % [
			int(entry.get("day", i + 1)),
			(entry.get("lines", []) as Array).size(),
			"" if (entry.get("lines", []) as Array).size() == 1 else "s",
		]
		card.set_meta("index", i)
		card.focus_entered.connect(_show_entry.bind(i))
		_rows.add_child(card)
		_cards.append(card)

func _show_entry(index: int) -> void:
	var entries: Array = WorldState.log_entries
	if index < 0 or index >= entries.size():
		return
	var entry: Dictionary = entries[index]
	_title.text = "Day %d" % int(entry.get("day", index + 1))
	# The templates that turn these into sentences are the author's to write, so
	# the book shows what happened rather than putting words in her mouth.
	var lines: PackedStringArray = []
	for event in entry.get("lines", []):
		lines.append("TODO_CONTENT · %s" % String(event))
	_body.text = "\n".join(lines)
	var by := String(entry.get("written_by", ""))
	_byline.text = "written by %s · cycle %d" % [
		"A" if by == Command.SLOT_A else "B", int(entry.get("cycle", 0)),
	]
	_log("reading entry %d" % (index + 1))

func _focus_last() -> void:
	if _cards.is_empty():
		return
	_cards[_cards.size() - 1].grab_focus()

func _log(line: String) -> void:
	print("%.3f [logbook] %s" % [Time.get_unix_time_from_system(), line])
