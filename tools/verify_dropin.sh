#!/usr/bin/env bash
# verify_dropin.sh — couch drop-in: the second keeper is not in the world until a
# second player is.
#
#   (cd nakama && npx tsc) && docker compose restart nakama && tools/verify_dropin.sh
#
# Not a PLAN acceptance criterion — a regression guard for the couch session
# model. `--couch` used to claim both slots at boot, so a session started alone
# had a silent twin standing at spawn. Claiming a slot flips presence, and
# presence gates the tide and every tandem gate, so the claim is a Command the
# match validates: the client asks, it does not help itself.
#
# What is asserted is what is ON SCREEN as well as what the server believes.
# Presence alone would not prove the twin is gone.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="${OUT:-$REPO/.dropin-evidence}"

mkdir -p "$OUT"
rm -f "$OUT"/*.log

# Worlds persist; a fixed code would let one run's claims decide the next run's
# result. Fresh world per run.
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
}
kill_all() { pkill -f "Godot --headless --path $REPO/godot" 2>/dev/null; sleep 2; }
trap kill_all EXIT
kill_all

# The selftest's own two report lines, so the assertions read off one source.
before() { grep -m1 "\[dropin:before\]" "$1"; }
after()  { grep -m1 "\[dropin:after\]"  "$1"; }

echo "=============================================================="
echo "AC1 — --couch alone: one keeper in the world, not two"
echo "=============================================================="
W="DRI$TAG"
launch dropin_solo --couch --world="$W" --dropin-selftest
sleep 22
B=$(before "$OUT/dropin_solo.log")
A=$(after  "$OUT/dropin_solo.log")

grep -q "claimed slots keeper_a (couch (waiting for player 2))" "$OUT/dropin_solo.log"
check "--couch claims keeper_a only at boot" $? "${B:-no before line}"

echo "$B" | grep -q "presence=\[a=true b=false\]"
check "server presence has keeper_b absent before any second input" $? "${B:-no before line}"

echo "$B" | grep -q "keeper_b.is_local=false keeper_b.visible=false"
check "keeper_b is OFF SCREEN and driven by nobody" $? "${B:-no before line}"

echo "=============================================================="
echo "AC2 — one press on the second input set and keeper B joins"
echo "=============================================================="
grep -q "\[dropin\] second player pressed p2_interact, claiming keeper_b" "$OUT/dropin_solo.log"
check "a p2_ press sends CLAIM (not a local self-grant)" $? \
  "$(grep -m1 'second player pressed' "$OUT/dropin_solo.log" || echo 'no claim sent')"

echo "$A" | grep -q "claimed=\[keeper_a, keeper_b\]"
check "the match granted keeper_b to this connection" $? "${A:-no after line}"

echo "$A" | grep -q "presence=\[a=true b=true\]"
check "server presence now has both keepers" $? "${A:-no after line}"

echo "$A" | grep -q "keeper_b.is_local=true keeper_b.visible=true"
check "keeper_b is ON SCREEN and locally driven" $? "${A:-no after line}"

echo "$A" | grep -q "keeper_b.input=p2_"
check "keeper_b reads the SECOND input set, not player one's" $? "${A:-no after line}"
kill_all

echo "=============================================================="
echo "AC3 — a keeper someone else holds cannot be claimed"
echo "=============================================================="
W2="DRT$TAG"
launch theft_owner --slot=keeper_b --world="$W2"
sleep 8
launch theft_couch --couch --world="$W2" --dropin-selftest
sleep 22
A2=$(after "$OUT/theft_couch.log")

echo "$A2" | grep -q "claimed=\[keeper_a\]"
check "the couch machine still holds only keeper_a" $? "${A2:-no after line}"

echo "$A2" | grep -q "keeper_b.is_local=false"
check "the online player's keeper stays theirs, not locally driven" $? "${A2:-no after line}"

echo "$A2" | grep -q "presence=\[a=true b=true\]"
check "presence still reports the online keeper present" $? "${A2:-no after line}"
kill_all

echo "=============================================================="
echo "AC4 — --couch-both still claims both up front (the harness path)"
echo "=============================================================="
W3="DRB$TAG"
launch both_now --couch-both --world="$W3"
sleep 14
grep -q "claimed slots keeper_a, keeper_b (couch (both pads))" "$OUT/both_now.log"
check "--couch-both claims both slots at boot, no input needed" $? \
  "$(grep -m1 'claimed slots' "$OUT/both_now.log" || echo 'no claim line')"

grep -q "world entered: beach (couch)" "$OUT/both_now.log"
check "--couch-both reports a full couch session" $? \
  "$(grep -m1 'world entered' "$OUT/both_now.log" || echo 'no world-entered line')"

echo
echo "=============================================================="
echo "drop-in result: $pass passed, $fail failed   (evidence in $OUT/)"
echo "=============================================================="
[ "$fail" = "0" ]
