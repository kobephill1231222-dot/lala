--!strict
-- Curse enemy rigs. Each is a Humanoid (R15 rig type so HipHeight floats it without legs)
-- driving an invisible HumanoidRootPart, with massless decorative parts welded on.

local Enemies = require(script.Parent.Parent.Config.Enemies)
local PartKit = require(script.Parent.PartKit)

local CurseModels = {}

local rad = math.rad
local V3 = Vector3.new
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic

local VOID = Color3.fromRGB(22, 14, 30)
local BRUISE = Color3.fromRGB(58, 30, 72)
local BONE = Color3.fromRGB(226, 218, 204)
local GLOW = Color3.fromRGB(196, 92, 255)
local SICK = Color3.fromRGB(214, 255, 120)
local BLOOD = Color3.fromRGB(255, 60, 90)

local function L(x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(rad(rx or 0), rad(ry or 0), rad(rz or 0))
end

type Ctx = { model: Model, root: BasePart, scale: number }

local function add(
	ctx: Ctx,
	shape: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	extra: { [string]: any }?
): BasePart
	local s = ctx.scale
	local scaled = CFrame.new(cf.Position * s) * cf.Rotation
	local props: { [string]: any } = {
		Size = size * s,
		CFrame = ctx.root.CFrame * scaled,
		Color = color,
		Material = material or SMOOTH,
		Anchored = false,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Massless = true,
		CastShadow = size.Magnitude * s > 2,
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	local part: BasePart
	if shape == "ball" then
		props.Shape = Enum.PartType.Ball
		part = PartKit.part(ctx.model, props :: any)
	elseif shape == "ellipsoid" then
		part = PartKit.ellipsoid(ctx.model, props :: any)
	elseif shape == "wedge" then
		props.ClassName = "WedgePart"
		part = PartKit.part(ctx.model, props :: any)
	else
		part = PartKit.part(ctx.model, props :: any)
	end
	PartKit.weld(ctx.root, part)
	return part
end

local BUILDERS: { [string]: (Ctx) -> () } = {}

BUILDERS.gloomling = function(ctx)
	add(ctx, "ellipsoid", V3(2.6, 2.1, 2.5), L(0, 0.2, 0), VOID)
	add(ctx, "ellipsoid", V3(2.0, 1.2, 2.0), L(0, 0.75, 0.2), BRUISE)
	-- A cluster of mismatched eyes
	for i, p in
		{
			V3(-0.55, 0.65, -1.05),
			V3(0.5, 0.75, -1.0),
			V3(0.05, 1.05, -0.85),
			V3(-0.9, 0.25, -0.85),
			V3(0.95, 0.2, -0.8),
		}
	do
		local size = if i <= 2 then 0.5 else 0.3
		add(ctx, "ball", V3(size, size, size), CFrame.new(p), if i == 3 then SICK else GLOW, NEON)
	end
	-- Jagged grin
	add(ctx, "block", V3(1.5, 0.35, 0.2), L(0, -0.35, -1.12), Color3.fromRGB(8, 4, 10))
	for i = 0, 4 do
		add(ctx, "wedge", V3(0.22, 0.3, 0.1), L(-0.6 + i * 0.3, -0.25, -1.2, 180, 0, 0), BONE)
	end
	-- Dripping tendrils
	for i = 0, 4 do
		local a = rad(i * 72)
		add(
			ctx,
			"wedge",
			V3(0.45, 1.3, 0.45),
			L(math.cos(a) * 0.8, -1.2, math.sin(a) * 0.8, 180, i * 72, 0),
			VOID
		)
	end
end

BUILDERS.wailer = function(ctx)
	-- Robe tapering into smoke
	add(ctx, "ellipsoid", V3(2.2, 3.4, 1.8), L(0, -0.6, 0.1), Color3.fromRGB(34, 28, 44))
	for i = 0, 5 do
		add(
			ctx,
			"wedge",
			V3(0.9, 1.8, 0.4),
			CFrame.Angles(0, rad(i * 60), 0) * L(0, -2.4, 0.7, 180 - 10, 0, 0),
			Color3.fromRGB(28, 22, 36)
		)
	end
	-- Long hanging hair
	for i = 0, 6 do
		local x = -0.9 + i * 0.3
		add(
			ctx,
			"block",
			V3(0.28, 2.6 + (i % 3) * 0.4, 0.28),
			L(x, 0.7, 0.55 + math.abs(x) * 0.1),
			Color3.fromRGB(12, 10, 16)
		)
	end
	add(ctx, "ball", V3(1.9, 1.9, 1.9), L(0, 1.8, 0.2), Color3.fromRGB(12, 10, 16))
	-- Cracked mask with an open, wailing mouth
	add(ctx, "ellipsoid", V3(1.5, 1.9, 0.5), L(0, 1.65, -0.75), BONE)
	add(ctx, "ellipsoid", V3(0.55, 0.75, 0.2), L(0, 1.05, -0.98), Color3.fromRGB(10, 6, 12))
	for _, side in { -1, 1 } do
		add(ctx, "ellipsoid", V3(0.36, 0.22, 0.15), L(side * 0.35, 2.0, -0.98), BLOOD, NEON)
		add(
			ctx,
			"block",
			V3(0.06, 0.8, 0.06),
			L(side * 0.42, 1.55, -1.0, 0, 0, side * 15),
			Color3.fromRGB(60, 40, 50)
		)
		-- Long, bony arms
		add(ctx, "block", V3(0.35, 2.4, 0.35), L(side * 1.35, 0.1, -0.3, 20, 0, side * 22), BONE)
		for f = -1, 1 do
			add(
				ctx,
				"wedge",
				V3(0.12, 0.6, 0.12),
				L(side * 1.85 + f * 0.12, -1.15, -0.7, 200, 0, side * 10),
				BONE
			)
		end
	end
end

BUILDERS.brute = function(ctx)
	local hide = Color3.fromRGB(48, 40, 58)
	add(ctx, "ellipsoid", V3(3.6, 3.2, 2.7), L(0, 0.4, 0.2, 12, 0, 0), hide, Enum.Material.Basalt)
	add(ctx, "ellipsoid", V3(3.2, 1.8, 2.4), L(0, 1.75, 0.5, 20, 0, 0), hide, Enum.Material.Basalt)
	-- The hollow: a glowing wound through the chest
	add(ctx, "ball", V3(1.25, 1.25, 1.25), L(0, 0.55, -1.15), Color3.fromRGB(6, 2, 10))
	for i = 0, 7 do
		local a = rad(i * 45)
		add(
			ctx,
			"block",
			V3(0.38, 0.14, 0.14),
			L(math.cos(a) * 0.7, 0.55 + math.sin(a) * 0.7, -1.28, 0, 0, i * 45 + 90),
			GLOW,
			NEON
		)
	end
	-- Small head, one huge eye, horns
	add(ctx, "ball", V3(1.4, 1.4, 1.4), L(0, 2.1, -0.95), hide, Enum.Material.Basalt)
	add(ctx, "ellipsoid", V3(0.75, 0.55, 0.2), L(0, 2.15, -1.6), SICK, NEON)
	add(ctx, "ball", V3(0.28, 0.28, 0.28), L(0, 2.15, -1.7), VOID)
	for _, side in { -1, 1 } do
		add(
			ctx,
			"wedge",
			V3(0.35, 1.2, 0.4),
			L(side * 0.5, 2.95, -0.9, -15, 0, side * -25),
			BONE,
			Enum.Material.Marble
		)
		-- Huge arms dragging claws
		add(
			ctx,
			"ellipsoid",
			V3(1.2, 2.7, 1.2),
			L(side * 2.2, 0.2, -0.4, 10, 0, side * 10),
			hide,
			Enum.Material.Basalt
		)
		add(ctx, "ellipsoid", V3(1.5, 1.2, 1.5), L(side * 2.45, -1.4, -0.7), hide, Enum.Material.Basalt)
		for f = -1, 1 do
			add(
				ctx,
				"wedge",
				V3(0.25, 0.9, 0.3),
				L(side * 2.45 + f * 0.4, -2.2, -1.2, 200, 0, 0),
				BONE,
				Enum.Material.Marble
			)
		end
		add(ctx, "ellipsoid", V3(1.1, 1.6, 1.1), L(side * 0.9, -1.6, 0.4), hide, Enum.Material.Basalt)
		add(ctx, "block", V3(0.12, 1.6, 0.12), L(side * 1.2, 0.9, -1.2, 0, 0, side * 30), GLOW, NEON)
	end
end

-- Builds the rig standing on `groundPoint`.
function CurseModels.build(id: string, groundPoint: Vector3): Model
	local def = Enemies.ById[id]
	assert(def, "unknown curse " .. tostring(id))
	local scale = def.scale
	local model = Instance.new("Model")
	model.Name = def.name

	local rootSize = V3(2.4, 2.2, 2.4) * scale
	local root = PartKit.part(model, {
		Name = "HumanoidRootPart",
		Size = rootSize,
		CFrame = CFrame.new(groundPoint + V3(0, def.hipHeight + rootSize.Y / 2, 0)),
		Transparency = 1,
		Anchored = false,
		CanCollide = true,
		CanQuery = true,
		CanTouch = false,
		CastShadow = false,
	})
	model.PrimaryPart = root

	local ctx: Ctx = { model = model, root = root, scale = scale }
	BUILDERS[id](ctx)

	PartKit.particles(root, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(80, 30, 120), Color3.fromRGB(10, 0, 20)),
		LightEmission = 0.3,
		Size = PartKit.sequence({ { 0, 1.2 * scale }, { 1, 3 * scale } }),
		Transparency = PartKit.sequence({ { 0, 0.65 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1, 1.8),
		Rate = 5,
		Speed = NumberRange.new(0.5, 1),
		EmissionDirection = Enum.NormalId.Bottom,
	})

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = def.hipHeight
	humanoid.WalkSpeed = def.walkSpeed
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	return model
end

return CurseModels
