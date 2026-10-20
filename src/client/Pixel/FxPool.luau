--!strict
-- Pools of prebuilt pixel pieces for effects, so animating never creates or destroys Frames
-- once a piece has been built: animated sprites (Sprite.frames containers), Canvas drawings
-- (rings of each radius, light pillars of each width), single-colour motes and text labels.
-- Everything is placed in art pixels in the world's Overlay layer by its anchor.
--
--   local f = FxPool.sprite(Fx.coin, "coin")   -- container, parented and visible
--   FxPool.place(f, x, y); Sprite.show(f, 2)
--   FxPool.release(f)                         -- back to the pool (unparented)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Canvas = require(Shared.Pixel.Canvas)
local Sprite = require(Shared.Pixel.Sprite)
local Screen = require(script.Parent.Screen)
local Text = require(script.Parent.Text)
local Widgets = require(script.Parent.Widgets)

local FxPool = {}

FxPool.MaxPerKey = 48

local pools: { [string]: { Frame } } = {}
local keys: { [Frame]: string } = setmetatable({}, { __mode = "k" }) :: any
local anchors: { [Frame]: { number } } = setmetatable({}, { __mode = "k" }) :: any
FxPool.built = 0 -- pieces built so far (for budgets and tests)
FxPool.live = 0 -- pieces in use

local function take(key: string): Frame?
	local list = pools[key]
	local f = list and table.remove(list)
	if f then
		FxPool.live += 1
	end
	return f
end

local function adopt(f: Frame, key: string, ax: number, ay: number)
	keys[f] = key
	anchors[f] = { ax, ay }
	FxPool.built += 1
	FxPool.live += 1
end

local function show(f: Frame, parent: Instance?, z: number?)
	f.Visible = true
	if z then
		f.ZIndex = z
	end
	f.Parent = parent or Screen.layers.Overlay
end

-- An animated sprite (every frame prebuilt; switch with Sprite.show). `key` must identify the
-- def, flip and palette.
function FxPool.sprite(
	def: Sprite.Def,
	key: string,
	flip: boolean?,
	palette: Sprite.Palette?,
	z: number?,
	parent: Instance?
): Frame
	local k = "spr:" .. key .. (if flip then ":f" else "")
	local f = take(k)
	if not f then
		local built = Sprite.frames(def, { scale = 1, flip = flip, palette = palette, name = "Fx" })
		local ax = if flip then def.w - def.anchor[1] else def.anchor[1]
		adopt(built, k, ax, def.anchor[2])
		f = built
	end
	local frame = f :: Frame
	Sprite.show(frame, 1)
	show(frame, parent, z)
	return frame
end

-- A Canvas drawing, built once per key. `draw` draws around (0, 0), which becomes the anchor.
function FxPool.canvas(key: string, draw: (Canvas.Canvas) -> (), z: number?, parent: Instance?): Frame
	local k = "cv:" .. key
	local f = take(k)
	if not f then
		local canvas = Canvas.new()
		draw(canvas)
		local bx0, by0, bx1, by1 = canvas:bounds()
		local x0, y0 = bx0 or 0, by0 or 0
		local w, h = (bx1 or 0) - x0, (by1 or 0) - y0
		local holder = Instance.new("Frame")
		holder.Name = "Fx"
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.Size = UDim2.fromOffset(w, h)
		canvas:build(holder, 1, x0, y0)
		adopt(holder, k, -x0, -y0)
		f = holder
	end
	local frame = f :: Frame
	show(frame, parent, z)
	return frame
end

-- A single solid rectangle (motes, flashes).
function FxPool.mote(color: Color3, w: number, h: number, z: number?, parent: Instance?): Frame
	local f = take("mote")
	if not f then
		local m = Instance.new("Frame")
		m.Name = "Mote"
		m.BorderSizePixel = 0
		adopt(m, "mote", 0, 0)
		f = m
	end
	local frame = f :: Frame
	frame.BackgroundColor3 = color
	frame.Size = UDim2.fromOffset(w, h)
	anchors[frame] = { math.floor(w / 2), math.floor(h / 2) }
	show(frame, parent, z)
	return frame
end

-- A line of pixel text (size 8 or 16), anchored at its centre.
function FxPool.text(text: string, color: Color3, size: number, z: number?, parent: Instance?): Frame
	local k = "txt:" .. size
	local f = take(k)
	if not f then
		local holder = Text.new(nil, "", { size = size, zindex = 1 })
		adopt(holder, k, 0, 0)
		f = holder
	end
	local frame = f :: Frame
	Widgets.setLabel(frame, text, color)
	for _, child in frame:GetChildren() do
		if child:IsA("TextLabel") and z then
			child.ZIndex = z
		end
	end
	anchors[frame] = { math.floor(Text.width(text, size) / 2), math.floor(size / 2) }
	show(frame, parent, z)
	return frame
end

-- Puts a pooled piece so its anchor lands on art pixel (x, y).
function FxPool.place(f: Frame, x: number, y: number)
	local a = anchors[f]
	local ax, ay = if a then a[1] else 0, if a then a[2] else 0
	f.Position = UDim2.fromOffset(math.floor(x + 0.5) - ax, math.floor(y + 0.5) - ay)
end

function FxPool.release(f: Frame?)
	if not f then
		return
	end
	local k = keys[f]
	f.Parent = nil
	if not k then
		f:Destroy()
		return
	end
	FxPool.live -= 1
	local list = pools[k]
	if not list then
		list = {}
		pools[k] = list
	end
	if #list < FxPool.MaxPerKey then
		table.insert(list, f)
	else
		keys[f] = nil
		f:Destroy()
	end
end

return FxPool
