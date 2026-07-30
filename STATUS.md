# STATUS.md — handoff, 2026-07-30

Development paused. Every number below was produced by a run on 2026-07-30, not
from recollection. Where a claim could not be re-verified, it says so.

Toolchain: Godot 4.6.3.stable.official, Nakama 3.21.1+cd82b6c5, Docker Compose.

---

## 1. Git state

- **Branch:** `main` (only branch; no remotes configured)
- **HEAD:** `c6cc19c`
- **Uncommitted changes:** none (working tree clean before this file)
- **Branches with unmerged commits:** none

**`m0-boot-backbone`:** merged, then deleted. `git merge-base --is-ancestor
4e7020b HEAD` returns true, so its tip is an ancestor of `main` — the work is on
`main`. The branch ref was deleted this session with `git branch -d` (the safe
form, which refuses unmerged branches and accepted). Same for `couch-dropin`,
which was created and fast-forwarded into `main` this session.

Last 5 commit subjects:

```
c6cc19c  M1: couch claims keeper B when a player arrives, not at boot
6f5b85c  M1: give the second keeper a keyboard, not just a second pad
3be2d2c  docs: say what the playtest rule actually is
f4f89a9  M8: make it readable — the world was being multiplied into the dark
66f684a  M8: something two people can actually play, and turn while playing
```

---

## 2. Milestone position

| Milestone | State |
|---|---|
| M0 — Boot & backbone | **DONE** — 9/9 |
| M1 — Keepers exist and move | **DONE** — 10/10 |
| M2 — The tide is real | **DONE** — 16/16 |
| M3 — Gather → shared inventory | **DONE** — 15/15 |
| M4 — Craft & cook | **DONE** — 17/17 |
| M5 — Restoration milestones (the hearth) | **DONE** — 13/13 |
| M6 — Story & the crab | **DONE** — 20/20 |
| M7 — The lamp (vertical slice complete) | **DONE** — 17/17 |
| M8 — Playtest build & feel tuning | **IN PROGRESS** — 14/16 |
| M9 — Slice debt | **NOT STARTED** (partial, unplanned — §6) |
| M10 — Sound & sight | **NOT STARTED** |
| M11 — Content Sessions 2–5 | **NOT STARTED** |

Totals re-run 2026-07-30: M0–M7 = **117 checks, 0 failures**. Plus
`verify_dropin.sh` = **13/13** (not a PLAN milestone; regression guard for the
couch session model).

### M8 acceptance criteria, re-run 2026-07-30

| AC | Result | Evidence |
|---|---|---|
| AC1 — full-content playthrough from a built binary | **PASS** (4/4) | five milestones sealed and lamp lit from the built binary |
| AC2 — four values adjustable from a pad, apply <1s, survive relaunch | **FAIL** (3/4) | turn ✅, applied in 0.299s ✅, harness ignores cfg ✅, **relaunch check failed** |
| AC3 — feel-test room has zero story content | **PASS** (2/2) | no story class/scene/id in `feel_test.tscn` |
| AC4 — moving a test prop 40px breaks no harness test | **PASS** (2/2) | gather and craft routes both re-found moved markers |
| AC5 — at least one two-human playtest logged | **FAIL** (1/2) | format present; **zero entries** |

**AC2's failure is a broken test, not broken code.** `verify_m8.sh:150` asserts
the literal string `walk speed 95`. The selftest turns each value one step right
from whatever is loaded and persists it, so the assertion only holds on the first
run after a clean `tuning.cfg`. Observed ratchet across runs: 90 → 95 → 100.
This run started at 95, produced 100, saved 100, reloaded 100 correctly — the
persistence feature works; the assertion is hard-coded and non-idempotent.
Earlier runs today reported 15/16 for exactly this reason (they started at 90).

**AC5's failure is the gate working as designed.** It blocks M9 feel work.

**Could not re-run:** nothing in M8 was skipped. AC1 is satisfied by the macOS
build; the Windows `.exe` is only checked for being a valid PE32+ binary
(`verify_m8.sh:64`) and has **never been executed** — no Windows machine
available. See §6.

---

## 3. Environment truth (verified from a stopped stack, 2026-07-30)

