--!strict
-- A jointed Sorcerer rig built from primitives. Its parts and Motor6D joints use the R15 names
-- (HumanoidRootPart, LowerTorso, UpperTorso, Head, Left/RightUpperArm ..., and Root, Waist,
-- Neck, Left/RightShoulder, Elbow, Wrist, Hip, Knee, Ankle), so the same poses can drive a
-- Marketplace-item R15 rig later without changes.
--
-- Rig space: feet on y = 0, facing -Z. The anchored, invisible HumanoidRootPart is the
-- PrimaryPart; every other part hangs off it through the joints. Decorations (face, hair,
-- trim) are welded to the body part they belong to.
--
-- Poses are applied by multiplying a joint's rest C0 (`Rig.apply`). On a real R15 rig the same
-- CFrames go into Motor6D.Transform instead.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PartKit = require(Shared.Visuals.PartKit)

local Rig = {}

local V3 = Vector3.new
local rad = math.rad
local SMOOTH = Enum.Material.SmoothPlastic
local FABRIC = Enum.Material.Fabric
local NEON = Enum.Material.Neon

local DARK = Color3.fromRGB(26, 22, 30)
local WHITE = Color3.fromRGB(250, 248, 255)
local GOLD = Color3.fromRGB(232, 188, 92)

-- Scale used on the training post (1 = about 6.6 studs tall with hair).
Rig.PostScale = 1.15

export type PartDef = { name: string, size: Vector3, at: Vector3, shape: string? }
export type JointDef = { name: string, part0: string, part1: string, at: Vector3 }

-- Body parts (unscaled rig space). R15 proportions with a slightly larger, rounder head.
local PARTS: { PartDef } = {
	{ name = "HumanoidRootPart", size = V3(2, 2, 1), at = V3(0, 3.0, 0) },
	{ name = "LowerTorso", size = V3(1.9, 0.55, 1.0), at = V3(0, 2.95, 0) },
	{ name = "UpperTorso", size = V3(2.0, 1.5, 1.05), at = V3(0, 3.97, 0) },
	{ name = "Head", size = V3(1.75, 1.75, 1.75), at = V3(0, 5.55, 0), shape = "ball" },
}
local JOINTS: { JointDef } = {
	{ name = "Root", part0 = "HumanoidRootPart", part1 = "LowerTorso", at = V3(0, 2.95, 0) },
	{ name = "Waist", part0 = "LowerTorso", part1 = "UpperTorso", at = V3(0, 3.22, 0) },
	{ name = "Neck", part0 = "UpperTorso", part1 = "Head", at = V3(0, 4.72, 0) },
}
for _, side in { { n = "Right", s = 1 }, { n = "Left", s = -1 } } do
	local n, s = side.n, side.s
	local arm, leg = 1.42 * s, 0.5 * s
	table.insert(PARTS, { name = n .. "UpperArm", size = V3(0.72, 1.2, 0.72), at = V3(arm, 4.07, 0) })
	table.insert(PARTS, { name = n .. "LowerArm", size = V3(0.66, 1.05, 0.66), at = V3(arm, 2.94, 0) })
	table.insert(
		PARTS,
		{ name = n .. "Hand", size = V3(0.62, 0.62, 0.62), at = V3(arm, 2.2, 0), shape = "ball" }
	)
	table.insert(PARTS, { name = n .. "UpperLeg", size = V3(0.84, 1.22, 0.84), at = V3(leg, 2.08, 0) })
	table.insert(PARTS, { name = n .. "LowerLeg", size = V3(0.76, 1.2, 0.76), at = V3(leg, 0.88, 0) })
	table.insert(PARTS, { name = n .. "Foot", size = V3(0.8, 0.3, 1.15), at = V3(leg, 0.15, -0.14) })
	table.insert(
		JOINTS,
		{ name = n .. "Shoulder", part0 = "UpperTorso", part1 = n .. "UpperArm", at = V3(arm, 4.45, 0) }
	)
	table.insert(
		JOINTS,
		{ name = n .. "Elbow", part0 = n .. "UpperArm", part1 = n .. "LowerArm", at = V3(arm, 3.47, 0) }
	)
	table.insert(
		JOINTS,
		{ name = n .. "Wrist", part0 = n .. "LowerArm", part1 = n .. "Hand", at = V3(arm, 2.42, 0) }
	)
	table.insert(
		JOINTS,
		{ name = n .. "Hip", part0 = "LowerTorso", part1 = n .. "UpperLeg", at = V3(leg, 2.69, 0) }
	)
	table.insert(
		JOINTS,
		{ name = n .. "Knee", part0 = n .. "UpperLeg", part1 = n .. "LowerLeg", at = V3(leg, 1.48, 0) }
	)
	table.insert(
		JOINTS,
		{ name = n .. "Ankle", part0 = n .. "LowerLeg", part1 = n .. "Foot", at = V3(leg, 0.3, 0) }
	)
