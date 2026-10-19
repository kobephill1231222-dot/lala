--!strict
-- The prototype's world: one compact training courtyard with a single training post (a
-- Sorcerer facing a training dummy), the farm's Reward Chest with its Collect pad, and a
-- review board with test switches. Built from parts by the same code in Studio and in the
-- offline bake (tools/lune/prototype.luau), so the place opens with everything in place.
--
-- Names the server and client rely on (Workspace.TrainingCourtyard):
--   Post            Model; the server writes the hit schedule onto its attributes
--     Spot          invisible part where the Sorcerer stands (feet, facing the dummy)
--     Sorcerer      the jointed rig (Prototype.Rig)
--   Dummy           Model; Base (anchored) + Body on Motor6D "Spring", HitPoint attachment
--   Chest           Model; Body (anchored), Lid on Motor6D "Hinge", Gold, Label, Prompt
--   CollectPad      touch to collect (TouchAction = "Collect")
--   ReviewBoard     FastPrompt and FillPrompt (review switches)
--   Spawn           SpawnLocation

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PartKit = require(Shared.Visuals.PartKit)
local Prng = require(Shared.Util.Prng)
local Sorcerers = require(Shared.Config.Sorcerers)
local Prototype = ReplicatedStorage:WaitForChild("Prototype")
local Rig = require(Prototype.Rig)
local PrototypeConfig = require(Prototype.PrototypeConfig)
local Map = script.Parent.Parent:WaitForChild("Map")
local Kit = require(Map.Kit)
local Palette = require(Map.Palette)

local Courtyard = {}

local V3 = Vector3.new
local rad = math.rad
local M = Enum.Material

Courtyard.Name = "TrainingCourtyard"

local DECK_Y = 0.5
-- The Sorcerer faces the dummy along this frame; it's turned so that a player arriving from
-- the spawn sees the Sorcerer's front and striking arm at three-quarter view.
Courtyard.SorcererCFrame = CFrame.new(-2.6, DECK_Y, -3.2) * CFrame.Angles(0, rad(-105), 0)
-- Where the palm lands at contact, in the Sorcerer's frame (measured from the rig's pose).
local DUMMY_OFFSET = CFrame.new(0.9, 0, -5.55) * CFrame.Angles(0, math.pi, 0)
Courtyard.DummyCFrame = Courtyard.SorcererCFrame * DUMMY_OFFSET
Courtyard.ChestCFrame = CFrame.new(9.5, 0, 3) * CFrame.Angles(0, rad(155), 0)
Courtyard.SpawnCFrame = CFrame.new(0, 0.5, 17)
Courtyard.BoardCFrame = CFrame.new(-15, 0, 1) * CFrame.Angles(0, rad(-100), 0)

local STRAW = Color3.fromRGB(214, 184, 120)
local STRAW_DARK = Color3.fromRGB(170, 140, 86)
local CHEST_WOOD = Color3.fromRGB(120, 72, 46)
local GOLD = Color3.fromRGB(255, 205, 90)

-- Weld a decoration to the unanchored part it moves with.
local function weldTo(body: BasePart, part: BasePart)
	part.Anchored = false
	part.Massless = true
	local weld = Instance.new("Weld")
	weld.Name = "DetailWeld"
	weld.Part0 = body
	weld.Part1 = part
	weld.C0 = body.CFrame:Inverse() * part.CFrame
	weld.Parent = part
end

