#!/usr/bin/env bash
# verify_m9.sh — runs the M9 acceptance criteria against a live local stack.
#
#   (cd nakama && npx tsc) && docker compose restart nakama && tools/verify_m9.sh
#
# NOTE: the server runtime is loaded at container start. A tsc build alone does
# NOT reload it, and a world created against the old runtime will not have the
# arrival in it. Restart nakama before running this or AC1 fails for the wrong
# reason.
#
# Scope is the three findings this pass covers: the arrival, the shoal glimmer
# from CONTENT.md's implementation note, and keeper warmth at HIGH tide.
# PLAN.md's third M9 bullet (bottle pacing on phase boundaries) is NOT covered
# here and is not implemented.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
APP=""   # set below, from the zip this run unpacks
OUT="${OUT:-$REPO/.m9-evidence}"
HOST="http://127.0.0.1:7350"

mkdir -p "$OUT"
rm -f "$OUT"/*.log "$OUT"/*.png

# Worlds persist; each run gets its own so leftovers cannot decide the result.
# This matters more here than anywhere else: the arrival is BY DEFINITION only
# applied to a world that has never existed before.
TAG=$(date +%s | tail -c 5)

# The macOS export is a ZIP, so "the built binary" is whatever comes out of it —
# not whatever somebody unzipped by hand into build/macos/app/ at some point in
# the past. Unpacking it here per run is the only way a claim about the built
# game is a claim about the build that was just made.
APP_ZIP="$REPO/build/macos/LighthouseKeepers.zip"
if [ ! -f "$APP_ZIP" ]; then
  echo "no macOS build at $APP_ZIP — run tools/build.sh macos first" >&2
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

launch() {
  local name="$1"; shift
  "$GODOT" --headless --path "$REPO/godot" -- "$@" >"$OUT/$name.log" 2>&1 &
  echo $!
}
kill_all() {
  pkill -f "Godot --headless --path $REPO/godot" 2>/dev/null
  # The exported bundle's binary has a space in its name; matching the repo
  # spelling would silently kill nothing and leave a window on somebody's screen.
  pkill -f "Lighthouse Keepers" 2>/dev/null
  sleep 2
}
trap kill_all EXIT
kill_all

TOKEN=$(curl -s -X POST "$HOST/v2/account/authenticate/device?create=true" \
  -H "Authorization: Basic $(printf 'defaultkey:' | base64)" \
  -H "Content-Type: application/json" \
  -d '{"id":"verify-m9-device-0000"}' | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])')

setflag() { # setflag <world> <flag>
  curl -s -X POST "$HOST/v2/rpc/debug_set_flag" -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "\"{\\\"world_code\\\":\\\"$1\\\",\\\"flag\\\":\\\"$2\\\"}\"" >/dev/null
}

set_tide() { # set_tide <world> <t>
  curl -s -X POST "$HOST/v2/rpc/debug_set_tide" -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "\"{\\\"world_code\\\":\\\"$1\\\",\\\"t\\\":$2}\""
}

## Ask until the CLIENT says it got there, rather than asking once and sleeping.
##
## A single fire-and-forget call races the world: the RPC needs a live match in
## the world index, and the client needs to have entered the beach to hear the
## answer. Sleeping a guessed number of seconds either flakes or is slower than
## it needs to be — and a timed leg is exactly what the Testing law forbids
## everywhere else, so it has no business here either.
wait_for_phase() { # wait_for_phase <world> <t> <phase> <logfile>
  local world="$1" t="$2" want="$3" log="$4" i
  for i in $(seq 1 20); do
    if grep -q "\[beach\] phase=$want" "$log" 2>/dev/null; then return 0; fi
    set_tide "$world" "$t" >>"$OUT/rpc.log" 2>&1
    echo >>"$OUT/rpc.log"
    sleep 1.5
  done
  grep -q "\[beach\] phase=$want" "$log" 2>/dev/null
}

echo "=============================================================="
echo "AC1 — a fresh world is not an empty one: a readable bottle and"
echo "      gatherable crates are there at spawn, and the story is"
echo "      in reach inside 60 seconds"
echo "=============================================================="

ARR=ARR$TAG
launch m9_arrival --slot=keeper_a --world=$ARR --autowalk=read_bottle >/dev/null
sleep 22
kill_all

# The letter is on the sand at spawn rather than waiting on a tide roll.
ONSAND=$(grep -oE "\[bottle\] bottle_01 on the sand" "$OUT/m9_arrival.log" | head -1)
[ -n "$ONSAND" ]
check "Elio's first letter is on the shore when a new world opens" $? \
  "${ONSAND:-bottle_01 was not on the sand at spawn}"

# ...and it is a bottle you can actually open, not scenery.
OPENED=$(grep -oE "\[reader\] opened bottle_01 \([0-9]+ page\(s\)\)" "$OUT/m9_arrival.log" | head -1)
[ -n "$OPENED" ]
check "the letter opens and has pages" $? "${OPENED:-the reader never opened}"

# The AC's number. Measured from the moment the world is joined — the first
# instant a keeper could have moved — to the moment the letter is open.
REACH=$(python3 - "$OUT/m9_arrival.log" <<'PY'
import re, sys
joined = opened = None
for line in open(sys.argv[1]):
    if joined is None and "join ok" in line:
        joined = float(line.split()[0])
    if opened is None and "[reader] opened bottle_01" in line:
        opened = float(line.split()[0])
print("%.2f" % (opened - joined) if joined and opened else "999")
PY
)
awk "BEGIN{exit !($REACH <= 60.0)}"
check "the story is in reach within 60s of spawning" $? "reached it in ${REACH}s"

# The crates: present, gatherable, and they pay out.
CRATES=$(grep -cE "\[node\] arrival_crate_0[12] visible=true" "$OUT/m9_arrival.log" || true)
[ "$CRATES" -ge 2 ]
check "both arrival crates are on the beach at spawn" $? \
  "$CRATES crate visibility announcements"

CR=CRT$TAG
launch m9_crate --slot=keeper_a --world=$CR --autowalk=gather_crate >/dev/null
sleep 14
kill_all
CRATE_PAID=$(grep -ohE "driftwood\":[0-9.]+" "$OUT/m9_crate.log" | tail -1)
[ -n "$CRATE_PAID" ] && [ "${CRATE_PAID#*:}" != "0.0" ]
check "a crate is gatherable and the server pays it out" $? \
  "${CRATE_PAID:-the crate yielded nothing}"

# The crates are what you brought with you. The sea does not restock them.
TAKEN=$(grep -oE "\[node\] arrival_crate_01 visible=false" "$OUT/m9_crate.log" | tail -1)
[ -n "$TAKEN" ]
check "an emptied crate stays empty" $? "${TAKEN:-the crate never went away}"

echo
echo "=============================================================="
echo "AC2 — the shoal glimmer: nothing until the letter says to"
echo "      watch, then three flashes, a pause, three more"
echo "=============================================================="

GLM=GLM$TAG
launch m9_glimmer --slot=keeper_a --world=$GLM >/dev/null
sleep 8
# Before: the water is empty, because nobody has told you to look at it.
BEFORE=$(grep -oE "\[glimmer\] (watching|dark)" "$OUT/m9_glimmer.log" | tail -1)
[ "$BEFORE" = "[glimmer] dark" ]
check "before bottle_2 is read there is nothing out there" $? \
  "${BEFORE:-the glimmer never reported}"

# Reading bottle_2 is what arms it. A fresh world is at LOW, which is the only
# tide it speaks on.
setflag $GLM read_bottle_02
sleep 20
kill_all

ARMED=$(grep -oE "\[glimmer\] watching \(flag=set phase=LOW\)" "$OUT/m9_glimmer.log" | tail -1)
[ -n "$ARMED" ]
check "reading bottle_2 puts a light past the shoal at low tide" $? \
  "${ARMED:-the glimmer never armed}"

# The shape of the signal, as bottle_2 describes it: three, a pause, three.
SHAPE=$(python3 - "$OUT/m9_glimmer.log" <<'PY'
import re, sys
times = [float(l.split()[0]) for l in open(sys.argv[1]) if "[glimmer] flash" in l]
if len(times) < 6:
    print("only %d flashes" % len(times)); raise SystemExit
gaps = [times[i + 1] - times[i] for i in range(5)]
# Gap 3 (between the third flash and the fourth) is the held breath, and must be
# clearly longer than the gaps inside each group of three.
inside = gaps[:2] + gaps[3:]
print("OK" if gaps[2] > max(inside) * 1.5 else "no pause: gaps=%s" % [round(g, 2) for g in gaps])
PY
)
[ "$SHAPE" = "OK" ]
check "three flashes, a held breath, three more" $? \
  "$([ "$SHAPE" = "OK" ] && echo "the pause is clearly longer than the gaps inside each three" || echo "$SHAPE")"

echo
echo "=============================================================="
echo "AC3 — the warmth law holds at HIGH tide: keepers stay warm and"
echo "      tellable-apart when the sky ramp is at its darkest"
echo "=============================================================="

# Windowed, not headless: this AC is about pixels, and headless has no
# framebuffer to photograph.
#
# ONE launch, not two. The numbers the code believes and the photograph of what
# it drew come from the same instance at the same high water — so the assertions
# below cannot disagree with each other about which run they are describing, and
# there is only one window to fight macOS over.
WRM=WRM$TAG
"$APP" -- --slot=keeper_a --world=$WRM --couch-both \
  --shot="$OUT/high_tide.png" --shot-at=45 >"$OUT/m9_warm_world.log" 2>&1 &
wait_for_phase $WRM 0.6 HIGH "$OUT/m9_warm_world.log"   # 0.6 is squarely inside HIGH
# The shutter is on a timer inside the game and the run quits itself once it
# fires; --shot-at is generous so the water is always where we want it first.
for i in $(seq 1 50); do [ -f "$OUT/high_tide.png" ] && break; sleep 1.5; done
kill_all

PHASE=$(grep -oE "\[beach\] phase=[A-Z]+" "$OUT/m9_warm_world.log" | tail -1)
[ "$PHASE" = "[beach] phase=HIGH" ]
check "the world really was at high water" $? "${PHASE:-no phase was reported}"

# The half that already existed (AMBIENT_RESISTANCE) was never verified — STATUS
# called it UNVERIFIED. These are its numbers, out of the running game.
LIFT=$(grep -oE "\[warmth\] keeper_a ambient_v=[0-9.]+ lift=[0-9.,]+ halo_darkness=[0-9.]+" \
  "$OUT/m9_warm_world.log" | tail -1)
LIFT_R=$(echo "$LIFT" | sed -nE 's/.*lift=([0-9.]+),.*/\1/p')
awk "BEGIN{exit !(${LIFT_R:-0} > 1.0)}"
check "keepers are lifted OUT of the ambient tint, not multiplied by it" $? \
  "${LIFT:-no warmth line was printed}"