end
Rig.Parts = PARTS
-- Parent joints come before their children, so poses can be solved in this order.
Rig.Joints = JOINTS

type Ctx = { model: Model, base: CFrame, scale: number, parts: { [string]: BasePart } }

local function world(ctx: Ctx, cf: CFrame): CFrame
	local s = ctx.scale
	return ctx.base * (CFrame.new(cf.Position * s) * cf.Rotation)
end

local function newPart(
	ctx: Ctx,
	name: string,
	shape: string?,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): BasePart
	local props: { [string]: any } = {
		Name = name,
		Size = size * ctx.scale,
		CFrame = world(ctx, cf),
		Color = color,
		Material = material or SMOOTH,
		Anchored = false,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Massless = true,
		CastShadow = size.Magnitude > 1,
	}
	local part: BasePart
	if shape == "ball" then
		props.Shape = Enum.PartType.Ball
		part = PartKit.part(ctx.model, props :: any)
	elseif shape == "ellipsoid" then
		part = PartKit.ellipsoid(ctx.model, props :: any)
	elseif shape == "wedge" then
		props.ClassName = "WedgePart"
		part = PartKit.part(ctx.model, props :: any)
	elseif shape == "cyl" then
		-- Cylinder along local Y.
		props.Shape = Enum.PartType.Cylinder
		props.Size = V3(size.Y, size.X, size.Z) * ctx.scale
		props.CFrame = world(ctx, cf) * CFrame.Angles(0, 0, rad(90))
		part = PartKit.part(ctx.model, props :: any)
	else
		part = PartKit.part(ctx.model, props :: any)
	end
	return part
end

-- Decoration welded to body part `on`. `cf` is in rig space, like the body parts.
local function deco(
	ctx: Ctx,
	on: string,
	shape: string?,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): BasePart
	local part = newPart(ctx, on .. "Detail", shape, size, cf, color, material)
	local body = ctx.parts[on]
	local weld = Instance.new("Weld")
	weld.Name = "DetailWeld"
	weld.Part0 = body
	weld.Part1 = part
	weld.C0 = body.CFrame:Inverse() * part.CFrame
	weld.C1 = CFrame.new()
	weld.Parent = part
	return part
end

