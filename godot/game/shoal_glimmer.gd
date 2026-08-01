extends Node2D
class_name ShoalGlimmer
## The light out past the shoal, answering.
##
## CONTENT.md, bottle_2: "Three flashes. A pause, long as a held breath. Three
## more." Elio charted it and rowed out to it. This is the thing he saw, put
## where the letter says it is — and it does not exist until you have read the
## letter, because a light in the water is only a signal to somebody who has
## been told to watch for one.
##
## PURELY PRESENTATIONAL. It reads WorldState and the tide and draws; it never
## sends a command and never writes shared state. Nothing about the world
## changes because you did or did not see it. That is deliberate: Act 2 is where
## the wreck becomes somewhere you can go.

## The letter that teaches you to watch. Set by READ_BOTTLE on the server.
const REQUIRES_FLAG := "read_bottle_02"

## "It only speaks on the low tide." — bottle_2.
const SPEAKS_IN_PHASE := "LOW"

## Three flashes, a pause, three more, then a long dark. Each entry is a span in
## seconds; they alternate lit / dark starting lit, so the shape of the signal is
## legible here as a shape rather than as a state machine.
##
## FEEL VALUES. Nobody has watched this at a real tide yet, so these are a first
## guess at "slow enough to count" and are the author's to change from a logged
## playtest (CLAUDE.md Testing law) — not from an automated run.
const PATTERN: PackedFloat32Array = [
	0.5, 0.7, 0.5, 0.7, 0.5, 1.8,   # three, then the held breath
	0.5, 0.7, 0.5, 0.7, 0.5, 6.0,   # three more, then the long dark
]

## Warm, because it is a light source and a story object — both halves of the
## warm/cool law (DESIGN §6). The golden end of the locked dusk ramp.
const C_CORE := Color("#f2ae80")
const C_HALO := Color("#d98d78")

const CORE_RADIUS := 2.0
const HALO_RADIUS := 4.0

var _armed := false
var _phase := ""
var _step := 0
var _elapsed := 0.0
## How many lit spans have gone by in this repetition — what a keeper counting
## from the yard would have counted.
var _flashes := 0

func _ready() -> void:
	EventBus.tide_changed.connect(_on_tide_changed)
	EventBus.flag_changed.connect(_on_flag_changed)
	_armed = WorldState.has_flag(REQUIRES_FLAG)
	# EventBus.tide_changed only fires when the phase FLIPS, and the join snapshot
	# flips it from nothing to LOW before this scene exists. Waiting for the next
	# flip would mean the glimmer stayed dark for up to a quarter of a cycle in
	# the world it is most likely to be watched in — a fresh one, at low water.
	# Same reasoning as beach.gd stating its opening phase explicitly.
	_phase = String(WorldState.tide.get("phase", ""))
	_reset()
	_refresh()

func _on_flag_changed(flag: String, value: bool) -> void:
	if flag != REQUIRES_FLAG:
		return
	_armed = value
	# Start the signal from its beginning, so the first thing you ever see it do
	# is the first of three and not the tail of somebody else's pause.
	_reset()
	_refresh()

func _on_tide_changed(phase: String, _t: float) -> void:
	if phase == _phase:
		return
	_phase = phase
	_reset()
	_refresh()

func _reset() -> void:
	_step = 0
	_elapsed = 0.0
	_flashes = 0

## Watching is allowed when you have been told to watch and the water is low.
func _watching() -> bool:
	return _armed and _phase == SPEAKS_IN_PHASE

func _refresh() -> void:
	visible = _watching()
	set_process(visible)
	queue_redraw()
	print("%.3f [glimmer] %s (flag=%s phase=%s)" % [
		Time.get_unix_time_from_system(),
		"watching" if visible else "dark",
		"set" if _armed else "unset", _phase if _phase != "" else "?",
	])

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < PATTERN[_step]:
		return
	_elapsed -= PATTERN[_step]
	var was_lit := _is_lit()
	_step = (_step + 1) % PATTERN.size()
	if was_lit:
		_flashes += 1
		print("%.3f [glimmer] flash %d of %d" % [
			Time.get_unix_time_from_system(), _flashes, _lit_spans(),
		])
	if _step == 0:
		_flashes = 0
	queue_redraw()

## Even indices are the lit spans — see PATTERN.
func _is_lit() -> bool:
	return _step % 2 == 0

func _lit_spans() -> int:
	return PATTERN.size() / 2

func _draw() -> void:
	if not _is_lit():
		return
	# Two flat discs, not a gradient: the dither law (CLAUDE.md rendering) has no
	# exception for light, and a banded glow is what the rest of the game does.
	draw_circle(Vector2.ZERO, HALO_RADIUS, C_HALO)
	draw_circle(Vector2.ZERO, CORE_RADIUS, C_CORE)
