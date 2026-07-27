extends Node
class_name TideClock
## TideClock — presentation only.
##
## The AUTHORITATIVE tide lives in the Nakama match and arrives via WorldState
## (phase + normalized t + cycle length). The server only sends discrete updates;
## this node interpolates between them every frame so the water animates smoothly
## and shore colliders open/close at the right moment. It never decides the tide.
##
## Attach to your shore scene. Drive water visuals from `water_level` (0..1).

signal water_level_changed(level: float)   # 0.0 = lowest, 1.0 = highest

@export var seconds_per_cycle := 480.0      # mirror the match's cycle length

var water_level := 0.0
var _phase := "LOW"
var _phase_t := 0.0      # 0..1 progress through current phase, from server

# Target water level per phase (LOW lowest -> HIGH highest); STORM rides high.
const PHASE_LEVEL := {
	"LOW": 0.05, "MID": 0.5, "HIGH": 0.95, "STORM": 1.0
}

func _ready() -> void:
	EventBus.tide_changed.connect(_on_tide_changed)
	_sync_from_world()

func _sync_from_world() -> void:
	_phase = WorldState.tide.get("phase", "LOW")
	_phase_t = WorldState.tide.get("t", 0.0)

func _on_tide_changed(phase: String, t: float) -> void:
	_phase = phase
	_phase_t = t

func _process(delta: float) -> void:
	# Smoothly chase the authoritative target. Server corrections snap us back if
	# we drift; between them we just ease toward the phase's target level.
	var target: float = PHASE_LEVEL.get(_phase, 0.5)
	water_level = lerp(water_level, target, clamp(delta * 1.5, 0.0, 1.0))
	water_level_changed.emit(water_level)

## Gameplay query: is a shore tile of given height currently submerged?
func is_submerged(tile_height: float) -> bool:
	return water_level >= tile_height
