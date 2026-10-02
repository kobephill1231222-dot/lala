#!/usr/bin/env bash
# Builds JJK Farm and runs every offline check.
#   1. rojo build           -> build/game.rbxl (code only)
#   2. lune bake            -> dist/JJKFarm.rbxl (code + baked map + lighting)
#   3. lune unit tests      (rules, economy, offline progress, persistence)
#   4. lune integration     (boots the real server in an engine shim and plays the whole loop)
#      lune client smoke    (runs the real client scripts and drives every screen and prompt)
#   5. luau-lsp analyze     (optional: set LUAU_DEFS to a globalTypes.d.luau path)
# Optional preview renders: PREVIEW=1 scripts/build.sh  (needs node + tools/preview deps)
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build dist
echo "== rojo build"
rojo build default.project.json -o build/game.rbxl
echo "== bake map into place"
lune run tools/lune/bake.luau build/game.rbxl dist/JJKFarm.rbxl build/scene.json
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
	echo "== preview renders"
	(cd tools/preview && npm install --no-audit --no-fund >/dev/null)
	node tools/preview/render.mjs build/scene.json tools/preview/views.json build/preview
	lune run tools/lune/models.luau build/game.rbxl build/models.json
	node tools/preview/render.mjs build/models.json tools/preview/model_views.json build/preview
fi
echo "Done: dist/JJKFarm.rbxl"
