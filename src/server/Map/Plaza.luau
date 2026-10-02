--!strict
-- The shared plaza at the centre of the map: the Sell Stand in the middle, the Crate Shop to
-- the north and the Upgrade Shop to the south, with a paved path out to every farm's gate.
-- Compact on purpose: from any farm entrance the Sell Stand is a few seconds' walk.
--
-- Contract with services/client: SellStand/SellPad (TouchAction = "Sell"), SellStand/Coin,
-- CrateShop/Displays/<tier> (Pedestal with Tier attribute), CrateShop/Counter,
-- UpgradeShop/Counter, UpgradeShop/UpgradeBoard, Spawn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Crates = require(ReplicatedStorage.Shared.Config.Crates)
local Layout = require(ReplicatedStorage.Shared.Config.FarmLayout)
local PartKit = require(ReplicatedStorage.Shared.Visuals.PartKit)
local CrateModels = require(ReplicatedStorage.Shared.Visuals.CrateModels)
local Prng = require(ReplicatedStorage.Shared.Util.Prng)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)

local Plaza = {}

local V3 = Vector3.new
local rad = math.rad
local M = Enum.Material

local function facing(position: Vector3, target: Vector3): CFrame
	return CFrame.lookAt(position, Vector3.new(target.X, position.Y, target.Z))
end

local function buildGround(model: Instance)
	local r = Layout.PlazaRadius
	Kit.cylinder(model, "Paving", r * 2, 0.4, CFrame.new(0, 0.2, 0), Palette.Paving, M.Pavement)
	Kit.cylinder(model, "Curb", r * 2 + 3, 0.3, CFrame.new(0, 0.15, 0), Palette.StoneDark, M.Slate)
	Kit.cylinder(model, "Inner", 64, 0.1, CFrame.new(0, 0.45, 0), Palette.PavingLight, M.Pavement)
	-- Gold inlay ring and spokes toward each farm
	for i = 0, 35 do
		local a = rad(i * 10)
		local p = V3(math.sin(a) * 32, 0.47, -math.cos(a) * 32)
		Kit.deco(model, "Inlay", V3(5.8, 0.06, 0.5), CFrame.lookAt(p, V3(0, 0.47, 0)), Palette.Gold, M.Metal)
	end
	-- Paths to the farm gates
	for index, angle in Layout.FarmAngles do
		local a = rad(angle)
		local dir = V3(math.sin(a), 0, -math.cos(a))
		local startR, endR = r - 6, Layout.FarmRadius - Layout.FarmDepth / 2 + 4
		local mid = dir * ((startR + endR) / 2)
		local len = endR - startR
		local path = CFrame.lookAt(mid + V3(0, 0.25, 0), dir * endR + V3(0, 0.25, 0))
		Kit.part(model, "FarmPath" .. index, V3(14, 0.5, len), path, Palette.PavingLight, M.Pavement)
		for _, side in { -1, 1 } do
			Kit.stoneLantern(
				model,
				CFrame.lookAt(dir * (r - 2) + V3(0, 0, 0), V3(0, 0, 0)) * CFrame.new(side * 10, 0, 0),
				1.35,
				true
			)
		end
	end
end

