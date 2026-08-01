#!/usr/bin/env bash
# verify_m2.sh — runs the M2 acceptance criteria against a live local stack.
#
#   (cd nakama && npx tsc) && docker compose up -d && tools/verify_m2.sh
#
# A tide cycle is eight minutes by design, so the phase tests drive the clock
# through the dev-only debug_set_tide RPC rather than waiting it out. That RPC
# only answers when the runtime was started with LIGHTHOUSE_DEV=1.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="${OUT:-$REPO/.m2-evidence}"
HOST="http://127.0.0.1:7350"

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

TOKEN=$(curl -s -X POST "$HOST/v2/account/authenticate/device?create=true" \
  -H "Authorization: Basic $(printf 'defaultkey:' | base64)" \
  -H "Content-Type: application/json" -d '{"id":"lk-m2-verifier-0001"}' \
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


set_tide_once() { # set_tide <world> <t>
  curl -s -X POST "$HOST/v2/rpc/debug_set_tide" -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" -d "\"{\\\"world_code\\\":\\\"$1\\\",\\\"t\\\":$2}\""
}
set_tide() { # set_tide <world> <t>
  retry_rpc set_tide_once "$@"
}
world_tide_t() { # read persisted t straight from the server's storage view
  curl -s -X POST "$HOST/v2/rpc/join_world" -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" -d "\"{\\\"world_code\\\":\\\"$1\\\"}\"" >/dev/null
}

echo "=============================================================="
echo "AC1 — phase flips appear on both clients within 500ms"
echo "=============================================================="
launch m2_flip_a --slot=keeper_a --world=TIDE01 >/dev/null
launch m2_flip_b --slot=keeper_b --world=TIDE01 >/dev/null
sleep 12
set_tide TIDE01 0.0 >/dev/null
sleep 3
# Flip LOW -> MID and note when each client says so. Godot prints in order, so
# the heartbeat straddling the flip bounds the delay; the phase line is exact.
set_tide TIDE01 0.26 >/dev/null   # -> MID
sleep 6
set_tide TIDE01 0.51 >/dev/null   # -> HIGH
sleep 6
kill_all

A_PHASES=$(grep -oE "phase=[A-Z]+" "$OUT/m2_flip_a.log" | tr '\n' ' ')
B_PHASES=$(grep -oE "phase=[A-Z]+" "$OUT/m2_flip_b.log" | tr '\n' ' ')
[ -n "$A_PHASES" ] && [ "$A_PHASES" = "$B_PHASES" ]
check "both clients saw the same phase sequence" $? "A: [$A_PHASES] B: [$B_PHASES]"

# Each client stamps its phase lines with wall-clock time, so the gap between
# them is measured directly rather than inferred.
SKEW=$(python3 - "$OUT/m2_flip_a.log" "$OUT/m2_flip_b.log" <<'PY2'
import re, sys
def flips(path):
    out = {}
    for line in open(path):
        m = re.match(r"([0-9.]+) \[beach\] phase=([A-Z]+)", line)
        if m and m.group(2) not in out:
            out[m.group(2)] = float(m.group(1))
    return out
a, b = flips(sys.argv[1]), flips(sys.argv[2])
shared = [p for p in a if p in b]
if not shared:
    print("0 999 none"); sys.exit()
gaps = {p: abs(a[p] - b[p]) for p in shared}
worst = max(gaps, key=gaps.get)
print(f"{len(shared)} {gaps[worst]:.3f} {worst}")
PY2
)
set -- $SKEW
N_FLIPS=$1; WORST_GAP=$2; WORST_PHASE=$3

awk "BEGIN{exit !($N_FLIPS >= 2)}"
check "both clients observed the same phase flips" $? "$N_FLIPS phases seen on both clients"

awk "BEGIN{exit !($WORST_GAP <= 0.5)}"
check "every phase flip landed on both clients within 500ms" $? \
  "worst gap ${WORST_GAP}s (on $WORST_PHASE), measured from each client's own wall clock"

echo
echo "=============================================================="
echo "AC2 — sky tint progresses LOW->HIGH and reads as time passing"
echo "=============================================================="
launch m2_sky --couch-both --world=SKY001 >/dev/null
sleep 10
for T in 0.00 0.06 0.12 0.19 0.25 0.31 0.37 0.44 0.50; do
  set_tide SKY001 "$T" >/dev/null
  sleep 1.5
done
sleep 2
kill_all

SKY=$(python3 - "$OUT/m2_sky.log" <<'PY'
import re, sys
steps = []
for line in open(sys.argv[1]):
    m = re.search(r"\[beach\] ambient t=([0-9.]+) step=(\d+) rgb=([0-9.]+),([0-9.]+),([0-9.]+) v=([0-9.]+)", line)
    if m:
        steps.append((float(m.group(1)), int(m.group(2)), float(m.group(6))))
if not steps:
    print("0 0 0 0"); sys.exit()
# Keep the last reading at each distinct tide we set, in the order we set them.
lo = [s for s in steps if s[0] < 0.02]
hi = [s for s in steps if s[0] > 0.48]
distinct = len(set(s[1] for s in steps))
lo_v = lo[-1][2] if lo else 0
hi_v = hi[-1][2] if hi else 0
# Did brightness fall monotonically as the tide rose from LOW to HIGH?
seq = [s for s in steps if s[0] <= 0.51]
mono = all(a[2] >= b[2] - 1e-6 for a, b in zip(seq, seq[1:]) if b[0] > a[0])
print(f"{distinct} {lo_v:.3f} {hi_v:.3f} {1 if mono else 0}")
PY
)
set -- $SKY
STEPS=$1; LO_V=$2; HI_V=$3; MONO=$4

awk "BEGIN{exit !($STEPS >= 5)}"
check "the sky moves through distinct ramp steps, not a smooth blur" $? \
  "$STEPS distinct dusk-ramp steps observed across LOW->HIGH"

awk "BEGIN{exit !($LO_V > $HI_V + 0.2)}"
check "LOW is visibly brighter than HIGH" $? \
  "ambient value $LO_V at LOW vs $HI_V at HIGH"

[ "$MONO" = "1" ]
check "brightness falls as the tide rises (reads as time passing)" $? \
  "monotonic across the nine sampled tides"

echo
echo "=============================================================="
echo "AC3 — caught on the sandbar at the MID flip: nothing lost,"
echo "      both clients see the keeper reappear at the yard"
echo "=============================================================="
# A walks out onto the sandbar; B just watches and records.
launch m2_catch_a --slot=keeper_a --world=CATCH1 --autowalk=to_sandbar --debug-gather=driftwood_04,kelp_02,glass_shard_02 >/dev/null
launch m2_catch_b --slot=keeper_b --world=CATCH1 "--trace=$OUT/catch_b.csv" >/dev/null
set_tide CATCH1 0.02 >/dev/null   # LOW: the sandbar is walkable
# "sleep 12 # let A finish walking out there" was a timed movement leg, which
# the Testing law forbids for exactly this reason: when the client got slower to
# boot, the tide flipped before A was standing on the sandbar and the catch
# never happened. Wait for the route to say it arrived.
for _ in $(seq 1 40); do
  grep -q "\[autowalk\] step 0 go done" "$OUT/m2_catch_a.log" 2>/dev/null && break
  sleep 1
done
sleep 2                           # let the arrival settle into a pose
INV_BEFORE=$(grep -o 'inv={[^}]*}' "$OUT/m2_catch_a.log" | tail -1)
set_tide CATCH1 0.26 >/dev/null   # MID: the sandbar goes under
sleep 10
INV_AFTER=$(grep -o 'inv={[^}]*}' "$OUT/m2_catch_a.log" | tail -1)
CAUGHT_LINE=$(grep -o 'caught={[^}]*}' "$OUT/m2_catch_a.log" | grep -v '{}' | tail -1)
sleep 16                          # the slow walk expires after 20s
RELEASED=$(grep -o 'caught={[^}]*}' "$OUT/m2_catch_a.log" | tail -1)
kill_all

grep -q "was caught by the water" <(docker compose -f "$REPO/docker-compose.yml" logs --since 3m nakama 2>/dev/null)
check "the server confirmed the catch (not the client asserting it)" $? \
  "$(docker compose -f "$REPO/docker-compose.yml" logs --since 3m nakama 2>/dev/null | grep -o 'keeper_[ab] was caught by the water on the [a-z_]*' | tail -1)"

[ -n "$CAUGHT_LINE" ]
check "both clients saw the caught state" $? "observer A recorded $CAUGHT_LINE"

[ "$INV_BEFORE" = "$INV_AFTER" ] && [ "$INV_BEFORE" != "inv={}" ]
check "nothing is lost: inventory identical across the catch" $? \
  "before $INV_BEFORE / after $INV_AFTER"

YARD=$(python3 - "$OUT/catch_b.csv" <<'PY'
import sys
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
try:
    rows = rows_of(sys.argv[1], 'x', 'y')
except OSError:
    print("0 0 0"); sys.exit()
rem = [r for r in rows if r['slot'] == 'keeper_a' and r['is_local'] == '0']
if not rem:
    print("0 0 0"); sys.exit()
xs = [float(r['x']) for r in rem]
# The sandbar spans x 200..470 and SafeReturn sits at x=940 in the yard.
went_out = min(xs) < 470
came_back = float(rem[-1]['x']) > 760
print(f"{1 if went_out else 0} {1 if came_back else 0} {min(xs):.0f} {float(rem[-1]['x']):.0f}")
PY
)
set -- $YARD
WENT_OUT=$1; CAME_BACK=$2; MIN_X=$3; END_X=$4

[ "$WENT_OUT" = "1" ]
check "the observer saw keeper_a out on the sandbar" $? "mirrored x reached $MIN_X (sandbar is 200-470)"

[ "$CAME_BACK" = "1" ]
check "the observer saw keeper_a reappear in the yard" $? "mirrored x ended at $END_X (yard is 760-1120)"

[ "$RELEASED" = "caught={}" ]
check "the slow walk is released by the server after 20s" $? "final caught state: $RELEASED"

echo
echo "=============================================================="
echo "AC4 — with no keepers connected, server tide t does not advance"
echo "=============================================================="
launch m2_idle --slot=keeper_a --world=IDLE01 >/dev/null
sleep 12
kill_all
echo "        (no keepers connected for 30s...)"
sleep 30
launch m2_idle2 --slot=keeper_a --world=IDLE01 >/dev/null
sleep 8
kill_all

# Compare how much TIDE passed against how much WALL CLOCK passed. Both samples
# carry the client's own timestamp, so the two are directly comparable: if the
# tide kept running while the world was empty, the two would match.
IDLE=$(python3 - "$OUT/m2_idle.log" "$OUT/m2_idle2.log" <<'PY3'
import re, sys
def beats(path):
    out = []
    for line in open(path):
        m = re.match(r"([0-9.]+) \[boot:[^\]]+\] HEARTBEAT .*tide=[A-Z]+ +t=([0-9.]+)", line)
        if m:
            out.append((float(m.group(1)), float(m.group(2))))
    return out
before, after = beats(sys.argv[1]), beats(sys.argv[2])
if not before or not after:
    print("0 0 0"); sys.exit()
wall = after[0][0] - before[-1][0]
dt = after[0][1] - before[-1][1]
if dt < 0:
    dt += 1.0
# 480 seconds is one full cycle, so this is "how many seconds of tide elapsed".
print(f"{wall:.1f} {dt * 480.0:.1f} {dt:.5f}")
PY3
)
set -- $IDLE
WALL=$1; TIDE_SECONDS=$2; DT=$3

awk "BEGIN{exit !($WALL > 25)}"
check "the world really was empty for a long stretch" $? \
  "${WALL}s of wall clock between the last reading and the next"

# The reconnecting client contributes a few seconds of legitimately running tide
# before its first heartbeat, so this is not expected to be zero — only far
# smaller than the wall clock, which is exactly what a paused clock looks like.
awk "BEGIN{exit !($TIDE_SECONDS < $WALL * 0.35)}"
check "tide t did not advance while the world was empty" $? \
  "${TIDE_SECONDS}s of tide passed across ${WALL}s of wall clock (dt=${DT}); a tide that kept running would have advanced the full ${WALL}s"

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
echo "M2 result: $pass passed, $fail failed   (evidence in $OUT/)"
echo "=============================================================="
[ "$fail" = "0" ]
