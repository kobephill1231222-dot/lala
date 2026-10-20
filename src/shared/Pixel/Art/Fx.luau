--!strict
-- Pixel-art effects: Cursed Orbs, sparks, spinning coins, technique slashes and bolts, and the
-- rings and light pillars of collects, sells and reveals. Sprites are small text grids built
-- from a colour ramp (dark, base, light) of any colour; rings and pillars draw into a Canvas.
-- Everything is centred on its anchor, and directional effects face RIGHT (mirror for left).

local Palette = require(script.Parent.Parent.Palette)
local Sprite = require(script.Parent.Parent.Sprite)
local Canvas = require(script.Parent.Parent.Canvas)

type Def = Sprite.Def

local Fx = {}

-- COLOUR RAMPS -----------------------------------------------------------------------------
-- For each palette colour: the next darker and lighter colour along ENDESGA's ramps.

local RAMP: { [string]: { string } } = {
	Rust = { "Crimson", "Clay" },
	Clay = { "Rust", "Tan" },
	Cream = { "Tan", "White" },
	Tan = { "Bark", "Cream" },
	Bark = { "Brown", "Tan" },
	Brown = { "DarkBrown", "Bark" },
	DarkBrown = { "Ink", "Brown" },
	Crimson = { "DarkBrown", "Red" },
	Red = { "Crimson", "Rose" },
	Orange = { "Rust", "Amber" },
	Amber = { "Orange", "Yellow" },
	Yellow = { "Amber", "White" },
	Leaf = { "Grass", "Yellow" },
	Grass = { "Pine", "Leaf" },
	Pine = { "DeepTeal", "Grass" },
	DeepTeal = { "Ink", "Pine" },
	Navy = { "Night", "Sky" },
	Sky = { "Navy", "Cyan" },
	Cyan = { "Sky", "White" },
	White = { "Mist", "White" },
	Mist = { "Slate", "White" },
	Slate = { "Steel", "Mist" },
	Steel = { "Dusk", "Slate" },
	Dusk = { "Night", "Steel" },
	Night = { "Ink", "Dusk" },
	Ink = { "Ink", "Night" },
	Hot = { "Crimson", "Rose" },
	Plum = { "Night", "Orchid" },
	Orchid = { "Plum", "Rose" },
	Rose = { "Orchid", "Peach" },
	Peach = { "Sand", "Cream" },
	Sand = { "Brown", "Peach" },
}

