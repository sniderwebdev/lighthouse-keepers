#!/usr/bin/env bash
# verify_m1.sh — runs the M1 acceptance criteria against a live local stack.
#
#   docker compose up -d && (cd nakama && npx tsc) && tools/verify_m1.sh
#
# Clients are driven headlessly by --autowalk, which synthesises input through
# the real action map, and record a per-frame CSV via --trace. They run in the
# plain room rather than the beach: movement and camera numbers are measured
# against that geometry, and a tide that flooded a zone mid-run would teleport a
# keeper and look exactly like the mirror stutter this is trying to detect. The assertions are
# made against those traces, so the evidence for each AC is a file you can plot.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="${OUT:-$REPO/.m1-evidence}"

mkdir -p "$OUT"
rm -f "$OUT"/*.log "$OUT"/*.csv

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

echo "=============================================================="
echo "AC1 — online: each instance moves its own keeper; the other's"
echo "      mirror moves smoothly (no teleporting at 10Hz)"
echo "=============================================================="
# A walks. B does not, and only traces — so B's keeper_a row is purely the
# mirrored, interpolated remote.
launch m1_online_a --slot=keeper_a --world=ONLINE1 --scene=room --autowalk >/dev/null
sleep 3
launch m1_online_b --slot=keeper_b --world=ONLINE1 --scene=room "--trace=$OUT/online_b.csv" >/dev/null
sleep 26
kill_all

# A keeper at 90 px/s covers 1.5 px per 60Hz frame. Replaying 10Hz samples
# without interpolation would instead show ~9 px hops separated by dead frames,
# so the per-frame step distribution is what separates the two outright.
ONLINE=$(python3 - "$OUT/online_b.csv" <<'PY'
import sys, math
def rows_of(path, *fields):
    import csv
    out = []
    for r in csv.DictReader(open(path)):
        try:
            for f in fields:
                float(r[f])
        except (ValueError, TypeError, KeyError):
            continue   # truncated final row from a killed process
        out.append(r)
    return out
rows=rows_of(sys.argv[1], 'x', 'y', 'zoom', 'cam_x', 'cam_y')
rem=[r for r in rows if r['slot']=='keeper_a' and r['is_local']=='0']
loc=[r for r in rows if r['slot']=='keeper_b' and r['is_local']=='1']
if not rem: print("0 0 0 0"); sys.exit()
xs=[float(r['x']) for r in rem]; ys=[float(r['y']) for r in rem]
travel=(max(xs)-min(xs))+(max(ys)-min(ys))
steps=[math.dist((float(a['x']),float(a['y'])),(float(b['x']),float(b['y']))) for a,b in zip(rem,rem[1:])]
jumps=sum(1 for s in steps if s>4.0)
lx=[float(r['x']) for r in loc]; lt=(max(lx)-min(lx)) if lx else 0
print(f"{travel:.0f} {max(steps):.2f} {jumps} {lt:.0f}")
PY
)
set -- $ONLINE
R_TRAVEL=$1; R_MAXSTEP=$2; R_JUMPS=$3; B_TRAVEL=$4

awk "BEGIN{exit !($R_TRAVEL > 200)}"
check "the remote keeper actually moved on the observer" $? "mirrored travel ${R_TRAVEL}px over the run"

[ "$R_JUMPS" = "0" ]
check "no teleporting: every mirrored step < 4px (90px/s = 1.5px/frame)" $? "largest single-frame step ${R_MAXSTEP}px, ${R_JUMPS} steps over 4px"

awk "BEGIN{exit !($B_TRAVEL < 2)}"
check "each instance moves ONLY its own keeper" $? "observer's own keeper_b travelled ${B_TRAVEL}px while idle"

echo
echo "=============================================================="
echo "AC2 — couch: both pads move their own keeper simultaneously;"
echo "      camera keeps both on screen across the test room"
echo "=============================================================="
launch m1_couch --couch-both --world=COUCH1 --scene=room --autowalk "--trace=$OUT/couch.csv" >/dev/null
sleep 33
kill_all

COUCH=$(python3 - "$OUT/couch.csv" <<'PY'
import sys, math
def rows_of(path, *fields):
    import csv
    out = []
    for r in csv.DictReader(open(path)):
        try:
            for f in fields:
                float(r[f])
        except (ValueError, TypeError, KeyError):
            continue   # truncated final row from a killed process
        out.append(r)
    return out
rows=rows_of(sys.argv[1], 'x', 'y', 'zoom', 'cam_x', 'cam_y')
ka=[r for r in rows if r['slot']=='keeper_a']
kb=[r for r in rows if r['slot']=='keeper_b']
n=min(len(ka),len(kb))
ka,kb=ka[:n],kb[:n]
def travel(rs):
    xs=[float(r['x']) for r in rs]; ys=[float(r['y']) for r in rs]
    return (max(xs)-min(xs))+(max(ys)-min(ys))
off=sum(1 for r in rows if r['on_screen']=='0')
zs=[float(r['zoom']) for r in ka]
cx=[float(r['cam_x']) for r in ka]; cy=[float(r['cam_y']) for r in ka]
cam=(max(cx)-min(cx))+(max(cy)-min(cy))
seps=[math.dist((float(a['x']),float(a['y'])),(float(b['x']),float(b['y']))) for a,b in zip(ka,kb)]
# how far apart did they get while BOTH stayed framed
framed=[d for d,a,b in zip(seps,ka,kb) if a['on_screen']=='1' and b['on_screen']=='1']
print(f"{travel(ka):.0f} {travel(kb):.0f} {off} {min(zs):.3f} {max(zs):.3f} {cam:.0f} {max(framed):.0f} {max(seps):.0f}")
PY
)
set -- $COUCH
A_TRAVEL=$1; B_TRAVEL2=$2; OFFSCREEN=$3; ZMIN=$4; ZMAX=$5; CAM_TRAVEL=$6; MAX_FRAMED=$7; MAX_SEP=$8

awk "BEGIN{exit !($A_TRAVEL > 300 && $B_TRAVEL2 > 300)}"
check "both pads drive their own keeper simultaneously" $? "keeper_a travelled ${A_TRAVEL}px, keeper_b ${B_TRAVEL2}px"

[ "$OFFSCREEN" = "0" ]
check "camera keeps both on screen for the whole route" $? "${OFFSCREEN} off-screen samples; camera itself travelled ${CAM_TRAVEL}px across the room"

awk "BEGIN{exit !($ZMIN <= 1.001 && $ZMAX >= 1.499)}"
check "zoom-to-fit uses the full 1.0x-1.5x range" $? "zoom spanned ${ZMIN}x - ${ZMAX}x; widest framed separation ${MAX_FRAMED}px (route peaked at ${MAX_SEP}px)"

echo
echo "=============================================================="
echo "AC3 — gamepad-only: no mouse handler in the player path"
echo "=============================================================="
PLAYER_PATH="$REPO/godot/game/keeper.gd $REPO/godot/game/keeper_camera.gd $REPO/godot/scenes/world.gd $REPO/godot/scenes/boot.gd"
HITS=$(grep -nE "InputEventMouse|InputEventScreenTouch|get_global_mouse_position|get_local_mouse_position|MOUSE_BUTTON" $PLAYER_PATH || true)
[ -z "$HITS" ]
check "no mouse/touch API anywhere in the player path" $? "${HITS:-none found in keeper.gd, keeper_camera.gd, world.gd, boot.gd}"

RAWKEYS=$(grep -nE "Input\.is_key_pressed|Input\.is_joy_button_pressed|Input\.get_joy_axis" $PLAYER_PATH || true)
[ -z "$RAWKEYS" ]
check "input goes through named actions, never raw keys or buttons" $? "${RAWKEYS:-no raw key/button reads}"

echo
echo "=============================================================="
echo "AC4 (standing) — tsc clean; GDScript compiles clean"
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
echo "M1 result: $pass passed, $fail failed   (evidence in $OUT/)"
echo "=============================================================="
[ "$fail" = "0" ]
