// main.ts — Nakama TS runtime entrypoint.
// Registers the lighthouse match and the join_world RPC that resolves a human
// world code ("TEST01") to a match id, creating the world on first join.

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

  // rpc join_world: payload {"world_code":"TEST01"} -> {"match_id":"..."}
  // World codes map 1:1 to persistent worlds; the code is the storage key.
  initializer.registerRpc("join_world", (ctx, logger, nk, payload) => {
    const req = JSON.parse(payload || "{}");
    const code: string = (req.world_code || "").toUpperCase().trim();
    if (!/^[A-Z0-9]{4,8}$/.test(code)) {
      throw JSON.stringify({ code: 3, message: "world_code must be 4-8 alphanumerics" });
    }
    // Find a live match for this world, else create one.
    const matches = nk.matchList(10, true, "lighthouse", 0, 2, `+label.world:${code}`);
    const matchId = matches.length
      ? matches[0].matchId
      : nk.matchCreate("lighthouse", { world_id: code });
    return JSON.stringify({ match_id: matchId });
  });

  logger.info("lighthouse runtime loaded");
};

// Reference so tsc keeps it.
!InitModule && InitModule.bind(null);
