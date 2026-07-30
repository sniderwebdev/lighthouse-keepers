#!/usr/bin/env bash
# build.sh — one command from a checkout to something you can hand somebody.
#
#   tools/build.sh              # both platforms
#   tools/build.sh windows      # just the .exe
#   tools/build.sh macos
#
# Playtests should never need the editor (PLAN.md M8), so this is the path a
# playtest build takes. The server runtime is built too: a client with nothing
# to connect to is not a playtest.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
WHAT="${1:-all}"

echo "==> server runtime"
(cd "$REPO/nakama" && npm install --silent && npx tsc)

# Imports have to be up to date or the export ships stale resources.
echo "==> importing resources"
"$GODOT" --headless --path "$REPO/godot" --import >/dev/null 2>&1 || true

build_one() { # build_one <preset> <output>
  local preset="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  echo "==> $preset"
  "$GODOT" --headless --path "$REPO/godot" --export-release "$preset" "$out"
  ls -lh "$out" | awk '{print "    " $5, $9}'
}

[ "$WHAT" = "all" ] || [ "$WHAT" = "windows" ] && \
  build_one "Windows Desktop" "$REPO/build/windows/LighthouseKeepers.exe"
[ "$WHAT" = "all" ] || [ "$WHAT" = "macos" ] && \
  build_one "macOS" "$REPO/build/macos/LighthouseKeepers.zip"

echo
echo "Built into $REPO/build/. To play:"
echo "  docker compose up -d          # the world has to be somewhere"
echo "  build/windows/LighthouseKeepers.exe --  --couch --world=HARBO"
echo "  (--couch starts with one keeper; the second joins on first input)"
