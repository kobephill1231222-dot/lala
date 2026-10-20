--!strict
-- Makes sure the (invisible) physics world exists. It is normally baked into the place file
-- (see tools/lune/bake.luau); if it's missing (e.g. a fresh `rojo serve` session) or is the
-- old 3D map from an earlier version of the place, it is (re)built here.

local Lighting = game:GetService("Lighting")

local MapBuilder = require(script.Parent.Parent.Map.MapBuilder)

local MapService = {}

function MapService.ensure()
	local started = os.clock()
	local map = workspace:FindFirstChild("JJKFarmMap")
	if map and not map:FindFirstChild("Solids") then
		map:Destroy() -- the pre-pixel 3D map
		map = nil
	end
	if not map then
		MapBuilder.buildStructures(workspace)
	end
	local old = workspace:FindFirstChild("CurseboundMap")
	if old then
		old:Destroy()
	end
	MapBuilder.applyLighting(Lighting)
	print(string.format("[JJK Farm] World ready in %.2fs", os.clock() - started))
end

return MapService
