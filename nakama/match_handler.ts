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

  // Not commands. Where a keeper APPEARS to be is presentation, not authoritative
  // shared state (PLAN.md M1): never validated against the world, never persisted,
  // never merged into WorldState. Relayed only.
  POSE: 20,        // client -> server: { slot, x, y, f, t }
  POSE_ECHO: 120,  // server -> clients: { poses: { slot: {x,y,f,t} } }

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

interface TideState {
  phase: string;
  t: number;
  cycle: number;
  storm: boolean;
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
  updated_at: number;
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
  dirty: boolean;
  ticksSinceSave: number;
  idleTicks: number;
}

interface Pose {
  x: number;
  y: number;
  f: number;  // facing, 0-7
  t: number;  // SENDER's clock in ms, relayed untouched
}

// Server-side recipe/cost tables. (Mirror of the .tres content; the SERVER copy
// is authoritative. Load from a storage object or bundle at deploy.)
const RECIPES: { [id: string]: { inputs: { [k: string]: number }; out: string; n: number } } = {
  patch_kit: { inputs: { driftwood: 3, kelp: 1 }, out: "patch_kit", n: 1 },
  // ...author the rest here / load from storage
};
const MILESTONE_COST: { [id: string]: { [k: string]: number } } = {
  fix_stairs: { driftwood: 5 },
  repair_lens: { brass_scrap: 3, glass_shard: 2 },
  relight_lamp: { lamp_oil: 2 },
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
        presence: s.presence,
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
    if (s.idleTicks >= IDLE_TERMINATE_TICKS) {
      saveWorld(nk, s.worldId, s.world);
      logger.info("world %s idle, closing", s.worldId);
      return null;
    }
  }

  // 1) advance the tide ONLY when at least one keeper is present (design choice).
  if (anyonePresent(s)) advanceTide(s, dispatcher);

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
    handleCommand(s, msg.opCode, data, msg.sender.sessionId, dispatcher, logger);
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

const matchSignal: nkruntime.MatchSignalFunction = (ctx, logger, nk, d, tick, state, data) => {
  return { state: state, data: data };
};

// --- command handling (the validation layer) ---

function handleCommand(
  s: MatchState, op: number, data: any, sessionId: string,
  dispatcher: nkruntime.MatchDispatcher, logger: nkruntime.Logger,
) {
  const w = s.world;
  switch (op) {
    case OP.GATHER: {
      // TODO(M3): look up node -> yield; for now grant 1 driftwood as illustration.
      grant(s, "driftwood", 1);
      broadcast(dispatcher, { inventory: { driftwood: w.inventory["driftwood"] } });
      break;
    }
    case OP.CRAFT: {
      const r = RECIPES[data.recipe_id];
      if (!r || !afford(w, r.inputs)) return;            // silent reject = cozy
      for (const k in r.inputs) grant(s, k, -r.inputs[k]);
      grant(s, r.out, r.n);
      const touchedCraft: { [k: string]: number } = {};
      for (const k in r.inputs) touchedCraft[k] = 0;
      touchedCraft[r.out] = 0;
      broadcast(dispatcher, { inventory: changedInv(w, touchedCraft) });
      break;
    }
    case OP.ADVANCE_STEP: {
      const cost = MILESTONE_COST[data.milestone_id];
      if (!cost || !afford(w, cost)) return;
      for (const k in cost) grant(s, k, -cost[k]);
      w.milestones[data.milestone_id] = "done";
      s.dirty = true;
      const done: { [k: string]: string } = {};
      done[data.milestone_id] = "done";
      broadcast(dispatcher, { inventory: changedInv(w, cost), milestones: done });
      break;
    }
    case OP.READ_BOTTLE: {
      const flag = "read_" + data.bottle_id;
      w.flags[flag] = true;
      s.dirty = true;
      const fdiff: { [k: string]: boolean } = {};
      fdiff[flag] = true;
      broadcast(dispatcher, { flags: fdiff });
      break;
    }
    case OP.TANDEM: {
      // CO-OP GATE: fires when BOTH slots submit the same gate within the
      // window — regardless of whether that's two connections (online) or one
      // connection driving both pads (couch). Couch payload carries `slot`;
      // online derives it from the connection's single claim.
      const gateId: string = data.gate_id;
      if (!gateId || w.flags[gateId]) return;
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
        w.flags[gateId] = true;
        s.dirty = true;
        delete s.tandem[gateId];
        const gdiff: { [k: string]: boolean } = {};
        gdiff[gateId] = true;
        broadcast(dispatcher, { flags: gdiff });
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
    case OP.LOG_SESSION: {
      // TODO(M6): assemble a keeper's-log entry from this session's diffs and
      // append to a storage-backed log list.
      break;
    }
  }
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
  const step = 1 / (SECONDS_PER_CYCLE * TICK_RATE);
  const before = t.t;
  t.t += step;
  if (t.t >= 1) {
    t.t -= 1;
    t.cycle += 1;
  }
  // phase index from t (4 phases per cycle), with rare storm on HIGH.
  const idx = Math.floor(t.t * PHASES.length) % PHASES.length;
  const newPhase = PHASES[idx];
  if (newPhase !== t.phase) {
    t.phase = newPhase;
    s.dirty = true;
    broadcast(dispatcher, { tide: { phase: t.phase, t: t.t, cycle: t.cycle, storm: t.storm } });
  } else if (Math.floor(before * 20) !== Math.floor(t.t * 20)) {
    // lightweight progress ticks for smooth client interpolation
    broadcast(dispatcher, { tide: { phase: t.phase, t: t.t, cycle: t.cycle, storm: t.storm } });
  }
}

function resolveSlot(s: MatchState, sessionId: string, explicit?: string): Slot | null {
  const claimed = s.claims[sessionId] || [];
  if (explicit === "keeper_a" || explicit === "keeper_b") {
    return claimed.indexOf(explicit) >= 0 ? explicit : null;
  }
  return claimed.length === 1 ? claimed[0] : null;
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
      tide: stored.tide || { phase: "LOW", t: 0, cycle: 0, storm: false },
      flags: stored.flags || {},
      inventory: stored.inventory || {},
      milestones: stored.milestones || {},
      updated_at: stored.updated_at || 0,
    };
  }
  return {
    version: 1,
    tide: { phase: "LOW", t: 0, cycle: 0, storm: false },
    flags: {},
    inventory: {},
    milestones: {},
    updated_at: Date.now(),
  };
}

function saveWorld(nk: nkruntime.Nakama, worldId: string, w: WorldState) {
  w.updated_at = Date.now();
  nk.storageWrite([{
    collection: STORAGE_WORLDS, key: worldId, userId: SYSTEM_USER,
    value: w as any, permissionRead: 2, permissionWrite: 0, // server-owned
  }]);
}
