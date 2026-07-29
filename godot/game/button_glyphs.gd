extends RefCounted
class_name ButtonGlyphs
## The one place a button is turned into something you can read.
##
## Console-ready posture (CLAUDE.md): every prompt in the game asks here, so the
## whole set can be re-skinned per platform later by editing this file and
## nothing else. Nowhere should a scene hardcode "press A".
##
## Gamepad is the design target, so gamepad glyphs are what you get unless the
## player has actually touched a keyboard this session.

enum Device { GAMEPAD, KEYBOARD }

## Glyphs per input action. Keep keyed by ACTION, never by key or button index —
## the action map is the only thing allowed to know what a button is.
const GAMEPAD: Dictionary = {
	"interact": "A",
	"cancel": "B",
	"use_tool": "X",
	"menu_radial": "Y",
	"menu_pause": "☰",   # ☰
	"page_prev": "L",
	"page_next": "R",
}
const KEYBOARD: Dictionary = {
	"interact": "E",
	"cancel": "Esc",
	"use_tool": "Q",
	"menu_radial": "Tab",
	"menu_pause": "F1",
	"page_prev": "[",
	"page_next": "]",
}

static var _device: Device = Device.GAMEPAD

## Called from the input path so prompts follow whatever the player last used.
static func note_event(event: InputEvent) -> void:
	if event is InputEventKey:
		_device = Device.KEYBOARD
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_device = Device.GAMEPAD

static func device() -> Device:
	return _device

## The glyph for an action, stripped of any p2_ prefix — the second pad's
## buttons are in the same places as the first's.
static func label_for(action: String) -> String:
	var base := action.trim_prefix("p2_")
	var table: Dictionary = KEYBOARD if _device == Device.KEYBOARD else GAMEPAD
	return String(table.get(base, "?"))

## A prompt line: the glyph and what it will do. One phrasing, everywhere.
static func prompt(action: String, verb: String) -> String:
	return "[%s] %s" % [label_for(action), verb]
