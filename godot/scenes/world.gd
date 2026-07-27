extends Node2D
## World — the playable room for M1.
##
## Spawns both keeper identities and decides, per slot, whether this client is
## driving it or mirroring it. That decision comes from Net.claimed_slots, which
## the server confirmed — the client never assumes which keepers are its own.
##
## Couch and online differ here in exactly two places: how many keepers are local,
## and what the camera is asked to frame.
##
## Whether a keeper is on screen is the keeper's own business, not the world's —
## it depends on having received a pose, which only the keeper knows about.

const KEEPER_SCENE := preload("res://game/keeper.tscn")
const SHEET_A: Texture2D = preload("res://art/placeholder/keeper_a.png")
const SHEET_B: Texture2D = preload("res://art/placeholder/keeper_b.png")

## Walkable extent, matching the wall colliders in world.tscn.
const ROOM := Rect2(0, 0, 1280, 720)

@onready var _actors: Node2D = %Actors
@onready var _camera: KeeperCamera = %Camera
@onready var _spawn_a: Marker2D = %SpawnA
@onready var _spawn_b: Marker2D = %SpawnB

var _keepers: Dictionary = {}   ## slot -> Keeper
var _trace: FileAccess = null
var _trace_clock := 0.0

func _ready() -> void:
	_spawn_keepers()
	_camera.apply_room_bounds(ROOM)
	_camera.set_targets(_local_keepers())
	_open_trace()

func _spawn_keepers() -> void:
	_spawn(Command.SLOT_A, SHEET_A, _spawn_a.position)
	_spawn(Command.SLOT_B, SHEET_B, _spawn_b.position)

func _spawn(slot: String, sheet: Texture2D, at: Vector2) -> void:
	var keeper: Keeper = KEEPER_SCENE.instantiate()
	keeper.slot = slot
	keeper.sheet = sheet
	keeper.is_local = Net.has_slot(slot)
	keeper.input_prefix = _input_prefix_for(slot)
	keeper.position = at
	keeper.name = slot
	_actors.add_child(keeper)
	_keepers[slot] = keeper

## Device 0 drives the slot you picked at session start; device 1 drives the
## other one, and only exists on the couch (CLAUDE.md controller-first law).
func _input_prefix_for(slot: String) -> String:
	if not Net.is_couch():
		return ""
	return "" if slot == Command.SLOT_A else "p2_"

func _local_keepers() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for slot in [Command.SLOT_A, Command.SLOT_B]:
		var keeper: Keeper = _keepers.get(slot)
		if keeper != null and keeper.is_local:
			out.append(keeper)
	return out

# --- debug trace (milestone verification only) ---

## `--trace=/abs/path.csv` records, every physics frame, where each keeper is and
## what the camera is doing. Per-frame resolution is the point: it is the only
## way to tell interpolation from a 10Hz teleport after the fact.
func _open_trace() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trace="):
			path = arg.split("=", true, 1)[1]
	if path == "":
		return
	_trace = FileAccess.open(path, FileAccess.WRITE)
	if _trace == null:
		push_warning("world: cannot open trace %s" % path)
		return
	_trace.store_line("t,slot,is_local,x,y,cam_x,cam_y,zoom,on_screen")

func _physics_process(delta: float) -> void:
	if _trace == null:
		return
	_trace_clock += delta
	var view := _camera.get_viewport_rect().size / _camera.zoom
	# The camera's own position is where it WANTS to be; near a wall the limits
	# pull the drawn view somewhere else. Measuring the wanted position would
	# quietly pass a keeper who is actually off the edge of the screen.
	var centre := _camera.get_screen_center_position()
	var frame := Rect2(centre - view * 0.5, view)
	for slot in _keepers:
		var keeper: Keeper = _keepers[slot]
		if not keeper.visible:
			continue
		_trace.store_line("%.4f,%s,%d,%.3f,%.3f,%.3f,%.3f,%.4f,%d" % [
			_trace_clock, slot, 1 if keeper.is_local else 0,
			keeper.position.x, keeper.position.y,
			centre.x, centre.y, _camera.zoom.x,
			1 if frame.has_point(keeper.position) else 0,
		])
