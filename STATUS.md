# STATUS.md — handoff, 2026-07-31

Every number below was produced by a run on 2026-07-31, not from recollection.
Where a claim could not be re-verified, it says so.

Toolchain: Godot 4.6.3.stable.official, Nakama 3.21.1+cd82b6c5, Docker Compose.

---

## 1. Git state

- **Branch:** `next-queue-2026-07-31` (branched from `main`)
- **HEAD:** `5483ceb`
- **Uncommitted changes:** none except this file
- **`main`:** at `81f9b91`, six commits ahead of `origin/main`

**There IS a remote**, contrary to what the previous STATUS said. `origin` is
`https://github.com/sniderwebdev/lighthouse-keepers.git`. Nothing has been
pushed — `main` is **6 commits ahead of `origin/main`** and this branch adds two
more. Pushing is the author's call; see §7.

Commits this session, oldest first:

```
42da5b6  M8: verifiers run the binary they just built
ddff4c7  M9: ENTER_ZONE is opcode 12, not 9
a309be9  M9: a prompt belongs to the keeper holding the pad
1404e75  M9: the arrival, the light past the shoal, and keepers who stay warm
914ad64  M6: the shore is not bare at cycle 0 any more
81f9b91  M4: cover the one recipe nobody has to be taught      <- main is here
153800c  docs: two documents, two owners, one direction of travel
5483ceb  M9: hungry story does not wait for the cycle
```

`m9-arrival-and-slice-debt` was merged into `main` fast-forward and deleted with
`git branch -d` (the safe form, which refuses unmerged branches and accepted).

---

## 2. Milestone position

| Milestone | State |
|---|---|
| M0 — Boot & backbone | **DONE** — 9/9 |
| M1 — Keepers exist and move | **DONE** — 10/10 |
| M2 — The tide is real | **DONE** — 16/16 |
| M3 — Gather → shared inventory | **DONE** — 15/15 |
| M4 — Craft & cook | **DONE** — 20/20 |
| M5 — Restoration milestones (the hearth) | **DONE** — 13/13 |
| M6 — Story & the crab | **DONE** — 24/24 |
| M7 — The lamp (vertical slice complete) | **DONE** — 18/18 |
| M8 — Playtest build & feel tuning | **15/16** — AC5 gated on the author |
| M9 — Slice debt | **DONE** — 19/19, all four ACs |
| M10 — Sound & sight | **NOT STARTED** |
| M11 — Content Sessions 2–5 | **NOT STARTED** |

Full suite re-run 2026-07-31 after the last code change: **172 checks, 1
failure.** M0–M9 = 159, plus `verify_dropin.sh` 13/13 (not a PLAN milestone; a
regression guard for the couch session model).

The single failure is M8 AC5 — zero playtest entries. That is the gate working
as designed, and it is the author's to close.

Counts moved this session: M4 17→20 (kelp_tea coverage), M6 23→24 (the arrival
changed what cycle 0 means), M9 0→19 (new).

### M9 acceptance criteria, run 2026-07-31

| AC | Result | Evidence |
|---|---|---|
| AC1 — fresh world has a readable bottle + gatherable crates; story in reach in 60s | **PASS** (6/6) | reached the letter in **6.94s** |
| AC2 — the shoal glimmer (three, a pause, three, after bottle_2, at LOW) | **PASS** (3/3) | dark before the flag; the pause is >1.5× the gaps inside each three |
| AC3 — HIGH-tide screenshot: keepers stay warm and tellable-apart | **PASS** (6/6) | warm pixels read **81.0 luminance** above the shore |
| AC4 — chapter 2 unlocked+unspawned arrives within a phase, not a cycle | **PASS** (2/2) | unlocked at cycle 1, arrived at cycle 1 |

Plus 2 standing checks (`tsc`, GDScript) = 19.

**AMBIENT_RESISTANCE is no longer UNVERIFIED.** The previous STATUS flagged it
as landed-but-unproven. It is now measured out of a running game at high water:
`lift=1.300,1.428,1.127` — every channel above 1.0, i.e. the keeper is lifted
OUT of the ambient tint rather than multiplied by it.

### M8 acceptance criteria, re-run 2026-07-31

