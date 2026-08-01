extends Node
## The whole mixer. Four buses, three beds, ten one-shots, one dusk theme.
##
## PLAN M10 says keep it small and use no middleware, so this is the entire audio
## system: it owns the bus volumes, crossfades an ambience bed when the tide or
## the room changes, plays a looping theme, and fires one-shots off EventBus.
##
## It reads the world and never writes it. Sound is presentation — the same law
## the poses and the sky ramp live under — so nothing in here is a Command and
## nothing here can disagree with the server about what happened.
##
## MISSING FILES ARE NOT ERRORS. Every slot here is a placeholder somebody is
## expected to replace (ASSET_MANIFEST.md), and a half-finished swap should make
## the game quieter, never broken.

signal volumes_changed()

const CONFIG_PATH := "user://audio.cfg"

## Bus name -> its default linear volume, 0..1. These are MIX values, not feel
## values: they have sliders of their own and are exempt from the playtest gate
## (NEXT.md 2026-07-31.2 item 5). Music sits under ambience on purpose.
const DEFAULTS: Dictionary = {
	"Master": 0.85,
	"Ambience": 0.75,
	"Music": 0.55,
	"SFX": 0.80,
}
## Slider order, which is also focus order in the settings panel.
const BUSES: PackedStringArray = ["Master", "Ambience", "Music", "SFX"]

const BED_DIR := "res://assets/audio/ambience"
const SFX_DIR := "res://assets/audio/sfx"
const MUSIC_PATH := "res://assets/audio/music/dusk_theme.ogg"

## How long a bed takes to hand over. Long enough that a phase flip feels like
## weather rather than a cut; short enough that walking indoors is not a wait.
const CROSSFADE_SECONDS := 1.6

## Enough voices that a busy moment does not cut its own tail off, few enough
## that nothing can pile up into a wall.
const SFX_VOICES := 8

var _beds: Dictionary = {}          ## bed name -> AudioStreamPlayer
var _bed_wanted := ""
var _music: AudioStreamPlayer
var _sfx: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _volumes: Dictionary = {}
var _phase := "LOW"
var _room := "beach"

func _ready() -> void:
	for key in DEFAULTS:
		_volumes[key] = float(DEFAULTS[key])
	_load()
	_build_players()
	_apply_all_volumes()

	EventBus.tide_changed.connect(_on_tide_changed)
	EventBus.room_changed.connect(_on_room_changed)
	EventBus.flag_changed.connect(_on_flag_changed)
	# One-shots that already have a signal of their own are taken straight off it
	# rather than given a second announcement to keep in step.
	EventBus.node_changed.connect(_on_node_changed)
	EventBus.milestone_changed.connect(_on_milestone_changed)
	EventBus.keeper_caught.connect(func(_slot: String, _s: float) -> void: play("caught"))
	EventBus.lamp_lit.connect(func() -> void: play("beam"))
	EventBus.tandem_waiting.connect(_on_tandem_waiting)
	# ...and the rest are asked for explicitly, because no existing signal means
	# exactly "a page turned" without also meaning three other things.
	EventBus.sfx_requested.connect(play)

	_refresh_bed()
	_start_music()

# --- players ---------------------------------------------------------------

func _build_players() -> void:
	for name in ["sea", "wind", "hearth"]:
		var p := AudioStreamPlayer.new()
		p.bus = "Ambience"
		p.stream = _load_looping("%s/%s.wav" % [BED_DIR, name])
		p.volume_db = -80.0
		add_child(p)
		_beds[name] = p
		if p.stream != null:
			p.play()

	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)

	for i in SFX_VOICES:
		var s := AudioStreamPlayer.new()
		s.bus = "SFX"
		add_child(s)
		_sfx.append(s)

