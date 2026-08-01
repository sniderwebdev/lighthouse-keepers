# NEXT.md — instruction queue (planning session → implementation session)

Owned by the planning session (Claude chat, via the author). Execute top-down.
Mark each item [DONE], [BLOCKED: why], or [SKIPPED: why] in place — do not
delete items. When all items are terminal, say so in STATUS.md and await a new
NEXT.md. If an item conflicts with CLAUDE.md or reality, mark [BLOCKED] with
one sentence and continue; do not improvise around it.

Queue version: 2026-07-31.1

## 0. [DONE] Install the session protocol
Append to CLAUDE.md under a "## Session protocol" heading:
- On session start: read NEXT.md and STATUS.md before touching code. Execute
  NEXT.md top-down.
- On session end (or pause request): regenerate STATUS.md from evidence (the
  established format), update NEXT.md item states, commit both.
- STATUS.md is written by the implementation session only; NEXT.md is written
  by the planning session only (item STATE markers excepted).
Then commit NEXT.md (this file) and the CLAUDE.md change.

## 1. [ ] Author default fills (verbatim)
- bottle_2 [SWAP] sentence → "Nine seconds. Close enough to row to. Far
  enough to doubt."
- log kelp_tea template → "Two cups of kelp tea before the tide turned. Elio
  was right about the second cup."
- Update CONTENT.md's author checklist to reality: slots 1–4 filled, slot 5
  intentionally omitted.

## 2. [ ] Stabilization (skip any already done; say which)
- verify_m8.sh tuning assertion reads Tuning.DEFAULTS; cfg reset around
  selftest.
- Interact prompt gated on is_local.
- Opcode collision: reserve ENTER_ZONE = 12; comment 9–11 as
  CAUGHT/TALK/CLAIM in both command.gd and match_handler.ts; amend PLAN.md's
  Act 2 note.
- Re-run M8 AC list; AC2 should pass legitimately. AC5 remains gated on the
  author's playtest — leave it failing.

## 3. [ ] Crab stage machine — four beats (scoped gameplay change)
- Grow server + NpcDef machine to: stage_1_ask/delivery (stone; grants
  patch_kit) and stage_2_ask/delivery (fish; grants chowder), using the
  authored beats already stored in hermit_crab.tres.
- Re-gate patch_kit from start-unlocked to crab-granted (client + server
  tables).
- Update M6 stage assertions and the M5 ordering AC to:
  clear_hearth → crab stage 1 → patch_kit learned → fix_stairs.
- Verify kelp_tea: craftable from a fresh world, shows available (not locked)
  in the radial — first no-unlock-flag recipe, watch table assumptions.

## 4. [ ] Queue, do not build
Add to the pre-M11 task list: "log event tape — emit gather:/craft:/caught:
events + active-slot count per session so flavor and SOLO log templates can
fire."

## 5. [ ] M9 — Slice debt (per PLAN.md)
- The arrival: fresh worlds get scripted shore state at cycle 0 in
  loadWorld(); story reachable within 60s of spawn, harness-verified.
- The shoal glimmer (CONTENT.md implementation note): after bottle_2 is read,
  LOW tide shows three slow pulses, pause, three, past the shoal.
- Keeper warmth at HIGH tide: lantern halo scaling with sky darkness +
  screenshot harness. AMBIENT_RESISTANCE half is UNVERIFIED — verify, don't
  trust.
- Bottle pacing: story-hungry flags roll on phase boundaries per PLAN.md M9.

## 6. [ ] Report
Regenerate STATUS.md (full M9 AC results, suite totals, divergences, next
three actions per PLAN.md). Commit everything.

## Standing author reminders (not agent tasks)
- Remote push if not done. PLAYTESTS.md entry (M8 AC5) still gates feel work.
- Final-card line: authored by hand, someday, last.
