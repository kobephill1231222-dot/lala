--!strict
-- Builds JJK Farm's world. `buildStructures` creates Workspace.JJKFarmMap (all parts),
-- `applyLighting` sets up the bright afternoon look. The same code runs in Studio/servers
-- and in the offline Lune bake (tools/lune/bake.luau), which saves the result into the place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Config.FarmLayout)
local Atmosphere = require(script.Parent.Atmosphere)
local Farm = require(script.Parent.Farm)
local Plaza = require(script.Parent.Plaza)
local Scenery = require(script.Parent.Scenery)

local MapBuilder = {}

function MapBuilder.buildStructures(parent: Instance): Folder
	local map = Instance.new("Folder")
	map.Name = "JJKFarmMap"
	Scenery.build(map)
	Plaza.build(map)
	local farms = Instance.new("Folder")
	farms.Name = "Farms"
	farms.Parent = map
	for index = 1, Layout.FarmCount do
		Farm.build(farms, index)
	end
	map.Parent = parent
	return map
end

function MapBuilder.applyLighting(lighting: Lighting)
	Atmosphere.apply(lighting)
end

return MapBuilder
