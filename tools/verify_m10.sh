#!/usr/bin/env bash
# verify_m10.sh — runs the M10 acceptance criteria against a live local stack.
#
#   (cd nakama && npx tsc) && docker compose up -d && tools/verify_m10.sh
#
# Both tracks. The audio AC is about whether the right thing plays at the right
# moment, which is observable headless: the mixer says out loud what it does, so
# a run without a speaker still proves the wiring. What it CANNOT prove is
# whether any of it sounds good — that is the author's ear and CREDITS.md says
# so plainly.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="${OUT:-$REPO/.m10-evidence}"
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
  -H "Content-Type: application/json" \
  -d '{"id":"verify-m10-device-000"}' | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])')

rpc_log() { cat >>"$OUT/rpc.log"; echo >>"$OUT/rpc.log"; }
set_tide_once() { # <world> <t>
  curl -s -X POST "$HOST/v2/rpc/debug_set_tide" -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "\"{\\\"world_code\\\":\\\"$1\\\",\\\"t\\\":$2}\""
}
## Ask until the world answers, never sleep a guess (see verify_m8.sh).
wait_for_bed() { # <world> <t> <bed> <log>
  local world="$1" t="$2" want="$3" log="$4" i
  for i in $(seq 1 20); do
    grep -q "\[audio\] bed -> $want" "$log" 2>/dev/null && return 0
    set_tide_once "$world" "$t" | rpc_log
    sleep 1.5
  done
  grep -q "\[audio\] bed -> $want" "$log" 2>/dev/null
}

echo "=============================================================="
echo "AC1 — ambience crossfades track phase flips, on both clients"
echo "=============================================================="

AMB=AMB$TAG
launch m10_amb_a --slot=keeper_a --world=$AMB >/dev/null
launch m10_amb_b --slot=keeper_b --world=$AMB >/dev/null
sleep 8

# A fresh world is at LOW, which is the open shore.
LOW_A=$(grep -oE "\[audio\] bed -> sea \(phase=LOW room=beach\)" "$OUT/m10_amb_a.log" | head -1)
[ -n "$LOW_A" ]
check "low water opens on the sea bed" $? "${LOW_A:-no bed was chosen}"

# Push it to high water and both clients should hand over to wind.
wait_for_bed $AMB 0.6 wind "$OUT/m10_amb_a.log"
sleep 3
kill_all

WIND_A=$(grep -oE "\[audio\] bed -> wind" "$OUT/m10_amb_a.log" | tail -1)
WIND_B=$(grep -oE "\[audio\] bed -> wind" "$OUT/m10_amb_b.log" | tail -1)
[ -n "$WIND_A" ] && [ -n "$WIND_B" ]
check "the phase flip moved the bed on BOTH clients" $? \
  "A: ${WIND_A:-nothing} | B: ${WIND_B:-nothing}"

# The bed is chosen by the world's state, not by a timer, so it must not thrash.
FLIPS=$(grep -c "\[audio\] bed ->" "$OUT/m10_amb_a.log" || true)
[ "$FLIPS" -le 4 ]
check "the bed changes when the world does, and not otherwise" $? \
  "$FLIPS bed changes across the run (a timer would give many more)"

echo
echo "=============================================================="
echo "AC2 — the one-shots fire on their events, in both play modes"
echo "=============================================================="

# Online: one client, one slot, a real gather.
SFX=SFX$TAG
launch m10_sfx_online --slot=keeper_a --world=$SFX --autowalk=gather_once >/dev/null
sleep 16
kill_all
GATHER=$(grep -oE "\[audio\] sfx gather" "$OUT/m10_sfx_online.log" | head -1)
[ -n "$GATHER" ]
check "gather sounds when a node is actually taken (online)" $? \
  "${GATHER:-no gather sfx}"

# Couch: one instance, both slots, the crafting wheel — which also exercises the
# wheel tick, a sound with no signal of its own.
CCH=CCH$TAG
launch m10_sfx_couch --slot=keeper_a --world=$CCH --couch-both --autowalk=craft_kelp_tea >/dev/null
sleep 30
kill_all
CRAFT=$(grep -oE "\[audio\] sfx craft" "$OUT/m10_sfx_couch.log" | head -1)
[ -n "$CRAFT" ]
check "craft sounds when the wheel crafts (couch)" $? "${CRAFT:-no craft sfx}"