| Check | Result |
|---|---|
| `docker compose up -d` from stopped | postgres healthy, nakama started |
| `curl /healthcheck` | **HTTP 200** |
| `npx tsc` (in `nakama/`) | exit 0, **0 lines of output** |
| Godot headless editor compile pass | exit 0, **0 script/parse/compile errors** |

`--check-only` alone is not the right check: without `--script` it runs the
project, and with `--script FILE` it parses one file with no autoloads
registered, so anything touching EventBus/Net/WorldState reports a false
"Identifier not found". The headless editor pass is what the AC wants.

**Nakama loads its runtime JS at container start.** `npx tsc` alone does not
reload it — `docker compose restart nakama` is required after any server change.
A whole test run was lost to this: the client sent `CLAIM` and the server
silently ignored an opcode it had never heard of.

---

## 4. Playtest state

- `PLAYTESTS.md` **exists** — how-to, what-to-watch, and entry template in place.
- **Entries: 0.** The file still carries `<!-- No entries yet. -->`.
- **The M8 AC5 gate is UNMET.** M9 feel work is blocked.

Committed defaults (`godot/autoload/tuning.gd`, `DEFAULTS`) — unchanged, correctly,
since no playtest has been logged:

| Value | Default | Range | Step |
|---|---|---|---|
| `walk_speed` | 90.0 px/s | 40–200 | 5 |
| `camera_smoothing` | 6.0 | 1–20 | 0.5 |
| `tide_cycle_seconds` | 480.0 s | 60–1200 | 30 |
| `radial_deadzone` | 0.45 | 0.15–0.9 | 0.05 |

⚠️ **This machine's `user://tuning.cfg` is polluted and will change how the game
feels for a human.** It currently holds `walk_speed=100, camera_smoothing=7.0,
tide_cycle_seconds=540, radial_deadzone=0.55` — not the committed defaults, and
not anybody's considered opinion. It is harness residue (see §6). **Delete it
before the first real playtest**, or the author tunes from a corrupted baseline:

```sh
rm ~/Library/Application\ Support/Godot/app_userdata/Lighthouse\ Keepers/tuning.cfg
```

Harness runs are unaffected — `Tuning._harness_is_driving()` makes them ignore
the cfg and measure committed defaults. Only humans get the polluted values.

---

## 5. UI mock inventory

All five mocks present in `design/ui/`, in **both** `.dc.html` (preferred) and
`.png`. All five gates satisfied; none outstanding.

| Screen | Mock file | Implemented as | Milestone |
|---|---|---|---|
| Radial crafting menu | `radial_crafting.dc.html` + `.png` | `godot/ui/radial_menu.{gd,tscn}` | M4 |
| Milestone board | `milestone_board.dc.html` + `.png` | `godot/ui/milestone_board.{gd,tscn}` | M5 |
| Keeper's log book | `keepers_log.dc.html` + `.png` | `godot/ui/log_book.{gd,tscn}` | M6 |
| Letter / bottle reader | `bottle_reader.dc.html` + `.png` | `godot/ui/bottle_reader.{gd,tscn}` | M6 |
| Title & session flow | `title_session.dc.html` + `.png` | `godot/ui/title_screen.{gd,tscn}` | M7 |

---

## 6. Divergence log

### Deliberate, documented

1. **`--couch` semantics changed** (post-M8, commit `c6cc19c`). It claimed both
   slots at boot; it now claims keeper A only, and keeper B is claimed via the
   `CLAIM` command when a second player first presses something. `--couch-both`
   is new and claims both up front — the harness needs it, and all ten verifier
   launch sites use it. `PLAN.md`, `README.md`, `PLAYTESTS.md` updated.
2. **Opcode 11 = `CLAIM`** added to `command.gd` and `match_handler.ts`. Not in
   `PLAN.md`'s opcode list.
3. **Keyboard bindings for `p2_*`** (commit `6f5b85c`). CLAUDE.md's
   controller-first law calls keyboard an adaptation; the second keeper had no
   keyboard events at all, so "one on a pad, one on the keyboard" was impossible.
   Keeper B now has arrows / Enter / Shift / `.` / `/` / `,` / `;` / `'`.

### Accidental / unresolved

4. **Opcode 9 collision with Act 2.** `PLAN.md:283` reserves `ENTER_ZONE` for Act
   2's zone authority. Opcode 9 is already `CAUGHT`, 10 is `TALK`, 11 is now
   `CLAIM`. `ENTER_ZONE` needs 12 or higher. Flagged at M7, still unresolved.