local function buildSellStand(model: Instance): Model
	local stand = PartKit.model(model, "SellStand")
	local c = Layout.SellStand
	Kit.cylinder(stand, "Dais", 34, 0.6, CFrame.new(c + V3(0, 0.7, 0)), Palette.StoneLight, M.Slate)
	Kit.cylinder(stand, "Dais2", 26, 0.6, CFrame.new(c + V3(0, 1.3, 0)), Palette.Stone, M.Slate)
	local pad = Kit.cylinder(
		stand,
		"SellPad",
		15,
		0.3,
		CFrame.new(c + V3(0, 1.75, 0)),
		Color3.fromRGB(255, 210, 90),
		M.Neon,
		{
			CanTouch = true,
			Transparency = 0.1,
		}
	)
	pad:SetAttribute("TouchAction", "Sell")
	Kit.cylinder(stand, "SellPadRim", 16.4, 0.25, CFrame.new(c + V3(0, 1.7, 0)), Palette.Gold, M.Metal)
	-- Pavilion
	local roofY = 1.6 + 14
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			local p = c + V3(x * 11, 0, z * 11)
			Kit.cylinder(stand, "Pillar", 1.6, 14, CFrame.new(p + V3(0, 1.6 + 7, 0)), Palette.Lacquer, M.Wood)
			Kit.cylinder(
				stand,
				"PillarBase",
				2.2,
				1,
				CFrame.new(p + V3(0, 1.6 + 0.5, 0)),
				Palette.Black,
				M.Slate
			)
		end
	end
	for _, z in { -1, 1 } do
		Kit.part(
			stand,
			"Beam",
			V3(24, 1.2, 1.2),
			CFrame.new(c + V3(0, roofY - 0.6, z * 11)),
			Palette.LacquerDark,
			M.Wood
		)
		Kit.part(
			stand,
			"Beam",
			V3(1.2, 1.2, 24),
			CFrame.new(c + V3(z * 11, roofY - 0.6, 0)),
			Palette.LacquerDark,
			M.Wood
		)
	end
	Kit.roof(stand, CFrame.new(c + V3(0, roofY, 0)), 32, 32, 8, Palette.RoofTile, true)
	-- Signs on all four sides
	for i = 0, 3 do
		local a = rad(i * 90)
		local dir = V3(math.sin(a), 0, -math.cos(a))
		local cf = facing(c + dir * 11.8 + V3(0, roofY - 2.6, 0), c + dir * 30)
		Kit.sign(stand, cf, 12, 2.8, "SELL STAND", {
			name = "SellSign",
			color = Palette.Gold,
			font = Enum.Font.FredokaOne,
			board = Palette.Black,
		})
	end
	-- Floating coin over the roof: the landmark you can see from every farm
	local coin = Kit.cylinder(
		stand,
		"Coin",
		9,
		1.2,
		CFrame.new(c + V3(0, roofY + 15, 0)) * CFrame.Angles(rad(90), 0, 0),
		Palette.Gold,
		M.Neon,
		{
			CanCollide = false,
			CanQuery = false,
		}
	)
	Kit.light(coin, Palette.Gold, 30, 1.4)
	local coinFace =
		Kit.deco(stand, "CoinMark", V3(1.4, 3.6, 1.5), coin.CFrame, Color3.fromRGB(200, 140, 40), M.Metal)
	PartKit.weld(coin, coinFace)
	coinFace.Anchored = false
	-- Coin piles and lantern tables
	local rng: any = Prng.new(77)
	for i = 0, 3 do
		local a = rad(45 + i * 90)
		local p = c + V3(math.sin(a) * 9.5, 1.6, -math.cos(a) * 9.5)
		Kit.part(stand, "Table", V3(3, 2.4, 3), CFrame.new(p + V3(0, 1.2, 0)), Palette.DarkWood, M.Wood)
		for k = 1, 4 do
			local h = 0.3 * rng:NextInteger(2, 6)
			Kit.cylinder(
				stand,
				"Coins",
				0.9,
				h,
				CFrame.new(p + V3(rng:NextNumber(-0.8, 0.8), 2.4 + h / 2, rng:NextNumber(-0.8, 0.8))),
				Palette.Gold,
				M.Metal,
				{
					CanCollide = false,
				}
			)
			local _ = k
		end
	end
	-- Paper lanterns hanging from the beams
	for i = 0, 3 do
		local a = rad(i * 90)
		Kit.paperLantern(
			stand,
			CFrame.new(c + V3(math.sin(a) * 11, roofY - 1.2, -math.cos(a) * 11)),
			1.3,
			nil,
			i % 2 == 0
		)
	end
	return stand
end

