--!nocheck
-- Builds every Sorcerer (farm scale) and every Crate in a line-up, with a 5.2-stud avatar
-- stand-in for scale, and exports it for the preview renderer.
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
local CrateModels = sb.requirePath("ReplicatedStorage/Shared/Visuals/CrateModels")
local PartKit = sb.requirePath("ReplicatedStorage/Shared/Visuals/PartKit")
local Sorcerers = sb.requirePath("ReplicatedStorage/Shared/Config/Sorcerers")
local Crates = sb.requirePath("ReplicatedStorage/Shared/Config/Crates")
local CFrame, Vector3 = Sandbox.CFrame, roblox.Vector3

local folder = roblox.Instance.new("Folder")
PartKit.part(folder, {
	Size = Vector3.new(200, 1, 120),
	CFrame = CFrame.new(50, -0.5, 20),
	Color = roblox.Color3.fromRGB(200, 186, 156),
})
for i, def in Sorcerers.List do
	-- Two rows, 10 studs apart, facing the camera (+Z).
	local row = if i <= 8 then 0 else 1
	local x = ((i - 1) % 8) * 11 + row * 5
	local z = row * -14
	local cf = CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(x, 0, z + 10))
	local model = CharacterModels.build(def.id, cf, { aura = true, scale = CharacterModels.FarmScale })
	model.Parent = folder
end
for i, def in Crates.List do
	local x = (i - 1) * 9
	local model = CrateModels.build(def.id, CFrame.lookAt(Vector3.new(x, 0, 44), Vector3.new(x + 4, 0, 56)))
	model.Parent = folder
end
-- Avatar stand-in (5.2 studs) next to the line-up
local skin = roblox.Color3.fromRGB(245, 205, 160)
for _, p in
	{
		{ Vector3.new(0.9, 2, 1), Vector3.new(-9.5, 1, 0), roblox.Color3.fromRGB(40, 60, 120) },
		{ Vector3.new(0.9, 2, 1), Vector3.new(-8.5, 1, 0), roblox.Color3.fromRGB(40, 60, 120) },
		{ Vector3.new(2, 2, 1), Vector3.new(-9, 3, 0), roblox.Color3.fromRGB(220, 60, 60) },
		{ Vector3.new(0.9, 2, 1), Vector3.new(-10.45, 3, 0), skin },
		{ Vector3.new(0.9, 2, 1), Vector3.new(-7.55, 3, 0), skin },
		{ Vector3.new(1.2, 1.2, 1.2), Vector3.new(-9, 4.6, 0), skin },
	}
do
	PartKit.part(folder, { Size = p[1], CFrame = CFrame.new(p[2]), Color = p[3] })
end
local out = Export.collect(folder)
print("sorcerers built:", #Sorcerers.List, "crates:", #Crates.List, "parts:", #out.parts)
fs.writeFile(process.args[2] or "build/models.json", serde.encode("json", out))
