// match_handler.ts — the authoritative shared world.
//
// This is where co-op "truth" lives. The match holds the canonical world state,
// advances the tide on a fixed tick, validates every incoming command, applies
// it, persists to storage, and broadcasts diffs back to both keepers.
//
// Build with the Nakama TypeScript runtime (tsc -> build/index.js, loaded by the
// server). Register in main.ts via initializer.registerMatch("lighthouse", {...}).
//
// Keep OP_* and the payload shapes IN SYNC with godot/game/command.gd.
//
// NOTE ON STATE: everything mutable lives in the per-match `state` object that
// Nakama threads through every handler. Module-level globals are shared by ALL
// matches in the process, so two world codes would silently trample each other.

const OP = {
  GATHER: 1,
  CRAFT: 2,
  PLACE: 3,
  ADVANCE_STEP: 4,
  READ_BOTTLE: 5,
  TANDEM: 6,       // co-op gate: { gate_id } — fires when BOTH slots submit in window
  CARRY_ASSIST: 7, // two-person carry: { object_id }
  LOG_SESSION: 8,  // request session log entry assembly
  CAUGHT: 9,       // { slot, zone } — "the water reached me". Validated, not trusted.
  TALK: 10,        // { npc_id, slot } — advance an NPC's stage if its conditions hold
  CLAIM: 11,       // { slot } — a second player on this connection joins mid-session

  // 12 is RESERVED for Act 2's ENTER_ZONE (PLAN.md "Act 2 pre-decisions"). That
  // plan originally called it opcode 9, which 9/10/11 had already been spent on
  // by the time the slice shipped. Reserved rather than declared: it is not a
  // command until the boat exists. Next free opcode is 13.

  // Not commands. Where a keeper APPEARS to be is presentation, not authoritative
  // shared state (PLAN.md M1): never validated against the world, never persisted,
  // never merged into WorldState. Relayed only.
  POSE: 20,        // client -> server: { slot, x, y, f, t, r }
  POSE_ECHO: 120,  // server -> clients: { poses: { slot: {x,y,f,t,r} } }

  STATE_DIFF: 100, // server -> client
};

// Keeper slots: the two identities of the world. Connections CLAIM slots —
// one each online, both for couch play. All gameplay logic keys off slots.
type Slot = "keeper_a" | "keeper_b";
const SLOTS: Slot[] = ["keeper_a", "keeper_b"];
const TANDEM_WINDOW_MS = 10000;

// The loop is the only place incoming messages are drained, so it also caps how
// fast poses can be relayed. Clients send position at 10Hz (PLAN.md M1), so the
// loop has to run at least that often or the mirror stutters at 2Hz.
const TICK_RATE = 10;                // loops per second
const SECONDS_PER_CYCLE = 480;       // full LOW->...->LOW
const PHASES = ["LOW", "MID", "HIGH", "MID"]; // STORM injected occasionally

const STORAGE_WORLDS = "worlds";

// A world with nobody in it eventually stops existing, and is rebuilt from
// storage on the next join. Without this, every match ever created lives forever
// — including the ones discarded when two keepers race to create the same world.
// Generous, because a freshly created match is empty until its creator joins.
const IDLE_TERMINATE_TICKS = TICK_RATE * 120;   // two minutes

// Which phases each shore zone is walkable in, concentric from the tower
// (DESIGN.md §2). LOW opens everything; each step in gives one zone back to the
// sea. This table is authoritative — the client mirrors it to place barriers,
// but only this copy decides whether a keeper was really caught.
const ZONE_PHASES: { [zone: string]: string[] } = {
  sandbar: ["LOW"],
  mid_beach: ["LOW", "MID"],
  yard: ["LOW", "MID", "HIGH"],
  tower: ["LOW", "MID", "HIGH", "STORM"],
};

// Caught by the water: you wade home wet and walk slow for a bit. You lose
// nothing — not inventory, not progress, not time you cared about. Cozy, not
// cruel (DESIGN.md §1, pillar 1).
const SLOW_WALK_MS = 20000;

// A session ends when the world has been empty this long. The log is written
// then — one entry for the evening, not one per departure.
const SESSION_END_TICKS = TICK_RATE * 60;   // one minute

// The bottles. Story arrives on the tide and cannot be binged (DESIGN §2, §9):
// a row is eligible only once its cycle has come round and whatever it waits on
// has happened. The letters themselves are the author's to write.
interface BottleDef {
  chapter: number;
  requires_flag: string;
  min_tide_cycle: number;
  weight: number;
  sets_flag: string;
}
const BOTTLES: { [id: string]: BottleDef } = {
  bottle_01: { chapter: 1, requires_flag: "", min_tide_cycle: 0, weight: 1, sets_flag: "read_bottle_01" },
  bottle_02: {
    chapter: 2, requires_flag: "read_bottle_01", min_tide_cycle: 1, weight: 1,
    sets_flag: "read_bottle_02",
  },
  bottle_03: {
    chapter: 3, requires_flag: "read_bottle_02", min_tide_cycle: 2, weight: 1,
    sets_flag: "read_bottle_03",
  },
};

// The neighbours. Each stage is a small ask, a reveal, and something you can now
// do (DESIGN §4, axis 3) — here, the stage that teaches you a recipe.
interface NpcStage {
  requires_flag: string;
  grants_flag: string;
  /// An item this stage wants handed over. The stage does not advance until it
  /// is in the shared basket, and handing it over spends it — "bring me a
  /// smooth stone" is not rhetorical.
  needs_item?: string;
}
// The co-op gates. Reserved for climaxes only (DESIGN §5): never for routine
// progress, because gating the ordinary on both of you being online is how a
// game about two people becomes a game about scheduling.
interface GateDef {
  requires_flag: string;   // what must already be true for the gate to be armed
  grants_flag: string;
}
const GATES: { [id: string]: GateDef } = {
  // Act one's climax. The lamp has to be fuelled first — funding the relight is
  // what ADVANCE_STEP does; lighting it is what the two of you do.
  relight_lamp: { requires_flag: "lamp_ready", grants_flag: "lamp_lit" },
};

