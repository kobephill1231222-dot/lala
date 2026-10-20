--!strict
-- Procedural pixel art for the static world and the farm fittings, drawn into Canvases at
-- art-pixel rectangles (footprints from Config/WorldMap, 4 art px per stud). Top-down 3/4 view:
-- tall things stand on their footprint and rise up the screen. Parts above head height
-- (roofs, canopies, lantern and pillar tops) go in `high`, drawn over characters; the rest in
-- `low`. Nothing in `high` comes lower than 20 px above the footprint's bottom edge, so a
-- character (20 px tall) standing just in front of an object is never drawn under it. Ground
-- detail is placed on a grid of absolute art pixels with a coordinate hash (no randomness),
-- and skipped where other ground or a farm fitting will cover it.

local Palette = require(script.Parent.Parent.Palette)
local Canvas = require(script.Parent.Parent.Canvas)
local Icons = require(script.Parent.Icons)
local WorldMap = require(script.Parent.Parent.Parent.Config.WorldMap)
local Layout = require(script.Parent.Parent.Parent.Config.FarmLayout)
local Upgrades = require(script.Parent.Parent.Parent.Config.Upgrades)

type Canvas = Canvas.Canvas
type Box = { number } -- x0, y0, x1, y1 (art pixels, x1/y1 exclusive)

local World = {}

local P = Palette

World.SlatSpacing = 8 -- lane slats repeat every 8 px

-- How far above its footprint's bottom edge an object's `high` art must stay (a character's
-- height): a character standing in front of the object is never covered by it.
World.HeadRoom = 20

local function round(n: number): number
	return math.floor(n + 0.5)
end

-- HASH --------------------------------------------------------------------------------------

local function mul32(a: number, b: number): number
	local lo = bit32.band(a, 0xFFFF)
	local hi = bit32.rshift(a, 16)
	return (lo * b + ((hi * b) % 65536) * 65536) % 4294967296
end

-- Deterministic 0..1 from integer coordinates and a salt.
local function hash(x: number, y: number, salt: number): number
	local h = ((x % 65536) * 65536 + (y % 65536)) % 4294967296
	h = bit32.bxor(h, mul32(salt + 1, 0x9E3779B1))
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x7FEB352D)
	h = bit32.bxor(h, bit32.rshift(h, 15))
	h = mul32(h, 0x846CA68B)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / 4294967296
end

-- COVER -------------------------------------------------------------------------------------
-- Where ground detail would be hidden anyway (computed once from the map).

local function artBox(rect: WorldMap.Rect): Box
	local x0, y0 = WorldMap.toPixels(rect.x0, rect.z0)
	local x1, y1 = WorldMap.toPixels(rect.x1, rect.z1)
	return { round(x0), round(y0), round(x1), round(y1) }
end

local covers: { [string]: { Box } }? = nil

local function coverFor(kind: string): { Box }
	if not covers then
		local map = WorldMap.get()
		local grass, floor, plaza, roads = {}, {}, {}, {}
		for _, g in map.ground do
			if g.kind ~= "grass" then
				table.insert(grass, artBox(g.rect))
			end
			if g.kind == "road" then
				table.insert(roads, artBox(g.rect))
			end
		end
		local slot = Layout.SlotSize * Layout.PixelsPerStud / 2
		local pad = Layout.PadSize * Layout.PixelsPerStud / 2
		for _, farm in map.farms do
			table.insert(floor, artBox(farm.lane))
			table.insert(floor, artBox(farm.box))
			table.insert(floor, artBox(farm.collect))
			for _, p in farm.slots do
				local x, y = WorldMap.toPixels(p.X, p.Z)
				table.insert(floor, { round(x - slot), round(y - slot), round(x + slot), round(y + slot) })
			end
			for _, p in farm.pads do
				local x, y = WorldMap.toPixels(p.X, p.Z)
				table.insert(floor, { round(x - pad), round(y - pad), round(x + pad), round(y + pad) })
			end
		end
		for _, o in map.objects do
			if o.kind ~= "tree" and o.kind ~= "fence" and o.kind ~= "lantern" then
				table.insert(plaza, artBox(o.rect))
			end
		end
		covers = { grass = grass, farmFloor = floor, plaza = plaza, roads = roads }
	end
	return (covers :: any)[kind] or {}
end

-- Is the detail rectangle inside the ground rectangle and not under anything?
local function free(
	list: { Box },
	gx: number,
	gy: number,
	gw: number,
	gh: number,
	x: number,
	y: number,
	w: number,
	h: number
): boolean
	if x < gx or y < gy or x + w > gx + gw or y + h > gy + gh then
		return false
	end
	for _, b in list do
		if x >= b[1] and y >= b[2] and x + w <= b[3] and y + h <= b[4] then
			return false
		end
	end
	return true
end

-- SHAPES ------------------------------------------------------------------------------------

-- Filled rectangle with 1px corners cut (2 rects).
local function rounded(c: Canvas, x: number, y: number, w: number, h: number, color: Color3)
	c:rect(x + 1, y, w - 2, h, color)
	c:rect(x, y + 1, w, h - 2, color)
end

-- Stepped ellipse-ish blob centred on (cx, cy) with radii rx, ry (3 rects).
local function blob(c: Canvas, cx: number, cy: number, rx: number, ry: number, color: Color3)
	c:rect(cx - rx, cy - round(ry * 0.55), rx * 2, round(ry * 1.1), color)
	c:rect(cx - round(rx * 0.8), cy - round(ry * 0.85), round(rx * 1.6), round(ry * 1.7), color)
	c:rect(cx - round(rx * 0.5), cy - ry, round(rx), ry * 2, color)
end

-- GROUND ------------------------------------------------------------------------------------

-- Grass: tufts as in the mock (a Leaf blade with a Pine shadow), the odd leaf speck, dark
-- clump or flower, one per 12 px cell on most cells.
local GRASS_CELL = 12

