extends CanvasLayer
class_name RelightBeat
## The moment the light comes back.
##
## Act One's climax, and the one thing in it that needed both of you. It plays
## off the authoritative `lamp_lit` flag, so it happens on both screens because
## the world said so — not because either client decided it had earned it.
##
## Warm floods everything here, which is the one place in the game that is
## allowed: this IS the light source (DESIGN §6).

const FLOOD_IN := 1.0
const HOLD := 1.6
const SWEEPS := 2
const SWEEP_TIME := 1.8

@onready var _flood: ColorRect = %Flood
@onready var _beam: ColorRect = %Beam
@onready var _closing: Label = %Closing

var _played := false

func _ready() -> void:
	_flood.modulate.a = 0.0
	_beam.modulate.a = 0.0
	_closing.modulate.a = 0.0
	visible = false
	EventBus.lamp_lit.connect(_play)
	# A keeper joining a world where the lamp is already lit should not sit
	# through the ending again.
	if WorldState.has_flag("lamp_lit"):
		_played = true

func _play() -> void:
	if _played:
		return
	_played = true
	visible = true
	print("%.3f [relight] the lamp is lit" % Time.get_unix_time_from_system())

	var beat := create_tween()
	beat.set_parallel(false)
	# The room floods first — you feel it before you see where it went.
	beat.tween_property(_flood, "modulate:a", 1.0, FLOOD_IN).set_trans(Tween.TRANS_SINE)
	beat.tween_property(_flood, "modulate:a", 0.35, 0.6).set_trans(Tween.TRANS_SINE)

	# Then the beam goes out over the water, twice, the way it will every night
	# from now on.
	beat.tween_callback(func() -> void: _beam.modulate.a = 1.0)
	for i in SWEEPS:
		beat.tween_property(_beam, "position:x", 640.0, SWEEP_TIME).from(-260.0) \
			.set_trans(Tween.TRANS_SINE)
	beat.tween_property(_beam, "modulate:a", 0.0, 0.5)

	# The closing words are the author's — this one is written to her.
	beat.tween_callback(func() -> void: _closing.text = "TODO_CONTENT_closing")
	beat.tween_property(_closing, "modulate:a", 1.0, 0.8)
	beat.tween_interval(HOLD)
	beat.tween_property(_closing, "modulate:a", 0.0, 0.8)
	beat.tween_property(_flood, "modulate:a", 0.0, 1.0)
	beat.tween_callback(func() -> void:
		visible = false
		print("%.3f [relight] beat complete" % Time.get_unix_time_from_system())
	)
