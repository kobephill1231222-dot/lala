--!strict
-- Makes sure the world exists. Structures are normally baked into the place file (see
-- tools/lune/bake.luau); if they're missing (e.g. a fresh `rojo serve` session) they are
-- generated here. Terrain cannot be baked offline, so it is generated at startup unless a
-- previous build was saved into the place.

local Lighting = game:GetService("Lighting")

local MapBuilder = require(script.Parent.Parent.Map.MapBuilder)

local MapService = {}

function MapService.ensure()
	local started = os.clock()
	if not workspace:FindFirstChild("CurseboundMap") then
		MapBuilder.buildStructures(workspace)
	end
	if not workspace.Terrain:GetAttribute("CurseboundTerrain") then
		MapBuilder.buildTerrain(workspace.Terrain)
		workspace.Terrain:SetAttribute("CurseboundTerrain", true)
	end
	MapBuilder.applyLighting(Lighting)
	print(string.format("[Cursebound] World ready in %.2fs", os.clock() - started))
end

return MapService
