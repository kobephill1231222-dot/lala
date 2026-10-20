--!strict
-- Building blocks for Pixel/Art/Characters: a small character grid you stamp text rows into,
-- palette ramps (one shade darker / lighter inside ENDESGA 32), and the step that turns grids
-- into a Sprite Def with one key per colour (so parts that end up the same colour merge into
-- fewer Frames).
--
-- Grids use one character per pixel like Sprite rows ("." is transparent).

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

-- Draws text rows with their top-left at (x, y); "." keeps what is already there.
function Parts.stamp(g: Grid, rows: { string }, x: number, y: number)
	for r, row in rows do
		for c = 1, #row do
			local ch = string.sub(row, c, c)
			if ch ~= "." and ch ~= " " then
				Parts.put(g, x + c - 1, y + r - 1, ch)
			end
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

-- COLOURS ---------------------------------------------------------------------------------

local function rgbKey(c: Color3): number
	return math.floor(c.R * 255 + 0.5) * 65536
		+ math.floor(c.G * 255 + 0.5) * 256
		+ math.floor(c.B * 255 + 0.5)
end

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

-- Palette colours with a clear hue: what accent colours (trim, eyes, glows) snap to, so a
-- pastel blue stays blue instead of turning grey. The greys and the skin tones are left out.
local VIVID = {}
for _, name in
	{ "Rust", "Clay", "Bark", "Brown", "Crimson", "Red", "Orange", "Amber", "Yellow", "Leaf", "Grass" }
do
	table.insert(VIVID, (Palette :: any)[name])
end
for _, name in { "Pine", "Navy", "Sky", "Cyan", "Hot", "Plum", "Orchid", "Rose" } do
	table.insert(VIVID, (Palette :: any)[name])
end

Parts.SkinTones = {
	[rgbKey(Palette.Cream)] = true,
	[rgbKey(Palette.Peach)] = true,
	[rgbKey(Palette.Tan)] = true,
	[rgbKey(Palette.Sand)] = true,
}

local function distance(a: Color3, b: Color3): number
	local dr, dg, db = (a.R - b.R) * 255, (a.G - b.G) * 255, (a.B - b.B) * 255
	return 2 * dr * dr + 4 * dg * dg + 3 * db * db
end

local function hueGap(a: number, b: number): number
	local d = math.abs(a - b) % 1
	return math.min(d, 1 - d) * 360
end

-- True when a colour carries a hue worth keeping (saturated and not near-grey).
function Parts.isVivid(c: Color3): boolean
	local _, s = c:ToHSV()
	local chroma = math.max(c.R, c.G, c.B) - math.min(c.R, c.G, c.B)
	return s > 0.3 and chroma * 255 > 40
end

-- Hue-preserving snap: a saturated colour goes to the nearest vivid palette colour within 75
-- degrees of its hue (skipping `avoid`); anything else to Palette.nearest.
function Parts.vivid(c: Color3, avoid: { [number]: boolean }?): Color3
	if not Parts.isVivid(c) then
		return Palette.nearest(c)
	end
	local hue = c:ToHSV()
	local best, bestD, any, anyD = nil, math.huge, nil, math.huge
	for _, v in VIVID do
		if not (avoid and avoid[rgbKey(v)]) then
			local d = distance(c, v)
			if d < anyD then
				any, anyD = v, d
			end
			if d < bestD and hueGap(hue, (v:ToHSV())) <= 75 then
				best, bestD = v, d
			end
		end
	end
	return best or any or Palette.nearest(c)
end