// The crab in full (CONTENT.md): meet him, then two ask/deliver pairs. Each
// pair is a small errand that ends in a recipe, so the neighbour axis and the
// crafting axis advance together (DESIGN §4).
//
// The asks gate on restoration flags and the deliveries gate on the item, so
// the order is: clear_hearth -> he asks for a stone -> you bring it and he
// teaches patch_kit -> patch_kit lets you fix_stairs -> he asks for a fish ->
// you bring it and he teaches chowder.
const NPCS: { [id: string]: NpcStage[] } = {
  hermit_crab: [
    { requires_flag: "", grants_flag: "crab_met" },
    { requires_flag: "hearth_lit", grants_flag: "crab_asked_stone" },
    {
      requires_flag: "crab_asked_stone", grants_flag: "crab_taught_patch_kit",
      needs_item: "smooth_stone",
    },
    { requires_flag: "stairs_fixed", grants_flag: "crab_asked_fish" },
    {
      requires_flag: "crab_asked_fish", grants_flag: "crab_taught_chowder",
      needs_item: "fish_stub",
    },
  ],
};

// The spawn table. Every resource node in the world: what it gives, how much,
// which zone it sits in, and how many tide cycles until the sea brings it back.
// Authoritative — the scene places matching ids but has no say in the yields.
// Expanding the game is adding rows here (DESIGN.md §2, "tide as content
// delivery"), not writing code.
interface NodeDef {
  item: string;
  yield: number;
  zone: string;
  respawn_cycles: number;
}

/// A node the sea does not restock. Expressed as a respawn interval longer than
/// any world will live rather than as a special case, so `nodeIsReady` stays one
/// line of arithmetic with no "unless" in it.
const NEVER_RESPAWNS = 1000000;
const NODES: { [id: string]: NodeDef } = {
  driftwood_01: { item: "driftwood", yield: 3, zone: "sandbar", respawn_cycles: 1 },
  driftwood_02: { item: "driftwood", yield: 1, zone: "mid_beach", respawn_cycles: 1 },
  driftwood_03: { item: "driftwood", yield: 1, zone: "mid_beach", respawn_cycles: 1 },
  driftwood_04: { item: "driftwood", yield: 2, zone: "yard", respawn_cycles: 2 },
  kelp_01: { item: "kelp", yield: 2, zone: "sandbar", respawn_cycles: 1 },
  kelp_02: { item: "kelp", yield: 1, zone: "mid_beach", respawn_cycles: 1 },
  brass_scrap_01: { item: "brass_scrap", yield: 1, zone: "sandbar", respawn_cycles: 2 },
  glass_shard_01: { item: "glass_shard", yield: 1, zone: "sandbar", respawn_cycles: 2 },
  glass_shard_02: { item: "glass_shard", yield: 1, zone: "mid_beach", respawn_cycles: 2 },
  // CANON (CONTENT.md): fish come from the tide pools at LOW tide. Fishing as an
  // activity is an Act 2 candidate, deliberately not built now.
  fish_stub_01: { item: "fish_stub", yield: 2, zone: "sandbar", respawn_cycles: 1 },
  // "Bring me a smooth stone from the pools. Low tide." — the crab, CONTENT.md.
  smooth_stone_01: { item: "smooth_stone", yield: 1, zone: "sandbar", respawn_cycles: 1 },

  // THE ARRIVAL (PLAN.md M9). What's left of the city life, washed in with you.
  // They sit in the yard, which is walkable in every phase but STORM, so the
  // first thing a new keeper can do does not depend on the tide being kind.
  //
  // Ordinary materials, deliberately: the crates are a first handhold, not a
  // separate economy. Between them they yield 3 driftwood against clear_hearth's
  // cost of 4 — enough that the beach is a short walk rather than a long one,
  // not so much that the first gathering loop is skipped. TUNING NOTE: those two
  // numbers are the whole feel of the opening minute and are the author's to
  // change; nothing else depends on them.
  arrival_crate_01: { item: "driftwood", yield: 2, zone: "yard", respawn_cycles: NEVER_RESPAWNS },
  arrival_crate_02: { item: "driftwood", yield: 1, zone: "yard", respawn_cycles: NEVER_RESPAWNS },
};

interface TideState {
  phase: string;
  t: number;
  cycle: number;
  storm: boolean;
  // How long a full cycle takes. Lives in the world rather than in a constant
  // because it is a FEEL value, and feel is tuned by playing (CLAUDE.md Testing
  // law). SECONDS_PER_CYCLE is the committed default; this is what is in force.
  cycle_seconds: number;
}

// The PERSISTED world. Presence is deliberately not in here: it is a property of
// who is connected right now, and a stale `presence` read back from storage
// would make the tide advance with nobody watching.
interface WorldState {
  version: number;
  tide: TideState;
  flags: { [k: string]: boolean };
  inventory: { [k: string]: number };
  milestones: { [k: string]: string };  // "todo" | "in_progress" | "done"
  // node id -> which tide cycle it was taken on. A node not in here is ready.
  // Persisted: a world you come back to should remember what you already picked
  // up, and the sea should have restocked it while you were away.
  nodes: { [id: string]: number };
  // bottle id -> "washed_up" | "read". Absent means the sea has not brought it.
  bottles: { [id: string]: string };
  // npc id -> how many stages of theirs you have had.
  npcs: { [id: string]: number };
  // The keeper's log, oldest first. A keepsake, so it is never pruned.
  log: LogEntry[];
  updated_at: number;
}

interface LogEntry {
  day: number;
  written_by: string;
  cycle: number;
  // Event ids, not prose. The templates that turn these into sentences are the
  // author's to write; inventing them here would put words in her book.
  lines: string[];
}

