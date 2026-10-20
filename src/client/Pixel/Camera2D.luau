--!strict
-- The 2D camera: keeps your character in the middle of the screen (clamped to the world's
-- edges) and converts between world studs, art pixels and screen pixels. It moves only in
-- whole art pixels, so the pixel art never shimmers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldMap = require(Shared.Config.WorldMap)
local Layout = require(Shared.Config.FarmLayout)
local Screen = require(script.Parent.Screen)

local Camera2D = {}

Camera2D.left = 0 -- art pixel at the screen's left edge
Camera2D.top = 0
Camera2D.focus = nil :: Vector3? -- world position being followed (override with setFocus)

local override: Vector3? = nil

-- World studs -> art pixels (whole pixels).
function Camera2D.toArt(position: Vector3): (number, number)
	local x, y = WorldMap.toPixels(position.X, position.Z)
	return math.floor(x + 0.5), math.floor(y + 0.5)
end

-- Art pixels -> world studs (y = 0).
function Camera2D.toWorld(px: number, py: number): Vector3
	local ppm = Layout.PixelsPerStud
	return Vector3.new(px / ppm - Layout.WorldHalfWidth, 0, py / ppm - Layout.WorldHalfDepth)
end

-- Art pixels -> screen pixels (for HUD-level things that point into the world).
function Camera2D.artToScreen(px: number, py: number): Vector2
	local s = Screen.scale
	return Vector2.new((px - Camera2D.left) * s, (py - Camera2D.top) * s)
end

function Camera2D.worldToScreen(position: Vector3): Vector2
	local px, py = Camera2D.toArt(position)
	return Camera2D.artToScreen(px, py)
end

function Camera2D.screenToWorld(point: Vector2): Vector3
	local s = Screen.scale
	return Camera2D.toWorld(point.X / s + Camera2D.left, point.Y / s + Camera2D.top)
end

-- Visible art rectangle (x0, y0, x1, y1).
function Camera2D.view(): (number, number, number, number)
	local w, h = Screen.viewArtSize()
	return Camera2D.left, Camera2D.top, Camera2D.left + w, Camera2D.top + h
end

-- Follow a fixed world point instead of the character (nil to go back to the character).
function Camera2D.setFocus(position: Vector3?)
	override = position
end

local function characterPosition(): Vector3?
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.CFrame.Position
	end
	return nil
end

-- Re-centres on the focus. Called every frame.
function Camera2D.update()
	local focus = override or characterPosition() or Camera2D.focus
	if not focus then
		return
	end
	Camera2D.focus = focus
	local w, h = Screen.viewArtSize()
	local worldW, worldH = WorldMap.pixelSize()
	local fx, fy = Camera2D.toArt(focus)
	local left = fx - math.floor(w / 2)
	local top = fy - math.floor(h / 2)
	-- Clamp to the world (centre it when the world is smaller than the screen)
	left = if worldW <= w then math.floor((worldW - w) / 2) else math.clamp(left, 0, worldW - w)
	top = if worldH <= h then math.floor((worldH - h) / 2) else math.clamp(top, 0, worldH - h)
	Camera2D.left, Camera2D.top = left, top
	Screen.scrollTo(left, top)
end

return Camera2D