local function grass(c: Canvas, x: number, y: number, w: number, h: number)
	c:rect(x, y, w, h, P.Grass)
	local cover = coverFor("grass")
	local cell = GRASS_CELL
	for cy = math.floor(y / cell), math.floor((y + h - 1) / cell) do
		for cx = math.floor(x / cell), math.floor((x + w - 1) / cell) do
			if hash(cx, cy, 1) < 0.58 then
				local tx = cx * cell + 1 + math.floor(hash(cx, cy, 2) * (cell - 4))
				local ty = cy * cell + 1 + math.floor(hash(cx, cy, 3) * (cell - 3))
				local kind = hash(cx, cy, 4)
				if free(cover, x, y, w, h, tx, ty, 3, 2) then
					if kind < 0.62 then -- tuft: .l. / .ld
						c:rect(tx + 1, ty, 1, 2, P.Leaf)
						c:rect(tx + 2, ty + 1, 1, 1, P.Pine)
					elseif kind < 0.8 then -- leaf speck
						c:rect(tx + 1, ty + 1, 1, 1, P.Leaf)
					elseif kind < 0.93 then -- dark clump
						c:rect(tx, ty + 1, 3, 1, P.Pine)
						c:rect(tx + 1, ty, 1, 1, P.Pine)
					else -- a flower
						c:rect(tx + 1, ty, 1, 1, if kind < 0.965 then P.Yellow else P.White)
						c:rect(tx + 1, ty + 1, 1, 1, P.Pine)
					end
				end
			end
		end
	end
end

-- Farm floor: Tan dirt with Sand and Cream specks (one per 9 px cell on most cells) and the
-- odd pebble, as in the mock.
local function farmFloor(c: Canvas, x: number, y: number, w: number, h: number)
	c:rect(x, y, w, h, P.Tan)
	local cover = coverFor("farmFloor")
	local cell = 9
	for cy = math.floor(y / cell), math.floor((y + h - 1) / cell) do
		for cx = math.floor(x / cell), math.floor((x + w - 1) / cell) do
			local roll = hash(cx, cy, 11)
			if roll < 0.78 then
				local sx = cx * cell + math.floor(hash(cx, cy, 12) * (cell - 2))
				local sy = cy * cell + math.floor(hash(cx, cy, 13) * (cell - 2))
				if roll < 0.04 then -- pebble
					if free(cover, x, y, w, h, sx, sy, 2, 2) then
						c:rect(sx, sy, 2, 1, P.Cream)
						c:rect(sx, sy + 1, 2, 1, P.Sand)
					end
				elseif free(cover, x, y, w, h, sx, sy, 1, 1) then
					c:rect(sx, sy, 1, 1, if roll < 0.52 then P.Sand else P.Cream)
				end
			end
		end
	end
end

-- A horizontal line from x0 to x1 (exclusive) with the gaps cut out.
local function hline(c: Canvas, x0: number, x1: number, y: number, gaps: { { number } }, color: Color3)
	local cursor = x0
	table.sort(gaps, function(a, b)
		return a[1] < b[1]
	end)
	for _, g in gaps do
		if g[1] > cursor then
			c:rect(cursor, y, math.min(g[1], x1) - cursor, 1, color)
		end
		cursor = math.max(cursor, g[2])
	end
	if x1 > cursor then
		c:rect(cursor, y, x1 - cursor, 1, color)
	end
end

-- Light stone slabs (32 x 16, running bond) with a curb, open where a road comes in.
local function plaza(c: Canvas, x: number, y: number, w: number, h: number)
	c:rect(x, y, w, h, P.Mist)
	local cover = coverFor("plaza")
	local sw, sh = 32, 16
	for row = math.floor(y / sh), math.floor((y + h - 1) / sh) do
		local ry = row * sh
		if ry > y then
			c:rect(x, ry, w, 1, P.Slate)
		end
		local shift = if row % 2 == 0 then 0 else sw / 2
		local y0, y1 = math.max(y, ry + 1), math.min(y + h, ry + sh)
		for col = math.floor((x - shift) / sw), math.floor((x + w - 1 - shift) / sw) do
			local jx = col * sw + shift
			if jx > x and jx < x + w and y1 > y0 then
				c:rect(jx, y0, 1, y1 - y0, P.Slate)
			end
			-- a few worn or bright slabs
			local roll = hash(col, row, 21)
			if roll < 0.12 then
				local sx = jx + 4 + math.floor(hash(col, row, 22) * (sw - 10))
				local sy = ry + 3 + math.floor(hash(col, row, 23) * (sh - 7))
				if free(cover, x, y, w, h, sx, sy, 2, 2) then
					c:rect(sx, sy, 1, 1, P.Slate)
					c:rect(sx + 1, sy + 1, 1, 1, P.Slate)
				end
			end
		end
	end
	-- curb, open at the road mouths
	local top, bottom = {}, {}
	for _, r in coverFor("roads") do
		if math.abs(r[4] - y) <= 1 then
			table.insert(top, { r[1], r[3] })
		end
		if math.abs(r[2] - (y + h)) <= 1 then
			table.insert(bottom, { r[1], r[3] })
		end
	end
	hline(c, x, x + w, y, top, P.Steel)
	hline(c, x, x + w, y + h - 1, bottom, P.Steel)
	c:rect(x, y, 1, h, P.Steel)
	c:rect(x + w - 1, y, 1, h, P.Steel)
end

-- Small paving bricks (8 x 4, running bond), as in the mock path.
local function road(c: Canvas, x: number, y: number, w: number, h: number)
	c:rect(x, y, w, h, P.Mist)
	for row = math.floor(y / 4), math.floor((y + h - 1) / 4) do
		local ly = row * 4 + 3
		if ly < y + h then
			c:rect(x, ly, w, 1, P.Slate)
		end
		local y0, y1 = math.max(y, row * 4), math.min(y + h, row * 4 + 3)
		local offset = if row % 2 == 0 then 7 else 3
		for col = math.floor((x - offset) / 8), math.floor((x + w - 1 - offset) / 8) do
			local jx = col * 8 + offset
			if jx >= x and jx < x + w and y1 > y0 then
				c:rect(jx, y0, 1, y1 - y0, P.Slate)
			end
		end
	end
	c:rect(x, y, 1, h, P.Steel)
	c:rect(x + w - 1, y, 1, h, P.Steel)
