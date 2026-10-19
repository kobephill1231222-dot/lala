--!strict
-- Code-driven technique animation for the jointed rig (Shared Prototype.Rig). A technique is a
-- set of key poses placed in time around the moment of contact (t = 0): anticipation before
-- it, recovery after it. The client samples it on the server's hit timestamps, so contact
-- lands on the exact moment the hit is credited.
--
-- A raw pose holds:
--   root   { rx, ry, rz, x, y, z }  the LowerTorso's offset (degrees, unscaled studs)
--   joints { [joint]: { rx, ry, rz } } upper-body joints (degrees)
--   feet   { Left = { x, z, yaw }, Right = { x, z, yaw } } where each ankle stands (rig space)
--          and which way the foot points (degrees)
-- Legs are solved with two-bone IK so the feet stay planted while the body lunges and twists.
--
-- Rotation conventions in this rig (front is -Z): +rx on a shoulder, elbow or hip swings
-- the limb forward; -rx on a knee bends it; +rx on a wrist lifts the fingers when the arm is
-- out front; +ry on Root, Waist or Neck turns to the left; +rz on a shoulder moves the hand
-- toward +X (the right).

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

-- Leg geometry of the rig (unscaled), from Prototype.Rig.
local ROOT_AT = Vector3.new(0, 2.95, 0)
local HIP_LOCAL = { Left = Vector3.new(-0.5, -0.26, 0), Right = Vector3.new(0.5, -0.26, 0) }
local THIGH = 2.69 - 1.48
local SHIN = 1.48 - 0.3
local ANKLE_Y = 0.3

local UPPER = {
	"Waist",
	"Neck",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
}
Techniques.UpperJoints = UPPER

local function pose(root: Vec, joints: { [string]: Vec }, feet: { [string]: Vec }): RawPose
	return { root = root, joints = joints, feet = feet }
end

-- Fighting stance: body turned a little to the right, guard up, weight low.
Techniques.Stance = pose({ 0, -20, 0, 0, -0.12, 0 }, {
	Waist = { -4, 5, 0 },
	Neck = { 0, 15, 0 },
	RightShoulder = { 30, 0, 12 },
	RightElbow = { 95, 0, 0 },
	RightWrist = { 0, 0, 0 },
	LeftShoulder = { 55, 0, -10 },
	LeftElbow = { 75, 0, 0 },
	LeftWrist = { 10, 0, 0 },
}, { Left = { -0.7, -0.55, -20 }, Right = { 0.75, 0.45, -20 } })

-- Resting while the Reward Chest is full: upright, arms loose, head down.
Techniques.Rest = pose({ 0, 0, 0, 0, 0, 0 }, {
	Waist = { 3, 0, 0 },
	Neck = { 14, 0, 0 },
	RightShoulder = { 6, 0, 6 },
	RightElbow = { 18, 0, 0 },
	RightWrist = { 0, 0, 0 },
	LeftShoulder = { 6, 0, -6 },
	LeftElbow = { 18, 0, 0 },
	LeftWrist = { 0, 0, 0 },
}, { Left = { -0.55, 0, 0 }, Right = { 0.55, 0, 0 } })

-- Kai's Spark Palm: coil back, step in and drive the right palm into the target.
local windup = pose({ 3, -45, 0, 0, -0.22, 0.25 }, {
	Waist = { 6, -25, 0 },
	Neck = { -5, 40, 0 },
	RightShoulder = { -25, 0, 20 },
	RightElbow = { 115, 0, 0 },
	RightWrist = { 30, 0, 0 },
	LeftShoulder = { 85, 0, -5 },
	LeftElbow = { 15, 0, 0 },
	LeftWrist = { 50, 0, 0 },
}, { Left = { -0.7, -0.55, -20 }, Right = { 0.75, 0.45, -20 } })
local coil = pose({ 4, -50, 0, 0, -0.25, 0.3 }, {
	Waist = { 7, -28, 0 },
	Neck = { -5, 44, 0 },
	RightShoulder = { -28, 0, 22 },
	RightElbow = { 118, 0, 0 },
	RightWrist = { 34, 0, 0 },
	LeftShoulder = { 86, 0, -5 },
	LeftElbow = { 12, 0, 0 },
	LeftWrist = { 55, 0, 0 },
}, { Left = { -0.7, -0.55, -20 }, Right = { 0.75, 0.45, -20 } })
local contact = pose({ -4, 20, 0, 0, -0.32, -0.45 }, {
	Waist = { -12, 22, 0 },
	Neck = { 5, -30, 0 },
	RightShoulder = { 90, 0, 40 },
	RightElbow = { 5, 0, 0 },
	RightWrist = { 70, 0, 0 },
	LeftShoulder = { 10, 0, -15 },
	LeftElbow = { 110, 0, 0 },
	LeftWrist = { 0, 0, 0 },
}, { Left = { -0.7, -0.85, -20 }, Right = { 0.75, 0.45, -20 } })
local impact = pose({ -5, 22, 0, 0, -0.34, -0.5 }, {
	Waist = { -13, 24, 0 },
	Neck = { 5, -32, 0 },
	RightShoulder = { 91, 0, 41 },
	RightElbow = { 3, 0, 0 },
	RightWrist = { 74, 0, 0 },
	LeftShoulder = { 8, 0, -15 },
	LeftElbow = { 112, 0, 0 },
	LeftWrist = { 0, 0, 0 },
}, { Left = { -0.7, -0.85, -20 }, Right = { 0.75, 0.45, -20 } })
local follow = pose({ -3, 16, 0, 0, -0.28, -0.4 }, {
	Waist = { -9, 18, 0 },
	Neck = { 3, -24, 0 },
	RightShoulder = { 84, 0, 36 },
	RightElbow = { 14, 0, 0 },
	RightWrist = { 50, 0, 0 },
	LeftShoulder = { 18, 0, -14 },
	LeftElbow = { 104, 0, 0 },
	LeftWrist = { 0, 0, 0 },
}, { Left = { -0.7, -0.8, -20 }, Right = { 0.75, 0.45, -20 } })

