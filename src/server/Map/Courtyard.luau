--!strict
-- The Summoning Courtyard: a walled stone court east of the shrine with an inlaid ritual circle
-- (its rings are separate welded assemblies so clients can rotate them cheaply), an altar
-- where rituals are performed, a carved stele and violet braziers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Config.MapLayout)
local PartKit = require(ReplicatedStorage.Shared.Visuals.PartKit)
local Prng = require(ReplicatedStorage.Shared.Util.Prng)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)

local Courtyard = {}

local rad = math.rad
local V3 = Vector3.new
local M = Enum.Material

local SIZE = 68
local FLOOR_TOP = 1.2

local function ringAssembly(
	parent: Instance,
	name: string,
	center: Vector3,
	radius: number,
	count: number,
	color: Color3,
	thickness: number
): Model
	local model = PartKit.model(parent, name)
	local root =
		Kit.deco(model, "Root", V3(1, 0.2, 1), CFrame.new(center), color, M.Neon, { Transparency = 1 })
	model.PrimaryPart = root
	for i = 0, count - 1 do
		local a = i / count * math.pi * 2
		local len = 2 * math.pi * radius / count * 0.78
		local cf = CFrame.new(center + V3(math.sin(a) * radius, 0, -math.cos(a) * radius))
			* CFrame.Angles(0, -a, 0)
		local seg = Kit.deco(
			model,
			"Segment",
			V3(len, 0.14, thickness),
			cf,
			color,
			M.Neon,
			{ Anchored = false, CastShadow = false }
		)
		PartKit.weld(root :: BasePart, seg)
	end
	return model
end

