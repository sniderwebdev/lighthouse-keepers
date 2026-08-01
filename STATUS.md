# STATUS.md — handoff, 2026-08-01

Every claim below carries its provenance, per `CLAUDE.md` § "STATUS.md
provenance":

- **`[VERIFIED 2026-08-01]`** — re-proven by a run this session.
- **`[CARRIED]`** — inherited from a previous STATUS and NOT re-proven here.
  A carried claim is a lead, not a fact.

Toolchain: Godot 4.6.3.stable.official, Nakama 3.21.1+cd82b6c5, Docker Compose.
`[VERIFIED 2026-08-01]`

---

## 1. Git state `[VERIFIED 2026-08-01]`

- **Branch:** `m10-sound-and-sight` (branched from `main`)
- **HEAD:** `3c66fbb`
- **Uncommitted:** none except this file and `NEXT.md`
- **`origin/main`:** at `e2e00c7` — **pushed this session**, verified with
  `git ls-remote`. The five commits below are not yet pushed; see §7.

```
680875d  docs: provenance, and the rule that a passing test can stop being one
02b6a42  M10: the whole mixer — four buses, three beds, ten one-shots, one theme
405974d  M10: keepers who walk, and the list of what still needs drawing
e9fdc74  M10: the verifier, and both ACs ticked
3c66fbb  M4: teach the world before the route acts, not four seconds after it starts
```

---

## 2. Milestone position

Full suite re-run 2026-08-01 after the last code change: **186 checks, 1
failure.** `[VERIFIED 2026-08-01]`

| Milestone | State | Provenance |
|---|---|---|
| M0 — Boot & backbone | **DONE** — 9/9 | `[VERIFIED 2026-08-01]` |
| M1 — Keepers exist and move | **DONE** — 10/10 | `[VERIFIED 2026-08-01]` |
| M2 — The tide is real | **DONE** — 16/16 | `[VERIFIED 2026-08-01]` |
| M3 — Gather → shared inventory | **DONE** — 15/15 | `[VERIFIED 2026-08-01]` |
| M4 — Craft & cook | **DONE** — 20/20 | `[VERIFIED 2026-08-01]` |
| M5 — Restoration milestones | **DONE** — 13/13 | `[VERIFIED 2026-08-01]` |
| M6 — Story & the crab | **DONE** — 24/24 | `[VERIFIED 2026-08-01]` |
| M7 — The lamp | **DONE** — 18/18 | `[VERIFIED 2026-08-01]` |
| M8 — Playtest build & feel tuning | **15/16** — AC5 gated on the author | `[VERIFIED 2026-08-01]` |
| M9 — Slice debt | **DONE** — 19/19 | `[VERIFIED 2026-08-01]` |
| M10 — Sound & sight | **DONE** — 14/14, placeholder-complete | `[VERIFIED 2026-08-01]` |
| M11 — Content Sessions 2–5 | **NOT STARTED** | — |

Plus `verify_dropin.sh` 13/13 `[VERIFIED 2026-08-01]` (not a PLAN milestone; a
regression guard for the couch session model).

The single failure is M8 AC5 — zero playtest entries. The gate working as
designed, and the author's to close.

### M10 acceptance criteria, run 2026-08-01 `[VERIFIED 2026-08-01]`

| AC | Result | Evidence |
|---|---|---|
| AC1 — ambience crossfades track phase flips on both clients | **PASS** (3/3) | LOW opens on sea; the flip moved the bed on A *and* B; 2 bed changes across the run, not a timer's worth |
| AC2 — SFX fire on their events in both play modes | **PASS** (4/4) | gather online, craft + wheel-tick on the couch, all ten files present |
| AC3 — sliders move and persist | **PASS** (3/3) | 4 buses turned from a pad; reloaded `Master 75% · Ambience 65% · Music 45% · SFX 70%`; no mouse or drag-slider in the panel |
| AC4 — keeper sheets: silhouette + palette | **PASS** (4/4) | worst silhouette overlap **0.72** against a 0.85 limit; zero off-ramp hexes; manifest up to date |

