extends Node
## WorldState — the client-side mirror of the authoritative world.
##
## The server (Nakama match) is the source of truth. This singleton holds the
## last-known authoritative snapshot, applies diffs as they arrive, and re-emits
## tidy local signals on EventBus so the rest of the game never has to know the
## network exists. Read from here; never write here directly.

# Mirror of the schema in DESIGN.md §8 / match_handler.ts.
var tide := { "phase": "LOW", "t": 0.0, "cycle": 0, "storm": false }
var flags: Dictionary = {}        # flag -> bool
var inventory: Dictionary = {}    # item_id -> int
var milestones: Dictionary = {}   # milestone_id -> "todo"|"in_progress"|"done"
## node_id -> is there anything there to pick up. Authoritative: a node only
## empties or restocks because the server said so, never because we took it.
var nodes: Dictionary = {}
var presence: Dictionary = {}     # keeper_id -> bool
## slot -> ms of slow walk left when the message arrived. Transient: the world
## never remembers that somebody got wet, it only knows they are wet now.
var caught: Dictionary = {}

## Called by Net when an authoritative diff arrives. A diff may contain any
## subset of keys; we apply only what's present and emit granular signals.
func apply_diff(diff: Dictionary) -> void:
	if diff.has("tide"):
		var old_phase: String = tide.get("phase", "")
		tide.merge(diff["tide"], true)
		# Progress fires on every update; tide_changed stays the "the phase
		# flipped" signal that gameplay reacts to.
		EventBus.tide_progressed.emit(
			tide.get("phase", ""), tide.get("t", 0.0), int(tide.get("cycle", 0))
		)
		if tide.get("phase", "") != old_phase:
			EventBus.tide_changed.emit(tide["phase"], tide.get("t", 0.0))

	if diff.has("inventory"):
		# Apply the WHOLE diff before telling anyone about any of it. A craft
		# arrives as one message carrying both the spend and the gain; emitting as
		# we went would let a listener read a basket that had paid for a patch kit
		# it had not been handed yet.
		var touched: Array = []
		for item_id in diff["inventory"]:
			inventory[item_id] = diff["inventory"][item_id]
			touched.append(item_id)
		var batch: Dictionary = {}
		for item_id in touched:
			batch[item_id] = inventory[item_id]
		if not batch.is_empty():
			EventBus.inventory_batch_applied.emit(batch)
		for item_id in touched:
			EventBus.inventory_changed.emit(item_id, inventory[item_id])

	if diff.has("flags"):
		for f in diff["flags"]:
			flags[f] = diff["flags"][f]
			EventBus.flag_changed.emit(f, flags[f])
			if f == "lamp_lit" and flags[f] == true:
				EventBus.lamp_lit.emit()   # the climax

	if diff.has("nodes"):
		for node_id in diff["nodes"]:
			nodes[node_id] = bool(diff["nodes"][node_id])
			EventBus.node_changed.emit(node_id, nodes[node_id])

	if diff.has("milestones"):
		for m in diff["milestones"]:
			milestones[m] = diff["milestones"][m]
			EventBus.milestone_changed.emit(m, milestones[m])

	if diff.has("presence"):
		for k in diff["presence"]:
			presence[k] = diff["presence"][k]
			EventBus.keeper_presence_changed.emit(k, presence[k])

	if diff.has("caught"):
		for slot in diff["caught"]:
			var remaining_ms: int = int(diff["caught"][slot])
			if remaining_ms > 0:
				caught[slot] = remaining_ms
				EventBus.keeper_caught.emit(slot, float(remaining_ms) / 1000.0)
			else:
				caught.erase(slot)
				EventBus.keeper_released.emit(slot)

# --- read helpers ---
func has_flag(flag: String) -> bool:
	return flags.get(flag, false) == true

func node_ready(node_id: String) -> bool:
	return nodes.get(node_id, true) == true

func count(item_id: String) -> int:
	return int(inventory.get(item_id, 0))

func can_afford(costs: Dictionary) -> bool:
	for item_id in costs:
		if count(item_id) < int(costs[item_id]):
			return false
	return true