5. **M8 AC1 is not literally satisfied.** The AC says "runs from a built .exe".
   The `.exe` is built (`build/windows/LighthouseKeepers.exe`, 104 MB, valid
   PE32+) but has never been run. The playthrough was verified on the macOS
   build. Needs a Windows machine to close honestly.
6. **`verify_m8.sh` pollutes `user://tuning.cfg` and then asserts on it.** The
   selftest turns every value one step right and persists, with no cleanup, and
   line 150 hard-codes `walk speed 95`. Consequences: (a) the M8 AC2 check fails
   on every run after the first, (b) a human launching the game afterwards plays
   at ratcheted values. Fix: reset the cfg before the selftest, or read the
   expected value from `Tuning.DEFAULTS` instead of hard-coding it. **Not fixed.**
7. **Interact prompt is not gated on `is_local`** (`keeper.gd:_on_target_changed`).
   Once a remote partner is visible, their prompt renders on your screen.
   Pre-existing, harmless in couch, confusing online. **Not fixed.**
8. **`ProjectSettings.save()` strips comments from `project.godot`.**
   `tools/gen_inputmap.gd` regenerating the input map silently deleted the note
   explaining `run/flush_stdout_on_print` and the `;`-not-`#` trap. Restored in
   `6f5b85c`, with the warning moved into the generator's header where a rewrite
   cannot reach. Comments in `project.godot` must start with `;` — a `#` makes
   the whole section unparse, and it fails **silently** (no main scene, no output).

### M9 work that landed early (unplanned, partial)

9. **"Keepers stay warm at HIGH tide"** (an M9 AC) is *partially* implemented.
   `keeper.gd` has `AMBIENT_RESISTANCE := 0.6` lifting sprite modulate against
   the ambient tint — added during M8's readability fix, not as M9 work. **The
   lantern halo does not exist** (no `halo`/`lantern` symbols in the codebase),
   and the M9 screenshot AC has never been run. Treat the M9 AC as UNVERIFIED,
   not done.

### TODO_CONTENT stubs — 18 occurrences, all author-owned

| Where | What is missing |
|---|---|
| `content/bottles/bottle_0{1,2,3}.tres` | the three letters |
| `content/npcs/hermit_crab.tres` | 2 stage lines + idle line |
| `content/recipes/chowder.tres` | inputs are `{TODO_CONTENT: 1}` — will not craft |
| `ui/log_book.gd:153` | log sentence templates |
| `ui/milestone_board.gd:163` | milestone descriptions |
| `ui/bottle_reader.gd:111` | letter body text |
| `ui/relight_beat.gd:56` | the closing beat |
| `match_handler.ts:149` | **where fish come from** — `lamp_oil` needs fish and neither PLAN nor DESIGN says the source. Stubbed as a tide pool so Act One completes. |
| `match_handler.ts:240,260` | chowder costs |

Open question from the M4 mock: whether the extra recipe names on
`radial_crafting.png` are real content or mock filler. Never answered.

---

## 7. Next three actions

1. **M8 AC5 — log a playtest.** Two humans, one session, write the entry into
   `PLAYTESTS.md` (date, mode, the four values, top-3 friction). *Blocked on: the
   author. Claude may not invent an entry.* **Delete the polluted `tuning.cfg`
   first** (§4) or the session starts from the wrong baseline. This is the only
   thing standing between here and M9.
2. **M9 — the arrival.** Fresh worlds initialize with scripted shore state at
   cycle 0: arrival crates, 1 pre-spawned bottle, pre-rolled nodes, applied in
   `loadWorld()`. AC: story in reach within 60s of spawn, verified by harness.
   *Not blocked* — it is content-shaped but structural, and does not touch feel
   values.
3. **M9 — keepers stay warm at HIGH tide.** Finish what partially landed (§6.9):
   add the warm lantern halo scaling with the sky ramp, then build the HIGH-tide
   screenshot harness the AC actually asks for. *Not blocked.*

Also worth doing before either M9 task, though not on the PLAN ladder: fix
`verify_m8.sh`'s tuning assertion (§6.6), because it will keep reporting a false
failure and quietly corrupting the playtest baseline the whole way through M9.
