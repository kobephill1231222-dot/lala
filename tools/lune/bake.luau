--!nocheck
-- Bakes JJK Farm's physics world into the place file. Players never see it (the pixel client
-- draws the world), but walls, the Orb Boxes, touch pads and the spawn must exist for
-- movement and the server's range checks.
-- Usage: lune run tools/lune/bake.luau <in.rbxl> <out.rbxl>
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Sandbox = require("./lib/Sandbox")

local input = process.args[1] or "build/game.rbxl"
local output = process.args[2] or "dist/JJKFarm.rbxl"

local game = Sandbox.loadPlace(input)
local sb = Sandbox.new(game)
local MapBuilder = sb.requirePath("ServerScriptService/Server/Map/MapBuilder")
local Layout = sb.requirePath("ReplicatedStorage/Shared/Config/FarmLayout")

local workspace = game:GetService("Workspace")
for _, name in { "JJKFarmMap", "CurseboundMap" } do
	local existing = workspace:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
end

local map = MapBuilder.buildStructures(workspace)
MapBuilder.applyLighting(game:GetService("Lighting"))

local parts, visible = 0, 0
for _, d in map:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
		if d.Transparency < 1 then
			visible += 1
		end
	end
end
print(string.format("Built physics world: %d invisible parts", parts))

local function check(cond, msg)
	if not cond then
		error("bake check failed: " .. msg)
	end
end
check(visible == 0, "every map part is invisible (the client draws the world)")
local farms = map:FindFirstChild("Farms")
check(farms and #farms:GetChildren() == Layout.FarmCount, "six farms")
for _, farm in farms:GetChildren() do
	local pad = farm:FindFirstChild("CollectPad")
	check(pad and pad:GetAttribute("TouchAction") == "Collect" and pad:GetAttribute("Farm"), farm.Name .. " collect pad")
end
local plaza = map:FindFirstChild("Plaza")
check(plaza and plaza.SellStand:FindFirstChild("SellPad"), "sell pad")
check(plaza.SellStand.SellPad:GetAttribute("TouchAction") == "Sell", "sell pad action")
check(plaza:FindFirstChild("Spawn"), "spawn location")
check(map:FindFirstChild("Solids") and #map.Solids:GetChildren() > 50, "solid walls")

fs.writeDir("dist")
fs.writeFile(output, roblox.serializePlace(game))
print("Wrote " .. output)
