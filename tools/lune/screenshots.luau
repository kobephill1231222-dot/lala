--!nocheck
-- Pixel screenshots of the real client, for docs/previews and for reviewing the look.
--
--   lune run tools/lune/screenshots.luau <place.rbxl> <outDir>            -- every scene
--   lune run tools/lune/screenshots.luau <place.rbxl> <outDir> <scene>    -- one scene
--
-- The engine shim can only be installed once per process and the client never exits on its
-- own, so each scene runs in its own Lune process (this script calling itself).
local process = require("@lune/process")
local fs = require("@lune/fs")
local ClientHarness = require("./lib/ClientHarness")

local place = process.args[1] or "dist/JJKFarm.rbxl"
local outDir = process.args[2] or "build/preview"
local only = process.args[3]

local V3 = function(x, y, z)
	return require("@lune/roblox").Vector3.new(x, y, z)
end

-- Each scene: screen size, input mode and what to do before the shot.
local SCENES = {
	{
		name = "farm",
		run = function(H)
			H:frames(150)
		end,
	},
	{
		name = "carry",
		run = function(H)
			H.player:SetAttribute("CarriedOrbs", 20)
			H.player:SetAttribute("CarriedValue", 40)
			local gate = H.Layout.farmCFrame(1) * H.Layout.Entrance
			H:moveTo(V3(gate.X, 0, gate.Z + 10))
			H:frames(20)
		end,
	},
	{
		name = "plaza",
		run = function(H)
			local p = H.Layout.SellStand
			H:moveTo(V3(p.X, 0, p.Z + 8))
			H:frames(30)
		end,
	},
	{
		name = "crate_shop",
		run = function(H)
			local p = H.Layout.CrateShop
			H:moveTo(V3(p.X, 0, p.Z))
			H:frames(10)
			H:key("B")
			H:frames(10)
		end,
	},
	{
		name = "upgrade_shop",
		run = function(H)
			local p = H.Layout.UpgradeShop
			H:moveTo(V3(p.X, 0, p.Z))
			H:frames(10)
			H:key("U")
			H:frames(10)
		end,
	},
	{
		name = "sorcerers",
		run = function(H)
			H:frames(10)
			H:key("G")
			H:frames(10)
		end,
	},
	{
		name = "phone",
		width = 844,
		height = 390,
		touch = true,
		run = function(H)
			H:frames(90)
		end,
	},
}

local function find(name)
	for _, scene in SCENES do
		if scene.name == name then
			return scene
		end
	end
	return nil
end

if only then
	local scene = find(only)
	if not scene then
		print("unknown scene " .. only)
		process.exit(2)
	end
	local H = ClientHarness.new(place, { width = scene.width, height = scene.height, touch = scene.touch })
	local ok, err = pcall(function()
		H:boot()
		scene.run(H)
		H:render(outDir .. "/" .. scene.name .. ".png")
	end)
	if not ok then
		print("FAIL " .. scene.name .. ": " .. tostring(err))
	end
	H:finish(if ok then 0 else 1)
end

fs.writeDir(outDir)
local failed = 0
for _, scene in SCENES do
	local result = process.exec("lune", { "run", "tools/lune/screenshots.luau", place, outDir, scene.name })
	if result.ok then
		print("ok   " .. outDir .. "/" .. scene.name .. ".png")
	else
		failed += 1
		print(result.stdout .. result.stderr)
	end
end
print(string.format("%d / %d screenshots", #SCENES - failed, #SCENES))
process.exit(if failed == 0 then 0 else 1)
