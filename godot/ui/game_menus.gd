extends CanvasLayer
class_name GameMenus
## Owns the in-play menus and the two ways into them.
##
## Held `menu_radial` goes straight to the basket, because that is the thing you
## want twenty times a session; `menu_pause` opens the list, which is the way you
## find it the first time. Both are on the pad. Nothing here is one of the five
## author-mocked screens (CLAUDE.md UI mock gate).
##
## While a menu is open the keepers stop reading their pads, so choosing an item
## never also walks you into the sea.

## Long enough not to fire on a tap, short enough not to feel like a wait.
const HOLD_SECONDS := 0.25

signal menu_opened()
signal menu_closed()
signal debug_toggle_requested()

@onready var _inventory: InventoryPanel = %Inventory
@onready var _pause: PauseMenu = %Pause

var _hold := 0.0
var _holding := false

func _ready() -> void:
	_inventory.closed.connect(_on_any_closed)
	_pause.closed.connect(_on_any_closed)
	_pause.chose_inventory.connect(_open_inventory)
	_pause.chose_debug.connect(func() -> void: debug_toggle_requested.emit())

func any_open() -> bool:
	return _inventory.is_open() or _pause.is_open()

func _process(delta: float) -> void:
	if any_open():
		_holding = false
		_hold = 0.0
		return
	# Either pad can call up the basket; it belongs to both of you.
	var held := Input.is_action_pressed("menu_radial") or Input.is_action_pressed("p2_menu_radial")
	if not held:
		_holding = false
		_hold = 0.0
		return
	if not _holding:
		_holding = true
		_hold = 0.0
	_hold += delta
	if _hold >= HOLD_SECONDS:
		_holding = false
		_open_inventory()

func _unhandled_input(event: InputEvent) -> void:
	if any_open():
		return
	if event.is_action_pressed("menu_pause") or event.is_action_pressed("p2_menu_pause"):
		# A CanvasLayer is not a Control, so it marks the event handled through
		# the viewport rather than accept_event().
		get_viewport().set_input_as_handled()
		_pause.open()
		_announce(true)

func _open_inventory() -> void:
	_pause.close()
	_inventory.open()
	_announce(true)

func _on_any_closed() -> void:
	if not any_open():
		_announce(false)

func _announce(open: bool) -> void:
	EventBus.ui_modal_changed.emit(open)
	if open:
		menu_opened.emit()
	else:
		menu_closed.emit()
