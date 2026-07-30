#!/usr/bin/env bash
# verify_m0.sh — runs the M0 acceptance criteria against a live local stack.
#
#   docker compose up -d && (cd nakama && npx tsc) && tools/verify_m0.sh
#
# Clients run headless; every assertion is made against their stdout, so the
# evidence for each AC is the log file it names.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="${OUT:-$REPO/.m0-evidence}"
WORLD="${WORLD:-TEST01}"

mkdir -p "$OUT"
rm -f "$OUT"/*.log

pass=0
fail=0
check() { # check <name> <condition-result> <detail>
  if [ "$2" = "0" ]; then
    echo "  PASS  $1"
    echo "        $3"
    pass=$((pass + 1))
  else
    echo "  FAIL  $1"
    echo "        $3"
    fail=$((fail + 1))
  fi
}

launch() { # launch <logname> <flags...>
  local name="$1"; shift
  "$GODOT" --headless --path "$REPO/godot" -- "$@" >"$OUT/$name.log" 2>&1 &
  echo $!
}

kill_all() {
  pkill -f "Godot --headless --path $REPO/godot" 2>/dev/null
  sleep 2
}

trap kill_all EXIT
kill_all

echo "=============================================================="
echo "AC1 — two instances join $WORLD, claim different slots,"
echo "      and read the same tide phase"
echo "=============================================================="
PA=$(launch ac1_a --slot=keeper_a "--world=$WORLD")
PB=$(launch ac1_b --slot=keeper_b "--world=$WORLD")
sleep 14

A_SLOT=$(grep -o 'claimed slots [a-z_, ]*' "$OUT/ac1_a.log" | tail -1)
B_SLOT=$(grep -o 'claimed slots [a-z_, ]*' "$OUT/ac1_b.log" | tail -1)
[ "$A_SLOT" = "claimed slots keeper_a " ] && [ "$B_SLOT" = "claimed slots keeper_b " ]
check "different slots claimed" $? "A: '$A_SLOT' | B: '$B_SLOT'"

A_PHASE=$(grep -o 'tide=[A-Z]*' "$OUT/ac1_a.log" | tail -1)
B_PHASE=$(grep -o 'tide=[A-Z]*' "$OUT/ac1_b.log" | tail -1)
[ -n "$A_PHASE" ] && [ "$A_PHASE" = "$B_PHASE" ]
check "same tide phase on both clients" $? "A: $A_PHASE | B: $B_PHASE"

A_PRES=$(grep -o 'presence=\[a=[a-z]* b=[a-z]*\]' "$OUT/ac1_a.log" | tail -1)
B_PRES=$(grep -o 'presence=\[a=[a-z]* b=[a-z]*\]' "$OUT/ac1_b.log" | tail -1)
[ "$A_PRES" = "presence=[a=true b=true]" ] && [ "$B_PRES" = "presence=[a=true b=true]" ]
check "both slots show present on both clients" $? "A: $A_PRES | B: $B_PRES"

echo
echo "--- extra: a third connection asking for a taken slot is refused ---"
PC3=$(launch ac1_c --slot=keeper_a "--world=$WORLD")
sleep 10
grep -q 'join refused' "$OUT/ac1_c.log"
check "duplicate slot claim rejected by the match" $? "$(grep -o 'join refused.*' "$OUT/ac1_c.log" | tail -1)"
kill "$PC3" 2>/dev/null

echo
echo "=============================================================="
echo "AC2 — killing one instance and rejoining restores its slot <5s"
echo "=============================================================="
kill "$PA" 2>/dev/null
sleep 2
START=$(date +%s)
PA2=$(launch ac2_a_rejoin --slot=keeper_a "--world=$WORLD")
DEADLINE=$((START + 5))
CLAIMED=""
while [ "$(date +%s)" -le "$DEADLINE" ]; do
  if grep -q 'claimed slots keeper_a' "$OUT/ac2_a_rejoin.log" 2>/dev/null; then
    CLAIMED="$(( $(date +%s) - START ))"
    break
  fi
  sleep 0.2
done
[ -n "$CLAIMED" ]
check "slot keeper_a restored within 5s of relaunch" $? "reclaimed after ${CLAIMED:-">5"}s (see ac2_a_rejoin.log)"
kill_all

echo
echo "=============================================================="
echo "AC3 — one instance in couch mode claims BOTH slots"
echo "=============================================================="
PC=$(launch ac3_couch --couch-both "--world=$WORLD")
sleep 12
C_SLOT=$(grep -oE 'claimed slots keeper_a, keeper_b \(couch' "$OUT/ac3_couch.log" | tail -1)
[ -n "$C_SLOT" ]
check "both slots claimed by one connection" $? "${C_SLOT:-none} (see ac3_couch.log)"
C_PRES=$(grep -o 'presence=\[a=[a-z]* b=[a-z]*\]' "$OUT/ac3_couch.log" | tail -1)
[ "$C_PRES" = "presence=[a=true b=true]" ]
check "both slots present from the single connection" $? "$C_PRES"
kill_all

echo
echo "=============================================================="
echo "AC4 — tsc clean; godot --check-only clean"
echo "=============================================================="
(cd "$REPO/nakama" && npx tsc) >"$OUT/tsc.log" 2>&1
check "tsc compiles clean" $? "$(wc -l <"$OUT/tsc.log" | tr -d ' ') lines of output (tsc.log)"

# `--check-only --script FILE` parses one file with NO autoloads registered, so
# every script that touches EventBus/Net/WorldState reports a false "Identifier
# not found". A headless editor pass compiles the whole project WITH autoloads,
# which is the check the AC actually wants.
"$GODOT" --headless --path "$REPO/godot" --editor --quit-after 60 >"$OUT/gdcheck.log" 2>&1
GD=$?
grep -qiE "SCRIPT ERROR|Parse Error|Compile Error" "$OUT/gdcheck.log"; GREPHIT=$?
[ "$GD" = "0" ] && [ "$GREPHIT" != "0" ]
check "GDScript compiles clean (headless editor pass)" $? "exit=$GD, no script/parse/compile errors (gdcheck.log)"

echo
echo "=============================================================="
echo "M0 result: $pass passed, $fail failed   (evidence in $OUT/)"
echo "=============================================================="
[ "$fail" = "0" ]
