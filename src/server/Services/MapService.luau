--!strict
-- Makes sure the world exists. The map is normally baked into the place file (see
-- tools/lune/bake.luau); if it's missing (e.g. a fresh `rojo serve` session) it is generated
-- here. Lighting is always (re)applied so the place looks right even if edited in Studio.

local Lighting = game:GetService("Lighting")

local MapBuilder = require(script.Parent.Parent.Map.MapBuilder)

local MapService = {}

function MapService.ensure()
	local started = os.clock()
	if not workspace:FindFirstChild("JJKFarmMap") then
		MapBuilder.buildStructures(workspace)
	end
	-- An older build of this place may still contain the previous map.
	local old = workspace:FindFirstChild("CurseboundMap")
	if old then
		old:Destroy()
	end
	MapBuilder.applyLighting(Lighting)
	print(string.format("[JJK Farm] World ready in %.2fs", os.clock() - started))
end

return MapService
