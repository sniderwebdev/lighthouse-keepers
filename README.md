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

1. **Server:** install Nakama (Docker is easiest). Add the TS runtime, register the
   match in `main.ts` (`initializer.registerMatch("lighthouse", {...})`), `tsc`, mount
   `build/index.js`. Bring up Nakama + Postgres.
2. **Client:** drop the [nakama-godot](https://github.com/heroiclabs/nakama-godot)
   addon into the Godot project, then fill the TODOs in `net.gd` (auth, socket,
   join match). Point `host`/`port` at your server.
3. **First content:** author a few `.tres` files under `godot/content/{items,recipes,
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
