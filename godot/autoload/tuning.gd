extends Node
## The four numbers that decide how the game FEELS.
##
## They live here, together, so they can be turned during a playtest by the two
## people playing rather than guessed at by whoever is holding the keyboard.
##
## The Testing law (CLAUDE.md) is what this exists to serve: synthesized-input
## checks prove systems, not feel, and these values are only ever changed for
## real by a logged human playtest. What is written into `DEFAULTS` below is the
## committed answer; `user://tuning.cfg` is one session's experiment and never
## ships.

signal changed(key: String, value: float)

const CONFIG_PATH := "user://tuning.cfg"

## key -> [default, minimum, maximum, step, human label, unit]
const DEFAULTS: Dictionary = {
	"walk_speed": [90.0, 40.0, 200.0, 5.0, "walk speed", "px/s"],
	"camera_smoothing": [6.0, 1.0, 20.0, 0.5, "camera follow", ""],
	"tide_cycle_seconds": [480.0, 60.0, 1200.0, 30.0, "tide cycle", "s"],
	"radial_deadzone": [0.45, 0.15, 0.9, 0.05, "wheel deadzone", ""],
}

var _values: Dictionary = {}

## Flags that mean a harness is driving rather than a person.
const HARNESS_FLAGS: PackedStringArray = [
	"--autowalk", "--ui-selftest", "--tuning-selftest", "--debug-harvest",
]

func _ready() -> void:
	for key in DEFAULTS:
		_values[key] = float(DEFAULTS[key][0])
	# An automated run measures the COMMITTED defaults, never one evening's
	# experiment (CLAUDE.md Testing law). Otherwise a playtest left walk speed at
	# 95 and every timing assertion afterwards is quietly measuring that instead.
	if _harness_is_driving():
		print("%.3f [tuning] harness run: using committed defaults" % Time.get_unix_time_from_system())
		return
	_load()

func _harness_is_driving() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--tuning-persist"):
		return false
	for arg in args:
		for flag in HARNESS_FLAGS:
			if arg == flag or arg.begins_with(flag + "="):
				return true
		if arg.begins_with("--debug-"):
			return true
	return false

func get_value(key: String) -> float:
	return float(_values.get(key, DEFAULTS[key][0] if DEFAULTS.has(key) else 0.0))

func label_for(key: String) -> String:
	return String(DEFAULTS[key][4])

func unit_for(key: String) -> String:
	return String(DEFAULTS[key][5])

func is_default(key: String) -> bool:
	return is_equal_approx(get_value(key), float(DEFAULTS[key][0]))

## Nudge a value by one step, clamped. Everything that reads it picks the change
## up on its next frame, which is what "applies within a second" means here.
func nudge(key: String, direction: int) -> void:
	if not DEFAULTS.has(key):
		return
	var spec: Array = DEFAULTS[key]
	var stepped := get_value(key) + float(spec[3]) * float(direction)
	set_value(key, clampf(stepped, float(spec[1]), float(spec[2])))

func set_value(key: String, value: float) -> void:
	if not DEFAULTS.has(key) or is_equal_approx(get_value(key), value):
		return
	_values[key] = value
	_save()
	changed.emit(key, value)
	print("%.3f [tuning] %s = %s" % [Time.get_unix_time_from_system(), key, _format(key)])

func reset_all() -> void:
	for key in DEFAULTS:
		set_value(key, float(DEFAULTS[key][0]))

## Rendered the way the overlay shows it, so a playtest note and the screen agree.
func _format(key: String) -> String:
	var value := get_value(key)
	var text := ("%.2f" % value) if value < 10.0 else ("%.0f" % value)
	var unit := unit_for(key)
	return text + (" " + unit if unit != "" else "")

func format(key: String) -> String:
	return _format(key)

## Every value, as a single line for a playtest log entry.
func summary() -> String:
	var parts: PackedStringArray = []
	for key in DEFAULTS:
		parts.append("%s %s" % [label_for(key), _format(key)])
	return " · ".join(parts)

# --- persistence ---

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	for key in DEFAULTS:
		if cfg.has_section_key("tuning", key):
			var spec: Array = DEFAULTS[key]
			_values[key] = clampf(float(cfg.get_value("tuning", key)), float(spec[1]), float(spec[2]))
	print("%.3f [tuning] loaded: %s" % [Time.get_unix_time_from_system(), summary()])

func _save() -> void:
	var cfg := ConfigFile.new()
	for key in DEFAULTS:
		cfg.set_value("tuning", key, get_value(key))
	cfg.save(CONFIG_PATH)
