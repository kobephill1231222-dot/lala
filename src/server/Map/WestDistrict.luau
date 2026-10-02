--!strict
-- West of the shrine: a small plaza, the Training Dojo with its practice yard, the Talisman
-- Shop (upgrades) and a five-storey pagoda that anchors the western skyline.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Config.MapLayout)
local PartKit = require(ReplicatedStorage.Shared.Visuals.PartKit)
local Prng = require(ReplicatedStorage.Shared.Util.Prng)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)

local WestDistrict = {}

local rad = math.rad
local V3 = Vector3.new
local M = Enum.Material

local function facingEast(position: Vector3): CFrame
	return CFrame.lookAt(V3(position.X, 0, position.Z), V3(position.X + 10, 0, position.Z))
end

local function buildPlaza(parent: Instance, rng: any)
	local folder = PartKit.folder(parent, "WestPlaza")
	local c = Layout.WestPlaza
	Kit.cylinder(folder, "PlazaFloor", 30, 0.6, CFrame.new(c.X, 0.1, c.Z), Palette.Stone, M.Slate)
	Kit.cylinder(folder, "PlazaInlay", 10, 0.65, CFrame.new(c.X, 0.12, c.Z), Palette.StoneLight, M.Slate)
	-- Village well with a little roof
	local well = CFrame.new(c.X - 4, 0, c.Z + 9)
	Kit.cylinder(folder, "WellRim", 4.2, 2.4, well * CFrame.new(0, 1.2, 0), Palette.StoneDark, M.Slate)
	Kit.cylinder(
		folder,
		"WellWater",
		3.2,
		0.2,
		well * CFrame.new(0, 1.9, 0),
		Color3.fromRGB(30, 46, 62),
		M.Glass,
		{ CanCollide = false }
	)
	for _, x in { -2.3, 2.3 } do
		Kit.part(folder, "WellPost", V3(0.45, 6, 0.45), well * CFrame.new(x, 3, 0), Palette.DarkWood, M.Wood)
	end
	Kit.roof(folder, well * CFrame.new(0, 6, 0), 6.4, 4, 1.8, nil, false)
	Kit.part(folder, "Bucket", V3(1, 1, 1), well * CFrame.new(0.6, 2.9, -1.4), Palette.Wood, M.WoodPlanks)
	-- Notice board with quests from villagers
	local board = CFrame.lookAt(V3(c.X + 2, 0, c.Z - 11), V3(c.X + 2, 0, c.Z))
	for _, x in { -3, 3 } do
		Kit.part(
			folder,
			"BoardPost",
			V3(0.5, 7, 0.5),
			board * CFrame.new(x, 3.5, 0),
			Palette.DarkWood,
			M.Wood
		)
	end
	Kit.sign(
		folder,
		board * CFrame.new(0, 4.6, 0),
		6.4,
		3.4,
		"NOTICE\nCurses sighted past the broken gate.\nSeals wanted at the Courtyard.",
		{
			font = Enum.Font.GothamMedium,
			board = Palette.AgedWood,
			color = Color3.fromRGB(40, 30, 30),
			stroke = 1,
			lightInfluence = 1,
		}
	)
	Kit.roof(folder, board * CFrame.new(0, 7, 0), 8, 2.4, 1.2, nil, false)
	for _, offset in { V3(12, 0, 10), V3(12, 0, -10), V3(-12, 0, -8) } do
		Kit.stoneLantern(folder, CFrame.new(c + offset), 1, true)
	end
	-- A cart and crates left by a merchant
	local cart = CFrame.new(c.X - 13, 0, c.Z + 6) * CFrame.Angles(0, rad(25), 0)
	Kit.part(folder, "CartBed", V3(4, 0.5, 6), cart * CFrame.new(0, 2, 0), Palette.AgedWood, M.WoodPlanks)
	for _, x in { -2.3, 2.3 } do
		Kit.cylinder(
			folder,
			"Wheel",
			3.4,
			0.4,
			cart * CFrame.new(x, 1.7, 0.5) * CFrame.Angles(0, 0, rad(90)),
			Palette.DarkWood,
			M.Wood
		)
	end
	for k = 0, 2 do
		Kit.part(
			folder,
			"Crate",
			V3(1.6, 1.6, 1.6),
			cart
				* CFrame.new(rng:NextNumber(-1, 1), 3.05, -1.8 + k * 1.8)
				* CFrame.Angles(0, rad(rng:NextNumber(-20, 20)), 0),
			Palette.Wood,
			M.WoodPlanks
		)
	end
