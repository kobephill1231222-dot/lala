--!strict
-- The 3D camera only exists so Roblox's default controls move your (invisible) character the
-- way the pixel screen suggests: it hangs above the character looking down, with north at the
-- top, so W walks up the screen, S down, A left and D right (thumbstick and gamepad too).
-- Nothing 3D is ever seen: the pixel world (WorldView) covers the screen.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CameraController = {}

CameraController.Height = 60
CameraController.Tilt = 6 -- studs south of straight-down, so "forward" is clearly north

-- Camera CFrame for a character at `position`.
function CameraController.frameFor(position: Vector3): CFrame
	local eye = position + Vector3.new(0, CameraController.Height, CameraController.Tilt)
	return CFrame.lookAt(eye, position, Vector3.new(0, 0, -1))
end

local function step()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local position = root.CFrame.Position
		camera.CFrame = CameraController.frameFor(position)
		camera.Focus = CFrame.new(position)
	end
end
CameraController.step = step

function CameraController.init(_registry: any) end

function CameraController.start()
	RunService:BindToRenderStep("JJKCamera", Enum.RenderPriority.Camera.Value + 1, step)
end

return CameraController
