# PLAN.md — implementation ladder

Work top to bottom. Each milestone is shippable and verified by its acceptance
criteria (AC) before moving on. `CLAUDE.md` rules apply to every task. Content
values marked here are canonical for the MVP; anything not specified gets a
`TODO_CONTENT` stub, not an invention.

Locked decisions: top-down 3/4 perspective · couch AND online co-op from day one
(keeper-slot model) · PC now, console-ready posture · controller-first ·
640×360 integer-scaled pixel art · palette per DESIGN.md §6.

---

## M0 — Boot & backbone

Stand up the whole pipe end to end with debug visuals only.

Tasks:
- Repo hygiene: Godot 4.3 project boots at 640×360 integer scale; input map
  defines `move_left/right/up/down`, `interact`, `cancel`, `use_tool`,
  `menu_radial`, `menu_pause` + `p2_*` mirrors (pad device 0 and 1).
- `docker compose up` starts Nakama + Postgres; `nakama/` TS builds with `tsc`
  and the `lighthouse` match registers (see `nakama/main.ts`).
- Install nakama-godot addon; implement the TODOs in `godot/autoload/net.gd`:
  device auth, socket, join-or-create world match via RPC `join_world(world_code)`.
- Keeper slots: joining client claims `keeper_a` or `keeper_b` (or BOTH for couch
  mode) via join metadata; match tracks slot→connection mapping.
- Debug scene: labels showing connection status, claimed slot(s), tide phase.

AC:
- [ ] Two Godot instances on one PC both join world code `TEST01`; each claims a
      different slot; both debug labels show the same tide phase value.
- [ ] Killing one instance and rejoining restores its slot within 5s.
- [ ] One instance started in couch mode claims both slots successfully.
- [ ] `tsc` clean; `godot --headless --check-only` clean.

## M1 — Keepers exist and move

- Player controller: 8-dir top-down movement, stick + d-pad, accel/decel tuned
  cozy (max ~90 px/s), pixel-snapped camera following the local keeper.
- Couch mode: both keepers in one instance, pad 0 and pad 1; shared camera frames
  both (midpoint + zoom-to-fit between 1.0x and 1.5x, clamped to room bounds).
- Position sync: local keeper sends position at 10Hz (unreliable channel is fine);
  remote keeper interpolates. Positions are presentation, not command-validated.
- Placeholder keeper sprites: two silhouette-distinct 16×24 stand-ins using
  palette ramps (yellow coat A, red-scarf-forward B). Y-sort enabled.

AC:
- [ ] Online: each instance moves its own keeper; the other's mirror moves
      smoothly (no teleporting at 10Hz).
- [ ] Couch: both pads move their own keeper simultaneously; camera keeps both
      on screen across the test room.
- [ ] Gamepad-only playable; no mouse handler exists in the player path.

## M2 — The tide is real

- Server: tide loop per `match_handler.ts` (8-min cycle) broadcasting phase +
  normalized t; pause when zero keepers present.
- Client: `TideClock` interpolation; **sky/ambient tint driven by the DESIGN §6
  dusk ramp indexed by tide t** (this IS the tide UI); a CanvasModulate or
  equivalent applies it.
- Beach test scene: three shore zones (sandbar/mid-beach/yard) whose access
  colliders enable/disable by phase per DESIGN §2 table; "caught by water" =
  fade + teleport to yard + 20s slow-walk, keep inventory.

AC:
- [ ] Phase flips appear on both clients within 500ms of each other.
- [ ] Sky tint visibly progresses LOW→HIGH and reads as time passing.
- [ ] Standing on the sandbar at the MID flip triggers the gentle catch; nothing
      is lost; both clients see the caught keeper reappear at the yard.
- [ ] With no keepers connected, server tide t does not advance.

## M3 — Gather → shared inventory

- `GATHER` command end-to-end: interactable resource nodes (driftwood, kelp,
  brass_scrap, glass_shard) with per-node yields defined server-side; node
  depletion + respawn rolls on tide-cycle boundaries (spawn tables).
- Context-sensitive interact prompt (world-space, shows action + button glyph).
- Shared inventory UI: controller-grid, opens with `menu_radial` hold or
  `menu_pause`→Inventory; both keepers see the same counts live.
- Content files: `godot/content/items/*.tres` for the four items above (+ icons
  as palette-correct 12×12 placeholders).