end

local function buildDojo(parent: Instance)
	local folder = PartKit.folder(parent, "Dojo")
	local cf = facingEast(Layout.DojoPosition)
	local hall, floorY = Kit.building(folder, cf, 30, 22, 10, {
		name = "DojoHall",
		open = { front = true },
		plinth = 1.4,
		roofHeight = 8,
		overhang = 3.2,
		hip = true,
	})
	-- Upper roof tier (irimoya silhouette)
	Kit.part(
		hall,
		"UpperWall",
		V3(20, 4, 12),
		cf * CFrame.new(0, floorY + 10 + 6, 2),
		Palette.Plaster,
		M.Plaster
	)
	Kit.roof(hall, cf * CFrame.new(0, floorY + 10 + 8, 2), 26, 18, 6, nil, false)
	-- Big name board above the entrance
	Kit.sign(
		folder,
		cf * CFrame.new(0, floorY + 8.6, -11.6),
		8,
		2.6,
		"道場",
		{ font = Enum.Font.Sarpanch, board = Palette.Black, color = Color3.fromRGB(236, 214, 170) }
	)
	-- Weapon racks and a scroll inside
	for _, x in { -10, 10 } do
		Kit.part(hall, "Rack", V3(4, 0.4, 0.6), cf * CFrame.new(x, floorY + 4, 10), Palette.Wood, M.Wood)
		for k = -1, 1 do
			Kit.deco(
				hall,
				"Staff",
				V3(0.25, 6, 0.25),
				cf * CFrame.new(x + k * 1.2, floorY + 3, 9.6) * CFrame.Angles(rad(8), 0, 0),
				Palette.AgedWood,
				M.Wood
			)
		end
	end
	Kit.sign(hall, cf * CFrame.new(0, floorY + 5.5, 10.5), 3, 5, "心", {
		font = Enum.Font.Sarpanch,
		board = Palette.Paper,
		color = Palette.Black,
		stroke = 1,
		name = "Scroll",
	})
	for _, x in { -12, 12 } do
		Kit.paperLantern(hall, cf * CFrame.new(x, floorY + 12.6, -14), 1.3, nil, true)
	end

	-- Practice yard: sanded ground and straw dummies (hit them to practise techniques)
	local yard = Layout.DojoYardCenter
	Kit.part(
		folder,
		"Yard",
		V3(28, 0.3, 26),
		CFrame.new(yard.X, 0.1, yard.Z),
		Color3.fromRGB(150, 132, 104),
		M.Sand
	)
	local dummies = PartKit.folder(folder, "Dummies")
	for k, offset in { V3(-6, 0, -8), V3(5, 0, -6), V3(-5, 0, 7), V3(7, 0, 8) } do
		local base = CFrame.lookAt(V3(yard.X, 0.25, yard.Z) + offset, V3(yard.X + 20, 0.25, yard.Z))
		local dummy = PartKit.model(dummies, "Dummy" .. k)
		local post = Kit.part(
			dummy,
			"Post",
			V3(0.8, 6.5, 0.8),
			base * CFrame.new(0, 3.25, 0),
			Palette.AgedWood,
			M.Wood
		)
		dummy.PrimaryPart = post
		Kit.part(dummy, "Arms", V3(4.4, 0.6, 0.6), base * CFrame.new(0, 4.6, 0), Palette.AgedWood, M.Wood)
		Kit.cylinder(
			dummy,
			"Straw",
			2.2,
			3,
			base * CFrame.new(0, 3.6, 0),
			Color3.fromRGB(196, 170, 100),
			M.Grass
		)
		Kit.ball(dummy, "Head", 1.8, base * CFrame.new(0, 6.3, 0), Color3.fromRGB(196, 170, 100), M.Grass)
		Kit.deco(
			dummy,
			"Target",
			V3(1.2, 1.2, 0.1),
			base * CFrame.new(0, 3.8, -1.12),
			Color3.fromRGB(170, 40, 50),
			M.Fabric
		)
		Kit.part(dummy, "Stand", V3(2.4, 0.5, 2.4), base * CFrame.new(0, 0.25, 0), Palette.DarkWood, M.Wood)
	end
	Kit.sign(
		folder,
		CFrame.lookAt(V3(yard.X + 14, 0, yard.Z - 14), V3(yard.X + 30, 0, yard.Z - 14))
			* CFrame.new(0, 2.6, 0),
		4.6,
		2.2,
		"PRACTICE YARD\nTest your techniques",
		{
			font = Enum.Font.GothamBold,
			board = Palette.AgedWood,
			color = Color3.fromRGB(40, 30, 30),
			stroke = 1,
			lightInfluence = 1,
		}
	)
