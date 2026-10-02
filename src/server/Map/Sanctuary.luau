--!strict
-- A player sanctuary: a raised gravel court behind a small torii, a Spirit Well at its heart,
-- ten training pedestals around it (sealed with rope until unlocked) and a little shrine
-- house. Names here are a contract with PlotService (Spots/SpotN/Anchor, Well/Core, Sign...).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Layout = require(ReplicatedStorage.Shared.Config.MapLayout)
local PartKit = require(ReplicatedStorage.Shared.Visuals.PartKit)
local Prng = require(ReplicatedStorage.Shared.Util.Prng)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)

local Sanctuary = {}

local rad = math.rad
local V3 = Vector3.new
local M = Enum.Material

local HALF = Layout.PlotSize / 2
local FLOOR = Layout.PlotY + Layout.PlotFloorHeight -- local height of the gravel above the ground

local function buildPlinth(model: Model, ground: CFrame, rng: any)
	Kit.part(
		model,
		"Plinth",
		V3(Layout.PlotSize, FLOOR - 0.4, Layout.PlotSize),
		ground * CFrame.new(0, (FLOOR - 0.4) / 2, 0),
		Palette.Stone,
		M.Slate
	)
	Kit.part(
		model,
		"Gravel",
		V3(Layout.PlotSize - 2, 0.4, Layout.PlotSize - 2),
		ground * CFrame.new(0, FLOOR - 0.2, 0),
		Palette.Gravel,
		M.Pebble
	)
	-- Stone coping, broken at the gate
	for _, side in { "back", "left", "right" } do
		local cf = if side == "back"
			then ground * CFrame.new(0, FLOOR + 0.4, HALF - 0.8)
			elseif side == "left" then ground * CFrame.new(-HALF + 0.8, FLOOR + 0.4, 0) * CFrame.Angles(
				0,
				rad(90),
				0
			)
			else ground * CFrame.new(HALF - 0.8, FLOOR + 0.4, 0) * CFrame.Angles(0, rad(90), 0)
		Kit.part(model, "Coping", V3(Layout.PlotSize, 0.8, 1.6), cf, Palette.StoneLight, M.Slate)
		-- Low stone wall with a wooden cap
		Kit.part(
			model,
			"Wall",
			V3(Layout.PlotSize - 4, 2.2, 1.2),
			cf * CFrame.new(0, 1.5, 0),
			Palette.Stone:Lerp(Palette.StoneDark, rng:NextNumber(0, 0.3)),
			M.Slate
		)
		Kit.part(
			model,
			"WallCap",
			V3(Layout.PlotSize - 4, 0.4, 1.6),
			cf * CFrame.new(0, 2.8, 0),
			Palette.DarkWood,
			M.Wood
		)
	end
	for _, x in { -1, 1 } do
		local cf = ground * CFrame.new(x * (HALF / 2 + 4), FLOOR + 0.4, -HALF + 0.8)
		Kit.part(model, "Coping", V3(HALF - 8, 0.8, 1.6), cf, Palette.StoneLight, M.Slate)
		-- Open wooden fence either side of the gate
		local a = (ground * CFrame.new(x * 8, FLOOR + 0.8, -HALF + 0.8)).Position
		local b = (ground * CFrame.new(x * (HALF - 1), FLOOR + 0.8, -HALF + 0.8)).Position
		Kit.fence(model, { a, b }, 2.6, Palette.DarkWood, 3.4)
	end
	-- Corner pillars topped with lanterns
	for _, corner in { V3(-1, 0, -1), V3(1, 0, -1), V3(-1, 0, 1), V3(1, 0, 1) } do
		local p = ground * CFrame.new(corner.X * (HALF - 1.4), FLOOR + 0.8, corner.Z * (HALF - 1.4))
		Kit.part(
			model,
			"CornerPillar",
			V3(2.4, 3.2, 2.4),
			p * CFrame.new(0, 1.6, 0),
			Palette.StoneDark,
			M.Slate
		)
		Kit.stoneLantern(model, p * CFrame.new(0, 3.2, 0), 0.75, corner.Z < 0)
	end
	-- Entrance stairs
	Kit.steps(
		model,
		ground * CFrame.new(0, 0, -HALF - 5 * 1.3) * CFrame.Angles(0, rad(180), 0),
		13,
		FLOOR,
		5,
		1.3,
		Palette.StoneLight
	)
end

