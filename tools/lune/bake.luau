--!nocheck
-- Bakes the JJK Farm map into the place file and exports a preview scene.
-- Usage: lune run tools/lune/bake.luau <in.rbxl> <out.rbxl> [preview.json]
--
-- Runs the real Map modules (ServerScriptService.Server.Map) against the place's DataModel,
-- so the .rbxl opens in Studio with the whole map and lighting already in place.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local Sandbox = require("./lib/Sandbox")
local Export = require("./lib/Export")

local input = process.args[1] or "build/game.rbxl"
local output = process.args[2] or "dist/JJKFarm.rbxl"
local previewPath = process.args[3]

local game = Sandbox.loadPlace(input)
local sb = Sandbox.new(game)
local MapBuilder = sb.requirePath("ServerScriptService/Server/Map/MapBuilder")

local workspace = game:GetService("Workspace")
for _, name in { "JJKFarmMap", "CurseboundMap" } do
	local existing = workspace:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
end

local started = os.clock()
local map = MapBuilder.buildStructures(workspace)
MapBuilder.applyLighting(game:GetService("Lighting"))
print(string.format("Built map in %.2fs", os.clock() - started))

-- Statistics per top-level group
local totalParts, totalLights, totalEmitters = 0, 0, 0
local groups = {}
for _, g in map:GetChildren() do
	if g.Name == "Farms" then
		for _, f in g:GetChildren() do
			table.insert(groups, f)
		end
	else
		table.insert(groups, g)
	end
end
for _, group in groups do
	local parts, lights = 0, 0
	for _, d in group:GetDescendants() do
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
	print(string.format("  %-14s %5d parts  %3d lights", group.Name, parts, lights))
end
print(
	string.format(
		"TOTAL %d parts, %d point lights, %d particle emitters",
		totalParts,
		totalLights,
		totalEmitters
	)
)

-- Sanity checks for the names services and the client rely on
local function require_(cond, msg)
	if not cond then
		error("bake check failed: " .. msg)
	end
end
local farms = map:FindFirstChild("Farms")
require_(farms and #farms:GetChildren() == 6, "six farms")
for _, farm in farms:GetChildren() do
	local n = farm.Name
	local sign = farm:FindFirstChild("Sign")
	require_(sign and sign:FindFirstChild("SignGui") and sign.SignGui:FindFirstChild("Title"), n .. " sign")
	require_(farm:FindFirstChild("Slots") and #farm.Slots:GetChildren() == 10, n .. " slots")
	for _, slot in farm.Slots:GetChildren() do
		if slot.Name:match("^Slot%d+$") then
			require_(
				slot:FindFirstChild("Ring") and slot:FindFirstChild("Lock") and slot:GetAttribute("Slot"),
				slot:GetFullName()
			)
		end
	end
	require_(farm:FindFirstChild("Pads") and #farm.Pads:GetChildren() == 4, n .. " pads")
	for _, pad in farm.Pads:GetChildren() do
		require_(
			pad:FindFirstChild("Ring") and pad:FindFirstChild("Lock") and pad:GetAttribute("Pad"),
			pad:GetFullName()
		)
	end
	local box = farm:FindFirstChild("OrbBox")
	require_(box and box:FindFirstChild("Fill") and box:FindFirstChild("LabelAnchor"), n .. " orb box")
	require_(
		farm:FindFirstChild("Lane") and farm.Lane:FindFirstChild("Belt") and farm.Lane:FindFirstChild("Slats"),
		n .. " lane"
	)
	local pad = farm:FindFirstChild("CollectPad")
	require_(
		pad and pad:GetAttribute("TouchAction") == "Collect" and pad:GetAttribute("Farm"),
		n .. " collect pad"
	)
	require_(farm:FindFirstChild("StatsBoard", true), n .. " stats board")
end
local plaza = map:FindFirstChild("Plaza")
require_(plaza, "plaza")
require_(
	plaza.SellStand:FindFirstChild("SellPad")
		and plaza.SellStand.SellPad:GetAttribute("TouchAction") == "Sell",
	"sell pad"
)
require_(
	plaza.CrateShop:FindFirstChild("Displays") and #plaza.CrateShop.Displays:GetChildren() == 4,
	"crate displays"
)
require_(
	plaza.CrateShop:FindFirstChild("Counter") and plaza.UpgradeShop:FindFirstChild("Counter"),
	"shop counters"
)
require_(plaza.UpgradeShop:FindFirstChild("UpgradeBoard"), "upgrade board")
require_(plaza:FindFirstChild("Spawn"), "spawn location")

fs.writeDir("dist")
fs.writeFile(output, roblox.serializePlace(game))
print("Wrote " .. output)

if previewPath then
	local Stage = require("./lib/Stage")
	local stage = Stage.build(sb, map)
	local scene = Export.collect(map)
	Export.collect(stage, scene)
	fs.writeFile(previewPath, serde.encode("json", scene))
	print(string.format("Wrote preview scene (%d parts, %d lights)", #scene.parts, #scene.lights))
end