end

local GROUND: { [string]: (Canvas, number, number, number, number) -> () } = {
	grass = grass,
	plaza = plaza,
	road = road,
	farmFloor = farmFloor,
}

function World.ground(canvas: Canvas, kind: string, x: number, y: number, w: number, h: number)
	x, y, w, h = round(x), round(y), round(w), round(h)
	if w <= 0 or h <= 0 then
		return
	end
	local draw = GROUND[kind] or grass
	draw(canvas, x, y, w, h)
end

-- OBJECTS -----------------------------------------------------------------------------------

type Draw = (low: Canvas, high: Canvas, variant: string?, x: number, y: number, w: number, h: number) -> ()

-- Positions every `step` px on absolute coordinates between a and b - size, plus both ends.
local function posts(a: number, b: number, size: number, step: number): { number }
	local out = { a }
	local last = b - size
	local p = (math.floor(a / step) + 1) * step
	while p <= last - size - 2 do
		if p >= a + size + 2 then
			table.insert(out, p)
		end
		p += step
	end
	if last > a then
		table.insert(out, last)
	end
	return out
end

-- A standing fence post, 4 x 12, on `bottom`.
local function post(c: Canvas, px: number, bottom: number)
	c:rect(px, bottom - 12, 4, 12, P.DarkBrown)
	c:rect(px + 1, bottom - 11, 2, 10, P.Bark)
	c:rect(px + 1, bottom - 11, 2, 1, P.Clay)
end

-- Wooden fence: rails with posts every 8 px. Horizontal runs stand 12 px tall on the
-- footprint's bottom edge; vertical runs are a column of rail tops between two standing end
-- posts, which land exactly on the end posts of the horizontal runs at the corners.
local function fence(low: Canvas, _high: Canvas, variant: string?, x: number, y: number, w: number, h: number)
	local vertical = if variant then variant == "v" else h > w
	if vertical then
		local cx = x + math.floor(w / 2) - 3 -- 6 px column centred on the footprint
		local px = x + math.floor((w - 4) / 2)
		local top, bottom = y + 4, y + h - 12 -- between the end posts
		if bottom > top then
			low:rect(cx, top, 6, bottom - top, P.DarkBrown)
			low:rect(cx + 1, top, 4, bottom - top, P.Bark)
			low:rect(cx + 1, top, 1, bottom - top, P.Clay)
			local py = (math.floor((top + 4) / 8) + 1) * 8
			while py <= bottom - 6 do
				low:rect(cx - 1, py, 8, 3, P.DarkBrown)
				low:rect(cx, py + 1, 6, 1, P.Clay)
				py += 8
			end
		end
		post(low, px, y + 4)
		post(low, px, y + h)
	else
		local bottom = y + h
		local top = bottom - 12
		for _, px in posts(x, x + w, 4, 8) do
			post(low, px, bottom)
		end
		low:rect(x, top + 2, w, 7, P.DarkBrown)
		low:rect(x, top + 3, w, 1, P.Clay)
		low:rect(x, top + 4, w, 1, P.Bark)
		low:rect(x, top + 6, w, 1, P.Clay)
		low:rect(x, top + 7, w, 1, P.Bark)
	end
end

-- The Orb Box: a wooden crate-box with a gold rim, seen from above with its front face at
-- the bottom. The renderer fills World.orbBoxInterior with the orbs.
local function orbBox(
	low: Canvas,
	_high: Canvas,
	_variant: string?,
	x: number,
	y: number,
	w: number,
	h: number
)
	local front = math.max(4, math.floor(h / 4)) -- front face height
	local open = h - front -- rows of the top view
	low:rect(x, y, w, h, P.Ink)
	low:rect(x + 1, y + 1, w - 2, open - 1, P.Amber) -- rim
	low:rect(x + 2, y + 2, w - 4, open - 3, P.Bark) -- wall tops
	low:rect(x + 2, y + 2, w - 4, 1, P.Clay)
	local ix, iy, iw, ih = World.orbBoxInterior(x, y, w, h)
	low:rect(ix - 1, iy - 1, iw + 2, ih + 2, P.DarkBrown) -- inner edge
	low:rect(ix, iy, iw, ih, P.Night) -- floor
	low:rect(ix, iy, iw, math.min(3, ih), P.Brown) -- back wall, inside
	low:rect(ix, iy + math.min(3, ih), iw, 1, P.DarkBrown)
	-- front face: planks between gold corner posts
	local fy = y + open
	low:rect(x + 1, fy - 1, w - 2, 1, P.Yellow) -- front rim edge
	low:rect(x + 1, fy, w - 2, front - 1, P.Bark)
	low:rect(x + 1, fy, w - 2, 1, P.Clay)
	low:rect(x + 1, fy + math.floor(front / 2), w - 2, 1, P.Brown)
	low:rect(x + 1, fy, 2, front - 1, P.Amber)
	low:rect(x + w - 3, fy, 2, front - 1, P.Amber)
	-- name plate
	local pw = math.min(10, w - 10)
	if pw > 2 and front >= 5 then
		local px = x + math.floor((w - pw) / 2)
		low:rect(px, fy + 1, pw, front - 3, P.Ink)
		low:rect(px + 1, fy + 2, pw - 2, front - 5, P.Plum)
		low:rect(px + math.floor(pw / 2) - 1, fy + 2, 2, math.max(1, front - 5), P.Orchid)
	end
end

function World.orbBoxInterior(x: number, y: number, w: number, h: number): (number, number, number, number)
	x, y, w, h = round(x), round(y), round(w), round(h)
	local front = math.max(4, math.floor(h / 4))
	return x + 4, y + 4, w - 8, h - front - 7
end

