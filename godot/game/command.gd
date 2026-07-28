extends RefCounted
class_name Command
## Command — the serializable INTENT a client sends to the authoritative match.
##
## This is the heart of the co-op architecture. A client never mutates shared
## state directly. It builds a Command, sends it (Net.send_command), and the
## Nakama match validates + applies + broadcasts the result. Keep these opcodes
## and payload shapes IN SYNC with nakama/match_handler.ts.

# Opcodes — must match OP.* in match_handler.ts exactly.
enum Op {
	GATHER       = 1,   # { "node_id": String }                -> grants item(s)
	CRAFT        = 2,   # { "recipe_id": String, "station": String } -> consumes, grants
	PLACE        = 3,   # { "item_id": String, "spot": String }
	ADVANCE_STEP = 4,   # { "milestone_id": String }           -> spends resources, sets flag
	READ_BOTTLE  = 5,   # { "bottle_id": String }              -> sets story flag
	TANDEM       = 6,   # { "gate_id": String, "slot": String } -> fires when BOTH slots submit
	CARRY_ASSIST = 7,   # { "object_id": String, "slot": String }
	LOG_SESSION  = 8,   # { }  -> server assembles keeper's log entry
	CAUGHT       = 9,   # { "slot": String, "zone": String } -> wade home, slow a while
}

## Non-command opcodes. These are not intents and the server does not validate,
## apply, or persist them — they are kept here so the whole opcode registry lives
## in one file, mirrored in match_handler.ts.
##
## POSE is the presentation channel: where a keeper *appears* to be. Positions
## are cosmetic mirroring, not authoritative shared state (PLAN.md M1), so they
## deliberately bypass WorldState. If you ever need a position the world can be
## held to — a milestone, a gate, a spawn — that is a Command, not a pose.
const OP_POSE := 20        # client -> server: { "slot", "x", "y", "f", "t", "r" }
const OP_POSE_ECHO := 120  # server -> clients: { "poses": { slot: {x,y,f,t,r} } }
const OP_STATE_DIFF := 100 # server -> clients: the authoritative diff

## Keeper slots. In couch mode one client drives both; every slot-sensitive
## command carries which keeper acted. In online mode the server can derive it,
## but sending it explicitly keeps both modes identical.
const SLOT_A := "keeper_a"
const SLOT_B := "keeper_b"

## Build the {op, payload} dict that goes over the wire.
static func make(op: Op, payload: Dictionary = {}) -> Dictionary:
	return { "op": int(op), "data": payload }

# Convenience constructors (typed call sites > magic dicts).
static func gather(node_id: String) -> Dictionary:
	return make(Op.GATHER, { "node_id": node_id })

## The station is part of the intent: the same recipe is a different act at the
## stove than at the bench, and the server checks you were at the right one.
static func craft(recipe_id: String, station: String) -> Dictionary:
	return make(Op.CRAFT, { "recipe_id": recipe_id, "station": station })

static func advance_step(milestone_id: String) -> Dictionary:
	return make(Op.ADVANCE_STEP, { "milestone_id": milestone_id })

static func read_bottle(bottle_id: String) -> Dictionary:
	return make(Op.READ_BOTTLE, { "bottle_id": bottle_id })

static func tandem(gate_id: String, slot: String) -> Dictionary:
	return make(Op.TANDEM, { "gate_id": gate_id, "slot": slot })

static func carry_assist(object_id: String, slot: String) -> Dictionary:
	return make(Op.CARRY_ASSIST, { "object_id": object_id, "slot": slot })

static func log_session() -> Dictionary:
	return make(Op.LOG_SESSION, {})

## "The water reached me." A report, not an assertion: the client knows where it
## is standing, but only the server knows whether that ground is under water, and
## only the server decides what happens next.
static func caught(slot: String, zone: String) -> Dictionary:
	return make(Op.CAUGHT, { "slot": slot, "zone": zone })

## Presentation, not a command — see OP_POSE. Sent on its own opcode so it can
## never be mistaken for something the world is held to.
##
## `t` is the SENDER's millisecond clock, relayed untouched. The receiver only
## ever takes differences within one sender's stream, so the offset between the
## two machines' clocks cancels out and nothing has to be synchronised. Without
## it the receiver would have to time samples by arrival, which measures the
## network's jitter rather than the keeper's movement.
## `r` is which room they are standing in. Still presentation: it decides whether
## to DRAW the other keeper, not whether they exist. A keeper on the beach and a
## keeper in the tower are both entirely present in the world.
static func pose(slot: String, pos: Vector2, facing: int, room: String) -> Dictionary:
	return { "op": OP_POSE, "data": {
		"slot": slot, "x": pos.x, "y": pos.y, "f": facing,
		"t": Time.get_ticks_msec(), "r": room,
	} }
