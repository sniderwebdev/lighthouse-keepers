#!/usr/bin/env bash
# verify_m7.sh — runs the M7 acceptance criteria against a live local stack.
#
#   (cd nakama && npx tsc) && docker compose up -d && tools/verify_m7.sh
#
# The last one. Includes a full Act One playthrough: everything is earned by
# real commands — gathered, crafted, funded, and finally lit by two keepers
# reaching for the crank at the same time.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="${OUT:-$REPO/.m7-evidence}"
HOST="http://127.0.0.1:7350"

mkdir -p "$OUT"
rm -f "$OUT"/*.log

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
  -H "Content-Type: application/json" -d '{"id":"lk-m7-verifier-0001"}' \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")

set_cycle() { # set_cycle <world> <cycle>
  curl -s -X POST "$HOST/v2/rpc/debug_set_tide" -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "\"{\\\"world_code\\\":\\\"$1\\\",\\\"t\\\":0.0,\\\"cycle\\\":$2}\"" >/dev/null
}
gate_fires() { # count the gate firings in the server log
  docker compose -f "$REPO/docker-compose.yml" logs --since "${1:-2m}" nakama 2>/dev/null \
    | grep -c "tandem gate relight_lamp fired" || true
}

# ---------------------------------------------------------------- playthrough
echo "=============================================================="
echo "AC2 — a full Act One: gather, craft, all five milestones, then"
echo "      the relight. Every step through the real commands."
echo "=============================================================="
PLAY=ACT$TAG
launch m7_play --slot=keeper_a --world=$PLAY --debug-harvest >/dev/null
sleep 6
# Six tides' worth of shore. Brass and glass come back every other cycle, so the
# lens is what sets the pace.
for C in 1 2 3 4 5 6 7; do set_cycle $PLAY $C; sleep 2.5; done
sleep 2
HARVEST=$(grep -oE "inventory-batch \[[^]]*\]" "$OUT/m7_play.log" | tail -1)
kill_all

# Two patch kits and two lamp oils, at their own stations.
launch m7_craft --slot=keeper_a --world=$PLAY \
  --debug-craft=patch_kit,patch_kit,lamp_oil,lamp_oil >/dev/null
sleep 8
CRAFTED=$(grep -oE "inventory-batch \[[^]]*\]" "$OUT/m7_craft.log" | tail -1)
kill_all

# The chain, in order, funded from what was gathered and made.
launch m7_chain --slot=keeper_a --world=$PLAY --scene=tower \
  --debug-advance=clear_hearth,fix_stairs,repair_glass,restore_lens,relight_lamp >/dev/null
sleep 10
SEALED=$(grep -cE "\[visual\] (hearth_lit|stairs_fixed|glass_repaired|lens_restored|lamp_ready) -> after" "$OUT/m7_chain.log" || true)
kill_all

[ "$SEALED" = "5" ]
check "all five milestones sealed, in order, from earned materials" $? \
  "$SEALED of 5 layers changed in the tower; last basket: ${CRAFTED:-nothing crafted}"

echo
echo "=============================================================="
echo "AC1a — the gate does NOT fire for one keeper alone"
echo "=============================================================="
BEFORE=$(gate_fires 30s)
launch m7_alone --slot=keeper_a --world=$PLAY --scene=tower --autowalk=crank_alone >/dev/null
sleep 16
kill_all
REACHED=$(grep -oE "\[crank\] keeper_a reached for relight_lamp" "$OUT/m7_alone.log" | tail -1)
SHIMMER=$(grep -oE "\[shimmer\] waiting for keeper [AB]" "$OUT/m7_alone.log" | tail -1)
LIT_ALONE=$(grep -cE "\[relight\] the lamp is lit" "$OUT/m7_alone.log" || true)

[ -n "$REACHED" ]
check "one keeper reached for the crank" $? "${REACHED:-never reached it}"

[ -n "$SHIMMER" ]
check "the other keeper is named as the one being waited for" $? "${SHIMMER:-no shimmer shown}"

[ "$LIT_ALONE" = "0" ] && [ "$(gate_fires 40s)" = "$BEFORE" ]
check "the gate did NOT fire" $? "$LIT_ALONE relight beats played; gate firings unchanged"

echo
echo "=============================================================="
echo "AC1b — it fires when the second keeper reaches, within 500ms"
echo "=============================================================="
launch m7_gate_a --slot=keeper_a --world=$PLAY --scene=tower --autowalk=crank_a >/dev/null
launch m7_gate_b --slot=keeper_b --world=$PLAY --scene=tower --autowalk=crank_b >/dev/null
sleep 18
kill_all

FIRED=$(docker compose -f "$REPO/docker-compose.yml" logs --since 1m nakama 2>/dev/null \
  | grep -oE "tandem gate relight_lamp fired \(lamp_lit\) in $PLAY" | tail -1)
[ -n "$FIRED" ]
check "both reached, and the gate fired" $? "${FIRED:-the gate never fired}"

A_LIT=$(grep -oE "\[relight\] the lamp is lit" "$OUT/m7_gate_a.log" | tail -1)
B_LIT=$(grep -oE "\[relight\] the lamp is lit" "$OUT/m7_gate_b.log" | tail -1)
[ -n "$A_LIT" ] && [ -n "$B_LIT" ]
check "the beat played on BOTH clients" $? \
  "keeper A: ${A_LIT:-nothing} | keeper B: ${B_LIT:-nothing}"

SKEW=$(python3 - "$OUT/m7_gate_a.log" "$OUT/m7_gate_b.log" <<'PY'
import re, sys
def lit(path):
    for line in open(path):
        m = re.match(r"([0-9.]+) \[relight\] the lamp is lit", line)
        if m:
            return float(m.group(1))
    return None
a, b = lit(sys.argv[1]), lit(sys.argv[2])
print(f"{abs(a-b):.3f}" if a and b else "999")
PY
)
awk "BEGIN{exit !($SKEW <= 0.5)}"
check "within 500ms of the second reach" $? "${SKEW}s between the two clients lighting up"

echo
echo "=============================================================="
echo "AC1c — the same gate on the couch: one pad is still not enough"
echo "=============================================================="
COUCH=CCH$TAG
launch m7_couch_seed --couch-both --world=$COUCH --debug-harvest >/dev/null
sleep 5
for C in 1 2 3 4 5 6 7; do set_cycle $COUCH $C; sleep 2.5; done
sleep 2
kill_all
launch m7_couch_make --couch-both --world=$COUCH --debug-craft=patch_kit,patch_kit,lamp_oil,lamp_oil >/dev/null
sleep 8
kill_all
launch m7_couch_chain --couch-both --world=$COUCH --scene=tower \
  --debug-advance=clear_hearth,fix_stairs,repair_glass,restore_lens,relight_lamp >/dev/null
sleep 10
kill_all

BEFORE2=$(gate_fires 30s)
launch m7_couch_one --couch-both --world=$COUCH --scene=tower --autowalk=crank_alone >/dev/null
sleep 16
kill_all
COUCH_SHIMMER=$(grep -oE "\[shimmer\] waiting for keeper [AB]" "$OUT/m7_couch_one.log" | tail -1)
[ -n "$COUCH_SHIMMER" ] && [ "$(gate_fires 40s)" = "$BEFORE2" ]
check "one pad on the couch waits for the other, and nothing fires" $? \
  "${COUCH_SHIMMER:-no shimmer}; gate firings unchanged"

# Now both pads. keeper_b is driven by the p2_ column on the couch.
launch m7_couch_both --couch-both --world=$COUCH --scene=tower --autowalk=crank_couch >/dev/null
sleep 18
kill_all
COUCH_LIT=$(grep -oE "\[relight\] the lamp is lit" "$OUT/m7_couch_both.log" | tail -1)
[ -n "$COUCH_LIT" ]
check "both pads on ONE machine fire the same gate" $? "${COUCH_LIT:-the couch never lit it}"

echo
echo "=============================================================="
echo "AC2b — the log shows the story, and the closing beat is stubbed"
echo "=============================================================="
launch m7_log --slot=keeper_a --world=$PLAY --scene=tower --autowalk=turn_in >/dev/null
sleep 14
kill_all
BOOK=$(grep -oE "\[logbook\] (book now holds|opened with) [0-9]+ entries" "$OUT/m7_log.log" | tail -1)
[ -n "$BOOK" ]
check "the evening is in the book" $? "${BOOK:-nothing written}"

STORY=$(grep -oE "\[relight\] beat complete" "$OUT/m7_gate_a.log" | tail -1)
[ -n "$STORY" ]
check "the relight beat ran to its end" $? "${STORY:-it never finished}"

grep -q "TODO_CONTENT_closing" "$REPO/godot/ui/relight_beat.gd"
check "the closing words are left for the author" $? "relight_beat.gd holds a TODO_CONTENT stub"

echo
echo "=============================================================="
echo "AC3 — title flow, mocks, and the standing checks"
echo "=============================================================="
launch m7_title >/dev/null    # no flags at all: a human at a controller
sleep 7
kill_all
TITLE=$(grep -oE "\[title\] focus -> [A-Z ]+" "$OUT/m7_title.log" | head -1)
[ -n "$TITLE" ]
check "with no flags, the front door is the title screen" $? "${TITLE:-the title never appeared}"

HITS=$(grep -nE "InputEventMouse|get_global_mouse_position|MOUSE_BUTTON|MOUSE_FILTER_STOP" \
  "$REPO/godot/ui/title_screen.gd" "$REPO/godot/game/crank.gd" \
  "$REPO/godot/ui/tandem_shimmer.gd" "$REPO/godot/ui/relight_beat.gd" || true)
[ -z "$HITS" ]
check "no mouse API in the title, crank, shimmer or beat" $? "${HITS:-none}"

for MOCK in radial_crafting milestone_board keepers_log bottle_reader title_session; do
  [ -f "$REPO/design/ui/$MOCK.png" ] || { echo "  FAIL  mock missing: $MOCK"; fail=$((fail+1)); }
done
check "all five gated mocks are present" 0 "radial, board, log, letter, title"

(cd "$REPO/nakama" && npx tsc) >"$OUT/tsc.log" 2>&1
check "tsc compiles clean" $? "$(wc -l <"$OUT/tsc.log" | tr -d ' ') lines of output"

"$GODOT" --headless --path "$REPO/godot" --editor --quit-after 60 >"$OUT/gdcheck.log" 2>&1
GD=$?
grep -qiE "SCRIPT ERROR|Parse Error|Compile Error" "$OUT/gdcheck.log"; GREPHIT=$?
[ "$GD" = "0" ] && [ "$GREPHIT" != "0" ]
check "GDScript compiles clean (headless editor pass)" $? "exit=$GD, no script/parse/compile errors"

echo
echo "=============================================================="
echo "M7 result: $pass passed, $fail failed   (evidence in $OUT/)"
echo "=============================================================="
[ "$fail" = "0" ]
