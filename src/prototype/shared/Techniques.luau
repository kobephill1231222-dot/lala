--!strict
-- Code-driven technique animation for the R6 rig (Prototype.Rig). A technique is a set of key
-- poses placed in time around the moment of contact (t = 0): anticipation before it, recovery
-- after it. The client samples it on the server's hit timestamps, so contact lands on the
-- exact moment the hit is credited.
--
-- A raw pose holds:
--   root   { rx, ry, rz, x, y, z }   the Torso's offset from the root (degrees, unscaled studs)
--   joints { [joint]: { rx, ry, rz } } Neck, Right Shoulder, Left Shoulder (degrees)
--   feet   { Left = { x, z, side }, ... } where each foot should stand (rig space), and
--          whether that leg leads (side 1) or trails (-1), which keeps its direction stable
-- R6 legs have no knees, so each hip aims its leg at that spot and tilts it just enough to keep
-- the sole on the ground: the feet stay where they are (sliding a little) while the body dips,
-- twists and lunges, and never cross.
--
-- Rotations are in the parent part's space (front is -Z): +rx on a shoulder or hip swings the
-- limb forward; +ry on Root or Neck turns to the left; +rz on the right shoulder lifts the arm
-- out to the right (-rz for the left arm).

local Techniques = {}

local rad = math.rad

export type Vec = { number }
export type RawPose = {
	root: Vec,
	joints: { [string]: Vec },
	feet: { [string]: Vec },
}
export type Key = { t: number, pose: RawPose, ease: string? }
export type Technique = {
	name: string,
	anticipation: number, -- seconds before contact the wind-up starts
	recovery: number, -- seconds after contact until back in stance
	keys: { Key },
	hand: string, -- part the hit leaves from
}

-- R6 leg geometry (unscaled), from Prototype.Rig: hips pivot at the Torso's bottom corners and
-- each sole is 2 studs below its pivot (and half a stud in).
local TORSO_AT = Vector3.new(0, 3, 0)
local HIP = { Left = Vector3.new(-1, -1, 0), Right = Vector3.new(1, -1, 0) }
local SOLE = { Left = Vector3.new(0.5, -2, 0), Right = Vector3.new(-0.5, -2, 0) }

local UPPER = { "Neck", "Right Shoulder", "Left Shoulder" }
Techniques.UpperJoints = UPPER

local function pose(root: Vec, joints: { [string]: Vec }, feet: { [string]: Vec }): RawPose
	return { root = root, joints = joints, feet = feet }
end

local FIGHT = { Left = { -0.75, -0.9, 1 }, Right = { 0.8, 0.85, -1 } }
local LUNGE = { Left = { -0.75, -1.3, 1 }, Right = { 0.8, 0.85, -1 } }

-- Fighting stance: turned a little to the right, lead arm up, weight low.
Techniques.Stance = pose({ 0, -18, 0, 0, -0.15, 0 }, {
	Neck = { 0, 16, 0 },
	["Right Shoulder"] = { 40, 0, 10 },
	["Left Shoulder"] = { 70, 0, -10 },
}, FIGHT)

-- Resting while the Reward Chest is full: upright, arms loose, head down.
Techniques.Rest = pose({ 0, 0, 0, 0, 0, 0 }, {
	Neck = { 16, 0, 0 },
	["Right Shoulder"] = { 6, 0, 4 },
	["Left Shoulder"] = { 6, 0, -4 },
}, { Left = { -0.6, 0, 0 }, Right = { 0.6, 0, 0 } })

-- Kai's Spark Palm: coil back, lunge in and drive the right palm into the target.
local windup = pose({ 4, -30, 0, 0, -0.3, 0.18 }, {
	Neck = { -4, 28, 0 },
	["Right Shoulder"] = { -50, 0, 25 },
	["Left Shoulder"] = { 90, 0, -5 },
}, FIGHT)
local coil = pose({ 5, -33, 0, 0, -0.32, 0.2 }, {
	Neck = { -4, 31, 0 },
	["Right Shoulder"] = { -55, 0, 28 },
	["Left Shoulder"] = { 92, 0, -5 },
}, FIGHT)
local contact = pose({ -8, 12, 0, 0, -0.42, -0.55 }, {
	Neck = { 6, -12, 0 },
	["Right Shoulder"] = { 98, 0, 10 },
	["Left Shoulder"] = { -35, 0, -10 },
}, LUNGE)
local impact = pose({ -9, 14, 0, 0, -0.44, -0.6 }, {
	Neck = { 6, -14, 0 },
	["Right Shoulder"] = { 99, 0, 11 },
	["Left Shoulder"] = { -38, 0, -10 },
}, LUNGE)
local follow = pose({ -6, 10, 0, 0, -0.38, -0.5 }, {
	Neck = { 4, -10, 0 },
	["Right Shoulder"] = { 92, 0, 8 },
	["Left Shoulder"] = { -25, 0, -10 },
}, LUNGE)

Techniques.SparkPalm = {
	name = "Spark Palm",
	anticipation = 0.42,
	recovery = 0.62,
	hand = "Right Arm",
	keys = {
		{ t = -0.42, pose = Techniques.Stance },
		{ t = -0.2, pose = windup, ease = "inOut" }, -- anticipation: coil back
		{ t = -0.1, pose = coil, ease = "inOut" }, -- held coil
		{ t = 0, pose = contact, ease = "in" }, -- strike accelerates into contact
		{ t = 0.07, pose = impact }, -- hit-stop
		{ t = 0.22, pose = follow, ease = "out" }, -- follow-through
		{ t = 0.62, pose = Techniques.Stance, ease = "inOut" }, -- recovery
	},
} :: Technique

