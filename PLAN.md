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

## M8+ — Content sessions & Act 2 (post-slice)

Sessions 2–5 content pass (real sprites replacing placeholders, room dressing,
remaining bottles), then Act 2 per DESIGN §7. Not planned in detail here on
purpose — re-plan after the slice teaches us.

---

## Runbook (environment)

- `docker compose up -d` → Nakama console at `http://127.0.0.1:7351`
  (admin/password per compose), game socket `7350`.
- `cd nakama && npm i && npx tsc` → outputs `build/index.js`, mounted by compose.
- Godot: open `godot/`, install nakama-godot addon to `addons/`, run scene
  `scenes/boot.tscn` (M0 creates it). Second instance: `godot --path godot`
  again. Couch mode: launch flag `--couch` or title-screen toggle.
- Server logs: `docker compose logs -f nakama`.

## Open items intentionally deferred

Steam packaging, invite flow beyond world codes, storm cycles, boat systems,
save-slot management for multiple worlds, accessibility pass (remapping UI),
audio direction. Flag these if a task seems to need them — don't build them.
