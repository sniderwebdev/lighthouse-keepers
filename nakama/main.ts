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

// One world code -> exactly one live match. Three lookups, cheapest first:
// the remembered id, then the match label index, then create.
function resolveWorldMatch(nk: nkruntime.Nakama, logger: nkruntime.Logger, code: string): string {
  const remembered = readWorldIndex(nk, code);
  if (remembered && matchIsLive(nk, remembered)) return remembered;

  // matchList takes EITHER a plain label or a query, never both — passing the
  // module name as `label` while also passing a query matches nothing, which is
  // how you end up with a second live match for a world that already exists.
  const found = nk.matchList(1, true, null, null, null, "+label.world:" + code);
  if (found.length) {
    writeWorldIndex(nk, code, found[0].matchId);
    return found[0].matchId;
  }

  const created = nk.matchCreate("lighthouse", { world_id: code });
  writeWorldIndex(nk, code, created);
  logger.info("created world %s as match %s", code, created);
  return created;
}

function matchIsLive(nk: nkruntime.Nakama, matchId: string): boolean {
  try {
    return nk.matchGet(matchId) !== null;
  } catch (e) {
    return false; // stale id left over from a previous server run
  }
}

function readWorldIndex(nk: nkruntime.Nakama, code: string): string | null {
  const res = nk.storageRead([{ collection: STORAGE_WORLD_INDEX, key: code, userId: SYSTEM_USER }]);
  if (res.length && res[0].value && (res[0].value as any).match_id) {
    return String((res[0].value as any).match_id);
  }
  return null;
}

function writeWorldIndex(nk: nkruntime.Nakama, code: string, matchId: string): void {
  nk.storageWrite([{
    collection: STORAGE_WORLD_INDEX, key: code, userId: SYSTEM_USER,
    value: { match_id: matchId }, permissionRead: 2, permissionWrite: 0,
  }]);
}

// Reference so tsc keeps it.
// @ts-ignore: intentional no-op reference to preserve the symbol
!InitModule && InitModule.bind(null);