local function ground(parent: Instance)
	local model = PartKit.model(parent, "Ground")
	Kit.part(model, "Grass", V3(600, 2, 600), CFrame.new(0, -1.1, 0), Palette.Grass, M.Grass)
	-- Paved courtyard (top at y = 0) with a darker border
	Kit.part(model, "Border", V3(50, 0.4, 50), CFrame.new(0, -0.25, 0), Palette.StoneDark, M.Slate)
	local rng: any = Prng.new(7)
	for i = -2, 2 do
		for j = -2, 2 do
			local shade = rng:NextNumber(-0.04, 0.04)
			local c = Palette.Paving
			Kit.part(
				model,
				"Paving",
				V3(8.9, 0.1, 8.9),
				CFrame.new(i * 9, -0.05, j * 9),
				Color3.new(
					math.clamp(c.R + shade, 0, 1),
					math.clamp(c.G + shade, 0, 1),
					math.clamp(c.B + shade, 0, 1)
				),
				M.Slate
			)
		end
	end
	-- Low stone wall around the yard
	local walls: { { size: Vector3, cf: CFrame } } = {
		{ size = V3(52, 3, 1.4), cf = CFrame.new(0, 1.5, -25.5) },
		{ size = V3(52, 3, 1.4), cf = CFrame.new(0, 1.5, 25.5) },
		{ size = V3(1.4, 3, 50), cf = CFrame.new(-25.5, 1.5, 0) },
		{ size = V3(1.4, 3, 50), cf = CFrame.new(25.5, 1.5, 0) },
	}
	for _, wall in walls do
		Kit.part(model, "Wall", wall.size, wall.cf, Palette.Stone, M.Slate)
		Kit.part(
			model,
			"WallCap",
			wall.size + V3(0.6, -2.6, 0.6),
			wall.cf * CFrame.new(0, 1.7, 0),
			Palette.RoofTile,
			M.Slate
		)
	end
end

local function backdrop(parent: Instance)
	local model = PartKit.model(parent, "Backdrop")
	-- Dojo hall behind the training post, open toward the yard.
	Kit.building(model, CFrame.new(0, 0, -17.5) * CFrame.Angles(0, math.pi, 0), 26, 10, 9, {
		name = "Dojo",
		open = { front = true },
		roofHeight = 5.5,
	})
	Kit.stoneLantern(model, CFrame.new(-11, 0, -8), 1.1, true)
	Kit.stoneLantern(model, CFrame.new(10, 0, -8), 1.1, true)
	Kit.stoneLantern(model, CFrame.new(16, 0, 9), 0.9, true)
	local rng: any = Prng.new(11)
	for _, pos in
		{
			V3(-32, 0, -22),
			V3(-35, 0, 4),
			V3(-31, 0, 24),
			V3(32, 0, -26),
			V3(36, 0, -2),
			V3(31, 0, 22),
			V3(-17, 0, -33),
			V3(18, 0, -34),
		}
	do
		Kit.pine(model, pos, rng:NextNumber(0.9, 1.25), rng)
	end
end

local function post(parent: Instance): Model
	local model = PartKit.model(parent, "Post")
	local frame = Courtyard.SorcererCFrame * CFrame.new(0.45, -DECK_Y, -2.75)
	Kit.part(
		model,
		"Deck",
		V3(9, DECK_Y, 12),
		frame * CFrame.new(0, DECK_Y / 2, 0),
		Palette.AgedWood,
		M.WoodPlanks
	)
	for _, x in { -4.6, 4.6 } do
		Kit.part(
			model,
			"Edge",
			V3(0.5, DECK_Y + 0.12, 12.4),
			frame * CFrame.new(x, (DECK_Y + 0.12) / 2, 0),
			Palette.DarkWood,
			M.Wood
		)
	end
	-- Marking where the Sorcerer stands
	local ring = Kit.cylinder(
		model,
		"StandRing",
		3.6,
		0.06,
		Courtyard.SorcererCFrame * CFrame.new(0, 0.03, 0),
		Palette.Gold,
		M.SmoothPlastic,
		{ CanCollide = false, CanQuery = false }
	)
	ring.Transparency = 0.2
	local spot =
		Kit.part(model, "Spot", V3(1, 0.2, 1), Courtyard.SorcererCFrame, Palette.Gold, M.SmoothPlastic, {
			CanCollide = false,
			CanQuery = false,
			Transparency = 1,
		})
	spot.CastShadow = false
	local def = Sorcerers.get(PrototypeConfig.SorcererId)
	assert(def, "unknown Sorcerer " .. PrototypeConfig.SorcererId)
	local rig = Rig.build(model, Courtyard.SorcererCFrame, def.look, Rig.PostScale)
	rig:SetAttribute("SorcererId", def.id)
	-- Low name plate on the deck's near edge, behind the Sorcerer, facing the way players arrive
	Kit.sign(
		model,
		Courtyard.SorcererCFrame * CFrame.new(4.4, 0.4, 1.6) * CFrame.Angles(0, rad(-90), 0),
		2.8,
		0.75,
		def.name .. "  ·  " .. def.technique,
		{ name = "NamePlate", back = true }
	)
	return model
