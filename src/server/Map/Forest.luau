--!strict
-- The Cursed Forest: an enclosed combat ground north of the shrine, entered through a giant
-- broken torii. Twisted trees, ruined shrines, spider lilies and violet mist set the mood;
-- open clearings keep fights readable. Exposes Spawns (enemy spawn points) and Zone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Config.MapLayout)
local PartKit = require(ReplicatedStorage.Shared.Visuals.PartKit)
local Prng = require(ReplicatedStorage.Shared.Util.Prng)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local TerrainPlan = require(script.Parent.TerrainPlan)

local Forest = {}

local rad = math.rad
local V3 = Vector3.new
local M = Enum.Material

local CENTER = Layout.ForestZoneCenter
local SIZE = Layout.ForestZoneSize
local MIN_X, MAX_X = CENTER.X - SIZE.X / 2, CENTER.X + SIZE.X / 2
local MIN_Z, MAX_Z = CENTER.Z - SIZE.Z / 2, CENTER.Z + SIZE.Z / 2

local function ground(x: number, z: number): Vector3
	return V3(x, TerrainPlan.heightAt(x, z), z)
end

local function buildGate(parent: Instance, rng: any)
	local folder = PartKit.folder(parent, "BrokenGate")
	local g = Layout.ForestGate
	local cf = CFrame.lookAt(V3(g.X, 0, g.Z), V3(g.X, 0, g.Z - 10))
	local color = Color3.fromRGB(44, 24, 30)
	local h, w = 34, 22
	-- Left pillar whole, right pillar snapped and leaning
	Kit.cylinder(folder, "Pillar", 2.4, h, cf * CFrame.new(-w / 2, h / 2, 0), color, M.Wood)
	Kit.cylinder(folder, "Pillar", 2.4, h * 0.62, cf * CFrame.new(w / 2, h * 0.31, 0), color, M.Wood)
	Kit.cylinder(
		folder,
		"PillarBroken",
		2.4,
		h * 0.36,
		cf * CFrame.new(w / 2 + 1.2, h * 0.79, 0) * CFrame.Angles(0, 0, rad(-9)),
		color,
		M.Wood
	)
	for _, x in { -w / 2, w / 2 } do
		Kit.cylinder(folder, "Base", 3.2, 2.4, cf * CFrame.new(x, 1.2, 0), Palette.Black, M.Slate)
	end
	Kit.part(
		folder,
		"Nuki",
		V3(w * 1.15, 1.6, 1.4),
		cf * CFrame.new(0, h * 0.72, 0) * CFrame.Angles(0, 0, rad(-2)),
		color,
		M.Wood
	)
	-- Kasagi split in two, one half tilted down
	Kit.part(
		folder,
		"Kasagi",
		V3(w * 0.75, 2.2, 2.8),
		cf * CFrame.new(-w * 0.28, h * 0.94, 0) * CFrame.Angles(0, 0, rad(4)),
		color,
		M.Wood
	)
	Kit.part(
		folder,
		"Kasagi",
		V3(w * 0.62, 2.2, 2.8),
		cf * CFrame.new(w * 0.42, h * 0.86, 0) * CFrame.Angles(0, 0, rad(-14)),
		color,
		M.Wood
	)
	Kit.part(
		folder,
		"Shimaki",
		V3(w * 0.75, 1.2, 3),
		cf * CFrame.new(-w * 0.28, h * 0.94 + 1.6, 0) * CFrame.Angles(0, 0, rad(4)),
		Palette.Black,
		M.Slate
	)
	-- Violet energy bleeding from the fractures
	for _, p in { V3(w / 2, h * 0.62, 0), V3(w * 0.1, h * 0.92, 0), V3(-w / 2, h * 0.45, 0) } do
		local crack = Kit.deco(
			folder,
			"Fissure",
			V3(0.4, 4, 2.6),
			cf * CFrame.new(p) * CFrame.Angles(0, 0, rad(rng:NextNumber(-30, 30))),
			Palette.Violet,
			M.Neon
		)
		PartKit.particles(crack, {
			Color = ColorSequence.new(Palette.VioletLight, Palette.VioletDeep),
			Size = PartKit.sequence({ { 0, 0.5 }, { 1, 0 } }),
			Lifetime = NumberRange.new(1, 2),
			Rate = 5,
			Speed = NumberRange.new(0.5, 1.5),
		})
	end
	Kit.rope(
		folder,
		(cf * CFrame.new(-w / 2, h * 0.62, 0)).Position,
		(cf * CFrame.new(w / 2, h * 0.58, 0)).Position,
		4,
		0.9,
		12,
		Color3.fromRGB(120, 104, 84)
	)
	-- Violet flame braziers and a warning sign
	for _, x in { -16, 16 } do
		local p = cf * CFrame.new(x, 0, -2)
		Kit.part(folder, "BrazierStand", V3(2, 4, 2), p * CFrame.new(0, 2, 0), Palette.StoneDark, M.Slate)
		local fire = Kit.deco(
			folder,
			"BrazierFire",
			V3(1.6, 0.5, 1.6),
			p * CFrame.new(0, 4.3, 0),
			Palette.Violet,
			M.Neon
		)
		PartKit.particles(fire, {
			Texture = "rbxasset://textures/particles/fire_main.dds",
			Color = ColorSequence.new(Palette.VioletLight, Palette.VioletDeep),
			Size = PartKit.sequence({ { 0, 2 }, { 1, 0.4 } }),
			Transparency = PartKit.sequence({ { 0, 0.2 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.7, 1.1),
			Rate = 16,
			Speed = NumberRange.new(2, 4),
		})
		Kit.light(fire, Palette.Violet, 22, 1.8)
	end
	Kit.sign(
		folder,
		CFrame.lookAt(V3(g.X - 15, 0, g.Z + 10), V3(g.X, 0, g.Z + 30)) * CFrame.new(0, 3, 0),
		7,
		3,
		"CURSED FOREST\nCurses roam beyond this gate",
		{
			font = Enum.Font.GothamBold,
			board = Palette.AgedWood,
			color = Color3.fromRGB(60, 20, 30),
			stroke = 1,
			lightInfluence = 1,
		}
	)
end

local function buildEnclosure(parent: Instance, rng: any)
	local folder = PartKit.folder(parent, "Enclosure")
	local edges = {
		{ V3(MIN_X - 2, 0, MAX_Z + 2), V3(-13, 0, MAX_Z + 2) },
		{ V3(13, 0, MAX_Z + 2), V3(MAX_X + 2, 0, MAX_Z + 2) },
		{ V3(MAX_X + 2, 0, MAX_Z + 2), V3(MAX_X + 2, 0, MIN_Z - 2) },
		{ V3(MAX_X + 2, 0, MIN_Z - 2), V3(MIN_X - 2, 0, MIN_Z - 2) },
		{ V3(MIN_X - 2, 0, MIN_Z - 2), V3(MIN_X - 2, 0, MAX_Z + 2) },
	}
	for _, edge in edges do
		local a, b = edge[1], edge[2]
		local len = (b - a).Magnitude
		local n = math.ceil(len / 9)
		for k = 0, n - 1 do
			local p0, p1 = a:Lerp(b, k / n), a:Lerp(b, (k + 1) / n)
			local mid = (p0 + p1) / 2
			local h = rng:NextNumber(3.5, 6) * (if rng:NextNumber() < 0.15 then 0.45 else 1)
			-- Crumbling stone wall
			Kit.part(
				folder,
				"RuinWall",
				V3((p1 - p0).Magnitude + 0.5, h, 2.4),
				CFrame.lookAt(mid, mid + (b - a):Cross(V3(0, 1, 0))) * CFrame.new(0, h / 2 - 0.5, 0),
				Palette.StoneDark:Lerp(Palette.Moss, rng:NextNumber(0, 0.4)),
				M.Slate
			)
		end
		-- Invisible barrier above the wall keeps fights inside
		Kit.part(
			folder,
			"Barrier",
			V3(len + 4, 40, 2),
			CFrame.lookAt((a + b) / 2, (a + b) / 2 + (b - a):Cross(V3(0, 1, 0))) * CFrame.new(0, 20, 0),
			Palette.StoneDark,
			M.SmoothPlastic,
			{ Transparency = 1, CastShadow = false }
		)
	end
	-- Dense trees just outside the wall
	for _, edge in edges do
		local a, b = edge[1], edge[2]
		local outward = (b - a).Unit:Cross(V3(0, 1, 0))
		local len = (b - a).Magnitude
		for d = 6, len - 6, 15 do
			local p = a:Lerp(b, d / len) - outward * rng:NextNumber(5, 10)
			Kit.cursedTree(folder, ground(p.X, p.Z), rng:NextNumber(1.1, 1.6), rng)
		end
	end
end

local function buildInterior(parent: Instance, rng: any)
	local folder = PartKit.folder(parent, "Interior")
	-- Twisted trees, keeping clearings open for combat
	local clearings = {
		V3(0, 0, -128),
		V3(-40, 0, -160),
		V3(40, 0, -165),
		V3(0, 0, -200),
		V3(-45, 0, -225),
		V3(45, 0, -228),
	}
	local placed = 0
	for _ = 1, 300 do
		if placed >= 30 then
			break
		end
		local x = rng:NextNumber(MIN_X + 6, MAX_X - 6)
		local z = rng:NextNumber(MIN_Z + 6, MAX_Z - 6)
		local clear = math.abs(x) > 12 or z < MAX_Z - 30 -- keep the entrance lane open
		for _, c in clearings do
			if (V3(x, 0, z) - c).Magnitude < 17 then
				clear = false
			end
		end
		if clear then
			Kit.cursedTree(folder, ground(x, z), rng:NextNumber(0.8, 1.3), rng)
			placed += 1
		end
	end
	-- Ruined shrine at the far end
	local ruin = CFrame.lookAt(V3(0, 0, MIN_Z + 16), V3(0, 0, CENTER.Z))
	Kit.part(folder, "RuinPlinth", V3(18, 1.6, 12), ruin * CFrame.new(0, 0.8, 0), Palette.StoneDark, M.Slate)
	for _, x in { -7, -2, 7 } do
		local h = if x == -2 then 4 else 10
		Kit.part(
			folder,
			"RuinPillar",
			V3(1.2, h, 1.2),
			ruin * CFrame.new(x, 1.6 + h / 2, -4) * CFrame.Angles(0, 0, rad(rng:NextNumber(-6, 6))),
			Palette.DarkWood,
			M.Wood
		)
	end
	Kit.part(
		folder,
		"FallenRoof",
		V3(16, 1.2, 8),
		ruin * CFrame.new(1, 3.6, 1) * CFrame.Angles(rad(18), rad(10), rad(12)),
		Palette.RoofTile,
		M.Slate
	)
	local idol =
		Kit.part(folder, "CursedIdol", V3(2.2, 4, 2.2), ruin * CFrame.new(0, 3.6, 2), Palette.Black, M.Basalt)
	Kit.deco(
		folder,
		"IdolEye",
		V3(0.8, 0.5, 0.2),
		ruin * CFrame.new(0, 4.6, 0.85),
		Color3.fromRGB(255, 70, 110),
		M.Neon
	)
	PartKit.light(idol, Palette.Violet, 24, 1.6, false)
	-- Fallen lanterns, jizo, lilies and glowing mushrooms tell the forest's story
	for _ = 1, 8 do
		local x, z = rng:NextNumber(MIN_X + 10, MAX_X - 10), rng:NextNumber(MIN_Z + 10, MAX_Z - 20)
		local p = ground(x, z)
		if rng:NextNumber() < 0.5 then
			Kit.part(
				folder,
				"FallenLantern",
				V3(1.6, 5, 1.6),
				CFrame.new(p + V3(0, 0.8, 0)) * CFrame.Angles(rad(85), rad(rng:NextNumber(0, 360)), 0),
				Palette.StoneDark,
				M.Slate
			)
		else
			Kit.jizo(
				folder,
				CFrame.new(p) * CFrame.Angles(0, rad(rng:NextNumber(0, 360)), rad(rng:NextNumber(-10, 10)))
			)
		end
	end
	for _ = 1, 9 do
		local x, z = rng:NextNumber(MIN_X + 8, MAX_X - 8), rng:NextNumber(MIN_Z + 8, MAX_Z - 8)
		Kit.lilies(folder, ground(x, z), rng:NextNumber(2.5, 4.5), rng:NextInteger(5, 9), rng)
	end
	for _ = 1, 14 do
		local x, z = rng:NextNumber(MIN_X + 6, MAX_X - 6), rng:NextNumber(MIN_Z + 6, MAX_Z - 6)
		local p = ground(x, z)
		for k = 0, 2 do
			local off = V3(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5))
			local s = rng:NextNumber(0.6, 1.3)
			Kit.deco(
				folder,
				"MushroomStem",
				V3(0.3, s, 0.3),
				CFrame.new(p + off + V3(0, s / 2, 0)),
				Palette.Paper
			)
			Kit.ellipsoid(
				folder,
				"MushroomCap",
				V3(s * 1.4, s * 0.6, s * 1.4),
				CFrame.new(p + off + V3(0, s, 0)),
				Palette.Violet:Lerp(Palette.VioletLight, k / 3),
				M.Neon,
				{ CanCollide = false, CanQuery = false, CastShadow = false }
			)
		end
	end
	for _ = 1, 20 do
		local x, z = rng:NextNumber(MIN_X + 4, MAX_X - 4), rng:NextNumber(MIN_Z + 4, MAX_Z - 4)
		Kit.rock(
			folder,
			ground(x, z),
			rng:NextNumber(2, 5),
			rng,
			Palette.StoneDark:Lerp(Palette.Moss, rng:NextNumber(0, 0.5))
		)
	end
	-- Low violet mist drifting over the forest floor
	for _, c in clearings do
		local mist = Kit.deco(
			folder,
			"Mist",
			V3(34, 1, 34),
			CFrame.new(c + V3(0, 1.5, 0)),
			Palette.Violet,
			M.SmoothPlastic,
			{ Transparency = 1 }
		)
		PartKit.particles(mist, {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(120, 80, 170), Color3.fromRGB(60, 30, 90)),
			LightEmission = 0.2,
			Size = PartKit.sequence({ { 0, 6 }, { 1, 12 } }),
			Transparency = PartKit.sequence({ { 0, 1 }, { 0.3, 0.82 }, { 1, 1 } }),
			Lifetime = NumberRange.new(6, 9),
			Rate = 2.5,
			Speed = NumberRange.new(0.3, 0.8),
			SpreadAngle = Vector2.new(80, 10),
			Shape = Enum.ParticleEmitterShape.Box,
		})
	end
	-- A few hanging violet will-o'-wisps for light and navigation
	for _, c in clearings do
		local wisp = Kit.ball(
			folder,
			"Wisp",
			1.4,
			CFrame.new(c + V3(4, 11, 0)),
			Palette.VioletLight,
			M.Neon,
			{ CanCollide = false, CanQuery = false, CastShadow = false }
		)
		-- Every clearing is lit so fights stay readable.
		Kit.light(wisp, Color3.fromRGB(190, 150, 255), 42, 1.1)
	end
	return clearings
end

function Forest.build(map: Instance)
	local rng = Prng.new(666)
	local folder = PartKit.folder(map, "Forest")
	buildGate(folder, rng)
	buildEnclosure(folder, rng)
	local clearings = buildInterior(folder, rng)
	-- Spawn points scattered around the clearings
	local spawns = PartKit.folder(folder, "Spawns")
	for _, c in clearings do
		for k = 0, 2 do
			local a = rad(k * 120 + rng:NextNumber(0, 60))
			local p = ground(c.X + math.sin(a) * 8, c.Z + math.cos(a) * 8)
			Kit.deco(
				spawns,
				"Spawn",
				V3(1, 1, 1),
				CFrame.new(p),
				Palette.Violet,
				M.SmoothPlastic,
				{ Transparency = 1 }
			)
		end
	end
	-- Zone volume (documentation / debugging; logic uses MapLayout.inForest)
	Kit.deco(
		folder,
		"Zone",
		SIZE,
		CFrame.new(CENTER + V3(0, SIZE.Y / 2 - 10, 0)),
		Palette.Violet,
		M.SmoothPlastic,
		{ Transparency = 1, CanTouch = false }
	)
end

return Forest
