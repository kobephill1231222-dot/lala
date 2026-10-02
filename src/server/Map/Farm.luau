--!strict
-- One player farm ("Your Farm"). Built in farm-local space (see Config/FarmLayout): the
-- front (-Z) faces the plaza through a torii gate; inside are the Crate Pads (front-left),
-- ten production slots either side of the collection lane, the Orb Box at the lane's end
-- and the Collect Pad in front of it. Everything is sized for a 5-stud avatar.
--
-- Names here are a contract with FarmService and the client: Sign/SignGui/Title, Slots/SlotN
-- (Ring, Lock), Pads/PadN (Ring, Lock), Lane/Belt/Slat, OrbBox/Fill/LabelAnchor, CollectPad,
-- StatsBoard/BoardGui.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Config.FarmLayout)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local PartKit = require(ReplicatedStorage.Shared.Visuals.PartKit)
local Prng = require(ReplicatedStorage.Shared.Util.Prng)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)

local Farm = {}

local V3 = Vector3.new
local rad = math.rad
local M = Enum.Material

local W, D = Layout.FarmWidth, Layout.FarmDepth

-- A tablet with a paper seal: shown on slots and pads you haven't unlocked yet.
local function lockTablet(parent: BasePart, cf: CFrame, scale: number)
	local tablet = Kit.part(
		parent,
		"Lock",
		V3(3.2, 4.2, 0.8) * scale,
		cf * CFrame.new(0, 2.1 * scale, 0),
		Palette.StoneDark,
		M.Slate,
		{
			CanCollide = false,
		}
	)
	Kit.deco(
		tablet,
		"Seal",
		V3(1.1, 3.0, 0.1) * scale,
		cf * CFrame.new(0, 2.2 * scale, -0.45 * scale),
		Palette.Paper
	)
	Kit.deco(
		tablet,
		"Ink",
		V3(0.3, 2.0, 0.12) * scale,
		cf * CFrame.new(0, 2.3 * scale, -0.47 * scale),
		Color3.fromRGB(190, 40, 52),
		M.Neon
	)
	Kit.deco(
		tablet,
		"Cap",
		V3(3.6, 0.5, 1.1) * scale,
		cf * CFrame.new(0, 4.4 * scale, 0),
		Palette.Black,
		M.Slate
	)
end

local function buildSlot(folder: Instance, chutes: Instance, index: number, floor: CFrame, slot: number)
	local local_ = Layout.slotLocalCFrame(slot)
	local cf = floor * local_
	local size = Layout.SlotSize
	local plate = Kit.part(
		folder,
		"Slot" .. slot,
		V3(size, 0.5, size),
		cf * CFrame.new(0, 0.25, 0),
		Palette.Tatami,
		M.Fabric
	)
	plate:SetAttribute("Slot", slot)
	plate:SetAttribute("Farm", index)
	Kit.part(
		plate,
		"Ring",
		V3(size + 1, 0.3, size + 1),
		cf * CFrame.new(0, 0.15, 0),
		Color3.fromRGB(255, 214, 120),
		M.Neon,
		{
			CanCollide = false,
		}
	)
	-- Dark timber frame on the plate edges
	for _, side in { -1, 1 } do
		Kit.deco(
			plate,
			"Frame",
			V3(size, 0.18, 0.5),
			cf * CFrame.new(0, 0.55, side * (size / 2 - 0.25)),
			Palette.DarkWood,
			M.Wood
		)
		Kit.deco(
			plate,
			"Frame",
			V3(0.5, 0.18, size),
			cf * CFrame.new(side * (size / 2 - 0.25), 0.55, 0),
			Palette.DarkWood,
			M.Wood
		)
	end
	-- Number plaque at the outer edge (behind the sorcerer)
	local plaque = Kit.part(
		plate,
		"Number",
		V3(2.2, 1.4, 0.3),
		cf * CFrame.new(0, 1.2, size / 2 - 0.3) * CFrame.Angles(0, rad(180), 0),
		Palette.Black,
		M.Wood,
		{
			CanCollide = false,
		}
	)
	Kit.label(plaque, tostring(slot), { color = Palette.Gold, font = Enum.Font.FredokaOne, pps = 30 })
	-- Chute from the slot to the lane rail: the orb's path into the lane
	local inner = local_.Position.X > 0
	local side = if inner then -1 else 1
	local laneEdge = Layout.LaneWidth / 2 + 1.2
	local slotEdge = math.abs(local_.Position.X) - size / 2
	local length = slotEdge - laneEdge
	local mid = (slotEdge + laneEdge) / 2
	local z = local_.Position.Z
	local chute = floor * CFrame.new(-side * mid, 0, z)
	Kit.part(chutes, "Chute", V3(length, 1.2, 3), chute * CFrame.new(0, 0.6, 0), Palette.DarkWood, M.Wood)
	Kit.deco(
		chutes,
		"ChuteGlow",
		V3(length, 0.15, 1.6),
		chute * CFrame.new(0, 1.25, 0),
		Palette.VioletLight,
		M.Neon,
		{
			Transparency = 0.3,
		}
	)
	lockTablet(plate, cf * CFrame.new(0, 0.5, 0), 1.2)
