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
	CRAFT        = 2,   # { "recipe_id": String }              -> consumes inputs, grants output
	PLACE        = 3,   # { "item_id": String, "spot": String }
	ADVANCE_STEP = 4,   # { "milestone_id": String }           -> spends resources, sets flag
	READ_BOTTLE  = 5,   # { "bottle_id": String }              -> sets story flag
	TANDEM       = 6,   # { "gate_id": String, "slot": String } -> fires when BOTH slots submit
	CARRY_ASSIST = 7,   # { "object_id": String, "slot": String }
	LOG_SESSION  = 8,   # { }  -> server assembles keeper's log entry
}

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

static func craft(recipe_id: String) -> Dictionary:
	return make(Op.CRAFT, { "recipe_id": recipe_id })

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