HALO=$(echo "$LIFT" | sed -nE 's/.*halo_darkness=([0-9.]+).*/\1/p')
awk "BEGIN{exit !(${HALO:-0} > 0.0)}"
check "the lantern halo is lit at high water" $? "halo darkness ${HALO:-none} of 1.0"

# And the photograph — the same instance, the same high water.
[ -f "$OUT/high_tide.png" ]
check "a HIGH-tide frame was captured" $? "$OUT/high_tide.png"

WARMTH=$(python3 - "$OUT/high_tide.png" <<'PY'
import sys
from PIL import Image
import numpy as np

img = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(float)
lum = 0.2126 * img[:, :, 0] + 0.7152 * img[:, :, 1] + 0.0722 * img[:, :, 2]
# Warmth = how much redder than bluer a pixel is. The palette's warm ramp is the
# only place this goes meaningfully positive (DESIGN §6: warm is reserved).
warm = img[:, :, 0] - img[:, :, 2]

# The keepers are the warm pixels; the beach is everything else.
mask = warm > 20
if mask.sum() < 20:
    print("FAIL no warm pixels at all (%d)" % mask.sum()); raise SystemExit
print("OK warm_px=%d warm_lum=%.1f world_lum=%.1f margin=%.1f" % (
    mask.sum(), lum[mask].mean(), lum[~mask].mean(), lum[mask].mean() - lum[~mask].mean()))
PY
)
echo "$WARMTH" | grep -q "^OK"
check "warm pixels exist at high water and are brighter than the world" $? "$WARMTH"

