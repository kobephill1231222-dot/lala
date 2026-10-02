--!nocheck
-- Bakes the village into the place file and exports a preview scene.
-- Usage: lune run tools/lune/bake.luau <in.rbxl> <out.rbxl> [preview.json]
--
-- Runs the real Map modules (ServerScriptService.Server.Map) against the place's DataModel.
-- Parts and lighting are baked; terrain is recorded for the preview only, because voxel data
-- can't be written offline (the server generates it on startup, or bake it in Studio).
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local Sandbox = require("./lib/Sandbox")
local Export = require("./lib/Export")

local input = process.args[1] or "build/game.rbxl"
local output = process.args[2] or "dist/CurseboundFarm.rbxl"
local previewPath = process.args[3]

local game = Sandbox.loadPlace(input)
local sb = Sandbox.new(game)
local MapBuilder = sb.requirePath("ServerScriptService/Server/Map/MapBuilder")
local TerrainPlan = sb.requirePath("ServerScriptService/Server/Map/TerrainPlan")

local workspace = game:GetService("Workspace")
local existing = workspace:FindFirstChild("CurseboundMap")
if existing then
	existing:Destroy()
end

local started = os.clock()
local map = MapBuilder.buildStructures(workspace)
MapBuilder.applyLighting(game:GetService("Lighting"))
print(string.format("Built map in %.2fs", os.clock() - started))

-- Statistics: parts per district, lights, emitters
local totalParts, totalLights, totalEmitters = 0, 0, 0
for _, district in map:GetChildren() do
	local parts, lights = 0, 0
	for _, d in district:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		elseif d:IsA("PointLight") then
			lights += 1
		elseif d:IsA("ParticleEmitter") then
			totalEmitters += 1
		end
	end
	totalParts += parts
	totalLights += lights
	print(string.format("  %-14s %5d parts  %3d lights", district.Name, parts, lights))
end
print(string.format("TOTAL %d parts, %d point lights, %d particle emitters", totalParts, totalLights, totalEmitters))

-- Sanity checks that services rely on
local function require_(cond, msg)
	if not cond then
		error("bake check failed: " .. msg)
	end
end
local sanctuaries = map:FindFirstChild("Sanctuaries")
require_(sanctuaries and #sanctuaries:GetChildren() == 6, "six sanctuaries")
for _, s in sanctuaries:GetChildren() do
	require_(s:FindFirstChild("Well") and s.Well:FindFirstChild("Core") and s.Well:FindFirstChild("Sensor"), s.Name .. " well")
	require_(s:FindFirstChild("Spots") and #s.Spots:GetChildren() == 10, s.Name .. " spots")
	for _, spot in s.Spots:GetChildren() do
		require_(spot:FindFirstChild("Anchor") and spot:FindFirstChild("Ring") and spot:FindFirstChild("Seal"), spot:GetFullName())
	end
	require_(s:FindFirstChild("Sign", true) and s:FindFirstChild("OwnerLabel", true), s.Name .. " sign")
end
require_(map:FindFirstChild("Forest") and map.Forest:FindFirstChild("Spawns") and #map.Forest.Spawns:GetChildren() > 0, "forest spawns")
require_(map:FindFirstChild("Dojo") and map.Dojo:FindFirstChild("Dummies"), "dojo dummies")
require_(map:FindFirstChild("Shop") and map.Shop:FindFirstChild("Counter"), "shop counter")
require_(map:FindFirstChild("Courtyard") and map.Courtyard:FindFirstChild("Circle") and map.Courtyard:FindFirstChild("Altar"), "courtyard")
require_(map:FindFirstChild("ArrivalSpawn", true), "spawn location")

fs.writeDir("dist")
fs.writeFile(output, roblox.serializePlace(game))
print("Wrote " .. output)

if previewPath then
	local scene = Export.collect(map)
	local ops = MapBuilder.terrainOps()
	local terrainOps = {}
	local function vec(v)
		return { v.X, v.Y, v.Z }
	end
	for _, op in ops do
		local entry = { m = op.material.Name, paint = op.paint == true }
		if op.kind == "ball" then
			entry.k, entry.p, entry.radius = "ball", vec(op.center), op.radius
		elseif op.kind == "cyl" then
			entry.k, entry.p, entry.height, entry.radius = "cyl", vec(op.cframe.Position), op.height, op.radius
		else
			local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = op.cframe:GetComponents()
			entry.k, entry.p, entry.z = op.kind, vec(op.cframe.Position), vec(op.size)
			entry.r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 }
		end
		table.insert(terrainOps, entry)
	end
	local colors = {}
	for material, color in TerrainPlan.MaterialColors do
		colors[material.Name] = { math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255) }
	end
	local wc = TerrainPlan.WaterColor
	scene.terrain = {
		ops = terrainOps,
		colors = colors,
		waterColor = { math.floor(wc.R * 255), math.floor(wc.G * 255), math.floor(wc.B * 255) },
		bounds = { -760, -760, 760, 760 },
		step = 4,
	}
	fs.writeFile(previewPath, serde.encode("json", scene))
	print(string.format("Wrote preview scene (%d parts, %d lights, %d terrain ops)", #scene.parts, #scene.lights, #terrainOps))
end