## Beds have to loop, and a WAV does not say so on its own — the import defaults
## to one-shot, which would give you twelve seconds of sea and then a silent
## beach. Set on the stream rather than in an .import file so a replacement
## dropped in by hand loops too, without anybody having to know that.
func _load_looping(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("audio: no bed at %s (staying quiet)" % path)
		return null
	var stream := load(path)
	var wav := stream as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = 0
	return stream

# --- ambience ---------------------------------------------------------------

func _on_tide_changed(phase: String, _t: float) -> void:
	_phase = phase
	_refresh_bed()

func _on_room_changed(room: String) -> void:
	_room = room
	_refresh_bed()

func _on_flag_changed(flag: String, _value: bool) -> void:
	# The hearth bed is the fire, so it only exists once there is one.
	if flag == "hearth_lit":
		_refresh_bed()

## Which bed the world is asking for. Inside the tower with the fire lit you hear
## the fire; outside, the tide decides. STORM counts as wind, loudly.
func _wanted_bed() -> String:
	if _room == "tower":
		return "hearth" if WorldState.has_flag("hearth_lit") else "wind"
	return "sea" if _phase == "LOW" else "wind"

func _refresh_bed() -> void:
	var wanted := _wanted_bed()
	if wanted == _bed_wanted:
		return
	_bed_wanted = wanted
	print("%.3f [audio] bed -> %s (phase=%s room=%s)" % [
		Time.get_unix_time_from_system(), wanted, _phase, _room,
	])
	for name in _beds:
		var player: AudioStreamPlayer = _beds[name]
		if player.stream == null:
			continue
		var target := 0.0 if name == wanted else -80.0
		var tween := create_tween()
		tween.tween_property(player, "volume_db", target, CROSSFADE_SECONDS)

# --- music ------------------------------------------------------------------

## One dusk theme, on a loop, forever. The author's decision (NEXT.md
## 2026-07-31.2): not none, not one per act. Swapping it is replacing the file at
## MUSIC_PATH — nothing here knows anything about the track but where it lives.
func _start_music() -> void:
	if not ResourceLoader.exists(MUSIC_PATH):
		print("%.3f [audio] no music at %s (silent)" % [
			Time.get_unix_time_from_system(), MUSIC_PATH,
		])
		return
	var stream := load(MUSIC_PATH)
	var vorbis := stream as AudioStreamOggVorbis
	if vorbis != null:
		vorbis.loop = true
	_music.stream = stream
	_music.play()
	print("%.3f [audio] music playing: %s" % [Time.get_unix_time_from_system(), MUSIC_PATH])

# --- one-shots --------------------------------------------------------------

func _on_node_changed(_node_id: String, ready_now: bool) -> void:
	# A node going away under you is somebody picking it up.
	if not ready_now:
		play("gather")

func _on_milestone_changed(_milestone_id: String, status: String) -> void:
	if status == "done":
		play("milestone")

func _on_tandem_waiting(_gate_id: String, waiting: PackedStringArray) -> void:
	if waiting.size() == 1:
		play("tandem_ready")

func play(id: String) -> void:
	var path := "%s/%s.wav" % [SFX_DIR, id]
	if not ResourceLoader.exists(path):
		push_warning("audio: no sfx '%s'" % id)
		return
	# Round-robin the voices. Stealing the oldest is better than refusing to
	# speak: a dropped tick is invisible, a missing milestone chime is not.
	var voice := _sfx[_next_voice]
	_next_voice = (_next_voice + 1) % _sfx.size()
	voice.stream = load(path)
	voice.play()
	print("%.3f [audio] sfx %s" % [Time.get_unix_time_from_system(), id])

# --- volumes ----------------------------------------------------------------

func get_volume(bus: String) -> float:
	return float(_volumes.get(bus, DEFAULTS.get(bus, 1.0)))

func set_volume(bus: String, value: float) -> void:
	if not DEFAULTS.has(bus):
		return
	var clamped := clampf(value, 0.0, 1.0)
	if is_equal_approx(get_volume(bus), clamped):
		return
	_volumes[bus] = clamped
	_apply_volume(bus)
	_save()
	volumes_changed.emit()
	print("%.3f [audio] bus %s = %.2f" % [Time.get_unix_time_from_system(), bus, clamped])

func _apply_volume(bus: String) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var v := get_volume(bus)
	# Silence is a real setting, and linear_to_db(0) is negative infinity.
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))

func _apply_all_volumes() -> void:
	for bus in DEFAULTS:
		_apply_volume(bus)

func summary() -> String:
	var parts: PackedStringArray = []
	for bus in BUSES:
		parts.append("%s %d%%" % [bus, roundi(get_volume(bus) * 100.0)])
	return " · ".join(parts)

# --- persistence ------------------------------------------------------------

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	for bus in DEFAULTS:
		if cfg.has_section_key("audio", bus):
			_volumes[bus] = clampf(float(cfg.get_value("audio", bus)), 0.0, 1.0)
	print("%.3f [audio] loaded: %s" % [Time.get_unix_time_from_system(), summary()])

func _save() -> void:
	var cfg := ConfigFile.new()
	for bus in DEFAULTS:
		cfg.set_value("audio", bus, get_volume(bus))
	cfg.save(CONFIG_PATH)