interface MatchState {
  world: WorldState;
  worldId: string;
  // slot -> is somebody driving it right now (runtime only, never persisted)
  presence: { [slot: string]: boolean };
  // CONNECTION (sessionId) -> slots it has claimed. 1 online, 2 for couch.
  // Keyed by session, not user: two instances on one PC may share a user id.
  claims: { [sessionId: string]: Slot[] };
  // slots requested in matchJoinAttempt — metadata is only available there,
  // so it is parked here until matchJoin can consume it.
  pending: { [sessionId: string]: Slot[] };
  // tandem gate bookkeeping: gate_id -> slot -> timestamp of intent
  tandem: { [gateId: string]: { [slot: string]: number } };
  // latest presentation pose per slot. Runtime only — poses are never
  // persisted and never enter the world state.
  poses: { [slot: string]: Pose };
  // slot -> wall-clock ms at which the slow walk ends. Runtime only: being wet
  // is a thing that is happening, not a thing the world remembers.
  caught: { [slot: string]: number };
  // What has happened since this world last woke up. The log is assembled from
  // this, then it is cleared: an evening's entry is about that evening.
  sessionEvents: string[];
  sessionLogged: boolean;
  dirty: boolean;
  ticksSinceSave: number;
  idleTicks: number;
}

interface Pose {
  x: number;
  y: number;
  f: number;   // facing, 0-7
  t: number;   // SENDER's clock in ms, relayed untouched
  r: string;   // which room they are standing in
}

// Server-side recipe table. Mirror of the .tres content under
// godot/content/recipes/ — the SERVER copy is authoritative and the client's is
// only there to draw the wheel and grey out what it already knows will be
// refused. Values are PLAN.md's, verbatim.
//
// `chowder` costs 1 fish + 2 kelp (CONTENT.md) and stays gated on
// `crab_taught_chowder`: the crab hands it over, and the handing over is the
// point of the scene.
interface RecipeDef {
  inputs: { [k: string]: number };
  out: string;
  n: number;
  station: string;      // "" = anywhere
  unlock_flag: string;  // "" = known from the start
}
const RECIPES: { [id: string]: RecipeDef } = {
  patch_kit: {
    inputs: { driftwood: 3, kelp: 1 }, out: "patch_kit", n: 1,
    station: "workbench", unlock_flag: "crab_taught_patch_kit",
  },
  lamp_oil: {
    inputs: { kelp: 2, fish_stub: 1 }, out: "lamp_oil", n: 1,
    station: "workbench", unlock_flag: "",
  },
  chowder: {
    inputs: { fish_stub: 1, kelp: 2 }, out: "chowder", n: 1,
    station: "stove", unlock_flag: "crab_taught_chowder",
  },
  // Adopted from the radial mock (CONTENT.md): the one name on it that was
  // real. Ungated on purpose — it is the small comforting thing you can always
  // make, and the letters lean on it.
  kelp_tea: {
    inputs: { kelp: 2 }, out: "kelp_tea", n: 1,
    station: "stove", unlock_flag: "",
  },
};
// The restoration chain. Costs and order are PLAN.md's, verbatim; this table
// mirrors the .tres under godot/content/milestones/ and is the copy that counts.
//
// Order is enforced by `requires` rather than by position: a step is fundable
// only once the step before it has set its flag, so no amount of resources buys
// you the lens before the glass.
interface MilestoneDef {
  cost: { [k: string]: number };
  requires: string;   // "" = the first step
  grants: string;     // flag set when it is sealed
}
const MILESTONES: { [id: string]: MilestoneDef } = {
  clear_hearth: { cost: { driftwood: 4 }, requires: "", grants: "hearth_lit" },
  fix_stairs: {
    cost: { driftwood: 6, patch_kit: 1 }, requires: "hearth_lit", grants: "stairs_fixed",
  },
  repair_glass: {
    cost: { glass_shard: 3, patch_kit: 1 }, requires: "stairs_fixed", grants: "glass_repaired",
  },
  restore_lens: {
    cost: { brass_scrap: 3, glass_shard: 2 }, requires: "glass_repaired", grants: "lens_restored",
  },
  // Funding the relight is not lighting it. This grants `lamp_ready`; `lamp_lit`
  // belongs to the tandem gate in M7, because the climax is the two of you
  // reaching for it together and a purchase cannot stand in for that.
  relight_lamp: {
    cost: { lamp_oil: 2 }, requires: "lens_restored", grants: "lamp_ready",
  },
};

const matchInit: nkruntime.MatchInitFunction = (ctx, logger, nk, params) => {
  const worldId = String(params["world_id"] || "default").toUpperCase();
  const world = loadWorld(nk, worldId);
  const state: MatchState = {
    world: world,
    worldId: worldId,
    presence: { keeper_a: false, keeper_b: false },
    claims: {},
    pending: {},
    tandem: {},
    poses: {},
    caught: {},
    sessionEvents: [],
    sessionLogged: false,
    dirty: false,
    ticksSinceSave: 0,
    idleTicks: 0,
  };
  logger.info("lighthouse match init for world %s", worldId);
  // The label must be JSON so main.ts can find this world again with the
  // query `+label.world:CODE`.
  return {
    state: state,
    tickRate: TICK_RATE,
    label: JSON.stringify({ world: worldId }),
  };
};

const matchJoinAttempt: nkruntime.MatchJoinAttemptFunction = (
  ctx, logger, nk, dispatcher, tick, state, presence, metadata,
) => {
  const s = state as MatchState;
  // metadata.slots: "keeper_a" | "keeper_b" | "both". Reject if requested
  // slot(s) are already claimed by a DIFFERENT connection.
  const wanted = parseSlots(metadata ? (metadata as any).slots : null);
  if (!wanted.length) {
    return { state: s, accept: false, rejectMessage: "No keeper slot requested." };
  }
  for (let i = 0; i < wanted.length; i++) {
    const owner = slotOwner(s, wanted[i]);
    if (owner && owner !== presence.sessionId) {
      return { state: s, accept: false, rejectMessage: wanted[i] + " is already taken." };
    }
  }
  s.pending[presence.sessionId] = wanted;
  return { state: s, accept: true };
};

function parseSlots(v: any): Slot[] {
  if (v === "both") return ["keeper_a", "keeper_b"];
  if (v === "keeper_a" || v === "keeper_b") return [v];
  return [];
}

function slotOwner(s: MatchState, slot: Slot): string | null {
  for (const sid in s.claims) {
    if (s.claims[sid].indexOf(slot) >= 0) return sid;
  }
  return null;
}

