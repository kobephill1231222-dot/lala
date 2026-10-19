--!nocheck
-- Exports preview scenes of the prototype's strike, one per frame, by posing the real rig with
-- the real technique (Prototype.Techniques) and solving the joints offline. The dummy rocks
-- back from contact like the client plays it. For tools/preview/render.mjs.
-- Usage: lune run tools/lune/prototype_frames.luau dist/Prototype.rbxl <outDir> [fps]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local Sandbox = require("./lib/Sandbox")
local Export = require("./lib/Export")

local placePath = process.args[1] or "dist/Prototype.rbxl"
local outDir = process.args[2] or "build/strike"
local fps = tonumber(process.args[3]) or 20

local game = Sandbox.loadPlace(placePath)
local sb = Sandbox.new(game)
local Rig = sb.requirePath("ReplicatedStorage/Prototype/Rig")
local Techniques = sb.requirePath("ReplicatedStorage/Prototype/Techniques")

local yard = game:GetService("Workspace").TrainingCourtyard
local rig = yard.Post.Sorcerer
local joints = Rig.joints(rig)
local scale = rig:GetAttribute("RigScale")
local tech = Techniques.SparkPalm
local body = yard.Dummy.Body
local spring = body.Spring
local springBase = spring.C0
local base = yard.Dummy.Base

-- Same damped rock as the client's TrainingView.
local function dummyAngle(age)
	if age < 0 then
		return 0
	end
	return 15 * math.exp(-5.5 * age) * math.sin(15 * age)
end

local function poseDummy(angle)
	spring.C0 = springBase * roblox.CFrame.Angles(math.rad(angle), 0, 0)
	local cf = base.CFrame * spring.C0 * spring.C1:Inverse()
	local old = body.CFrame
	body.CFrame = cf
	local delta = cf * old:Inverse()
	for _, part in yard.Dummy:GetChildren() do
		if part:IsA("BasePart") and part:FindFirstChild("DetailWeld") then
			part.CFrame = delta * part.CFrame
		end
	end
end

fs.writeDir(outDir)
local frames = {}
local start, finish = -tech.anticipation - 0.1, tech.recovery + 0.1
local n = 0
local u = start
while u <= finish + 1e-6 do
	n += 1
	Rig.apply(joints, Techniques.resolve(Techniques.sample(tech, u), scale))
	Rig.solve(rig)
	poseDummy(dummyAngle(u))
	local name = string.format("frame_%02d", n)
	fs.writeFile(outDir .. "/" .. name .. ".json", serde.encode("json", Export.collect(yard)))
	table.insert(frames, { name = name, u = math.floor(u * 1000 + 0.5) / 1000 })
	u += 1 / fps
end
-- Key poses for stills
for _, key in
	{
		{ "key_stance", nil },
		{ "key_windup", -0.1 },
		{ "key_contact", 0 },
		{ "key_follow", 0.22 },
		{ "key_rest", "rest" },
	}
do
	local raw
	if key[2] == "rest" then
		raw = Techniques.Rest
	elseif key[2] then
		raw = Techniques.sample(tech, key[2])
	else
		raw = Techniques.Stance
	end
	Rig.apply(joints, Techniques.resolve(raw, scale))
	Rig.solve(rig)
	poseDummy(if type(key[2]) == "number" then dummyAngle(key[2]) else 0)
	fs.writeFile(outDir .. "/" .. key[1] .. ".json", serde.encode("json", Export.collect(yard)))
end
fs.writeFile(outDir .. "/frames.json", serde.encode("json", frames))
print(string.format("Wrote %d strike frames and 5 key poses to %s", n, outDir))
