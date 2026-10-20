--!strict
-- 10x10 pixel icons for the HUD, menus, panels and world prompts: cash, orbs, locks, menu
-- buttons, one per farm upgrade and one gem per rarity. Each is a text grid (some stamped
-- together from smaller pieces) with a 1px Ink outline so it reads on any panel; coloured
-- tones are only used inside.

local Palette = require(script.Parent.Parent.Palette)
local Sprite = require(script.Parent.Parent.Sprite)
local Crates = require(script.Parent.Crates)
local Rarities = require(script.Parent.Parent.Parent.Config.Rarities)

type Def = Sprite.Def

local Icons = {}

local P = Palette

-- Writes `rows` into a 10x10 grid at (ox, oy); "." in the stamp is transparent.
local function compose(stamps: { { any } }): { string }
	local grid = table.create(10)
	for y = 1, 10 do
		grid[y] = table.create(10, ".")
	end
	for _, s in stamps do
		local rows, ox, oy = s[1] :: { string }, s[2] :: number, s[3] :: number
		for y, row in rows do
			for x = 1, #row do
				local c = string.sub(row, x, x)
				local gx, gy = x + ox, y + oy
				if c ~= "." and gy >= 1 and gy <= 10 and gx >= 1 and gx <= 10 then
					grid[gy][gx] = c
				end
			end
		end
	end
	local out = table.create(10)
	for y = 1, 10 do
		out[y] = table.concat(grid[y])
	end
	return out
end

-- A green "+" badge, stamped in the bottom-right corner of the "more of something" upgrades.
local PLUS = {
	".kkk.",
	"kDLDk",
	"kLLLk",
	"kDLDk",
	".kkk.",
}
local PLUS_PALETTE = { D = P.Pine, L = P.Leaf }

local function with(base: Sprite.Palette, extra: Sprite.Palette): Sprite.Palette
	local out = table.clone(base)
	for k, v in extra do
		out[k] = v
	end
	return out
end

local ORB_PALETTE = { k = P.Ink, d = P.Plum, o = P.Orchid, l = P.Rose, w = P.White }
local COIN_PALETTE = { c = P.Ink, y = P.Yellow, a = P.Amber, o = P.Orange }