const matchJoin: nkruntime.MatchJoinFunction = (ctx, logger, nk, dispatcher, tick, state, presences) => {
  const s = state as MatchState;
  for (let i = 0; i < presences.length; i++) {
    const p = presences[i];
    const wanted = s.pending[p.sessionId] || [];
    delete s.pending[p.sessionId];

    // Re-check availability: another connection may have claimed a slot between
    // this connection's join attempt and its join.
    const granted: Slot[] = [];
    for (let j = 0; j < wanted.length; j++) {
      const owner = slotOwner(s, wanted[j]);
      if (!owner || owner === p.sessionId) granted.push(wanted[j]);
    }
    s.claims[p.sessionId] = granted;
    for (let j = 0; j < granted.length; j++) s.presence[granted[j]] = true;
    logger.info("session %s claimed [%s] in world %s", p.sessionId, granted.join(","), s.worldId);

    // Snapshot + this connection's own slot grant, sent only to the joiner.
    dispatcher.broadcastMessage(
      OP.STATE_DIFF,
      JSON.stringify({
        tide: s.world.tide,
        flags: s.world.flags,
        inventory: s.world.inventory,
        milestones: s.world.milestones,
        nodes: nodeStates(s),
        bottles: s.world.bottles,
        npcs: s.world.npcs,
        log: s.world.log,
        presence: s.presence,
        caught: remainingCaught(s),
        you: { slots: granted, world: s.worldId },
      }),
      [p],
    );
  }
  broadcast(dispatcher, { presence: s.presence });
  return { state: s };
};

const matchLeave: nkruntime.MatchLeaveFunction = (ctx, logger, nk, dispatcher, tick, state, presences) => {
  const s = state as MatchState;
  for (let i = 0; i < presences.length; i++) {
    const p = presences[i];
    const held = s.claims[p.sessionId] || [];
    for (let j = 0; j < held.length; j++) {
      s.presence[held[j]] = false;
      // Drop the pose too, or the departed keeper leaves a ghost standing there.
      delete s.poses[held[j]];
      delete s.caught[held[j]];
    }
    delete s.claims[p.sessionId];
    delete s.pending[p.sessionId];
  }
  broadcast(dispatcher, { presence: s.presence });
  saveWorld(nk, s.worldId, s.world);
  s.dirty = false;
  return { state: s };
};

const matchLoop: nkruntime.MatchLoopFunction = (ctx, logger, nk, dispatcher, tick, state, messages) => {
  const s = state as MatchState;

  // 0) an empty world eventually closes. Returning null terminates the match;
  // the next join_world rebuilds it from storage, unchanged.
  if (anyonePresent(s)) {
    s.idleTicks = 0;
  } else {
    s.idleTicks += 1;
    // Both keepers gone a minute: the evening is over, so it gets written down
    // while the match is still alive to broadcast and persist it.
    if (s.idleTicks === SESSION_END_TICKS) {
      writeLogEntry(s, dispatcher, "keeper_a");
    }
    if (s.idleTicks >= IDLE_TERMINATE_TICKS) {
      saveWorld(nk, s.worldId, s.world);
      logger.info("world %s idle, closing", s.worldId);
      return null;
    }
  }

  // 1) advance the tide ONLY when at least one keeper is present (design choice).
  if (anyonePresent(s)) advanceTide(s, dispatcher);

  // 1b) release anyone who has finished wading home.
  expireCaught(s, dispatcher);

  // 2) process incoming commands authoritatively.
  for (let i = 0; i < messages.length; i++) {
    const msg = messages[i];
    let data: any = {};
    if (msg.data) {
      try {
        data = JSON.parse(nk.binaryToString(msg.data));
      } catch (e) {
        logger.warn("undecodable command payload on op %d", msg.opCode);
        continue;
      }
    }
    handleCommand(s, msg.opCode, data, msg.sender, dispatcher, logger);
  }

  // 3) periodic persistence.
  if (s.dirty) {
    s.ticksSinceSave += 1;
    if (s.ticksSinceSave >= TICK_RATE * 10) {
      saveWorld(nk, s.worldId, s.world);
      s.dirty = false;
      s.ticksSinceSave = 0;
    }
  }
  return { state: s };
};

const matchTerminate: nkruntime.MatchTerminateFunction = (ctx, logger, nk, dispatcher, tick, state) => {
  const s = state as MatchState;
  saveWorld(nk, s.worldId, s.world);
  return { state: s };
};

/// Match signals are the only way into a running match from an RPC. The single
/// signal understood is the dev tide jump — see rpcDebugSetTide in main.ts,
/// which is registered only when the runtime is explicitly in dev mode.
const matchSignal: nkruntime.MatchSignalFunction = (ctx, logger, nk, d, tick, state, data) => {
  const s = state as MatchState;
  let req: any = {};
  try {
    req = JSON.parse(data || "{}");
  } catch (e) {
    return { state: s, data: JSON.stringify({ ok: false, error: "bad signal payload" }) };
  }
  // Dev only, like set_tide: the cycle length is a feel value and this is how a
  // playtest turns it without an editor.
  // Dev only. Verifiers that exercise a MECHANIC should not have to play the
  // story that unlocks it: M4 tests the crafting wheel, and the wheel does not
  // care which recipe taught it. Sets one story flag, nothing else.
  if (req.op === "set_flag") {
    const flag = String(req.flag || "");
    if (!/^[a-z0-9_]{3,40}$/.test(flag)) {
      return { state: s, data: JSON.stringify({ ok: false, error: "bad flag name" }) };
    }
    s.world.flags[flag] = req.value !== false;
    s.dirty = true;
    broadcast(d, { flags: s.world.flags });
    logger.warn("DEV: flag %s of %s set to %s", flag, s.worldId, String(s.world.flags[flag]));
    return { state: s, data: JSON.stringify({ ok: true, flag: flag }) };
  }
  if (req.op === "set_cycle_seconds") {
    const secs = Number(req.seconds);
    if (!isFinite(secs) || secs < 10 || secs > 7200) {
      return { state: s, data: JSON.stringify({ ok: false, error: "seconds out of range" }) };
    }
    s.world.tide.cycle_seconds = secs;
    s.dirty = true;
    broadcast(d, { tide: tideDiff(s.world.tide) });
    logger.warn("DEV: cycle length of %s set to %ds", s.worldId, secs);
    return { state: s, data: JSON.stringify({ ok: true, cycle_seconds: secs }) };
  }
  if (req.op !== "set_tide") {
    return { state: s, data: JSON.stringify({ ok: false, error: "unknown signal" }) };
  }

  const t = Number(req.t);
  if (!isFinite(t) || t < 0 || t >= 1) {
    return { state: s, data: JSON.stringify({ ok: false, error: "t must be 0..1" }) };
  }
  s.world.tide.t = t;
  s.world.tide.phase = PHASES[Math.floor(t * PHASES.length) % PHASES.length];
  if (req.cycle !== undefined && isFinite(Number(req.cycle))) {
    s.world.tide.cycle = Math.floor(Number(req.cycle));
    // Jumping the cycle has to run the rolls, or the shore stays bare and no
    // letter ever arrives until the next natural rollover eight minutes later.
    rollSpawns(s, d);
    rollBottles(s, d, logger);
  }
  s.dirty = true;
  broadcast(d, { tide: tideDiff(s.world.tide) });
  logger.warn("DEV: tide of world %s jumped to t=%f (%s)", s.worldId, t, s.world.tide.phase);
  return { state: s, data: JSON.stringify({ ok: true, phase: s.world.tide.phase, t: t }) };
};

