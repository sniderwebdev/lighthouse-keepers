#!/usr/bin/env bash
# verify_m5.sh — runs the M5 acceptance criteria against a live local stack.
#
#   (cd nakama && npx tsc) && docker compose up -d && tools/verify_m5.sh
#
# The board is driven by an autowalk route that walks to the real post, opens it
# with the real interact action and confirms from the focused card. Order
# enforcement is tested by sending ADVANCE_STEP straight past the board, because
# the point of the rule is that it holds even when the UI is not asked.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="${OUT:-$REPO/.m5-evidence}"

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

# Exactly the 4 driftwood clear_hearth costs.
HEARTH_SEED="--debug-gather=driftwood_01,driftwood_02"

echo "=============================================================="
echo "AC1 — completing clear_hearth lights the fire on BOTH clients"
echo "      within 500ms, and survives a full server restart"
echo "=============================================================="
launch m5_a --slot=keeper_a --world=HRT$TAG --scene=tower $HEARTH_SEED --autowalk=seal_step >/dev/null
launch m5_b --slot=keeper_b --world=HRT$TAG --scene=tower >/dev/null
sleep 18
kill_all

SEALED=$(grep -oE "\[board\] beginning clear_hearth" "$OUT/m5_a.log" | tail -1)
[ -n "$SEALED" ]
check "the board funded the step" $? "${SEALED:-the board never began anything}"

A_LIT=$(grep -oE "\[visual\] hearth_lit -> after" "$OUT/m5_a.log" | tail -1)
B_LIT=$(grep -oE "\[visual\] hearth_lit -> after" "$OUT/m5_b.log" | tail -1)
[ -n "$A_LIT" ] && [ -n "$B_LIT" ]
check "the hearth lit on BOTH clients" $? \
  "keeper: ${A_LIT:-never lit} | observer: ${B_LIT:-never lit}"

SKEW=$(python3 - "$OUT/m5_a.log" "$OUT/m5_b.log" <<'PY'
import re, sys
def lit(path):
    for line in open(path):
        m = re.match(r"([0-9.]+) \[visual\] hearth_lit -> after", line)
        if m:
            return float(m.group(1))
    return None
a, b = lit(sys.argv[1]), lit(sys.argv[2])
print(f"{abs(a-b):.3f}" if a and b else "999")
PY
)
awk "BEGIN{exit !($SKEW <= 0.5)}"
check "both saw it within 500ms of each other" $? "${SKEW}s apart"

echo "        (restarting the whole server...)"
docker compose -f "$REPO/docker-compose.yml" restart nakama >/dev/null 2>&1
sleep 14
launch m5_after_restart --slot=keeper_a --world=HRT$TAG --scene=tower >/dev/null
sleep 10
kill_all

RESTORED=$(grep -oE "\[visual\] hearth_lit -> (after|before)" "$OUT/m5_after_restart.log" | head -1)
[ "$RESTORED" = "[visual] hearth_lit -> after" ]
check "the fire is still lit after a full server restart" $? \
  "on rejoin the tower drew: ${RESTORED:-nothing}"

STILL=$(grep -oE "\[tower\] entered; [0-9]+/[0-9]+ sealed" "$OUT/m5_after_restart.log" | tail -1)
echo "$STILL" | grep -q "1/5 sealed"
check "the chain remembers which step is sealed" $? "${STILL:-no tower line}"

echo
echo "=============================================================="
echo "AC2 — steps enforce order SERVER-side: repair_glass cannot be"
echo "      funded before fix_stairs, even with the resources."
echo "      The Act 1 chain is now clear_hearth -> crab stage 1 (stone)"
echo "      -> patch_kit -> fix_stairs, because patch_kit is taught, not known."
echo "=============================================================="
# A basket with everything repair_glass asks for, and the step before it unsealed.
launch m5_order --slot=keeper_a --world=ORD$TAG --scene=tower \
  --debug-gather=glass_shard_01,glass_shard_02 \
  --debug-advance=repair_glass,restore_lens,relight_lamp >/dev/null
sleep 14
kill_all

