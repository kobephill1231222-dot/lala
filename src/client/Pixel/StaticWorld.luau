--!strict
-- Draws everything that never changes (ground, fences, buildings, trees, the Sell Stand, shop
-- displays) once, from Shared/Config/WorldMap and the World art, into 128-pixel chunks. Only
-- chunks near the camera stay parented, so the screen holds a few hundred Frames however big
-- the world is. Low art goes in the Ground layer (under characters), high art (canopies,
-- roofs) in the High layer (over them). Props narrower than a character (World.PropKinds:
-- lanterns, pillars, the Upgrade Board) are drawn whole into the Actors layer instead and
-- y-sorted with the characters by their footprint's bottom edge, so whoever stands behind one
-- is hidden by all of it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldMap = require(Shared.Config.WorldMap)
local Canvas = require(Shared.Pixel.Canvas)
local World = require(Shared.Pixel.Art.World)
local Screen = require(script.Parent.Screen)

local StaticWorld = {}

StaticWorld.ChunkSize = 128
StaticWorld.Margin = 1 -- chunks kept around the view

type Chunk = { frame: Frame, layer: Frame, cx: number, cy: number, count: number }

local chunks: { [string]: Chunk } = {}
local active: { [string]: boolean } = {}
StaticWorld.frameCount = 0

-- Art-pixel rectangle of a world rectangle.
function StaticWorld.artRect(rect: WorldMap.Rect): (number, number, number, number)
	local x0, y0 = WorldMap.toPixels(rect.x0, rect.z0)
	local x1, y1 = WorldMap.toPixels(rect.x1, rect.z1)
	x0, y0, x1, y1 = math.floor(x0 + 0.5), math.floor(y0 + 0.5), math.floor(x1 + 0.5), math.floor(y1 + 0.5)
	return x0, y0, x1 - x0, y1 - y0
end

-- Splits a canvas's rectangles into chunk canvases (clipping at chunk edges).
local function split(canvas: Canvas.Canvas, into: { [string]: Canvas.Canvas })
	local size = StaticWorld.ChunkSize
	for _, r in canvas.rects do
		local cx0, cy0 = math.floor(r.x / size), math.floor(r.y / size)
		local cx1, cy1 = math.floor((r.x + r.w - 1) / size), math.floor((r.y + r.h - 1) / size)
		for cx = cx0, cx1 do
			for cy = cy0, cy1 do
				local x0 = math.max(r.x, cx * size)
				local y0 = math.max(r.y, cy * size)
				local x1 = math.min(r.x + r.w, (cx + 1) * size)
				local y1 = math.min(r.y + r.h, (cy + 1) * size)
				if x1 > x0 and y1 > y0 then
					local k = cx .. ":" .. cy
					local c = into[k]
					if not c then
						c = Canvas.new()
						into[k] = c
					end
					c:rect(x0, y0, x1 - x0, y1 - y0, r.color)
				end
			end
		end
	end
end

type Prop = { canvas: Canvas.Canvas, bottom: number }

-- Draws the whole static world into canvases: (low, high, props).
function StaticWorld.draw(): (Canvas.Canvas, Canvas.Canvas, { Prop })
	local map = WorldMap.get()
	local low, high = Canvas.new(), Canvas.new()
	local props: { Prop } = {}
	-- Ground: grass first, then the rest on top in map order.
	for _, g in map.ground do
		local x, y, w, h = StaticWorld.artRect(g.rect)
		World.ground(low, g.kind, x, y, w, h)
	end
	-- Objects, top to bottom so lower ones overlap the ones behind them.
	local objects = table.clone(map.objects)
	table.sort(objects, function(a, b)
		if a.rect.z1 == b.rect.z1 then
			return a.rect.x0 < b.rect.x0
		end
		return a.rect.z1 < b.rect.z1
	end)
	for _, object in objects do
		local x, y, w, h = StaticWorld.artRect(object.rect)
		local prop = World.prop(object, x, y, w, h)
		if prop then
			table.insert(props, { canvas = prop, bottom = y + h })
		else
			World.object(low, high, object, x, y, w, h)
		end
	end
	return low, high, props
end

local function buildChunks(canvas: Canvas.Canvas, layer: Frame, tag: string)
	local parts: { [string]: Canvas.Canvas } = {}
	split(canvas, parts)
	local size = StaticWorld.ChunkSize
	for k, c in parts do
		local cx, cy = string.match(k, "^(-?%d+):(-?%d+)$")
		local x, y = tonumber(cx) :: number, tonumber(cy) :: number
		local frame = Instance.new("Frame")
		frame.Name = tag .. k
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Position = UDim2.fromOffset(x * size, y * size)
		frame.Size = UDim2.fromOffset(size, size)
		local count = c:build(frame, 1, x * size, y * size)
		StaticWorld.frameCount += count
		chunks[tag .. k] = { frame = frame, layer = layer, cx = x, cy = y, count = count }
	end
end

-- Builds every chunk (unparented until the camera reaches it).
function StaticWorld.build()
	for _, chunk in chunks do
		chunk.frame:Destroy()
	end
	table.clear(chunks)
	table.clear(active)
	StaticWorld.frameCount = 0
	local low, high, props = StaticWorld.draw()
	buildChunks(low, Screen.layers.Ground, "G")
	buildChunks(high, Screen.layers.High, "H")
	-- Props: one Frame each in the Actors layer, sorted like an actor whose feet are on the
	-- footprint's bottom row (Actor uses ZIndex = y * 4 + zBias), culled with the chunks.
	local size = StaticWorld.ChunkSize
	for i, prop in props do
		local x0, y0, x1, y1 = prop.canvas:bounds()
		if not (x0 and y0 and x1 and y1) then
			continue
		end
		local frame = Instance.new("Frame")
		frame.Name = "Prop" .. i
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Position = UDim2.fromOffset(x0, y0)
		frame.Size = UDim2.fromOffset(x1 - x0, y1 - y0)
		frame.ZIndex = prop.bottom * 4
		local count = prop.canvas:build(frame, 1, x0, y0)
		StaticWorld.frameCount += count
		local cx, cy = math.floor((x0 + x1) / 2 / size), math.floor(prop.bottom / size)
		chunks["P" .. i] = { frame = frame, layer = Screen.layers.Actors, cx = cx, cy = cy, count = count }
	end
end

-- Parents the chunks within the view (plus a margin) and unparents the rest.
function StaticWorld.cull(x0: number, y0: number, x1: number, y1: number)
	local size = StaticWorld.ChunkSize
	local m = StaticWorld.Margin
	local cx0, cy0 = math.floor(x0 / size) - m, math.floor(y0 / size) - m
	local cx1, cy1 = math.floor(x1 / size) + m, math.floor(y1 / size) + m
	for key, chunk in chunks do
		local inside = chunk.cx >= cx0 and chunk.cx <= cx1 and chunk.cy >= cy0 and chunk.cy <= cy1
		if inside and not active[key] then
			chunk.frame.Parent = chunk.layer
			active[key] = true
		elseif not inside and active[key] then
			chunk.frame.Parent = nil
			active[key] = nil
		end
	end
end

-- How many Frames are on screen right now (for budgets and tests).
function StaticWorld.activeFrames(): number
	local n = 0
	for key in active do
		n += chunks[key].count
	end
	return n
end

return StaticWorld