// --- command handling (the validation layer) ---

function handleCommand(
  s: MatchState, op: number, data: any, sender: nkruntime.Presence,
  dispatcher: nkruntime.MatchDispatcher, logger: nkruntime.Logger,
) {
  const w = s.world;
  const sessionId = sender.sessionId;
  switch (op) {
    // A second player joins a connection that is already in the match — couch
    // drop-in. Claiming a slot is a real state change (it flips presence, and
    // presence gates the tide and every tandem gate), so it is a command that
    // the match validates, not something a client may assume about itself.
    case OP.CLAIM: {
      const slot = data.slot;
      if (SLOTS.indexOf(slot) < 0) {
        logger.warn("claim of unknown slot %s refused", String(slot));
        break;
      }
      const owner = slotOwner(s, slot);
      if (owner && owner !== sessionId) {
        // Someone else is that keeper. Nothing to say to the asker beyond the
        // presence they already have: the slot is simply not on offer.
        logger.info("claim of %s refused, held by %s", slot, owner);
        break;
      }
      const held = s.claims[sessionId] || [];
      if (held.indexOf(slot) >= 0) break;   // already ours; a no-op, not an error
      held.push(slot);
      s.claims[sessionId] = held;
      s.presence[slot] = true;
      logger.info("session %s claimed %s mid-session in world %s", sessionId, slot, s.worldId);
      // The grant goes only to the claimer (it is per-connection), the presence
      // to everyone — same split as matchJoin.
      dispatcher.broadcastMessage(
        OP.STATE_DIFF,
        JSON.stringify({ presence: s.presence, you: { slots: held, world: s.worldId } }),
        [sender],
      );
      broadcast(dispatcher, { presence: s.presence });
      break;
    }
    case OP.GATHER: {
      const nodeId = String(data.node_id || "");
      const def = NODES[nodeId];
      if (!def) return;                       // no such node; silent reject = cozy
      if (!nodeIsReady(w, nodeId, def)) return;

      // Taken in the SAME tick it is granted. That single ordering is the whole
      // of the idempotency: a second GATHER for this node — whether from a
      // mashed button, a duplicated packet, or the other keeper reaching for it
      // at the same moment — finds it already taken and grants nothing.
      w.nodes[nodeId] = w.tide.cycle;
      grant(s, def.item, def.yield);
      s.dirty = true;

      const inv: { [k: string]: number } = {};
      inv[def.item] = w.inventory[def.item] || 0;
      const nodeDiff: { [k: string]: boolean } = {};
      nodeDiff[nodeId] = false;
      broadcast(dispatcher, { inventory: inv, nodes: nodeDiff });
      break;
    }
    case OP.CRAFT: {
      const r = RECIPES[String(data.recipe_id || "")];
      if (!r) return;                                       // silent reject = cozy
      // You must be at the right bench. The client only offers what the station
      // makes, but the client is not what decides.
      if (r.station !== "" && r.station !== String(data.station || "")) return;
      if (r.unlock_flag !== "" && !w.flags[r.unlock_flag]) return;
      if (!afford(w, r.inputs)) return;

      // Inputs and output move together, in one pass, announced in ONE diff.
      // A client can never observe a frame where the driftwood is gone and the
      // patch kit has not arrived.
      for (const k in r.inputs) grant(s, k, -r.inputs[k]);
      grant(s, r.out, r.n);
      const touchedCraft: { [k: string]: number } = {};
      for (const k in r.inputs) touchedCraft[k] = 0;
      touchedCraft[r.out] = 0;
      s.dirty = true;
      broadcast(dispatcher, { inventory: changedInv(w, touchedCraft) });
      logger.info("crafted %s at the %s in %s", data.recipe_id, r.station || "hands", s.worldId);
      break;
    }
    case OP.ADVANCE_STEP: {
      const id = String(data.milestone_id || "");
      const step = MILESTONES[id];
      if (!step) return;                                  // silent reject = cozy
      if (w.milestones[id] === "done") return;            // already sealed
      // The chain, enforced here and nowhere else that matters. A client with a
      // full basket and a doctored request still cannot skip a step.
      if (step.requires !== "" && !w.flags[step.requires]) return;
      if (!afford(w, step.cost)) return;

      for (const k in step.cost) grant(s, k, -step.cost[k]);
      w.milestones[id] = "done";
      w.flags[step.grants] = true;
      s.dirty = true;
      // Cost, status and flag in ONE diff: the tower lights up at the same
      // moment the driftwood leaves the basket, on both screens.
      const done: { [k: string]: string } = {};
      done[id] = "done";
      const flagged: { [k: string]: boolean } = {};
      flagged[step.grants] = true;
      broadcast(dispatcher, {
        inventory: changedInv(w, step.cost), milestones: done, flags: flagged,
      });
      note(s, "milestone:" + id);
      logger.info("sealed milestone %s (%s) in %s", id, step.grants, s.worldId);
      break;
    }
    case OP.READ_BOTTLE: {
      const id = String(data.bottle_id || "");
      const bottle = BOTTLES[id];
      if (!bottle) return;
      // Only a bottle the sea actually brought, and only once. Whoever opens it
      // opens it for the world — the other keeper reads the same letter, not a
      // second copy of it.
      if (w.bottles[id] !== "washed_up") return;
      w.bottles[id] = "read";
      w.flags[bottle.sets_flag] = true;
      s.dirty = true;
      note(s, "bottle:" + id);
      const fdiff: { [k: string]: boolean } = {};
      fdiff[bottle.sets_flag] = true;
      const bdiff: { [k: string]: string } = {};
      bdiff[id] = "read";
      broadcast(dispatcher, { flags: fdiff, bottles: bdiff });
      logger.info("bottle %s was read in %s", id, s.worldId);
      break;
    }
    case OP.TALK: {
      const npcId = String(data.npc_id || "");
      const stages = NPCS[npcId];
      if (!stages) return;
      const reached = w.npcs[npcId] || 0;
      if (reached >= stages.length) return;          // nothing further to say yet
      const stage = stages[reached];
      // A stage that is waiting on something simply does not advance; the NPC
      // still talks, they just have nothing new.
      if (stage.requires_flag !== "" && !w.flags[stage.requires_flag]) return;
      // An errand stage wants the thing in hand. Not having it is not an error
      // — he simply asks again next time you come down.
      const wanted = stage.needs_item || "";
      if (wanted !== "" && (w.inventory[wanted] || 0) < 1) {
        logger.info("%s stage %d still waiting on %s in %s", npcId, reached, wanted, s.worldId);
        return;
      }
      w.npcs[npcId] = reached + 1;
      w.flags[stage.grants_flag] = true;
      s.dirty = true;
      note(s, "npc:" + npcId + ":" + (reached + 1));
      const tflags: { [k: string]: boolean } = {};
      tflags[stage.grants_flag] = true;
      const tnpc: { [k: string]: number } = {};
      tnpc[npcId] = reached + 1;
      const tdiff: { [k: string]: any } = { flags: tflags, npcs: tnpc };
      if (wanted !== "") {
        // Handing it over spends it. "Bring me a stone" is not rhetorical.
        const spent: { [k: string]: number } = {};
        spent[wanted] = 1;
        grant(s, wanted, -1);
        tdiff.inventory = changedInv(w, spent);
      }
      broadcast(dispatcher, tdiff);
      logger.info("%s reached stage %d (%s) in %s", npcId, reached + 1, stage.grants_flag, s.worldId);
      break;
    }
    case OP.TANDEM: {
      // CO-OP GATE: fires when BOTH slots submit the same gate within the
      // window — regardless of whether that's two connections (online) or one
      // connection driving both pads (couch). Couch payload carries `slot`;
      // online derives it from the connection's single claim.
      const gateId: string = String(data.gate_id || "");
      const gate = GATES[gateId];
      if (!gate) return;
      if (w.flags[gate.grants_flag]) return;                 // already done
      // Armed only when the world is ready for it. Reaching for a lamp with no
      // oil in it is not a moment, it is a mistake waiting to be explained.
      if (gate.requires_flag !== "" && !w.flags[gate.requires_flag]) return;
      const slot = resolveSlot(s, sessionId, data.slot);
      if (!slot) return;
      const now = Date.now();
      if (!s.tandem[gateId]) s.tandem[gateId] = {};
      const votes = s.tandem[gateId];
      votes[slot] = now;
      const live: Slot[] = [];
      const waiting: Slot[] = [];
      for (let i = 0; i < SLOTS.length; i++) {
        const sl = SLOTS[i];
        if (votes[sl] && now - votes[sl] <= TANDEM_WINDOW_MS) live.push(sl);
        else waiting.push(sl);
      }
      broadcast(dispatcher, { tandem: { gate_id: gateId, waiting: waiting } });
      if (live.length === 2) {
        w.flags[gate.grants_flag] = true;
        s.dirty = true;
        delete s.tandem[gateId];
        note(s, "gate:" + gateId);
        const gdiff: { [k: string]: boolean } = {};
        gdiff[gate.grants_flag] = true;
        broadcast(dispatcher, { flags: gdiff });
        logger.info("tandem gate %s fired (%s) in %s", gateId, gate.grants_flag, s.worldId);
      }
      break;
    }
    case OP.CARRY_ASSIST: {
      // Same both-slots pattern, scoped to a carryable object; flag toggles
      // while both hold. v1: mark intent flag, client handles the visual.
      const objId: string = data.object_id;
      if (!objId) return;
      const slot = resolveSlot(s, sessionId, data.slot);
      if (!slot) return;
      const key = "carry_" + objId + "_" + slot;
      w.flags[key] = true;
      const cdiff: { [k: string]: boolean } = {};
      cdiff[key] = true;
      broadcast(dispatcher, { flags: cdiff });
      break;
    }
    case OP.POSE: {
      // Presentation only: validated for OWNERSHIP (you may not puppet the other
      // keeper) but never against the world. There is nothing here to cheat at —
      // position buys you nothing a command would grant.
      const slot = resolveSlot(s, sessionId, data.slot);
      if (!slot) return;
      const x = Number(data.x);
      const y = Number(data.y);
      if (!isFinite(x) || !isFinite(y)) return;
      // `t` is the sender's clock, relayed untouched — the server has no opinion
      // about it and must not restamp it, or the receiver ends up interpolating
      // against this machine's jitter instead of the sender's motion.
      const pose: Pose = {
        x: x, y: y, f: Math.floor(Number(data.f) || 0) & 7, t: Number(data.t) || 0,
        r: String(data.r || ""),
      };
      s.poses[slot] = pose;
      // Relayed one for one rather than coalesced per tick. Two 10Hz clocks
      // (the sender's timer and this loop) beat against each other, so
      // coalescing quietly drops roughly every seventh sample — which the
      // receiver then has to cover by moving at double speed.
      const out: { [slot: string]: Pose } = {};
      out[slot] = pose;
      dispatcher.broadcastMessage(OP.POSE_ECHO, JSON.stringify({ poses: out }));
      break;
    }
    case OP.CAUGHT: {
      // The client reports being in a zone the water has taken; the server
      // decides whether that is true. Positions are presentation and never
      // authoritative (PLAN.md M1), so the world cannot check WHERE a keeper is
      // — but it owns the tide, so it can check whether that zone is under water
      // at all, which is the part that matters. The consequence is entirely the
      // server's: both clients learn about it the same way, at the same time.
      const slot = resolveSlot(s, sessionId, data.slot);
      if (!slot) return;
      const phases = ZONE_PHASES[String(data.zone || "")];
      if (!phases) return;
      if (phases.indexOf(w.tide.phase) >= 0) return;  // dry land; nothing caught anyone
      const now = Date.now();
      if (s.caught[slot] && s.caught[slot] > now) return;  // already wading home
      s.caught[slot] = now + SLOW_WALK_MS;
      const cdiff: { [k: string]: number } = {};
      cdiff[slot] = SLOW_WALK_MS;
      broadcast(dispatcher, { caught: cdiff });
      logger.info("%s was caught by the water on the %s", slot, data.zone);
      break;
    }
    case OP.LOG_SESSION: {
      // Turning in at the bed. The same assembly the empty-world timer runs, so
      // an evening produces one entry either way.
      writeLogEntry(s, dispatcher, resolveSlot(s, sessionId, data.slot) || "keeper_a", logger);
      break;
    }
  }
}