-- Stone toro lantern with a lit window; the roof is high (and stays HeadRoom clear).
local function lantern(
	low: Canvas,
	high: Canvas,
	_variant: string?,
	x: number,
	y: number,
	w: number,
	h: number
)
	local b = y + h
	local cx = x + math.floor(w / 2)
	local roof = b - World.HeadRoom -- bottom of the roof
	-- base and post
	low:rect(cx - 4, b - 3, 8, 3, P.Ink)
	low:rect(cx - 3, b - 3, 6, 2, P.Steel)
	low:rect(cx - 2, b - 10, 4, 7, P.Ink)
	low:rect(cx - 1, b - 10, 2, 7, P.Slate)
	-- platform and firebox
	low:rect(cx - 4, b - 12, 8, 3, P.Ink)
	low:rect(cx - 3, b - 12, 6, 1, P.Mist)
	low:rect(cx - 3, b - 11, 6, 1, P.Slate)
	low:rect(cx - 3, roof, 6, b - 12 - roof, P.Ink)
	low:rect(cx - 2, roof, 4, b - 12 - roof, P.Slate)
	low:rect(cx - 1, roof + 2, 2, 4, P.Yellow)
	low:rect(cx - 1, roof + 5, 2, 1, P.Amber)
	-- roof and jewel
	high:rect(cx - 5, roof - 3, 10, 3, P.Ink)
	high:rect(cx - 4, roof - 3, 8, 2, P.Steel)
	high:rect(cx - 3, roof - 3, 6, 1, P.Mist)
	high:rect(cx - 1, roof - 5, 2, 2, P.Ink)
	high:rect(cx - 1, roof - 5, 1, 1, P.Slate)
end

-- Lacquer pillar on a black base with a gold cap; the shaft above HeadRoom is high.
local PILLAR_H = 29

local function pillar(
	low: Canvas,
	high: Canvas,
	_variant: string?,
	x: number,
	y: number,
	w: number,
	h: number
)
	local b = y + h
	local cx = x + math.floor(w / 2)
	local split = b - World.HeadRoom
	low:rect(cx - 3, b - 4, 6, 4, P.Ink)
	low:rect(cx - 2, b - 3, 4, 2, P.Night)
	local function shaft(c: Canvas, y0: number, y1: number)
		c:rect(cx - 3, y0, 6, y1 - y0, P.Ink)
		c:rect(cx - 2, y0, 4, y1 - y0, P.Red)
		c:rect(cx - 2, y0, 1, y1 - y0, P.Rose)
		c:rect(cx + 1, y0, 1, y1 - y0, P.Crimson)
	end
	shaft(low, split, b - 4)
	shaft(high, b - PILLAR_H + 3, split)
	high:rect(cx - 4, b - PILLAR_H, 8, 3, P.Ink)
	high:rect(cx - 3, b - PILLAR_H + 1, 6, 1, P.Yellow)
	high:rect(cx - 3, b - PILLAR_H + 2, 6, 1, P.Amber)
end

-- A small stack of gold coins (each 5 x 3: Yellow top, Amber edge, Brown outline), the top
-- coin nudged sideways; `bottom` is the stack's bottom edge.
local function coins(c: Canvas, x: number, bottom: number, n: number)
	for i = 0, n - 1 do
		local cx = x + (if i % 2 == 1 then 1 else 0)
		local cy = bottom - 4 - i * 2
		c:rect(cx + 1, cy, 3, 4, P.Brown)
		c:rect(cx, cy + 1, 5, 2, P.Brown)
		c:rect(cx + 1, cy + 1, 3, 1, P.Yellow)
		c:rect(cx + 1, cy + 2, 3, 1, P.Amber)
	end
end