local function buildCrateShop(model: Instance): Model
	local shop = PartKit.model(model, "CrateShop")
	local front = Layout.CrateShop
	local center = front + V3(0, 0, -12)
	local cf = facing(center, V3(0, 0, 0))
	Kit.building(shop, cf, 44, 18, 13, {
		name = "Hall",
		open = { front = true },
		roofHeight = 9,
		plaster = Palette.Plaster,
		wood = Palette.LacquerDark,
	})
	-- Banner sign over the open front
	Kit.sign(shop, cf * CFrame.new(0, 12.4, -9.8), 22, 4, "CRATE SHOP", {
		name = "ShopSign",
		color = Palette.Gold,
		font = Enum.Font.FredokaOne,
		board = Palette.Black,
	})
	-- Counter (where the client puts the shop prompt)
	Kit.part(
		shop,
		"Counter",
		V3(16, 3.4, 3),
		cf * CFrame.new(0, 1.2 + 1.7, -2),
		Palette.AgedWood,
		M.WoodPlanks
	)
	Kit.part(
		shop,
		"CounterTop",
		V3(16.6, 0.3, 3.4),
		cf * CFrame.new(0, 1.2 + 3.55, -2),
		Palette.LacquerDark,
		M.Wood
	)
	-- Crate displays out front, one per tier sold, cheapest on the left as you face the shop
	local displays = PartKit.folder(shop, "Displays")
	local sold = {}
	for _, def in Crates.List do
		if def.price > 0 then
			table.insert(sold, def)
		end
	end
	table.sort(sold, function(a, b)
		return a.order < b.order
	end)
	local spacing = 11
	for i, def in sold do
		local x = (i - (#sold + 1) / 2) * spacing
		-- Facing the plaza, the shop's local +X is to the viewer's left; flip so prices rise
		-- left-to-right for someone standing in the plaza.
		local spot = cf * CFrame.new(-x, 0, -16)
		local holder = PartKit.model(displays, def.id)
		local pedestal = Kit.part(
			holder,
			"Pedestal",
			V3(7, 2.4, 7),
			spot * CFrame.new(0, 1.2, 0),
			Palette.StoneLight,
			M.Slate
		)
		pedestal:SetAttribute("Tier", def.id)
		Kit.part(
			holder,
			"PedestalTrim",
			V3(7.6, 0.4, 7.6),
			spot * CFrame.new(0, 2.5, 0),
			def.color,
			if def.order >= 2 then M.Neon else M.SmoothPlastic,
			{
				CanCollide = false,
			}
		)
		local crate = CrateModels.build(def.id, spot * CFrame.new(0, 2.7, 0))
		crate.Name = "Crate"
		crate.Parent = holder
		holder:SetAttribute("Tier", def.id)
	end
	return shop
end

local function buildUpgradeShop(model: Instance): Model
	local shop = PartKit.model(model, "UpgradeShop")
	local front = Layout.UpgradeShop
	local center = front + V3(0, 0, 12)
	local cf = facing(center, V3(0, 0, 0))
	Kit.building(shop, cf, 40, 18, 13, {
		name = "Hall",
		open = { front = true },
		roofHeight = 9,
		plaster = Palette.Plaster,
		wood = Palette.DarkWood,
	})
	Kit.sign(shop, cf * CFrame.new(0, 12.4, -9.8), 22, 4, "UPGRADE SHOP", {
		name = "ShopSign",
		color = Palette.Gold,
		font = Enum.Font.FredokaOne,
		board = Palette.Black,
	})
	Kit.part(
		shop,
		"Counter",
		V3(16, 3.4, 3),
		cf * CFrame.new(0, 1.2 + 1.7, -2),
		Palette.AgedWood,
		M.WoodPlanks
	)
	Kit.part(
		shop,
		"CounterTop",
		V3(16.6, 0.3, 3.4),
		cf * CFrame.new(0, 1.2 + 3.55, -2),
		Palette.LacquerDark,
		M.Wood
	)
	-- Big board out front listing the upgrades (the client keeps the text current)
	local boardCf = cf * CFrame.new(0, 0, -15)
	for _, side in { -1, 1 } do
		Kit.cylinder(
			shop,
			"BoardPost",
			1,
			12,
			boardCf * CFrame.new(side * 9.5, 6, 0),
			Palette.Lacquer,
			M.Wood
		)
	end
	local board = Kit.part(
		shop,
		"UpgradeBoard",
		V3(18, 8, 0.5),
		boardCf * CFrame.new(0, 7, 0),
		Palette.AgedWood,
		M.WoodPlanks
	)
	local label = Kit.label(
		board,
		"ORB VALUE  -  MORE SLOTS  -  BOX SIZE\nOPENING SPEED  -  MORE CRATE PADS\nLUCK  -  WALK SPEED",
		{
			guiName = "BoardGui",
			labelName = "Text",
			color = Palette.Black,
			font = Enum.Font.FredokaOne,
			pps = 24,
			stroke = 1,
		}
	)
	label.TextWrapped = true
	Kit.part(shop, "BoardRoof", V3(20, 0.6, 2.2), boardCf * CFrame.new(0, 11.4, 0), Palette.RoofTile, M.Slate)
	-- Lucky charms: a few glowing ema plaques
	for i = -2, 2 do
		Kit.deco(
			shop,
			"Ema",
			V3(1.6, 1.2, 0.2),
			cf * CFrame.new(i * 2.4 + 0.4, 7.5, 3.5),
			Palette.AgedWood,
			M.Wood
		)
	end
	return shop
end

local function buildDecor(model: Instance)
	local decor = PartKit.model(model, "Decor")
	local rng: any = Prng.new(31)
	-- Sakura between the paths, around the plaza rim
	for i = 0, 5 do
		local a = rad(i * 60)
		local p = V3(math.sin(a) * 70, 0.4, -math.cos(a) * 70)
		if math.abs(p.X) > 20 then -- keep the shop fronts clear
			Kit.maple(decor, p, 1.3, rng, if i % 2 == 0 then Palette.Sakura else Palette.SakuraDeep)
		end
	end
	-- Benches facing the Sell Stand, between the farm paths
	for _, angle in { 60, 120, 240, 300 } do
		local a = rad(angle)
		local p = V3(math.sin(a) * 44, 0.4, -math.cos(a) * 44)
		local cf = facing(p, V3(0, 0.4, 0))
		Kit.part(decor, "Bench", V3(7, 0.5, 2), cf * CFrame.new(0, 1.6, 0), Palette.AgedWood, M.WoodPlanks)
		for _, side in { -1, 1 } do
			Kit.part(
				decor,
				"BenchLeg",
				V3(0.6, 1.4, 1.8),
				cf * CFrame.new(side * 3, 0.7, 0),
				Palette.DarkWood,
				M.Wood
			)
		end
	end
	-- Lantern strings radiating from the Sell Stand roof to poles on the plaza rim
	for _, angle in { 60, 120, 240, 300 } do
		local a = rad(angle)
		local rim = V3(math.sin(a) * 52, 0, -math.cos(a) * 52)
		Kit.cylinder(decor, "LanternPole", 0.8, 15, CFrame.new(rim + V3(0, 7.5, 0)), Palette.Lacquer, M.Wood)
		Kit.deco(decor, "PoleCap", V3(1.4, 0.6, 1.4), CFrame.new(rim + V3(0, 15.2, 0)), Palette.Gold, M.Metal)
		local inner = V3(math.sin(a) * 15, 15.2, -math.cos(a) * 15)
		Kit.lanternString(decor, inner, rim + V3(0, 14.6, 0), 6, 2.2, 3)
	end
end

function Plaza.build(parent: Instance): Model
	local model = PartKit.model(parent, "Plaza")
	buildGround(model)
	buildSellStand(model)
	buildCrateShop(model)
	buildUpgradeShop(model)
	buildDecor(model)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = V3(10, 1, 10)
	spawn.CFrame = CFrame.new(Layout.SpawnPosition)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn.Parent = model
	return model
end

return Plaza
