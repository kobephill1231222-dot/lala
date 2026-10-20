--!strict
-- Pixel-art Crates: a lacquered chest bound with a paper seal (strap over the lid and down the
-- front, red ink glyph on top, round seal on the front), coloured per tier. Every tier shares
-- one silhouette; the colours come from Config/Crates (hand-picked palette ramps for the five
-- tiers, snapped config colours for any tier added later).

local Palette = require(script.Parent.Parent.Palette)
local Sprite = require(script.Parent.Parent.Sprite)
local CrateConfig = require(script.Parent.Parent.Parent.Config.Crates)

type Def = Sprite.Def

local Crates = {}

-- Keys: h lid top, b body, B body shade, t trim, T trim shade, m corner metal, g glow.
local TIERS: { [string]: { [string]: string } } = {
	starter = { h = "Tan", b = "Bark", B = "Brown", t = "Slate", T = "Steel", m = "Dusk", g = "White" },
	basic = { h = "Bark", b = "Brown", B = "DarkBrown", t = "Tan", T = "Sand", m = "Dusk", g = "Yellow" },
	rare = { h = "Steel", b = "Dusk", B = "Night", t = "Sky", T = "Navy", m = "Mist", g = "Cyan" },
	epic = { h = "Orchid", b = "Plum", B = "Night", t = "Orchid", T = "Plum", m = "Amber", g = "Rose" },
	legendary = { h = "Amber", b = "Brown", B = "DarkBrown", t = "Amber", T = "Orange", m = "Yellow", g = "Yellow" },
}

local function lerp(a: Color3, b: Color3, t: number): Color3
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

local function tierPalette(tier: string): Sprite.Palette
	local P = Palette :: any
	local pal: Sprite.Palette = {
		k = Palette.Ink,
		p = Palette.Cream,
		r = Palette.Red,
		w = Palette.White,
	}
	local named = TIERS[tier]
	local config = CrateConfig.get(tier)
	if not named and config then
		-- A tier this art doesn't know yet: snap its config colours.
		pal.h = Palette.nearest(lerp(config.body, Color3.new(1, 1, 1), 0.25))
		pal.b = Palette.nearest(config.body)
		pal.B = Palette.nearest(Palette.shade(config.body, 0.45))
		pal.t = Palette.nearest(config.color)
		pal.T = Palette.nearest(Palette.shade(config.color, 0.4))
		pal.m = Palette.Dusk
		pal.g = Palette.White
		return pal
	end
	for k, name in named or TIERS.starter do
		pal[k] = P[name]
	end
	return pal
end

-- 16x16, closed. The lid is rows 1-6, the body rows 7-14.
local CLOSED = {
	"................",
	"..kkkkkkkkkkkk..",
	".khhhhhpphhhhhk.",
	".khhhhhrrhhhhhk.",
	".kbbbbbppbbbbbk.",
	".kmttttppttttmk.",
	".kkkkkkppkkkkkk.",
	".kmbbbbppbbbbmk.",
	".kmttttppttttmk.",
	".kmbbbmttmbbbmk.",
	".kmbbbmttmbbbmk.",
	".kmBBBBppBBBBmk.",
	".kmTTTTppTTTTmk.",
	".kmBBBBBBBBBBmk.",
	".kkkkkkkkkkkkkk.",
	"................",
}

-- The open crate (frame 4): lid gone, light pouring out.
local OPEN_TOP = {
	"...g...w..g.....",
	".....g.ww...g...",
	"..g...gwwg....g.",
	"....g.gwwg.g....",
	"..kkkkkkkkkkkk..",
	".kmgggwwwwgggmk.",
	".kmttttppttttmk.",
}

local function setChar(row: string, i: number, c: string): string
	return string.sub(row, 1, i - 1) .. c .. string.sub(row, i + 1)
end

-- Lid rows (1-6) shifted by dx, with motion ticks on the trailing side.
local function shaken(dx: number): { string }
	local rows = table.clone(CLOSED)
	for i = 2, 7 do
		local row = rows[i]
		rows[i] = if dx < 0 then string.sub(row, 2) .. "." else "." .. string.sub(row, 1, -2)
	end
	local tick = if dx < 0 then 16 else 1
	rows[4] = setChar(rows[4], tick, "w")
	rows[11] = setChar(rows[11], tick, "w")
	return rows
end

local function opened(): { string }
	local rows = table.clone(CLOSED)
	for i, row in OPEN_TOP do
		rows[i] = row
	end
	return rows
end

local LID = {
	{
		"................",
		"..kkkkkkkkkkkk..",
		".khhhhhpphhhhhk.",
		".khhhhhrrhhhhhk.",
		".kbbbbbppbbbbbk.",
		".kmttttppttttmk.",
		".kkkkkkkkkkkkkk.",
		"................",
	},
	{
		"................",
		"................",
		"................",
		".kkkkkkkkkkkkkk.",
		".kmttttppttttmk.",
		".kkkkkkkkkkkkkk.",
		"................",
		"................",
	},
	{
		"................",
		".kkkkkkkkkkkkkk.",
		".kmttttppttttmk.",
		".kBBBBBBBBBBBBk.",
		".kBBBBBBBBBBBBk.",
		"..kkkkkkkkkkkk..",
		"................",
		"................",
	},
	{
		"................",
		"................",
		"................",
		".kkkkkkkkkkkkkk.",
		".kmttttppttttmk.",
		".kkkkkkkkkkkkkk.",
		"................",
		"................",
	},
}

local ICON = {
	".kkkkkkkk.",
	"khhhpphhhk",
	"ktttpptttk",
	"kkkkppkkkk",
	"kmbbppbbmk",
	"kmbmttmbmk",
	"kmttppttmk",
	"kmBBppBBmk",
	"kmBBBBBBmk",
	"kkkkkkkkkk",
}

local cache: { [string]: Def } = {}

local function cached(kind: string, tier: string, build: () -> Def): Def
	local k = kind .. ":" .. tier
	local def = cache[k]
	if not def then
		def = build()
		cache[k] = def
	end
	return def
end

-- 16x16, anchor bottom middle. Frames: 1 closed, 2 shake left, 3 shake right, 4 open (glow).
function Crates.sprite(tier: string): Def
	return cached("sprite", tier, function()
		return Sprite.define({
			name = "Crate_" .. tier,
			palette = tierPalette(tier),
			anchor = { 8, 16 },
			frames = { table.clone(CLOSED), shaken(-1), shaken(1), opened() },
		})
	end)
end

-- 16x8, anchor at the centre: the lid that flies off when the crate opens. Frames tumble:
-- top, edge, underside, edge.
function Crates.lid(tier: string): Def
	return cached("lid", tier, function()
		return Sprite.define({
			name = "CrateLid_" .. tier,
			palette = tierPalette(tier),
			anchor = { 8, 4 },
			frames = LID,
		})
	end)
end

-- 10x10 glyph for lists and buttons.
function Crates.icon(tier: string): Def
	return cached("icon", tier, function()
		return Sprite.define({ name = "CrateIcon_" .. tier, palette = tierPalette(tier), frames = { ICON } })
	end)
end

return Crates
