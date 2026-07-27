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

const OP = {
  GATHER: 1,
  CRAFT: 2,
  PLACE: 3,
  ADVANCE_STEP: 4,
  READ_BOTTLE: 5,
  TANDEM: 6,       // co-op gate: { gate_id } — fires when BOTH slots submit in window
  CARRY_ASSIST: 7, // two-person carry: { object_id }
  LOG_SESSION: 8,  // request session log entry assembly
  STATE_DIFF: 100, // server -> client
} as const;

// Keeper slots: the two identities of the world. Connections CLAIM slots —
// one each online, both for couch play. All gameplay logic keys off slots.
type Slot = "keeper_a" | "keeper_b";
const SLOTS: Slot[] = ["keeper_a", "keeper_b"];
const TANDEM_WINDOW_MS = 10000;

const TICK_RATE = 2;                 // loops per second
const SECONDS_PER_CYCLE = 480;       // full LOW->...->LOW
const PHASES = ["LOW", "MID", "HIGH", "MID"]; // STORM injected occasionally

interface WorldState {
  version: number;
  tide: { phase: string; t: number; cycle: number; storm: boolean };
  flags: { [k: string]: boolean };
  inventory: { [k: string]: number };
  milestones: { [k: string]: "todo" | "in_progress" | "done" };
  presence: { [userId: string]: boolean };
  updated_at: number;
}

// Server-side recipe/cost tables. (Mirror of the .tres content; the SERVER copy
// is authoritative. Load from a storage object or bundle at deploy.)
const RECIPES: { [id: string]: { inputs: Record<string, number>; out: string; n: number } } = {
  patch_kit: { inputs: { driftwood: 3, kelp: 1 }, out: "patch_kit", n: 1 },
  // ...author the rest here / load from storage
};
const MILESTONE_COST: { [id: string]: Record<string, number> } = {
  fix_stairs: { driftwood: 5 },
  repair_lens: { brass_scrap: 3, glass_shard: 2 },
  relight_lamp: { lamp_oil: 2 },
};

let mState: {
  world: WorldState;
  worldId: string;
  // connection userId -> slots it has claimed (1 online, 2 couch)
  claims: { [userId: string]: Slot[] };
  // tandem gate bookkeeping: gate_id -> slot -> timestamp of intent
  tandem: { [gateId: string]: { [slot: string]: number } };
  dirty: boolean;
  ticksSinceSave: number;
};

const matchInit: nkruntime.MatchInitFunction = (ctx, logger, nk, params) => {
  const worldId = (params["world_id"] as string) || "default";
  const world = loadWorld(nk, worldId);
  mState = { world, worldId, claims: {}, tandem: {}, dirty: false, ticksSinceSave: 0 };
  return { state: mState, tickRate: TICK_RATE, label: "lighthouse" };
};

const matchJoinAttempt: nkruntime.MatchJoinAttemptFunction = (
  ctx, logger, nk, dispatcher, tick, state, presence, metadata,
) => {
  // metadata.slots: "keeper_a" | "keeper_b" | "both". Reject if requested
  // slot(s) are already claimed by a DIFFERENT connection.
  const wanted = parseSlots(metadata && (metadata as any).slots);
  if (!wanted.length) {
    return { state, accept: false, rejectMessage: "No keeper slot requested." };
  }
  for (const s of wanted) {
    const owner = slotOwner(s);
    if (owner && owner !== presence.userId) {
      return { state, accept: false, rejectMessage: `${s} is already taken.` };
    }
  }
  return { state, accept: true };
};

function parseSlots(v: any): Slot[] {
  if (v === "both") return ["keeper_a", "keeper_b"];
  if (v === "keeper_a" || v === "keeper_b") return [v];
  return [];
}
function slotOwner(slot: Slot): string | null {
  for (const uid in mState.claims) if (mState.claims[uid].indexOf(slot) >= 0) return uid;
  return null;
}

const matchJoin: nkruntime.MatchJoinFunction = (ctx, logger, nk, dispatcher, tick, state, presences) => {
  for (const p of presences) {
    // Slots were validated in join attempt; re-parse from claims or default.
    // Nakama passes metadata at attempt time; store claim now via first-free fallback.
    if (!mState.claims[p.userId]) {
      const free = SLOTS.filter((s) => !slotOwner(s));
      mState.claims[p.userId] = free.length === 2 ? [free[0]] : free; // refined by claim_slots signal if couch
    }
    for (const s of mState.claims[p.userId]) mState.world.presence[s] = true;
  }
  // Send the full snapshot to the joiner(s) so they sync immediately.
  dispatcher.broadcastMessage(OP.STATE_DIFF, JSON.stringify(snapshot(mState.world)), presences);
  broadcast(dispatcher, { presence: mState.world.presence });
  return { state };
};

