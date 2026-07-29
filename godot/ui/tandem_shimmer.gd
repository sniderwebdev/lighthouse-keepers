extends CanvasLayer
class_name TandemShimmer
## "Waiting for your keeper."
##
## One of you has reached for the crank and the other has not. This is an
## invitation, not an error: it names who is being waited on and it fades on its
## own, because the window closes and nothing is lost if it does.
##
## In couch play both slots are on one screen, so the line names the slot rather
## than saying "the other player" — on the couch that would be meaningless.

## Matches the server's TANDEM_WINDOW_MS. Shown a touch shorter so the shimmer is
## gone before the window it describes has quietly expired.
const WINDOW := 9.0
const PULSE := 1.4

@onready var _label: Label = %Waiting
@onready var _panel: PanelContainer = %Panel

var _time_left := 0.0
var _pulse := 0.0

func _ready() -> void:
	_panel.visible = false
	EventBus.tandem_waiting.connect(_on_tandem_waiting)
	EventBus.lamp_lit.connect(_hide)

func _on_tandem_waiting(_gate_id: String, waiting: PackedStringArray) -> void:
	if waiting.is_empty():
		_hide()
		return
	# Name whoever has not reached yet. On the couch that is the other half of
	# this screen; online it is the other house.
	var names: PackedStringArray = []
	for slot in waiting:
		names.append("keeper A" if slot == Command.SLOT_A else "keeper B")
	_label.text = "waiting for %s" % " and ".join(names)
	_panel.visible = true
	_time_left = WINDOW
	print("%.3f [shimmer] %s" % [Time.get_unix_time_from_system(), _label.text])

func _process(delta: float) -> void:
	if not _panel.visible:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_hide()
		return
	# A slow breath rather than a blink: this is somebody waiting for you, not an
	# alarm going off.
	_pulse += delta
	var t := 0.5 + 0.5 * sin(_pulse * TAU / PULSE)
	_panel.modulate.a = lerpf(0.55, 1.0, t)

func _hide() -> void:
	_panel.visible = false
	_time_left = 0.0
