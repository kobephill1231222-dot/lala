--!strict
-- Building blocks for Pixel/Art/Characters: a small character grid you stamp text rows into,
-- palette ramps (one shade darker / lighter inside ENDESGA 32), and the step that turns grids
-- into a Sprite Def with one key per colour (so parts that end up the same colour merge into
-- fewer Frames).
--
-- Grids use one character per pixel like Sprite rows: "." is transparent, "_" in a stamp erases.

local Palette = require(script.Parent.Parent.Palette)
local Sprite = require(script.Parent.Parent.Sprite)

local Parts = {}

export type Grid = { w: number, h: number, cells: { { string } } }

function Parts.grid(w: number, h: number): Grid
	local cells = table.create(h)
	for y = 1, h do
		cells[y] = table.create(w, ".")
	end
	return { w = w, h = h, cells = cells }
end

-- Sets one pixel (0-based x, y); anything outside the grid is clipped.
function Parts.put(g: Grid, x: number, y: number, ch: string)
	if x >= 0 and y >= 0 and x < g.w and y < g.h then
		g.cells[y + 1][x + 1] = ch
	end
end

function Parts.get(g: Grid, x: number, y: number): string
	if x >= 0 and y >= 0 and x < g.w and y < g.h then
		return g.cells[y + 1][x + 1]
	end
	return "."
end

-- Draws text rows with their top-left at (x, y). "." keeps what is there, "_" erases.
-- `flip` mirrors the rows left-right first.
function Parts.stamp(g: Grid, rows: { string }, x: number, y: number, flip: boolean?)
	for r, row in rows do
		local n = #row
		for c = 1, n do
			local ch = string.sub(row, c, c)
			if ch ~= "." and ch ~= " " then
				local cx = if flip then x + n - c else x + c - 1
				Parts.put(g, cx, y + r - 1, if ch == "_" then "." else ch)
			end
		end
	end
end

-- Filled rectangle of one key.
function Parts.fill(g: Grid, x: number, y: number, w: number, h: number, ch: string)
	for yy = y, y + h - 1 do
		for xx = x, x + w - 1 do
			Parts.put(g, xx, yy, ch)
		end
	end
end

-- Replaces every pixel of key `from` with `to`.
function Parts.swap(g: Grid, from: string, to: string)
	for _, row in g.cells do
		for i, ch in row do
			if ch == from then
				row[i] = to
			end
		end
	end
end

-- Outlines a key: every empty pixel 4-touching a pixel of `key` becomes `outline`.
function Parts.outline(g: Grid, keys: string, outline: string)
	local marks = {}
	for y = 0, g.h - 1 do
		for x = 0, g.w - 1 do
			if Parts.get(g, x, y) == "." then
				for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
					local n = Parts.get(g, x + d[1], y + d[2])
					if n ~= "." and string.find(keys, n, 1, true) then
						table.insert(marks, { x, y })
						break
					end
				end
			end
		end
	end
	for _, m in marks do
		Parts.put(g, m[1], m[2], outline)
	end
end

function Parts.rows(g: Grid): { string }
	local out = table.create(g.h)
	for y = 1, g.h do
		out[y] = table.concat(g.cells[y])
	end
	return out
end

function Parts.copy(g: Grid): Grid
	local c = Parts.grid(g.w, g.h)
	for y = 1, g.h do
		c.cells[y] = table.clone(g.cells[y])
	end
	return c
end

-- COLOURS ---------------------------------------------------------------------------------

local function rgbKey(c: Color3): number
	return math.floor(c.R * 255 + 0.5) * 65536 + math.floor(c.G * 255 + 0.5) * 256 + math.floor(c.B * 255 + 0.5)
end
Parts.rgbKey = rgbKey

local nameOf: { [number]: string } = {}
for name, c in Palette :: any do
	if typeof(c) == "Color3" then
		nameOf[rgbKey(c)] = name
	end
end