local SPECS: { [string]: { palette: Sprite.Palette, rows: { string } } } = {
	cash = {
		palette = { k = P.Ink, y = P.Yellow, a = P.Amber, o = P.Orange, d = P.DarkBrown },
		rows = {
			"..kkkkkk..",
			".kyyydyyk.",
			"kyaddddaok",
			"kyadaaaaok",
			"kyaddddaok",
			"kyaaaadaok",
			"kyaddddaok",
			"kyaaadaaok",
			".kooooook.",
			"..kkkkkk..",
		},
	},
	orb = {
		palette = ORB_PALETTE,
		rows = {
			"..kkkkkk..",
			".kllooook.",
			"klwwoooook",
			"klwooooodk",
			"kloooooodk",
			"kooooooodk",
			"kooooooddk",
			"kooooodddk",
			".kooddddk.",
			"..kkkkkk..",
		},
	},
	lock = {
		palette = { k = P.Ink, m = P.Mist, s = P.Slate, y = P.Yellow, a = P.Amber, o = P.Orange },
		rows = {
			"...kkkk...",
			"..kmmssk..",
			"..km..sk..",
			"..km..sk..",
			".kkkkkkkk.",
			".kyyyyyyk.",
			".kaakkaok.",
			".kaakkaok.",
			".kooooook.",
			".kkkkkkkk.",
		},
	},
	star = {
		palette = { k = P.Ink, y = P.Yellow, a = P.Amber, o = P.Orange, w = P.White },
		rows = {
			"....kk....",
			"...kyak...",
			"...kyak...",
			"kkkkyyakkk",
			"kyyyyyaaak",
			".kyyyyaak.",
			"..kyyaak..",
			".kyakkaak.",
			"kyak..kaak",
			"kkk....kkk",
		},
	},
	sorcerers = {
		palette = { k = P.Ink, h = P.Rose, H = P.Orchid, s = P.Peach, e = P.Ink, o = P.Night, t = P.Red },
		rows = {
			"..k.kk.k..",
			".khkhhkhk.",
			"khhhhhhhHk",
			"khHhhhhHHk",
			"khsssssshk",
			"kssesseskk",
			".kssssssk.",
			"kkottttokk",
			"koootooook",
			"kkkkkkkkkk",
		},
	},
	crateShop = {
		palette = {
			k = P.Ink,
			r = P.Red,
			c = P.Cream,
			h = P.Steel,
			b = P.Dusk,
			B = P.Night,
			t = P.Sky,
			p = P.Cream,
		},
		rows = {
			"kkkkkkkkkk",
			"krcrcrcrck",
			"krcrcrcrck",
			"kkkkkkkkkk",
			".khhpphhk.",
			".kttppttk.",
			".kbbttbbk.",
			".kBBppBBk.",
			".kBBBBBBk.",
			".kkkkkkkk.",
		},
	},
	upgradeShop = {
		palette = { k = P.Ink, l = P.Leaf, g = P.Grass, d = P.Pine, w = P.Yellow },
		rows = {
			"....kk....",
			"...kwlk...",
			"..kwllgk..",
			".kllllggk.",
			"kkkllggkkk",
			"..kllggk..",
			"..kllggk..",
			"..kllggk..",
			"..klggdk..",
			"..kkkkkk..",
		},
	},
	home = {
		-- a torii gate
		palette = { k = P.Ink, r = P.Red, c = P.Crimson },
		rows = {
			"kkkkkkkkkk",
			"krrrrrrrrk",
			"kkrkkkkrkk",
			".krk..krk.",
			"kkrkkkkrkk",
			"kcrccccrck",
			"kkrkkkkrkk",
			".krk..krk.",
			".krk..krk.",
			".kkk..kkk.",
		},
	},
	settings = {
		palette = { k = P.Ink, m = P.Mist, s = P.Slate, d = P.Steel },
		rows = {
			"...kkkk...",
			".kkkmmkkk.",
			".kmmmmmsk.",
			"kkmmkkssk.",
			"kmmk..ksdk",
			"kmsk..kddk",
			".ksskkddk.",
			".ksssdddk.",
			".kkksdkkk.",
			"...kkkk...",
		},
	},
	close = {
		palette = { k = P.Ink, r = P.Red },
		rows = {
			"kkk....kkk",
			"krrk..krrk",
			"kkrrkkrrkk",
			".kkrrrrkk.",
			"..kkrrkk..",
			"..kkrrkk..",
			".kkrrrrkk.",
			"kkrrkkrrkk",
			"krrk..krrk",
			"kkk....kkk",
		},
	},
	arrow = {
		palette = { k = P.Ink, y = P.Yellow, a = P.Amber, o = P.Orange },
		rows = {
			"..kkkkkk..",
			"..kyyaok..",
			"..kyyaok..",
			"..kyyaok..",
			"kkkyyaokkk",
			"kyyyyaaook",
			".kyyyaaok.",
			"..kyyaok..",
			"...kyok...",
			"....kk....",
		},
	},

	-- Farm upgrades
	orbValue = {
		palette = with(ORB_PALETTE, COIN_PALETTE),
		rows = compose({
			{ { "..kkk..", ".kllok.", "klwoook", "klooodk", "koooodk", ".koddk.", "..kkk.." }, 0, 0 },
			{ { ".ccc.", "cyyac", "cyoac", "caaoc", ".ccc." }, 5, 5 },
		}),
	},
	slots = {
		palette = with({ k = P.Ink, a = P.Amber, m = P.Mist, s = P.Slate }, PLUS_PALETTE),
		rows = compose({
			{
				{
					"kkkkkkkk",
					"kaaaaaak",
					"kamsmsak",
					"kasmsmak",
					"kamsmsak",
					"kasmsmak",
					"kaaaaaak",
					"kkkkkkkk",
				},
				0,
				0,
			},
			{ PLUS, 5, 5 },
		}),
	},
	boxSize = {
		palette = with(
			{ k = P.Ink, a = P.Amber, b = P.Bark, d = P.Brown, o = P.Orchid, l = P.Rose },
			PLUS_PALETTE
		),
		rows = compose({
			{
				{
					"kkkkkkkk",
					"kaloolak",
					"kaooooak",
					"kaaaaaak",
					"kbbbbbbk",
					"kddddddk",
					"kbbbbbbk",
					"kkkkkkkk",
				},
				0,
				1,
			},
			{ PLUS, 5, 5 },
		}),
	},
	openSpeed = {
		palette = { k = P.Ink, b = P.Bark, m = P.Mist, a = P.Amber, s = P.Sky },
		rows = {
			".kkkkkkkk.",
			".kbbbbbbk.",
			"..kmmaak..",
			"..kkmakk..",
			"....kk....",
			"..kkmakk..",
			"..kmmaak..",
			"..kaaaak..",
			".kbbbbbbk.",
			".kkkkkkkk.",
		},
	},
	pads = {
		-- a Crate Pad as it looks in the world (gold rim, red corner marks) with a tiny crate
		palette = with(
			{ k = P.Ink, a = P.Amber, m = P.Mist, r = P.Red, h = P.Bark, t = P.Tan },
			PLUS_PALETTE
		),
		rows = compose({
			{
				{
					".kkkkkkkk.",
					"kaaaaaaaak",
					"kakkkkmrak",
					"kakhhkmmak",
					"kakttkmmak",
					"kakkkkmmak",
					"kammmmmmak",
					"karmmmmrak",
					"kaaaaaaaak",
					".kkkkkkkk.",
				},
				0,
				0,
			},
			{ PLUS, 5, 5 },
		}),
	},
	luck = {
		palette = { k = P.Ink, l = P.Leaf, g = P.Grass, d = P.Pine },
		rows = {
			".kkk.kkk..",
			"kllgkllgk.",
			"klggdgggk.",
			"kgggdggdk.",
			"kdddddddk.",
			"kllgdllgk.",
			"klggdgggk.",
			"kgggdggdk.",
			".kkkdkkk..",
			"....kk....",
		},
	},
	walkSpeed = {
		palette = { k = P.Ink, b = P.Bark, l = P.Clay, d = P.Brown, w = P.Cream, s = P.Sky },
		rows = {
			"....kkkk..",
			"ss..klbk..",
			"....klbk..",
			"sss.klbk..",
			"...klbbk..",
			"ss.klbbkkk",
			"..klbbbbbk",
			"..kwwwwwwk",
			"..kddddddk",
			"..kkkkkkkk",
		},
	},
}

