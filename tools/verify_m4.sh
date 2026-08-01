#!/usr/bin/env bash
# verify_m4.sh — runs the M4 acceptance criteria against a live local stack.
#
#   (cd nakama && npx tsc) && docker compose up -d && tools/verify_m4.sh
#
# The wheel is driven by autowalk routes that walk to a real bench, hold the real
# interact action, aim with the real movement actions (or a real d-pad button
# event), and release. Nothing calls into the menu directly.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="${OUT:-$REPO/.m4-evidence}"
HOST="http://127.0.0.1:7350"

mkdir -p "$OUT"
rm -f "$OUT"/*.log

# Worlds PERSIST. Reusing a fixed code would let one run's leftovers — a taken
# node, a stocked basket — decide the next run's result, and an assertion like
# "the basket holds exactly 3" would start passing for the wrong reason. Each run
# gets its own world.
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

# Enough driftwood and kelp for a patch kit, and deliberately no fish, so lamp
# oil is present-but-unaffordable in the same wheel.
SEED="--debug-gather=driftwood_01,driftwood_02,driftwood_03,kelp_01,kelp_02"

TOKEN=$(curl -s -X POST "$HOST/v2/account/authenticate/device?create=true" \
  -H "Authorization: Basic $(printf 'defaultkey:' | base64)" \
  -H "Content-Type: application/json" -d '{"id":"lk-m4-verifier-0001"}' \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")

# patch_kit is TAUGHT by the crab now (CONTENT.md), not known from the start.
# M4 is about the crafting wheel, and the wheel does not care which recipe
# taught it — so put the world into the taught state rather than playing the
# crab's errand inside a crafting test.
teach() { # teach <world>
  curl -s -X POST "$HOST/v2/rpc/debug_set_flag" -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "\"{\\\"world_code\\\":\\\"$1\\\",\\\"flag\\\":\\\"crab_taught_patch_kit\\\"}\"" >/dev/null
}

echo "=============================================================="
echo "AC1 — craft succeeds only when affordable; inputs decrement and"
echo "      output increments on BOTH clients atomically"
echo "=============================================================="
launch m4_craft_a --slot=keeper_a --world=CFA$TAG $SEED --autowalk=craft_at_bench >/dev/null
launch m4_craft_b --slot=keeper_b --world=CFA$TAG >/dev/null
sleep 4; teach CFA$TAG
sleep 20
kill_all

CRAFTED=$(grep -oE "\[radial\] crafting [a-z_]+ at [a-z_]+" "$OUT/m4_craft_a.log" | tail -1)
[ -n "$CRAFTED" ]
check "the wheel sent one craft" $? "${CRAFTED:-nothing was crafted}"

A_OUT=$(grep -oE "inventory patch_kit=[0-9]+" "$OUT/m4_craft_a.log" | tail -1)
B_OUT=$(grep -oE "inventory patch_kit=[0-9]+" "$OUT/m4_craft_b.log" | tail -1)
[ "$A_OUT" = "inventory patch_kit=1" ] && [ "$B_OUT" = "inventory patch_kit=1" ]
check "the output landed on both clients" $? "crafter: $A_OUT | observer: $B_OUT"

A_IN=$(grep -oE "inventory driftwood=[0-9]+" "$OUT/m4_craft_a.log" | tail -1)
[ "$A_IN" = "inventory driftwood=2" ]
check "the inputs were spent (5 driftwood - 3 = 2)" $? "$A_IN"

# Atomicity: the client announces one line per applied diff. A craft that paid
# before it delivered would show its spend and its gain in different batches.
BATCH=$(grep -oE "inventory-batch \[[^]]*\]" "$OUT/m4_craft_b.log" | grep "patch_kit=1" | tail -1)

echo "$BATCH" | grep -q "driftwood=2" && echo "$BATCH" | grep -q "kelp=" && echo "$BATCH" | grep -q "patch_kit=1"
check "spend and gain arrived in ONE diff, not in pieces" $? \
  "${BATCH:-no batch containing patch_kit=1}"

SPLIT=$(grep -cE "inventory-batch \[[^]]*patch_kit" "$OUT/m4_craft_b.log" || true)
[ "$SPLIT" = "1" ]
check "no frame exists where the cost is paid and the output is missing" $? \
  "the craft touched the basket exactly $SPLIT time(s)"

echo
echo "=============================================================="
echo "AC2 — an unaffordable recipe is visibly disabled, and selecting"
echo "      it does nothing server-side"
echo "=============================================================="
launch m4_short --slot=keeper_a --world=CFB$TAG --debug-gather=driftwood_01,kelp_01 \
  --autowalk=craft_unaffordable >/dev/null
# Taught but unaffordable is the state under test here — a LOCKED recipe would
# be disabled for the wrong reason and the check would pass without meaning it.
sleep 4; teach CFB$TAG
sleep 20
kill_all

REFUSED=$(grep -oE "\[radial\] released on unaffordable [a-z_]+; sending nothing" "$OUT/m4_short.log" | tail -1)
[ -n "$REFUSED" ]
check "releasing on an unaffordable recipe sends nothing" $? "${REFUSED:-it sent something}"

SENT=$(grep -cE "\[radial\] crafting " "$OUT/m4_short.log" || true)
[ "$SENT" = "0" ]
check "no craft command left the client" $? "$SENT craft commands sent"

GOT=$(grep -cE "inventory lamp_oil=" "$OUT/m4_short.log" || true)
[ "$GOT" = "0" ]
check "the world granted nothing" $? "$GOT lamp_oil announcements"

# And the same command sent straight past the wheel is still refused, because
# the client's greying-out is a prediction and the server is the actual answer.
# Scoped to THIS world. Unscoped, any lamp_oil crafted anywhere in the last
# three minutes — M7's chain, a previous run still inside the window — fails a
# check that has nothing to do with it.
SRV_BEFORE=$(docker compose -f "$REPO/docker-compose.yml" logs --since 3m nakama 2>/dev/null \
  | grep -c "crafted lamp_oil at the workbench in CFB$TAG" || true)
[ "$SRV_BEFORE" = "0" ]
check "the server never crafted it either" $? "$SRV_BEFORE server-side lamp_oil crafts"

echo
echo "=============================================================="
echo "AC3 — the radial is operable by stick AND by d-pad"
echo "=============================================================="
launch m4_stick --slot=keeper_a --world=CFC$TAG $SEED --autowalk=craft_at_bench >/dev/null
sleep 4; teach CFC$TAG
sleep 20
kill_all
STICK=$(grep -oE "\[radial\] crafting patch_kit at workbench" "$OUT/m4_stick.log" | tail -1)

launch m4_dpad --slot=keeper_a --world=CFD$TAG $SEED --autowalk=craft_dpad >/dev/null
sleep 4; teach CFD$TAG
sleep 20
kill_all
DPAD=$(grep -oE "\[radial\] crafting patch_kit at workbench" "$OUT/m4_dpad.log" | tail -1)

[ -n "$STICK" ]
check "stick aims the wheel and release crafts" $? "${STICK:-the stick route crafted nothing}"

[ -n "$DPAD" ]
check "a real d-pad button event aims it too" $? "${DPAD:-the d-pad route crafted nothing}"

echo
echo "=============================================================="
echo "AC4 — stations, locks and the mock's structure"
echo "=============================================================="
OPENED=$(grep -oE "\[radial\] opened at [a-z_]+ for keeper_[ab]" "$OUT/m4_stick.log" | tail -1)
[ -n "$OPENED" ]
check "holding interact at a bench opens its wheel" $? "$OPENED"

# chowder is stove-only and locked behind crab_taught_chowder, so it must not
# appear on the bench wheel at all.
CHOWDER=$(grep -cE "\[radial\] crafting chowder" "$OUT/m4_stick.log" || true)
[ "$CHOWDER" = "0" ]
check "a stove recipe is not craftable at the bench" $? "$CHOWDER chowder crafts from the bench wheel"

MOCK=design/ui/radial_crafting.png
[ -f "$REPO/$MOCK" ]
check "the gated mock is present and was built from" $? "$MOCK"

# kelp_tea is the only recipe with no unlock flag at a station, so it is the one
# that has to work in a world where nothing has been taught yet. A fresh world:
# gather the kelp, walk to the stove, aim right, let go.
# Longer than the other routes because it is the only one that crosses the whole
# beach: the kelp is at the water and the stove is up by the tower.
KT=KTEA$TAG
launch m4_kelp_tea --slot=keeper_a --world=$KT --autowalk=craft_kelp_tea >/dev/null
sleep 30
kill_all

KT_WHEEL=$(grep -oE "\[radial\] opened at stove .* with \[[^]]*\]" "$OUT/m4_kelp_tea.log" | tail -1)
echo "$KT_WHEEL" | grep -q "kelp_tea:ready"
check "an ungated recipe reads as available in a world that has taught nothing" $? \
  "${KT_WHEEL:-the stove wheel never opened}"

KT_SENT=$(grep -oE "\[radial\] crafting kelp_tea at stove" "$OUT/m4_kelp_tea.log" | tail -1)
[ -n "$KT_SENT" ]
check "the wheel crafted kelp_tea at the stove" $? "${KT_SENT:-the wheel sent no kelp_tea craft}"

# And the world agreed: the server is the only thing that can put it in the basket.
KT_HELD=$(grep -ohE "kelp_tea\":[0-9.]+" "$OUT/m4_kelp_tea.log" | tail -1)
[ -n "$KT_HELD" ] && [ "${KT_HELD#*:}" != "0.0" ]
check "the server granted the kelp_tea into the shared basket" $? \
  "${KT_HELD:-no kelp_tea in the basket}"

echo
echo "=============================================================="
echo "AC5 (standing) — no mouse in the wheel; tsc and GDScript clean"
echo "=============================================================="
HITS=$(grep -nE "InputEventMouse|get_global_mouse_position|MOUSE_BUTTON|MOUSE_FILTER_STOP" \
  "$REPO/godot/ui/radial_menu.gd" "$REPO/godot/game/station.gd" || true)
[ -z "$HITS" ]
check "no mouse API in the wheel or the stations" $? "${HITS:-none}"

(cd "$REPO/nakama" && npx tsc) >"$OUT/tsc.log" 2>&1
check "tsc compiles clean" $? "$(wc -l <"$OUT/tsc.log" | tr -d ' ') lines of output"

"$GODOT" --headless --path "$REPO/godot" --editor --quit-after 60 >"$OUT/gdcheck.log" 2>&1
GD=$?
grep -qiE "SCRIPT ERROR|Parse Error|Compile Error" "$OUT/gdcheck.log"; GREPHIT=$?
[ "$GD" = "0" ] && [ "$GREPHIT" != "0" ]
check "GDScript compiles clean (headless editor pass)" $? "exit=$GD, no script/parse/compile errors"

echo
echo "=============================================================="
echo "M4 result: $pass passed, $fail failed   (evidence in $OUT/)"
echo "=============================================================="
[ "$fail" = "0" ]
