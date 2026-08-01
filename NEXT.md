# NEXT.md — instruction queue (planning session → implementation session)

Execute top-down. Mark items [DONE], [BLOCKED: why], or [SKIPPED: why] in
place. When all items are terminal, say so in STATUS.md and await a new
NEXT.md.

Queue version: 2026-07-31.2
Author decisions carried in this queue: music = ONE dusk theme loop; keeper
sprites = agent drafts programmatic sheets now, author replaces later.

## 0. [DONE] Push
Pushed `8a02e7a..e2e00c7`; verified in sync with `git status` and confirmed with
`git ls-remote origin main`. Push-at-session-end appended to CLAUDE.md's
protocol section.

Push main to origin (the 9+ waiting commits). Verify with git status and
ls-remote. From now on, pushing at session end is part of the session
protocol — append that line to CLAUDE.md's protocol section.

## 1. [DONE] Codify the intent-reinterpretation rule
Added to CLAUDE.md's Testing law, verbatim as given. No further action taken on
`verify_m6.sh`.

Append to CLAUDE.md's Testing law: "When a deliberate design change
contradicts a test's letter, reinterpret the test toward the intent it was
defending — never delete the guard, never let a dead assertion block shipped
design. Flag the judgment in STATUS.md and keep the change revert-clean."
(This ratifies the verify_m6 rewrite; no further action on that file.)

## 2. [DONE] STATUS.md provenance format
Documented in CLAUDE.md beside the protocol; STATUS.md regenerated in it. The
auto-UNVERIFIED rule bit immediately and correctly: `verify_m4.sh` changed this
session, so M4 was re-run rather than carried. The Windows `.exe` gap is
recorded as `[CARRIED]` in STATUS §7.8.

Amend the STATUS format (document it in CLAUDE.md next to the protocol):
- Every factual claim carries [VERIFIED <date>] (re-proven that session) or
  [CARRIED] (inherited, unproven this session).
- Any AC whose measurement apparatus changed since its last pass reverts to
  UNVERIFIED automatically until re-run.
- Known [CARRIED] gap to record now: the Windows .exe has never been executed
  on Windows; PE32+ validity only.

## 3. [DONE] M10 audio track
Four buses, three beds crossfaded by phase and room, ten one-shots, one theme,
controller-navigable sliders that persist. 11 of `verify_m10.sh`'s 14 checks.
**Two departures from this item as written, both in STATUS §7:** the beds and
one-shots are synthesised rather than taken from CC0 packs, and nobody here has
heard any of it.

- Godot buses: Master / Ambience / Music / SFX, with settings sliders
  (controller-nav, persisted).
- Three ambient beds crossfaded by tide phase per PLAN M10: sea+gulls (LOW),
  wind (MID/HIGH), fire crackle (tower interior when hearth lit).
- The ten one-shots per PLAN M10 list, wired to their events.
- Music: ONE dusk theme loop (author decision). Shortlist 3 CC0 candidates
  into assets/audio/music_candidates/ with source URLs and licenses; wire the
  best fit as the default; swapping = replacing assets/audio/music/dusk_theme.ogg,
  document that path. Author may veto/swap at leisure.
- All sources CC0/CC-BY only; record every file + license + URL in CREDITS.md.
- Mix sanity: music sits under ambience; nothing startles. Cozy is the spec.
- AC per PLAN M10 (crossfades track phase flips both clients/modes; SFX fire
  on events; sliders persist).

## 4. [DONE] M10 art track — programmatic keeper sheets + the manifest
Both sheets at 8×3 frames of 16×24 — idle, four-step walk, gather crouch, three
facing rows. Silhouette overlap 0.72 against a 0.85 limit; zero off-ramp hexes.
`ASSET_MANIFEST.md` is generated from repo truth, which immediately found two
items shipped with no icon at all.

- Draft programmatic sprite sheets for both keepers: idle + walk, 4
  directions, + gather anim. Keeper A silhouette: sou'wester brim + coat
  flare (yellow ramp). Keeper B silhouette: bare head + long scarf tail (red
  accents). Palette-locked to DESIGN §6 ramps only.
- M10 AC applies: grayscale-at-50% silhouette distinguishability check +
  no-off-ramp-hex check, both scripted.
- Stable asset paths so author replacement is drop-in: fixed file locations,
  fixed frame grid, documented.
- Generate ASSET_MANIFEST.md at repo root from code/scene truth: every
  placeholder asset in the game with its canvas size, frame grid, animation
  names, palette ramps, current file path, and a replacement recommendation
  (hand-pixel / AI-gen+cleanup / pack-recolor), ordered by priority: keepers,
  tower interior tileset, beach tileset, lighthouse vista, props/resource
  nodes, crab, UI icons. This is the author's shopping list for the real art
  pass.

## 5. [DONE — observed] Feel-gate carve-out (standing constraint for this queue)
No tuning default was committed and no feel value changed. The walk cycle is
driven by distance covered rather than by a timer specifically so animation
could be added without touching `walk_speed`.

No tuning-default commits and no feel-value changes of any kind. M8 AC5
(PLAYTESTS.md entry) still gates all of that. Audio levels are exempt (they
have their own sliders); movement/timing/deadzone are not.

## 6. [DONE] Report
Regenerate STATUS.md in the new provenance format: M10 AC results, suite
totals, the music candidate shortlist (so the author can listen), divergences,
next three actions per PLAN.md. Push. Commit everything.

## Standing author reminders (not agent tasks)
- The playtest evening: still the only gate between here and finishing M10's
  feel side + starting M11. Oldest open item.
- Listen to the three music candidates when STATUS lands; veto or bless.
- Replace programmatic keeper sheets per ASSET_MANIFEST.md at leisure.
- The final-card line. No deadline. Last commit before she plays.

---

## NOTE from the implementation session (2026-08-01)

Suite: **186 checks, 1 failure** — M8 AC5, the playtest gate.

**Item 3's audio brief could not be met as written, and the difference matters.**
"Sources: CC0 packs (freesound, Sonniss GDC)" is not reachable from here:
freesound requires an authenticated API and the Sonniss packs are multi-gigabyte
archives. The MUSIC is a genuine CC0 download — three real candidates, listed in
STATUS §4 for you to listen to. The three beds and ten one-shots are synthesised
by a seeded script and are ours. CREDITS.md says so outright rather than letting
a licence table imply a provenance those files do not have.

**Nobody on this side has heard a single audio file.** Every audio AC is about
whether the right thing plays at the right moment. Which track is the default was
chosen from documented properties, and should be treated as a placeholder
decision until an ear lands on it.

**A third instance of the same bug class.** `verify_m4.sh` had the timed-sleep
race that `verify_m8.sh` had, and this milestone's own audio autoload made boot
slow enough to expose it. Worth a future queue item: no verifier should sleep a
guess before a dev RPC, and no dev RPC response should go to `/dev/null`. M4, M8
and M9 are fixed; **M2, M3, M5, M6 and M7 have not been audited** for the same
pattern.

**The first full suite run failed broadly and the failures were not real** —
machine contention; every one was clean when re-run alone. Only M4's survived
isolation. This suite is not currently safe to trust on a loaded machine, which
is itself worth fixing.

Two cheap things for M11, both found by tooling rather than by anyone looking:
`kelp_tea` and `smooth_stone` have no icons, and `PLACE` is an opcode nothing
sends.