| AC | Result | Evidence |
|---|---|---|
| AC1 — full-content playthrough from a built binary | **PASS** (4/4) | five milestones sealed and the lamp lit, from a binary unzipped this run |
| AC2 — four values adjustable from a pad, apply <1s, survive relaunch | **PASS** (4/4) | expected string derived from `Tuning.DEFAULTS`, matched exactly |
| AC3 — feel-test room has zero story content | **PASS** (2/2) | no story class/scene/id in `feel_test.tscn` |
| AC4 — moving a test prop 40px breaks no harness test | **PASS** (2/2) | both routes re-found their moved markers |
| AC5 — at least one two-human playtest logged | **FAIL** (1/2) | format present; **zero entries** |

AC2's old failure is gone and gone honestly — it no longer asserts a literal.
AC1 now passes against a binary that is actually current; see §6.1 for why that
sentence is not redundant.

---

## 3. Environment truth (verified 2026-07-31)

| Check | Result |
|---|---|
| `docker compose up -d` from a stopped daemon | postgres healthy, nakama started |
| `curl /healthcheck` | **HTTP 200** |
| `npx tsc` (in `nakama/`) | exit 0, **0 lines of output** |
| Godot headless editor compile pass | exit 0, **0 script/parse/compile errors** |
| `tools/build.sh` (both platforms) | exit 0 |

**Nakama loads its runtime JS at container start.** `npx tsc` alone does not
reload it — `docker compose restart nakama` is required after any server change.
This bit again this session in the opposite direction, usefully: M8 was run
deliberately *without* restarting, so it measured stabilization alone rather
than stabilization plus the half-finished arrival.

`--check-only` alone is still not the right check: without `--script` it runs
the project, and with `--script FILE` it parses one file with no autoloads
registered, so anything touching EventBus/Net/WorldState reports a false
"Identifier not found". The headless editor pass is what the AC wants.

---

## 4. Playtest state

- `PLAYTESTS.md` **exists** — how-to, what-to-watch, and entry template in place.
- **Entries: 0.** The file still carries `<!-- No entries yet. -->`.
- **The M8 AC5 gate is UNMET.**

Committed defaults (`godot/autoload/tuning.gd`, `DEFAULTS`) — unchanged,
correctly, since no playtest has been logged:

| Value | Default | Range | Step |
|---|---|---|---|
| `walk_speed` | 90.0 px/s | 40–200 | 5 |
| `camera_smoothing` | 6.0 | 1–20 | 0.5 |
| `tide_cycle_seconds` | 480.0 s | 60–1200 | 30 |
| `radial_deadzone` | 0.45 | 0.15–0.9 | 0.05 |

✅ **The polluted `user://tuning.cfg` the previous STATUS warned about is gone.**
`verify_m8.sh` now deletes it either side of its selftest, so harness runs no
longer leave ratcheted values behind for a human to unknowingly play at. A
playtest started today starts from the committed defaults. Verified absent after
the final suite run.

---

## 5. UI mock inventory

All five mocks present in `design/ui/`, in **both** `.dc.html` (preferred) and
`.png`. All five gates satisfied; none outstanding. Unchanged this session.

| Screen | Mock file | Implemented as | Milestone |
|---|---|---|---|
| Radial crafting menu | `radial_crafting.dc.html` + `.png` | `godot/ui/radial_menu.{gd,tscn}` | M4 |
| Milestone board | `milestone_board.dc.html` + `.png` | `godot/ui/milestone_board.{gd,tscn}` | M5 |
| Keeper's log book | `keepers_log.dc.html` + `.png` | `godot/ui/log_book.{gd,tscn}` | M6 |
| Letter / bottle reader | `bottle_reader.dc.html` + `.png` | `godot/ui/bottle_reader.{gd,tscn}` | M6 |
| Title & session flow | `title_session.dc.html` + `.png` | `godot/ui/title_screen.{gd,tscn}` | M7 |

---

## 6. Divergence log

### Resolved this session (were open in the previous STATUS)

1. **Opcode 9 collision with Act 2** — resolved. `ENTER_ZONE` is reserved at
   **12** in both `command.gd` and `match_handler.ts`, with "next free opcode is
   13" recorded in both. `PLAN.md`'s Act 2 note amended.
2. **`verify_m8.sh` polluting `user://tuning.cfg` and asserting on it** —
   resolved. Expected value derives from `Tuning.DEFAULTS`; cfg reset either
   side of the selftest.
3. **Interact prompt not gated on `is_local`** — resolved, plus `become_local`
   now re-states the prompt for the slot it just took, so a drop-in player at a
   station already in reach is not left promptless.
