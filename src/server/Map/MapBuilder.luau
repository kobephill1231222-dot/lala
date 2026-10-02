--!strict
-- Builds the Cursebound village. `buildStructures` creates Workspace.CurseboundMap (all parts),
-- `buildTerrain` runs the TerrainPlan, `applyLighting` sets up the dusk atmosphere.
-- The same code runs in Studio/servers and in the offline Lune bake (tools/lune/bake.luau).

local Atmosphere = require(script.Parent.Atmosphere)
local Courtyard = require(script.Parent.Courtyard)
local Forest = require(script.Parent.Forest)
local Sanctuary = require(script.Parent.Sanctuary)
local Shrine = require(script.Parent.Shrine)
local TerrainPlan = require(script.Parent.TerrainPlan)
local Village = require(script.Parent.Village)
local WestDistrict = require(script.Parent.WestDistrict)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Layout = require(ReplicatedStorage.Shared.Config.MapLayout)

local MapBuilder = {}

function MapBuilder.buildStructures(parent: Instance): Folder
	local map = Instance.new("Folder")
	map.Name = "CurseboundMap"
	Shrine.build(map)
	Courtyard.build(map)
	WestDistrict.build(map)
	Forest.build(map)
	local sanctuaries = Instance.new("Folder")
	sanctuaries.Name = "Sanctuaries"
	sanctuaries.Parent = map
	for index = 1, #Layout.PlotAngles do
		Sanctuary.build(sanctuaries, index)
	end
	Village.build(map)
	map.Parent = parent
	return map
end

function MapBuilder.terrainOps(): { TerrainPlan.Op }
	local ops = TerrainPlan.create()
	for _, road in Village.roads() do
		TerrainPlan.paintPath(ops, road.points, road.width, road.material)
	end
	return ops
end

function MapBuilder.buildTerrain(terrain: any)
	local ops = MapBuilder.terrainOps()
	TerrainPlan.apply(terrain, ops)
	if typeof(terrain) == "Instance" and terrain:IsA("Terrain") then
		terrain.WaterColor = TerrainPlan.WaterColor
		terrain.WaterTransparency = 0.75
		terrain.WaterReflectance = 0.55
		terrain.WaterWaveSize = 0.06
		terrain.WaterWaveSpeed = 6
	end
end

function MapBuilder.applyLighting(lighting: Lighting)
	Atmosphere.apply(lighting)
end

return MapBuilder