**M10 is placeholder-complete, not art-complete.** The three beds and ten
one-shots are synthesised by `tools/gen_placeholder_audio.py`; the keeper sheets
are drawn in code. The music is a genuine CC0 download. `ASSET_MANIFEST.md` is
the replacement list and `CREDITS.md` records every source and licence.

**What the M10 ACs do NOT prove:** whether any of it sounds good. Nobody on this
side of the repo has heard a single file. See §4.

---

## 3. Environment truth `[VERIFIED 2026-08-01]`

| Check | Result |
|---|---|
| `docker compose up -d` | postgres healthy, nakama started |
| `curl /healthcheck` | **HTTP 200** |
| `npx tsc` | exit 0, **0 lines of output** |
| Godot headless editor compile pass | exit 0, **0 script/parse/compile errors** |
| `tools/build.sh` (both platforms) | exit 0 |

`[CARRIED]` Nakama loads its runtime JS at container start; `npx tsc` alone does
not reload it — `docker compose restart nakama` is required after a server
change. Not exercised this session (no server changes landed).

---

## 4. For the author — three tracks to listen to

The music decision was ONE dusk theme. Three CC0 candidates are downloaded and
sitting in `godot/assets/audio/music_candidates/`:

| File | Title / author | Why it might suit |
|---|---|---|
| `heavenly_loop.ogg` | Heavenly Loop — isaiah658 | **Currently wired as the default.** The only one whose author describes it as a *seamless* loop built to survive repetition |
| `winter_dust.ogg` | Winter Dust — hernandack | Short calm loop from a four-track pack |
| `a_brand_new_wisdom.ogg` | A Brand New Wisdom — hernandack | Short loop from the same pack |

All CC0, sources in `CREDITS.md`. **The default was chosen on documented
properties, not by listening** — that limit is stated in `CREDITS.md` too, so
nobody later mistakes it for a judgment about how it sounds.

To swap: copy the chosen file over `godot/assets/audio/music/dusk_theme.ogg`.
Nothing in the code knows anything about the track except where it lives.

---

## 5. Playtest state `[VERIFIED 2026-08-01]`

- `PLAYTESTS.md` exists — how-to, what-to-watch, entry template in place.
- **Entries: 0.** The file still carries `<!-- No entries yet. -->`.
- **The M8 AC5 gate is UNMET.**

Committed feel defaults are **unchanged this session**, correctly: `NEXT.md`
item 5 forbade feel-value commits, and nothing here touched them. Audio levels
are the exempt case and live on their own sliders.

| Value | Default | Range | Step |
|---|---|---|---|
| `walk_speed` | 90.0 px/s | 40–200 | 5 |
| `camera_smoothing` | 6.0 | 1–20 | 0.5 |
| `tide_cycle_seconds` | 480.0 s | 60–1200 | 30 |
| `radial_deadzone` | 0.45 | 0.15–0.9 | 0.05 |

`user://tuning.cfg` is absent — `verify_m8.sh` clears it either side of its
selftest, so a playtest starts from the committed defaults. `[VERIFIED
2026-08-01]`

---

## 6. UI mock inventory `[CARRIED]`

All five mocks present in `design/ui/` in both `.dc.html` and `.png`; all five
gates satisfied. Not re-checked this session — no UI-mock-gated screen was
touched. The new volume panel is not one of the five gated screens.

---

## 7. Divergence log

### Deliberate, documented (new this session)

1. **Beds and one-shots are synthesised, not sourced from CC0 packs.** PLAN M10
   says freesound / Sonniss GDC. Freesound needs an authenticated API and the
   Sonniss packs are multi-gigabyte archives; neither is reachable from here.
   Thirteen slots filled the way the sprites and icons already are —
   programmatically, with stable paths. `CREDITS.md` says so plainly rather than
   letting a licence table imply a provenance these files do not have.
2. **A fourth bus.** PLAN says Master/Ambience/SFX; the queue added Music once
   the author chose a theme. Followed the queue.
3. **Keeper sheets moved** from `godot/art/placeholder/` to
   `godot/assets/art/keepers/` and grew from a 3-frame strip to an 8×3 grid.
   `keeper.gd` reads `row * 8 + column`; the grid is documented in
   `ASSET_MANIFEST.md` and is the contract a replacement must match.

