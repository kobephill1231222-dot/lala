--!strict
-- A jointed R6 Sorcerer rig built from primitives: the standard R6 parts (HumanoidRootPart,
-- Torso, Head, Left/Right Arm, Left/Right Leg), the standard R6 Motor6Ds (RootJoint, Neck,
-- Left/Right Shoulder, Left/Right Hip) with the standard C0/C1 offsets, and a Humanoid set to
-- RigType R6. A Marketplace R6 rig (or HumanoidDescription) can replace it without changes.
--
-- Rig space: feet on y = 0, facing -Z. The anchored, invisible HumanoidRootPart is the
-- PrimaryPart; every other part hangs off it through the joints. Decorations (face, hair,
-- trim) are welded to the body part they belong to.
--
-- Poses are rotations in the parent part's space (+X right, +Y up, -Z forward). R6 joint frames
-- are rotated, so `Rig.apply` converts each pose into the joint's own frame. On a rig driven by
-- an Animator the same converted CFrame goes into Motor6D.Transform.

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

-- Scale used on the training post (1 = a standard 5-stud R6 character).
Rig.PostScale = 1.2

export type PartDef = { name: string, size: Vector3, at: Vector3 }
export type JointDef = { name: string, parent: string, part0: string, part1: string, c0: CFrame, c1: CFrame }

-- Standard R6 body (unscaled rig space).
local PARTS: { PartDef } = {
	{ name = "HumanoidRootPart", size = V3(2, 2, 1), at = V3(0, 3, 0) },
	{ name = "Torso", size = V3(2, 2, 1), at = V3(0, 3, 0) },
	{ name = "Head", size = V3(2, 1, 1), at = V3(0, 4.5, 0) },
	{ name = "Right Arm", size = V3(1, 2, 1), at = V3(1.5, 3, 0) },
	{ name = "Left Arm", size = V3(1, 2, 1), at = V3(-1.5, 3, 0) },
	{ name = "Right Leg", size = V3(1, 2, 1), at = V3(0.5, 1, 0) },
	{ name = "Left Leg", size = V3(1, 2, 1), at = V3(-0.5, 1, 0) },
}

