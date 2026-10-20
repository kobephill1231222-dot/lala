#!/usr/bin/env bash
# Builds JJK Farm and runs every offline check.
#   1. rojo build           -> build/game.rbxl (code only)
#   2. lune bake            -> dist/JJKFarm.rbxl (code + the invisible physics world)
#   3. lune unit tests      (rules, economy, offline progress, persistence, pixel art)
#   4. lune integration     (boots the real server in an engine shim and plays the whole loop)
#      lune client smoke    (runs the real pixel client and drives every screen and action)
#   5. luau-lsp analyze     (optional: set LUAU_DEFS to a globalTypes.d.luau path)
# Optional screenshots of the pixel client: PREVIEW=1 scripts/build.sh  (needs node)
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build dist
echo "== rojo build"
rojo build default.project.json -o build/game.rbxl
echo "== bake physics world into place"
lune run tools/lune/bake.luau build/game.rbxl dist/JJKFarm.rbxl
echo "== unit tests"
lune run tools/lune/test.luau build/game.rbxl
echo "== economy pacing simulation (2 h bot)"
lune run tools/lune/simulate.luau build/game.rbxl 120 | tail -n 12
echo "== server integration playtest"
lune run tools/lune/integration.luau dist/JJKFarm.rbxl
echo "== client smoke test"
lune run tools/lune/client_smoke.luau dist/JJKFarm.rbxl
if [[ -n "${LUAU_DEFS:-}" ]]; then
	echo "== type analysis"
	rojo sourcemap default.project.json -o sourcemap.json
	luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions="$LUAU_DEFS" src/
fi
if [[ "${PREVIEW:-0}" == "1" ]]; then
	echo "== screenshots"
	lune run tools/lune/screenshots.luau dist/JJKFarm.rbxl build/preview
fi
echo "Done: dist/JJKFarm.rbxl"