/// Milliseconds of slow walk each caught keeper has left, for the join snapshot.
/// A keeper arriving mid-wade should see the same thing everyone else does.
function remainingCaught(s: MatchState): { [k: string]: number } {
  const now = Date.now();
  const out: { [k: string]: number } = {};
  for (const slot in s.caught) {
    const left = s.caught[slot] - now;
    if (left > 0) out[slot] = left;
  }
  return out;
}

/// The server, not a client timer, decides when someone has dried off — so both
/// clients stop the slow walk on the same authoritative message.
function expireCaught(s: MatchState, dispatcher: nkruntime.MatchDispatcher) {
  const now = Date.now();
  const released: { [k: string]: number } = {};
  let any = false;
  for (const slot in s.caught) {
    if (s.caught[slot] <= now) {
      delete s.caught[slot];
      released[slot] = 0;
      any = true;
    }
  }
  if (any) broadcast(dispatcher, { caught: released });
}


// --- tide ---

function anyonePresent(s: MatchState): boolean {
  for (let i = 0; i < SLOTS.length; i++) {
    if (s.presence[SLOTS[i]]) return true;
  }
  return false;
}

function advanceTide(s: MatchState, dispatcher: nkruntime.MatchDispatcher) {
  const t = s.world.tide;
  const step = 1 / (Math.max(1, t.cycle_seconds) * TICK_RATE);
  const before = t.t;
  t.t += step;
  let rolledBottles = false;
  if (t.t >= 1) {
    t.t -= 1;
    t.cycle += 1;
    // The sea restocks the shore on cycle boundaries, never mid-cycle: the tide
    // is the only clock the world has, and content arrives on it (DESIGN §2).
    rollSpawns(s, dispatcher);
    rollBottles(s, dispatcher);
    rolledBottles = true;
  }
  // phase index from t (4 phases per cycle), with rare storm on HIGH.
  const idx = Math.floor(t.t * PHASES.length) % PHASES.length;
  const newPhase = PHASES[idx];
  if (newPhase !== t.phase) {
    t.phase = newPhase;
    s.dirty = true;
    // HUNGRY STORY does not wait for the cycle to come round (PLAN.md M9).
    //
    // Materials are the tide's to ration; story is not. A chapter whose flag has
    // just been earned but which has not washed in yet means the player did
    // everything asked of them and got told to wait — up to a full cycle, which
    // at the committed 480s is eight minutes of nothing. That is the tide acting
    // as a lock rather than as delivery, and it is the one place the clock can
    // starve the game instead of pacing it.
    //
    // Safe on every boundary because eligibility is self-limiting: each chapter
    // requires the previous one to have been READ, so at most one unread letter
    // can be on the sand at a time. rollBottles is a no-op when nothing is
    // eligible, which is the common case — this only fires when the story is
    // actually waiting.
    if (!rolledBottles) {
      rollBottles(s, dispatcher);
    }
    broadcast(dispatcher, { tide: tideDiff(t) });
  } else if (Math.floor(before * 20) !== Math.floor(t.t * 20)) {
    // lightweight progress ticks for smooth client interpolation
    broadcast(dispatcher, { tide: tideDiff(t) });
  }
}

