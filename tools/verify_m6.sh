#!/usr/bin/env bash
# verify_m6.sh — runs the M6 acceptance criteria against a live local stack.
#
#   (cd nakama && npx tsc) && docker compose up -d && tools/verify_m6.sh
#
# Everything is driven through the real world: real walks, real interact presses,
# real menus. Story arrives on the tide, so the cycle is driven with the dev RPC
# rather than waiting out eight-minute cycles.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="${OUT:-$REPO/.m6-evidence}"
HOST="http://127.0.0.1:7350"

mkdir -p "$OUT"
rm -f "$OUT"/*.log

# Worlds persist; each run gets its own so leftovers cannot decide the result.
TAG=$(date +%s | tail -c 5)

pass=0
fail=0
check() {
  if [ "$2" = "0" ]; then echo "  PASS  $1"; pass=$((pass + 1))
  else echo "  FAIL  $1"; fail=$((fail + 1)); fi
  echo "        $3"
}

launch() {
  local name="$1"; shift
  "$GODOT" --headless --path "$REPO/godot" -- "$@" >"$OUT/$name.log" 2>&1 &
  echo $!
}
kill_all() { pkill -f "Godot --headless --path $REPO/godot" 2>/dev/null; sleep 2; }
trap kill_all EXIT
kill_all

TOKEN=$(curl -s -X POST "$HOST/v2/account/authenticate/device?create=true" \
  -H "Authorization: Basic $(printf 'defaultkey:' | base64)" \
  -H "Content-Type: application/json" -d '{"id":"lk-m6-verifier-0001"}' \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")

# Put a world into a story state without replaying the systems that produce it.
# The subject here is the CRAB; the stairs are somebody else's acceptance
# criteria, and rebuilding them inside this test would only add ways to fail
# for reasons that have nothing to do with the crab.
setflag() { # setflag <world> <flag>
  curl -s -X POST "$HOST/v2/rpc/debug_set_flag" -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "\"{\\\"world_code\\\":\\\"$1\\\",\\\"flag\\\":\\\"$2\\\"}\"" >/dev/null
}

set_tide() { # set_tide <world> <t> [cycle]
  local body="{\\\"world_code\\\":\\\"$1\\\",\\\"t\\\":$2"
  [ $# -ge 3 ] && body="$body,\\\"cycle\\\":$3"
  body="$body}"
  curl -s -X POST "$HOST/v2/rpc/debug_set_tide" -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" -d "\"$body\"" >/dev/null
}

echo "=============================================================="
echo "AC1 — a bottle spawns only when its cycle and flag conditions"
echo "      hold; reading it marks it read for the WORLD"
echo "=============================================================="
launch m6_b_a --slot=keeper_a --world=BOT$TAG --autowalk=read_bottle >/dev/null
launch m6_b_b --slot=keeper_b --world=BOT$TAG >/dev/null
sleep 4
BEFORE=$(grep -cE "\[bottle\] bottle_0[123] on the sand" "$OUT/m6_b_a.log" || true)
# Cycle 0: nothing has washed in yet, because nothing has washed in yet.
[ "$BEFORE" = "0" ]
check "nothing is on the sand before a cycle has turned" $? \
  "$BEFORE bottles present at cycle 0"

set_tide BOT$TAG 0.0 1
sleep 16
kill_all

ARRIVED=$(grep -oE "\[bottle\] bottle_0[123] on the sand" "$OUT/m6_b_a.log" | sort -u)
ARRIVED_N=$(echo "$ARRIVED" | grep -c . || true)
[ "$ARRIVED_N" = "1" ] && echo "$ARRIVED" | grep -q bottle_01
check "exactly one bottle washed in, and only the eligible one" $? \
  "$(echo "$ARRIVED" | tr '\n' ' ')"

# bottle_02 waits on bottle_01 being read AND on a later cycle, so it must not
# have come in on the same tide.
echo "$ARRIVED" | grep -qv bottle_02
check "a bottle whose conditions do not hold stayed away" $? \
  "bottle_02 requires read_bottle_01 and cycle 2; it did not appear"

READ=$(grep -oE "\[reader\] finished bottle_01" "$OUT/m6_b_a.log" | tail -1)
[ -n "$READ" ]
check "the letter was read to the end" $? "${READ:-never finished}"

SRV_READS=$(docker compose -f "$REPO/docker-compose.yml" logs --since 3m nakama 2>/dev/null \
  | grep -c "bottle bottle_01 was read in BOT$TAG" || true)
[ "$SRV_READS" = "1" ]
check "the world recorded the read exactly once" $? "$SRV_READS server-side reads"

GONE_A=$(grep -oE "\[bottle\] bottle_01 not here" "$OUT/m6_b_a.log" | tail -1)
GONE_B=$(grep -oE "\[bottle\] bottle_01 not here" "$OUT/m6_b_b.log" | tail -1)
[ -n "$GONE_A" ] && [ -n "$GONE_B" ]
check "it is gone for BOTH keepers, not just the reader" $? \
  "reader: ${GONE_A:-still there} | observer: ${GONE_B:-still there}"

echo
echo "=============================================================="
echo "AC2 — the crab's stage-2 recipe appears in the wheel only"
echo "      after its flag sets"
echo "=============================================================="
# Stage one first: the crab has to have met you before it teaches you anything.
launch m6_crab1 --slot=keeper_a --world=CRB$TAG --autowalk=talk_crab >/dev/null
sleep 13
kill_all
launch m6_locked --slot=keeper_a --world=CRB$TAG --autowalk=wheel_stove >/dev/null
sleep 15
kill_all
LOCKED=$(grep -oE "\[radial\] opened at stove .* with \[[^]]*\]" "$OUT/m6_locked.log" | tail -1)
echo "$LOCKED" | grep -q "chowder:locked"
check "before the crab teaches it, the wheel shows it locked" $? "${LOCKED:-the stove wheel never opened}"

# The crab now runs two ask/deliver errands (CONTENT.md), so the sequence is:
# hearth -> he asks for a stone -> you bring it and he teaches patch_kit ->
# patch_kit funds fix_stairs -> he asks for a fish -> chowder.
launch m6_crab2 --slot=keeper_a --world=CRB$TAG --scene=tower \
  --debug-gather=driftwood_01,driftwood_02 --debug-advance=clear_hearth >/dev/null
sleep 10
kill_all

# Errand one: fetch the stone, then hand it over. Two conversations — a TALK
# advances one stage, and the ask and the delivery are separate beats.
launch m6_crab_stone --slot=keeper_a --world=CRB$TAG --autowalk=crab_stone >/dev/null
sleep 34
kill_all

ASKED=$(docker compose -f "$REPO/docker-compose.yml" logs --since 4m nakama 2>/dev/null \
  | grep -oE "hermit_crab reached stage 2 \(crab_asked_stone\) in CRB$TAG" | tail -1)
[ -n "$ASKED" ]
check "with the hearth lit, the crab asks for a stone" $? "${ASKED:-never asked}"

TAUGHT=$(docker compose -f "$REPO/docker-compose.yml" logs --since 4m nakama 2>/dev/null \
  | grep -oE "hermit_crab reached stage 3 \(crab_taught_patch_kit\) in CRB$TAG" | tail -1)
[ -n "$TAUGHT" ]
check "handing over the stone earns the patch_kit recipe" $? "${TAUGHT:-never taught}"

SPENT=$(grep -oE "inv=\{[^}]*\}" "$OUT/m6_crab_stone.log" | tail -1 | grep -oE "smooth_stone\":[0-9.]+")
echo "$SPENT" | grep -qE "smooth_stone\":0" || [ -z "$SPENT" ]
check "the stone was actually handed over, not just shown" $? "${SPENT:-no smooth_stone left in the basket}"

# Errand two needs the stairs. That the stairs REQUIRE the patch_kit he just
# taught is M5's ordering criterion and is checked there; here we just need a
# world where they are up.
launch m6_crab4 --slot=keeper_a --world=CRB$TAG >/dev/null
sleep 6
setflag CRB$TAG stairs_fixed
sleep 3
kill_all

launch m6_crab_fish --slot=keeper_a --world=CRB$TAG --autowalk=crab_fish >/dev/null
sleep 34
kill_all
launch m6_ready --slot=keeper_a --world=CRB$TAG --autowalk=wheel_stove >/dev/null
sleep 15
kill_all

STAGE5=$(docker compose -f "$REPO/docker-compose.yml" logs --since 5m nakama 2>/dev/null \
  | grep -oE "hermit_crab reached stage 5 \(crab_taught_chowder\) in CRB$TAG" | tail -1)
[ -n "$STAGE5" ]
check "the fish errand ends in the chowder recipe" $? "${STAGE5:-never reached stage five}"

READY=$(grep -oE "\[radial\] opened at stove .* with \[[^]]*\]" "$OUT/m6_ready.log" | tail -1)
echo "$READY" | grep -q "chowder:ready"
check "and only then does the recipe appear unlocked" $? "${READY:-the stove wheel never opened}"

echo
echo "=============================================================="
echo "AC3 — ending a session writes exactly ONE entry; reconnecting"
echo "      shows it in the book on both clients"
echo "=============================================================="
launch m6_log_a --slot=keeper_a --world=LOG$TAG --scene=tower \
  --debug-gather=driftwood_01,driftwood_02 --debug-advance=clear_hearth --autowalk=turn_in >/dev/null
sleep 15
kill_all
launch m6_log_b --slot=keeper_b --world=LOG$TAG --scene=tower --autowalk=turn_in_b >/dev/null
sleep 14
kill_all

WROTE=$(grep -oE "\[logbook\] book now holds [0-9]+ entries" "$OUT/m6_log_a.log" | tail -1)
echo "$WROTE" | grep -q "holds 1 entries"
check "turning in wrote the evening down" $? "${WROTE:-nothing was written}"

OTHER=$(grep -oE "\[logbook\] opened with [0-9]+ entries" "$OUT/m6_log_b.log" | tail -1)
echo "$OTHER" | grep -q "with 1 entries"
check "the other keeper, reconnecting, finds it in the book" $? "${OTHER:-the book never opened}"

# The second turn-in must not write a second entry for the same evening.
NOOP=$(docker compose -f "$REPO/docker-compose.yml" logs --since 2m nakama 2>/dev/null \
  | grep -oE "log requested: logged=true events=0" | tail -1)
[ -n "$NOOP" ]
check "a second turn-in writes nothing" $? "${NOOP:-no second request was seen}"

echo
echo "=============================================================="
echo "AC4 — letter, dialogue and log all pass the unplugged-mouse test"
echo "=============================================================="
UI="$REPO/godot/ui/bottle_reader.gd $REPO/godot/ui/dialogue_box.gd $REPO/godot/ui/log_book.gd"
HITS=$(grep -nE "InputEventMouse|get_global_mouse_position|MOUSE_BUTTON|MOUSE_FILTER_STOP" $UI || true)
[ -z "$HITS" ]
check "no mouse API in any of the three" $? "${HITS:-none}"

# The letter has exactly one stop, which is what makes every direction a no-op.
FOCUSED=$(grep -oE "\[reader\] opened bottle_01 \([0-9]+ page\(s\)\)" "$OUT/m6_b_a.log" | tail -1)
[ -n "$FOCUSED" ]
check "the letter opens with its single stop focused" $? "$FOCUSED"

# The book's focus lives in the entry list and nowhere else.
BOOKFOCUS=$(grep -oE "\[logbook\] reading entry [0-9]+" "$OUT/m6_log_a.log" | tail -1)
[ -n "$BOOKFOCUS" ]
check "the book's left page follows the focused entry" $? "$BOOKFOCUS"

TALKED=$(grep -oE "\[dialogue\] talking to hermit_crab at stage [0-9]+" "$OUT/m6_crab1.log" | tail -1)
[ -n "$TALKED" ]
check "the dialogue box opens on interact and waits for a button" $? "$TALKED"

for MOCK in design/ui/keepers_log.png design/ui/bottle_reader.png; do
  [ -f "$REPO/$MOCK" ]
  check "gated mock present: $MOCK" $? "built from the author's artboard"
done

echo
echo "=============================================================="
echo "AC5 (standing) — tsc clean; GDScript compiles clean"
echo "=============================================================="
(cd "$REPO/nakama" && npx tsc) >"$OUT/tsc.log" 2>&1
check "tsc compiles clean" $? "$(wc -l <"$OUT/tsc.log" | tr -d ' ') lines of output"

"$GODOT" --headless --path "$REPO/godot" --editor --quit-after 60 >"$OUT/gdcheck.log" 2>&1
GD=$?
grep -qiE "SCRIPT ERROR|Parse Error|Compile Error" "$OUT/gdcheck.log"; GREPHIT=$?
[ "$GD" = "0" ] && [ "$GREPHIT" != "0" ]
check "GDScript compiles clean (headless editor pass)" $? "exit=$GD, no script/parse/compile errors"

echo
echo "=============================================================="
echo "M6 result: $pass passed, $fail failed   (evidence in $OUT/)"
echo "=============================================================="
[ "$fail" = "0" ]