end

local function buildPad(folder: Instance, index: number, floor: CFrame, pad: number)
	local cf = floor * Layout.padLocalCFrame(pad)
	local base =
		Kit.cylinder(folder, "Pad" .. pad, 9, 0.6, cf * CFrame.new(0, 0.3, 0), Palette.StoneLight, M.Slate)
	base:SetAttribute("Pad", pad)
	base:SetAttribute("Farm", index)
	Kit.cylinder(
		base,
		"Ring",
		10.2,
		0.3,
		cf * CFrame.new(0, 0.15, 0),
		Color3.fromRGB(255, 214, 120),
		M.Neon,
		{
			CanCollide = false,
		}
	)
	-- Four little posts with shimenawa rope: a ritual dais for opening crates
	for i = 0, 3 do
		local a = rad(45 + i * 90)
		local p = cf * CFrame.new(math.cos(a) * 5.2, 0, math.sin(a) * 5.2)
		Kit.cylinder(
			base,
			"Post",
			0.5,
			2.4,
			p * CFrame.new(0, 1.2, 0),
			Palette.Lacquer,
			M.Wood,
			{ CanCollide = false }
		)
		Kit.deco(base, "Cap", V3(0.7, 0.25, 0.7), p * CFrame.new(0, 2.5, 0), Palette.Gold, M.Metal)
	end
	lockTablet(base, cf * CFrame.new(0, 0.6, 0), 1.0)
end

local function buildLane(parent: Instance, floor: CFrame)
	local lane = PartKit.model(parent, "Lane")
	local z0, z1 = Layout.LaneEnd.Z, Layout.LaneStart.Z
	local length = z1 - z0
	local midZ = (z0 + z1) / 2
	local top = Layout.LaneHeight
	local width = Layout.LaneWidth
	Kit.part(
		lane,
		"Base",
		V3(width + 2, top - 0.2, length + 2),
		floor * CFrame.new(0, (top - 0.2) / 2, midZ),
		Palette.DarkWood,
		M.Wood
	)
	local belt = Kit.part(
		lane,
		"Belt",
		V3(width, 0.2, length),
		floor * CFrame.new(0, top - 0.1, midZ),
		Color3.fromRGB(62, 50, 74),
		M.SmoothPlastic
	)
	belt:SetAttribute("Length", length)
	-- Slats the client scrolls toward the Orb Box: the lane visibly moves.
	local slats = PartKit.folder(lane, "Slats")
	local spacing = 4
	for i = 0, math.floor(length / spacing) - 1 do
		local slat = Kit.deco(
			slats,
			"Slat",
			V3(width - 0.2, 0.12, 0.6),
			floor * CFrame.new(0, top + 0.06, z0 + 1 + i * spacing),
			Palette.VioletLight,
			M.Neon,
			{
				Transparency = 0.25,
				CastShadow = false,
			}
		)
		slat:SetAttribute("Offset", 1 + i * spacing)
	end
	-- Rails: lacquered sides with a gold cap
	for _, side in { -1, 1 } do
		local x = side * (width / 2 + 0.5)
		Kit.part(
			lane,
			"Rail",
			V3(1, 1.4, length + 2),
			floor * CFrame.new(x, top + 0.5, midZ),
			Palette.Lacquer,
			M.Wood
		)
		Kit.deco(
			lane,
			"RailCap",
			V3(1.2, 0.2, length + 2.2),
			floor * CFrame.new(x, top + 1.3, midZ),
			Palette.Gold,
			M.Metal
		)
	end
	-- Back end cap and front lip
	Kit.part(
		lane,
		"EndCap",
		V3(width + 3, 2.4, 1.2),
		floor * CFrame.new(0, top + 0.2, z1 + 1.2),
		Palette.Lacquer,
		M.Wood
	)
	Kit.part(
		lane,
		"Lip",
		V3(width + 2, 0.6, 2),
		floor * CFrame.new(0, top - 0.1, z0 - 0.8),
		Palette.Gold,
		M.Metal
	)
	-- Stone lanterns at the start of the lane
	for _, side in { -1, 1 } do
		Kit.stoneLantern(lane, floor * CFrame.new(side * 6.5, 0, z1 + 3), 1.25, true)
	end
	return lane