local function buildGate(model: Model, ground: CFrame)
	local gate = ground * CFrame.new(0, FLOOR, -HALF + 1.5)
	Kit.torii(model, gate, 13, 11, { color = Palette.Lacquer })
	-- Ward: a glowing threshold line that lights up when the sanctuary is claimed
	Kit.deco(
		model,
		"Ward",
		V3(11, 0.12, 0.9),
		gate * CFrame.new(0, 0.08, 0),
		Palette.Violet,
		M.Neon,
		{ Transparency = 1 }
	)
	-- Owner sign on its own post beside the gate
	local post = gate * CFrame.new(8.8, 0, -3)
	Kit.part(model, "SignPost", V3(0.6, 7.4, 0.6), post * CFrame.new(0, 3.7, 0), Palette.DarkWood, M.Wood)
	local board = Kit.part(
		model,
		"Sign",
		V3(6.4, 2.4, 0.35),
		post * CFrame.new(0, 6, -0.45) * CFrame.Angles(0, rad(180), 0),
		Palette.DarkWood,
		M.Wood
	)
	local label = Kit.label(board, "Vacant Sanctuary", {
		font = Enum.Font.Sarpanch,
		color = Color3.fromRGB(236, 214, 255),
		labelName = "OwnerLabel",
		face = Enum.NormalId.Back,
	})
	local _ = label
	Kit.roof(model, post * CFrame.new(0, 7.4, -0.4), 7.4, 2, 1, nil, false)
	Kit.paperLantern(model, post * CFrame.new(-3.6, 7.2, -0.6), 0.8, nil, false)
end

local function buildWell(model: Model, floor: CFrame, rng: any)
	local well = PartKit.model(model, "Well")
	local c = floor * CFrame.new(Layout.WellOffset)
	-- Octagonal basin
	for k = 0, 7 do
		local a = rad(k * 45)
		local cf = c * CFrame.Angles(0, a, 0) * CFrame.new(0, 1.1, -3.7)
		Kit.part(well, "Basin", V3(3.3, 2.2, 1.1), cf, Palette.StoneDark, M.Slate)
		Kit.part(well, "Rim", V3(3.5, 0.35, 1.4), cf * CFrame.new(0, 1.25, 0), Palette.StoneLight, M.Slate)
	end
	local core = Kit.cylinder(
		well,
		"Core",
		7,
		0.3,
		c * CFrame.new(0, 1.7, 0),
		Palette.Violet,
		M.Neon,
		{ CanCollide = false }
	)
	Kit.cylinder(
		well,
		"Depth",
		7.2,
		1.2,
		c * CFrame.new(0, 1, 0),
		Palette.VioletDeep,
		M.Neon,
		{ CanCollide = false }
	)
	PartKit.light(core, Palette.Violet, 18, 1.5, false)
	PartKit.particles(core, {
		Color = ColorSequence.new(Palette.VioletLight, Palette.Violet),
		Size = PartKit.sequence({ { 0, 0.35 }, { 1, 0 } }),
		Lifetime = NumberRange.new(1.5, 2.5),
		Rate = 6,
		Speed = NumberRange.new(1.5, 3),
		SpreadAngle = Vector2.new(20, 20),
		Shape = Enum.ParticleEmitterShape.Disc,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})
	-- Floating fractured crystal (animated by clients)
	local crystal = PartKit.model(well, "Crystal")
	local crystalRoot = Kit.deco(
		crystal,
		"Root",
		V3(0.5, 0.5, 0.5),
		c * CFrame.new(0, 5.2, 0),
		Palette.Violet,
		M.Neon,
		{ Transparency = 1 }
	)
	crystal.PrimaryPart = crystalRoot
	for k = 0, 4 do
		local shard = Kit.wedge(
			crystal,
			"Shard",
			V3(0.8, rng:NextNumber(1.6, 2.6), 1.1),
			c
				* CFrame.new(0, 5.2, 0)
				* CFrame.Angles(rad(k * 72), rad(k * 50), rad(k * 30))
				* CFrame.new(0, 0.6, 0),
			Palette.VioletLight,
			M.Neon,
			false
		)
		shard.Anchored = false
		shard.CastShadow = false
		PartKit.weld(crystalRoot, shard)
	end
	-- Four posts with a sacred rope around the well
	local corners = {}
	for k = 0, 3 do
		local a = rad(k * 90 + 45)
		local p = c * CFrame.new(math.sin(a) * 6.2, 0, -math.cos(a) * 6.2)
		Kit.part(well, "RopePost", V3(0.6, 5, 0.6), p * CFrame.new(0, 2.5, 0), Palette.DarkWood, M.Wood)
		table.insert(corners, (p * CFrame.new(0, 4.4, 0)).Position)
	end
	for k = 1, 4 do
		Kit.rope(well, corners[k], corners[k % 4 + 1], 0.8, 0.45, 4)
	end
	-- Touch sensor for collecting and an anchor for the client's display
	Kit.cylinder(well, "Sensor", 10, 7, c * CFrame.new(0, 3.5, 0), Palette.Violet, M.SmoothPlastic, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = true,
		CastShadow = false,
	})
	Kit.deco(
		well,
		"Display",
		V3(1, 1, 1),
		c * CFrame.new(0, 8.6, 0),
		Palette.Violet,
		M.SmoothPlastic,
		{ Transparency = 1 }
	)
end