function tideDiff(t: TideState) {
  return {
    phase: t.phase, t: t.t, cycle: t.cycle, storm: t.storm,
    cycle_seconds: t.cycle_seconds,
  };
}

function resolveSlot(s: MatchState, sessionId: string, explicit?: string): Slot | null {
  const claimed = s.claims[sessionId] || [];
  if (explicit === "keeper_a" || explicit === "keeper_b") {
    return claimed.indexOf(explicit) >= 0 ? explicit : null;
  }
  return claimed.length === 1 ? claimed[0] : null;
}

// --- resource nodes ---

function nodeIsReady(w: WorldState, nodeId: string, def: NodeDef): boolean {
  const takenOn = w.nodes[nodeId];
  if (takenOn === undefined) return true;
  return w.tide.cycle - takenOn >= def.respawn_cycles;
}

/// Ready state for every known node, for the join snapshot.
function nodeStates(s: MatchState): { [id: string]: boolean } {
  const out: { [id: string]: boolean } = {};
  for (const id in NODES) out[id] = nodeIsReady(s.world, id, NODES[id]);
  return out;
}

/// Hand back to the shore whatever has been gone long enough. Announced as a
/// diff so both clients grow their driftwood back at the same moment.
function rollSpawns(s: MatchState, dispatcher: nkruntime.MatchDispatcher) {
  const restocked: { [id: string]: boolean } = {};
  let any = false;
  for (const id in s.world.nodes) {
    const def = NODES[id];
    if (!def) {
      delete s.world.nodes[id];   // a node that no longer exists in the table
      continue;
    }
    if (nodeIsReady(s.world, id, def)) {
      delete s.world.nodes[id];
      restocked[id] = true;
      any = true;
    }
  }
  if (any) {
    s.dirty = true;
    broadcast(dispatcher, { nodes: restocked });
  }
}

