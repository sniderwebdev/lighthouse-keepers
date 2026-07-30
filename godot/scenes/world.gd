extends Node2D
class_name PlayableWorld
## The base every playable space is built on — the plain test room of M1 and the
## tide-governed beach of M2 both run this.
##
## Spawns both keeper identities and decides, per slot, whether this client is
## driving it or mirroring it. That decision comes from Net.claimed_slots, which
## the server confirmed — the client never assumes which keepers are its own.
##
## Couch and online differ here in exactly two places: how many keepers are local,
## and what the camera is asked to frame.
##
## In couch play the second keeper may not have a person behind it yet, so this
## watches the second input set and asks the match for the slot when somebody
## touches it (CLAIM). Until then that keeper is a mirror of nobody and stays
## off screen, exactly as a not-yet-connected online partner does.
##
## Whether a keeper is on screen is the keeper's own business, not the world's —
## it depends on having received a pose, which only the keeper knows about.

const KEEPER_SCENE := preload("res://game/keeper.tscn")
const SHEET_A: Texture2D = preload("res://art/placeholder/keeper_a.png")
const SHEET_B: Texture2D = preload("res://art/placeholder/keeper_b.png")

## Walkable extent, matching this scene's wall colliders.
@export var room := Rect2(0, 0, 1280, 720)
## Which place this is. Carried on every pose so the other keeper's screen knows
## whether to draw you (presentation only — the world does not care where you are).
@export var room_id := "beach"
## Where keepers stand when they arrive through a door, if they came through one.
@export var arrival: NodePath

@onready var _actors: Node2D = %Actors
@onready var _camera: KeeperCamera = %Camera
@onready var _spawn_a: Marker2D = %SpawnA
@onready var _spawn_b: Marker2D = %SpawnB
## Where the world puts a keeper down when it has to move them somewhere safe.
@onready var _safe_return: Marker2D = %SafeReturn

## Set by the session when a scene swap came from walking through a door rather
## than from joining. Static because it has to survive the scene being replaced.
static var entered_by_door := false

## Actions on the second input set. Any of them is somebody saying "I'm here".
const DROPIN_ACTIONS: PackedStringArray = [
	"p2_move_left", "p2_move_right", "p2_move_up", "p2_move_down",
	"p2_interact", "p2_use_tool", "p2_menu_radial",
]

var _keepers: Dictionary = {}   ## slot -> Keeper
## Seconds to wait before asking again. A CLAIM can be refused (the other keeper
## is someone else's, online), and a refusal is silent by design — so this is a
## cooldown rather than a latch, or one refusal would mean never asking again
## even after that player leaves.
const DROPIN_RETRY := 2.0
var _dropin_cooldown := 0.0
var _modal_open := false
var _trace: FileAccess = null
var _trace_clock := 0.0

func _ready() -> void:
	_spawn_keepers()
	_camera.apply_room_bounds(room)
	_camera.set_targets(_local_keepers())
	EventBus.net_slots_claimed.connect(_on_slots_claimed)
	EventBus.ui_modal_changed.connect(_on_ui_modal_changed)
	_open_trace()

func _process(delta: float) -> void:
	_dropin_cooldown = maxf(0.0, _dropin_cooldown - delta)
	_watch_for_second_player()

## `p2_cancel` and `p2_menu_pause` are deliberately NOT drop-in triggers, and
## nothing counts while a menu is open: on a keyboard the second input set shares
## keys with menu navigation, so player one paging through the pause menu with the
## arrows must not silently conscript a second keeper.
func _watch_for_second_player() -> void:
	if _dropin_cooldown > 0.0 or _modal_open:
		return
	var slot := Net.unclaimed_slot()
	if slot == "":
		return
	for action in DROPIN_ACTIONS:
		if Input.is_action_just_pressed(action):
			_dropin_cooldown = DROPIN_RETRY
			print("%.3f [dropin] second player pressed %s, claiming %s" % [
				Time.get_unix_time_from_system(), action, slot,
			])
			Net.send_claim(slot)
			return

func _on_ui_modal_changed(open: bool) -> void:
	_modal_open = open

## The match granted a slot. If it is one we were mirroring, it has a person
## behind it now — hand it its input set and put it on screen.
func _on_slots_claimed(_slots: PackedStringArray) -> void:
	_dropin_cooldown = 0.0
	for slot in [Command.SLOT_A, Command.SLOT_B]:
		var keeper: Keeper = _keepers.get(slot)
		if keeper == null or keeper.is_local or not Net.has_slot(slot):
			continue
		keeper.position = _spawn_for(slot)
		keeper.become_local(_input_prefix_for(slot))
		print("%.3f [dropin] %s is local now (input %s)" % [
			Time.get_unix_time_from_system(), slot,
			"pad 2 / arrows" if keeper.input_prefix == "p2_" else "pad 1 / WASD",
		])
	_camera.set_targets(_local_keepers())

## Where a keeper belongs when the world has to place it: just inside the door if
## we walked in, otherwise this scene's opening spawn. Used both at _ready and
## when a drop-in keeper first appears.
func _spawn_for(slot: String) -> Vector2:
	var door := get_node_or_null(arrival) as Node2D
	if door != null and PlayableWorld.entered_by_door:
		return door.position + (Vector2.ZERO if slot == Command.SLOT_A else Vector2(24, 0))
	return _spawn_a.position if slot == Command.SLOT_A else _spawn_b.position

func _spawn_keepers() -> void:
	# Arriving through a door puts you just inside it, not back at the world's
	# opening spawn.
	_spawn(Command.SLOT_A, SHEET_A, _spawn_for(Command.SLOT_A))
	_spawn(Command.SLOT_B, SHEET_B, _spawn_for(Command.SLOT_B))

func _spawn(slot: String, sheet: Texture2D, at: Vector2) -> void:
	var keeper: Keeper = KEEPER_SCENE.instantiate()
	keeper.slot = slot
	keeper.sheet = sheet
	keeper.is_local = Net.has_slot(slot)
	keeper.input_prefix = _input_prefix_for(slot)
	keeper.room = room_id
	keeper.position = at
	keeper.name = slot
	_actors.add_child(keeper)
	# Only meaningful once both nodes share a tree — a relative path between an
	# orphan and a node in the scene has no common parent to be relative to.
	keeper.safe_return = keeper.get_path_to(_safe_return)
	_keepers[slot] = keeper

## Device 0 drives the slot you picked at session start; device 1 drives the
## other one, and only exists on the couch (CLAUDE.md controller-first law).
##
## Keyed off the SLOT, not off how many slots are claimed, so it gives the same
## answer before and after a drop-in — a machine expecting a second player has
## already reserved the second input set for them.
func _input_prefix_for(slot: String) -> String:
	if not Net.is_couch() and not Net.couch_dropin:
		return ""
	return "" if slot == Command.SLOT_A else "p2_"

func keeper_for(slot: String) -> Keeper:
	return _keepers.get(slot)

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
