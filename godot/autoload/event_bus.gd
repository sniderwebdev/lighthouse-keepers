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
signal flag_changed(flag: String, value: bool)
signal milestone_changed(milestone_id: String, status: String)

## The tide caught someone. Gentle by design: they wade home and walk slow for a
## while, and lose nothing at all (DESIGN §1, pillar 1).
signal keeper_caught(slot: String, slow_seconds: float)
signal keeper_released(slot: String)

# --- Local gameplay / UI ---
signal interact_pressed(target: Node)
signal notification(text: String)            # cozy toast ("A bottle washed ashore")
signal lamp_lit()                            # the climax — fire confetti, music swell

# --- Net lifecycle (mirrors net.gd state for UI) ---
signal net_status_changed(status: String)    # "connecting" | "online" | "offline" | "error"
signal net_error(message: String)            # join refused, auth failed, socket dropped
signal net_slots_claimed(slots: PackedStringArray)  # which keeper slot(s) THIS client drives
signal keeper_presence_changed(keeper_id: String, present: bool)  # keeper_id = slot

## Presentation only — where the OTHER keeper appears to be, at ~10Hz. Never
## authoritative; see Command.OP_POSE. `sent_at` is the sender's clock in
## seconds, meaningful only as a difference against that same sender.
signal keeper_pose_received(slot: String, pos: Vector2, facing: int, sent_at: float)