local function buildSpots(model: Model, floor: CFrame)
	local folder = PartKit.folder(model, "Spots")
	for spot = 1, GameConfig.SpotCount do
		local spotModel = PartKit.model(folder, "Spot" .. spot)
		spotModel:SetAttribute("SpotIndex", spot)
		local cf = floor * Layout.spotLocalCFrame(spot)
		Kit.cylinder(spotModel, "Pedestal", 7, 1, cf * CFrame.new(0, 0.5, 0), Palette.Stone, M.Slate)
		Kit.cylinder(
			spotModel,
			"Ring",
			7.7,
			0.25,
			cf * CFrame.new(0, 0.85, 0),
			Color3.fromRGB(60, 56, 66),
			M.Slate,
			{ CanCollide = false }
		)
		Kit.cylinder(spotModel, "Cap", 6.2, 0.3, cf * CFrame.new(0, 1.05, 0), Palette.StoneLight, M.Slate)
		Kit.deco(
			spotModel,
			"Number",
			V3(1.2, 0.05, 1.2),
			cf * CFrame.new(0, 1.22, 2.3),
			Palette.StoneDark,
			M.Slate
		)
		Kit.deco(
			spotModel,
			"Anchor",
			V3(1, 0.2, 1),
			cf * CFrame.new(0, 1.2, 0),
			Palette.Violet,
			M.SmoothPlastic,
			{ Transparency = 1 }
		)
		-- Seal: four stakes, a rope and a paper ward. Hidden once the spot is unlocked.
		local seal = PartKit.model(spotModel, "Seal")
		local stakes = {}
		for k = 0, 3 do
			local a = rad(k * 90 + 45)
			local p = cf * CFrame.new(math.sin(a) * 3.6, 0, -math.cos(a) * 3.6)
			Kit.deco(seal, "Stake", V3(0.35, 3, 0.35), p * CFrame.new(0, 1.5, 0), Palette.DarkWood, M.Wood)
			table.insert(stakes, (p * CFrame.new(0, 2.6, 0)).Position)
		end
		for k = 1, 4 do
			PartKit.cylinderBetween(seal, stakes[k], stakes[k % 4 + 1], 0.3, {
				Name = "Rope",
				Color = Palette.Rope,
				Material = M.Fabric,
				CanCollide = false,
				CanQuery = false,
				CastShadow = false,
			})
		end
		Kit.deco(
			seal,
			"Ofuda",
			V3(1.1, 1.8, 0.08),
			cf * CFrame.new(0, 2.6, 0),
			Palette.Paper,
			M.SmoothPlastic
		)
		Kit.deco(
			seal,
			"OfudaInk",
			V3(0.2, 1.4, 0.1),
			cf * CFrame.new(0, 2.6, 0),
			Color3.fromRGB(200, 40, 60),
			M.Neon
		)
	end
end

local function buildHouse(model: Model, floor: CFrame, rng: any)
	local cf = floor * CFrame.new(0, 0, HALF - 9) -- faces the gate (local -Z)
	local house, houseFloor = Kit.building(model, cf, 15, 9, 6.5, {
		name = "ShrineHouse",
		open = { front = true },
		plinth = 1.2,
		roofHeight = 4.6,
		overhang = 2,
	})
	Kit.part(
		house,
		"Altar",
		V3(5, 1.6, 1.4),
		cf * CFrame.new(0, houseFloor + 0.8, 3),
		Palette.LacquerDark,
		M.Wood
	)
	local flame = Kit.deco(
		house,
		"Candle",
		V3(0.3, 0.8, 0.3),
		cf * CFrame.new(0, houseFloor + 2, 3),
		Palette.LanternPaper,
		M.Neon
	)
	Kit.light(flame, Palette.LanternLight, 10, 0.9)
	Kit.steps(
		house,
		cf * CFrame.new(0, 0, -4.5 - 2 * 1.1) * CFrame.Angles(0, rad(180), 0),
		5,
		houseFloor,
		2,
		1.1,
		Palette.StoneLight
	)
	-- Garden corners: a pine and a maple
	Kit.pine(model, (floor * CFrame.new(-HALF + 7, 0, HALF - 6)).Position, 0.7, rng)
	Kit.maple(model, (floor * CFrame.new(HALF - 7, 0, HALF - 6)).Position, 0.62, rng)
	-- Raked gravel arcs on either side of the entrance
	for _, x in { -1, 1 } do
		for k = 0, 2 do
			Kit.deco(
				model,
				"Rake",
				V3(7, 0.06, 0.2),
				floor * CFrame.new(x * 22, 0.02, -25 + k * 1.2) * CFrame.Angles(0, rad(x * 10), 0),
				Palette.StoneLight,
				M.Pebble
			)
		end
	end
end

function Sanctuary.build(parent: Instance, index: number): Model
	local rng = Prng.new(5000 + index)
	local model = PartKit.model(parent, "Sanctuary" .. index)
	model:SetAttribute("PlotIndex", index)
	local ground = Layout.plotCFrame(index) * CFrame.new(0, -Layout.PlotY, 0)
	local floor = Layout.plotFloorCFrame(index)
	buildPlinth(model, ground, rng)
	buildGate(model, ground)
	buildWell(model, floor, rng)
	buildSpots(model, floor)
	buildHouse(model, floor, rng)
	PartKit.folder(model, "Units")
	return model
end

return Sanctuary
