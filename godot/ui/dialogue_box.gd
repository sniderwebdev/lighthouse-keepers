extends Control
class_name DialogueBox
## Somebody talking to you.
##
## Button-advanced, never timed (CLAUDE.md controller-first law: text advances on
## a button press, never on a click or a timer alone). A portrait slot sits where
## the art will go.
##
## Not one of the five author-mocked screens, so this is built directly — plain,
## and shaped like the other panels.

signal closed()

@onready var _name_label: Label = %Speaker
@onready var _line: Label = %Line
@onready var _hint: Label = %Hint

var _npc_id := ""
var _slot := ""
var _prefix := ""
var _open := false
var _spoke := false
## The beat being spoken, and how far through it we are. They talk in short
## lines and you press for each one.
var _lines: PackedStringArray = []
var _index := 0

func is_open() -> bool:
	return _open

func _ready() -> void:
	visible = false

func open(npc_id: String, slot: String, input_prefix: String) -> void:
	_npc_id = npc_id
	_slot = slot
	_prefix = input_prefix
	_spoke = false
	_index = 0
	_refresh()
	visible = true
	_open = true
	EventBus.ui_modal_changed.emit(true)
	# Talking is an intent; whether there is anything new to say is the world's
	# call, and its answer arrives as a stage change while the box is open.
	EventBus.npc_stage_changed.connect(_on_stage_changed)
	Net.send_command(Command.talk(_npc_id, _slot))
	_log("talking to %s at stage %d" % [_npc_id, WorldState.npc_stage(_npc_id)])

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	if EventBus.npc_stage_changed.is_connected(_on_stage_changed):
		EventBus.npc_stage_changed.disconnect(_on_stage_changed)
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
	elif event.is_action_pressed(_prefix + "interact") or event.is_action_pressed("ui_accept"):
		accept_event()
		# One press per line, then the press that would have been the next line
		# closes instead. Never a timer (CLAUDE.md controller-first law).
		if _index + 1 < _lines.size():
			_index += 1
			_refresh_text()
		else:
			close()

func _on_stage_changed(npc_id: String, _stage: int) -> void:
	if npc_id == _npc_id:
		_spoke = true
		# A stage landed while the box was open: that is the new thing they had
		# to say, so start it from its first line.
		_index = 0
		_refresh()

func _refresh() -> void:
	var def := StoryRegistry.npc(_npc_id)
	_name_label.text = def.display_name.to_upper() if def != null else _npc_id.to_upper()
	_lines = StoryRegistry.npc_lines(_npc_id)
	_index = clampi(_index, 0, maxi(0, _lines.size() - 1))
	_refresh_text()

func _refresh_text() -> void:
	_line.text = _lines[_index] if _index < _lines.size() else ""
	var more := _index + 1 < _lines.size()
	_hint.text = "%s  %s" % [
		ButtonGlyphs.label_for("interact"),
		"go on" if more else ("go on" if _spoke else "leave them to it"),
	]

func _log(line: String) -> void:
	print("%.3f [dialogue] %s" % [Time.get_unix_time_from_system(), line])
