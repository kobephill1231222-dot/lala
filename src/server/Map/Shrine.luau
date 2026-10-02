--!strict
-- The heart of the village: a stone terrace ringed by a moat, the giant fractured spirit tree,
-- the shrine hall in front of it, four arched bridges and the torii-lined approach that frames
-- the arrival view from the spawn plaza.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Config.MapLayout)
local PartKit = require(ReplicatedStorage.Shared.Visuals.PartKit)
local Prng = require(ReplicatedStorage.Shared.Util.Prng)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)

local Shrine = {}

local rad = math.rad
local V3 = Vector3.new
local M = Enum.Material

local BARK = Color3.fromRGB(64, 52, 62)
local BARK_DARK = Color3.fromRGB(44, 36, 46)

local function ringWall(
	parent: Instance,
	radius: number,
	bottom: number,
	top: number,
	thickness: number,
	segments: number,
	rng: any,
	color: Color3
)
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		local len = 2 * math.pi * radius / segments + 0.4
		local h = top - bottom + rng:NextNumber(-0.15, 0.15)
		local cf = CFrame.new(math.sin(a) * radius, bottom + h / 2, -math.cos(a) * radius)
			* CFrame.Angles(0, -a, 0)
		local shade = color:Lerp(Palette.StoneDark, rng:NextNumber(0, 0.35))
		Kit.part(parent, "Wall", V3(len, h, thickness), cf, shade, M.Slate)
	end
end

local function buildTerrace(parent: Instance, rng: any)
	local folder = PartKit.folder(parent, "Terrace")
	local y = Layout.TerraceY
	ringWall(folder, Layout.TerraceRadius + 0.6, -6, y + 0.5, 2.2, 52, rng, Palette.Stone)
	-- Low coping ring with a soft moss line
	ringWall(folder, Layout.TerraceRadius + 0.2, y + 0.4, y + 1.1, 1.4, 52, rng, Palette.StoneLight)
	ringWall(folder, Layout.MoatOuterRadius + 0.6, -6, 0.6, 2, 60, rng, Palette.StoneDark)

	-- Paved cross of flagstones linking the four bridges with the tree and hall
	for _, dir in { V3(0, 0, 1), V3(1, 0, 0), V3(-1, 0, 0), V3(0, 0, -1) } do
		for d = 18, 42, 3 do
			local p = dir * d
			local jitter = rng:NextNumber(-0.25, 0.25)
			local side = dir:Cross(V3(0, 1, 0))
			Kit.part(
				folder,
				"Flagstone",
				V3(8.4, 0.5, 2.7),
				CFrame.lookAt(V3(p.X, y + 0.2, p.Z), V3(p.X, y + 0.2, p.Z) + dir) * CFrame.new(jitter, 0, 0),
				Palette.StoneLight:Lerp(Palette.Stone, rng:NextNumber(0, 0.6)),
				M.Slate
			)
			local _ = side
		end
	end
	-- Ring path around the tree
	for i = 0, 35 do
		local a = i / 36 * math.pi * 2
		local r = 25
		Kit.part(
			folder,
			"Flagstone",
			V3(4.6, 0.5, 5.5),
			CFrame.new(math.sin(a) * r, y + 0.2, -math.cos(a) * r + Layout.TreeBase.Z)
				* CFrame.Angles(0, -a, 0),
			Palette.StoneLight:Lerp(Palette.Stone, rng:NextNumber(0, 0.6)),
			M.Slate
		)
	end
end

local function buildBridges(parent: Instance)
	local folder = PartKit.folder(parent, "Bridges")
	local outer, inner = Layout.MoatOuterRadius + 3, Layout.TerraceRadius - 1
	for _, dir in { V3(0, 0, 1), V3(1, 0, 0), V3(-1, 0, 0), V3(0, 0, -1) } do
		local a = dir * outer + V3(0, 0.6, 0)
		local b = dir * inner + V3(0, Layout.TerraceY + 0.4, 0)
		Kit.bridge(folder, a, b, if dir.Z == 1 then 11 else 9, 2.4, { segments = 12, supportBottom = -6 })
	end
end