// --- story: bottles, neighbours, the log ---

/// Remember that something happened tonight. The log is assembled from these.
function note(s: MatchState, event: string) {
  if (s.sessionEvents.indexOf(event) < 0) s.sessionEvents.push(event);
  s.sessionLogged = false;
}

/// One bottle at most per cycle, drawn by weight from whatever is eligible. The
/// tide is the delivery mechanism, so nothing arrives off-schedule.
function rollBottles(s: MatchState, dispatcher: nkruntime.MatchDispatcher, logger?: nkruntime.Logger) {
  const w = s.world;
  const eligible: string[] = [];
  let total = 0;
  for (const id in BOTTLES) {
    const b = BOTTLES[id];
    if (w.bottles[id]) continue;                       // already here, or read
    if (w.tide.cycle < b.min_tide_cycle) continue;
    if (b.requires_flag !== "" && !w.flags[b.requires_flag]) continue;
    eligible.push(id);
    total += b.weight;
  }
  if (logger) logger.info("tide %d brought in %d eligible bottle(s)", w.tide.cycle, eligible.length);
  if (!eligible.length) return;

  let pick = Math.random() * total;
  let chosen = eligible[0];
  for (let i = 0; i < eligible.length; i++) {
    pick -= BOTTLES[eligible[i]].weight;
    if (pick <= 0) { chosen = eligible[i]; break; }
  }
  w.bottles[chosen] = "washed_up";
  s.dirty = true;
  const diff: { [k: string]: string } = {};
  diff[chosen] = "washed_up";
  broadcast(dispatcher, { bottles: diff });
}

/// The evening, written down. Assembled from what actually happened rather than
/// from anything a client claims, and written at most once per session.
function writeLogEntry(
  s: MatchState, dispatcher: nkruntime.MatchDispatcher, by: string, logger?: nkruntime.Logger,
) {
  if (logger) {
    logger.info("log requested: logged=%s events=%d", String(s.sessionLogged), s.sessionEvents.length);
  }
  if (s.sessionLogged || !s.sessionEvents.length) return;
  const entry: LogEntry = {
    day: s.world.log.length + 1,
    written_by: by,
    cycle: s.world.tide.cycle,
    lines: s.sessionEvents.slice(),
  };
  s.world.log.push(entry);
  s.sessionEvents = [];
  s.sessionLogged = true;
  s.dirty = true;
  broadcast(dispatcher, { log: s.world.log });
}

// --- helpers ---

function grant(s: MatchState, id: string, n: number) {
  const w = s.world;
  w.inventory[id] = Math.max(0, (w.inventory[id] || 0) + n);
  s.dirty = true;
}

function afford(w: WorldState, costs: { [k: string]: number }): boolean {
  for (const k in costs) {
    if ((w.inventory[k] || 0) < costs[k]) return false;
  }
  return true;
}

function changedInv(w: WorldState, touched: { [k: string]: number }) {
  const out: { [k: string]: number } = {};
  for (const k in touched) out[k] = w.inventory[k] || 0;
  return out;
}

function broadcast(dispatcher: nkruntime.MatchDispatcher, diff: object) {
  dispatcher.broadcastMessage(OP.STATE_DIFF, JSON.stringify(diff));
}

// --- persistence (Nakama storage as the single source of truth) ---

function loadWorld(nk: nkruntime.Nakama, worldId: string): WorldState {
  const res = nk.storageRead([{ collection: STORAGE_WORLDS, key: worldId, userId: SYSTEM_USER }]);
  if (res.length && res[0].value) {
    const stored = res[0].value as any;
    return {
      version: stored.version || 1,
      tide: normaliseTide(stored.tide),
      flags: stored.flags || {},
      inventory: stored.inventory || {},
      milestones: stored.milestones || {},
      nodes: stored.nodes || {},
      bottles: stored.bottles || {},
      npcs: stored.npcs || {},
      log: stored.log || [],
      updated_at: stored.updated_at || 0,
    };
  }
  return freshWorld();
}

/// THE ARRIVAL (PLAN.md M9).
///
/// A new world is not an empty one. The first session used to open on a bare
/// shore with nothing to read and nothing to pick up until the tide came round
/// — the worst possible first impression of a game whose whole premise is that
/// the tide brings you things.
///
/// So the wreckage of your own arrival is already on the beach, and Elio's
/// first letter is already waiting rather than being rolled for. Everything
/// here is state a fresh world STARTS in; nothing re-applies on later loads.
function freshWorld(): WorldState {
  return {
    version: 1,
    tide: { phase: "LOW", t: 0, cycle: 0, storm: false, cycle_seconds: SECONDS_PER_CYCLE },
    flags: {},
    inventory: {},
    milestones: {},
    // Every node absent from this map is ready (see nodeIsReady), so a fresh
    // world already has its full shore — including the arrival crates — rolled
    // and waiting. Pre-rolling is the ABSENCE of state, not an entry.
    nodes: {},
    // Chapter one does not wait on the tide. bottle_01 requires no flag and no
    // cycle, so rollBottles would have produced it at the first cycle boundary
    // anyway — this just means the letter is on the sand when you arrive
    // instead of eight minutes later.
    bottles: { bottle_01: "washed_up" },
    npcs: {},
    log: [],
    updated_at: Date.now(),
  };
}

/// Worlds saved before the cycle length was tunable have no cycle_seconds.
function normaliseTide(stored: any): TideState {
  const t = stored || {};
  return {
    phase: String(t.phase || "LOW"),
    t: Number(t.t) || 0,
    cycle: Math.floor(Number(t.cycle) || 0),
    storm: !!t.storm,
    cycle_seconds: Number(t.cycle_seconds) || SECONDS_PER_CYCLE,
  };
}

function saveWorld(nk: nkruntime.Nakama, worldId: string, w: WorldState) {
  w.updated_at = Date.now();
  nk.storageWrite([{
    collection: STORAGE_WORLDS, key: worldId, userId: SYSTEM_USER,
    value: w as any, permissionRead: 2, permissionWrite: 0, // server-owned
  }]);
}
