#!/usr/bin/env bash
# verify_m8.sh — runs the M8 acceptance criteria against a live local stack.
#
#   tools/build.sh && docker compose up -d && tools/verify_m8.sh
#
# The playthrough checks run against the BUILT binary, not the editor — that is
# the whole point of the milestone. The last criterion is the playtest gate, and
# it is meant to fail until a human has played and written it down.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
# AC1 is "it runs from a BUILT binary", so this must be the binary the build just
# produced. The macOS export is a ZIP; pointing at build/macos/app/ meant running
# whatever had last been unzipped there by hand — which, when this was found, was
# a copy two days older than the code under test. Unpacked per run below.
APP=""
EXE="$REPO/build/windows/LighthouseKeepers.exe"
OUT="${OUT:-$REPO/.m8-evidence}"
HOST="http://127.0.0.1:7350"

mkdir -p "$OUT"
rm -f "$OUT"/*.log

TAG=$(date +%s | tail -c 5)

APP_ZIP="$REPO/build/macos/LighthouseKeepers.zip"
if [ ! -f "$APP_ZIP" ]; then
  echo "no macOS build at $APP_ZIP — run tools/build.sh first" >&2
  exit 1
fi
rm -rf "$OUT/app"
mkdir -p "$OUT/app"
unzip -q "$APP_ZIP" -d "$OUT/app"
APP="$OUT/app/Lighthouse Keepers.app/Contents/MacOS/Lighthouse Keepers"
chmod +x "$APP"

pass=0
fail=0
check() {
  if [ "$2" = "0" ]; then echo "  PASS  $1"; pass=$((pass + 1))
  else echo "  FAIL  $1"; fail=$((fail + 1)); fi
  echo "        $3"
}

# Launched from the BUILT app: no --path, no editor, nothing but the binary.
launch_built() {
  local name="$1"; shift
  "$APP" --headless -- "$@" >"$OUT/$name.log" 2>&1 &
  echo $!
}
launch_editor() {
  local name="$1"; shift
  "$GODOT" --headless --path "$REPO/godot" -- "$@" >"$OUT/$name.log" 2>&1 &
  echo $!
}
kill_all() {
  pkill -f "Lighthouse Keepers" 2>/dev/null
  pkill -f "Godot --headless --path $REPO/godot" 2>/dev/null
  sleep 2
}
trap kill_all EXIT
kill_all

TOKEN=$(curl -s -X POST "$HOST/v2/account/authenticate/device?create=true" \
  -H "Authorization: Basic $(printf 'defaultkey:' | base64)" \
  -H "Content-Type: application/json" -d '{"id":"lk-m8-verifier-0001"}' \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")
# Every dev RPC's answer is kept. Discarding it means a world that quietly never
# entered the state the run assumes, and an assertion three steps later failing
# for a reason nothing in the output explains — which is exactly how the flag
# below went missing while AC1 blamed the milestone chain.
rpc_log() { cat >>"$OUT/rpc.log"; echo >>"$OUT/rpc.log"; }

## A world is only reachable once its match is LIVE, and how long a 180MB binary
## takes to get there is a property of the machine, not of anything under test.
## Sleeping a guessed six seconds worked until the binary grew; then `teach`
## started landing before the world existed, silently, and the playthrough failed
## four steps downstream. Ask until it answers instead.
retry_rpc() { # retry_rpc <command...>
  local i out
  for i in $(seq 1 20); do
    out=$("$@")
    printf '%s\n' "$out" | rpc_log
    case "$out" in
      *"no live match"*) sleep 1.5 ;;
      *) return 0 ;;
    esac
  done
  return 1
}

set_cycle_once() {
  curl -s -X POST "$HOST/v2/rpc/debug_set_tide" -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "\"{\\\"world_code\\\":\\\"$1\\\",\\\"t\\\":0.0,\\\"cycle\\\":$2}\""
}
set_cycle() { retry_rpc set_cycle_once "$1" "$2"; }

# patch_kit is TAUGHT by the crab now (CONTENT.md). M8's subject is the BUILT
# BINARY, not the crab's errands, so put the world into the taught state.
teach_once() { # teach_once <world>
  curl -s -X POST "$HOST/v2/rpc/debug_set_flag" -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "\"{\\\"world_code\\\":\\\"$1\\\",\\\"flag\\\":\\\"crab_taught_patch_kit\\\"}\""
}
teach() { # teach <world>
  retry_rpc teach_once "$1"
}

echo "=============================================================="
echo "AC1 — a full-content playthrough runs from a BUILT binary,"
echo "      not just the editor"
echo "=============================================================="
[ -f "$EXE" ] && file "$EXE" | grep -q "PE32+ executable"
check "the Windows build is a real executable" $? "$(file -b "$EXE" 2>/dev/null | cut -d, -f1-2)"

[ -x "$APP" ]
check "the macOS build exists and can be run here" $? "$(basename "$(dirname "$(dirname "$APP")")")"

PLAY=BLT$TAG
launch_built m8_harvest --slot=keeper_a --world=$PLAY --debug-harvest >/dev/null
sleep 6
# While this world is live: the next run crafts at world entry, too early for
# an RPC aimed at it to land first.
teach $PLAY
for C in 1 2 3 4 5 6 7; do set_cycle $PLAY $C; sleep 2.2; done
sleep 2
kill_all
launch_built m8_craft --slot=keeper_a --world=$PLAY \
  --debug-craft=patch_kit,patch_kit,lamp_oil,lamp_oil >/dev/null
sleep 8
kill_all
launch_built m8_chain --slot=keeper_a --world=$PLAY --scene=tower \
  --debug-advance=clear_hearth,fix_stairs,repair_glass,restore_lens,relight_lamp >/dev/null
sleep 10
SEALED=$(grep -cE "\[visual\] (hearth_lit|stairs_fixed|glass_repaired|lens_restored|lamp_ready) -> after" "$OUT/m8_chain.log" || true)
kill_all

[ "$SEALED" = "5" ]
check "all five milestones sealed, from the built binary" $? "$SEALED of 5 tower layers changed"

launch_built m8_gate_a --slot=keeper_a --world=$PLAY --scene=tower --autowalk=crank_a >/dev/null
launch_built m8_gate_b --slot=keeper_b --world=$PLAY --scene=tower --autowalk=crank_b >/dev/null
sleep 18
kill_all
A_LIT=$(grep -oE "\[relight\] the lamp is lit" "$OUT/m8_gate_a.log" | tail -1)
B_LIT=$(grep -oE "\[relight\] the lamp is lit" "$OUT/m8_gate_b.log" | tail -1)
[ -n "$A_LIT" ] && [ -n "$B_LIT" ]
check "two built clients lit the lamp together" $? \
  "A: ${A_LIT:-nothing} | B: ${B_LIT:-nothing}"

echo
echo "=============================================================="
echo "AC2 — four tuning values, adjustable from a pad, applying"
echo "      within a second, surviving relaunch"
echo "=============================================================="

# The selftest turns every value ONE STEP RIGHT from whatever is already loaded,
# and persists it. So this assertion is only knowable if we control where it
# starts: run it from the committed defaults, and derive what one step right of
# those looks like from Tuning.DEFAULTS rather than hard-coding a number.
#
# Hard-coding it (this used to assert the literal "walk speed 95") failed on
# every run after the first — the value ratcheted 90 -> 95 -> 100 across runs —
# and left whatever it ratcheted to in the cfg for the next human to play at.
TUNING_CFG="$HOME/Library/Application Support/Godot/app_userdata/Lighthouse Keepers/tuning.cfg"
reset_tuning_cfg() { rm -f "$TUNING_CFG"; }
reset_tuning_cfg

# One step right of every committed default, rendered exactly the way
# Tuning.summary() renders it, straight out of the GDScript source of truth.
EXPECTED_TUNING=$(python3 - "$REPO/godot/autoload/tuning.gd" <<'PY'
import re, sys

src = open(sys.argv[1]).read()
block = re.search(r"const DEFAULTS.*?\n\}", src, re.S).group(0)
row = re.compile(
    r'"(\w+)":\s*\[\s*([-\d.]+),\s*([-\d.]+),\s*([-\d.]+),\s*([-\d.]+),'
    r'\s*"([^"]*)",\s*"([^"]*)"\s*\]'
)
parts = []
for key, default, lo, hi, step, label, unit in row.findall(block):
    value = min(max(float(default) + float(step), float(lo)), float(hi))
    # Tuning._format: two decimals under ten, none at or above it.
    text = ("%.2f" % value) if value < 10.0 else ("%.0f" % value)
    if unit:
        text += " " + unit
    parts.append("%s %s" % (label, text))
print(" · ".join(parts))
PY
)

launch_built m8_tune --slot=keeper_a --world=TUN$TAG --tuning-selftest --tuning-persist >/dev/null
sleep 16
kill_all

TUNED=$(python3 - "$OUT/m8_tune.log" <<'PY'
import re, sys
turns = {}
opened = closed = None
for line in open(sys.argv[1]):
    m = re.match(r"([0-9.]+) .*tunetest: ([a-z_]+) now ", line)
    if m:
        turns[m.group(2)] = float(m.group(1))
    m = re.search(r"\[tuning\] ([a-z_]+) = ", line)
    if m:
        t = float(line.split()[0])
        turns.setdefault(m.group(1), t)
    if "tunetest: before" in line:
        opened = float(line.split()[0])
    if "tunetest: after" in line:
        closed = float(line.split()[0])
# Widest gap between a value being set and the UI reporting it back.
lags = []
prev = None
for line in open(sys.argv[1]):
    m = re.search(r"([0-9.]+) \[tuning\] ([a-z_]+) = ", line)
    if m:
        prev = (float(m.group(1)), m.group(2))
    m2 = re.match(r"([0-9.]+) .*tunetest: ([a-z_]+) now ", line)
    if m2 and prev and prev[1] == m2.group(2):
        lags.append(float(m2.group(1)) - prev[0])
print(f"{len(turns)} {max(lags) if lags else 9:.3f}")
PY
)
set -- $TUNED
TURNED_N=$1; WORST_LAG=$2

[ "$TURNED_N" = "4" ]
check "all four values turned from the pad" $? "$TURNED_N of 4 changed during the run"

awk "BEGIN{exit !($WORST_LAG <= 1.0)}"
check "a changed value is in force within a second" $? "worst set-to-observed gap ${WORST_LAG}s"

launch_built m8_tune2 --slot=keeper_a --world=TUN$TAG >/dev/null
sleep 8
kill_all
RELOADED=$(grep -oE "\[tuning\] loaded: .*" "$OUT/m8_tune2.log" | tail -1)
[ "$RELOADED" = "[tuning] loaded: $EXPECTED_TUNING" ]
check "the values survived relaunch" $? \
  "expected '$EXPECTED_TUNING'; got '${RELOADED#*loaded: }'"

# ...and an automated run must NOT inherit them, or every timing assertion after
# a playtest is quietly measuring somebody's experiment.
launch_built m8_tune3 --slot=keeper_a --world=TUN$TAG --autowalk=gather_once >/dev/null
sleep 6
kill_all
IGNORED=$(grep -oE "\[tuning\] harness run: using committed defaults" "$OUT/m8_tune3.log" | tail -1)
[ -n "$IGNORED" ]
check "a harness run measures committed defaults, not the experiment" $? \
  "${IGNORED:-the harness inherited tuning.cfg}"

# The selftest's experiment does not outlive the selftest. Without this, the next
# person to launch the game plays at values nobody chose — and the author tunes
# a playtest from a baseline this script invented.
reset_tuning_cfg

echo
echo "=============================================================="
echo "AC3 — the feel-test room contains zero story content"
echo "=============================================================="
STORY=$(grep -nE "BottleDef|MilestoneDef|NpcDef|BottlePickup|MilestonePost|bottle_id|milestone_id|npc_id|hermit" \
  "$REPO/godot/scenes/feel_test.tscn" || true)
[ -z "$STORY" ]
check "no story class, scene or id appears in feel_test.tscn" $? "${STORY:-none}"

launch_built m8_feel --couch-both --world=FEL$TAG --scene=feel >/dev/null
sleep 8
kill_all
OPENED=$(grep -oE "\[feeltest\] room open .*" "$OUT/m8_feel.log" | tail -1)
NOSTORY=$(grep -cE "\[bottle\]|\[board\]|\[dialogue\]" "$OUT/m8_feel.log" || true)
[ -n "$OPENED" ] && [ "$NOSTORY" = "0" ]
check "the room runs and nothing story-shaped wakes up in it" $? \
  "${OPENED:-room never opened}; $NOSTORY story events"

echo
echo "=============================================================="
echo "AC4 — moving a test prop 40px breaks no harness test"
echo "=============================================================="
# Move the driftwood and the workbench (and their markers, which live beside
# them) and re-run the routes that visit them. A route that encoded distance
# would fail here; one that names a place does not care.
python3 - "$REPO" <<'PY'
import sys, shutil
repo = sys.argv[1]
p = f"{repo}/godot/scenes/beach.tscn"
shutil.copy(p, p + ".bak")

# Shift the position line that follows each named node header. Line-wise rather
# than by regex: a .tscn is a flat list of stanzas, and treating it as one is far
# harder to get quietly wrong than a pattern that can silently match nothing.
TARGETS = ['[node name="driftwood_01" ', '[node name="tm_driftwood_01" ',
           '[node name="workbench" ', '[node name="tm_workbench" ']
lines = open(p).read().split("\n")
armed = False
moved = []
for i, line in enumerate(lines):
    if any(line.startswith(t) for t in TARGETS):
        armed = True
    elif armed and line.startswith("position = Vector2("):
        x, y = [int(float(v)) for v in line[len("position = Vector2("):-1].split(",")]
        lines[i] = f"position = Vector2({x + 40}, {y + 40})"
        moved.append((x, y))
        armed = False
    elif armed and line.startswith("["):
        armed = False
open(p, "w").write("\n".join(lines))
if len(moved) != 4:
    print(f"MOVE FAILED: shifted {len(moved)} of 4")
    sys.exit(1)
print(f"moved driftwood_01 and workbench, and their markers, by 40px from {moved}")
PY
MOVE_OK=$?
"$GODOT" --headless --path "$REPO/godot" --import >/dev/null 2>&1

launch_editor m8_moved_gather --slot=keeper_a --world=MOV$TAG --autowalk=gather_once >/dev/null
sleep 20
kill_all
MOVED_GATHER=$(grep -oE "inventory driftwood=[0-9]+" "$OUT/m8_moved_gather.log" | tail -1)

launch_editor m8_moved_craft --slot=keeper_a --world=MOV$TAG \
  --debug-gather=driftwood_02,driftwood_03,kelp_01 --autowalk=craft_at_bench >/dev/null
sleep 22
kill_all
MOVED_CRAFT=$(grep -oE "\[radial\] opened at workbench .*" "$OUT/m8_moved_craft.log" | tail -1)

mv "$REPO/godot/scenes/beach.tscn.bak" "$REPO/godot/scenes/beach.tscn"
"$GODOT" --headless --path "$REPO/godot" --import >/dev/null 2>&1

[ "$MOVE_OK" = "0" ] && [ -n "$MOVED_GATHER" ]
check "the gather route still found its node after it moved" $? "${MOVED_GATHER:-never gathered}"

[ "$MOVE_OK" = "0" ] && [ -n "$MOVED_CRAFT" ]
check "the craft route still found the bench after it moved" $? "${MOVED_CRAFT:-the wheel never opened}"

echo
echo "=============================================================="
echo "AC5 — a two-human playtest is logged (the author runs this)"
echo "=============================================================="
[ -f "$REPO/PLAYTESTS.md" ]
check "PLAYTESTS.md exists with the entry format" $? "the how-to and the template are in place"

ENTRIES=$(grep -cE "^### [0-9]{4}-[0-9]{2}-[0-9]{2} — " "$REPO/PLAYTESTS.md" || true)
[ "$ENTRIES" -ge 1 ]
check "at least one playtest is logged" $? \
  "$ENTRIES entries — this is the gate; M9's feel work waits for a human"

echo
echo "=============================================================="
echo "Standing checks"
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
echo "M8 result: $pass passed, $fail failed   (evidence in $OUT/)"
echo "=============================================================="
[ "$fail" = "0" ]