-- The giant fractured spirit tree.
local function buildTree(parent: Instance, rng: any)
	local tree = PartKit.folder(parent, "SpiritTree")
	local base = Layout.TreeBase
	local trunkTop = 78

	-- Roots spreading over the terrace and spilling over its edge
	for i = 0, 9 do
		local a = rad(i * 36 + rng:NextNumber(-10, 10))
		local dir = V3(math.sin(a), 0, -math.cos(a))
		local p0 = base + dir * 6 + V3(0, 4, 0)
		local p1 = base + dir * rng:NextNumber(12, 15) + V3(0, 1.2, 0)
		local p2 = base + dir * rng:NextNumber(18, 24) + V3(0, -0.6, 0)
		PartKit.cylinderBetween(
			tree,
			p0,
			p1,
			rng:NextNumber(4, 5.2),
			{ Name = "Root", Color = BARK, Material = M.Wood }
		)
		PartKit.cylinderBetween(
			tree,
			p1,
			p2,
			rng:NextNumber(2.4, 3.2),
			{ Name = "Root", Color = BARK_DARK, Material = M.Wood }
		)
	end

	-- Trunk: tapered, gently twisting segments
	local segments = 9
	local previous = base + V3(0, -1, 0)
	local trunkPoints = { previous }
	for i = 1, segments do
		local t = i / segments
		local wobble = V3(math.sin(i * 1.7) * 1.6, 0, math.cos(i * 1.3) * 1.4)
		local p = base + V3(0, t * trunkTop, 0) + wobble * t
		local d = 19 - t * 9
		PartKit.cylinderBetween(tree, previous, p, d, {
			Name = "Trunk",
			Color = if i % 2 == 0 then BARK else BARK:Lerp(BARK_DARK, 0.4),
			Material = M.Wood,
		})
		-- Bark ridges
		for k = 0, 3 do
			local ang = rad(k * 90 + i * 23)
			local off = V3(math.sin(ang), 0, -math.cos(ang)) * (d / 2 - 0.2)
			PartKit.cylinderBetween(
				tree,
				previous + off,
				p + off,
				d * 0.18,
				{ Name = "Ridge", Color = BARK_DARK, Material = M.Wood, CanCollide = false, CanQuery = false }
			)
		end
		table.insert(trunkPoints, p)
		previous = p
	end

	-- The fracture: a jagged glowing seam up the south and north faces, with split bark
	-- plates drifting off it.
	local cracks = PartKit.folder(tree, "Fracture")
	for _, face in { 0, 180 } do
		local faceDir = V3(math.sin(rad(face)), 0, math.cos(rad(face)))
		local prevPoint: Vector3? = nil
		for i = 1, 16 do
			local t = i / 16
			local y = 6 + t * 66
			local d = 19 - (y / trunkTop) * 9
			local zig = if i % 2 == 0 then 1.4 else -1.4
			local side = faceDir:Cross(V3(0, 1, 0))
			local p = base + V3(0, y, 0) + faceDir * (d / 2 - 0.15) + side * zig
			if prevPoint then
				PartKit.blockBetween(cracks, prevPoint, p, 1.8, 1, {
					Name = "Crack",
					Color = Palette.VioletLight,
					Material = M.Neon,
					CanCollide = false,
					CanQuery = false,
					CastShadow = false,
				})
				PartKit.blockBetween(cracks, prevPoint - faceDir * 0.4, p - faceDir * 0.4, 4.2, 0.8, {
					Name = "CrackGlow",
					Color = Palette.Violet,
					Material = M.Neon,
					CanCollide = false,
					CanQuery = false,
					CastShadow = false,
					Transparency = 0.2,
				})
			end
			if i % 4 == 2 then
				local plate = p + faceDir * rng:NextNumber(2.5, 4.5) + side * rng:NextNumber(-3, 3)
				Kit.deco(
					cracks,
					"BarkShard",
					V3(rng:NextNumber(2.5, 4), rng:NextNumber(3, 6), 0.9),
					CFrame.lookAt(plate, plate + faceDir)
						* CFrame.Angles(rad(rng:NextNumber(-25, 25)), 0, rad(rng:NextNumber(-30, 30))),
					BARK,
					M.Wood
				)
			end
			prevPoint = p
		end
	end
	for _, y in { 16, 36, 56 } do
		local glow = Kit.deco(
			cracks,
			"CoreGlow",
			V3(1, 1, 1),
			CFrame.new(base + V3(0, y, 10)),
			Palette.Violet,
			M.Neon,
			{ Transparency = 1 }
		)
		PartKit.light(glow, Palette.Violet, 34, 2.2, false)
	end

	-- Shimenawa girdling the trunk
	local ropeY = 13
	local ropeR = 9.6
	local ring = {}
	for i = 0, 18 do
		local a = i / 18 * math.pi * 2
		table.insert(
			ring,
			base + V3(math.sin(a) * ropeR, ropeY + math.sin(i * 1.3) * 0.2, -math.cos(a) * ropeR)
		)
	end
	for i = 1, #ring - 1 do
		PartKit.cylinderBetween(
			tree,
			ring[i],
			ring[i + 1],
			1.5,
			{ Name = "Rope", Color = Palette.Rope, Material = M.Fabric, CanCollide = false, CanQuery = false }
		)
		if i % 2 == 0 then
			Kit.shide(tree, CFrame.lookAt(ring[i], base + V3(0, ropeY, 0)) * CFrame.new(0, -0.6, 0.4), 2.2)
		end
	end

	-- Limbs reaching out to the canopy clusters
	local canopy = PartKit.folder(tree, "Canopy")
	local trunkTip = trunkPoints[#trunkPoints]
	local clusterCenters = {}
	for i = 0, 5 do
		local a = rad(i * 60 + 25 + rng:NextNumber(-12, 12))
		local dir = V3(math.sin(a), 0, -math.cos(a))
		local startY = 52 + (i % 3) * 7
		local start = base + V3(0, startY, 0)
		local reach = rng:NextNumber(30, 40)
		local mid = start + dir * reach * 0.55 + V3(0, rng:NextNumber(12, 18), 0)
		local tip = start + dir * reach + V3(0, rng:NextNumber(24, 32), 0)
		PartKit.cylinderBetween(tree, start, mid, 6.5, { Name = "Limb", Color = BARK, Material = M.Wood })
		PartKit.cylinderBetween(
			tree,
			mid,
			tip,
			4,
			{ Name = "Limb", Color = BARK, Material = M.Wood, CanCollide = false }
		)
		table.insert(clusterCenters, tip)
	end
	table.insert(clusterCenters, trunkTip + V3(0, 26, 0))
	table.insert(clusterCenters, trunkTip + V3(10, 16, -8))
	table.insert(clusterCenters, trunkTip + V3(-12, 14, 6))

	-- Foliage: dark violet masses lit from within by spirit blossoms
	for _, c in clusterCenters do
		for k = 1, 6 do
			local off = V3(rng:NextNumber(-13, 13), rng:NextNumber(-5, 8), rng:NextNumber(-13, 13))
			local d = rng:NextNumber(22, 32)
			local color = Palette.SpiritLeaf:Lerp(Palette.SpiritLeafLight, rng:NextNumber(0, 0.6))
			-- Broad, layered cloud-pads rather than round balls: reads as one great spreading crown.
			Kit.ellipsoid(
				canopy,
				"Leaves",
				V3(d * 1.25, d * 0.55, d * 1.1),
				CFrame.new(c + off)
					* CFrame.Angles(0, rad(rng:NextNumber(0, 180)), rad(rng:NextNumber(-8, 8))),
				color,
				M.Grass,
				{ CanCollide = false, CanQuery = false }
			)
			-- Spirit blossoms dotted over the foliage surface
			for _ = 1, 3 do
				local dir = V3(rng:NextNumber(-1, 1), rng:NextNumber(-0.6, 0.8), rng:NextNumber(-1, 1)).Unit
				Kit.ball(
					canopy,
					"Blossom",
					rng:NextNumber(1.3, 2.3),
					CFrame.new(c + off + dir * V3(d * 0.6, d * 0.27, d * 0.55).Magnitude * 0.62),
					if k % 2 == 0 then Palette.VioletLight else Color3.fromRGB(255, 170, 230),
					M.Neon,
					{ CanCollide = false, CanQuery = false, CastShadow = false }
				)
			end
		end
		-- Hanging glowing tassels, like wisteria
		for _ = 1, 3 do
			local top = c + V3(rng:NextNumber(-14, 14), -rng:NextNumber(9, 13), rng:NextNumber(-14, 14))
			local len = rng:NextNumber(5, 9)
			for j = 0, 2 do
				Kit.ball(
					canopy,
					"Tassel",
					1.6 - j * 0.35,
					CFrame.new(top - V3(0, j * len / 3, 0)),
					Palette.Violet:Lerp(Palette.VioletLight, j / 3),
					M.Neon,
					{ CanCollide = false, CanQuery = false, CastShadow = false, Transparency = 0.1 }
				)
			end
			Kit.deco(
				canopy,
				"Strand",
				V3(0.25, len, 0.25),
				CFrame.new(top - V3(0, len / 2, 0)),
				Palette.VioletDeep,
				M.Neon,
				{ Transparency = 0.3 }
			)
		end
	end
	local canopyLight = Kit.deco(
		canopy,
		"CanopyGlow",
		V3(1, 1, 1),
		CFrame.new(base + V3(0, 94, 0)),
		Palette.Violet,
		M.Neon,
		{ Transparency = 1 }
	)
	PartKit.light(canopyLight, Palette.VioletLight, 60, 1.6, false)

	-- Falling spirit petals
	local petals = Kit.deco(
		canopy,
		"PetalEmitter",
		V3(76, 1, 76),
		CFrame.new(base + V3(0, 82, 0)),
		Palette.Violet,
		M.SmoothPlastic,
		{ Transparency = 1 }
	)
	PartKit.particles(petals, {
		Color = ColorSequence.new(Palette.VioletLight, Color3.fromRGB(255, 190, 230)),
		Size = PartKit.sequence({ { 0, 0.35 }, { 1, 0.25 } }),
		Transparency = PartKit.sequence({ { 0, 0.1 }, { 0.85, 0.3 }, { 1, 1 } }),
		Lifetime = NumberRange.new(9, 13),
		Rate = 7,
		Speed = NumberRange.new(1, 2),
		SpreadAngle = Vector2.new(60, 60),
		Acceleration = V3(0.6, -1.4, 0.3),
		RotSpeed = NumberRange.new(-90, 90),
		Rotation = NumberRange.new(0, 360),
		EmissionDirection = Enum.NormalId.Bottom,
	})

	-- Orbiting crystal shards (animated by the client)
	local shards = PartKit.folder(tree, "Shards")
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		local r = 15 + (i % 3) * 3
		local y = 22 + (i % 4) * 9
		local shard = Kit.wedge(
			shards,
			"Shard",
			V3(0.9, rng:NextNumber(2.6, 4.2), 1.6),
			CFrame.new(base + V3(math.sin(a) * r, y, -math.cos(a) * r))
				* CFrame.Angles(rad(rng:NextNumber(0, 360)), rad(rng:NextNumber(0, 360)), 0),
			Palette.VioletLight,
			M.Neon,
			false
		)
		shard:SetAttribute("OrbitRadius", r)
		shard:SetAttribute("OrbitHeight", y)
		shard:SetAttribute("OrbitPhase", a)
		shard.CastShadow = false
	end

	-- Sacred fence around the roots, open toward the hall
	local fencePts = {}
	for i = 0, 28 do
		local a = rad(200 + i * 11.5)
		table.insert(fencePts, base + V3(math.sin(a) * 21, 0, -math.cos(a) * 21))
	end
	Kit.fence(tree, fencePts, 2.6, Palette.DarkWood, 3.2)
	return tree
end

local function buildHall(parent: Instance, rng: any)
	local y = Layout.TerraceY
	local center = V3(0, y, 21)
	local cf = CFrame.lookAt(center, center + V3(0, 0, 1)) -- faces south, toward the arrival plaza
	local hall = Kit.building(parent, cf, 26, 13, 9, {
		name = "ShrineHall",
		open = { front = true, left = true, right = true },
		plinth = 1.6,
		wood = Palette.DarkWood,
		roofHeight = 8.5,
		overhang = 3.6,
	})
	-- Front steps
	Kit.steps(
		hall,
		cf * CFrame.new(0, 0, -6.5 - 3 * 1.2) * CFrame.Angles(0, rad(180), 0),
		10,
		2,
		3,
		1.2,
		Palette.Stone
	)
	-- Offering box, bell and the great rope across the front
	local floorY = 2
	Kit.part(
		hall,
		"OfferingBox",
		V3(5, 2, 2.4),
		cf * CFrame.new(0, floorY + 1, -4.6),
		Palette.Wood,
		M.WoodPlanks
	)
	Kit.deco(
		hall,
		"OfferingSlats",
		V3(5.1, 0.25, 2.5),
		cf * CFrame.new(0, floorY + 2.05, -4.6),
		Palette.Black,
		M.Wood
	)
	Kit.ball(
		hall,
		"Bell",
		1.6,
		cf * CFrame.new(0, floorY + 8.4, -5.6),
		Color3.fromRGB(196, 160, 80),
		M.Metal,
		{ CanCollide = false }
	)
	Kit.deco(
		hall,
		"BellRope",
		V3(0.4, 6, 0.4),
		cf * CFrame.new(0, floorY + 4.6, -5.6),
		Color3.fromRGB(170, 40, 50),
		M.Fabric
	)
	Kit.rope(
		hall,
		(cf * CFrame.new(-12, floorY + 9.3, -6.6)).Position,
		(cf * CFrame.new(12, floorY + 9.3, -6.6)).Position,
		1.6,
		1.4,
		12
	)
	-- Inner sanctum glow
	local altar = Kit.part(
		hall,
		"Altar",
		V3(8, 3, 2),
		cf * CFrame.new(0, floorY + 1.5, 4.5),
		Palette.LacquerDark,
		M.Wood
	)
	for _, x in { -3, 0, 3 } do
		local candle = Kit.deco(
			hall,
			"Candle",
			V3(0.35, 1, 0.35),
			cf * CFrame.new(x, floorY + 3.5, 4.5),
			Palette.LanternPaper,
			M.Neon
		)
		if x == 0 then
			Kit.light(candle, Palette.LanternLight, 14, 1.2)
		end
	end
	Kit.deco(
		hall,
		"Mirror",
		V3(2.2, 2.2, 0.3),
		cf * CFrame.new(0, floorY + 5.4, 5.4),
		Color3.fromRGB(200, 196, 220),
		M.Glass,
		{ Reflectance = 0.4 }
	)
	local _ = altar
	-- Hanging lanterns at the eaves
	for _, x in { -11, 11 } do
		Kit.paperLantern(hall, cf * CFrame.new(x, floorY + 11.3, -7.5), 1.3, nil, true)
	end
	local _ = rng
	return hall
end

local function buildTerraceDressing(parent: Instance, rng: any)
	local folder = PartKit.folder(parent, "TerraceDressing")
	local y = Layout.TerraceY
	-- Guardian lion-dogs flank the south landing
	for _, x in { -7.5, 7.5 } do
		Kit.komainu(folder, CFrame.lookAt(V3(x, y, 36), V3(x, y, 60)))
	end
	-- Stone lanterns around the terrace
	for i = 0, 7 do
		local a = rad(i * 45 + 22.5)
		local p = V3(math.sin(a) * 38, y, -math.cos(a) * 38)
		Kit.stoneLantern(folder, CFrame.lookAt(p, V3(0, y, 0)), 1.15, true)
	end
	-- Small sub-shrines east and west
	for _, x in { -31, 31 } do
		local p = V3(x, y, -2)
		local cf = CFrame.lookAt(p, V3(0, y, -2))
		Kit.building(
			folder,
			cf,
			8,
			6,
			5,
			{ name = "SubShrine", open = { front = true }, plinth = 1, roofHeight = 3.6, overhang = 1.6 }
		)
		Kit.torii(folder, cf * CFrame.new(0, 0, -8), 7, 5, { color = Palette.Lacquer })
	end
	-- Ema rack: wooden wish plaques left by villagers
	local rack = CFrame.lookAt(V3(17, y, 34), V3(17, y, 50))
	Kit.part(folder, "EmaRack", V3(8, 0.4, 0.4), rack * CFrame.new(0, 4.2, 0), Palette.DarkWood, M.Wood)
	for _, x in { -3.8, 3.8 } do
		Kit.part(folder, "EmaPost", V3(0.5, 4.4, 0.5), rack * CFrame.new(x, 2.2, 0), Palette.DarkWood, M.Wood)
	end
	for i = 0, 9 do
		local cf = rack
			* CFrame.new(-3.3 + i * 0.73, 3.5 + (i % 2) * 0.15, -0.25)
			* CFrame.Angles(0, 0, rad(rng:NextNumber(-8, 8)))
		Kit.deco(folder, "Ema", V3(0.65, 0.5, 0.06), cf, Palette.AgedWood:Lerp(Palette.Paper, 0.3), M.Wood)
	end
	-- A sakaki shrub pair by the hall
	for _, x in { -15, 15 } do
		Kit.ball(
			folder,
			"Shrub",
			4.5,
			CFrame.new(x, y + 1.8, 31),
			Palette.Pine,
			M.Grass,
			{ CanCollide = false }
		)
	end
end

-- The sandō approach from the plaza steps to the south bridge.
local function buildApproach(parent: Instance, rng: any)
	local folder = PartKit.folder(parent, "Approach")
	-- Flagstone path
	for z = 66, 150, 3 do
		local w = 8.5
		Kit.part(
			folder,
			"Flagstone",
			V3(w + rng:NextNumber(-0.3, 0.3), 0.5, 2.8),
			CFrame.new(rng:NextNumber(-0.2, 0.2), 0.15, z)
				* CFrame.Angles(0, rad(rng:NextNumber(-1.5, 1.5)), 0),
			Palette.StoneLight:Lerp(Palette.Stone, rng:NextNumber(0, 0.7)),
			M.Slate
		)
	end
	-- Gravel shoulders
	Kit.part(folder, "Gravel", V3(16, 0.3, 86), CFrame.new(0, 0.05, 108), Palette.Gravel, M.Pebble)
	-- Senbon torii tunnel
	for i = 0, 5 do
		local z = 142 - i * 8.5
		local t = Kit.torii(
			folder,
			CFrame.new(0, 0, z),
			11.5,
			9.5,
			{ name = "TunnelTorii", color = Palette.LacquerDark }
		)
		if i % 2 == 1 then
			Kit.paperLantern(t, CFrame.new(0, 11.2, z), 1, nil, i == 3)
		end
	end
	-- The great torii
	Kit.torii(
		folder,
		CFrame.new(0, 0, 86),
		27,
		19,
		{ name = "GreatTorii", color = Palette.Lacquer, plaque = "霊樹", rope = true }
	)
	-- Lantern rows
	for z = 70, 140, 14 do
		for _, x in { -9.5, 9.5 } do
			Kit.stoneLantern(folder, CFrame.lookAt(V3(x, 0, z), V3(0, 0, z)), 1, z % 28 == 0 or z < 100)
		end
	end
	-- Purification pavilion (chōzuya) beside the path
	local basinCf = CFrame.lookAt(V3(19, 0, 100), V3(0, 0, 100))
	Kit.part(folder, "Basin", V3(6, 2.4, 3), basinCf * CFrame.new(0, 1.2, 0), Palette.Stone, M.Slate)
	Kit.part(
		folder,
		"BasinWater",
		V3(5.2, 0.2, 2.2),
		basinCf * CFrame.new(0, 2.35, 0),
		Color3.fromRGB(60, 90, 120),
		M.Glass,
		{ Transparency = 0.3, CanCollide = false }
	)
	PartKit.cylinderBetween(
		folder,
		(basinCf * CFrame.new(-3.4, 3.6, 0)).Position,
		(basinCf * CFrame.new(-1.5, 3.2, 0)).Position,
		0.5,
		{ Name = "Spout", Color = Palette.Bamboo, Material = M.SmoothPlastic }
	)
	for _, p in { V3(-3.5, 0, -2.2), V3(3.5, 0, -2.2), V3(-3.5, 0, 2.2), V3(3.5, 0, 2.2) } do
		Kit.part(
			folder,
			"Post",
			V3(0.6, 7.5, 0.6),
			basinCf * CFrame.new(p + V3(0, 3.75, 0)),
			Palette.DarkWood,
			M.Wood
		)
	end
	Kit.roof(folder, basinCf * CFrame.new(0, 7.5, 0), 10, 7, 3, nil, true)
end

local function buildPlaza(parent: Instance, rng: any)
	local folder = PartKit.folder(parent, "SpawnPlaza")
	local y = Layout.SpawnY
	local c = V3(0, y, 182)
	Kit.cylinder(folder, "PlazaFloor", 46, 2, CFrame.new(c - V3(0, 1, 0)), Palette.StoneDark, M.Slate)
	Kit.cylinder(folder, "PlazaInlay", 24, 0.3, CFrame.new(c + V3(0, 0.05, -4)), Palette.Stone, M.Slate)
	Kit.cylinder(
		folder,
		"PlazaRune",
		24.6,
		0.2,
		CFrame.new(c + V3(0, 0.02, -4)),
		Palette.VioletDeep,
		M.Neon,
		{ CanCollide = false, Transparency = 0.35 }
	)
	Kit.cylinder(
		folder,
		"PlazaCore",
		3.2,
		0.35,
		CFrame.new(c + V3(0, 0.1, -4)),
		Palette.VioletDeep,
		M.Neon,
		{ CanCollide = false }
	)
	-- Retaining ring wall
	for i = 0, 31 do
		local a = (i + 0.5) / 32 * math.pi * 2
		if not (a > math.pi * 0.86 and a < math.pi * 1.14) then -- opening to the north stairs
			local r = 23.4
			local cf = CFrame.new(c.X + math.sin(a) * r, y - 2.5, c.Z - math.cos(a) * r)
				* CFrame.Angles(0, -a, 0)
			Kit.part(
				folder,
				"PlazaWall",
				V3(4.8, 6.4, 1.6),
				cf,
				Palette.Stone:Lerp(Palette.StoneDark, rng:NextNumber(0, 0.4)),
				M.Slate
			)
			if i % 4 == 0 then
				Kit.stoneLantern(
					folder,
					CFrame.new(c.X + math.sin(a) * (r - 2.5), y, c.Z - math.cos(a) * (r - 2.5)),
					0.9,
					true
				)
			end
		end
	end
	-- Stairs down to the approach
	Kit.steps(folder, CFrame.new(0, 0, 150) * CFrame.Angles(0, rad(180), 0), 12, y, 7, 1.5, Palette.Stone)
	-- Spawn point (invisible so the stone medallion shows through)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ArrivalSpawn"
	spawn.Size = V3(8, 1, 8)
	spawn.CFrame = CFrame.new(Layout.SpawnPosition - V3(0, 0.5, 0)) -- LookVector north: players arrive facing the tree
	spawn.Anchored = true
	spawn.Transparency = 1
	spawn.CanCollide = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = folder
	-- Welcome board and guide
	local boardCf = CFrame.lookAt(V3(17, y, 188), V3(0, y, 182))
	Kit.part(folder, "BoardPost", V3(0.7, 9, 0.7), boardCf * CFrame.new(-4, 4.5, 0), Palette.DarkWood, M.Wood)
	Kit.part(folder, "BoardPost", V3(0.7, 9, 0.7), boardCf * CFrame.new(4, 4.5, 0), Palette.DarkWood, M.Wood)
	Kit.sign(
		folder,
		boardCf * CFrame.new(0, 6.2, -0.1),
		9,
		4,
		"CURSEBOUND\nFARM",
		{ font = Enum.Font.Sarpanch, color = Color3.fromRGB(236, 210, 255), name = "TitleBoard" }
	)
	Kit.sign(
		folder,
		boardCf * CFrame.new(0, 2.7, -0.1),
		7.6,
		2.4,
		"Shrine N  -  Courtyard E  -  Dojo & Shop W\nCursed Forest beyond the shrine",
		{ font = Enum.Font.GothamMedium, color = Palette.Paper, name = "GuideBoard" }
	)
	Kit.roof(folder, boardCf * CFrame.new(0, 9, 0), 11, 3, 1.4, nil, false)
	-- Flanking pines frame the view north
	Kit.pine(folder, V3(-17, y, 168), 1.25, rng)
	Kit.pine(folder, V3(17, y, 168), 1.15, rng)
end

function Shrine.build(map: Instance)
	local rng = Prng.new(77)
	local folder = PartKit.folder(map, "Shrine")
	buildTerrace(folder, rng)
	buildBridges(folder)
	buildTree(folder, rng)
	buildHall(folder, rng)
	buildTerraceDressing(folder, rng)
	buildApproach(folder, rng)
	buildPlaza(map, rng)
end

return Shrine
