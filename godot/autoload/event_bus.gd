extends Node
## EventBus — the decoupled nervous system.
##
## Local, in-process signals only. Systems emit/listen here instead of holding
## references to each other. NOTHING here crosses the network — anything that
## changes shared world state must go through Net.send_command() instead (see net.gd).
##
## Rule of thumb:
##   - "I want to DO something to the shared world"  -> Net.send_command(...)
##   - "the world told me something CHANGED"         -> WorldState applies it, then
##                                                       re-emits a local signal here
##   - "purely cosmetic / UI / audio reaction"       -> emit here directly

# --- World-state echoes (emitted by WorldState after it applies an authoritative diff) ---
signal tide_changed(phase: String, t: float)
## Every authoritative tide update, phase flip or not. The sky IS the tide clock
## (DESIGN §2), so it has to hear the quiet progress between flips too —
## listening only for phase changes leaves it free-running for minutes at a time.
signal tide_progressed(phase: String, t: float, cycle: int)
signal inventory_changed(item_id: String, new_count: int)
## One authoritative diff's worth of inventory change, together. A craft spends
## and grants in a single message, and anything that wants to react to THAT —
## an animation, a sound, a test asserting nothing was ever half-done — needs the
## batch rather than three unrelated-looking events.
signal inventory_batch_applied(changed: Dictionary)
signal flag_changed(flag: String, value: bool)
signal milestone_changed(milestone_id: String, status: String)
## A resource node emptied (false) or the sea restocked it (true).
signal node_changed(node_id: String, ready: bool)
## A bottle washed in ("washed_up") or was read ("read").
signal bottle_changed(bottle_id: String, state: String)
signal npc_stage_changed(npc_id: String, stage: int)
## The whole book, whenever it grows. Small and rare, so it is sent entire.
signal log_changed(entries: Array)

## The tide caught someone. Gentle by design: they wade home and walk slow for a
## while, and lose nothing at all (DESIGN §1, pillar 1).
signal keeper_caught(slot: String, slow_seconds: float)
signal keeper_released(slot: String)

# --- Local gameplay / UI ---
signal interact_pressed(target: Node)
## Somebody walked through a door. Rooms are presentation: the world does not
## care which one you are in, but the other keeper's screen does.
signal room_changed(room: String)
signal room_change_requested(scene_key: String)

## A keeper opened a bottle, or spoke to somebody, or opened the book.
signal bottle_reader_requested(bottle_id: String, slot: String, input_prefix: String)
signal dialogue_requested(npc_id: String, slot: String, input_prefix: String)
signal log_book_requested(slot: String, input_prefix: String)

## A keeper read the board in the tower.
signal milestone_board_requested(slot: String, input_prefix: String)

## A keeper held interact at a bench. Carries the pad prefix, because the wheel
## is aimed with the same stick that opened it.
signal station_wheel_requested(station: Station, slot: String, input_prefix: String)

## A menu took the screen. Keepers stop reading their pads while this is true, so
## choosing something never also walks you into the sea.
signal ui_modal_changed(open: bool)
signal notification(text: String)            # cozy toast ("A bottle washed ashore")
signal lamp_lit()                            # the climax — fire confetti, music swell
## A co-op gate is half-submitted: these slots have not reached for it yet.
## Empty means everybody has, which is the moment the gate fires.
signal tandem_waiting(gate_id: String, waiting: PackedStringArray)

# --- Net lifecycle (mirrors net.gd state for UI) ---
signal net_status_changed(status: String)    # "connecting" | "online" | "offline" | "error"
signal net_error(message: String)            # join refused, auth failed, socket dropped
signal net_slots_claimed(slots: PackedStringArray)  # which keeper slot(s) THIS client drives
signal keeper_presence_changed(keeper_id: String, present: bool)  # keeper_id = slot

## Presentation only — where the OTHER keeper appears to be, at ~10Hz. Never
## authoritative; see Command.OP_POSE. `sent_at` is the sender's clock in
## seconds, meaningful only as a difference against that same sender.
signal keeper_pose_received(slot: String, pos: Vector2, facing: int, sent_at: float, room: String)