MARGIN=$(echo "$WARMTH" | sed -nE 's/.*margin=(-?[0-9.]+).*/\1/p')
awk "BEGIN{exit !(${MARGIN:-0} > 10.0)}"
check "you can find the humans by finding the warmth" $? \
  "keepers read ${MARGIN:-no} luminance above the shore around them"

echo
echo "=============================================================="
echo "AC4 — story that is hungry arrives on a phase, not a cycle"
echo "=============================================================="

# The trap this has to avoid: making a bottle eligible with an RPC that ALSO
# rolls. debug_set_tide rolls when it is given a cycle, so the world is left to
# reach cycle 1 on its own with a short cycle, and only THEN is chapter 2
# unlocked — mid-cycle, with the next cycle boundary a long way off.
PAC=PAC$TAG
set_cycle_seconds() { # set_cycle_seconds <world> <seconds>
  curl -s -X POST "$HOST/v2/rpc/debug_set_cycle_seconds" -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "\"{\\\"world_code\\\":\\\"$1\\\",\\\"seconds\\\":$2}\"" >>"$OUT/rpc.log" 2>&1
  echo >>"$OUT/rpc.log"
}

launch m9_pacing --slot=keeper_a --world=$PAC >/dev/null
sleep 6
set_cycle_seconds $PAC 40      # a phase every ten seconds
# Wait for the world to turn a cycle by itself. bottle_02 is NOT eligible yet —
# read_bottle_01 is unset — so this boundary spawns nothing, which is the point:
# it proves what follows did not come from a cycle.
for i in $(seq 1 30); do
  grep -q "cycle=1" "$OUT/m9_pacing.log" && break
  sleep 2