-- Sell Stand: a two-tier stone dais with the gold Sell Pad (coin emblem) on the upper tier,
-- coin stacks either side of the front step, and a beam with a coin plaque across the two
-- back pillars.
-- The corner pillars are separate objects in the outer ring of the footprint, which the dais
-- leaves clear (draw order never matters).
local function sellStand(
	low: Canvas,
	high: Canvas,
	_variant: string?,
	x: number,
	y: number,
	w: number,
	h: number
)
	local cx, cy = x + math.floor(w / 2), y + math.floor(h / 2)
	local ring = math.max(2, round(w / 8))
	local dx, dy, dw, dh = x + ring, y + ring, w - ring * 2, h - ring * 2
	local face = 3
	-- lower tier: Slate slab with a Steel front face
	low:rect(dx, dy, dw, dh, P.Ink)
	low:rect(dx + 1, dy + 1, dw - 2, dh - 2, P.Steel)
	low:rect(dx + 1, dy + 1, dw - 2, dh - 2 - face, P.Slate)
	low:rect(dx + 1, dy + 1, dw - 2, 1, P.Mist)
	-- upper tier: Mist slab, inset, with its own face
	local s = math.min(Layout.PixelsPerStud * 6, dw - 8, dh - 8 - face)
	local ux, uy, uw, uh = dx + 3, dy + 2, dw - 6, dh - 2 - face - 1
	low:rect(ux, uy, uw, uh, P.Ink)
	low:rect(ux + 1, uy + 1, uw - 2, uh - 2, P.Slate)
	low:rect(ux + 1, uy + 1, uw - 2, uh - 2 - 2, P.Mist)
	low:rect(ux + 1, uy + 1, uw - 2, 1, P.White)
	-- front step
	low:rect(cx - 9, dy + dh - 1, 18, 4, P.Ink)
	low:rect(cx - 8, dy + dh - 1, 16, 2, P.Mist)
	low:rect(cx - 8, dy + dh + 1, 16, 1, P.Slate)
	-- the Sell Pad (6 x 6 studs), gold with a coin
	local px, py = cx - math.floor(s / 2), cy - math.floor(s / 2)
	low:rect(px, py, s, s, P.Brown)
	low:rect(px + 1, py + 1, s - 2, s - 2, P.Orange)
	low:rect(px + 2, py + 2, s - 4, s - 4, P.Amber)
	low:rect(px + 2, py + 2, s - 4, 1, P.Yellow)
	low:rect(px + 2, py + 2, 1, s - 4, P.Yellow)
	local coin = Icons.get("cash")
	low:sprite(coin, cx - math.floor(coin.w / 2), cy - math.floor(coin.h / 2))
	-- coin stacks either side of the front step
	coins(low, cx - 17, dy + dh + 3, 3)
	coins(low, cx + 11, dy + dh + 2, 2)
	-- beam on the back pillars, with a coin plaque standing on it (kept HeadRoom clear of the
	-- back pillars' footprint)
	local by = y + ring - PILLAR_H - 3
	high:rect(x, by, w, 4, P.Ink)
	high:rect(x + 1, by + 1, w - 2, 2, P.Crimson)
	high:rect(x + 1, by + 1, w - 2, 1, P.Red)
	local sw, sh = 16, 14
	local sy = by - 7
	high:rect(cx - sw / 2, sy, sw, sh, P.Ink)
	high:rect(cx - sw / 2 + 1, sy + 1, sw - 2, sh - 2, P.Amber)
	high:rect(cx - sw / 2 + 2, sy + 2, sw - 4, sh - 4, P.Night)
	high:sprite(coin, cx - math.floor(coin.w / 2), sy + 2)
end

-- A Japanese shop: tiled roof (high), plaster front wall with an open counter (low), a sign
-- board on the eave with the shop's icon. The Crate Shop has a slate roof and a navy noren,
-- the Upgrade Shop a green copper roof and a pine noren.
local SHOPS = {
	crateShop = {
		timber = P.Crimson,
		noren = P.Navy,
		icon = "crateShop",
		goods = { P.Sky, P.Orchid, P.Amber },
		-- roof: tiles, ribs, courses, fascia, ridge, ridge highlight
		roof = { P.Dusk, P.Steel, P.Night, P.Slate, P.Night, P.Steel },
	},
	upgradeShop = {
		timber = P.Brown,
		noren = P.Pine,
		icon = "upgradeShop",
		goods = { P.Cream, P.Leaf, P.Cream },
		roof = { P.Pine, P.Grass, P.DeepTeal, P.Grass, P.DeepTeal, P.Grass },
	},
}

local function shop(kind: string): Draw
	local style = SHOPS[kind]
	local roof = style.roof
	return function(low: Canvas, high: Canvas, _variant: string?, x: number, y: number, w: number, h: number)
		local b = y + h
		local cx = x + math.floor(w / 2)
		local eave = b - World.HeadRoom - 2 -- bottom of the roof
		-- Wall
		low:rect(x, eave - 2, w, b - eave + 2, P.Ink)
		low:rect(x + 1, eave - 2, w - 2, b - eave, P.Cream)
		low:rect(x + 1, b - 4, w - 2, 3, P.Slate) -- stone plinth
		low:rect(x + 1, b - 4, w - 2, 1, P.Mist)
		low:rect(x + 1, eave + 4, w - 2, 2, style.timber) -- tie beam
		for _, tx in { x + 1, x + w - 3, x + math.floor(w / 4) - 1, x + w - math.floor(w / 4) - 1 } do
			low:rect(tx, eave - 2, 2, b - eave - 2, style.timber)
		end
		-- open front: a short noren curtain, goods on the counter peeking out under it
		local ow = math.floor(w / 2) - 4
		local ox = cx - math.floor(ow / 2)
		low:rect(ox, eave + 6, ow, b - eave - 10, P.Night)
		local flaps = 4
		local fw = math.floor((ow - (flaps - 1)) / flaps)
		for i = 0, flaps - 1 do
			low:rect(ox + i * (fw + 1), eave + 6, fw, 3, style.noren)
		end
		for i, color in style.goods do
			local gx = ox + 4 + (i - 1) * math.floor((ow - 12) / 2)
			low:rect(gx, b - 12, 4, 3, P.Ink)
			low:rect(gx + 1, b - 11, 2, 2, color)
		end
		low:rect(ox - 2, b - 9, ow + 4, 5, P.Ink) -- counter
		low:rect(ox - 1, b - 8, ow + 2, 3, P.Bark)
		low:rect(ox - 1, b - 8, ow + 2, 1, P.Tan)
		-- shoji windows either side
		for _, wx in { x + math.floor(w / 8), x + w - math.floor(w / 8) - 12 } do
			low:rect(wx, eave + 8, 12, 8, P.Ink)
			low:rect(wx + 1, eave + 9, 10, 6, P.White)
			low:rect(wx + 6, eave + 9, 1, 6, P.Tan)
			low:rect(wx + 1, eave + 11, 10, 1, P.Tan)
		end
		-- Roof: eaves overhang the wall, ribbed tiles, a ridge with end tiles
		local rx0, rx1 = x - 4, x + w + 4
		local top = y - 6
		high:rect(rx0, top, rx1 - rx0, eave - top + 1, P.Ink)
		high:rect(rx0 + 1, top + 1, rx1 - rx0 - 2, eave - top - 2, roof[1])
		for rib = math.floor((rx0 + 3) / 6) * 6 + 3, rx1 - 3, 6 do
			high:rect(rib, top + 2, 1, eave - top - 5, roof[2])
		end
		for _, ly in { top + 7, top + 13, top + 19 } do
			if ly < eave - 4 then
				high:rect(rx0 + 1, ly, rx1 - rx0 - 2, 1, roof[3])
			end
		end
		high:rect(rx0 + 1, eave - 3, rx1 - rx0 - 2, 1, roof[4]) -- fascia
		high:rect(rx0 + 1, eave - 2, rx1 - rx0 - 2, 2, roof[3])
		high:rect(x + 2, top - 5, w - 4, 6, P.Ink) -- ridge
		high:rect(x + 3, top - 4, w - 6, 4, roof[5])
		high:rect(x + 3, top - 4, w - 6, 1, roof[6])
		for _, ex in { x, x + w - 6 } do
			high:rect(ex, top - 7, 6, 8, P.Ink)
			high:rect(ex + 1, top - 6, 4, 6, roof[5])
			high:rect(ex + 1, top - 6, 4, 1, roof[4])
		end
		-- sign board hanging from the eave (its bottom level with the eave's)
		local icon = Icons.get(style.icon)
		local sw, sh = 28, 14
		local sx, sy = cx - math.floor(sw / 2), eave + 1 - sh
		high:rect(sx, sy, sw, sh, P.Ink)
		high:rect(sx + 1, sy + 1, sw - 2, sh - 2, P.Amber)
		high:rect(sx + 2, sy + 2, sw - 4, sh - 4, P.Night)
		high:sprite(icon, cx - math.floor(icon.w / 2), sy + math.floor((sh - icon.h) / 2))
	end
end

-- Crate Shop display: stone pedestal with a trim slab in the tier's colour (the crate on
-- top is drawn by the renderer).
local TIER_TRIM: { [string]: { Color3 } } = {
	starter = { P.Mist, P.Slate },
	basic = { P.Tan, P.Sand },
	rare = { P.Sky, P.Navy },
	epic = { P.Orchid, P.Plum },
	legendary = { P.Amber, P.Orange },
}

local function display(
	low: Canvas,
	_high: Canvas,
	variant: string?,
	x: number,
	y: number,
	w: number,
	h: number
)
	local trim = TIER_TRIM[variant or ""] or TIER_TRIM.starter
	local face = math.max(3, math.floor(h * 3 / 8))
	local topH = h - face
	low:rect(x, y, w, h, P.Ink)
	low:rect(x + 1, y + 1, w - 2, topH - 1, P.Mist)
	low:rect(x + 1, y + 1, w - 2, 1, P.White)
	low:rect(x + 2, y + topH - 3, w - 4, 1, P.Slate) -- where the crate stands
	low:rect(x + 1, y + topH, w - 2, 2, trim[1])
	low:rect(x + 1, y + topH + 1, w - 2, 1, trim[2])
	low:rect(x + 1, y + topH + 2, w - 2, face - 3, P.Slate)
	if variant == "epic" or variant == "legendary" then
		low:rect(x + 1, y + topH, 2, 2, P.Yellow)
		low:rect(x + w - 3, y + topH, 2, 2, P.Yellow)
	end
end

-- Upgrade board: a notice board on two lacquer posts with one note per farm upgrade (in
-- Config/Upgrades order, each marked in its icon's key colour); its tiled cap is high.
local NOTE_COLOR: { [string]: Color3 } = {
	orbValue = P.Orchid,
	slots = P.Slate,
	boxSize = P.Bark,
	openSpeed = P.Amber,
	pads = P.Red,
	luck = P.Leaf,
	walkSpeed = P.Sky,
}

local function upgradeBoard(
	low: Canvas,
	high: Canvas,
	_variant: string?,
	x: number,
	y: number,
	w: number,
	h: number
)
	local b = y + h
	local top = b - 24
	for _, px in { x + 2, x + w - 6 } do
		low:rect(px, top, 4, b - top, P.Ink)
		low:rect(px + 1, top, 2, b - top - 1, P.Red)
		low:rect(px + 1, top, 1, b - top - 1, P.Rose)
	end
	low:rect(x + 3, top + 2, w - 6, 14, P.Ink)
	low:rect(x + 4, top + 3, w - 8, 12, P.Bark)
	low:rect(x + 4, top + 3, w - 8, 1, P.Clay)
	local inner = w - 8
	local nw = 6
	local n = math.min(#Upgrades.List, math.floor((inner - 2) / (nw + 1)))
	local gap = if inner - n * nw - (n - 1) * 2 >= 2 then 2 else 1
	local nx = x + 4 + math.floor((inner - n * nw - (n - 1) * gap) / 2)
	for i = 1, n do
		local mark = NOTE_COLOR[Upgrades.List[i].id] or P.Steel
		low:rect(nx, top + 5, nw, 8, P.Cream)
		low:rect(nx, top + 12, nw, 1, P.Tan)
		low:rect(nx + 1, top + 7, nw - 2, 3, mark)
		low:rect(nx + math.floor(nw / 2) - 1, top + 5, 2, 1, P.Crimson) -- pin
		nx += nw + gap
	end
	high:rect(x, top - 3, w, 5, P.Ink)
	high:rect(x + 1, top - 2, w - 2, 3, P.Dusk)
	high:rect(x + 1, top - 2, w - 2, 1, P.Steel)
end

-- Backless wooden bench.
local function bench(
	low: Canvas,
	_high: Canvas,
	_variant: string?,
	x: number,
	y: number,
	w: number,
	h: number
)
	local seat = math.max(3, h - 2)
	low:rect(x + 2, y + seat - 1, 4, h - seat + 1, P.Ink)
	low:rect(x + w - 6, y + seat - 1, 4, h - seat + 1, P.Ink)
	low:rect(x + 3, y + seat - 1, 2, h - seat, P.DarkBrown)
	low:rect(x + w - 5, y + seat - 1, 2, h - seat, P.DarkBrown)
	low:rect(x, y, w, seat, P.Ink)
	low:rect(x + 1, y + 1, w - 2, seat - 2, P.Bark)
	low:rect(x + 1, y + 1, w - 2, 1, P.Tan)
	if seat >= 5 then
		low:rect(x + 1, y + 3, w - 2, 1, P.Brown)
	end
end

-- Trees: the trunk is low, the canopy (wider than the footprint) is high and stays
-- HeadRoom clear of the footprint's bottom edge.
local CANOPY: { [string]: { Color3 } } = {
	-- outline, shadow, base, light
	pine = { P.DeepTeal, P.Pine, P.Grass, P.Leaf },
	sakura = { P.Plum, P.Orchid, P.Rose, P.Peach },
	maple = { P.Crimson, P.Rust, P.Clay, P.Orange },
}

local function tree(low: Canvas, high: Canvas, variant: string?, x: number, y: number, w: number, h: number)
	local kind = if variant and CANOPY[variant] then variant else "pine"
	local col = CANOPY[kind]
	local b = y + h - 1 -- the footprint's last row
	local canopy = y + h - World.HeadRoom -- the canopy's bottom edge
	local cx = x + math.floor(w / 2)
	local flip = hash(x, y, 31) < 0.5
	local dx = if flip then -1 else 1
	-- trunk with a root flare, up into the canopy
	low:rect(cx - 4, b - 3, 8, 4, P.Ink)
	low:rect(cx - 3, b - 3, 6, 3, P.Brown)
	low:rect(cx - 3, canopy - 4, 6, b - canopy + 3, P.Ink)
	low:rect(cx - 2, canopy - 4, 4, b - canopy + 2, P.Bark)
	low:rect(cx + 1, canopy - 4, 1, b - canopy + 2, P.Brown)
	if kind == "pine" then
		-- three tiers, narrower going up
		local tiers = { { 13, 9, canopy - 9 }, { 10, 8, canopy - 17 }, { 6, 7, canopy - 24 } }
		for _, t in tiers do
			local hw, th, ty = t[1], t[2], t[3]
			high:rect(cx - hw, ty, hw * 2, th, col[1])
			high:rect(cx - hw + 2, ty - 2, hw * 2 - 4, 2, col[1])
			high:rect(cx - hw + 1, ty, hw * 2 - 2, th - 1, col[2])
			high:rect(cx - hw + 3, ty - 1, hw * 2 - 6, 1, col[3])
			high:rect(cx - hw + 2, ty, hw * 2 - 3 - math.floor(hw * 2 / 3), th - 3, col[3])
			high:rect(cx - hw + 3, ty, math.max(2, hw - 3), 1, col[4])
			high:rect(cx - hw + 2, ty + 1, 2, 1, col[4])
		end
		high:rect(cx - 1, canopy - 28, 2, 3, col[1])
		high:rect(cx - 1, canopy - 27, 1, 2, col[4])
	else
		-- a rounded crown of three clumps
		local cy = canopy - 11
		blob(high, cx, cy, 13, 11, col[1])
		blob(high, cx + dx * 2, cy + 1, 12, 10, col[2])
		blob(high, cx - dx, cy - 1, 11, 9, col[3])
		blob(high, cx - dx * 4, cy - 4, 4, 3, col[4])
		high:rect(cx + dx * 4 - 1, cy - 6, 3, 2, col[4])
		-- blossoms / leaf glints
		for i = 1, 5 do
			local bx = cx - 9 + math.floor(hash(x + i, y, 32) * 18)
			local by = cy - 7 + math.floor(hash(x, y + i, 33) * 13)
			high:rect(bx, by, 1, 1, if kind == "sakura" then P.White else P.Amber)
		end
	end
end

local function unknown(
	low: Canvas,
	_high: Canvas,
	_variant: string?,
	x: number,
	y: number,
	w: number,
	h: number
)
	low:rect(x, y, w, h, P.Ink)
	if w > 2 and h > 2 then
		low:rect(x + 1, y + 1, w - 2, h - 2, P.Steel)
		low:rect(x + 1, y + 1, w - 2, 1, P.Slate)
	end
end

local OBJECTS: { [string]: Draw } = {
	fence = fence,
	orbBox = orbBox,
	lantern = lantern,
	sellStand = sellStand,
	pillar = pillar,
	crateShop = shop("crateShop"),
	display = display,
	upgradeShop = shop("upgradeShop"),
	upgradeBoard = upgradeBoard,
	bench = bench,
	tree = tree,
}

World.Kinds = {} :: { string }
for kind in OBJECTS do
	table.insert(World.Kinds, kind)
end
table.sort(World.Kinds)

function World.object(
	low: Canvas,
	high: Canvas,
	object: WorldMap.Object,
	x: number,
	y: number,
	w: number,
	h: number
)
	x, y, w, h = round(x), round(y), round(w), round(h)
	local draw: Draw = OBJECTS[object.kind] or unknown
	draw(low, high, object.variant, x, y, w, h)
end

-- Props narrower than a character (pillars, lanterns, the upgrade board) cannot be split
-- correctly into `low` and `high`: a character standing right behind one shows in front of
-- its lower half. World.prop draws such an object whole (low then high) into a new Canvas, in
-- the same art pixels as World.object, for a renderer that y-sorts it with the characters by
-- its footprint's bottom edge (y + h). Returns nil for every other kind.
World.PropKinds = { pillar = true, lantern = true, upgradeBoard = true } :: { [string]: boolean }

function World.prop(object: WorldMap.Object, x: number, y: number, w: number, h: number): Canvas?
	if not World.PropKinds[object.kind] then
		return nil
	end
	local low, high = Canvas.new(), Canvas.new()
	World.object(low, high, object, x, y, w, h)
	for _, r in high.rects do
		table.insert(low.rects, r)
	end
	return low
end

-- FARM FITTINGS -----------------------------------------------------------------------------

local function railWidth(w: number): number
	return if w >= 24 then 5 elseif w >= 12 then 3 else 1
end

-- The lane's bed and rails: gold-capped rails either side of a dark belt.
function World.lane(canvas: Canvas, x: number, y: number, w: number, h: number)
	x, y, w, h = round(x), round(y), round(w), round(h)
	local rw = railWidth(w)
	canvas:rect(x, y, w, h, P.Ink)
	if rw >= 3 then
		canvas:rect(x + 1, y, 1, h, P.Amber)
		canvas:rect(x + w - 2, y, 1, h, P.Amber)
		canvas:rect(x + 2, y, rw - 3, h, P.Dusk)
		canvas:rect(x + w - rw + 1, y, rw - 3, h, P.Dusk)
		for _, ey in { y, y + h - 2 } do
			canvas:rect(x + 1, ey, rw - 2, 2, P.Yellow)
			canvas:rect(x + w - rw + 1, ey, rw - 2, 2, P.Yellow)
		end
	end
	canvas:rect(x + rw, y, w - rw * 2, h, P.Night)
end

-- One repeat of the moving slats (from y = 0, World.SlatSpacing tall), across the belt only.
function World.laneSlats(canvas: Canvas, w: number, h: number)
	w, h = round(w), round(h)
	local rw = railWidth(w)
	local bw = w - rw * 2
	if bw <= 0 or h <= 0 then
		return
	end
	canvas:rect(rw, 0, bw, 1, P.Steel)
	if h >= 2 then
		canvas:rect(rw, 1, bw, 1, P.Dusk)
	end
end

-- Small padlock centred on (cx, cy), 6 x 7.
local function miniLock(c: Canvas, cx: number, cy: number)
	c:rect(cx - 2, cy - 4, 4, 4, P.Ink)
	c:rect(cx - 1, cy - 3, 2, 2, P.Dusk)
	c:rect(cx - 2, cy - 3, 1, 3, P.Slate)
	c:rect(cx - 3, cy - 1, 6, 5, P.Ink)
	c:rect(cx - 2, cy, 4, 3, P.Amber)
	c:rect(cx - 2, cy, 4, 1, P.Yellow)
	c:rect(cx, cy + 1, 1, 1, P.Ink)
end

-- Production slot: a stone mat with a gold rim when open, dark with a lock when locked.
function World.slot(canvas: Canvas, x: number, y: number, size: number, state: string)
	x, y, size = round(x), round(y), round(size)
	local open = state == "open"
	canvas:rect(x, y, size, size, P.Ink)
	canvas:rect(x + 1, y + 1, size - 2, size - 2, if open then P.Amber else P.Dusk)
	canvas:rect(x + 2, y + 2, size - 4, size - 4, if open then P.Mist else P.Night)
	-- a 4 x 4 checker of equal tiles inside the 2 px rim, joints on each tile's first column
	local t = (size - 4) / 4
	local function edge(k: number): number
		return x + 2 + round(k * t)
	end
	local function edgeY(k: number): number
		return y + 2 + round(k * t)
	end
	local tile = if open then P.Slate else P.Ink
	for j = 0, 3 do
		for i = 0, 3 do
			if (i + j) % 2 == 0 then
				local x0, y0 = edge(i), edgeY(j)
				canvas:rect(x0, y0, edge(i + 1) - x0, edgeY(j + 1) - y0, tile)
			end
		end
	end
	local joint = if open then P.Steel else P.Dusk
	for k = 1, 3 do
		canvas:rect(edge(k), y + 2, 1, size - 4, joint)
		canvas:rect(x + 2, edgeY(k), size - 4, 1, joint)
	end
	if not open then
		local lock = Icons.get("lock")
		if size >= lock.w + 6 then
			canvas:sprite(lock, x + math.floor((size - lock.w) / 2), y + math.floor((size - lock.h) / 2))
		else
			miniLock(canvas, x + math.floor(size / 2), y + math.floor(size / 2))
		end
	end
end

-- Crate Pad: a rounded stone pad, gold ring when usable, dark with a lock when locked.
function World.pad(canvas: Canvas, x: number, y: number, size: number, state: string)
	x, y, size = round(x), round(y), round(size)
	local open = state == "open"
	rounded(canvas, x, y, size, size, P.Ink)
	rounded(canvas, x + 1, y + 1, size - 2, size - 2, if open then P.Amber else P.Steel)
	canvas:rect(x + 2, y + 2, size - 4, size - 4, if open then P.Mist else P.Dusk)
	if open then
		canvas:rect(x + 2, y + 2, size - 4, 1, P.Slate)
		canvas:rect(x + 2, y + 2, 1, size - 4, P.Slate)
		for _, c in
			{
				{ x + 2, y + 2 },
				{ x + size - 4, y + 2 },
				{ x + 2, y + size - 4 },
				{ x + size - 4, y + size - 4 },
			}
		do
			canvas:rect(c[1], c[2], 2, 2, P.Red)
		end
	else
		miniLock(canvas, x + math.floor(size / 2), y + math.floor(size / 2))
	end
end

-- Collect Pad: a woven mat with a gold rim (as in the mock).
function World.collectPad(canvas: Canvas, x: number, y: number, w: number, h: number)
	x, y, w, h = round(x), round(y), round(w), round(h)
	canvas:rect(x, y, w, h, P.Ink)
	canvas:rect(x + 1, y + 1, w - 2, h - 2, P.Amber)
	canvas:rect(x + 2, y + 1, w - 4, h - 2, P.Yellow)
	canvas:rect(x + 3, y + 2, w - 6, h - 4, P.Brown)
	for ly = y + 4, y + h - 4, 3 do
		canvas:rect(x + 4, ly, w - 8, 1, P.DarkBrown)
	end
	-- an orb glyph: what you pick up here
	local cx, cy = x + math.floor(w / 2), y + math.floor(h / 2)
	if w >= 12 and h >= 8 then
		canvas:rect(cx - 2, cy - 2, 4, 4, P.Plum)
		canvas:rect(cx - 1, cy - 2, 2, 4, P.Orchid)
		canvas:rect(cx - 2, cy - 1, 4, 2, P.Orchid)
		canvas:rect(cx - 1, cy - 1, 1, 1, P.White)
	end
end

-- The farm name board (the renderer writes the name on the dark panel, inset 2 px).
function World.sign(canvas: Canvas, x: number, y: number, w: number, h: number)
	x, y, w, h = round(x), round(y), round(w), round(h)
	canvas:rect(x, y, w, h, P.Ink)
	canvas:rect(x + 1, y + 1, w - 2, h - 2, P.Bark)
	canvas:rect(x + 1, y + 1, w - 2, 1, P.Clay)
	canvas:rect(x + 2, y + 2, w - 4, h - 4, P.DarkBrown)
	for _, c in { { x + 1, y + 1 }, { x + w - 2, y + 1 }, { x + 1, y + h - 2 }, { x + w - 2, y + h - 2 } } do
		canvas:rect(c[1], c[2], 1, 1, P.Amber)
	end
end

return World