end

local function buildShopkeeper(parent: Instance, cf: CFrame)
	local model = PartKit.model(parent, "Shopkeeper")
	local fur = Color3.fromRGB(122, 92, 68)
	local light = Color3.fromRGB(214, 190, 160)
	Kit.ellipsoid(model, "Body", V3(3.2, 3.4, 3), cf * CFrame.new(0, 1.7, 0), fur, M.Fabric)
	Kit.ellipsoid(model, "Belly", V3(2.2, 2.4, 1), cf * CFrame.new(0, 1.6, -1.2), light, M.Fabric)
	Kit.ball(model, "Head", 2.6, cf * CFrame.new(0, 4.1, 0), fur, M.Fabric)
	Kit.ellipsoid(
		model,
		"Mask",
		V3(2.2, 1, 0.6),
		cf * CFrame.new(0, 4.05, -1.05),
		Color3.fromRGB(46, 34, 30),
		M.Fabric
	)
	for _, side in { -1, 1 } do
		Kit.ball(
			model,
			"Eye",
			0.42,
			cf * CFrame.new(side * 0.5, 4.15, -1.38),
			Color3.fromRGB(255, 220, 120),
			M.Neon
		)
		Kit.ball(
			model,
			"Ear",
			0.8,
			cf * CFrame.new(side * 0.9, 5.25, 0),
			Color3.fromRGB(46, 34, 30),
			M.Fabric
		)
	end
	Kit.ellipsoid(model, "Snout", V3(0.9, 0.6, 0.7), cf * CFrame.new(0, 3.75, -1.4), light, M.Fabric)
	Kit.ball(model, "Nose", 0.35, cf * CFrame.new(0, 3.85, -1.78), Palette.Black, M.SmoothPlastic)
	-- A leaf on its head: an old shapeshifter's charm
	Kit.ellipsoid(
		model,
		"Leaf",
		V3(1.4, 0.15, 0.8),
		cf * CFrame.new(0.2, 5.5, -0.2) * CFrame.Angles(0, rad(30), rad(15)),
		Color3.fromRGB(96, 140, 70),
		M.Grass
	)
	Kit.deco(model, "Apron", V3(2.4, 1.6, 0.2), cf * CFrame.new(0, 1.3, -1.6), Palette.Noren, M.Fabric)
end

