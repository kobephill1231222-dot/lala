--!nocheck
-- Usage: rojo build default.project.json -o build/game.rbxl && lune run tools/lune/test.luau
local process = require("@lune/process")
local Sandbox = require("./lib/Sandbox")
local TestKit = require("./lib/TestKit")

local placePath = process.args[1] or "build/game.rbxl"
local game = Sandbox.loadPlace(placePath)

local specs = {
	require("../../tests/rules.spec"),
	require("../../tests/data.spec"),
	require("../../tests/combat.spec"),
}

for _, spec in specs do
	-- Fresh sandbox per spec so module state never leaks between suites.
	spec({ sandbox = Sandbox.new(game), kit = TestKit, game = game, Sandbox = Sandbox })
end

if not TestKit.report() then
	process.exit(1)
end