-- Rarity gems: one shape with an Ink outline, a colour ramp per rarity (dark, base, light).
local GEM = {
	"..kkkkkk..",
	".kwlllodk.",
	"kwlllloddk",
	"kllllooddk",
	".kllooodk.",
	".kloooodk.",
	"..kloodk..",
	"..kloodk..",
	"...kodk...",
	"....kk....",
}
local GEMS: { [string]: { string } } = {
	Common = { "Slate", "Mist", "White" },
	Uncommon = { "Pine", "Grass", "Leaf" },
	Rare = { "Navy", "Sky", "Cyan" },
	Epic = { "Plum", "Orchid", "Rose" },
	Legendary = { "Orange", "Amber", "Yellow" },
}

local UNKNOWN = {
	palette = { k = P.Ink, m = P.Slate, w = P.White },
	rows = {
		"kkkkkkkkkk",
		"kmmmmmmmmk",
		"kmmwwwwmmk",
		"kmwmmmmwmk",
		"kmmmmmwmmk",
		"kmmmmwmmmk",
		"kmmmmmmmmk",
		"kmmmmwmmmk",
		"kmmmmmmmmk",
		"kkkkkkkkkk",
	},
}

local function gemPalette(rarity: string): Sprite.Palette?
	local names = GEMS[rarity]
	if names then
		local p = Palette :: any
		return { k = P.Ink, d = p[names[1]], o = p[names[2]], l = p[names[3]], w = P.White }
	end
	local info = Rarities.get(rarity)
	if info then
		local base = Palette.nearest(info.color)
		return {
			k = P.Ink,
			d = Palette.nearest(Palette.shade(base, 0.4)),
			o = base,
			l = Palette.nearest(info.glow),
			w = P.White,
		}
	end
	return nil
end

local cache: { [string]: Def } = {}

-- The icon called `name` (see the list above; "rarity_<Rarity>" for gems). Unknown names
-- get a "?" tile instead of an error.
function Icons.get(name: string): Def
	local hit = cache[name]
	if hit then
		return hit
	end
	local def: Def
	if name == "crates" then
		def = Crates.icon("basic")
	else
		local spec = SPECS[name]
		local rarity = string.match(name, "^rarity_(.+)$")
		local gem = rarity and gemPalette(rarity)
		if gem then
			spec = { palette = gem, rows = GEM }
		end
		spec = spec or UNKNOWN
		def = Sprite.define({ name = "Icon_" .. name, palette = spec.palette, frames = { spec.rows } })
	end
	cache[name] = def
	return def
end

-- Every icon name (for tests and previews).
Icons.Names = {
	"cash",
	"orb",
	"lock",
	"star",
	"sorcerers",
	"crates",
	"crateShop",
	"upgradeShop",
	"home",
	"settings",
	"close",
	"arrow",
	"orbValue",
	"slots",
	"boxSize",
	"openSpeed",
	"pads",
	"luck",
	"walkSpeed",
}
for _, rarity in Rarities.Order do
	table.insert(Icons.Names, "rarity_" .. rarity)
end

return Icons
