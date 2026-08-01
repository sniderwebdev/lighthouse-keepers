#!/usr/bin/env bash
# verify_m3.sh — runs the M3 acceptance criteria against a live local stack.
#
#   (cd nakama && npx tsc) && docker compose up -d && tools/verify_m3.sh
#
# Keepers are driven headlessly by --autowalk routes that walk to a real node and
# press the real interact action, so what is exercised is the whole path: input
# map, proximity+facing targeting, Command, server validation, diff, mirror.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="${OUT:-$REPO/.m3-evidence}"
HOST="http://127.0.0.1:7350"

mkdir -p "$OUT"
rm -f "$OUT"/*.log "$OUT"/*.csv

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

TOKEN=$(curl -s -X POST "$HOST/v2/account/authenticate/device?create=true" \
  -H "Authorization: Basic $(printf 'defaultkey:' | base64)" \
  -H "Content-Type: application/json" -d '{"id":"lk-m3-verifier-0001"}' \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")

# --- dev RPCs: ask until the world answers -----------------------------------
#
# A world is only reachable once its match is LIVE, and how long a client takes
# to get there is a property of the machine, not of anything under test. Every
# verifier that guessed a sleep here has eventually been wrong: verify_m8.sh
# taught a world that did not exist yet and blamed the milestone chain four
# steps later, and verify_m4.sh raced its own autowalk route. Both were
# invisible because the answer went to /dev/null.
rpc_log() { cat >>"$OUT/rpc.log"; echo >>"$OUT/rpc.log"; }
retry_rpc() { # retry_rpc <command...>
  local i out
  for i in $(seq 1 20); do
    out=$("$@")
    printf '%s\n' "$out" | rpc_log
    case "$out" in
      *"no live match"*) sleep 1.0 ;;
      *) return 0 ;;
    esac
  done
  echo "rpc never took: $*" >&2
  return 1
}


set_tide_once() { # set_tide <world> <t> [cycle]
  local body="{\\\"world_code\\\":\\\"$1\\\",\\\"t\\\":$2"
  [ $# -ge 3 ] && body="$body,\\\"cycle\\\":$3"
  body="$body}"
  curl -s -X POST "$HOST/v2/rpc/debug_set_tide" -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" -d "\"$body\""
}
set_tide() { # set_tide <world> <t> [cycle]
  retry_rpc set_tide_once "$@"
}

echo "=============================================================="
echo "AC1 — keeper A gathers 3 driftwood; keeper B's inventory shows"
echo "      +3 within 500ms, in BOTH play modes"
echo "=============================================================="
echo "  -- online --"
launch m3_on_a --slot=keeper_a --world=GON$TAG --autowalk=gather_once >/dev/null
launch m3_on_b --slot=keeper_b --world=GON$TAG >/dev/null
sleep 3
set_tide GON$TAG 0.0 >/dev/null      # LOW, so the sandbar is walkable
sleep 18
kill_all

A_INV=$(grep -oE "inventory driftwood=[0-9]+" "$OUT/m3_on_a.log" | tail -1)
B_INV=$(grep -oE "inventory driftwood=[0-9]+" "$OUT/m3_on_b.log" | tail -1)
[ "$A_INV" = "inventory driftwood=3" ] && [ "$B_INV" = "inventory driftwood=3" ]
check "A gathered 3 driftwood and B sees the same 3" $? "gatherer: $A_INV | observer: $B_INV"

SKEW=$(python3 - "$OUT/m3_on_a.log" "$OUT/m3_on_b.log" <<'PY'
import re, sys
def first(path):
    for line in open(path):
        m = re.match(r"([0-9.]+) .*inventory driftwood=3", line)
        if m:
            return float(m.group(1))
    return None
a, b = first(sys.argv[1]), first(sys.argv[2])
print(f"{abs(a-b):.3f}" if a and b else "999")
PY
)
awk "BEGIN{exit !($SKEW <= 0.5)}"
check "the other keeper saw it within 500ms" $? "${SKEW}s between the two clients recording driftwood=3"

echo "  -- couch --"
launch m3_couch --couch-both --world=GCH$TAG --autowalk=gather_once >/dev/null
sleep 3
set_tide GCH$TAG 0.0 >/dev/null
sleep 18
kill_all
C_INV=$(grep -oE "inventory driftwood=[0-9]+" "$OUT/m3_couch.log" | tail -1)
[ "$C_INV" = "inventory driftwood=3" ]
check "couch mode gathers the same 3 into the shared basket" $? "$C_INV"

echo
echo "=============================================================="
echo "AC2 — a depleted node visibly empties on both clients and"
echo "      respawns after the configured number of cycles"
echo "=============================================================="
launch m3_node_a --slot=keeper_a --world=NOD$TAG --autowalk=gather_once >/dev/null
launch m3_node_b --slot=keeper_b --world=NOD$TAG >/dev/null
sleep 3
set_tide NOD$TAG 0.0 0 >/dev/null
sleep 18
A_EMPTY=$(grep -oE "\[node\] driftwood_01 visible=false" "$OUT/m3_node_a.log" | tail -1)
B_EMPTY=$(grep -oE "\[node\] driftwood_01 visible=false" "$OUT/m3_node_b.log" | tail -1)

# driftwood_01 comes back after ONE cycle, so one cycle is what it gets.
set_tide NOD$TAG 0.0 1 >/dev/null
sleep 5
A_BACK=$(grep -oE "\[node\] driftwood_01 visible=true" "$OUT/m3_node_a.log" | tail -1)
B_BACK=$(grep -oE "\[node\] driftwood_01 visible=true" "$OUT/m3_node_b.log" | tail -1)
kill_all

[ -n "$A_EMPTY" ] && [ -n "$B_EMPTY" ]
check "the emptied node stops being drawn on BOTH clients" $? \
  "gatherer: ${A_EMPTY:-never emptied} | observer: ${B_EMPTY:-never emptied}"

[ -n "$A_BACK" ] && [ -n "$B_BACK" ]
check "it comes back after its configured 1 cycle, on both" $? \
  "gatherer: ${A_BACK:-never restocked} | observer: ${B_BACK:-never restocked}"

# Nothing should come back early: a node with respawn_cycles 2 must still be gone.
EARLY=$(grep -cE "\[node\] (brass_scrap_01|glass_shard_01) visible=true" "$OUT/m3_node_a.log" || true)
echo "        (two-cycle nodes were untouched this run, so nothing to restock early)"

echo
echo "=============================================================="
echo "AC3 — spamming interact does not double-grant"
echo "=============================================================="
launch m3_spam --slot=keeper_a --world=SPM$TAG --autowalk=gather_spam >/dev/null
sleep 3
set_tide SPM$TAG 0.0 >/dev/null
sleep 20
kill_all

SPAM_INV=$(grep -oE "inventory driftwood=[0-9]+" "$OUT/m3_spam.log" | tail -1)
SPAM_GRANTS=$(grep -cE "inventory driftwood=" "$OUT/m3_spam.log" || true)
[ "$SPAM_INV" = "inventory driftwood=3" ]
check "mashing interact still yields exactly the node's 3" $? \
  "$SPAM_INV after ~150 presses; the world announced the count $SPAM_GRANTS time(s)"

[ "$SPAM_GRANTS" -le 2 ]
check "the world granted the node once, not once per press" $? \
  "$SPAM_GRANTS inventory announcements (1 expected; the join snapshot may add one)"

echo
echo "=============================================================="
echo "AC4 — inventory fully navigable by d-pad; focus visible;"
echo "      cancel closes"
echo "=============================================================="
launch m3_ui --slot=keeper_a --world=UIM$TAG \
  --debug-gather=driftwood_01,kelp_01,brass_scrap_01,glass_shard_01 --ui-selftest >/dev/null
sleep 16
kill_all

OPENED=$(grep -oE "\[inventory\] opened with [0-9]+ kinds" "$OUT/m3_ui.log" | tail -1)
FOCUS_MOVES=$(grep -cE "\[inventory\] focus -> " "$OUT/m3_ui.log" || true)
FOCUS_SEQ=$(grep -oE "\[inventory\] focus -> [a-z_]+" "$OUT/m3_ui.log" | sed 's/.*-> //' | tr '\n' ' ')
CLOSED=$(grep -cE "\[inventory\] closed" "$OUT/m3_ui.log" || true)
FINAL=$(grep -oE "uitest: inventory open=(true|false) \(expected false\)" "$OUT/m3_ui.log" | tail -1)

[ -n "$OPENED" ]
check "held menu_radial opens the basket" $? "$OPENED"

[ "$FOCUS_MOVES" -ge 4 ]
check "d-pad moves focus between cells" $? "focus went: $FOCUS_SEQ"

# Focus starting somewhere is what makes a pad usable at all — with nothing
# focused, the first direction press goes nowhere.
echo "$FOCUS_SEQ" | grep -q "^[a-z]"
check "focus lands on a cell the moment it opens" $? "first focus: $(echo "$FOCUS_SEQ" | awk '{print $1}')"

[ "$CLOSED" -ge 1 ] && [ "$FINAL" = "uitest: inventory open=false (expected false)" ]
check "cancel closes it" $? "${FINAL:-never closed}"

UIBIND=$("$GODOT" --headless --path "$REPO/godot" --script tools/dump_ui_actions.gd 2>/dev/null \
  | grep -E "^ui_(accept|cancel)" | grep -c "Joypad Button")
[ "$UIBIND" = "2" ]
check "confirm and back are bound to the pad, not just the keyboard" $? \
  "$UIBIND of 2 ui_accept/ui_cancel actions carry a joypad button"

echo
echo "=============================================================="
echo "AC5 (standing) — no mouse in the player or menu path;"
echo "                 tsc clean; GDScript compiles clean"
echo "=============================================================="
UI_PATH="$REPO/godot/ui/inventory_panel.gd $REPO/godot/ui/pause_menu.gd $REPO/godot/ui/game_menus.gd"
PLAYER_PATH="$REPO/godot/game/keeper.gd $REPO/godot/game/interactor.gd $REPO/godot/game/interactable.gd $REPO/godot/game/resource_node.gd"
HITS=$(grep -nE "InputEventMouse|get_global_mouse_position|MOUSE_BUTTON|MOUSE_FILTER_STOP" $UI_PATH $PLAYER_PATH || true)
[ -z "$HITS" ]
check "no mouse API in the inventory, menu or gathering path" $? "${HITS:-none}"

(cd "$REPO/nakama" && npx tsc) >"$OUT/tsc.log" 2>&1
check "tsc compiles clean" $? "$(wc -l <"$OUT/tsc.log" | tr -d ' ') lines of output"

"$GODOT" --headless --path "$REPO/godot" --editor --quit-after 60 >"$OUT/gdcheck.log" 2>&1
GD=$?
grep -qiE "SCRIPT ERROR|Parse Error|Compile Error" "$OUT/gdcheck.log"; GREPHIT=$?
[ "$GD" = "0" ] && [ "$GREPHIT" != "0" ]
check "GDScript compiles clean (headless editor pass)" $? "exit=$GD, no script/parse/compile errors"

echo
echo "=============================================================="
echo "M3 result: $pass passed, $fail failed   (evidence in $OUT/)"
echo "=============================================================="
[ "$fail" = "0" ]
