--!strict
-- A list of solid rectangles in art pixels: what procedural pixel art (ground, fences,
-- buildings, effects) draws into. Canvas.build turns it into UI Frames at a whole-number
-- scale. Kept separate from Frames so art code is plain data and can be tested offline.

local Canvas = {}
Canvas.__index = Canvas

export type Rect = { x: number, y: number, w: number, h: number, color: Color3 }
export type Canvas = typeof(setmetatable({} :: { rects: { Rect }, ox: number, oy: number }, Canvas))

function Canvas.new(): Canvas
	return setmetatable({ rects = {}, ox = 0, oy = 0 }, Canvas)
end

-- Adds a filled rectangle (art pixels; fractional values are rounded to whole pixels).
function Canvas.rect(self: Canvas, x: number, y: number, w: number, h: number, color: Color3)
	local x0 = math.floor(x + self.ox + 0.5)
	local y0 = math.floor(y + self.oy + 0.5)
	local x1 = math.floor(x + w + self.ox + 0.5)
	local y1 = math.floor(y + h + self.oy + 0.5)
	if x1 > x0 and y1 > y0 then
		table.insert(self.rects, { x = x0, y = y0, w = x1 - x0, h = y1 - y0, color = color })
	end
end

-- Single pixel.
function Canvas.px(self: Canvas, x: number, y: number, color: Color3)
	self:rect(x, y, 1, 1, color)
end

-- Draws a sprite frame (Sprite.Def rows) at (x, y) top-left, optionally mirrored.
function Canvas.sprite(
	self: Canvas,
	def: any,
	x: number,
	y: number,
	frame: number?,
	flip: boolean?,
	palette: { [string]: Color3 }?
)
	for _, r in def.rects[frame or 1] do
		local rx = if flip then def.w - r.x - r.w else r.x
		self:rect(x + rx, y + r.y, r.w, r.h, (palette and palette[r.key]) or def.palette[r.key])
	end
end

-- Runs `fn` with the origin moved by (dx, dy).
function Canvas.offset(self: Canvas, dx: number, dy: number, fn: () -> ())
	self.ox += dx
	self.oy += dy
	fn()
	self.ox -= dx
	self.oy -= dy
end

function Canvas.count(self: Canvas): number
	return #self.rects
end

-- Bounding box of everything drawn: (x0, y0, x1, y1), or nil when empty.
function Canvas.bounds(self: Canvas): (number?, number?, number?, number?)
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, r in self.rects do
		x0, y0 = math.min(x0, r.x), math.min(y0, r.y)
		x1, y1 = math.max(x1, r.x + r.w), math.max(y1, r.y + r.h)
	end
	if x0 == math.huge then
		return nil, nil, nil, nil
	end
	return x0, y0, x1, y1
end

-- Creates one Frame per rectangle under `parent`, at `scale` screen pixels per art pixel,
-- offset so art pixel (originX, originY) lands at the parent's top-left. Later rectangles draw
-- on top of earlier ones (sibling order with one ZIndex).
function Canvas.build(
	self: Canvas,
	parent: Instance,
	scale: number,
	originX: number?,
	originY: number?,
	zindex: number?
): number
	local ox, oy = originX or 0, originY or 0
	for _, r in self.rects do
		local f = Instance.new("Frame")
		f.Name = "Px"
		f.BorderSizePixel = 0
		f.BackgroundColor3 = r.color
		f.Position = UDim2.fromOffset((r.x - ox) * scale, (r.y - oy) * scale)
		f.Size = UDim2.fromOffset(r.w * scale, r.h * scale)
		f.ZIndex = zindex or 1
		f.Parent = parent
	end
	return #self.rects
end

return Canvas