-- Palette.nearest that refuses to flip a tinted colour's hue (a dark olive jacket stays green
-- instead of turning purple-brown): candidates must be within 75 degrees of its hue.
function Parts.hueSnap(c: Color3?, fallback: Color3): Color3
	if not c then
		return fallback
	end
	local hue, sat = c:ToHSV()
	local chroma = math.max(c.R, c.G, c.B) - math.min(c.R, c.G, c.B)
	local s = Palette.nearest(c)
	if sat >= 0.2 and chroma * 255 >= 12 then
		local best, bestD = nil, math.huge
		for _, p in Palette.All do
			local ph, ps = p:ToHSV()
			local pc = math.max(p.R, p.G, p.B) - math.min(p.R, p.G, p.B)
			if pc * 255 >= 12 and ps >= 0.15 and hueGap(hue, ph) <= 75 then
				local d = distance(c, p)
				if d < bestD then
					best, bestD = p, d
				end
			end
		end
		s = best or s
	end
	if s == Palette.Ink then
		return Palette.Night
	end
	return s
end

-- The skin's ramp (skin, one darker, one lighter) as a set of rgb keys.
function Parts.skinRamp(skin: Color3): { [number]: boolean }
	return {
		[rgbKey(skin)] = true,
		[rgbKey(Parts.darker(skin))] = true,
		[rgbKey(Parts.lighter(skin))] = true,
	}
end

-- An accent colour that must read against the skin: hue-preserving, never on the skin's ramp
-- or a skin tone. Pale colours that would land there turn White (paper, cream) instead.
function Parts.accent(c: Color3?, skin: Color3, fallback: Color3): Color3
	if not c then
		return fallback
	end
	local avoid = Parts.skinRamp(skin)
	local s = Parts.vivid(c, avoid)
	if avoid[rgbKey(s)] or Parts.SkinTones[rgbKey(s)] then
		local _, _, v = c:ToHSV()
		s = if v > 0.6 then Palette.White else Parts.darker(Parts.darker(skin))
	end
	if s == Palette.Ink then
		return Palette.Night
	end
	return s
end

-- The bright core of a glow in colour `c` (never on the skin's ramp).
local GLOW_LIGHT = {
	Amber = "Yellow",
	Orange = "Yellow",
	Yellow = "White",
	Clay = "Amber",
	Rust = "Orange",
	Bark = "Amber",
	Brown = "Clay",
	Red = "Rose",
	Crimson = "Red",
	Hot = "Rose",
	Rose = "White",
	Orchid = "Rose",
	Plum = "Orchid",
	Leaf = "White",
	Grass = "Leaf",
	Pine = "Grass",
	Navy = "Sky",
	Sky = "Cyan",
	Cyan = "White",
}
function Parts.glowLight(c: Color3, skin: Color3): Color3
	local name = nameOf[rgbKey(c)]
	local light = (name and GLOW_LIGHT[name] and (Palette :: any)[GLOW_LIGHT[name]]) or Parts.lighter(c)
	if Parts.skinRamp(skin)[rgbKey(light)] then
		return Palette.White
	end
	return light
end

function Parts.same(a: Color3, b: Color3): boolean
	return rgbKey(a) == rgbKey(b)
end

-- Reads one pixel (0-based); "." outside the grid.
function Parts.get(g: Grid, x: number, y: number): string
	if x >= 0 and y >= 0 and x < g.w and y < g.h then
		return g.cells[y + 1][x + 1]
	end
	return "."
end

-- Like stamp, but only onto empty pixels (things hanging behind what is already drawn).
function Parts.stampUnder(g: Grid, rows: { string }, x: number, y: number)
	for r, row in rows do
		for c = 1, #row do
			local ch = string.sub(row, c, c)
			if ch ~= "." and ch ~= " " and Parts.get(g, x + c - 1, y + r - 1) == "." then
				Parts.put(g, x + c - 1, y + r - 1, ch)
			end
		end
	end
end

-- DEF -------------------------------------------------------------------------------------

local KEYS = "kabcdefghijlmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

-- Turns grids into a Sprite Def. Keys that resolve to the same colour share one key so their
-- pixels merge into the same rectangles; keys are reassigned in a fixed order (deterministic).
function Parts.define(
	name: string,
	grids: { Grid },
	palette: { [string]: Color3 },
	anchor: { number }?
): Sprite.Def
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
		local key = byColor[ck] or string.sub(KEYS, nextKey, nextKey)
		if not byColor[ck] then
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
