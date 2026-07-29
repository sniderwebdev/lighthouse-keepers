extends Node
class_name TideClock
## TideClock — presentation only.
##
## The AUTHORITATIVE tide lives in the Nakama match and arrives via WorldState.
## The server sends discrete updates; this node carries t forward between them at
## the same rate the server uses, so the sky changes every frame instead of
## lurching once a broadcast. It never decides the tide: every server message is
## a correction it accepts.
##
## Drives the ambient tint through DuskRamp — which IS the tide UI (DESIGN §2).

signal water_level_changed(level: float)   # 0.0 = lowest, 1.0 = highest
signal ambient_changed(color: Color)       # the sky's colour, on the world
signal phase_changed(phase: String)

## The committed default, mirroring SECONDS_PER_CYCLE in match_handler.ts. What
## is actually in force comes from the world, because the cycle length is a feel
## value a playtest can turn.
const SECONDS_PER_CYCLE := 480.0
## A correction bigger than this is a jump — a join, or a dev tide set — and is
## taken at once rather than eased into.
const SNAP_THRESHOLD := 0.02
const CORRECTION_RATE := 0.5

## Where the water sits through the cycle. LOW is t=0, HIGH is t=0.5.
const LOW_LEVEL := 0.05
const HIGH_LEVEL := 0.95

## Mirror of the server's phase table: four quarters, LOW MID HIGH MID.
const PHASES: PackedStringArray = ["LOW", "MID", "HIGH", "MID"]

@export var apply_to: NodePath      ## optional CanvasModulate to tint

var t := 0.0
var cycle := 0
var phase := "LOW"
var water_level := LOW_LEVEL

var _canvas: CanvasModulate
var _last_ambient := Color(0, 0, 0, 0)

func _ready() -> void:
	if apply_to != NodePath():
		_canvas = get_node_or_null(apply_to) as CanvasModulate
	# Progress, not just phase flips: a correction that only arrives four times a
	# cycle would let this clock free-run for two minutes at a stretch.
	EventBus.tide_progressed.connect(_on_tide_progressed)
	_sync_from_world()
	_apply()

func _sync_from_world() -> void:
	t = float(WorldState.tide.get("t", 0.0))
	cycle = int(WorldState.tide.get("cycle", 0))
	phase = String(WorldState.tide.get("phase", "LOW"))

func _on_tide_progressed(p_phase: String, p_t: float, p_cycle: int) -> void:
	_correct_to(p_t)
	cycle = p_cycle
	if p_phase != phase:
		phase = p_phase
		phase_changed.emit(phase)
	_apply()

func _correct_to(server_t: float) -> void:
	var gap := absf(server_t - t)
	# Across the wrap point the short way round is the other way.
	if gap > 0.5:
		gap = 1.0 - gap
	if gap >= SNAP_THRESHOLD:
		t = server_t
	else:
		t = lerpf(t, server_t, CORRECTION_RATE)

func _process(delta: float) -> void:
	# Carry the tide forward at the server's rate. When nobody is connected the
	# server's clock is paused — and so is this one, because there is no client
	# running to advance it.
	t = fposmod(t + delta / cycle_seconds(), 1.0)

	var next_phase := _phase_for(t)
	if next_phase != phase:
		phase = next_phase
		phase_changed.emit(phase)
	_apply()

## What is in force right now, not what shipped.
func cycle_seconds() -> float:
	return maxf(1.0, float(WorldState.tide.get("cycle_seconds", SECONDS_PER_CYCLE)))

func _phase_for(p_t: float) -> String:
	return PHASES[int(p_t * PHASES.size()) % PHASES.size()]

func _apply() -> void:
	# Water rides a triangle: lowest at t=0, highest at t=0.5.
	var rise := 1.0 - 2.0 * absf(t - 0.5)
	water_level = lerpf(LOW_LEVEL, HIGH_LEVEL, rise)
	water_level_changed.emit(water_level)

	var ambient := DuskRamp.ambient_for(t)
	if ambient != _last_ambient:
		_last_ambient = ambient
		if _canvas != null:
			_canvas.color = ambient
		ambient_changed.emit(ambient)
		EventBus.ambient_changed.emit(ambient)

## Gameplay query: is a shore tile of given height currently submerged?
func is_submerged(tile_height: float) -> bool:
	return water_level >= tile_height
