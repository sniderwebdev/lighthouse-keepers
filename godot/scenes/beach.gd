extends PlayableWorld
## The tide-governed shore.
##
## Everything the beach adds on top of a plain room is the tide: the ambient
## light, which IS the clock (DESIGN §2), and three zones the sea takes back in
## turn. The zones are told the phase and decide for themselves whether to raise
## a barrier and who is standing in the water.

@onready var _tide: TideClock = %TideClock
@onready var _zones: Node2D = %Zones

func _ready() -> void:
	super()
	_tide.phase_changed.connect(_on_phase_changed)
	_tide.ambient_changed.connect(_on_ambient_changed)
	# The tide is already at some phase when we arrive — a keeper joining at high
	# water should find the beach closed, not open until the next flip.
	_on_phase_changed(_tide.phase)
	# TideClock emits its first ambient in its own _ready, before this node has
	# had a chance to connect, so state the opening value explicitly.
	_on_ambient_changed(DuskRamp.ambient_for(_tide.t))

func _on_phase_changed(phase: String) -> void:
	var closed: PackedStringArray = []
	for child in _zones.get_children():
		var zone := child as ShoreZone
		if zone != null:
			zone.set_phase(phase)
			if not zone.is_open:
				closed.append(zone.zone_id)
	print("%.3f [beach] phase=%s t=%.4f under_water=[%s]" % [
		Time.get_unix_time_from_system(), phase, _tide.t, ", ".join(closed),
	])

## The sky is the only tide readout there is, so its every step is worth saying
## out loud in a headless run.
func _on_ambient_changed(color: Color) -> void:
	print("%.3f [beach] ambient t=%.4f step=%d rgb=%.3f,%.3f,%.3f v=%.3f" % [
		Time.get_unix_time_from_system(), _tide.t, DuskRamp.index_for(_tide.t),
		color.r, color.g, color.b, maxf(color.r, maxf(color.g, color.b)),
	])
