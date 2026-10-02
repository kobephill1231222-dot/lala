--!strict
-- Builds the original unit designs from primitives. Every model has an anchored, invisible
-- "Root" at its feet (PrimaryPart); all visible parts are welded to it so clients can animate
-- the whole figure by moving one part. Front of the model is -Z (the Root's LookVector).

local Characters = require(script.Parent.Parent.Config.Characters)
local Rarities = require(script.Parent.Parent.Config.Rarities)
local PartKit = require(script.Parent.PartKit)

local CharacterModels = {}

export type Options = {
	aura: boolean?, -- rarity particles
	ghost: boolean?, -- translucent placement preview
}

local rad = math.rad
local V3 = Vector3.new
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local FABRIC = Enum.Material.Fabric
local WOOD = Enum.Material.Wood

local DARK = Color3.fromRGB(26, 22, 30)
local WHITE = Color3.fromRGB(250, 248, 255)
local PAPER = Color3.fromRGB(240, 230, 204)
local GOLD = Color3.fromRGB(232, 188, 92)

local function L(x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(rad(rx or 0), rad(ry or 0), rad(rz or 0))
end

type Ctx = {
	model: Model,
	root: BasePart,
	base: CFrame,
	ghost: boolean,
}

-- Adds a welded detail part. `shape` = "block" | "ball" | "ellipsoid" | "cyl" (along local Y) | "wedge"
local function add(
	ctx: Ctx,
	shape: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	extra: { [string]: any }?
): BasePart
	local world = ctx.base * cf
	local props: { [string]: any } = {
		Size = size,
		CFrame = world,
		Color = color,
		Material = material or SMOOTH,
		Anchored = false,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Massless = true,
		CastShadow = size.Magnitude > 1.6,
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	if ctx.ghost then
		props.Transparency = math.max(props.Transparency or 0, 0.55)
		props.CastShadow = false
	end
	local part: BasePart
	if shape == "ball" then
		props.Shape = Enum.PartType.Ball
		part = PartKit.part(ctx.model, props :: any)
	elseif shape == "ellipsoid" then
		part = PartKit.ellipsoid(ctx.model, props :: any)
	elseif shape == "cyl" then
		props.Shape = Enum.PartType.Cylinder
		props.Size = V3(size.Y, size.X, size.Z)
		props.CFrame = world * CFrame.Angles(0, 0, rad(90))
		part = PartKit.part(ctx.model, props :: any)
	elseif shape == "wedge" then
		props.ClassName = "WedgePart"
		part = PartKit.part(ctx.model, props :: any)
	else
		part = PartKit.part(ctx.model, props :: any)
	end
	PartKit.weld(ctx.root, part)
	return part
end

-- SORCERER -------------------------------------------------------------------------------

local HEAD_Y = 4.2
local HEAD_D = 2.2

local function sorcererFace(ctx: Ctx, look: any)
	local eyeColor = look.eyes or DARK
	for _, side in { -1, 1 } do
		add(ctx, "block", V3(0.3, 0.46, 0.12), L(side * 0.42, HEAD_Y - 0.12, -1.0), DARK)
		add(ctx, "block", V3(0.2, 0.3, 0.1), L(side * 0.42, HEAD_Y - 0.17, -1.04), eyeColor, NEON)
		add(ctx, "block", V3(0.08, 0.08, 0.06), L(side * 0.36, HEAD_Y - 0.02, -1.08), WHITE, NEON)
	end
	add(ctx, "block", V3(0.24, 0.06, 0.06), L(0, HEAD_Y - 0.62, -0.96), Color3.fromRGB(120, 60, 70))
end

local function sorcererHair(ctx: Ctx, look: any)
	local hair = look.hair
	local style = look.hairStyle
	add(ctx, "ball", V3(2.34, 2.34, 2.34), L(0, HEAD_Y + 0.3, 0.22), hair)
	-- Bangs
	for i, x in { -0.62, -0.2, 0.22, 0.62 } do
		local tilt = (i % 2 == 0) and 8 or -8
		add(ctx, "wedge", V3(0.48, 0.5, 0.38), L(x, HEAD_Y + 0.8, -0.82, 180 - 20, 0, tilt), hair)
	end
	if style == "Spiky" then
		for i = 1, 7 do
			local a = (i - 4) * 24
			add(
				ctx,
				"wedge",
				V3(0.6, 1.3, 0.8),
				CFrame.new(0, HEAD_Y + 1.05, 0.35)
					* CFrame.Angles(0, rad(a), 0)
					* CFrame.new(0, 0, 0.55)
					* CFrame.Angles(rad(-35), 0, 0),
				hair
			)
		end
	elseif style == "Bob" then
		for _, side in { -1, 1 } do
			add(ctx, "block", V3(0.42, 1.5, 1.7), L(side * 1.06, HEAD_Y - 0.25, 0.1), hair)
		end
		add(ctx, "block", V3(2.1, 1.5, 0.5), L(0, HEAD_Y - 0.25, 0.95), hair)
	elseif style == "Ponytail" then
		add(ctx, "ball", V3(0.62, 0.62, 0.62), L(0, HEAD_Y + 0.55, 1.22), look.trim or hair, nil)
		add(ctx, "ellipsoid", V3(0.7, 2.3, 0.7), L(0, HEAD_Y - 0.45, 1.45, -18, 0, 0), hair)
		for _, side in { -1, 1 } do
			add(ctx, "block", V3(0.3, 1.1, 0.4), L(side * 1.0, HEAD_Y - 0.35, -0.45), hair)
		end
	elseif style == "Long" then
		add(ctx, "block", V3(2.2, 3.4, 0.55), L(0, HEAD_Y - 1.2, 0.95, -6, 0, 0), hair)
		for _, side in { -1, 1 } do
			add(ctx, "block", V3(0.38, 2.2, 0.55), L(side * 1.02, HEAD_Y - 0.9, -0.25), hair)
		end
	elseif style == "Swept" then
		add(ctx, "wedge", V3(1.3, 0.9, 1.6), L(-0.55, HEAD_Y + 0.75, -0.35, 0, 0, 25), hair)
		add(ctx, "block", V3(2.15, 1.6, 0.5), L(0, HEAD_Y - 0.35, 0.95), hair)
		if look.hairStreak then
			add(ctx, "block", V3(0.24, 1.55, 0.5), L(0.55, HEAD_Y - 0.33, 0.97), look.hairStreak)
			add(ctx, "wedge", V3(0.3, 0.8, 0.45), L(0.62, HEAD_Y + 0.58, -0.86, 165, 0, -6), look.hairStreak)
		end
	else -- Short
		add(ctx, "block", V3(2.1, 1.0, 0.5), L(0, HEAD_Y - 0.05, 0.9), hair)
		for _, side in { -1, 1 } do
			add(ctx, "block", V3(0.3, 0.8, 0.7), L(side * 1.02, HEAD_Y - 0.05, 0.1), hair)
		end
	end
end

local ACCESSORIES: { [string]: (Ctx, any) -> () } = {}

ACCESSORIES.Talismans = function(ctx, look)
	for i = 1, 3 do
		local a = rad(i * 120)
		local cf = L(math.cos(a) * 1.7, 2.6 + i * 0.35, math.sin(a) * 1.2 - 0.3, 0, -i * 120, 10)
		add(ctx, "block", V3(0.5, 0.85, 0.05), cf, PAPER)
		add(ctx, "block", V3(0.12, 0.6, 0.06), cf, Color3.fromRGB(196, 50, 60), NEON)
	end
	local _ = look
end

ACCESSORIES.BellStaff = function(ctx, look)
	add(ctx, "cyl", V3(0.22, 5.4, 0.22), L(1.45, 2.6, -0.3), Color3.fromRGB(90, 60, 40), WOOD)
	for i = 0, 5 do
		local a = rad(i * 60)
		add(
			ctx,
			"ball",
			V3(0.28, 0.28, 0.28),
			L(1.45 + math.cos(a) * 0.5, 5.6 + math.sin(a) * 0.5, -0.3),
			GOLD,
			Enum.Material.Metal
		)
	end
	add(ctx, "ball", V3(0.42, 0.42, 0.42), L(1.45, 5.0, -0.3), GOLD, Enum.Material.Metal)
	local _ = look
end

ACCESSORIES.Sash = function(ctx, look)
	add(ctx, "block", V3(1.8, 0.38, 1.02), L(0, 1.62, 0), look.trim)
	add(ctx, "block", V3(0.32, 1.2, 0.12), L(0.5, 1.05, -0.5, 0, 0, 8), look.trim)
end

ACCESSORIES.Gauntlets = function(ctx, _look)
	local stone = Color3.fromRGB(128, 124, 120)
	for _, side in { -1, 1 } do
		add(ctx, "block", V3(0.85, 0.95, 0.85), L(side * 1.18, 1.55, -0.05), stone, Enum.Material.Slate)
		add(ctx, "block", V3(0.9, 0.12, 0.9), L(side * 1.18, 1.95, -0.05), Color3.fromRGB(214, 150, 70), NEON)
	end
end

ACCESSORIES.Headband = function(ctx, look)
	add(ctx, "cyl", V3(2.3, 0.3, 2.3), L(0, HEAD_Y + 0.42, 0.05), look.trim)
	add(ctx, "block", V3(0.25, 0.9, 0.08), L(0.3, HEAD_Y + 0.05, 1.18, 10, 0, 18), look.trim)
end

ACCESSORIES.KatanaBack = function(ctx, _look)
	add(ctx, "block", V3(0.28, 4.2, 0.22), L(0, 2.9, 0.68, 0, 0, 38), Color3.fromRGB(20, 24, 34))
	add(ctx, "block", V3(0.3, 1.0, 0.26), L(-1.15, 4.35, 0.68, 0, 0, 38), Color3.fromRGB(70, 214, 220))
	add(ctx, "block", V3(0.7, 0.12, 0.4), L(-0.85, 3.95, 0.68, 0, 0, 38), GOLD, Enum.Material.Metal)
end

ACCESSORIES.KatanaHip = function(ctx, look)
	add(ctx, "block", V3(0.26, 3.6, 0.22), L(-1.05, 1.5, -0.2, 70, 0, 0), Color3.fromRGB(30, 20, 22))
	add(ctx, "block", V3(0.28, 0.9, 0.24), L(-1.05, 1.95, -1.6, 70, 0, 0), look.trim)
end

ACCESSORIES.Scarf = function(ctx, look)
	add(ctx, "cyl", V3(1.55, 0.55, 1.35), L(0, 3.15, 0), look.trim, FABRIC)
	add(ctx, "block", V3(0.45, 1.6, 0.12), L(0.45, 2.6, 0.62, -12, 0, 6), look.trim, FABRIC)
end

ACCESSORIES.StarBow = function(ctx, look)
	local wood = Color3.fromRGB(60, 50, 90)
	add(ctx, "block", V3(0.2, 1.6, 0.2), L(-1.55, 3.4, -0.4, 0, 0, -18), wood)
	add(ctx, "block", V3(0.2, 1.6, 0.2), L(-1.55, 1.8, -0.4, 0, 0, 18), wood)
	add(ctx, "block", V3(0.04, 3.0, 0.04), L(-1.25, 2.6, -0.4), look.trim, NEON)
	add(ctx, "block", V3(0.45, 0.45, 0.1), L(-1.82, 4.15, -0.4, 0, 0, 45), look.trim, NEON)
end

ACCESSORIES.Haori = function(ctx, look)
	local coat = look.outfit:Lerp(Color3.new(0, 0, 0), 0.25)
	for _, side in { -1, 1 } do
		add(ctx, "block", V3(0.75, 2.6, 0.18), L(side * 0.6, 1.9, -0.56, -4, 0, side * 3), coat, FABRIC)
		add(ctx, "block", V3(0.78, 0.2, 0.2), L(side * 0.6, 0.65, -0.6), look.trim, NEON)
	end
	add(ctx, "block", V3(1.9, 2.8, 0.2), L(0, 1.8, 0.58, 5, 0, 0), coat, FABRIC)
	add(ctx, "block", V3(1.92, 0.2, 0.22), L(0, 0.45, 0.67), look.trim, NEON)
	for _, side in { -1, 1 } do
		add(ctx, "block", V3(0.8, 1.2, 1.0), L(side * 1.2, 2.7, 0), coat, FABRIC)
	end
end

ACCESSORIES.FoxMaskSide = function(ctx, look)
	local cf = L(1.05, HEAD_Y + 0.15, -0.3, 0, -70, 0)
	add(ctx, "ellipsoid", V3(1.0, 1.25, 0.4), cf, WHITE)
	add(ctx, "wedge", V3(0.25, 0.45, 0.2), cf * L(-0.3, 0.75, 0), WHITE)
	add(ctx, "wedge", V3(0.25, 0.45, 0.2), cf * L(0.3, 0.75, 0), WHITE)
	add(ctx, "block", V3(0.35, 0.06, 0.06), cf * L(-0.22, 0.12, -0.2, 0, 0, 15), look.trim, NEON)
	add(ctx, "block", V3(0.35, 0.06, 0.06), cf * L(0.22, 0.12, -0.2, 0, 0, -15), look.trim, NEON)
end

ACCESSORIES.Orbs = function(ctx, look)
	for i = 1, 3 do
		local a = rad(i * 120 + 30)
		add(
			ctx,
			"ball",
			V3(0.42, 0.42, 0.42),
			L(math.cos(a) * 1.9, 3.4 + (i % 2) * 0.5, math.sin(a) * 1.4),
			look.aura,
			NEON
		)
	end
end

ACCESSORIES.Halo = function(ctx, look)
	local segments = 14
	for i = 1, segments do
		if i % 5 ~= 0 then -- deliberate gaps: a fractured halo
			local a = (i / segments) * math.pi * 2
			local cf = CFrame.new(0, HEAD_Y + 0.6, 1.1)
				* CFrame.Angles(rad(-15), 0, 0)
				* CFrame.Angles(0, 0, a)
				* CFrame.new(0, 1.55, 0)
			add(ctx, "block", V3(0.62, 0.14, 0.14), cf, look.aura, NEON)
		end
	end
end

ACCESSORIES.Veil = function(ctx, _look)
	add(
		ctx,
		"block",
		V3(2.3, 3.8, 0.12),
		L(0, 2.8, 1.18, 8, 0, 0),
		Color3.fromRGB(40, 20, 60),
		FABRIC,
		{ Transparency = 0.35 }
	)
end

local function buildSorcerer(ctx: Ctx, look: any)
	local outfit, trim, pants, skin = look.outfit, look.trim, look.pants, look.skin
	-- Legs and shoes
	for _, side in { -1, 1 } do
		add(ctx, "block", V3(0.72, 1.35, 0.78), L(side * 0.42, 0.88, 0), pants)
		add(ctx, "block", V3(0.78, 0.36, 1.0), L(side * 0.42, 0.18, -0.1), DARK)
	end
	-- Torso: high-collared jacket with trim
	add(ctx, "block", V3(1.75, 1.7, 1.0), L(0, 2.35, 0), outfit, FABRIC)
	add(ctx, "block", V3(1.8, 0.28, 1.04), L(0, 1.55, 0), trim)
	add(ctx, "block", V3(0.18, 1.6, 0.06), L(0, 2.35, -0.53), trim)
	for i = 0, 2 do
		add(ctx, "ball", V3(0.16, 0.16, 0.16), L(0.2, 2.85 - i * 0.42, -0.55), GOLD, Enum.Material.Metal)
	end
	add(ctx, "cyl", V3(1.3, 0.55, 1.15), L(0, 3.35, 0), outfit, FABRIC)
	add(ctx, "cyl", V3(1.35, 0.08, 1.2), L(0, 3.62, 0), trim)
	-- Arms and hands
	for _, side in { -1, 1 } do
		add(ctx, "block", V3(0.6, 1.5, 0.66), L(side * 1.18, 2.4, 0, 0, 0, side * 6), outfit, FABRIC)
		add(ctx, "block", V3(0.64, 0.18, 0.7), L(side * 1.24, 1.72, 0, 0, 0, side * 6), trim)
		add(ctx, "ball", V3(0.55, 0.55, 0.55), L(side * 1.27, 1.42, 0), skin)
	end
	-- Head
	add(ctx, "ball", V3(HEAD_D, HEAD_D, HEAD_D), L(0, HEAD_Y, 0), skin)
	sorcererFace(ctx, look)
	sorcererHair(ctx, look)
	for _, accessory in look.accessories or {} do
		local builder = ACCESSORIES[accessory]
		if builder then
			builder(ctx, look)
		end
	end
end

-- SPIRITS ------------------------------------------------------------------------------

local SPIRITS: { [string]: (Ctx, any) -> () } = {}

SPIRITS.Lantern = function(ctx, look)
	local y = 2.9
	add(ctx, "cyl", V3(1.9, 2.4, 1.9), L(0, y, 0), look.glow, NEON)
	add(ctx, "cyl", V3(2.3, 2.6, 2.3), L(0, y, 0), look.paper, SMOOTH, { Transparency = 0.22 })
	for _, dy in { -0.85, -0.3, 0.3, 0.85 } do
		add(ctx, "cyl", V3(2.4, 0.1, 2.4), L(0, y + dy, 0), look.rib)
	end
	add(ctx, "cyl", V3(1.7, 0.32, 1.7), L(0, y + 1.42, 0), look.rib, WOOD)
	add(ctx, "cyl", V3(1.7, 0.32, 1.7), L(0, y - 1.42, 0), look.rib, WOOD)
	add(ctx, "block", V3(0.15, 0.9, 0.15), L(-0.5, y + 1.95, 0, 0, 0, -30), look.rib, WOOD)
	add(ctx, "block", V3(0.15, 0.9, 0.15), L(0.5, y + 1.95, 0, 0, 0, 30), look.rib, WOOD)
	add(ctx, "block", V3(1.1, 0.15, 0.15), L(0, y + 2.32, 0), look.rib, WOOD)
	-- One huge eye and a lolling tongue: the classic paper-lantern yokai, our way.
	add(ctx, "ellipsoid", V3(1.05, 0.9, 0.3), L(0.05, y + 0.35, -1.14), WHITE)
	add(ctx, "ball", V3(0.48, 0.48, 0.48), L(0.1, y + 0.33, -1.24), look.eye)
	add(ctx, "ball", V3(0.14, 0.14, 0.14), L(0.02, y + 0.45, -1.42), WHITE, NEON)
	add(ctx, "block", V3(0.9, 0.12, 0.12), L(0, y - 0.45, -1.16), look.rib)
	add(ctx, "wedge", V3(0.45, 0.9, 0.15), L(0.15, y - 0.95, -1.2, 180, 0, 0), look.tongue)
	if not ctx.ghost then
		PartKit.particles(ctx.root, {
			Texture = "rbxasset://textures/particles/fire_main.dds",
			Color = ColorSequence.new(look.glow),
			Size = PartKit.sequence({ { 0, 0.5 }, { 1, 0 } }),
			Transparency = PartKit.sequence({ { 0, 0.3 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.5, 0.9),
			Rate = 10,
			Speed = NumberRange.new(0.5, 1),
			Acceleration = V3(0, -2, 0),
			EmissionDirection = Enum.NormalId.Bottom,
		})
	end
end

SPIRITS.Toad = function(ctx, look)
	add(ctx, "ellipsoid", V3(3.2, 2.1, 3.0), L(0, 1.15, 0.1), look.body)
	add(ctx, "ellipsoid", V3(2.4, 1.6, 0.9), L(0, 0.95, -1.05), look.belly)
	for _, side in { -1, 1 } do
		add(ctx, "ball", V3(0.95, 0.95, 0.95), L(side * 0.75, 2.2, -0.75), look.body)
		add(ctx, "ball", V3(0.7, 0.7, 0.7), L(side * 0.78, 2.3, -1.0), look.eye, NEON)
		add(ctx, "block", V3(0.42, 0.14, 0.1), L(side * 0.8, 2.3, -1.34), DARK)
		add(ctx, "ellipsoid", V3(1.0, 0.6, 1.5), L(side * 1.35, 0.35, 0.2), look.body)
		add(ctx, "ellipsoid", V3(0.7, 0.5, 0.9), L(side * 1.0, 0.3, -1.3), look.body)
	end
	add(ctx, "block", V3(1.8, 0.1, 0.1), L(0, 1.55, -1.42), DARK)
	for i, pos in { V3(-0.6, 2.05, 0.6), V3(0.7, 1.95, 0.9), V3(0.1, 2.15, 0.2), V3(-1.1, 1.6, 0.9) } do
		add(ctx, "ellipsoid", V3(0.9 - i * 0.08, 0.35, 0.8), CFrame.new(pos), look.moss, Enum.Material.Grass)
	end
	add(ctx, "cyl", V3(1.9, 0.12, 1.9), L(0, 2.42, 0.15), look.hat, Enum.Material.Fabric)
	add(ctx, "cyl", V3(0.9, 0.45, 0.9), L(0, 2.65, 0.15), look.hat, Enum.Material.Fabric)
end

SPIRITS.Moth = function(ctx, look)
	local y = 3.2
	add(ctx, "ellipsoid", V3(0.9, 2.1, 0.9), L(0, y, 0.2, 15, 0, 0), look.body, FABRIC)
	add(ctx, "ball", V3(0.95, 0.95, 0.95), L(0, y + 1.15, -0.15), look.body, FABRIC)
	for _, side in { -1, 1 } do
		add(ctx, "ball", V3(0.36, 0.36, 0.36), L(side * 0.25, y + 1.2, -0.55), look.eye, NEON)
		add(ctx, "block", V3(0.06, 1.0, 0.06), L(side * 0.3, y + 1.9, -0.3, -25, 0, side * -20), look.body)
		add(ctx, "ball", V3(0.22, 0.22, 0.22), L(side * 0.5, y + 2.35, -0.55), look.wing, NEON)
		-- Upper and lower wings
		add(
			ctx,
			"block",
			V3(2.4, 1.9, 0.08),
			L(side * 1.35, y + 0.6, 0.35, 0, side * 18, side * 18),
			look.wing,
			NEON,
			{ Transparency = 0.35 }
		)
		add(
			ctx,
			"block",
			V3(2.5, 0.1, 0.1),
			L(side * 1.42, y + 1.48, 0.33, 0, side * 18, side * 18),
			look.wingEdge,
			NEON
		)
		add(
			ctx,
			"block",
			V3(1.6, 1.3, 0.08),
			L(side * 0.95, y - 0.75, 0.4, 0, side * 18, side * -22),
			look.wing,
			NEON,
			{ Transparency = 0.45 }
		)
	end
	if not ctx.ghost then
		PartKit.particles(ctx.root, {
			Color = ColorSequence.new(look.wing),
			Size = PartKit.sequence({ { 0, 0.18 }, { 1, 0 } }),
			Lifetime = NumberRange.new(1.5, 2.5),
			Rate = 6,
			Speed = NumberRange.new(0.2, 0.6),
			Acceleration = V3(0, -0.6, 0),
		})
	end
end

SPIRITS.Mask = function(ctx, look)
	local y = 3.9
	-- Tattered cloak
	for i = 0, 5 do
		local a = rad(i * 60)
		add(
			ctx,
			"wedge",
			V3(1.2, 2.8, 0.5),
			CFrame.new(0, y - 1.7, 0) * CFrame.Angles(0, a, 0) * L(0, 0, 0.75, 180 - 12, 0, 0),
			look.cloak,
			FABRIC
		)
	end
	add(ctx, "ellipsoid", V3(2.4, 1.6, 2.2), L(0, y - 0.4, 0.15), look.cloak, FABRIC)
	add(ctx, "ellipsoid", V3(1.9, 2.3, 0.6), L(0, y + 0.3, -0.95), look.mask)
	for _, side in { -1, 1 } do
		add(ctx, "block", V3(0.55, 0.16, 0.12), L(side * 0.42, y + 0.55, -1.25, 0, 0, side * -14), DARK)
		add(ctx, "block", V3(0.3, 0.1, 0.1), L(side * 0.42, y + 0.55, -1.3, 0, 0, side * -14), look.eye, NEON)
		add(
			ctx,
			"block",
			V3(0.1, 0.9, 0.1),
			L(side * 0.62, y + 0.05, -1.24, 0, 0, side * 8),
			look.marking,
			NEON
		)
		add(ctx, "ball", V3(0.7, 0.7, 0.7), L(side * 1.7, y - 1.0, -0.6), look.cloak, FABRIC)
		add(ctx, "ball", V3(0.22, 0.22, 0.22), L(side * 1.7, y - 1.0, -0.98), look.eye, NEON)
	end
	for _, side in { -1, 1 } do
		add(
			ctx,
			"wedge",
			V3(0.3, 1.1, 0.35),
			L(side * 0.62, y + 1.55, -0.9, -10, 0, side * -28),
			look.mask,
			Enum.Material.Marble
		)
		add(
			ctx,
			"block",
			V3(0.08, 0.5, 0.08),
			L(side * 0.75, y + 1.45, -1.06, -10, 0, side * -28),
			look.marking,
			NEON
		)
	end
	add(ctx, "block", V3(0.95, 0.3, 0.12), L(0, y - 0.45, -1.2), DARK)
	for i = 0, 3 do
		add(ctx, "wedge", V3(0.16, 0.22, 0.08), L(-0.33 + i * 0.22, y - 0.36, -1.27, 180, 0, 0), WHITE)
	end
	add(ctx, "block", V3(0.95, 0.06, 0.1), L(0, y - 0.62, -1.24), look.marking, NEON)
	add(ctx, "block", V3(0.12, 0.5, 0.1), L(0, y + 1.0, -1.18), look.marking, NEON)
	if not ctx.ghost then
		PartKit.particles(ctx.root, {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(30, 20, 40)),
			LightEmission = 0,
			Size = PartKit.sequence({ { 0, 1 }, { 1, 2.4 } }),
			Transparency = PartKit.sequence({ { 0, 0.6 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1.2, 2),
			Rate = 6,
			Speed = NumberRange.new(0.3, 0.8),
			EmissionDirection = Enum.NormalId.Bottom,
		})
	end
end

SPIRITS.Wolf = function(ctx, look)
	local fur, accent = look.fur, look.accent
	add(ctx, "ellipsoid", V3(1.7, 1.6, 3.0), L(0, 1.85, 0.3), fur, FABRIC)
	add(ctx, "ball", V3(1.75, 1.75, 1.75), L(0, 2.85, -1.2), fur, FABRIC)
	add(ctx, "ellipsoid", V3(0.85, 0.7, 1.1), L(0, 2.55, -2.0), fur, FABRIC)
	add(ctx, "ball", V3(0.3, 0.3, 0.3), L(0, 2.7, -2.55), DARK)
	for _, side in { -1, 1 } do
		add(ctx, "wedge", V3(0.45, 0.85, 0.5), L(side * 0.55, 3.85, -1.15, 0, 0, side * -12), fur)
		add(ctx, "wedge", V3(0.25, 0.5, 0.3), L(side * 0.55, 3.8, -1.32, 0, 0, side * -12), accent, NEON)
		add(ctx, "block", V3(0.3, 0.26, 0.1), L(side * 0.4, 3.05, -2.03, 0, 0, side * 12), look.eye, NEON)
		for _, z in { -0.7, 1.2 } do
			add(ctx, "cyl", V3(0.55, 1.3, 0.55), L(side * 0.55, 0.7, z), fur, FABRIC)
			add(ctx, "block", V3(0.6, 0.12, 0.62), L(side * 0.55, 0.12, z - 0.05), accent, NEON)
		end
	end
	add(ctx, "ellipsoid", V3(0.6, 0.6, 2.0), L(0, 2.7, 2.1, 35, 0, 0), fur, FABRIC)
	add(ctx, "ellipsoid", V3(0.45, 0.45, 0.9), L(0, 3.35, 2.75, 35, 0, 0), accent, NEON)
	for i = 0, 2 do
		add(
			ctx,
			"block",
			V3(1.75, 0.1, 0.25),
			L(0, 2.25 - i * 0.05, -0.2 + i * 0.6, 0, 20 - i * 20, 0),
			accent,
			NEON
		)
	end
	if not ctx.ghost then
		PartKit.particles(ctx.root, {
			Texture = "rbxasset://textures/particles/fire_sparks_main.dds",
			Color = ColorSequence.new(accent, Color3.fromRGB(140, 220, 255)),
			Size = PartKit.sequence({ { 0, 0.4 }, { 1, 0 } }),
			Lifetime = NumberRange.new(0.2, 0.5),
			Rate = 8,
			Speed = NumberRange.new(2, 4),
			SpreadAngle = Vector2.new(180, 180),
		})
	end
end

SPIRITS.Serpent = function(ctx, look)
	local scale, crack = look.scale, look.crack
	local segments = 12
	for i = 1, segments do
		local t = i / segments
		local a = t * math.pi * 3
		local radius = 1.8 - t * 0.9
		local size = 2.2 - t * 0.85
		local pos = V3(math.cos(a) * radius, 0.8 + t * 4.6, math.sin(a) * radius + 0.3)
		local frame = CFrame.new(pos) * CFrame.Angles(0, -a, 0)
		add(ctx, "ellipsoid", V3(size, size * 0.85, size * 1.3), frame, scale, Enum.Material.Basalt)
		if i % 2 == 0 then
			add(
				ctx,
				"block",
				V3(size * 0.95, 0.14, 0.16),
				frame * CFrame.new(0, size * 0.3, 0) * CFrame.Angles(0, 0, rad(20)),
				crack,
				NEON
			)
		end
		add(
			ctx,
			"wedge",
			V3(0.25, 0.5, 0.5),
			frame * CFrame.new(0, size * 0.42, 0.2),
			look.horn,
			Enum.Material.Marble
		)
	end
	local head = L(0, 6.2, -0.6, 10, 0, 0)
	add(ctx, "ellipsoid", V3(2.2, 1.6, 2.8), head, scale, Enum.Material.Basalt)
	add(ctx, "block", V3(2.25, 0.12, 2.2), head * L(0, 0.1, 0.05), crack, NEON)
	add(ctx, "wedge", V3(1.7, 0.6, 1.4), head * L(0, -0.75, -0.9, 180, 0, 0), scale, Enum.Material.Basalt)
	for _, side in { -1, 1 } do
		add(
			ctx,
			"block",
			V3(0.42, 0.16, 0.2),
			head * L(side * 0.55, 0.25, -1.15, 0, 0, side * -15),
			look.eye,
			NEON
		)
		add(
			ctx,
			"wedge",
			V3(0.35, 1.6, 0.45),
			head * L(side * 0.65, 1.05, 0.55, -40, 0, side * -20),
			look.horn,
			Enum.Material.Marble
		)
		add(ctx, "block", V3(0.08, 0.9, 0.08), head * L(side * 0.4, 0.45, -0.4, 0, 0, side * 30), crack, NEON)
	end
	add(ctx, "block", V3(1.2, 0.08, 0.6), head * L(0, -0.42, -1.05), crack, NEON)
	for i = 1, 4 do
		local a = rad(i * 90 + 20)
		add(
			ctx,
			"block",
			V3(0.45, 0.8, 0.25),
			L(math.cos(a) * 2.8, 4.6 + (i % 2) * 1.1, math.sin(a) * 2.8, 20, i * 40, 30),
			crack,
			NEON
		)
	end
end

-- PUBLIC -------------------------------------------------------------------------------

local HEIGHTS = {
	Sorcerer = 5.6,
	Lantern = 5.4,
	Toad = 2.9,
	Moth = 5.8,
	Mask = 5.4,
	Wolf = 4.2,
	Serpent = 7.2,
}

function CharacterModels.heightOf(id: string): number
	local def = Characters.get(id)
	return if def then HEIGHTS[def.look.template] or 5 else 5
end

local function addAura(ctx: Ctx, def: Characters.CharacterDef)
	local rarity = Rarities.get(def.rarity)
	if not rarity or rarity.auraRate <= 0 then
		return
	end
	local look = def.look
	local color = look.aura or look.crack or look.accent or look.wing or look.glow or rarity.color
	PartKit.particles(ctx.root, {
		Color = ColorSequence.new(rarity.glow, color),
		Size = PartKit.sequence({ { 0, 0.25 }, { 0.5, 0.35 }, { 1, 0 } }),
		Transparency = PartKit.sequence({ { 0, 0.2 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.4, 2.4),
		Rate = rarity.auraRate,
		Speed = NumberRange.new(1, 2.2),
		SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Top,
	})
	if look.flameAura then
		PartKit.particles(ctx.root, {
			Texture = "rbxasset://textures/particles/fire_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(255, 160, 60), Color3.fromRGB(255, 60, 40)),
			Size = PartKit.sequence({ { 0, 0.8 }, { 1, 0 } }),
			Transparency = PartKit.sequence({ { 0, 0.4 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.5, 0.9),
			Rate = 12,
			Speed = NumberRange.new(1.5, 3),
		})
	end
	if look.voidAura then
		PartKit.particles(ctx.root, {
			Texture = "rbxasset://textures/particles/forcefield_vortex_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(120, 50, 220), Color3.fromRGB(20, 0, 40)),
			Size = PartKit.sequence({ { 0, 3 }, { 1, 5 } }),
			Transparency = PartKit.sequence({ { 0, 0.75 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1, 1.6),
			Rate = 3,
			Speed = NumberRange.new(0, 0),
			RotSpeed = NumberRange.new(-60, 60),
		})
	end
end

-- Builds the unit standing at `baseCFrame` (feet at its position, facing its LookVector).
function CharacterModels.build(id: string, baseCFrame: CFrame, options: Options?): Model
	local opts: Options = options or {}
	local def = Characters.get(id)
	assert(def, "unknown character " .. tostring(id))
	local model = Instance.new("Model")
	model.Name = def.id
	local root = PartKit.part(model, {
		Name = "Root",
		Size = V3(1, 1, 1),
		CFrame = baseCFrame,
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	model.PrimaryPart = root
	local ctx: Ctx = { model = model, root = root, base = baseCFrame, ghost = opts.ghost == true }
	local template = def.look.template
	if template == "Sorcerer" then
		buildSorcerer(ctx, def.look)
	else
		local builder = SPIRITS[template]
		assert(builder, "missing spirit template " .. tostring(template))
		builder(ctx, def.look)
	end
	if opts.aura and not ctx.ghost then
		addAura(ctx, def)
	end
	return model
end

return CharacterModels