AC:
- [ ] Keeper A gathers 3 driftwood; keeper B's inventory shows +3 within 500ms,
      both modes.
- [ ] A depleted node visibly empties on both clients and respawns after the
      configured number of cycles.
- [ ] Spamming interact during flight of a prior command does not double-grant
      (server-side idempotency per node per roll).
- [ ] Inventory fully navigable by d-pad; focus visible; cancel closes.

## UI mock checkpoint (read at M4, M5, M6, M7)

The five UI screens are implemented from author-made mocks (see CLAUDE.md
"UI mock gate" for the file table). When a required PNG is missing, pause the
UI task and print this prompt to the author, filling in the blanks:

> **Mock needed before I build the {screen name}.**
> 1. Open Claude Design and start (or continue) the Lighthouse Keepers UI project.
> 2. Paste `design/UI_BRIEF.md` if you haven't already, then say:
>    "Design screen {N} ({screen name}) as a 1280×720 artboard per the brief."
> 3. Iterate until you're happy (watch for the two failure modes the brief
>    names: web-app polish and off-palette colors).
> 4. Export the artboard as PNG to `design/ui/{expected_filename}` in this repo.
> 5. Tell me "mock ready" and I'll implement it adapted to 640×360.
> Meanwhile I'll continue with: {list the non-UI tasks you can proceed with}.

Never invent these five screens without their mock. All other UI (debug labels,
placeholder HUD, prompts) does not need mocks — build it directly per the
controller-first law.

## M4 — Craft & cook

- `CRAFT` command with stations: workbench (craft) and stove (cook). Recipes:
  `patch_kit` (3 driftwood + 1 kelp), `lamp_oil` (2 kelp + 1 fish_stub),
  `chowder` (TODO_CONTENT values) — server-authoritative tables mirror `.tres`.
- Radial crafting menu at station: hold `interact` at station opens radial;
  stick selects, release confirms; shows affordability from `WorldState`.
  **GATE: requires `design/ui/radial_crafting.png` — see UI mock checkpoint.**
- Recipe unlock via flags (`unlock_flag` on RecipeDef) — locked recipes render
  as "???" silhouettes.

AC:
- [ ] Craft succeeds only when affordable; inputs decrement + output increments
      on both clients atomically (never a frame with both states wrong).
- [ ] Unaffordable recipe visibly disabled; selecting it does nothing server-side.
- [ ] Radial is stick-only operable; also d-pad operable.

## M5 — Restoration milestones (the hearth)

- `ADVANCE_STEP` end-to-end with `MilestoneDef`: MVP chain `clear_hearth` →
  `fix_stairs` → `repair_glass` → `restore_lens` → `relight_lamp` (costs in
  DESIGN §7; exact numbers: clear_hearth 4 driftwood; fix_stairs 6 driftwood +
  1 patch_kit; repair_glass 3 glass_shard + 1 patch_kit; restore_lens 3
  brass_scrap + 2 glass_shard; relight_lamp 2 lamp_oil).
- Visual state machine on the tower scene: each completed milestone swaps/enables
  its layer (cold hearth → lit fire glow, broken → fixed stairs, etc.), driven by
  flags, warm-palette only for the lit states.
- Milestone board UI in the tower: shows chain, next step, costs, controller-nav.
  **GATE: requires `design/ui/milestone_board.png` — see UI mock checkpoint.**

AC:
- [ ] Completing `clear_hearth` lights the fire on BOTH clients within 500ms and
      persists across full server restart (Nakama storage).
- [ ] Steps enforce order server-side (cannot fund `repair_glass` before
      `fix_stairs` even with resources).
- [ ] Each visual state uses warm ramp only where DESIGN's warm/cool law allows.

## M6 — Story & the crab

- `READ_BOTTLE` end-to-end with `BottleDef` spawn rows: bottles wash in on cycle
  boundaries respecting `min_tide_cycle` + `requires_flag`; reading opens a
  controller-paged letter UI and sets flags. Ship 3 bottle stubs with
  `TODO_CONTENT` text markers (the author writes the real letters).
- NPC framework + Hermit Crab stage 1–2: proximity talk (`interact`), stage
  advances on flag conditions, hands out `unlock_flag` recipes. Dialogue box:
  button-advanced, portrait slot, no timers.
