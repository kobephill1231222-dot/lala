#!/usr/bin/env bash
# Builds JJK Farm and runs every offline check.
#   1. rojo build           -> build/game.rbxl (code only)
#   2. lune bake            -> dist/JJKFarm.rbxl (code + baked map + lighting)
#   3. lune unit tests      (rules, economy, offline progress, persistence)
#   4. lune integration     (boots the real server in an engine shim and plays the whole loop)
#      lune client smoke    (runs the real client scripts and drives every screen and prompt)
#   5. prototype            -> dist/Prototype.rbxl (training post, docs/NEXT_STEPS_PROPOSAL.md)
#      lune prototype tests (schedule, rig, technique, real server and client scripts)
#   6. luau-lsp analyze     (optional: set LUAU_DEFS to a globalTypes.d.luau path)
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
echo "== training-post prototype"
rojo build prototype.project.json -o build/prototype.rbxl
lune run tools/lune/prototype_bake.luau build/prototype.rbxl dist/Prototype.rbxl build/prototype_scene.json
lune run tools/lune/prototype_test.luau dist/Prototype.rbxl
if [[ -n "${LUAU_DEFS:-}" ]]; then
	echo "== type analysis"
	rojo sourcemap default.project.json -o sourcemap.json
	luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions="$LUAU_DEFS" \
		src/server src/client src/shared
	rojo sourcemap prototype.project.json -o sourcemap.json
	luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions="$LUAU_DEFS" src/prototype
fi
if [[ "${PREVIEW:-0}" == "1" ]]; then
	echo "== preview renders"
	(cd tools/preview && npm install --no-audit --no-fund >/dev/null)
	node tools/preview/render.mjs build/scene.json tools/preview/views.json build/preview
	lune run tools/lune/models.luau build/game.rbxl build/models.json
	node tools/preview/render.mjs build/models.json tools/preview/model_views.json build/preview
	node tools/preview/render.mjs build/scene.json tools/preview/topdown_views.json build/preview
	node tools/preview/render.mjs build/prototype_scene.json tools/preview/prototype_views.json build/preview
	node tools/preview/render.mjs build/prototype_scene.json tools/preview/prototype_topdown_views.json build/preview
	lune run tools/lune/prototype_frames.luau dist/Prototype.rbxl build/strike 20
	for scene in build/strike/*.json; do
		[[ "$scene" == */frames.json ]] && continue
		node tools/preview/render.mjs "$scene" tools/preview/strike_view.json "build/strike_png/$(basename "$scene" .json)" 960 540
		node tools/preview/render.mjs "$scene" tools/preview/strike_topdown_view.json "build/strike_td/$(basename "$scene" .json)" 960 540
	done
fi
echo "Done: dist/JJKFarm.rbxl and dist/Prototype.rbxl"