4. **M9 "keepers stay warm" partially landed / UNVERIFIED** — resolved. The
   halo exists (`godot/game/keeper_halo.gd`), and both halves are measured by
   `verify_m9.sh` AC3.

### Found and fixed this session (new)

5. **The verifiers were testing a stale binary.** The macOS export is a `.zip`;
   `verify_m8.sh`'s `$APP` pointed into `build/macos/app/`, a directory somebody
   had unzipped by hand. When found it held a build **two days older** than the
   code under test, so every "runs from a BUILT binary" claim — including the
   previous STATUS's AC1 **PASS** — was about a binary nobody had just built.
   Both M8 and M9 now unpack the zip per run into their evidence directory.
   **Treat the previous STATUS's M8 AC1 result as unreliable.**
6. **`verify_m8.sh` had a timed-sleep race.** `teach` fired six seconds after
   launch on the assumption the world would be live; once the binary grew it was
   not, the RPC answered "world has no live match" into `/dev/null`,
   `patch_kit` stayed locked, and AC1 failed four steps downstream reporting
   "1 of 5 tower layers changed" — true, and silent about why. Dev RPCs now
   retry until the match is live and every answer is kept in `rpc.log`.
7. **The autowalk `AIM` step raced the station.** It held interact and pushed a
   direction from the same frame; until the wheel is open the keeper is still a
   keeper, so the direction walked them out of reach before the hold completed.
   It only ever worked because every existing route wanted a slot on the side
   the station already was. `AIM` takes an optional settle time now; existing
   routes pass 0 and are unchanged.

### Deliberate, documented

8. **Cycle 0 is no longer a bare shore.** M9's arrival places `bottle_01` and
   two crates in a fresh world. `verify_m6.sh`'s AC1 opener asserted the
   opposite; it was rewritten to assert what the check was actually defending —
   that the tide is the only way story arrives — and a second check added that
   no later chapter has jumped the tide. **This is a reinterpretation of a
   previously-passing assertion and is the one judgement call worth the author's
   review**; it reverts cleanly as `914ad64`.
9. **Bottle rolls now also fire on phase boundaries**, four times as often as
   before, when a chapter is eligible but unspawned. Self-limiting: each chapter
   requires the previous one READ, so at most one unread letter can be on the
   sand. Guarded against double-rolling on a tick that turns both.

### Open / unresolved

10. **The Windows `.exe` has still never been run.** It is built
    (`build/windows/LighthouseKeepers.exe`, valid PE32+) and only checked for
    being a valid binary. No Windows machine available. M8 AC1 is satisfied on
    macOS only.
11. **Arrival crate yields (2 + 1 driftwood) and the glimmer's flash timings
    are unplaytested feel values.** Chosen so the crates leave you one driftwood
    short of `clear_hearth`'s cost of 4. Flagged in-code as the author's to
    change; nothing else depends on them.
12. **Arrival crates render as driftwood** and prompt "Gather driftwood",
    because `ResourceNode` names the item and there is no crate art.
    Programmer art; M10's problem.

### TODO_CONTENT stubs — 1 occurrence

| Where | What is missing |
|---|---|
| `ui/bottle_reader.gd:119` | a fallback branch, returns `["TODO_CONTENT"]` when a bottle has no body |

Down from 18. Every author-owned stub was filled in `8a02e7a`; this one is a
defensive default, not an author slot.

The **final card** (`[PERSONAL]`, the author's line to her) remains
**intentionally unwritten**. `verify_m7.sh` asserts nothing stands in for it.

---

## 7. Next three actions

1. **M8 AC5 — log a playtest.** Two humans, one session, an entry in
   `PLAYTESTS.md` (date, mode, the four values, top-3 friction). *Blocked on:
   the author. Claude may not invent an entry.* The baseline is clean now (§4),
   so whatever gets tuned starts from the committed defaults. This is the only
   thing standing between here and M10.
2. **Decide about the remote.** `main` is 6 commits ahead of `origin/main` and
   nothing has been pushed. *Author's call* — pushing publishes to GitHub, where
   it can be indexed regardless of later deletion.
3. **M10 — sound & sight**, whose audio track opens with a question only the
   author can answer: none / single dusk theme / theme-per-act. PLAN says prompt
   for it, don't pick. The art track (keeper sheets first, silhouette + palette
   tests) needs nobody's permission and can start immediately.

`NEXT.md` queue version 2026-07-31.1 is **fully terminal** — every item is
`[DONE]`. Awaiting a new `NEXT.md`.