end

local function buildOrbBox(parent: Instance, index: number, floor: CFrame)
	local box = PartKit.model(parent, "OrbBox")
	local center = floor * CFrame.new(Layout.BoxPosition)
	local bw, bh, bd = 12, 6.5, 10
	local wall = 0.8
	local baseY = 0.8
	Kit.part(
		box,
		"Plinth",
		V3(bw + 2, baseY, bd + 2),
		center * CFrame.new(0, baseY / 2, 0),
		Palette.StoneLight,
		M.Slate
	)
	Kit.part(
		box,
		"Bottom",
		V3(bw, 0.6, bd),
		center * CFrame.new(0, baseY + 0.3, 0),
		Palette.LacquerDark,
		M.Wood
	)
	local wallY = baseY + bh / 2
	-- Back and sides
	Kit.part(
		box,
		"Wall",
		V3(bw, bh, wall),
		center * CFrame.new(0, wallY, bd / 2 - wall / 2),
		Palette.Lacquer,
		M.Wood
	)
	for _, side in { -1, 1 } do
		Kit.part(
			box,
			"Wall",
			V3(wall, bh, bd),
			center * CFrame.new(side * (bw / 2 - wall / 2), wallY, 0),
			Palette.Lacquer,
			M.Wood
		)
	end
	-- Front: a lower lacquer band with a glass window above it so the fill level shows
	Kit.part(
		box,
		"Wall",
		V3(bw, 1.6, wall),
		center * CFrame.new(0, baseY + 0.8, -bd / 2 + wall / 2),
		Palette.Lacquer,
		M.Wood
	)
	Kit.part(
		box,
		"Window",
		V3(bw - 1.6, bh - 2.4, 0.4),
		center * CFrame.new(0, baseY + 1.6 + (bh - 2.4) / 2, -bd / 2 + 0.4),
		Color3.fromRGB(220, 230, 255),
		M.Glass,
		{
			Transparency = 0.55,
			CastShadow = false,
		}
	)
	Kit.part(
		box,
		"Wall",
		V3(bw, 0.8, wall),
		center * CFrame.new(0, baseY + bh - 0.4, -bd / 2 + wall / 2),
		Palette.Lacquer,
		M.Wood
	)
	-- Gold corner posts and rim
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			Kit.part(
				box,
				"Corner",
				V3(1.2, bh + 0.6, 1.2),
				center * CFrame.new(x * bw / 2, baseY + (bh + 0.6) / 2, z * bd / 2),
				Palette.Gold,
				M.Metal
			)
		end
	end
	for _, z in { -1, 1 } do
		Kit.deco(
			box,
			"Rim",
			V3(bw + 0.6, 0.35, 0.9),
			center * CFrame.new(0, baseY + bh + 0.1, z * (bd / 2 - 0.2)),
			Palette.Gold,
			M.Metal
		)
	end
	for _, x in { -1, 1 } do
		Kit.deco(
			box,
			"Rim",
			V3(0.9, 0.35, bd + 0.6),
			center * CFrame.new(x * (bw / 2 - 0.2), baseY + bh + 0.1, 0),
			Palette.Gold,
			M.Metal
		)
	end
	-- The glowing pile of Cursed Orbs inside. The client resizes it with the box contents.
	local fill = Kit.part(
		box,
		"Fill",
		V3(bw - 2 * wall - 0.2, 0.3, bd - 2 * wall - 0.2),
		center * CFrame.new(0, baseY + 0.75, 0),
		Palette.Violet,
		M.Neon,
		{
			CanCollide = false,
			CastShadow = false,
		}
	)
	fill:SetAttribute("BaseY", baseY + 0.6)
	fill:SetAttribute("MaxHeight", bh - 1.0)
	Kit.light(fill, Palette.Violet, 14, 1.2)
	-- Name board on the front
	local board = Kit.part(
		box,
		"NameBoard",
		V3(7, 1.3, 0.3),
		center * CFrame.new(0, baseY + 0.8, -bd / 2 - 0.1),
		Palette.Black,
		M.Wood,
		{
			CanCollide = false,
		}
	)
	Kit.label(board, "ORB BOX", { color = Palette.Gold, font = Enum.Font.FredokaOne, pps = 30 })
	-- Where the client hangs the "Orb Box 37 / 60" label
	Kit.part(
		box,
		"LabelAnchor",
		V3(1, 1, 1),
		center * CFrame.new(0, baseY + bh + 4, 0),
		Palette.Black,
		M.SmoothPlastic,
		{
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		}
	)
	box:SetAttribute("Farm", index)
	return box