const matchLeave: nkruntime.MatchLeaveFunction = (ctx, logger, nk, dispatcher, tick, state, presences) => {
  for (const p of presences) {
    for (const s of mState.claims[p.userId] || []) mState.world.presence[s] = false;
    delete mState.claims[p.userId];
  }
  broadcast(dispatcher, { presence: mState.world.presence });
  saveWorld(nk, mState.worldId, mState.world);
  return { state };
};

const matchLoop: nkruntime.MatchLoopFunction = (ctx, logger, nk, dispatcher, tick, state, messages) => {
  // 1) advance the tide ONLY when at least one keeper is present (design choice).
  const anyone = Object.values(mState.world.presence).some(Boolean);
  if (anyone) advanceTide(dispatcher);

  // 2) process incoming commands authoritatively.
  for (const msg of messages) {
    const data = msg.data ? JSON.parse(nk.binaryToString(msg.data)) : {};
    handleCommand(msg.opCode, data, msg.sender.userId, dispatcher, logger);
  }

  // 3) periodic persistence.
  if (mState.dirty && ++mState.ticksSinceSave >= TICK_RATE * 10) {
    saveWorld(nk, mState.worldId, mState.world);
    mState.dirty = false;
    mState.ticksSinceSave = 0;
  }
  return { state: mState };
};

const matchTerminate: nkruntime.MatchTerminateFunction = (ctx, logger, nk, dispatcher, tick, state) => {
  saveWorld(nk, mState.worldId, mState.world);
  return { state };
};
const matchSignal: nkruntime.MatchSignalFunction = (ctx, logger, nk, d, tick, state, data) => {
  return { state, data };
};

// --- command handling (the validation layer) ---

function handleCommand(
  op: number, data: any, userId: string,
  dispatcher: nkruntime.MatchDispatcher, logger: nkruntime.Logger,
) {
  const w = mState.world;
  switch (op) {
    case OP.GATHER: {
      // TODO: look up node -> yield; for now grant 1 driftwood as illustration.
      grant(w, "driftwood", 1);
      broadcast(dispatcher, { inventory: { driftwood: w.inventory["driftwood"] } });
      break;
    }
    case OP.CRAFT: {
      const r = RECIPES[data.recipe_id];
      if (!r || !afford(w, r.inputs)) return;            // silent reject = cozy
      for (const k in r.inputs) grant(w, k, -r.inputs[k]);
      grant(w, r.out, r.n);
      broadcast(dispatcher, { inventory: changedInv(w, { ...r.inputs, [r.out]: r.n }) });
      break;
    }
    case OP.ADVANCE_STEP: {
      const cost = MILESTONE_COST[data.milestone_id];
      if (!cost || !afford(w, cost)) return;
      for (const k in cost) grant(w, k, -cost[k]);
      w.milestones[data.milestone_id] = "done";
      mState.dirty = true;
      broadcast(dispatcher, {
        inventory: changedInv(w, cost),
        milestones: { [data.milestone_id]: "done" },
      });
      break;
    }
    case OP.READ_BOTTLE: {
      const flag = "read_" + data.bottle_id;
      w.flags[flag] = true; mState.dirty = true;
      broadcast(dispatcher, { flags: { [flag]: true } });
      break;
    }
    case OP.TANDEM: {
      // CO-OP GATE: fires when BOTH slots submit the same gate within the
      // window — regardless of whether that's two connections (online) or one
      // connection driving both pads (couch). Couch payload carries `slot`;
      // online derives it from the connection's single claim.
      const gateId: string = data.gate_id;
      if (!gateId || w.flags[gateId]) return;
      const slot = resolveSlot(userId, data.slot);
      if (!slot) return;
      const now = Date.now();
      const votes = (mState.tandem[gateId] = mState.tandem[gateId] || {});
      votes[slot] = now;
      const live = SLOTS.filter((s) => votes[s] && now - votes[s] <= TANDEM_WINDOW_MS);
      broadcast(dispatcher, { tandem: { gate_id: gateId, waiting: SLOTS.filter((s) => live.indexOf(s) < 0) } });
      if (live.length === 2) {
        w.flags[gateId] = true; mState.dirty = true;
        delete mState.tandem[gateId];
        broadcast(dispatcher, { flags: { [gateId]: true } });
      }
      break;
    }
    case OP.CARRY_ASSIST: {
      // Same both-slots pattern, scoped to a carryable object; flag toggles
      // while both hold. v1: mark intent flag, client handles the visual.
      const objId: string = data.object_id;
      if (!objId) return;
      const slot = resolveSlot(userId, data.slot);
      if (!slot) return;
      w.flags[`carry_${objId}_${slot}`] = true;
      broadcast(dispatcher, { flags: { [`carry_${objId}_${slot}`]: true } });
      break;
    }
    case OP.LOG_SESSION: {
      // TODO(M6): assemble a keeper's-log entry from this session's diffs and
      // append to a storage-backed log list. Stub: set a flag clients render.
      break;
    }
  }
}