- Keeper's log v1 (`LOG_SESSION`): on session end (both keepers gone 60s or
  explicit "turn in" at the bed), server assembles an entry from that session's
  completed flags/milestones using template strings; log book UI lists entries.

AC:
- [ ] A bottle spawns only when its cycle+flag conditions hold; reading it on one
      client marks it read for the world (no double-reads).
- [ ] Crab stage 2 recipe appears in the radial only after its flag sets.
- [ ] Ending a session writes exactly one log entry; reconnecting shows it in
      the book on both clients.
- [ ] All three UIs (letter, dialogue, log) pass the unplugged-mouse test.

## M7 — The lamp (vertical slice complete)

- Generalize the gate: `TANDEM(gate_id)` opcode replacing LIGHT_LAMP; gate fires
  when both slots submit within a 10s window; partial submission shows "waiting
  for your keeper" shimmer on the other client (and on the other half of the
  couch screen).
- The relight sequence: both keepers at the crank → tandem gate → scripted beat:
  lamp room floods warm, beam sweeps the water (shader or animated sprite),
  `lamp_lit` flag, log entry, closing text stub (`TODO_CONTENT` — the author
  writes this one to her).
- Title/session flow polish: world code entry, slot pick, couch/online toggle —
  all controller-first.
  **GATE: requires `design/ui/title_session.png` — see UI mock checkpoint.**

AC:
- [ ] Gate does NOT fire with one keeper, in either mode; fires within 500ms of
      the second submission.
- [ ] Full Session-1-through-5 playthrough possible: boot → join → gather →
      craft → all five milestones → tandem relight → log shows the story, using
      only gamepads, in both play modes.
- [ ] Fresh checkout + `docker compose up` + documented steps reproduces all of
      the above (see Runbook).

## POST-SLICE LADDER (re-planned after the M0–M7 report)

Slice findings drive M8–M11. Standing order: merge `m0-boot-backbone` to main
first (re-run the M7 AC checklist on the merge result before anything else).

## M8 — Playtest build & feel tuning

Nothing new; make the slice *playable and tunable by humans*.

- Tuning overlay (debug menu, controller-nav like everything else): live-adjust
  walk speed, camera smoothing, tide cycle length, radial deadzone. Values
  persist to a local `tuning.cfg`; final numbers get committed as the new
  defaults after playtests.
- **Feel-test room**: a story-free scene (no bottles, no milestones, no crab)
  with movement space, tide-gated zones, a test crank for tandem timing, and
  props to weave around. This is the AUTHOR-AND-SPOUSE playtest space — it
  exists so feel can be tuned together without spoiling Session 1–5 content.
- Windows export preset + one-command build so playtests don't need the editor.
- Test harness refactor (slice finding): autowalk routes target named
  `TestMarker` nodes, never timed legs. Re-point existing routes.

AC:
- [ ] Full-content playthrough runs from a built .exe, not just the editor.
- [ ] All four tuning values adjustable mid-session from a pad; a changed value
      visibly applies within 1s; values survive relaunch.
- [ ] Feel-test room contains zero story content (grep: no BottleDef,
      MilestoneDef, or NPC references in its scene).
- [ ] Moving any test-room prop 40px breaks no harness test.
- [ ] At least one two-human playtest logged in `PLAYTESTS.md` (date, mode,
      tuned values, top 3 friction notes). The author runs this; Claude prompts
      for it and blocks M9 content-tuning tasks until the file has an entry.

## Pre-M11 parked work

- **Log event tape** — the keeper's log has authored FLAVOR lines for gathering,
  crafting and being caught, plus SOLO variants, but none can fire: the match
  records only `milestone:`, `bottle:`, `npc:` and `gate:` events, and a log
  entry carries no count of how many keeper slots were active. Needs
  `gather:` / `craft:` / `caught:` events plus an active-slot count on the
  entry. Authored content is already in `content/log/entries.tres` waiting for
  it. NOT scheduled — do not build it as part of M9 or M10.

## M9 — Slice debt (the three real findings)