local function cf(x: number, y: number, z: number, r: { number }): CFrame
	return CFrame.new(x, y, z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
end
local ROOT = { -1, 0, 0, 0, 0, 1, 0, 1, 0 }
local RIGHT = { 0, 0, 1, 0, 1, 0, -1, 0, 0 }
local LEFT = { 0, 0, -1, 0, 1, 0, 1, 0, 0 }

-- Standard R6 joints, parents before children (poses are solved in this order).
local JOINTS: { JointDef } = {
	{
		name = "RootJoint",
		parent = "HumanoidRootPart",
		part0 = "HumanoidRootPart",
		part1 = "Torso",
		c0 = cf(0, 0, 0, ROOT),
		c1 = cf(0, 0, 0, ROOT),
	},
	{
		name = "Neck",
		parent = "Torso",
		part0 = "Torso",
		part1 = "Head",
		c0 = cf(0, 1, 0, ROOT),
		c1 = cf(0, -0.5, 0, ROOT),
	},
	{
		name = "Right Shoulder",
		parent = "Torso",
		part0 = "Torso",
		part1 = "Right Arm",
		c0 = cf(1, 0.5, 0, RIGHT),
		c1 = cf(-0.5, 0.5, 0, RIGHT),
	},
	{
		name = "Left Shoulder",
		parent = "Torso",
		part0 = "Torso",
		part1 = "Left Arm",
		c0 = cf(-1, 0.5, 0, LEFT),
		c1 = cf(0.5, 0.5, 0, LEFT),
	},
	{
		name = "Right Hip",
		parent = "Torso",
		part0 = "Torso",
		part1 = "Right Leg",
		c0 = cf(1, -1, 0, RIGHT),
		c1 = cf(0.5, 1, 0, RIGHT),
	},
	{
		name = "Left Hip",
		parent = "Torso",
		part0 = "Torso",
		part1 = "Left Leg",
		c0 = cf(-1, -1, 0, LEFT),
		c1 = cf(-0.5, 1, 0, LEFT),
	},
}
Rig.Parts = PARTS
Rig.Joints = JOINTS

type Ctx = { model: Model, base: CFrame, scale: number, parts: { [string]: BasePart } }

local function scaled(c: CFrame, s: number): CFrame
	return CFrame.new(c.Position * s) * c.Rotation
end

local function world(ctx: Ctx, c: CFrame): CFrame
	return ctx.base * scaled(c, ctx.scale)
end

local function newPart(
	ctx: Ctx,
	name: string,
	shape: string?,
	size: Vector3,
	at: CFrame,
	color: Color3,
	material: Enum.Material?
): BasePart
	local props: { [string]: any } = {
		Name = name,
		Size = size * ctx.scale,
		CFrame = world(ctx, at),
		Color = color,
		Material = material or SMOOTH,
		Anchored = false,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Massless = true,
		CastShadow = size.Magnitude > 1,
	}
	if shape == "ball" then
		props.Shape = Enum.PartType.Ball
	elseif shape == "wedge" then
		props.ClassName = "WedgePart"
	end
	return PartKit.part(ctx.model, props :: any)
end

-- Decoration welded to body part `on`. `at` is in rig space, like the body parts.
local function deco(
	ctx: Ctx,
	on: string,
	shape: string?,
	size: Vector3,
	at: CFrame,
	color: Color3,
	material: Enum.Material?
): BasePart
	local part = newPart(ctx, (string.gsub(on, " ", "")) .. "Detail", shape, size, at, color, material)
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
	local skin, hair, outfit, trim = look.skin, look.hair, look.outfit, look.trim
	local head = 4.5
	-- Face on the front of the classic head (front is -Z, about 0.62 from the centre)
	for _, s in { -1, 1 } do
		deco(ctx, "Head", nil, V3(0.22, 0.32, 0.06), L(s * 0.26, head - 0.02, -0.6), DARK)
		deco(ctx, "Head", nil, V3(0.14, 0.2, 0.05), L(s * 0.26, head - 0.06, -0.63), look.eyes or DARK, NEON)
		deco(ctx, "Head", nil, V3(0.06, 0.06, 0.04), L(s * 0.22, head + 0.06, -0.65), WHITE, NEON)
		deco(ctx, "Head", nil, V3(0.3, 0.06, 0.05), L(s * 0.28, head + 0.22, -0.6, 0, 0, s * -10), DARK)
	end
	deco(ctx, "Head", nil, V3(0.2, 0.05, 0.05), L(0, head - 0.34, -0.6), Color3.fromRGB(120, 60, 70))
	-- Spiky hair: a cap over the head plus swept spikes
	deco(ctx, "Head", nil, V3(1.36, 0.42, 1.36), L(0, head + 0.5, 0.04), hair)
	deco(ctx, "Head", nil, V3(1.36, 0.95, 0.3), L(0, head + 0.12, 0.56), hair)
	for i, x in { -0.45, -0.15, 0.15, 0.45 } do
		local tilt = if i % 2 == 0 then 8 else -8
		deco(ctx, "Head", "wedge", V3(0.32, 0.36, 0.26), L(x, head + 0.42, -0.6, 160, 0, tilt), hair)
	end
	for i = 1, 7 do
		local a = (i - 4) * 24
		deco(
			ctx,
			"Head",
			"wedge",
			V3(0.42, 0.9, 0.55),
			CFrame.new(0, head + 0.68, 0.2)
				* CFrame.Angles(0, rad(a), 0)
				* CFrame.new(0, 0, 0.38)
				* CFrame.Angles(rad(-35), 0, 0),
			hair
		)
	end
	-- High-collared jacket
	deco(ctx, "Torso", nil, V3(0.16, 1.9, 0.06), L(0, 3, -0.53), trim)
	for i = 0, 2 do
		deco(
			ctx,
			"Torso",
			"ball",
			V3(0.14, 0.14, 0.14),
			L(0.22, 3.55 - i * 0.45, -0.54),
			GOLD,
			Enum.Material.Metal
		)
	end
	deco(ctx, "Torso", nil, V3(1.4, 0.3, 1.1), L(0, 4.1, 0), outfit, FABRIC)
	deco(ctx, "Torso", nil, V3(2.04, 0.26, 1.04), L(0, 2.2, 0), trim)
	if table.find(look.accessories or {}, "Hood") then
		deco(ctx, "Torso", nil, V3(1.5, 0.7, 0.5), L(0, 3.95, 0.7, -12, 0, 0), outfit, FABRIC)
	end
	for _, s in { -1, 1 } do
		local arm = if s > 0 then "Right Arm" else "Left Arm"
		local leg = if s > 0 then "Right Leg" else "Left Leg"
		local x = 1.5 * s
		-- Cuffs and bare hands at the bottom of the sleeves
		deco(ctx, arm, nil, V3(1.04, 0.2, 1.04), L(x, 2.5, 0), trim)
		deco(ctx, arm, nil, V3(1.02, 0.42, 1.02), L(x, 2.2, 0), skin)
		-- Shoes
		deco(ctx, leg, nil, V3(1.04, 0.36, 1.12), L(0.5 * s, 0.18, -0.05), DARK)
	end
end

-- Builds the rig standing at `at` (feet on it, facing its LookVector).
function Rig.build(parent: Instance?, at: CFrame, look: { [string]: any }, scale: number?): Model
	local model = Instance.new("Model")
	model.Name = "Sorcerer"
	local ctx: Ctx = { model = model, base = at, scale = scale or 1, parts = {} }
	local colors: { [string]: Color3 } = {
		Torso = look.outfit,
		Head = look.skin,
		["Right Arm"] = look.outfit,
		["Left Arm"] = look.outfit,
		["Right Leg"] = look.pants,
		["Left Leg"] = look.pants,
	}
	for _, def in PARTS do
		local material: Enum.Material? = if colors[def.name] == look.outfit then FABRIC else nil
		ctx.parts[def.name] =
			newPart(ctx, def.name, nil, def.size, CFrame.new(def.at), colors[def.name] or DARK, material)
	end
	-- The classic R6 head shape
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = V3(1.25, 1.25, 1.25)
	mesh.Parent = ctx.parts.Head
	local root = ctx.parts.HumanoidRootPart
	root.Anchored = true
	root.Transparency = 1
	root.CastShadow = false
	model.PrimaryPart = root
	for _, def in JOINTS do
		local motor = Instance.new("Motor6D")
		motor.Name = def.name
		motor.Part0 = ctx.parts[def.part0]
		motor.Part1 = ctx.parts[def.part1]
		motor.C0 = scaled(def.c0, ctx.scale)
		motor.C1 = scaled(def.c1, ctx.scale)
		motor.Parent = ctx.parts[def.parent]
	end
	-- A real R6 Humanoid (inert: no name tag, no states), so clothing and HumanoidDescription
	-- apply like on any R6 character.
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.EvaluateStateMachine = false
	humanoid.Parent = model
	dress(ctx, look)
	-- Where the technique leaves the hand (follows the arm as it moves).
	local cast = Instance.new("Attachment")
	cast.Name = "Cast"
	cast.CFrame = CFrame.new(0, -1.1 * ctx.scale, 0)
	cast.Parent = ctx.parts["Right Arm"]
	model:SetAttribute("RigScale", ctx.scale)
	model.Parent = parent
	return model
end

export type Joint = { motor: Motor6D, base: CFrame, toJoint: CFrame, fromJoint: CFrame }

-- Joint handles with their rest C0, read once before any pose is applied.
function Rig.joints(model: Model): { [string]: Joint }
	local joints: { [string]: Joint } = {}
	for _, def in JOINTS do
		local holder = model:FindFirstChild(def.parent)
		local motor = holder and holder:FindFirstChild(def.name)
		if motor and motor:IsA("Motor6D") then
			local r = motor.C0.Rotation
			joints[def.name] = { motor = motor, base = motor.C0, toJoint = r:Inverse(), fromJoint = r }
		end
	end
	return joints
end

-- A pose offset (parent-part space) in a joint's own frame: what Motor6D.Transform takes.
function Rig.transform(joint: Joint, offset: CFrame): CFrame
	return joint.toJoint * offset * joint.fromJoint
end

-- Applies a pose ({ [jointName]: CFrame } in parent-part space); joints left out go to rest.
function Rig.apply(joints: { [string]: Joint }, pose: { [string]: CFrame })
	for name, joint in joints do
		local offset = pose[name]
		joint.motor.C0 = if offset then joint.base * Rig.transform(joint, offset) else joint.base
	end
end

-- Moves every part to where the joints put it. Roblox does this itself every frame; this is
-- for offline tools (tests, preview renders) that have no physics engine.
function Rig.solve(model: Model)
	local parts: { [string]: BasePart } = {}
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			parts[d.Name] = d
		end
	end
	local cframes: { [string]: CFrame } = { HumanoidRootPart = parts.HumanoidRootPart.CFrame }
	for _, def in JOINTS do
		local holder = parts[def.parent]
		local motor = holder and holder:FindFirstChild(def.name) :: Motor6D?
		local c0 = cframes[def.part0]
		if motor and c0 then
			local c = c0 * motor.C0 * motor.C1:Inverse()
			cframes[def.part1] = c
			parts[def.part1].CFrame = c
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
