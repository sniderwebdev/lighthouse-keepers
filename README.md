# Lighthouse Keepers — implementation pack

Everything an implementing Claude (or you) needs, in reading order:
1. `DESIGN.md` — vision, systems, art spec (the WHY and WHAT)
2. `CLAUDE.md` — repo law: architecture, controller-first, art constraints (the RULES)
3. `PLAN.md`  — milestone ladder M0→M7 with acceptance criteria (the ORDER)
4. This file  — architecture map + how to run (the HOW)

Locked decisions: top-down 3/4 · couch AND online co-op via keeper slots ·
controller-first · PC now console-ready later · 640×360 integer-scaled pixel art.

The expandable, co-op-ready spine for the game in `DESIGN.md`. This is a skeleton:
it demonstrates the architecture and compiles-shaped patterns, but the Nakama addon
wiring and content are left as marked TODOs. Built for Godot 4 + Nakama.

## The one idea

A client never mutates shared state. It sends an **intent** (a `Command`) to the
authoritative Nakama match, which validates, applies, persists, and broadcasts an
authoritative **diff**. Clients just render what the server confirms. This is the only
thing you can't bolt on later, so it's wired from the start — and it's the same clean
seam that makes single-player tidy too.

```
 player input ─▶ Command.make(op,payload) ─▶ Net.send_command()
                                                   │  (Nakama socket, opcode)
                                                   ▼
                                    nakama/match_handler.ts  ← source of truth
                                       • owns the tide clock
                                       • validates every command
                                       • mutates world state
                                       • persists to storage
                                       • broadcasts STATE_DIFF
                                                   │
                              ┌────────────────────┴───────────────────┐
                              ▼                                         ▼
                   Net._on_match_state                       (the other keeper)
                              │
                   WorldState.apply_diff()
                              │  re-emits granular signals
                              ▼
                         EventBus  ─▶  UI / world / audio react locally
```

## Files

```
godot/
  project.godot                 autoloads: EventBus, Net, WorldState
  autoload/
    event_bus.gd                local decoupled signals (never crosses the wire)
    net.gd                      Nakama client wrapper: auth, join, send/receive
    world_state.gd              client mirror; applies diffs, emits signals
  game/
    command.gd                  serializable intents + opcodes (sync w/ server)
    tide_clock.gd               smooth client interpolation of authoritative tide
  resources/
    item_def.gd recipe_def.gd milestone_def.gd bottle_def.gd
                                data-driven content schemas (.tres per entry)
nakama/
  match_handler.ts              authoritative world: tide loop + command validation
DESIGN.md                       the living design doc
```

## Run it

**Build the server runtime BEFORE bringing the stack up** — compose mounts only
`nakama/build/`, which does not exist in a fresh checkout.

```sh
cd nakama && npm install && npx tsc && cd ..   # -> nakama/build/index.js
docker compose up -d                            # Nakama + Postgres
docker compose logs nakama | grep "runtime loaded"
```

Nakama console: `http://127.0.0.1:7351` (admin / lighthousedev1). Game socket: `7350`.

**Client.** The [nakama-godot](https://github.com/heroiclabs/nakama-godot) addon is
vendored at `godot/addons/com.heroiclabs.nakama/` (see `INSTALLED_FROM.txt`) and
registered as the `Nakama` autoload. Open `godot/` in Godot 4 and run — the main
scene is `scenes/boot.tscn`.

Launch flags (after a `--` separator when using the CLI):

| Flag | Effect |
|---|---|
| `--slot=keeper_a` / `--slot=keeper_b` | claim one keeper (online play) |
| `--couch` | couch play on one machine: claim keeper A now, keeper B when a second player touches pad 2 or the arrow keys |
| `--couch-both` | claim BOTH slots immediately, no waiting (what the harness uses — synthesized input has no hands to wait for) |
| `--world=TEST01` | world code to join (default `TEST01`) |
| `--host= --port=` | point at a non-local server |
| `--scene=beach` / `--scene=tower` / `--scene=room` | which space to enter |
| `--net-verbose` | dump the Nakama wire trace |
| `--shot=/abs/path.png` | grab the 640×360 viewport, then quit |

```sh
# two keepers, online, on one PC
godot --path godot -- --slot=keeper_a --world=TEST01
godot --path godot -- --slot=keeper_b --world=TEST01
# one PC, two pads
godot --path godot -- --couch --world=TEST01
```

**Verify the milestones:** `tools/verify_m0.sh` … `verify_m7.sh` run every
acceptance criterion for their milestone against the live stack and write
evidence to `.m0-evidence/` … `.m7-evidence/`. Each run uses a fresh world code,
so they are safe to re-run.

**Playing it.** Run with no flags and you get the title screen: pick a world code
with the stick, choose couch or online, choose a keeper. The flags below are for
launching straight past it, which is what the verifiers do.

**The tide.** One cycle is eight real minutes (`LOW → MID → HIGH → MID`), and it
only advances while at least one keeper is connected. The sky's colour IS the
tide readout — there is no meter, by design (DESIGN §2). Because eight minutes is
a long time to wait for a phase, the local stack exposes a `debug_set_tide` RPC
that jumps the clock; it answers only when Nakama is started with
`LIGHTHOUSE_DEV=1`, which `docker-compose.yml` sets and a real deploy would not.

```sh
curl -s -X POST http://127.0.0.1:7350/v2/rpc/debug_set_tide \
  -H "Authorization: Bearer $TOKEN" \
  -d '"{\"world_code\":\"TEST01\",\"t\":0.5}"'   # 0.0 LOW, 0.25 MID, 0.5 HIGH
```

**Next content:** author `.tres` files under `godot/content/{items,recipes,
milestones,bottles}/`, and mirror the authoritative recipe/cost tables in
`match_handler.ts`. Wire a button to `Net.send_command(Command.gather("driftwood_01"))`
and watch the inventory update on both clients.

## Keeper slots (couch + online unified)

The world has two identities: `keeper_a` and `keeper_b`. A connection CLAIMS
slots at join — one each for online play, both for couch play (one machine, two
pads). Presence, tandem gates, and per-keeper logic all key off slots, so both
play modes are the same server code path. Slot-sensitive commands carry `slot`.

## What's intentionally NOT here yet

Rendering, scenes, character controllers, inventory UI, the bottle reader, and the
boat/season/NPC expansion systems — M0→M7 in PLAN.md builds them in order. Add
content, not architecture.