// --- tide ---

function advanceTide(dispatcher: nkruntime.MatchDispatcher) {
  const t = mState.world.tide;
  const step = 1 / (SECONDS_PER_CYCLE * TICK_RATE);
  const before = t.t;
  t.t += step;
  if (t.t >= 1) { t.t -= 1; t.cycle += 1; }
  // phase index from t (4 phases per cycle), with rare storm on HIGH.
  const idx = Math.floor(t.t * PHASES.length) % PHASES.length;
  const newPhase = PHASES[idx];
  if (newPhase !== t.phase) {
    t.phase = newPhase;
    broadcast(dispatcher, { tide: { phase: t.phase, t: t.t, cycle: t.cycle, storm: t.storm } });
  } else if (Math.floor(before * 20) !== Math.floor(t.t * 20)) {
    // lightweight progress ticks for smooth client interpolation
    broadcast(dispatcher, { tide: { phase: t.phase, t: t.t, cycle: t.cycle, storm: t.storm } });
  }
}

function resolveSlot(userId: string, explicit?: string): Slot | null {
  const claimed = mState.claims[userId] || [];
  if (explicit === "keeper_a" || explicit === "keeper_b") {
    return claimed.indexOf(explicit) >= 0 ? explicit : null;
  }
  return claimed.length === 1 ? claimed[0] : null;
}

// --- helpers ---

function grant(w: WorldState, id: string, n: number) {
  w.inventory[id] = Math.max(0, (w.inventory[id] || 0) + n);
  mState.dirty = true;
}
function afford(w: WorldState, costs: Record<string, number>): boolean {
  return Object.entries(costs).every(([k, n]) => (w.inventory[k] || 0) >= n);
}
function changedInv(w: WorldState, touched: Record<string, number>) {
  const out: Record<string, number> = {};
  for (const k in touched) out[k] = w.inventory[k] || 0;
  return out;
}
function broadcast(dispatcher: nkruntime.MatchDispatcher, diff: object) {
  dispatcher.broadcastMessage(OP.STATE_DIFF, JSON.stringify(diff));
}
function snapshot(w: WorldState) {
  return { tide: w.tide, flags: w.flags, inventory: w.inventory,
           milestones: w.milestones, presence: w.presence };
}

// --- persistence (Nakama storage as the single source of truth) ---

function loadWorld(nk: nkruntime.Nakama, worldId: string): WorldState {
  const res = nk.storageRead([{ collection: "worlds", key: worldId, userId: "" }]);
  if (res.length && res[0].value) return res[0].value as WorldState;
  return {
    version: 1,
    tide: { phase: "LOW", t: 0, cycle: 0, storm: false },
    flags: {}, inventory: {}, milestones: {}, presence: {},
    updated_at: Date.now(),
  };
}
function saveWorld(nk: nkruntime.Nakama, worldId: string, w: WorldState) {
  w.updated_at = Date.now();
  nk.storageWrite([{
    collection: "worlds", key: worldId, userId: "",
    value: w, permissionRead: 2, permissionWrite: 0, // server-owned
  }]);
}

// Export for main.ts registration.
// initializer.registerMatch("lighthouse", {
//   matchInit, matchJoinAttempt, matchJoin, matchLeave,
//   matchLoop, matchTerminate, matchSignal,
// });