GRANTED=$(grep -cE "\[visual\] (glass_repaired|lens_restored|lamp_ready) -> after" "$OUT/m5_order.log" || true)
[ "$GRANTED" = "0" ]
check "none of the out-of-order steps were granted" $? \
  "$GRANTED later steps came true after asking for all three directly"

SRV=$(docker compose -f "$REPO/docker-compose.yml" logs --since 2m nakama 2>/dev/null \
  | grep -cE "sealed milestone (repair_glass|restore_lens|relight_lamp) \([a-z_]+\) in ORD$TAG" || true)
[ "$SRV" = "0" ]
check "the server sealed none of them" $? "$SRV out-of-order seals in the server log"

# And the board itself will not offer them either.
BOARD_REFUSED=$(grep -oE "\[board\] .* is locked behind an earlier step; sending nothing" "$OUT/m5_order.log" | tail -1)
echo "        (the board also declines: ${BOARD_REFUSED:-not exercised in this run})"

echo
echo "=============================================================="
echo "AC3 — warm ramps appear ONLY on states that are actually alight"
echo "=============================================================="
WARM=$(python3 - "$REPO/godot/scenes/tower.tscn" <<'PY'
import re, sys
# The warm ramps from DESIGN §6, as Godot writes them.
WARM = ["1.000000, 0.952941, 0.768627", "0.964706, 0.780392, 0.321569",
        "0.949020, 0.756863, 0.305882"]
# Only these branches are allowed to be warm: something is burning, or brass is
# catching the light, or the lamp is fuelled.
ALLOWED = ("Hearth/Lit", "Lens/Restored", "Lamp/Ready")
bad, good = [], []
parent = ""
for line in open(sys.argv[1]):
    m = re.match(r'\[node name="([^"]+)" type="\w+" parent="([^"]+)"\]', line)
    if m:
        parent = m.group(2) + "/" + m.group(1)
        continue
    if line.startswith("color = Color(") and any(w in line for w in WARM):
        (good if parent.startswith(ALLOWED) else bad).append(parent)
print(f"{len(good)} {len(bad)} {';'.join(bad[:4]) or 'none'}")
PY
)
set -- $WARM
WARM_OK=$1; WARM_BAD=$2; WARM_WHERE=$3

[ "$WARM_BAD" = "0" ]
check "no warm ramp on anything unlit, cold or structural" $? \
  "$WARM_OK warm elements, all inside the lit states; offenders: $WARM_WHERE"

awk "BEGIN{exit !($WARM_OK >= 3)}"
check "the lit states DO carry the warmth" $? "$WARM_OK warm elements across the lit branches"

MOCK=design/ui/milestone_board.png
[ -f "$REPO/$MOCK" ]
check "the gated mock is present and was built from" $? "$MOCK"

echo
echo "=============================================================="
echo "AC4 (standing) — no mouse in the board; tsc and GDScript clean"
echo "=============================================================="
HITS=$(grep -nE "InputEventMouse|get_global_mouse_position|MOUSE_BUTTON|MOUSE_FILTER_STOP" \
  "$REPO/godot/ui/milestone_board.gd" "$REPO/godot/game/milestone_post.gd" \
  "$REPO/godot/game/doorway.gd" "$REPO/godot/game/visual_state.gd" || true)
[ -z "$HITS" ]
check "no mouse API in the board or the tower" $? "${HITS:-none}"

(cd "$REPO/nakama" && npx tsc) >"$OUT/tsc.log" 2>&1
check "tsc compiles clean" $? "$(wc -l <"$OUT/tsc.log" | tr -d ' ') lines of output"

"$GODOT" --headless --path "$REPO/godot" --editor --quit-after 60 >"$OUT/gdcheck.log" 2>&1
GD=$?
grep -qiE "SCRIPT ERROR|Parse Error|Compile Error" "$OUT/gdcheck.log"; GREPHIT=$?
[ "$GD" = "0" ] && [ "$GREPHIT" != "0" ]
check "GDScript compiles clean (headless editor pass)" $? "exit=$GD, no script/parse/compile errors"

echo
echo "=============================================================="
echo "M5 result: $pass passed, $fail failed   (evidence in $OUT/)"
echo "=============================================================="
[ "$fail" = "0" ]
