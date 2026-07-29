extends Control
class_name BottleReader
## The letter, built to design/ui/bottle_reader.png.
##
## One stop. CONTINUE holds focus the whole time, so every d-pad direction is a
## no-op and interact always fires it — the mock's note is explicit about that,
## and it is the right shape for something you only ever read and close.
##
## Longer letters page with interact rather than scrolling: the button reads NEXT
## PAGE until the last leaf, then CONTINUE. Nothing here advances on a timer.

signal closed()

const C_INK := Color("#3a3340")
const C_PAPER := Color("#ece2d0")
const C_ACCENT := Color("#f2c14e")
const C_DIM := Color("#82558a")

@onready var _chapter: Label = %Chapter
@onready var _body: Label = %Body
@onready var _found: Label = %Found
@onready var _button: Button = %Continue
@onready var _hint: Label = %Hint

var _bottle_id := ""
var _slot := ""
var _prefix := ""
var _pages: PackedStringArray = []
var _page := 0
var _open := false

func _ready() -> void:
	visible = false
	_button.pressed.connect(_advance)

func is_open() -> bool:
	return _open

func open(bottle_id: String, slot: String, input_prefix: String) -> void:
	_bottle_id = bottle_id
	_slot = slot
	_prefix = input_prefix
	_pages = _pages_for(bottle_id)
	_page = 0
	_refresh()
	visible = true
	_open = true
	EventBus.ui_modal_changed.emit(true)
	# Focus goes to the single stop immediately, or a pad has nothing to press.
	_button.grab_focus()
	_log("opened %s (%d page(s))" % [bottle_id, _pages.size()])

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
		# Rolling it up unread leaves it unread: closing sends nothing, so the
		# letter is still there on the sand afterwards.
		close()
		return
	if event.is_action_pressed(_prefix + "interact") or event.is_action_pressed("ui_accept"):
		accept_event()
		_advance()

## Last page confirms the read. Sent once, and only from the final leaf, so a
## letter you backed out of halfway is not marked as read.
func _advance() -> void:
	if _page + 1 < _pages.size():
		_page += 1
		_refresh()
		_log("page %d of %d" % [_page + 1, _pages.size()])
		return
	if WorldState.bottle_state(_bottle_id) == "washed_up":
		_log("finished %s" % _bottle_id)
		Net.send_command(Command.read_bottle(_bottle_id))
	close()

func _refresh() -> void:
	var def := StoryRegistry.bottle(_bottle_id)
	var numeral := _roman(def.chapter if def != null else 1)
	_chapter.text = "THE KEEPER'S TRAIL — %s" % numeral
	_body.text = _pages[_page] if _page < _pages.size() else ""
	_found.text = "FOUND ON THE SHORE"

	var last := _page + 1 >= _pages.size()
	_button.text = "  CONTINUE" if last else "  NEXT PAGE"
	_hint.text = "%s  %s      %s  roll it up      %s" % [
		ButtonGlyphs.label_for("interact"),
		"continue" if last else "next page",
		ButtonGlyphs.label_for("cancel"),
		"one page · nothing else to reach" if _pages.size() == 1
			else "page %d of %d" % [_page + 1, _pages.size()],
	]

## The letters are the author's. Until they are written, the reader shows the
## content key it is waiting for rather than prose nobody chose.
func _pages_for(bottle_id: String) -> PackedStringArray:
	var def := StoryRegistry.bottle(bottle_id)
	if def == null or def.text_key == "":
		return PackedStringArray(["TODO_CONTENT"])
	return PackedStringArray([def.text_key])

func _roman(n: int) -> String:
	const NUMERALS: PackedStringArray = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII"]
	return NUMERALS[n] if n >= 0 and n < NUMERALS.size() else str(n)

func _log(line: String) -> void:
	print("%.3f [reader] %s" % [Time.get_unix_time_from_system(), line])
