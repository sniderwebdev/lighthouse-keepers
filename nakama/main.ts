// main.ts — Nakama TS runtime entrypoint.
// Registers the lighthouse match and the join_world RPC that resolves a human
// world code ("TEST01") to a match id, creating the world on first join.

const STORAGE_WORLD_INDEX = "world_index";
// Server-owned storage records. An empty string is NOT accepted as a userId;
// the nil UUID is how the runtime spells "belongs to the system".
const SYSTEM_USER = "00000000-0000-0000-0000-000000000000";

let InitModule: nkruntime.InitModule = function (ctx, logger, nk, initializer) {
  initializer.registerMatch("lighthouse", {
    matchInit,
    matchJoinAttempt,
    matchJoin,
    matchLeave,
    matchLoop,
    matchTerminate,
    matchSignal,
  });

  // The runtime extracts handlers by identifier — an inline function literal
  // here fails registration ("javascript functions cannot be inlined").
  initializer.registerRpc("join_world", rpcJoinWorld);

  // Dev-only. A full tide cycle is eight minutes by design, which makes phase
  // behaviour untestable in any reasonable time, so the local stack can jump the
  // clock. The guard lives inside the handler rather than around this call: the
  // runtime resolves handler names by static analysis and cannot see an
  // identifier nested inside an `if`.
  initializer.registerRpc("debug_set_tide", rpcDebugSetTide);
  if (ctx.env["LIGHTHOUSE_DEV"] === "1") {
    logger.warn("LIGHTHOUSE_DEV=1: debug_set_tide will answer. Never set this in production.");
  }

  logger.info("lighthouse runtime loaded");
};

// rpc join_world: payload {"world_code":"TEST01"} -> {"match_id":"..."}
// World codes map 1:1 to persistent worlds; the code is the storage key.
const rpcJoinWorld: nkruntime.RpcFunction = function (ctx, logger, nk, payload) {
  const req = JSON.parse(payload || "{}");
  const code: string = String(req.world_code || "").toUpperCase().replace(/\s/g, "");
  if (!/^[A-Z0-9]{4,8}$/.test(code)) {
    throw Error("world_code must be 4-8 alphanumerics");
  }
  const matchId = resolveWorldMatch(nk, logger, code);
  return JSON.stringify({ match_id: matchId, world_code: code });
};

// rpc debug_set_tide: payload {"world_code":"TEST01","t":0.26} -> {"phase":"MID"}
// Jumps a world's tide clock so phase behaviour can be tested without waiting
// out an eight-minute cycle. Refuses outright unless the runtime was explicitly
// started as a dev server, so a production deploy answers nothing here.
const rpcDebugSetTide: nkruntime.RpcFunction = function (ctx, logger, nk, payload) {
  if (ctx.env["LIGHTHOUSE_DEV"] !== "1") {
    throw Error("debug_set_tide is not enabled on this server");
  }
  const req = JSON.parse(payload || "{}");
  const code: string = String(req.world_code || "").toUpperCase().replace(/\s/g, "");
  if (!/^[A-Z0-9]{4,8}$/.test(code)) {
    throw Error("world_code must be 4-8 alphanumerics");
  }
  const index = readWorldIndex(nk, code);
  if (!index.matchId || !matchIsLive(nk, index.matchId)) {
    throw Error("world " + code + " has no live match");
  }
  // The tide lives inside the match, and a match can only be reached from an
  // RPC by signalling it.
  // Forward the cycle too when one was asked for. Without it the receiving end
  // sees no cycle at all and quietly leaves the clock's cycle where it was.
  const signal: { [k: string]: any } = { op: "set_tide", t: Number(req.t) };
  if (req.cycle !== undefined) signal.cycle = Number(req.cycle);
  return nk.matchSignal(index.matchId, JSON.stringify(signal));
};

interface WorldIndex {
  matchId: string | null;
  version: string | null;   // null when the record does not exist yet
}

// One world code -> exactly one live match. Three lookups, cheapest first: the
// remembered id, then the match label index, then create.
//
// Two keepers launching together call this in the same millisecond, in separate
// runtime VMs, and both find nothing. Whoever creates a match second must NOT
// keep it, or the couple ends up alone in two identical worlds — so the index
// write is a conditional claim and the loser adopts the winner's match.
function resolveWorldMatch(nk: nkruntime.Nakama, logger: nkruntime.Logger, code: string): string {
  const index = readWorldIndex(nk, code);
  if (index.matchId && matchIsLive(nk, index.matchId)) return index.matchId;

  // matchList takes EITHER a plain label or a query, never both — passing the
  // module name as `label` while also passing a query matches nothing, which is
  // how you end up with a second live match for a world that already exists.
  const found = nk.matchList(1, true, null, null, null, "+label.world:" + code);
  if (found.length) {
    claimWorldIndex(nk, code, found[0].matchId, index.version);
    return found[0].matchId;
  }

  const created = nk.matchCreate("lighthouse", { world_id: code });
  if (claimWorldIndex(nk, code, created, index.version)) {
    logger.info("created world %s as match %s", code, created);
    return created;
  }

  // Lost the claim. Somebody else's match is the world now; ours was never
  // joined and idles itself out (see IDLE_TERMINATE_TICKS in match_handler).
  const winner = readWorldIndex(nk, code);
  logger.info("world %s was claimed concurrently; joining %s and discarding %s",
    code, winner.matchId, created);
  return winner.matchId || created;
}

function matchIsLive(nk: nkruntime.Nakama, matchId: string): boolean {
  try {
    return nk.matchGet(matchId) !== null;
  } catch (e) {
    return false; // stale id left over from a previous server run
  }
}

function readWorldIndex(nk: nkruntime.Nakama, code: string): WorldIndex {
  const res = nk.storageRead([{ collection: STORAGE_WORLD_INDEX, key: code, userId: SYSTEM_USER }]);
  if (res.length && res[0].value && (res[0].value as any).match_id) {
    return { matchId: String((res[0].value as any).match_id), version: res[0].version || null };
  }
  return { matchId: null, version: null };
}

/// Compare-and-swap on the index. `expectedVersion` is the version this caller
/// read, or null if it saw no record at all — "*" then means "only if it still
/// does not exist". Returns false when somebody else got there first.
function claimWorldIndex(
  nk: nkruntime.Nakama, code: string, matchId: string, expectedVersion: string | null,
): boolean {
  try {
    nk.storageWrite([{
      collection: STORAGE_WORLD_INDEX, key: code, userId: SYSTEM_USER,
      value: { match_id: matchId }, version: expectedVersion || "*",
      permissionRead: 2, permissionWrite: 0,
    }]);
    return true;
  } catch (e) {
    return false;
  }
}

// Reference so tsc keeps it.
// @ts-ignore: intentional no-op reference to preserve the symbol
!InitModule && InitModule.bind(null);