end

local function buildCollectPad(parent: Instance, index: number, floor: CFrame)
	local cf = floor * CFrame.new(Layout.CollectPoint)
	local pad = Kit.cylinder(
		parent,
		"CollectPad",
		8,
		0.3,
		cf * CFrame.new(0, 0.15, 0),
		Color3.fromRGB(255, 220, 130),
		M.Neon,
		{
			CanTouch = true,
			Transparency = 0.15,
		}
	)
	pad:SetAttribute("TouchAction", "Collect")
	pad:SetAttribute("Farm", index)
	Kit.cylinder(parent, "CollectPadRim", 9.4, 0.25, cf * CFrame.new(0, 0.12, 0), Palette.StoneLight, M.Slate)
	return pad
end

local function buildStatsBoard(parent: Instance, floor: CFrame)
	-- A notice board facing the entrance path: Orbs per Second, Cash/s and the Orb Box.
	local cf = floor * CFrame.new(16, 0, -50) * CFrame.Angles(0, rad(-20), 0)
	local model = PartKit.model(parent, "StatsBoardStand")
	for _, side in { -1, 1 } do
		Kit.cylinder(model, "Post", 0.8, 9, cf * CFrame.new(side * 5.2, 4.5, 0), Palette.DarkWood, M.Wood)
	end
	local board = Kit.part(
		model,
		"StatsBoard",
		V3(10, 5.4, 0.4),
		cf * CFrame.new(0, 6, 0),
		Palette.AgedWood,
		M.WoodPlanks
	)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.3
	gui.Parent = board
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = gui
	for i, line in
		{
			{ "Title", "FARM STATS" },
			{ "Ops", "Orbs per Second: 0" },
			{ "Income", "Cash: $0/s" },
			{ "Box", "Orb Box: 0 / 60" },
		}
	do
		local label = Instance.new("TextLabel")
		label.Name = line[1]
		label.LayoutOrder = i
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0.22, 0)
		label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
		label.TextScaled = true
		label.Text = line[2]
		label.TextColor3 = if i == 1 then Palette.Lacquer else Palette.Black
		label.Parent = gui
	end
	Kit.part(model, "Roof", V3(11.6, 0.5, 2), cf * CFrame.new(0, 9.1, 0), Palette.RoofTile, M.Slate)
	return board
