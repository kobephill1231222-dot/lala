--!nocheck
-- Bakes the training-post prototype (docs/NEXT_STEPS_PROPOSAL.md, Decision C) into its own
-- place file, so it opens in Studio with the courtyard, the Sorcerer and the lighting in place.
-- Usage: lune run tools/lune/prototype_bake.luau <in.rbxl> <out.rbxl> [preview.json]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local Sandbox = require("./lib/Sandbox")
local Export = require("./lib/Export")

local input = process.args[1] or "build/prototype.rbxl"
local output = process.args[2] or "dist/Prototype.rbxl"
local previewPath = process.args[3]

local game = Sandbox.loadPlace(input)
local sb = Sandbox.new(game)
local Courtyard = sb.requirePath("ServerScriptService/Prototype/Courtyard")
local Atmosphere = sb.requirePath("ServerScriptService/Map/Atmosphere")

local workspace = game:GetService("Workspace")
local existing = workspace:FindFirstChild(Courtyard.Name)
if existing then
	existing:Destroy()
end
local yard = Courtyard.build(workspace)
Atmosphere.apply(game:GetService("Lighting"))

local parts = 0
for _, d in yard:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	end
end
print(string.format("Built training courtyard: %d parts", parts))

local function check(cond, msg)
	if not cond then
		error("prototype bake check failed: " .. msg)
	end
end
local post = yard:FindFirstChild("Post")
check(post and post:FindFirstChild("Spot") and post:FindFirstChild("Sorcerer"), "post, spot and Sorcerer")
local rig = post.Sorcerer
check(rig.PrimaryPart and rig.PrimaryPart.Anchored, "rig root anchored")
local Rig = sb.requirePath("ReplicatedStorage/Prototype/Rig")
local joints = Rig.joints(rig)
for _, def in Rig.Joints do
	check(joints[def.name], "joint " .. def.name)
end
local dummy = yard:FindFirstChild("Dummy")
check(dummy and dummy.Body:FindFirstChild("Spring") and dummy.Body:FindFirstChild("HitPoint"), "dummy")
local chest = yard:FindFirstChild("Chest")
check(
	chest and chest.Body:FindFirstChild("Prompt") and chest.Body:FindFirstChild("Label"),
	"chest prompt and label"
)
check(chest.Lid:FindFirstChild("Hinge") and chest:FindFirstChild("Gold"), "chest lid and gold")
check(
	yard:FindFirstChild("CollectPad") and yard.CollectPad:GetAttribute("TouchAction") == "Collect",
	"collect pad"
)
local board = yard:FindFirstChild("ReviewBoard")
check(
	board
		and board.Board:FindFirstChild("FastPromptAnchor")
		and board.Board:FindFirstChild("FillPromptAnchor"),
	"review board"
)
check(yard:FindFirstChild("Spawn"), "spawn")

fs.writeDir("dist")
fs.writeFile(output, roblox.serializePlace(game))
print("Wrote " .. output)

if previewPath then
	fs.writeFile(previewPath, serde.encode("json", Export.collect(yard)))
	print("Wrote preview scene " .. previewPath)
end
