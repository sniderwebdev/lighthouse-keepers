# NEXT.md — instruction queue (planning session → implementation session)

Execute top-down. Mark items terminal in place. This is a deliberately small
queue: development is gated on the author's playtest; do not manufacture work.

Queue version: 2026-07-31.3

## 0. [DONE] Retry-helper audit (the 17 silent firings)
All 16 re-measured firings classified **(a)** — legitimate async waits expressed
as blind retries. **None was (b).** Every one was a dev RPC issued before the
world's match existed. Converted to named awaited conditions
(`await_world_live`, `await_phase`) with `WORLD_LIVE_TIMEOUT` / `PHASE_TIMEOUT`.
**Zero firings across the whole suite afterwards**, backstop retained, no
assertion weakened — M2 16/16, M4 20/20, M9 19/19, same counts as before.
Classification table in STATUS.md §9.
For each retried check in the last clean run (9×M4, 6×M9, 2×M2): classify as
(a) legitimate async wait — the retry is correct, convert it to an explicit
awaited condition with a named timeout, or (b) race-prone assertion — fix the
underlying ordering so the retry becomes unnecessary. Goal: a clean run where
retry helpers fire ZERO times, or every remaining retry is a documented, named
wait. Report the classification table in STATUS.md. Do not weaken any assertion
to achieve zero.

## 1. [DONE] Then stop
STATUS.md regenerated, pushed. No M11 work, nothing feel-adjacent touched.
Regenerate STATUS.md, push, and report. Do not begin M11 or touch anything
feel-adjacent. The next queue arrives after PLAYTESTS.md has its first entry.

## Standing author items (the actual critical path)
- The playtest evening — the only gate left in the project.
- Bless or veto the dusk-theme candidate while you're at it.
- Sprites per ASSET_MANIFEST.md, final-card line: at leisure.
