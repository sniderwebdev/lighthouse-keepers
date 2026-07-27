# CLAUDE.md — rules for implementing The Lighthouse Keepers

You are implementing a cozy two-player lighthouse-restoration game. Read `DESIGN.md`
for the vision and systems; read `PLAN.md` for the milestone ladder and what to build
next. This file is the law of the repo: conventions and constraints that apply to
every task. When a task conflicts with this file, this file wins; if something here
seems wrong, stop and ask rather than silently deviating.

## Tech pins

- **Godot 4.3+** (GDScript, typed). Project lives in `godot/`.
- **Nakama 3.x** server, **TypeScript runtime** in `nakama/` (tsc → `nakama/build/`).
- **nakama-godot** addon for the client (`godot/addons/com.heroiclabs.nakama/`).
- Local stack via `docker-compose.yml` at repo root (Nakama + Postgres).
- Do not add other networking layers, ENet, or Godot high-level multiplayer. All
  shared state flows through the Nakama match. No exceptions.

## Architecture law (non-negotiable)

1. **Clients never mutate shared state.** Every state-changing player action is a
   `Command` (see `godot/game/command.gd`) sent via `Net.send_command()`. The match
   (`nakama/match_handler.ts`) validates, applies, persists, broadcasts diffs.
2. **`WorldState` is a read-only mirror** on the client. Systems read it and listen
   to `EventBus` echoes. If you find yourself writing to `WorldState` outside
   `apply_diff()`, you are doing it wrong.
3. **Opcodes and payload shapes must stay in sync** between `command.gd` and
   `match_handler.ts`. Any change touches both files in the same commit.
4. **Keeper slots, not connections.** The world has exactly two keeper identities:
   `keeper_a` and `keeper_b`. A connection *claims* one slot (online play) or both
   (couch play — one machine, two controllers). All gameplay logic (presence,
   tandem gates, per-keeper position) is keyed by slot, never by socket/userId.
   This is how couch and online co-op are the same code path.
5. **Tandem gates** (`TANDEM` opcode) fire only when *both slots* have submitted
   the matching intent within the gate window — regardless of how many
   connections those slots arrive on.
6. **Content is data.** Items, recipes, milestones, bottles, NPC stages are `.tres`
   resources under `godot/content/`, mirrored in authoritative server tables.
   Never hardcode content values in scenes or scripts.

## Controller-first law (non-negotiable)

The game must be fully playable start-to-finish with a gamepad, designed for
gamepad *first*. Keyboard/mouse is an adaptation, never the design target.

- **Input actions, never raw keys/buttons.** All input goes through the actions
  defined in `project.godot` (`move_*`, `interact`, `cancel`, `use_tool`,
  `menu_radial`, `menu_pause`, plus `p2_*` mirrors for the second local pad).
- **One context-sensitive interact button.** Proximity + facing selects the target;
  a small prompt shows what `interact` will do. No cursors, no click targets.
- **All menus navigable by d-pad/stick + confirm/cancel.** Crafting and inventory
  are grid or radial UIs with visible focus. Every focusable element must be
  reachable by directional navigation (test: unplug the mouse).
- **Text advances on button press**, never on click or timer alone.
- **Couch = two pads on one machine.** Device 0 → the slot chosen at session start,
  device 1 → the other. Never assume keyboard exists.
- **Console-ready posture:** UI respects a 5% overscan safe area; all text ≥ the
  equivalent of 16px at 1080p; button glyphs come from one glyph helper so they
  can be re-skinned per platform later; no OS dialogs, no file pickers.

## Rendering & art law

- **Base viewport 640×360, integer-scaled.** `viewport` stretch mode, `integer`
  scale. Camera uses pixel snapping. No sub-pixel movement on sprites.
- **Perspective: top-down 3/4** (Winter Burrow-style). Y-sort for depth; feet are
  the sort origin. The side-view concept art is key-art/cutscene style, not the
  gameplay projection.
- **Palette is locked** — use only the ramps in `DESIGN.md` §6. New art must
  quantize to those ramps. The warm/cool law applies: warm colors only for people,
  story objects, and light sources.
- **The sky ramp is the tide UI.** Sky/ambient tint is derived from
  `WorldState.tide` via the ramp lookup — do not build a separate tide meter.
- No smooth gradients; dither at band boundaries. No rotation on pixel sprites;
  use flipping and drawn frames.

## Code conventions

- GDScript: typed everywhere (`var x: int`), signals via `EventBus`, node paths via
  `%UniqueName` or exported NodePaths — never brittle absolute paths.
- Scenes: one scene per logical entity; `snake_case` filenames; scene root script
  matches scene name.
- Server TS: no `any` on new code; pure functions for validation logic so they're
  unit-testable; every opcode handler validates before mutating.
- Commits: one milestone sub-task per commit, message prefixed with the milestone
  id (`M2: beach colliders follow tide phase`).

## Definition of done (every task)

- Meets the acceptance criteria listed for it in `PLAN.md` — literally, as written.
- Works with gamepad only (unplug the mouse).
- Works in BOTH play modes: two instances online, and one instance with two pads.
- No client-side mutation of shared state snuck in.
- `godot --headless --check-only` passes (script errors) and `tsc` compiles clean.

## UI mock gate (author-in-the-loop)

Five screens have visual reference mocks that the AUTHOR produces in Claude
Design using `design/UI_BRIEF.md`. They land as PNGs in `design/ui/`:

| Screen | Expected file | Needed by |
|---|---|---|
| Radial crafting menu | `design/ui/radial_crafting.png` | M4 |
| Milestone board | `design/ui/milestone_board.png` | M5 |
| Keeper's log book | `design/ui/keepers_log.png` | M6 |
| Letter / bottle reader | `design/ui/bottle_reader.png` | M6 |
| Title & session flow | `design/ui/title_session.png` | M7 |

Rule: **before implementing any of these screens, check the file exists.** If it
is missing, do NOT invent the design and do NOT skip ahead into that screen's UI
tasks. Instead, pause that task and prompt the author with the exact
instructions in `PLAN.md` §"UI mock checkpoint" (tell them which file is
missing, where the brief is, and where to export). Non-UI tasks in the same
milestone may proceed while waiting. When the PNG exists, implement to match its
layout, hierarchy, focus behavior, and palette, adapted to 640×360 — visual
simplification is fine; structural deviation is not.

## Things you must NOT do

- Don't invent content (item names, dialogue, recipe values) beyond what
  `PLAN.md`/`DESIGN.md` specify — stub with `TODO_CONTENT` markers instead. The
  bottles and the closing beat are personal; the author writes those.
- Don't add difficulty, damage, hunger, or fail states. Cozy, not cruel.
- Don't optimize prematurely; two players and a crab do not need spatial hashing.
- Don't upgrade engine/server versions mid-milestone.
