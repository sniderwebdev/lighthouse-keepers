extends Control
class_name PauseMenu
## A short list you move through with a direction and choose with one button.
##
## Placeholder furniture, not the title/session flow — that screen is author-mocked
## and gated (CLAUDE.md UI mock gate); this is the plain in-play menu M3 needs to
## reach the basket.

signal chose_inventory()
signal chose_debug()
signal closed()

@onready var _items: VBoxContainer = %Items
@onready var _hint: Label = %Hint

func _ready() -> void:
	visible = false
	%Inventory.pressed.connect(func() -> void: chose_inventory.emit())
	%DebugReadout.pressed.connect(func() -> void: chose_debug.emit())
	%Resume.pressed.connect(close)
	for child in _items.get_children():
		var button := child as Button
		if button != null:
			# No mouse anywhere in the menu path; direction and confirm only.
			button.mouse_filter = Control.MOUSE_FILTER_IGNORE

func open() -> void:
	visible = true
	_hint.text = "%s  ·  %s" % [
		ButtonGlyphs.prompt("interact", "choose"), ButtonGlyphs.prompt("cancel", "back"),
	]
	(%Inventory as Button).grab_focus()

func close() -> void:
	visible = false
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
	# The second pad has to be able to work the menu too — on the couch either
	# keeper might be the one holding a controller when you want the basket.
	elif event.is_action_pressed("p2_interact"):
		var focused := get_viewport().gui_get_focus_owner() as Button
		if focused != null:
			accept_event()
			focused.pressed.emit()