end

local function buildDecor(parent: Instance, index: number, floor: CFrame)
	local decor = PartKit.model(parent, "Decor")
	local rng: any = Prng.new(1000 + index)
	local function at(x: number, y: number, z: number): CFrame
		return floor * CFrame.new(x, y, z)
	end
	-- Hedges along the sides and back (low, so the whole farm reads from the plaza)
	local hedgeH = 3.4
	for _, side in { -1, 1 } do
		Kit.part(
			decor,
			"Hedge",
			V3(2.6, hedgeH, D - 22),
			at(side * (W / 2 - 1.3), hedgeH / 2, 11),
			Palette.Hedge,
			M.Grass
		)
		-- Front corner hedges, leaving a wide open front
		Kit.part(
			decor,
			"Hedge",
			V3(16, hedgeH, 2.6),
			at(side * (W / 2 - 8), hedgeH / 2, -D / 2 + 1.3),
			Palette.Hedge,
			M.Grass
		)
	end
	Kit.part(decor, "Hedge", V3(W, hedgeH, 2.6), at(0, hedgeH / 2, D / 2 - 1.3), Palette.Hedge, M.Grass)
	-- Stone lanterns lining the entrance walk
	for _, z in { -56, -44 } do
		for _, side in { -1, 1 } do
			Kit.stoneLantern(decor, at(side * 7.5, 0, z), 1.3, true)
		end
	end
	-- Lantern strings across the lane
	for _, z in { -12, 16, 44 } do
		local a = (at(-10, 0, z)).Position
		local b = (at(10, 0, z)).Position
		for _, p in { a, b } do
			Kit.cylinder(
				decor,
				"LanternPole",
				0.7,
				13,
				CFrame.new(p + V3(0, 6.5, 0)),
				Palette.DarkWood,
				M.Wood
			)
		end
		Kit.lanternString(decor, a + V3(0, 12.5, 0), b + V3(0, 12.5, 0), 5, 1.4, 2)
	end
	-- Back-right pagoda: the farm's landmark on the skyline
	local pagoda = at(36, 0, 46)
	local model = PartKit.model(decor, "Pagoda")
	Kit.part(model, "Base", V3(16, 1.6, 16), pagoda * CFrame.new(0, 0.8, 0), Palette.StoneDark, M.Slate)
	local y = 1.6
	for tier = 1, 3 do
		local w = 12 - tier * 2
		local h = 5.5 - tier * 0.5
		Kit.part(
			model,
			"Story",
			V3(w, h, w),
			pagoda * CFrame.new(0, y + h / 2, 0),
			if tier == 1 then Palette.Plaster else Palette.Lacquer,
			M.Wood
		)
		Kit.roof(model, pagoda * CFrame.new(0, y + h, 0), w + 6, w + 6, 3.2, Palette.RoofTile, true)
		y += h + 3.2
	end
	Kit.cylinder(model, "Spire", 0.6, 7, pagoda * CFrame.new(0, y + 3.5, 0), Palette.Gold, M.Metal)
	for i = 1, 5 do
		Kit.cylinder(
			model,
			"SpireRing",
			1.4,
			0.3,
			pagoda * CFrame.new(0, y + 1 + i * 1.1, 0),
			Palette.Gold,
			M.Metal
		)
	end
	-- Back-left bamboo grove and a sakura tree
	Kit.bamboo(decor, at(-36, 0.4, 46).Position, rng, 22, 9, 16, 26)
	Kit.maple(decor, at(40, 0.4, -52).Position, 1.25, rng, Palette.Sakura)
	Kit.maple(decor, at(40, 0.4, 26).Position, 1.1, rng, Palette.SakuraDeep)
	-- Crate Pads sign
	Kit.sign(decor, at(-24, 7, -55) * CFrame.Angles(0, rad(-25), 0), 10, 2.4, "CRATE PADS", {
		color = Palette.Paper,
		font = Enum.Font.FredokaOne,
		board = Palette.Black,
	})
	for _, side in { -1, 1 } do
		Kit.cylinder(
			decor,
			"SignPost",
			0.5,
			7,
			at(-24, 3.5, -55) * CFrame.Angles(0, rad(-25), 0) * CFrame.new(side * 4.5, 0, 0.3),
			Palette.DarkWood,
			M.Wood
		)
	end
	-- Rocks and tufts for texture
	for _ = 1, 6 do
		local x = rng:NextNumber(-44, 44)
		local z = rng:NextNumber(48, 56)
		if math.abs(x) > 12 and math.abs(x - 36) > 10 and math.abs(x + 36) > 10 then
			Kit.rock(decor, at(x, 0.4, z).Position, rng:NextNumber(1.5, 3), rng, Palette.Stone)
		end
	end
	return decor