local function addSegment(model: Model, root: BasePart, a: Vector3, b: Vector3, width: number, color: Color3)
	local seg = PartKit.blockBetween(model, a, b, width, 0.14, {
		Name = "Line",
		Color = color,
		Material = M.Neon,
		Anchored = false,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	PartKit.weld(root, seg)
end

local function buildCircle(parent: Instance, rng: any)
	local folder = PartKit.folder(parent, "Circle")
	local c = Layout.CourtyardCenter + V3(0, FLOOR_TOP - 1 + 0.08, 0)
	local y = c.Y
	Kit.cylinder(
		folder,
		"CircleBase",
		Layout.CircleRadius * 2 + 4,
		0.2,
		CFrame.new(c.X, y - 0.05, c.Z),
		Color3.fromRGB(30, 26, 38),
		M.Basalt,
		{ CanCollide = false }
	)
	ringAssembly(folder, "OuterRing", V3(c.X, y + 0.12, c.Z), Layout.CircleRadius, 56, Palette.Violet, 0.45)
	ringAssembly(
		folder,
		"MiddleRing",
		V3(c.X, y + 0.12, c.Z),
		Layout.CircleRadius - 2.6,
		44,
		Palette.VioletLight,
		0.25
	)

	-- Rotating sigil: hexagram, glyph marks and an inner eye
	local sigil = PartKit.model(folder, "Sigil")
	local root = Kit.deco(
		sigil,
		"Root",
		V3(1, 0.2, 1),
		CFrame.new(c.X, y + 0.14, c.Z),
		Palette.Violet,
		M.Neon,
		{ Transparency = 1 }
	) :: BasePart
	sigil.PrimaryPart = root
	local r = Layout.CircleRadius - 3.4
	for _, offset in { 0, 60 } do
		local pts = {}
		for k = 0, 2 do
			local a = rad(offset + k * 120)
			table.insert(pts, V3(c.X + math.sin(a) * r, y + 0.14, c.Z - math.cos(a) * r))
		end
		for k = 1, 3 do
			addSegment(sigil, root, pts[k], pts[k % 3 + 1], 0.32, Palette.Violet)
		end
	end
	for k = 0, 11 do
		local a = rad(k * 30 + 15)
		local p = V3(
			c.X + math.sin(a) * (Layout.CircleRadius - 1.3),
			y + 0.14,
			c.Z - math.cos(a) * (Layout.CircleRadius - 1.3)
		)
		local tangent = V3(math.cos(a), 0, math.sin(a))
		addSegment(sigil, root, p - tangent * 0.5, p + tangent * 0.5, 0.18, Palette.VioletLight)
		addSegment(
			sigil,
			root,
			p - tangent * 0.2 + V3(math.sin(a), 0, -math.cos(a)) * 0.5,
			p + tangent * 0.3 - V3(math.sin(a), 0, -math.cos(a)) * 0.4,
			0.14,
			Palette.VioletLight
		)
	end
	local inner = ringAssembly(folder, "InnerRing", V3(c.X, y + 0.14, c.Z), 4.2, 24, Palette.VioletLight, 0.3)
	local _ = inner
	Kit.cylinder(
		folder,
		"Eye",
		2.4,
		0.25,
		CFrame.new(c.X, y + 0.1, c.Z),
		Palette.Violet,
		M.Neon,
		{ CanCollide = false }
	)
	local beacon = Kit.deco(
		folder,
		"Beacon",
		V3(1, 1, 1),
		CFrame.new(c.X, y + 1.5, c.Z),
		Palette.Violet,
		M.Neon,
		{ Transparency = 1 }
	)
	PartKit.light(beacon, Palette.Violet, 26, 1.4, false)
	PartKit.particles(beacon, {
		Color = ColorSequence.new(Palette.VioletLight, Palette.Violet),
		Size = PartKit.sequence({ { 0, 0.3 }, { 1, 0 } }),
		Lifetime = NumberRange.new(2, 3.5),
		Rate = 10,
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(15, 15),
		Shape = Enum.ParticleEmitterShape.Disc,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})
	-- Standing stones around the circle
	for k = 0, 5 do
		local a = rad(k * 60 + 30)
		local p = V3(c.X + math.sin(a) * 19.5, FLOOR_TOP, c.Z - math.cos(a) * 19.5)
		local cf = CFrame.lookAt(p, V3(c.X, FLOOR_TOP, c.Z))
		local h = rng:NextNumber(5.5, 7.5)
		Kit.part(
			folder,
			"Monolith",
			V3(2.2, h, 1.4),
			cf * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, rad(rng:NextNumber(-3, 3))),
			Palette.StoneDark,
			M.Slate
		)
		Kit.deco(
			folder,
			"Rune",
			V3(0.25, h * 0.6, 0.1),
			cf * CFrame.new(0, h * 0.55, -0.72),
			Palette.Violet,
			M.Neon
		)
	end
end

local function brazier(parent: Instance, position: Vector3)
	local model = PartKit.model(parent, "Brazier")
	for k = 0, 2 do
		local a = rad(k * 120)
		PartKit.cylinderBetween(
			model,
			position + V3(math.sin(a) * 1.4, 0, math.cos(a) * 1.4),
			position + V3(math.sin(a) * 0.6, 3, math.cos(a) * 0.6),
			0.35,
			{ Name = "Leg", Color = Palette.Black, Material = M.Metal }
		)
	end
	local bowl =
		Kit.cylinder(model, "Bowl", 2.8, 1, CFrame.new(position + V3(0, 3.3, 0)), Palette.Black, M.Metal)
	local flame = Kit.deco(
		model,
		"Flame",
		V3(1.6, 0.4, 1.6),
		CFrame.new(position + V3(0, 3.9, 0)),
		Palette.Violet,
		M.Neon
	)
	PartKit.particles(flame, {
		Texture = "rbxasset://textures/particles/fire_main.dds",
		Color = ColorSequence.new(Palette.VioletLight, Palette.VioletDeep),
		Size = PartKit.sequence({ { 0, 1.6 }, { 1, 0.2 } }),
		Transparency = PartKit.sequence({ { 0, 0.15 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.6, 1),
		Rate = 18,
		Speed = NumberRange.new(2, 4),
		SpreadAngle = Vector2.new(8, 8),
	})
	PartKit.light(bowl, Palette.Violet, 18, 1.6, false)
end

local function buildWalls(parent: Instance, center: Vector3)
	local folder = PartKit.folder(parent, "Walls")
	local half = SIZE / 2
	local wallH = 6
	-- tsuijibei: plaster walls on a stone base with a little tiled roof
	local function wall(a: Vector3, b: Vector3)
		local mid = (a + b) / 2
		local cf = CFrame.lookAt(mid, mid + (b - a):Cross(V3(0, 1, 0)))
		local len = (b - a).Magnitude
		Kit.part(folder, "WallBase", V3(len, 1.6, 2), cf * CFrame.new(0, 0.8, 0), Palette.StoneDark, M.Slate)
		Kit.part(
			folder,
			"Wall",
			V3(len, wallH - 1.6, 1.4),
			cf * CFrame.new(0, 1.6 + (wallH - 1.6) / 2, 0),
			Palette.Plaster:Lerp(Palette.Stone, 0.25),
			M.Plaster
		)
		Kit.part(
			folder,
			"WallBand",
			V3(len, 0.4, 1.5),
			cf * CFrame.new(0, wallH - 0.9, 0),
			Palette.DarkWood,
			M.Wood
		)
		Kit.roof(folder, cf * CFrame.new(0, wallH, 0), len + 1, 3.4, 1.4, nil, false)
	end
	local y = 0
	local c = V3(center.X, y, center.Z)
	wall(c + V3(-half, 0, -half), c + V3(half, 0, -half))
	wall(c + V3(half, 0, -half), c + V3(half, 0, half))
	wall(c + V3(half, 0, half), c + V3(-half, 0, half))
	-- West side: two short walls either side of the gate
	wall(c + V3(-half, 0, half), c + V3(-half, 0, 9))
	wall(c + V3(-half, 0, -9), c + V3(-half, 0, -half))
	-- Gate: a roofed portal facing the shrine
	local gate = CFrame.lookAt(c + V3(-half, 0, 0), c + V3(-half - 10, 0, 0))
	for _, x in { -8, 8 } do
		Kit.part(
			folder,
			"GatePillar",
			V3(1.6, 15, 1.6),
			gate * CFrame.new(x, 7.5, 0),
			Palette.DarkWood,
			M.Wood
		)
		Kit.part(
			folder,
			"GateBase",
			V3(2.2, 0.8, 2.2),
			gate * CFrame.new(x, 0.4, 0),
			Palette.StoneDark,
			M.Slate
		)
	end
	Kit.part(folder, "GateBeam", V3(18, 1, 1.4), gate * CFrame.new(0, 14, 0), Palette.DarkWood, M.Wood)
	Kit.roof(folder, gate * CFrame.new(0, 15, 0), 23, 9, 4, nil, false)
	-- Plaque sits high on the beam so it never blocks the camera when walking through.
	Kit.sign(
		folder,
		gate * CFrame.new(0, 15.7, -4.7),
		7,
		1.4,
		"SUMMONING COURTYARD",
		{ font = Enum.Font.Sarpanch, color = Palette.VioletLight, board = Palette.Black }
	)
	for _, x in { -6.5, 6.5 } do
		Kit.paperLantern(folder, gate * CFrame.new(x, 13.6, -1.6), 1.2, nil, x > 0)
	end
	-- Lantern strings across the court
	for _, z in { -18, 14 } do
		Kit.lanternString(folder, c + V3(-half + 1, wallH + 1, z), c + V3(half - 1, wallH + 1, z), 7, 2.4, 3)
	end
end

local function buildAltar(parent: Instance)
	local folder = PartKit.folder(parent, "Altar")
	local p = Layout.AltarPosition
	local cf = CFrame.lookAt(V3(p.X, 0, p.Z), V3(Layout.CourtyardCenter.X, 0, p.Z))
	-- Dais with steps toward the circle
	Kit.part(folder, "Dais", V3(13, 2.4, 9), cf * CFrame.new(0, 1.2, 1), Palette.Stone, M.Slate)
	Kit.steps(
		folder,
		cf * CFrame.new(0, 0, -3.5 - 2 * 1.2) * CFrame.Angles(0, rad(180), 0),
		9,
		2.4,
		2,
		1.2,
		Palette.StoneLight
	)
	Kit.part(folder, "Table", V3(7, 2.6, 3), cf * CFrame.new(0, 3.7, 1.5), Palette.LacquerDark, M.Wood)
	Kit.deco(
		folder,
		"Cloth",
		V3(7.2, 0.15, 3.2),
		cf * CFrame.new(0, 5.05, 1.5),
		Palette.NorenAccent,
		M.Fabric
	)
	for _, x in { -2.6, -1.2, 1.2, 2.6 } do
		Kit.deco(
			folder,
			"Candle",
			V3(0.3, 0.9, 0.3),
			cf * CFrame.new(x, 5.6, 1.9),
			Palette.LanternPaper,
			M.Neon
		)
	end
	Kit.deco(
		folder,
		"Offering",
		V3(1.6, 1.2, 1.2),
		cf * CFrame.new(0, 5.7, 1.4),
		Palette.Paper,
		M.SmoothPlastic
	)
	local anchor = Kit.deco(
		folder,
		"PromptAnchor",
		V3(2, 2, 2),
		cf * CFrame.new(0, 5, -0.5),
		Palette.Violet,
		M.Neon,
		{ Transparency = 1 }
	)
	local _ = anchor
	-- The stele: a tall carved stone that marks the courtyard from afar
	local stele = cf * CFrame.new(0, 2.4, 5.2)
	Kit.part(folder, "Stele", V3(4.4, 17, 1.8), stele * CFrame.new(0, 8.5, 0), Palette.StoneDark, M.Slate)
	Kit.part(folder, "SteleCap", V3(5.4, 1.2, 2.4), stele * CFrame.new(0, 17.4, 0), Palette.Black, M.Slate)
	Kit.wedge(
		folder,
		"SteleCrown",
		V3(5.4, 1.6, 1.2),
		stele * CFrame.new(0, 18.8, -0.6),
		Palette.Black,
		M.Slate,
		false
	)
	Kit.wedge(
		folder,
		"SteleCrown",
		V3(5.4, 1.6, 1.2),
		stele * CFrame.new(0, 18.8, 0.6) * CFrame.Angles(0, rad(180), 0),
		Palette.Black,
		M.Slate,
		false
	)
	Kit.deco(
		folder,
		"SteleRune",
		V3(0.35, 13, 0.12),
		stele * CFrame.new(0, 8.6, -0.92),
		Palette.Violet,
		M.Neon
	)
	for k = 0, 4 do
		Kit.deco(
			folder,
			"SteleGlyph",
			V3(1.6, 0.25, 0.12),
			stele * CFrame.new(0, 3.5 + k * 2.6, -0.92),
			Palette.VioletLight,
			M.Neon
		)
	end
	-- Nobori banners
	for _, x in { -8.5, 8.5 } do
		local pole = cf * CFrame.new(x, 0, 3)
		Kit.part(
			folder,
			"BannerPole",
			V3(0.35, 15, 0.35),
			pole * CFrame.new(0, 7.5, 0),
			Palette.Black,
			M.Wood
		)
		Kit.deco(folder, "Banner", V3(2.6, 9, 0.1), pole * CFrame.new(0, 9.4, -0.3), Palette.Noren, M.Fabric)
		Kit.deco(
			folder,
			"BannerMark",
			V3(0.5, 6.5, 0.12),
			pole * CFrame.new(0, 9.6, -0.38),
			Palette.Violet,
			M.Neon
		)
	end
end

function Courtyard.build(map: Instance)
	local rng = Prng.new(404)
	local folder = PartKit.folder(map, "Courtyard")
	local center = Layout.CourtyardCenter
	-- Paved floor
	Kit.part(
		folder,
		"Floor",
		V3(SIZE, FLOOR_TOP, SIZE),
		CFrame.new(center.X, FLOOR_TOP / 2, center.Z),
		Palette.StoneDark,
		M.Slate
	)
	for k = -2, 2 do
		Kit.deco(
			folder,
			"Joint",
			V3(SIZE - 2, 0.06, 0.25),
			CFrame.new(center.X, FLOOR_TOP + 0.02, center.Z + k * 13),
			Palette.Black,
			M.Slate
		)
		Kit.deco(
			folder,
			"Joint",
			V3(0.25, 0.06, SIZE - 2),
			CFrame.new(center.X + k * 13, FLOOR_TOP + 0.02, center.Z),
			Palette.Black,
			M.Slate
		)
	end
	-- Entry ramp from the ring road
	Kit.wedge(
		folder,
		"Ramp",
		V3(16, FLOOR_TOP, 4),
		CFrame.new(center.X - SIZE / 2 - 2, FLOOR_TOP / 2, center.Z) * CFrame.Angles(0, rad(-90), 0),
		Palette.StoneDark,
		M.Slate
	)
	buildCircle(folder, rng)
	buildWalls(folder, center)
	buildAltar(folder)
	for _, offset in { V3(-21, 0, -21), V3(21, 0, -21), V3(-21, 0, 21), V3(21, 0, 21) } do
		brazier(folder, V3(center.X, FLOOR_TOP, center.Z) + offset)
	end
	-- Benches for onlookers along the north and south walls
	for _, z in { -28, 24 } do
		for _, x in { -18, -6, 6 } do
			local b = CFrame.new(center.X + x, FLOOR_TOP, center.Z + z)
			Kit.part(folder, "Bench", V3(7, 0.5, 2), b * CFrame.new(0, 1.6, 0), Palette.Wood, M.WoodPlanks)
			for _, lx in { -3, 3 } do
				Kit.part(
					folder,
					"BenchLeg",
					V3(0.5, 1.4, 1.6),
					b * CFrame.new(lx, 0.7, 0),
					Palette.DarkWood,
					M.Wood
				)
			end
		end
	end
	for _, corner in { V3(-30, 0, -30), V3(30, 0, -30), V3(-30, 0, 30), V3(30, 0, 30) } do
		Kit.stoneLantern(folder, CFrame.new(V3(center.X, FLOOR_TOP, center.Z) + corner), 1, true)
	end
end

return Courtyard