### Found this session

4. **`verify_m4.sh` had the M8 timed-sleep race** — `sleep 4; teach` against an
   autowalk route that reached the bench in ~3.6s. It held until this
   milestone's audio autoload made boot slower, then AC1 started failing with
   "released on a locked recipe". Fixed by ordering: a routeless client brings
   the world live, teach retries until the server answers `ok`, and only then
   does the acting client start. **Third instance of this class.** Every dev-RPC
   response in M4, M8 and M9 is now kept in `rpc.log`.
5. **Two content items have no icon.** `kelp_tea` and `smooth_stone` were added
   to the content tables in `8a02e7a` without art. `ItemRegistry.icon()` falls
   back so nothing crashes — they simply show as nothing in the basket and on
   the wheel. Found by the manifest generator, not by a human. Cheapest fix in
   `ASSET_MANIFEST.md`.
6. **`place.wav` has no trigger.** The `PLACE` opcode is defined in both
   `command.gd` and `match_handler.ts` and is **never sent by any client code**.
   Either the verb is unimplemented or the opcode is vestigial — worth a decision
   before M11.
7. **The first full suite run of this session failed broadly** (M2, M3, M5, M6,
   M7) with empty evidence strings. Re-running each alone passed — machine
   contention, not regression. Only M4's failure survived isolation.

   **Audited and fixed 2026-08-01.** All five carried the same class of defect:

   - `verify_m7.sh` — `sleep 6; teach`, response to `/dev/null`. Structurally
     identical to the M8 bug. If it lost, `patch_kit` stayed locked and the Act
     One playthrough failed several steps downstream.
   - `verify_m2.sh` — **a timed movement leg**, `sleep 12 # let A finish walking
     out there`, which the Testing law forbids by name. When boot slowed, the
     tide flipped before A stood on the sandbar and the catch never happened.
     Now waits for the route to report arrival.
   - `verify_m5.sh` — `sleep 14` for a whole Nakama restart. Now polls
     `/healthcheck`. This is why AC1 read "on rejoin the tower drew: nothing":
     true, and silent about persistence, the thing under test.
   - `verify_m3.sh` — `sleep 3` before `set_tide`, the tightest liveness margin
     in the suite against a ~2s join.
   - `verify_m6.sh` — correct ordering already, but silent responses.

   Every dev RPC in the suite now retries until the world answers and logs every
   response to `rpc.log`. Re-run after the fix: M2 16/16, M3 15/15, M5 13/13,
   M6 24/24, M7 18/18 `[VERIFIED 2026-08-01]`. M2's retry fired twice on that
   run, so the race was live there and not hypothetical.

### Open / unresolved

8. `[CARRIED]` **The Windows `.exe` has never been executed on Windows.** Built
   and checked for PE32+ validity only. No Windows machine available. This is
   the standing carried gap `NEXT.md` item 2 asked to record.
9. `[CARRIED]` Arrival crate yields and the glimmer's flash timings are
   unplaytested feel values.
10. **Nobody has heard the audio.** Every audio AC is about wiring.

### TODO_CONTENT stubs — 1 `[VERIFIED 2026-08-01]`

`ui/bottle_reader.gd:119` — a defensive fallback, not an author slot. The
**final card** (`[PERSONAL]`) remains intentionally unwritten; `verify_m7.sh`
asserts nothing stands in for it.

---

## 8. Next three actions

1. **M8 AC5 — log a playtest.** Two humans, one session, an entry in
   `PLAYTESTS.md`. *Blocked on: the author.* Oldest open item in the project and
   still the only gate between here and M10's feel side and M11.
2. **Push this branch and merge it.** Five commits sit local; `main` itself is
   pushed and current at `e2e00c7`.
3. **M11 — Content Sessions 2–5.** Nothing blocks it. The cheapest openers are
   the two missing item icons (§7.5) and a decision about `PLACE` (§7.6). Per
   PLAN, M11's exit criterion is a stranger-couple playing Act 1 start to finish
   without the editor.

`NEXT.md` queue version 2026-07-31.2 is **fully terminal** — every item
`[DONE]`. Awaiting a new `NEXT.md`.