end

local function dummy(parent: Instance): Model
	local model = PartKit.model(parent, "Dummy")
	local cf = Courtyard.DummyCFrame
	local base =
		Kit.cylinder(model, "Base", 3.0, 0.5, cf * CFrame.new(0, 0.25, 0), Palette.StoneDark, M.Slate)
	Kit.cylinder(model, "Pole", 0.5, 2.0, cf * CFrame.new(0, 1.4, 0), Palette.DarkWood, M.Wood)
	model.PrimaryPart = base
	-- Straw body on a spring: the client rocks it back on every hit.
	local pivot = cf * CFrame.new(0, 2.4, 0)
	local body = Kit.cylinder(model, "Body", 1.9, 2.6, cf * CFrame.new(0, 3.7, 0), STRAW, M.Fabric)
	body.Anchored = false
	body.Massless = true
	local spring = Instance.new("Motor6D")
	spring.Name = "Spring"
	spring.Part0 = base
	spring.Part1 = body
	spring.C0 = base.CFrame:Inverse() * pivot
	spring.C1 = body.CFrame:Inverse() * pivot
	spring.Parent = body
	for _, y in { 2.75, 4.65 } do
		weldTo(body, Kit.cylinder(model, "Rope", 1.98, 0.18, cf * CFrame.new(0, y, 0), STRAW_DARK, M.Fabric))
	end
	-- Target disc on the front (local -Z faces the Sorcerer)
	local hitY = 4.19
	weldTo(
		body,
		Kit.part(
			model,
			"Target",
			V3(1.3, 1.3, 0.1),
			cf * CFrame.new(0, hitY, -0.93),
			Palette.Lacquer,
			M.SmoothPlastic,
			{
				CanCollide = false,
			}
		)
	)
	weldTo(
		body,
		Kit.part(
			model,
			"TargetCore",
			V3(0.55, 0.55, 0.1),
			cf * CFrame.new(0, hitY, -0.98),
			Palette.Paper,
			M.SmoothPlastic,
			{
				CanCollide = false,
			}
		)
	)
	weldTo(
		body,
		Kit.cylinder(
			model,
			"Arms",
			0.36,
			3.4,
			cf * CFrame.new(0, 4.3, 0) * CFrame.Angles(0, 0, rad(90)),
			STRAW_DARK,
			M.Wood
		)
	)
	for _, s in { -1, 1 } do
		weldTo(body, Kit.ball(model, "Fist", 0.62, cf * CFrame.new(s * 1.75, 4.3, 0), STRAW, M.Fabric))
	end
	local head = Kit.ball(model, "Head", 1.45, cf * CFrame.new(0, 5.65, 0), STRAW, M.Fabric)
	weldTo(body, head)
	-- A paper ward on the forehead
	weldTo(
		body,
		Kit.part(
			model,
			"Ward",
			V3(0.4, 0.75, 0.05),
			cf * CFrame.new(0, 5.75, -0.7),
			Palette.Paper,
			M.SmoothPlastic,
			{
				CanCollide = false,
			}
		)
	)
	weldTo(
		body,
		Kit.part(
			model,
			"WardInk",
			V3(0.1, 0.55, 0.06),
			cf * CFrame.new(0, 5.75, -0.72),
			Palette.Lacquer,
			M.Neon,
			{
				CanCollide = false,
			}
		)
	)
	local hit = Instance.new("Attachment")
	hit.Name = "HitPoint"
	hit.CFrame = body.CFrame:Inverse() * (cf * CFrame.new(0, hitY, -1.0))
	hit.Parent = body
	-- Popups rise from above the head.
	local top = Instance.new("Attachment")
	top.Name = "PopupAnchor"
	top.CFrame = body.CFrame:Inverse() * (cf * CFrame.new(0, 6.8, 0))
	top.Parent = body
	return model