TICK=$(grep -c "\[audio\] sfx radial_tick" "$OUT/m10_sfx_couch.log" || true)
[ "$TICK" -ge 1 ]
check "the wheel ticks as the thumb crosses a slot" $? "$TICK ticks"

# Every one-shot the manifest promises must exist as a file, or a slot is silent
# and nobody finds out until the moment it was supposed to play.
MISSING=""
for s in gather craft place milestone bottle_open page_turn radial_tick tandem_ready beam caught; do
  [ -f "$REPO/godot/assets/audio/sfx/$s.wav" ] || MISSING="$MISSING $s"
done
[ -z "$MISSING" ]
check "all ten one-shots exist on disk" $? "${MISSING:-all present}"

echo
echo "=============================================================="
echo "AC3 — the sliders exist, move, and persist"
echo "=============================================================="

VOL=VOL$TAG
launch m10_vol --slot=keeper_a --world=$VOL --audio-selftest >/dev/null
sleep 14
kill_all
TURNED=$(grep -cE "\[audio\] bus [A-Za-z]+ = " "$OUT/m10_vol.log" || true)
[ "$TURNED" -ge 4 ]
check "all four buses can be turned from a pad" $? "$TURNED bus changes"

launch m10_vol2 --slot=keeper_a --world=$VOL >/dev/null
sleep 7
kill_all
RELOADED=$(grep -oE "\[audio\] loaded: .*" "$OUT/m10_vol2.log" | tail -1)
[ -n "$RELOADED" ]
check "the levels survived relaunch" $? "${RELOADED:-nothing was loaded}"

# Controller-first law: a slider you have to drag is a slider a pad cannot use.
# Comments stripped first: the file EXPLAINS why it has no HSlider, and a check
# that cannot tell an explanation from a use would have this file fail for
# documenting itself.
HITS=$(grep -vE "^[[:space:]]*#" "$REPO/godot/ui/audio_settings.gd" \
  | grep -nE "InputEventMouse|get_global_mouse_position|MOUSE_BUTTON|HSlider|VSlider" || true)
[ -z "$HITS" ]
check "no mouse and no drag-slider in the settings panel" $? "${HITS:-none}"

echo
echo "=============================================================="
echo "AC4 — the keeper sheets: silhouette and palette"
echo "=============================================================="
python3 "$REPO/tools/check_art.py" >"$OUT/art.log" 2>&1
ART_RC=$?
sed -n '4,$p' "$OUT/art.log" | grep -E "PASS|FAIL" | sed 's/^/  /' | head -20
ART_LINE=$(grep -oE "art result: .*" "$OUT/art.log")
[ "$ART_RC" = "0" ]
check "tools/check_art.py passes" $? "$ART_LINE"

# The manifest has to describe the repo as it is, not as it was.
python3 "$REPO/tools/gen_asset_manifest.py" >"$OUT/manifest.log" 2>&1
git -C "$REPO" diff --quiet -- ASSET_MANIFEST.md
check "ASSET_MANIFEST.md is up to date with the repo" $? \
  "$(grep -oE '[0-9]+ keeper sheets.*' "$OUT/manifest.log" || echo 'regenerated')"

echo
echo "=============================================================="
echo "Standing checks"
echo "=============================================================="
(cd "$REPO/nakama" && npx tsc >"$OUT/tsc.log" 2>&1)
[ ! -s "$OUT/tsc.log" ]
check "tsc compiles clean" $? "$(wc -l <"$OUT/tsc.log" | tr -d ' ') lines of output"

"$GODOT" --headless --path "$REPO/godot" --editor --quit >"$OUT/gdcheck.log" 2>&1
! grep -qiE "SCRIPT ERROR|Parse Error|Compile Error" "$OUT/gdcheck.log"
check "GDScript compiles clean (headless editor pass)" $? "no script/parse/compile errors"

echo
echo "=============================================================="
echo "M10 result: $pass passed, $fail failed   (evidence in $OUT/)"
echo "=============================================================="
[ "$fail" = "0" ]
