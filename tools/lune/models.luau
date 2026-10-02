--!nocheck
-- Builds every unit and curse in a line-up and exports it for the preview renderer.
-- Usage: lune run tools/lune/models.luau build/game.rbxl build/models.json
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local Sandbox = require("./lib/Sandbox")
local Export = require("./lib/Export")

local game = Sandbox.loadPlace(process.args[1] or "build/game.rbxl")
local sb = Sandbox.new(game)
local CharacterModels = sb.requirePath("ReplicatedStorage/Shared/Visuals/CharacterModels")
local CurseModels = sb.requirePath("ReplicatedStorage/Shared/Visuals/CurseModels")
local Characters = sb.requirePath("ReplicatedStorage/Shared/Config/Characters")
local Enemies = sb.requirePath("ReplicatedStorage/Shared/Config/Enemies")
local CFrame, Vector3 = Sandbox.CFrame, roblox.Vector3

local folder = roblox.Instance.new("Folder")
local count = 0
for i, def in Characters.List do
	-- One row, 8 studs apart, facing the camera (+Z).
	local x = (i - 1) * 8
	local cf = CFrame.lookAt(Vector3.new(x, 0, 0), Vector3.new(x, 0, 10))
	local model = CharacterModels.build(def.id, cf, { aura = true })
	model.Parent = folder
	count += #model:GetChildren()
end
for i, def in Enemies.List do
	local model = CurseModels.build(def.id, Vector3.new(i * 14 - 14, 0, 30))
	model.Parent = folder
end
local out = Export.collect(folder)
print("characters built:", #Characters.List, "parts:", #out.parts)
fs.writeFile(process.args[2] or "build/models.json", serde.encode("json", out))