local function buildShop(parent: Instance, rng: any)
	local folder = PartKit.folder(parent, "Shop")
	local cf = facingEast(Layout.ShopPosition)
	local building, floorY = Kit.building(folder, cf, 20, 15, 8, {
		name = "ShopHouse",
		open = { front = true },
		plinth = 1,
		roofHeight = 5.5,
		overhang = 2.6,
	})
	local _ = building
	-- Counter (players interact here)
	local counter = Kit.part(
		folder,
		"Counter",
		V3(14, 3, 2.2),
		cf * CFrame.new(0, floorY + 1.5, -4.5),
		Palette.Wood,
		M.WoodPlanks
	)
	Kit.part(
		folder,
		"CounterTop",
		V3(14.4, 0.3, 2.6),
		cf * CFrame.new(0, floorY + 3.15, -4.5),
		Palette.DarkWood,
		M.Wood
	)
	counter:SetAttribute("Interact", "Upgrades")
	-- Wares: jars, talisman bundles, charms
	for k = 0, 5 do
		local x = -6 + k * 2.4
		Kit.cylinder(
			folder,
			"Jar",
			1.1,
			1.3,
			cf * CFrame.new(x, floorY + 3.95, -4.4),
			Palette.StoneLight:Lerp(Palette.Lacquer, rng:NextNumber(0, 0.6)),
			M.SmoothPlastic,
			{ CanCollide = false }
		)
	end
	for k = 0, 2 do
		local shelf = cf * CFrame.new(0, floorY + 2 + k * 2, 6.6)
		Kit.part(folder, "Shelf", V3(16, 0.3, 1.6), shelf, Palette.Wood, M.Wood)
		for j = 0, 6 do
			local item = shelf * CFrame.new(-6.6 + j * 2.2, 0.75, 0)
			if (j + k) % 2 == 0 then
				Kit.deco(
					folder,
					"Talisman",
					V3(0.7, 1.2, 0.1),
					item * CFrame.new(0, 0, -0.4),
					Palette.Paper,
					M.SmoothPlastic
				)
				Kit.deco(
					folder,
					"Ink",
					V3(0.15, 0.8, 0.12),
					item * CFrame.new(0, 0, -0.45),
					Color3.fromRGB(180, 40, 50),
					M.Neon
				)
			else
				Kit.ball(
					folder,
					"Charm",
					0.9,
					item,
					Palette.Violet:Lerp(Palette.Lantern, rng:NextNumber(0, 1)),
					M.Neon,
					{ CanCollide = false, CastShadow = false }
				)
			end
		end
	end
	-- Noren curtains over the entrance
	for k = 0, 4 do
		Kit.deco(
			folder,
			"Noren",
			V3(2.6, 3, 0.1),
			cf * CFrame.new(-5.6 + k * 2.8, floorY + 6.3, -7.2),
			Palette.Noren,
			M.Fabric
		)
	end
	Kit.deco(
		folder,
		"NorenMark",
		V3(1.4, 1.4, 0.12),
		cf * CFrame.new(0, floorY + 6.4, -7.27) * CFrame.Angles(0, 0, rad(45)),
		Palette.NorenAccent,
		M.Neon
	)
	Kit.sign(
		folder,
		cf * CFrame.new(0, floorY + 9.6, -9.6),
		10,
		2.2,
		"TALISMAN SHOP",
		{ font = Enum.Font.Sarpanch, board = Palette.Black, color = Color3.fromRGB(255, 214, 150) }
	)
	for _, x in { -9.2, 9.2 } do
		Kit.paperLantern(folder, cf * CFrame.new(x, floorY + 9.6, -9.6), 1.2, nil, true)
	end
	buildShopkeeper(folder, cf * CFrame.new(0, floorY, -1.5))
end

