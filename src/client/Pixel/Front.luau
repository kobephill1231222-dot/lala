--!strict
-- The world's front layer: a ScreenGui above the HUD (DisplayOrder 15: over JJKFarmUI's 10,
-- under the Reveal card's 20) for the few world things the HUD must never hide: the interaction
-- prompt, the guide arrows and floating text. It mirrors the scrolling world exactly (same
-- art-pixel grid, same whole-number UIScale), and it knows which parts of the screen the HUD
-- and other cards cover ("blockers"), so those things can be placed clear of them.
--
--   Front.start()
--   Front.world     -- art pixels in world coordinates (scrolls with the world, like an Overlay)
--   Front.screen    -- art pixels from the screen's top-left corner (fixed)
--   Front.addBlocker("hud", gui, rectsFn, scaleFn)  -- what a HUD-level ScreenGui covers
--   Front.blockers()   -- { Rect } in world art pixels (screenBlockers(): screen art pixels)
--   Front.hideWhen("panel", fn)  -- the layer is hidden while any of these return true

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Screen = require(script.Parent.Screen)
local Camera2D = require(script.Parent.Camera2D)

local Front = {}

Front.DisplayOrder = 15

export type Rect = { x0: number, y0: number, x1: number, y1: number }
export type GuiRect = { x: number, y: number, w: number, h: number }

Front.gui = nil :: ScreenGui?
Front.world = nil :: Frame?
Front.screen = nil :: Frame?

type Blocker = {
	gui: () -> ScreenGui?,
	rects: () -> { GuiRect },
	scale: () -> number,
}

local blockerList: { [string]: Blocker } = {}
local hiders: { [string]: () -> boolean } = {}
local worldScale: UIScale? = nil
local screenScale: UIScale? = nil

local function insetOf(gui: ScreenGui?): Vector2
	if not gui or gui.IgnoreGuiInset then
		return Vector2.zero
	end
	local ok, inset = pcall(function()
		return GuiService:GetGuiInset()
	end)
	return if ok and typeof(inset) == "Vector2" then inset else Vector2.zero
end

-- Registers what a HUD-level ScreenGui covers: `rects` in that gui's own art pixels (scaled by
-- `scale` screen pixels per art pixel, from the gui's top-left, below the top bar unless the
-- gui ignores it). nil `gui` / `rects` removes the blocker.
function Front.addBlocker(
	key: string,
	gui: (() -> ScreenGui?)?,
	rects: (() -> { GuiRect })?,
	scale: (() -> number)?
)
	if not gui or not rects then
		blockerList[key] = nil
		return
	end
	blockerList[key] = {
		gui = gui,
		rects = rects,
		scale = scale or function()
			return Screen.scale
		end,
	}
end

-- Every blocker in screen art pixels (Screen.scale), rounded outward.
function Front.screenBlockers(): { Rect }
	local out: { Rect } = {}
	local s = math.max(1, Screen.scale)
	for _, blocker in blockerList do
		local ok, gui, rects, k = pcall(function()
			return blocker.gui(), blocker.rects(), blocker.scale()
		end)
		if ok and rects then
			local inset = insetOf(gui)
			local scale = math.max(1, k or s)
			for _, r in rects do
				if r.w > 0 and r.h > 0 then
					local sx0, sy0 = inset.X + r.x * scale, inset.Y + r.y * scale
					local sx1, sy1 = sx0 + r.w * scale, sy0 + r.h * scale
					table.insert(out, {
						x0 = math.floor(sx0 / s),
						y0 = math.floor(sy0 / s),
						x1 = math.ceil(sx1 / s),
						y1 = math.ceil(sy1 / s),
					})
				end
			end
		end
	end
	return out
end

-- Every blocker in world art pixels (where the world is drawn under it right now).
function Front.blockers(): { Rect }
	local out = Front.screenBlockers()
	local left, top = Camera2D.left, Camera2D.top
	for _, r in out do
		r.x0 += left
		r.x1 += left
		r.y0 += top
		r.y1 += top
	end
	return out
end

-- Area of the overlap between rectangle (x0, y0, x1, y1) and the blockers.
function Front.overlap(blockers: { Rect }, x0: number, y0: number, x1: number, y1: number): number
	local total = 0
	for _, r in blockers do
		local w = math.min(x1, r.x1) - math.max(x0, r.x0)
		local h = math.min(y1, r.y1) - math.max(y0, r.y0)
		if w > 0 and h > 0 then
			total += w * h
		end
	end
	return total
end

-- The layer is hidden while `fn` returns true (e.g. while a HUD panel is open over everything).
function Front.hideWhen(key: string, fn: (() -> boolean)?)
	hiders[key] = fn
end

local function layer(parent: Instance, name: string): (Frame, UIScale)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Parent = parent
	local scale = Instance.new("UIScale")
	scale.Scale = math.max(1, Screen.scale)
	scale.Parent = f
	return f, scale
end

-- Keeps the front world exactly over the real one (same scroll, same scale).
local function sync()
	local world = Front.world
	local source = Screen.world
	if not world or not source then
		return
	end
	if world.Position ~= source.Position then
		world.Position = source.Position
	end
	local s = math.max(1, Screen.scale)
	if worldScale and worldScale.Scale ~= s then
		worldScale.Scale = s
	end
	if screenScale and screenScale.Scale ~= s then
		screenScale.Scale = s
	end
	local screen = Front.screen
	if screen then
		local w, h = Screen.viewArtSize()
		local size = UDim2.fromOffset(w, h)
		if screen.Size ~= size then
			screen.Size = size
		end
	end
end

local function hidden(): boolean
	for _, fn in hiders do
		local ok, hide = pcall(fn)
		if ok and hide then
			return true
		end
	end
	return false
end

function Front.start()
	if Front.gui then
		return
	end
	Screen.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "JJKFront"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = Front.DisplayOrder
	local world, ws = layer(gui, "World")
	local source = Screen.world
	if source then
		world.Size = source.Size
	end
	local screen, ss = layer(gui, "Screen")
	Front.gui, Front.world, Front.screen = gui, world, screen
	worldScale, screenScale = ws, ss
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	sync()
	if source then
		source:GetPropertyChangedSignal("Position"):Connect(sync)
	end
	local screenChanged: any = Screen.Changed
	screenChanged:Connect(sync)
	RunService.RenderStepped:Connect(function()
		sync()
		local show = not hidden()
		if gui.Enabled ~= show then
			gui.Enabled = show
		end
	end)
end

return Front