end

function Farm.build(parent: Instance, index: number): Model
	local floor = Layout.farmFloor(index)
	local model = PartKit.model(parent, "Farm" .. index)
	model:SetAttribute("FarmIndex", index)

	-- Ground: a raised gravel yard with a stone curb, and a paved entrance walk
	local h = Layout.FloorHeight
	Kit.part(model, "Floor", V3(W, h, D), floor * CFrame.new(0, -h / 2, 0), Palette.Gravel, M.Sand)
	for _, side in { -1, 1 } do
		Kit.part(
			model,
			"Curb",
			V3(1.6, h + 0.3, D),
			floor * CFrame.new(side * (W / 2 - 0.8), -h / 2 + 0.15, 0),
			Palette.StoneDark,
			M.Slate
		)
	end
	Kit.part(
		model,
		"Curb",
		V3(W, h + 0.3, 1.6),
		floor * CFrame.new(0, -h / 2 + 0.15, D / 2 - 0.8),
		Palette.StoneDark,
		M.Slate
	)
	Kit.part(
		model,
		"Walk",
		V3(12, 0.1, 20),
		floor * CFrame.new(0, 0.05, -50),
		Palette.PavingLight,
		M.Pavement
	)
	-- Paving under the slot rows
	for _, side in { -1, 1 } do
		Kit.part(
			model,
			"SlotYard",
			V3(16, 0.08, 70),
			floor * CFrame.new(side * Layout.SlotX, 0.04, 10),
			Palette.Paving,
			M.Pavement
		)
	end

	-- Entrance torii with the owner's sign
	local gate = floor * CFrame.new(Layout.Entrance)
	Kit.torii(model, gate, 23, 20, { rope = true, name = "Gate" })
	local sign =
		Kit.part(model, "Sign", V3(15, 3.4, 0.4), gate * CFrame.new(0, 14.6, -0.7), Palette.Black, M.Wood, {
			CanCollide = false,
		})
	Kit.label(sign, "Empty Farm", {
		guiName = "SignGui",
		labelName = "Title",
		color = Palette.Gold,
		font = Enum.Font.FredokaOne,
		pps = 30,
		stroke = 1,
	})
	Kit.label(sign, "Your Farm", {
		guiName = "BackGui",
		labelName = "Title",
		face = Enum.NormalId.Back,
		color = Palette.Gold,
		font = Enum.Font.FredokaOne,
		pps = 30,
		stroke = 1,
	})

	local slots = PartKit.folder(model, "Slots")
	local chutes = PartKit.folder(model, "Chutes")
	for slot = 1, GameConfig.SlotCount do
		buildSlot(slots, chutes, index, floor, slot)
	end
	local pads = PartKit.folder(model, "Pads")
	for pad = 1, GameConfig.PadCount do
		buildPad(pads, index, floor, pad)
	end
	buildLane(model, floor)
	buildOrbBox(model, index, floor)
	buildCollectPad(model, index, floor)
	buildStatsBoard(model, floor)
	buildDecor(model, index, floor)
	return model
end

return Farm