-- One step along ENDESGA 32's ramps (by palette name), so shading stays inside the palette.
local DARKER = {
	White = "Mist",
	Mist = "Slate",
	Slate = "Steel",
	Steel = "Dusk",
	Dusk = "Night",
	Night = "Ink",
	Ink = "Ink",
	Cream = "Peach",
	Peach = "Sand",
	Tan = "Bark",
	Sand = "Bark",
	Bark = "Brown",
	Clay = "Rust",
	Rust = "Brown",
	Brown = "DarkBrown",
	DarkBrown = "Ink",
	Yellow = "Amber",
	Amber = "Orange",
	Orange = "Rust",
	Red = "Crimson",
	Hot = "Crimson",
	Crimson = "DarkBrown",
	Rose = "Orchid",
	Orchid = "Plum",
	Plum = "DarkBrown",
	Leaf = "Grass",
	Grass = "Pine",
	Pine = "DeepTeal",
	DeepTeal = "Ink",
	Cyan = "Sky",
	Sky = "Navy",
	Navy = "Night",
}
local LIGHTER = {
	Ink = "Night",
	Night = "Dusk",
	Dusk = "Steel",
	Steel = "Slate",
	Slate = "Mist",
	Mist = "White",
	White = "White",
	Cream = "White",
	Peach = "Cream",
	Tan = "Cream",
	Sand = "Peach",
	Bark = "Tan",
	Clay = "Tan",
	Rust = "Clay",
	Brown = "Bark",
	DarkBrown = "Brown",
	Yellow = "White",
	Amber = "Yellow",
	Orange = "Amber",
	Red = "Rose",
	Hot = "Rose",
	Crimson = "Red",
	Rose = "Peach",
	Orchid = "Rose",
	Plum = "Orchid",
	Leaf = "Yellow",
	Grass = "Leaf",
	Pine = "Grass",
	DeepTeal = "Pine",
	Cyan = "White",
	Sky = "Cyan",
	Navy = "Sky",
}

local function step(c: Color3, ramp: { [string]: string }, toward: Color3): Color3
	local name = nameOf[rgbKey(c)]
	local nextName = name and ramp[name]
	local nextColor = nextName and (Palette :: any)[nextName]
	if typeof(nextColor) == "Color3" then
		return nextColor
	end
	-- Colours outside the known ramps (a palette extension): blend, then snap.
	return Palette.nearest(c:Lerp(toward, 0.35))
end

function Parts.darker(c: Color3): Color3
	return step(c, DARKER, Color3.new(0, 0, 0))
end

function Parts.lighter(c: Color3): Color3
	return step(c, LIGHTER, Color3.new(1, 1, 1))
end

-- Snaps a config colour; fills that would vanish into the Ink outline move one step lighter.
function Parts.snap(c: Color3?, fallback: Color3): Color3
	local s = if c then Palette.nearest(c) else fallback
	if s == Palette.Ink then
		return Palette.Night
	end
	return s
end

-- DEF -------------------------------------------------------------------------------------

local KEYS = "kabcdefghijlmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

-- Turns grids into a Sprite Def. Keys that resolve to the same colour share one key so their
-- pixels merge into the same rectangles; keys are reassigned in a fixed order (deterministic).
function Parts.define(name: string, grids: { Grid }, palette: { [string]: Color3 }, anchor: { number }?): Sprite.Def
	local used: { [string]: boolean } = {}
	for _, g in grids do
		for _, row in g.cells do
			for _, ch in row do
				if ch ~= "." then
					used[ch] = true
				end
			end
		end
	end
	local order = {}
	for ch in used do
		assert(palette[ch], string.format("%s: key '%s' has no colour", name, ch))
		table.insert(order, ch)
	end
	-- Outline first so it keeps "k"; the rest in byte order.
	table.sort(order, function(a, b)
		if a == "k" or b == "k" then
			return a == "k" and b ~= "k"
		end
		return a < b
	end)
	local byColor: { [number]: string } = {}
	local remap: { [string]: string } = {}
	local outPalette: { [string]: Color3 } = {}
	local nextKey = 1
	for _, ch in order do
		local c = palette[ch]
		local ck = rgbKey(c)
		local key = byColor[ck]
		if not key then
			key = string.sub(KEYS, nextKey, nextKey)
			nextKey += 1
			byColor[ck] = key
			outPalette[key] = c
		end
		remap[ch] = key
	end
	local frames = {}
	for i, g in grids do
		local rows = table.create(g.h)
		for y, row in g.cells do
			local out = table.create(g.w)
			for x, ch in row do
				out[x] = if ch == "." then "." else remap[ch]
			end
			rows[y] = table.concat(out)
		end
		frames[i] = rows
	end
	return Sprite.define({ palette = outPalette, frames = frames, anchor = anchor, name = name })
end

return Parts