- **The arrival** (fixes the empty first session): new worlds initialize with
  scripted shore state at cycle 0 — wrecked crates of your own belongings on
  the beach (narratively: what's left of the city life washing in), 1 bottle
  pre-spawned, resource nodes pre-rolled. Implemented as an `arrival` spawn
  table applied in `loadWorld()` when creating a fresh world. Session 1 must
  have story in reach within 60 seconds of spawn.
- **Keepers stay warm at HIGH tide** (DESIGN §6 law): keeper sprites exempted
  from full ambient modulation + a small warm lantern halo that scales up as
  the sky ramp darkens. The find-the-human-by-warmth law must hold in the
  darkest phase.
- **Bottle pacing**: bottles may also roll on phase boundaries (not just full
  cycles) when a story flag is "hungry" (next chapter unlocked but unspawned),
  so story never starves behind the tide clock.

AC:
- [ ] Fresh world: a readable bottle and gatherable arrival crates exist at
      spawn; the "reach the story in 60s" walk is verified by harness.
- [ ] Screenshot harness at HIGH tide: keeper sprite luminance stays within
      warm-ramp range while environment drops; both keepers distinguishable.
- [ ] With chapter 2 unlocked and unspawned, a bottle arrives within one phase,
      not one cycle.

## M10 — Sound & sight (parallel tracks)

Audio track (direction now exists — keep it small):
- Three ambient beds crossfaded by tide phase: sea+gulls (LOW), wind (MID/HIGH),
  fire crackle inside the tower. ~10 one-shot SFX: gather, craft, place,
  milestone-complete, bottle-open, page-turn, radial tick, tandem-ready, beam
  ignition, caught-by-tide. One music decision deferred to the author:
  none / single dusk theme / theme-per-act (prompt for it, don't pick).
- Sources: CC0 packs (freesound, Sonniss GDC) quantity-limited to the list
  above. No audio middleware; Godot buses (Master/Ambience/SFX) + settings
  sliders.

Art track (see ASSET_MANIFEST.md when added; keepers first):
- Replace the two keeper stand-ins with real sprite sheets (idle/walk 4-dir +
  gather), palette-locked, silhouette-distinct. Then tower interior tileset.
  Everything else stays programmer art until M11.

AC:
- [ ] Ambience crossfades track phase flips on both clients; SFX fire on their
      events in both play modes; sliders persist.
- [ ] Keeper sheets pass the silhouette test (grayscale thumbnails at 50%
      scale are still tellable-apart) and the palette check (no off-ramp hexes).

## M11 — Content Sessions 2–5 (the real game)

The Session 2–5 beats per DESIGN §7 in full: remaining milestones' visual
states, crab stages, bottle chain (author writes final letters — TODO_CONTENT
gates remain), beach dressing, room dressing, remaining icons. Exit criteria:
a stranger-couple could play Act 1 start to finish without the editor, and the
author has run the full five-session arc in couch mode.

## Act 2 pre-decisions (locked now, implemented later)

- **Zone authority**: Act 2 introduces coarse position truth — an `ENTER_ZONE`
  command (opcode 9) marking which named zone each SLOT occupies. Enough to
  validate "who is rowing" and boat tandem gates; full position authority stays
  out. Do not implement before the boat exists.
- Audio direction above is Act-1-scoped; boat/storm audio re-planned with Act 2.

---

## Runbook (environment)

- `cd nakama && npm i && npx tsc` → outputs `build/index.js`. Do this FIRST:
  compose mounts `nakama/build/` at `<data>/modules`, and Nakama refuses to
  start if the entrypoint is missing.
- `docker compose up -d` → Nakama console at `http://127.0.0.1:7351`
  (admin/password per compose), game socket `7350`.
- Godot: open `godot/`, run scene `scenes/boot.tscn` (the nakama-godot addon is
  vendored under `godot/addons/`). Running with no flags gets the title screen;
  `godot --path godot -- --slot=keeper_b --world=HARBO` skips it. Couch mode:
  `--couch`, or the title-screen toggle — either way the session starts with ONE
  keeper and the second joins when a second player first presses something
  (`--couch-both` claims both up front; that is the harness path, not a human one).
- Server logs: `docker compose logs -f nakama`.
- `tools/verify_m0.sh` … `verify_m7.sh` run each milestone's acceptance criteria
  and write evidence to `.m0-evidence/` … `.m7-evidence/`. Each run uses a fresh
  world code, so they are safe to re-run.

## Open items intentionally deferred

Steam packaging, invite flow beyond world codes, storm cycles, boat systems,
save-slot management for multiple worlds, accessibility pass (remapping UI),
audio direction. Flag these if a task seems to need them — don't build them.