end

local function chest(parent: Instance): Model
	local model = PartKit.model(parent, "Chest")
	local cf = Courtyard.ChestCFrame
	Kit.part(model, "Plinth", V3(5.2, 0.4, 3.8), cf * CFrame.new(0, 0.2, 0), Palette.StoneDark, M.Slate)
	local body =
		Kit.part(model, "Body", V3(4.4, 2.2, 3.0), cf * CFrame.new(0, 1.5, 0), CHEST_WOOD, M.WoodPlanks)
	model.PrimaryPart = body
	for _, x in { -2.0, 2.0 } do
		Kit.part(model, "Band", V3(0.3, 2.3, 3.1), cf * CFrame.new(x, 1.5, 0), Palette.Gold, M.Metal, {
			CanCollide = false,
		})
	end
	Kit.part(model, "Lock", V3(0.7, 0.8, 0.12), cf * CFrame.new(0, 2.1, -1.55), Palette.Gold, M.Metal, {
		CanCollide = false,
	})
	-- Gold heap on top of the body, under the lid. The client raises it as the chest fills.
	local gold = Kit.part(model, "Gold", V3(3.9, 0.2, 2.6), cf * CFrame.new(0, 2.7, 0), GOLD, M.Neon, {
		CanCollide = false,
		CanQuery = false,
	})
	gold.CastShadow = false
	gold:SetAttribute("BaseY", 2.6)
	gold:SetAttribute("MaxHeight", 0.9)
	-- Lid on a hinge along the back edge (+Z). Rotating +X lifts the front.
	local lid =
		Kit.part(model, "Lid", V3(4.5, 0.6, 3.1), cf * CFrame.new(0, 2.9, 0), CHEST_WOOD, M.WoodPlanks)
	lid.Anchored = false
	lid.Massless = true
	lid.CanCollide = false
	local hingeAt = cf * CFrame.new(0, 2.6, 1.55)
	local hinge = Instance.new("Motor6D")
	hinge.Name = "Hinge"
	hinge.Part0 = body
	hinge.Part1 = lid
	hinge.C0 = body.CFrame:Inverse() * hingeAt
	hinge.C1 = lid.CFrame:Inverse() * hingeAt
	hinge.Parent = lid
	for _, x in { -2.0, 2.0 } do
		weldTo(
			lid,
			Kit.part(
				model,
				"LidBand",
				V3(0.3, 0.66, 3.16),
				cf * CFrame.new(x, 2.9, 0),
				Palette.Gold,
				M.Metal,
				{
					CanCollide = false,
				}
			)
		)
	end
	PartKit.light(gold, GOLD, 10, 0)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.ActionText = "Collect"
	prompt.ObjectText = "Reward Chest"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = body

	-- Floating label: title, amount and a fill bar. The client fills in the numbers.
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(220, 74)
	gui.StudsOffsetWorldSpace = V3(0, 3.6, 0)
	gui.MaxDistance = 90
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Parent = body
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 22)
	title.Text = "REWARD CHEST"
	title.TextColor3 = Palette.Paper
	title.TextStrokeTransparency = 0.4
	title.TextScaled = true
	title.FontFace = PartKit.font(Enum.Font.GothamBold, true)
	title.Parent = gui
	local amount = Instance.new("TextLabel")
	amount.Name = "Amount"
	amount.BackgroundTransparency = 1
	amount.Position = UDim2.fromOffset(0, 22)
	amount.Size = UDim2.new(1, 0, 0, 30)
	amount.Text = "$0"
	amount.TextColor3 = GOLD
	amount.TextStrokeTransparency = 0.3
	amount.TextScaled = true
	amount.FontFace = PartKit.font(Enum.Font.GothamBlack, true)
	amount.Parent = gui
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = Color3.fromRGB(30, 26, 36)
	bar.BackgroundTransparency = 0.2
	bar.BorderSizePixel = 0
	bar.Position = UDim2.new(0.1, 0, 0, 58)
	bar.Size = UDim2.new(0.8, 0, 0, 10)
	bar.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = GOLD
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = bar
	for _, frame in { bar, fill } do
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
	end
	return model
