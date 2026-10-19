--!strict
-- Top-down camera (Shared/Visuals/TopDownCamera). Once your farm is known, the view turns so
-- Your Farm sits upright on screen: its back at the top, its entrance and the plaza below.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared.Config.FarmLayout)
local TopDownCamera = require(Shared.Visuals.TopDownCamera)

local CameraController = {}

local registry: any
local orientedFarm: number? = nil

-- Screen-up for a farm: from its entrance toward its back (away from the plaza).
function CameraController.yawFor(farm: number): number
	return TopDownCamera.yawFacing(-Layout.farmCFrame(farm).LookVector)
end

local function orient()
	local farm = registry.StateController.farm()
	if farm and farm ~= orientedFarm then
		-- Snap on the first assignment (you spawn there); ease on any later change.
		TopDownCamera.setYaw(CameraController.yawFor(farm), orientedFarm == nil)
		orientedFarm = farm
	end
end

function CameraController.init(r: any)
	registry = r
end

-- Tall gameplay objects stay solid: the Orb Box, the Crate Shop's display crates, and
-- everything the server places at runtime (Sorcerers and Crates on farms).
function CameraController.keep(part: BasePart): boolean
	return part:FindFirstAncestor("OrbBox") ~= nil
		or part:FindFirstAncestor("Displays") ~= nil
		or part:FindFirstAncestor("Runtime") ~= nil
end

function CameraController.start()
	TopDownCamera.start({ workspace:WaitForChild("JJKFarmMap") }, CameraController.keep)
	orient()
	registry.StateController.Changed:Connect(orient)
end

return CameraController