local function key(c: Color3): string
	return string.format("%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local byKey: { [string]: string } = {}
for name in RAMP do
	byKey[key((Palette :: any)[name])] = name
end

local function hsv(c: Color3): (number, number, number)
	local r, g, b = c.R, c.G, c.B
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then
			h = ((g - b) / d) % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
	end
	return h * 60, if mx > 0 then d / mx else 0, mx
end

-- Snaps a colour to the palette keeping its hue (Palette.nearest turns violets grey).
local function snapName(color: Color3): string
	local exact = byKey[key(color)]
	if exact then
		return exact
	end
	local h, s, v = hsv(color)
	if s < 0.2 then
		return byKey[key(Palette.nearest(color))] or "Slate"
	end
	local best, bestD = "Slate", math.huge
	for name in RAMP do
		local ph, ps, pv = hsv((Palette :: any)[name])
		if ps >= 0.3 and pv >= 0.3 then
			local dh = math.abs(h - ph)
			dh = math.min(dh, 360 - dh)
			local d = (dh / 45) ^ 2 + ((v - pv) / 0.35) ^ 2 + ((s - ps) / 0.6) ^ 2
			if d < bestD or (d == bestD and name < best) then
				best, bestD = name, d
			end
		end
	end
	return best
end

-- (dark, base, light) palette colours for any colour.
local function ramp(color: Color3): (Color3, Color3, Color3)
	local name = snapName(color)
	local r = RAMP[name]
	local P = Palette :: any
	return P[r[1]], P[name], P[r[2]]
end

local function palette(color: Color3): Sprite.Palette
	local d, o, l = ramp(color)
	return { d = d, o = o, l = l, w = Palette.White, k = Palette.Ink, y = Palette.Yellow, a = Palette.Amber }
end

local cache: { [string]: Def } = {}

local function cached(name: string, color: Color3, build: () -> Def): Def
	local k = name .. key(color)
	local def = cache[k]
	if not def then
		def = build()
		cache[k] = def
	end
	return def
end

-- SPRITES ----------------------------------------------------------------------------------

-- A Cursed Orb in `color`: 6x6, frame 1 at rest, frame 2 glowing. Anchor at the centre.
function Fx.orb(color: Color3): Def
	return cached("orb", color, function()
		return Sprite.define({
			name = "Orb",
			palette = palette(color),
			anchor = { 3, 3 },
			frames = {
				{
					".dddd.",
					"dwlood",
					"dloood",
					"dooood",
					"dooodd",
					".dddd.",
				},
				{
					".oooo.",
					"owwllo",
					"owlllo",
					"ollllo",
					"ollllo",
					".oooo.",
				},
			},
		})
	end)
end

-- A golden twinkle: 7x7, 3 frames (pop, burst, fade). Anchor at the centre.
Fx.spark = Sprite.define({
	name = "Spark",
	palette = { y = Palette.Yellow, w = Palette.White, a = Palette.Amber },
	anchor = { 3, 3 },
	frames = {
		{
			".......",
			".......",
			"...y...",
			"..ywy..",
			"...y...",
			".......",
			".......",
		},
		{
			"...y...",
			"...w...",
			"..ywy..",
			"ywwwwwy",
			"..ywy..",
			"...w...",
			"...y...",
		},
		{
			"...a...",
			".......",
			".a...a.",
			"a..y..a",
			".a...a.",
			".......",
			"...a...",
		},
	},
})

-- A spinning gold coin: 8x8, 4 frames (face, turning, edge, back). Anchor at the centre.
Fx.coin = Sprite.define({
	name = "Coin",
	palette = { k = Palette.Brown, y = Palette.Yellow, a = Palette.Amber, o = Palette.Orange, w = Palette.White },
	anchor = { 4, 4 },
	frames = {
		{
			"..kkkk..",
			".kwyyyk.",
			"kyyaaaok",
			"kyaooaok",
			"kyaooaok",
			"kyaaaaok",
			".kooook.",
			"..kkkk..",
		},
		{
			"...kk...",
			"..kwyk..",
			".kyyaok.",
			".kyooak.",
			".kyooak.",
			".kyaaok.",
			"..kook..",
			"...kk...",
		},
		{
			"...kk...",
			"...wk...",
			"...yk...",
			"...yk...",
			"...ak...",
			"...ak...",
			"...ok...",
			"...kk...",
		},
		{
			"...kk...",
			"..kyak..",
			".kyaaok.",
			".kaaaok.",
			".kaaaok.",
			".kaaook.",
			"..kook..",
			"...kk...",
		},
	},
})

-- A crescent blade swing facing right: 16x16, 3 frames (start, full arc, fading).
-- Built from two circles: inside A (centre 4,8 r 10), outside B (centre 1,8 r 10.5).
function Fx.slash(color: Color3): Def
	return cached("slash", color, function()
		local frames = {}
		for f = 1, 3 do
			local rows = {}
			for y = 0, 15 do
				local row = table.create(16, ".")
				for x = 0, 15 do
					local px, py = x + 0.5, y + 0.5
					local da = math.sqrt((px - 4) ^ 2 + (py - 8) ^ 2)
					local db = math.sqrt((px - 1) ^ 2 + (py - 8) ^ 2)
					if da <= 10 and db > 10.5 then
						local depth = 10 - da -- 0 at the outer edge
						local c = if depth < 1 then "w" elseif depth < 2 then "l" else "o"
						if f == 1 then
							-- the blade's leading edge: the upper two thirds, thin
							if py > 11 or depth >= 1.6 then
								c = "."
							end
						elseif f == 3 then
							-- fading: the inner side only, darker, dissolving from the top
							if depth < 0.8 or py < 3 or (py < 9 and (x + y) % 2 == 1) then
								c = "."
							else
								c = if (x + y) % 2 == 0 then "o" else "d"
							end
						end
						row[x + 1] = c
					end
				end
				rows[y + 1] = table.concat(row)
			end
			frames[f] = rows
		end
		return Sprite.define({ name = "Slash", palette = palette(color), anchor = { 8, 8 }, frames = frames })
	end)
end

-- A technique bolt flying right (needles, arrows): 12x5, 2 frames (flicker). Anchor at the tip.
function Fx.bolt(color: Color3): Def
	return cached("bolt", color, function()
		return Sprite.define({
			name = "Bolt",
			palette = palette(color),
			anchor = { 11, 2 },
			frames = {
				{
					"........oo..",
					"..d.oooolwo.",
					"d.oolllllwww",
					"..d.oooolwo.",
					"........oo..",
				},
				{
					".......o....",
					".d..oooollo.",
					"..ooolllwwww",
					".d..oooollo.",
					".......o....",
				},
			},
		})
	end)
end

-- CANVAS EFFECTS ---------------------------------------------------------------------------

-- A one-pixel circle outline of radius r around (cx, cy), merged into runs.
function Fx.ring(canvas: Canvas.Canvas, cx: number, cy: number, r: number, color: Color3)
	cx, cy, r = math.floor(cx + 0.5), math.floor(cy + 0.5), math.max(0, math.floor(r + 0.5))
	if r == 0 then
		canvas:px(cx, cy, color)
		return
	end
	-- Midpoint circle: collect the outline pixels once (no duplicates)
	local rows: { [number]: { [number]: boolean } } = {}
	local function plot(x: number, y: number)
		rows[y] = rows[y] or {}
		rows[y][x] = true
	end
	local x, y, err = r, 0, 1 - r
	while x >= y do
		plot(cx + x, cy + y)
		plot(cx - x, cy + y)
		plot(cx + x, cy - y)
		plot(cx - x, cy - y)
		plot(cx + y, cy + x)
		plot(cx - y, cy + x)
		plot(cx + y, cy - x)
		plot(cx - y, cy - x)
		y += 1
		if err < 0 then
			err += 2 * y + 1
		else
			x -= 1
			err += 2 * (y - x) + 1
		end
	end
	-- Horizontal runs; single pixels stack into vertical runs per column.
	local singles: { [number]: { number } } = {}
	for yy = cy - r, cy + r do
		local row = rows[yy]
		if row then
			local xs = {}
			for xx in row do
				table.insert(xs, xx)
			end
			table.sort(xs)
			local i = 1
			while i <= #xs do
				local j = i
				while j < #xs and xs[j + 1] == xs[j] + 1 do
					j += 1
				end
				if j > i then
					canvas:rect(xs[i], yy, xs[j] - xs[i] + 1, 1, color)
				else
					singles[xs[i]] = singles[xs[i]] or {}
					table.insert(singles[xs[i]], yy)
				end
				i = j + 1
			end
		end
	end
	for xx = cx - r, cx + r do
		local ys = singles[xx]
		if ys then
			local i = 1
			while i <= #ys do
				local j = i
				while j < #ys and ys[j + 1] == ys[j] + 1 do
					j += 1
				end
				canvas:rect(xx, ys[i], 1, ys[j] - ys[i] + 1, color)
				i = j + 1
			end
		end
	end
end

-- A beam of light rising from (cx, bottom): w wide, h tall, white core, tapering tip and a
-- glowing foot.
function Fx.pillar(canvas: Canvas.Canvas, cx: number, bottom: number, w: number, h: number, color: Color3)
	cx, bottom = math.floor(cx + 0.5), math.floor(bottom + 0.5)
	w, h = math.max(1, math.floor(w + 0.5)), math.max(1, math.floor(h + 0.5))
	local dark, base, light = ramp(color)
	local top = bottom - h
	local x0 = cx - math.floor(w / 2)
	local tip = math.min(math.max(2, math.floor(h / 6)), h)
	local edge = math.max(1, math.floor(w / 4))
	-- foot glow
	canvas:rect(x0 - 3, bottom - 1, w + 6, 2, dark)
	canvas:rect(x0 - 1, bottom - 2, w + 2, 2, base)
	-- tip, narrower
	if w > 2 then
		canvas:rect(x0 + 1, top, w - 2, tip, base)
	else
		canvas:rect(x0, top, w, tip, base)
	end
	-- body: colour edges, light inside, white core
	canvas:rect(x0, top + tip, w, h - tip, base)
	if w - 2 * edge > 0 then
		canvas:rect(x0 + edge, top + 1, w - 2 * edge, h - 1, light)
	end
	local core = math.max(1, math.floor(w / 4))
	canvas:rect(cx - math.floor(core / 2), top + tip, core, h - tip, Palette.White)
	-- motes beside the beam
	canvas:px(x0 - 2, top + math.floor(h * 0.3), light)
	canvas:px(x0 + w + 1, top + math.floor(h * 0.55), light)
	canvas:px(x0 - 1, top + math.floor(h * 0.75), base)
end

return Fx