end

local function collectPad(parent: Instance): BasePart
	local cf = Courtyard.ChestCFrame * CFrame.new(0, 0, -4.2)
	local pad = Kit.part(
		parent,
		"CollectPad",
		V3(5, 0.24, 3),
		cf * CFrame.new(0, 0.12, 0),
		Palette.Gold,
		M.SmoothPlastic,
		{
			CanTouch = true,
		}
	)
	pad:SetAttribute("TouchAction", "Collect")
	Kit.part(
		parent,
		"CollectPadInset",
		V3(4.3, 0.26, 2.3),
		cf * CFrame.new(0, 0.13, 0),
		Palette.DarkWood,
		M.Wood,
		{
			CanCollide = false,
			CanQuery = false,
		}
	)
	local text = Kit.part(
		parent,
		"CollectPadText",
		V3(4.2, 2.2, 0.05),
		cf * CFrame.new(0, 0.27, 0) * CFrame.Angles(rad(90), 0, 0),
		Palette.DarkWood,
		M.Wood,
		{
			CanCollide = false,
			CanQuery = false,
			Transparency = 1,
		}
	)
	Kit.label(text, "COLLECT", { color = Palette.Gold, face = Enum.NormalId.Front, pps = 30 })
	return pad
end

local function reviewBoard(parent: Instance): Model
	local model = PartKit.model(parent, "ReviewBoard")
	local cf = Courtyard.BoardCFrame
	for _, x in { -2.4, 2.4 } do
		Kit.cylinder(model, "Leg", 0.4, 4.6, cf * CFrame.new(x, 2.3, 0), Palette.DarkWood, M.Wood)
	end
	local board = Kit.sign(
		model,
		cf * CFrame.new(0, 3.4, 0),
		5.6,
		2.6,
		"PROTOTYPE REVIEW\nTraining post · Reward Chest\nUse the switches below",
		{ name = "Board", color = Palette.Paper }
	)
	local function switch(name: string, x: number, action: string, object: string)
		local a = Instance.new("Attachment")
		a.Name = name .. "Anchor"
		a.CFrame = CFrame.new(x, -1.6, -0.3)
		a.Parent = board
		Kit.ball(model, name .. "Knob", 0.6, board.CFrame * a.CFrame, Palette.Lacquer, M.SmoothPlastic)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = name
		prompt.ActionText = action
		prompt.ObjectText = object
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = if name == "FastPrompt" then Enum.KeyCode.F else Enum.KeyCode.G
		prompt.Parent = a
	end
	switch("FastPrompt", -1.4, "Fast Sorcerer", "Combo test")
	switch("FillPrompt", 1.4, "Fill chest", "Full-chest test")
	return model
end

function Courtyard.build(parent: Instance): Model
	local root = PartKit.model(nil, Courtyard.Name)
	ground(root)
	backdrop(root)
	post(root)
	dummy(root)
	chest(root)
	collectPad(root)
	reviewBoard(root)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = V3(6, 0.2, 6)
	spawn.CFrame = Courtyard.SpawnCFrame * CFrame.new(0, -0.4, 0)
	spawn.Anchored = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root
	root.Parent = parent
	return root
end

return Courtyard
