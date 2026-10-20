--!strict
-- The pixel world's screen: a full-screen ScreenGui that covers everything 3D, and inside it
-- the scrolling world, built at art-pixel size (1 UI pixel = 1 art pixel) and blown up by a
-- whole-number UIScale, so every art pixel is exactly S x S screen pixels.
--
--   JJKWorld (ScreenGui, DisplayOrder -10, no insets)
--     View (full screen, grass-coloured backdrop)
--       World (art size, UIScale = S, moved by Camera2D)
--         Ground   static ground and low props (chunks)
--         Floor    farm fittings: slots, pads, lane, Orb Box fill, Collect Pads
--         Actors   y-sorted: Sorcerers, Crates, players
--         High     tree canopies, roofs, tops of tall props (chunks)
--         Overlay  effects, labels, prompts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared.Pixel.Palette)
local WorldMap = require(Shared.Config.WorldMap)
local Signal = require(Shared.Util.Signal)

local Screen = {}

Screen.LayerNames = { "Ground", "Floor", "Actors", "High", "Overlay" }
Screen.scale = 1
Screen.size = Vector2.new(1280, 720)
Screen.Changed = Signal.new() -- (scale, size)

Screen.gui = nil :: ScreenGui?
Screen.view = nil :: Frame?
Screen.world = nil :: Frame?
Screen.layers = {} :: { [string]: Frame }

local uiScale: UIScale? = nil

-- Screen pixels per art pixel for a screen this tall: about 200 art pixels of height.
function Screen.scaleFor(height: number): number
	return math.max(1, math.floor(height / 200 + 0.5))
end

local function frame(parent: Instance, name: string, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = z
	f.Parent = parent
	return f
end

local function resize()
	local gui = Screen.gui
	if not gui then
		return
	end
	local ok, measured = pcall(function()
		return gui.AbsoluteSize
	end)
	local size = if ok and measured.X >= 1 and measured.Y >= 1 then measured else Screen.size
	local scale = Screen.scaleFor(size.Y)
	local changed = scale ~= Screen.scale or size ~= Screen.size
	Screen.size = size
	Screen.scale = scale
	if uiScale then
		uiScale.Scale = scale
	end
	if changed then
		Screen.Changed:Fire(scale, size)
	end
end

function Screen.start(parent: Instance?)
	if Screen.gui then
		return
	end
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "JJKWorld"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = -10
	Screen.gui = gui

	local view = Instance.new("Frame")
	view.Name = "View"
	view.BorderSizePixel = 0
	view.BackgroundColor3 = Palette.Grass
	view.Size = UDim2.fromScale(1, 1)
	view.ClipsDescendants = true
	view.Parent = gui
	Screen.view = view

	local w, h = WorldMap.pixelSize()
	local world = Instance.new("Frame")
	world.Name = "World"
	world.BackgroundTransparency = 1
	world.BorderSizePixel = 0
	world.Size = UDim2.fromOffset(w, h)
	world.Parent = view
	Screen.world = world
	local scale = Instance.new("UIScale")
	scale.Scale = Screen.scale
	scale.Parent = world
	uiScale = scale
	for i, name in Screen.LayerNames do
		Screen.layers[name] = frame(world, name, i)
	end

	gui.Parent = parent or player:WaitForChild("PlayerGui")
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	resize()
end

-- Moves the world so art pixel (left, top) is at the screen's top-left corner.
function Screen.scrollTo(left: number, top: number)
	local world = Screen.world
	if world then
		world.Position = UDim2.fromOffset(-left * Screen.scale, -top * Screen.scale)
	end
end

-- The view's size in art pixels (rounded up).
function Screen.viewArtSize(): (number, number)
	local s = Screen.scale
	return math.ceil(Screen.size.X / s), math.ceil(Screen.size.Y / s)
end

return Screen