done

CYCLE_AT_UNLOCK=$(grep -oE "tide=[A-Z]+ *t=[0-9.]+ *cycle=[0-9]+" "$OUT/m9_pacing.log" \
  | tail -1 | grep -oE "cycle=[0-9]+")
setflag $PAC read_bottle_01    # chapter 2 becomes eligible, mid-cycle
sleep 14                       # longer than one phase, far shorter than one cycle
kill_all

ARRIVED_02=$(grep -oE "\[bottle\] bottle_02 on the sand" "$OUT/m9_pacing.log" | head -1)
[ -n "$ARRIVED_02" ]
check "an unlocked chapter washes in without waiting for the cycle" $? \
  "${ARRIVED_02:-bottle_02 never arrived}"

# The assertion that makes this about PHASES: the cycle counter must not have
# moved between unlocking the chapter and the letter landing. If it had, this
# would be the old cycle-boundary path passing under a new name.
CYCLE_AT_ARRIVAL=$(python3 - "$OUT/m9_pacing.log" <<'PY'
import re, sys
cycle = None
for line in open(sys.argv[1]):
    m = re.search(r"cycle=(\d+)", line)
    if m:
        cycle = m.group(1)
    if "[bottle] bottle_02 on the sand" in line:
        print("cycle=%s" % cycle); break
else:
    print("cycle=?")
PY
)
[ -n "$CYCLE_AT_UNLOCK" ] && [ "$CYCLE_AT_UNLOCK" = "$CYCLE_AT_ARRIVAL" ]
check "it arrived inside the same cycle it was unlocked in" $? \
  "unlocked at ${CYCLE_AT_UNLOCK:-?}, arrived at ${CYCLE_AT_ARRIVAL:-?}"

echo
echo "=============================================================="
echo "Standing checks"
echo "=============================================================="
(cd "$REPO/nakama" && npx tsc >"$OUT/tsc.log" 2>&1)
[ ! -s "$OUT/tsc.log" ]
check "tsc compiles clean" $? "$(wc -l <"$OUT/tsc.log" | tr -d ' ') lines of output"

"$GODOT" --headless --path "$REPO/godot" --editor --quit >"$OUT/gdcheck.log" 2>&1
! grep -qiE "SCRIPT ERROR|Parse Error|Compile Error" "$OUT/gdcheck.log"
check "GDScript compiles clean (headless editor pass)" $? \
  "exit=$?, no script/parse/compile errors"

echo
echo "=============================================================="
echo "M9 result: $pass passed, $fail failed   (evidence in $OUT/)"
echo "=============================================================="
[ "$fail" = "0" ]