local function buildPagoda(parent: Instance)
	local folder = PartKit.folder(parent, "Pagoda")
	local base = CFrame.new(Layout.PagodaPosition)
	Kit.part(folder, "Foundation", V3(20, 2, 20), base * CFrame.new(0, 1, 0), Palette.Stone, M.Slate)
	Kit.part(folder, "Foundation2", V3(17, 1.4, 17), base * CFrame.new(0, 2.7, 0), Palette.StoneDark, M.Slate)
	local y = 3.4
	for tier = 1, 5 do
		local w = 14 - tier * 1.5
		local h = if tier == 1 then 8 else 5.6
		Kit.part(folder, "Body", V3(w, h, w), base * CFrame.new(0, y + h / 2, 0), Palette.Lacquer, M.Wood)
		Kit.part(
			folder,
			"Balcony",
			V3(w + 1.2, 0.5, w + 1.2),
			base * CFrame.new(0, y + 0.25, 0),
			Palette.DarkWood,
			M.Wood
		)
		for _, side in { -1, 1 } do
			Kit.deco(
				folder,
				"Lattice",
				V3(w * 0.4, h * 0.5, 0.2),
				base * CFrame.new(0, y + h * 0.5, side * (w / 2 + 0.05)),
				Palette.Black,
				M.Wood
			)
			Kit.deco(
				folder,
				"Lattice",
				V3(0.2, h * 0.5, w * 0.4),
				base * CFrame.new(side * (w / 2 + 0.05), y + h * 0.5, 0),
				Palette.Black,
				M.Wood
			)
		end
		y += h
		local roofW = w + 9 - tier * 0.6
		Kit.roof(folder, base * CFrame.new(0, y, 0), roofW, roofW, 2.6, nil, true)
		Kit.roof(
			folder,
			base * CFrame.new(0, y, 0) * CFrame.Angles(0, rad(90), 0),
			roofW,
			roofW,
			2.6,
			nil,
			true
		)
		local glow = Kit.deco(
			folder,
			"TierLantern",
			V3(0.9, 1.2, 0.9),
			base * CFrame.new(roofW / 2 - 0.6, y - 0.6, roofW / 2 - 0.6),
			Palette.LanternPaper,
			M.Neon
		)
		if tier == 1 or tier == 3 then
			Kit.light(glow, Palette.LanternLight, 16, 1)
		end
		y += 2.4
	end
	-- Sōrin: the spire, with glowing rings
	Kit.cylinder(folder, "Spire", 0.9, 14, base * CFrame.new(0, y + 7, 0), Palette.Black, M.Metal)
	for k = 0, 6 do
		Kit.cylinder(
			folder,
			"SpireRing",
			2.4 - k * 0.15,
			0.35,
			base * CFrame.new(0, y + 2 + k * 1.4, 0),
			if k % 2 == 0 then Palette.VioletLight else Color3.fromRGB(196, 160, 80),
			if k % 2 == 0 then M.Neon else M.Metal,
			{ CanCollide = false }
		)
	end
	Kit.ball(
		folder,
		"SpireJewel",
		1.4,
		base * CFrame.new(0, y + 14.4, 0),
		Palette.Violet,
		M.Neon,
		{ CanCollide = false }
	)
end

function WestDistrict.build(map: Instance)
	local rng = Prng.new(909)
	local folder = PartKit.folder(map, "West")
	buildPlaza(folder, rng)
	buildDojo(map)
	buildShop(map, rng)
	buildPagoda(folder)
	-- Lanterns strung from the plaza toward the dojo and the shop
	Kit.lanternString(
		folder,
		Layout.WestPlaza + V3(-6, 9, -12),
		Layout.DojoYardCenter + V3(10, 9, 10),
		5,
		2,
		2
	)
	Kit.lanternString(folder, Layout.WestPlaza + V3(-6, 9, 12), Layout.ShopPosition + V3(16, 9, -6), 5, 2, 2)
	for _, p in { V3(-96, 0, -24), V3(-96, 0, 22) } do
		Kit.part(
			folder,
			"LanternPole",
			V3(0.6, 10, 0.6),
			CFrame.new(p + V3(0, 5, 0)),
			Palette.DarkWood,
			M.Wood
		)
	end
end

return WestDistrict
