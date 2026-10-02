#!/usr/bin/env bash
# Builds Cursebound Farm and runs every offline check.
#   1. rojo build           -> build/game.rbxl (code only)
#   2. lune bake            -> dist/CurseboundFarm.rbxl (code + baked map + lighting)
#   3. lune unit tests      (rules, persistence, combat math, layout)
#   4. lune integration     (boots the real server in an engine shim and plays a session)
#      lune client smoke    (runs the real client scripts and drives every screen)
#   5. luau-lsp analyze     (optional: set LUAU_DEFS to a globalTypes.d.luau path)
# Optional preview renders: PREVIEW=1 scripts/build.sh  (needs node + tools/preview deps)
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build dist
echo "== rojo build"
rojo build default.project.json -o build/game.rbxl
echo "== bake map into place"
lune run tools/lune/bake.luau build/game.rbxl dist/CurseboundFarm.rbxl build/scene.json
echo "== unit tests"
lune run tools/lune/test.luau build/game.rbxl
echo "== server integration playtest"
lune run tools/lune/integration.luau dist/CurseboundFarm.rbxl
echo "== client smoke test"
lune run tools/lune/client_smoke.luau dist/CurseboundFarm.rbxl
if [[ -n "${LUAU_DEFS:-}" ]]; then
	echo "== type analysis"
	rojo sourcemap default.project.json -o sourcemap.json
	luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions="$LUAU_DEFS" src/
fi
if [[ "${PREVIEW:-0}" == "1" ]]; then
	echo "== preview renders"
	(cd tools/preview && npm install --no-audit --no-fund >/dev/null)
	node tools/preview/render.mjs build/scene.json tools/preview/views.json build/preview
fi
echo "Done: dist/CurseboundFarm.rbxl"