local function ease(kind: string?, a: number): number
	if kind == "in" then
		return a * a * a
	elseif kind == "out" then
		local b = 1 - a
		return 1 - b * b
	elseif kind == "inOut" then
		return a * a * (3 - 2 * a)
	end
	return a
end

local function lerpVec(a: Vec, b: Vec, w: number): Vec
	local out = table.create(math.max(#a, #b))
	for i = 1, math.max(#a, #b) do
		local x, y = a[i] or 0, b[i] or 0
		out[i] = x + (y - x) * w
	end
	return out
end

-- Blends two raw poses (w = 0 gives a, 1 gives b).
function Techniques.blend(a: RawPose, b: RawPose, w: number): RawPose
	if w <= 0 then
		return a
	elseif w >= 1 then
		return b
	end
	local joints = {}
	for _, name in UPPER do
		joints[name] = lerpVec(a.joints[name] or { 0, 0, 0 }, b.joints[name] or { 0, 0, 0 }, w)
	end
	return {
		root = lerpVec(a.root, b.root, w),
		joints = joints,
		feet = {
			Left = lerpVec(a.feet.Left, b.feet.Left, w),
			Right = lerpVec(a.feet.Right, b.feet.Right, w),
		},
	}
end

-- Raw pose `u` seconds after contact (negative = anticipation). Outside the technique's
-- window this is the stance.
function Techniques.sample(tech: Technique, u: number): RawPose
	local keys = tech.keys
	if u <= keys[1].t or u >= keys[#keys].t then
		return Techniques.Stance
	end
	for i = 2, #keys do
		local k = keys[i]
		if u <= k.t then
			local prev = keys[i - 1]
			local a = (u - prev.t) / (k.t - prev.t)
			return Techniques.blend(prev.pose, k.pose, ease(k.ease, a))
		end
	end
	return Techniques.Stance
end

-- Small idle motion on top of any pose: breathing and a slight bob.
function Techniques.breathe(raw: RawPose, clock: number, amount: number): RawPose
	if amount <= 0 then
		return raw
	end
	local s = math.sin(clock * math.pi * 2 / 3.2) * amount
	local joints = table.clone(raw.joints)
	local neck = joints.Neck or { 0, 0, 0 }
	joints.Neck = { neck[1] - 1.5 * s, neck[2], neck[3] }
	local root = table.clone(raw.root)
	root[1] = (root[1] or 0) + 1.2 * s
	root[5] = (root[5] or 0) + 0.035 * s
	return { root = root, joints = joints, feet = raw.feet }
end

local function rotation(v: Vec): CFrame
	return CFrame.Angles(rad(v[1] or 0), rad(v[2] or 0), rad(v[3] or 0))
end

-- Hip rotation that aims this leg at its foot spot with the sole on the ground (y = 0).
local function solveHip(torso: CFrame, leg: string, foot: Vec): CFrame
	local pivot = torso * HIP[leg]
	local rest = torso.Rotation * SOLE[leg] -- where the sole would be with the hip at rest
	local length = rest.Magnitude
	local h = pivot.Y
	local want: Vector3
	if h >= length then
		want = Vector3.new(0, -length, 0) -- out of reach: hang straight down
	else
		-- Toward the spot, nudged the way the leg leads or trails, so the direction can't flip
		-- when the hip passes over the spot.
		local forward = Vector3.new(torso.LookVector.X, 0, torso.LookVector.Z).Unit
		local flat = Vector3.new(foot[1] - pivot.X, 0, foot[2] - pivot.Z) + forward * (0.6 * (foot[3] or 0))
		local dir = if flat.Magnitude > 1e-4 then flat.Unit else Vector3.new(0, 0, 0)
		want = dir * math.sqrt(length * length - h * h) - Vector3.new(0, h, 0)
	end
	-- Shortest rotation (in the Torso's space) from the rest leg onto the wanted one.
	local a = SOLE[leg].Unit
	local b = torso.Rotation:Inverse() * want.Unit
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-6 then
		return CFrame.new()
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(a:Dot(b), -1, 1)))
end

-- Turns a raw pose into joint offsets for Rig.apply. `scale` is the rig's build scale.
function Techniques.resolve(raw: RawPose, scale: number): { [string]: CFrame }
	local r = raw.root
	local rootRot = rotation(r)
	local rootOffset = Vector3.new(r[4] or 0, r[5] or 0, r[6] or 0)
	-- Rigid legs can only stand on their spots at one height. The body rises or sinks to the
	-- height the lower-reaching leg needs, so that foot lands on its spot and the other one
	-- lands just past its own (never floating). The pose's own height is only a starting point.
	local probe = CFrame.new(TORSO_AT + rootOffset) * rootRot
	local adjust = math.huge
	for _, leg in { "Left", "Right" } do
		local foot = raw.feet[leg]
		if foot then
			local pivot = probe * HIP[leg]
			local length = SOLE[leg].Magnitude
			local dist = math.min(Vector3.new(foot[1] - pivot.X, 0, foot[2] - pivot.Z).Magnitude, length)
			adjust = math.min(adjust, math.sqrt(length * length - dist * dist) - pivot.Y)
		end
	end
	if adjust < math.huge then
		rootOffset += Vector3.new(0, adjust, 0)
	end
	local out: { [string]: CFrame } = {}
	out.RootJoint = CFrame.new(rootOffset * scale) * rootRot
	for _, name in UPPER do
		local v = raw.joints[name]
		if v then
			out[name] = rotation(v)
		end
	end
	local torso = CFrame.new(TORSO_AT + rootOffset) * rootRot
	for _, leg in { "Left", "Right" } do
		local foot = raw.feet[leg]
		if foot then
			out[leg .. " Hip"] = solveHip(torso, leg, foot)
		end
	end
	return out
end

return Techniques