Techniques.SparkPalm = {
	name = "Spark Palm",
	anticipation = 0.42,
	recovery = 0.62,
	hand = "RightHand",
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
	local out = table.create(#a)
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
	local waist = joints.Waist or { 0, 0, 0 }
	joints.Waist = { waist[1] + 1.5 * s, waist[2], waist[3] }
	local neck = joints.Neck or { 0, 0, 0 }
	joints.Neck = { neck[1] - 1.0 * s, neck[2], neck[3] }
	local root = table.clone(raw.root)
	root[5] = (root[5] or 0) + 0.035 * s
	return { root = root, joints = joints, feet = raw.feet }
end

local function rotation(v: Vec): CFrame
	return CFrame.Angles(rad(v[1] or 0), rad(v[2] or 0), rad(v[3] or 0))
end

-- Two-bone IK for one leg. Returns hip, knee and ankle offsets that put the ankle on `foot`.
local function solveLeg(rootFrame: CFrame, side: string, foot: Vec): (CFrame, CFrame, CFrame)
	local target = Vector3.new(foot[1], ANKLE_Y, foot[2])
	local hip = HIP_LOCAL[side]
	local d = rootFrame:PointToObjectSpace(target) - hip
	-- Abduction from the sideways offset, then a planar solve in the leg's swing plane.
	local abduct = math.atan2(d.X, -d.Y)
	local down = math.sqrt(d.X * d.X + d.Y * d.Y)
	local dist =
		math.clamp(math.sqrt(down * down + d.Z * d.Z), math.abs(THIGH - SHIN) + 1e-3, THIGH + SHIN - 1e-4)
	local cosKnee = (THIGH * THIGH + SHIN * SHIN - dist * dist) / (2 * THIGH * SHIN)
	local knee = -(math.pi - math.acos(math.clamp(cosKnee, -1, 1)))
	local cosHip = (THIGH * THIGH + dist * dist - SHIN * SHIN) / (2 * THIGH * dist)
	local swing = math.atan2(-d.Z, down) + math.acos(math.clamp(cosHip, -1, 1))
	-- Abduct after the swing so the knee bends in the leg's own plane.
	local hipRot = CFrame.Angles(0, 0, abduct) * CFrame.Angles(swing, 0, 0)
	local kneeRot = CFrame.Angles(knee, 0, 0)
	-- Keep the sole flat and planted: it points where the pose says, whatever the body does.
	local level = CFrame.Angles(0, rad(foot[3] or 0), 0)
	local ankleRot = (rootFrame.Rotation * hipRot * kneeRot):Inverse() * level
	return hipRot, kneeRot, ankleRot
end

-- Turns a raw pose into joint offsets for Rig.apply. `scale` is the rig's build scale.
function Techniques.resolve(raw: RawPose, scale: number): { [string]: CFrame }
	local r = raw.root
	local rootRot = rotation(r)
	local rootOffset = Vector3.new(r[4] or 0, r[5] or 0, r[6] or 0)
	local out: { [string]: CFrame } = {}
	out.Root = CFrame.new(rootOffset * scale) * rootRot
	for _, name in UPPER do
		local v = raw.joints[name]
		if v then
			out[name] = rotation(v)
		end
	end
	local rootFrame = CFrame.new(ROOT_AT + rootOffset) * rootRot
	for _, side in { "Left", "Right" } do
		local foot = raw.feet[side]
		if foot then
			local hip, knee, ankle = solveLeg(rootFrame, side, foot)
			out[side .. "Hip"] = hip
			out[side .. "Knee"] = knee
			out[side .. "Ankle"] = ankle
		end
	end
	return out
end

return Techniques