local function L(x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(rad(rx or 0), rad(ry or 0), rad(rz or 0))
end

local function dress(ctx: Ctx, look: { [string]: any })
	local hair, outfit, trim = look.hair, look.outfit, look.trim
	local head = 5.55
	-- Face (front is -Z)
	for _, s in { -1, 1 } do
		deco(ctx, "Head", nil, V3(0.26, 0.4, 0.1), L(s * 0.36, head - 0.08, -0.82), DARK)
		deco(ctx, "Head", nil, V3(0.17, 0.26, 0.08), L(s * 0.36, head - 0.12, -0.86), look.eyes or DARK, NEON)
		deco(ctx, "Head", nil, V3(0.07, 0.07, 0.05), L(s * 0.31, head + 0.02, -0.9), WHITE, NEON)
		deco(ctx, "Head", nil, V3(0.36, 0.07, 0.06), L(s * 0.38, head + 0.24, -0.82, 0, 0, s * -10), DARK)
	end
	deco(ctx, "Head", nil, V3(0.22, 0.05, 0.05), L(0, head - 0.5, -0.8), Color3.fromRGB(120, 60, 70))
	-- Spiky hair
	deco(ctx, "Head", "ball", V3(1.86, 1.86, 1.86), L(0, head + 0.2, 0.16), hair)
	for i, x in { -0.5, -0.17, 0.17, 0.5 } do
		local tilt = if i % 2 == 0 then 8 else -8
		deco(ctx, "Head", "wedge", V3(0.4, 0.42, 0.32), L(x, head + 0.62, -0.66, 160, 0, tilt), hair)
	end
	for i = 1, 7 do
		local a = (i - 4) * 24
		deco(
			ctx,
			"Head",
			"wedge",
			V3(0.5, 1.1, 0.66),
			CFrame.new(0, head + 0.82, 0.28)
				* CFrame.Angles(0, rad(a), 0)
				* CFrame.new(0, 0, 0.45)
				* CFrame.Angles(rad(-35), 0, 0),
			hair
		)
	end
	-- High-collared jacket
	deco(ctx, "UpperTorso", nil, V3(0.16, 1.4, 0.06), L(0, 3.97, -0.55), trim)
	for i = 0, 2 do
		deco(
			ctx,
			"UpperTorso",
			"ball",
			V3(0.14, 0.14, 0.14),
			L(0.2, 4.4 - i * 0.38, -0.56),
			GOLD,
			Enum.Material.Metal
		)
	end
	deco(ctx, "UpperTorso", "cyl", V3(1.25, 0.42, 1.12), L(0, 4.78, 0), outfit, FABRIC)
	deco(ctx, "UpperTorso", "cyl", V3(1.3, 0.07, 1.16), L(0, 5.0, 0), trim)
	deco(ctx, "LowerTorso", nil, V3(1.96, 0.24, 1.06), L(0, 3.1, 0), trim)
	if table.find(look.accessories or {}, "Hood") then
		deco(ctx, "UpperTorso", "ellipsoid", V3(1.7, 0.9, 0.8), L(0, 4.75, 0.62, -15, 0, 0), outfit, FABRIC)
	end
	for _, s in { -1, 1 } do
		local side = if s > 0 then "Right" else "Left"
		local x = 1.42 * s
		deco(ctx, side .. "LowerArm", nil, V3(0.7, 0.18, 0.7), L(x, 2.55, 0), trim)
		deco(ctx, side .. "UpperArm", "ball", V3(0.82, 0.82, 0.82), L(x, 4.5, 0), outfit, FABRIC)
	end
end

-- Builds the rig standing at `cf` (feet on cf, facing cf.LookVector).
function Rig.build(parent: Instance?, cf: CFrame, look: { [string]: any }, scale: number?): Model
	local model = Instance.new("Model")
	model.Name = "Sorcerer"
	local ctx: Ctx = { model = model, base = cf, scale = scale or 1, parts = {} }
	local colors: { [string]: Color3 } = {
		LowerTorso = look.pants,
		UpperTorso = look.outfit,
		Head = look.skin,
	}
	for _, def in PARTS do
		local color = colors[def.name]
		local material: Enum.Material? = if def.name == "UpperTorso" then FABRIC else nil
		if not color then
			if string.find(def.name, "Hand") then
				color = look.skin
			elseif string.find(def.name, "Foot") then
				color = DARK
			elseif string.find(def.name, "Arm") then
				color = look.outfit
				material = FABRIC
			else
				color = look.pants
			end
		end
		local part =
			newPart(ctx, def.name, def.shape, def.size, CFrame.new(def.at), color :: Color3, material)
		ctx.parts[def.name] = part
	end
	local root = ctx.parts.HumanoidRootPart
	root.Anchored = true
	root.Transparency = 1
	root.CastShadow = false
	model.PrimaryPart = root
	for _, def in JOINTS do
		local p0, p1 = ctx.parts[def.part0], ctx.parts[def.part1]
		local at = world(ctx, CFrame.new(def.at))
		local motor = Instance.new("Motor6D")
		motor.Name = def.name
		motor.Part0 = p0
		motor.Part1 = p1
		motor.C0 = p0.CFrame:Inverse() * at
		motor.C1 = p1.CFrame:Inverse() * at
		motor.Parent = p1
	end
	dress(ctx, look)
	-- Where the technique leaves the hand (follows the hand as it moves).
	local cast = Instance.new("Attachment")
	cast.Name = "Cast"
	cast.CFrame = CFrame.new(0, 0, -0.35 * ctx.scale)
	cast.Parent = ctx.parts.RightHand
	model:SetAttribute("RigScale", ctx.scale)
	model.Parent = parent
	return model
end

export type Joint = { motor: Motor6D, base: CFrame }

-- Joint handles with their rest C0, read once before any pose is applied.
function Rig.joints(model: Model): { [string]: Joint }
	local joints: { [string]: Joint } = {}
	for _, def in JOINTS do
		local part = model:FindFirstChild(def.part1)
		local motor = part and part:FindFirstChild(def.name)
		if motor and motor:IsA("Motor6D") then
			joints[def.name] = { motor = motor, base = motor.C0 }
		end
	end
	return joints
end

-- Applies a pose ({ [jointName]: CFrame }); joints it leaves out go back to rest.
function Rig.apply(joints: { [string]: Joint }, pose: { [string]: CFrame })
	for name, joint in joints do
		local offset = pose[name]
		joint.motor.C0 = if offset then joint.base * offset else joint.base
	end
end

-- Moves every part to where the joints put it. Roblox does this itself every frame; this is
-- for offline tools (tests, preview renders) that have no physics engine.
function Rig.solve(model: Model)
	local cframes: { [string]: CFrame } = {}
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	cframes.HumanoidRootPart = root.CFrame
	local parts: { [string]: BasePart } = {}
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			parts[d.Name] = d
		end
	end
	for _, def in JOINTS do
		local p1 = parts[def.part1]
		local motor = p1 and p1:FindFirstChild(def.name) :: Motor6D?
		local c0 = cframes[def.part0]
		if motor and c0 then
			local cf = c0 * motor.C0 * motor.C1:Inverse()
			cframes[def.part1] = cf
			p1.CFrame = cf
		end
	end
	for _, d in model:GetChildren() do
		local weld = d:FindFirstChild("DetailWeld")
		if d:IsA("BasePart") and weld and weld:IsA("Weld") then
			local on = weld.Part0
			local base = on and cframes[on.Name]
			if base then
				d.CFrame = base * weld.C0 * weld.C1:Inverse()
			end
		end
	end
	return cframes
end

return Rig
