--!strict
-- Builds the world the server needs. Everything players see is pixel art drawn by the client,
-- so this is only physics: an invisible floor, invisible walls wherever WorldMap says something
-- is solid (fences, buildings, trees, the Orb Box), the touch pads (Collect Pads and the Sell
-- Pad) and the spawn point, plus one Model per farm that carries its replicated attributes.
-- The same code runs on servers and in the offline Lune bake (tools/lune/bake.luau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared.Config.FarmLayout)
local WorldMap = require(Shared.Config.WorldMap)

local MapBuilder = {}

MapBuilder.WallHeight = 8

local function block(parent: Instance, name: string, rect: WorldMap.Rect, height: number, y: number?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.new(rect.x1 - rect.x0, height, rect.z1 - rect.z0)
	part.CFrame = CFrame.new((rect.x0 + rect.x1) / 2, (y or 0) + height / 2, (rect.z0 + rect.z1) / 2)
	part.Parent = parent
	return part
end

local function pad(parent: Instance, name: string, rect: WorldMap.Rect, action: string): Part
	local part = block(parent, name, rect, 1, 0)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = true
	part:SetAttribute("TouchAction", action)
	return part
end

function MapBuilder.buildStructures(parent: Instance): Folder
	local world = WorldMap.get()
	local map = Instance.new("Folder")
	map.Name = "JJKFarmMap"

	-- Floor and the walls at the edge of the world
	local b = world.bounds
	block(map, "Floor", { x0 = b.x0 - 20, z0 = b.z0 - 20, x1 = b.x1 + 20, z1 = b.z1 + 20 }, 2, -2)
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = map
	local h = MapBuilder.WallHeight
	block(walls, "North", { x0 = b.x0 - 2, z0 = b.z0 - 2, x1 = b.x1 + 2, z1 = b.z0 }, h)
	block(walls, "South", { x0 = b.x0 - 2, z0 = b.z1, x1 = b.x1 + 2, z1 = b.z1 + 2 }, h)
	block(walls, "West", { x0 = b.x0 - 2, z0 = b.z0, x1 = b.x0, z1 = b.z1 }, h)
	block(walls, "East", { x0 = b.x1, z0 = b.z0, x1 = b.x1 + 2, z1 = b.z1 }, h)

	-- Everything solid in the world map
	local solids = Instance.new("Folder")
	solids.Name = "Solids"
	solids.Parent = map
	for _, object in world.objects do
		if object.solid then
			local part = block(solids, object.kind, object.rect, h)
			if object.farm then
				part:SetAttribute("Farm", object.farm)
			end
		end
	end

	-- Plaza: the Sell Stand's pad and the spawn
	local plaza = Instance.new("Model")
	plaza.Name = "Plaza"
	plaza.Parent = map
	local stand = Instance.new("Model")
	stand.Name = "SellStand"
	stand.Parent = plaza
	pad(stand, "SellPad", world.sellPad, "Sell")
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(8, 0.2, 8)
	spawn.CFrame = CFrame.new(Layout.SpawnPosition.X, 0.1, Layout.SpawnPosition.Z)
	spawn.Parent = plaza

	-- One Model per farm: FarmService puts its replicated attributes and Runtime folder here.
	local farms = Instance.new("Folder")
	farms.Name = "Farms"
	farms.Parent = map
	for _, info in world.farms do
		local model = Instance.new("Model")
		model.Name = "Farm" .. info.index
		model:SetAttribute("Farm", info.index)
		local collect = pad(model, "CollectPad", info.collect, "Collect")
		collect:SetAttribute("Farm", info.index)
		model.PrimaryPart = collect
		model.Parent = farms
	end

	map.Parent = parent
	return map
end

-- Nothing in 3D is ever seen (the pixel world covers the screen), so lighting is kept as
-- cheap as possible.
function MapBuilder.applyLighting(lighting: Lighting)
	lighting.GlobalShadows = false
	lighting.Brightness = 1
	lighting.EnvironmentDiffuseScale = 0
	lighting.EnvironmentSpecularScale = 0
	for _, child in lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("Clouds") then
			child:Destroy()
		end
	end
end

return MapBuilder
