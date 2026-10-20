--!strict
-- Pixel-art characters: chibi 16x20 people in a top-down 3/4 view with a 1px Ink outline, in
-- ENDESGA 32. Sorcerers are generated from their look in Config/Sorcerers (hair style, colours,
-- accessories, streak), never drawn per id: a head per hair style, a body per pose, then the
-- accessories and the technique glow. Characters face RIGHT; the renderer mirrors for left.
-- Also: companions, 24x24 portraits, the player and the carried Orb Box.
--
-- Colours: skin, hair and outfit snap with Palette.nearest (pale skin is Peach, like the
-- approved mock); accents (trim, eyes, glows, orbs, bright pants) keep their hue through
-- Parts.accent so a pastel blue trim stays blue instead of turning grey, and never land on the
-- skin's ramp. The returned `color` is still Palette.nearest(technique colour). The player's
-- avatar colours are snapped the same way, so every pixel is a Palette colour.

local Palette = require(script.Parent.Parent.Palette)
local Sprite = require(script.Parent.Parent.Sprite)
local Parts = require(script.Parent.CharacterParts)
local Sorcerers = require(script.Parent.Parent.Parent.Config.Sorcerers)

type Grid = Parts.Grid
type Def = Sprite.Def
type Rows = { string }
type Stamp = { x: number, y: number, rows: Rows }

local Characters = {}

Characters.Size = { w = 16, h = 20 }
local W, H = 16, 20
local ANCHOR = { 8, 20 }

-- Grid keys used by every Sorcerer frame (colours come from the look, see lookPalette):
--   k outline   h/H/L hair, shade, light   z hair streak   s/S skin, shade   e eyes
--   o/O outfit, shade   t/T trim, shade   p pants   j hands (stone for Gauntlets)
--   x/X technique glow, light   c haori coat   f/F scarf, shade   u/U orbs and halo, core
--   w white   g/G gold, light   m stone   n wood   a/A blade, edge   v scabbard
--   q/r talisman paper, seal   b bow limbs   y bow string

-- HEADS -----------------------------------------------------------------------------------
-- Rows from y0 at rest; the face is the same in every style, "z" marks where a streak shows.

local HEADS: { [string]: Rows } = {
	Short = {
		"................",
		"................",
		"....kkkkkkkk....",
		"...khhhhhhhhk...",
		"..khhhhhhhhhLk..",
		"..kHhzhhhhhhhk..",
		"..kHhzhhhhhhhk..",
		"..kHhhhsshhssk..",
		"..kHhhSskssksk..",
		"..kHhhSsessesk..",
		"...kkkSsssssk...",
	},
	-- a sawtooth of small spikes with 1px tips (as in the mock), swept back into a rear spike
	Spiky = {
		"................",
		"...k.k.kk.k.....",
		"..khkhkhhkhk....",
		".kkhhhhhhhhhhk..",
		"kHhhhhhhhhhhhLk.",
		".kHhzhhhhhhhhk..",
		"..kHzhhhhhhhhk..",
		"..kHhhhsshhssk..",
		"..kHhhSskssksk..",
		"..kHhhSsessesk..",
		"...kkkSsssssk...",
	},
	Bob = {
		"................",
		"................",
		"....kkkkkkkk....",
		"...khhhhhhhhk...",
		"..khhhhhhhhhLk..",
		".khhzhhhhhhhhk..",
		".kHhzhhhhhhhhk..",
		".kHhhhhhhhhhhk..",
		".kHhhhSskssksk..",
		".kHhhhSsessesk..",
		".kHHHkkSssssk...",
		".kkkk...........",
	},
	Long = {
		"................",
		"................",
		"....kkkkkkkk....",
		"...khhhhhhhhk...",
		"..khhhhhhhhhLk..",
		".khhzhhhhhhhhk..",
		".kHhzhhhhhhhhk..",
		".kHhhhhsshhssk..",
		".kHhhhSskssksk..",
		".kHhhhSsessesk..",
		".kHhhkkSssssk...",
	},
	Ponytail = {
		"................",
		"................",
		"....kkkkkkkk....",
		"...khhhhhhhhk...",
		"..khhhhhhhhhLk..",
		"..kHhzhhhhhhhk..",
		"kttkhzhhhhhhhk..",
		"kttkhhhsshhssk..",
		".kkHhhSskssksk..",
		"..kHhhSsessesk..",
		"...kkkSsssssk...",
	},
	Swept = {
		"................",
		"................",
		"....kkkkkkkk....",
		"...khhhhhhhhk...",
		"..khhhhhhhhhLk..",
		"..kHzhhhhhhhhhk.",
		"..kHzhhhhhzzhhk.",
		"..kHzhhhhhhzssk.",
		"..kHhzShhhhksk..",
		"..kHhzSshhsesk..",
		"...kkkSsssssk...",
	},
}

-- Hair that hangs behind the body (drawn first), at rest; rows start at row `y`.
local HAIR_BACK: { [string]: { y: number, rows: Rows } } = {
	Long = {
		y = 11,
		rows = {
			".kHhhk..........",
			".kHhhk..........",
			".kHhhk..........",
			".kHhk...........",
			"..kk............",
		},
	},
	Ponytail = {
		y = 8,
		rows = {
			"khhk............",
			"khHk............",
			"khHk............",
			"kHk.............",
			"kk..............",
		},
	},
}

-- BODIES ----------------------------------------------------------------------------------
-- Upper body rows from y11 (moves with the head) and legs y16..y19. The jacket is the outfit
-- with a trim placket and belt; hands are "j" so Gauntlets can turn them to stone.

local UPPER: { [string]: Rows } = {
	idle = {
		"....kkkkkkkk....",
		"...kOoootoook...",
		"..kjOoootooojk..",
		"..kjOoootooojk..",
		"...kttttttttk...",
	},
	-- near fist cocked back at the hip, far hand up as a guard
	cock = {
		"....kkkkkkkk....",
		"..kkOoootookk...",
		".kjjOoootookjk..",
		".kjjOoootoookk..",
		"..kkttttttttk...",
	},
	-- near arm straight forward at shoulder height
	thrust = {
		"....kkkkkkkkkkk.",
		"...kOoootoootjjk",
		"..kjOoootoootjjk",
		"..kjOoootookkkk.",
		"...kttttttttk...",
	},
	-- both hands together in front of the chest
	gather = {
		"....kkkkkkkk....",
		"...kOoootoookkk.",
		"..kjOoootooojjk.",
		"..kjOoootooojjk.",
		"...kttttttttkkk.",
	},
	-- near arm raised (the arm itself is an ARMS stamp drawn over the head)
	raise = {
		"....kkkkkkkk....",
		"...kOoootookkkk.",
		"..kjOoootook....",
		"..kjOoootook....",
		"...kttttttttk...",
	},
	-- both hands forward on a sword hilt, cutting down
	cut = {
		"....kkkkkkkkk...",
		"...kOoootoojjk..",
		"..kjOoootoojjk..",
		"..kjOoootookkk..",
		"...kttttttttk...",
	},
	-- both hands on a held staff in front of the belly
	grip = {
		"....kkkkkkkk....",
		"...kOoootoook...",
		"...kOoojjoook...",
		"...kOoojjoook...",
		"...kttttttttk...",
	},
	-- hands low and forward (weapon swung through, punch dropped)
	low = {
		"....kkkkkkkk....",
		"...kOoootoook...",
		"..kjOoootoookk..",
		"..kjOoootooojjk.",
		"...kttttttttjjk.",
		"............kk..",
	},
	-- bow arm forward, string hand drawn back to the chest
	aim = {
		"....kkkkkkkkkkk.",
		"...kOoootjootjjk",
		"...kOoootoootjjk",
		"...kOoootookkkk.",
		"...kttttttttk...",
	},
}

local LEGS: { [string]: Rows } = {
	stand = {
		"....kppkkppk....",
		"....kppkkppk....",
		"....kkkk.kkkk...",
		"....kkkk.kkkk...",
	},
	lunge = {
		"....kppkkppk....",
		"...kppk.kppk....",
		"..kkkk..kkkkk...",
		"..kkkk..kkkkk...",
	},
	brace = {
		"....kppkkppk....",
		"...kppk..kppk...",
		"..kkkk...kkkk...",
		"..kkkk...kkkk...",
	},
}

-- Arms drawn after the head (in front of the face).
local ARMS: { [string]: Stamp } = {
	-- the near arm raised straight up, open hand
	raise = {
		x = 12,
		y = 4,
		rows = {
			".kk.",
			"kjjk",
			"kjjk",
			"kook",
			"kook",
			"kook",
			"kook",
			"oook",
		},
	},
	-- the near arm lifting a weapon: fists at y7..8, the weapon stamp sits on top of them
	lift = {
		x = 12,
		y = 7,
		rows = {
			".kjk",
			".kjk",
			".kok",
			".kok",
			"oook",
		},
	},
}

-- TECHNIQUE GLOW --------------------------------------------------------------------------
-- Stamps in the technique colour (x) and its light (X), in sprite pixels at rest. Nothing is
-- stamped on the shoulder row (y11) so the arm outlines stay whole.

local FX: { [string]: Stamp } = {
	charge = { x = 0, y = 12, rows = { "x", "X", "X", "x" } },
	impact = { x = 15, y = 11, rows = { "x", "X", "X", "x" } },
	burst = { x = 13, y = 7, rows = { "..x", "...", ".X.", "...", "...", "...", "...", "..X", "...", ".x." } },
	spark = { x = 15, y = 12, rows = { "x", "X", "X", "x" } },
	orb = { x = 12, y = 0, rows = { ".xx.", "xXXx", ".xx." } },
	release = { x = 15, y = 11, rows = { "x", "X", "X", "x" } },
	needles = { x = 0, y = 12, rows = { "X", "x", "X" } },
	needle = { x = 15, y = 12, rows = { "X", "X" } },
	swish = { x = 14, y = 3, rows = { "x.", ".X", ".X", ".X", ".X", ".X", "x." } },
}

-- WEAPONS ---------------------------------------------------------------------------------
-- Held weapons per frame, in sprite pixels at rest (the pose's hands grip them).

local BLADE: { [string]: Stamp } = {
	-- straight up from the lifted fists, guard just above them
	up = { x = 13, y = 0, rows = { ".k.", "kAk", "kak", "kak", "kak", "kak", "kgg" } },
	-- cutting down and forward from the hands
	fwd = { x = 12, y = 12, rows = { ".k..", ".gk.", ".kak", "..ka", "..kA", "...k" } },
	-- swung through, pointing at the ground
	low = { x = 13, y = 15, rows = { ".gk", "kak", "kak", "kAk", ".k." } },
}

local STAFF: { [string]: Stamp } = {
	rest = {
		x = 13,
		y = 2,
		rows = {
			".g.",
			"gGg",
			".n.",
			".n.",
			".n.",
			".n.",
			".n.",
			".n.",
			".n.",
			".n.",
			".n.",
			".n.",
			".n.",
			".n.",
			".n.",
			".n.",
			".n.",
		},
	},
	up = { x = 13, y = 0, rows = { ".g.", "gGg", ".g.", ".n.", ".n.", ".n.", ".n." } },
	fwd = { x = 6, y = 12, rows = { ".........g", "nnnnnnnngG", ".........g" } },
	low = { x = 13, y = 15, rows = { "n..", ".n.", ".gg", ".gG" } },
}

-- A D-shaped bow: limbs "b", string "y", a star "G" on the top tip; arrows are wood "n".
local BOW: { [string]: Stamp } = {
	-- carried in the near hand, string facing forward
	rest = {
		x = 13,
		y = 8,
		rows = { "..G", ".kb", ".by", "b.y", "b.y", "b.y", "b.y", "b.y", ".by", ".kb" },
	},
	-- drawn: the arrow along the arm, the string pulled back past the shoulder
	draw = {
		x = 9,
		y = 7,
		rows = {
			".....G.",
			".....bk",
			"....y.b",
			"...y..b",
			"nnnnnnG",
			"......b",
			"......b",
			"...y..b",
			"....y.b",
			".....bk",
			".....k.",
		},
	},
	-- loosed: the string snaps straight, the arrow is gone
	loose = {
		x = 14,
		y = 7,
		rows = { "G.", "bk", "yb", "yb", "yb", ".b", ".b", "yb", "yb", "bk", "k." },
	},
	lower = {
		x = 13,
		y = 9,
		rows = { "..G", ".kb", ".by", "b.y", "b.y", "b.y", "b.y", "b.y", ".by", ".kb" },
	},
}

-- POSES -----------------------------------------------------------------------------------

type Variant = { upper: string?, arms: string?, weapon: string?, fx: string? }
type Pose = {
	upper: string,
	legs: string,
	dx: number?, -- head and upper body offset
	dy: number?,
	arms: string?,
	weapon: string?, -- frame of the held weapon
	fx: string?,
	-- replacements when the Sorcerer holds a bow or a staff ("" clears a field)
	bow: Variant?,
	staff: Variant?,
}

local IDLE: { Pose } = {
	{ upper = "idle", legs = "stand", weapon = "rest" },
	{ upper = "idle", legs = "stand", dy = 1, weapon = "rest" },
}

local ATTACKS: { [string]: { Pose } } = {
	Punch = {
		{ upper = "cock", legs = "brace", dy = 1, fx = "charge" },
		{ upper = "thrust", legs = "lunge", fx = "impact" },
		{ upper = "low", legs = "brace", fx = "burst" },
	},
	Cast = {
		{ upper = "gather", legs = "stand", fx = "spark" },
		{ upper = "raise", legs = "stand", arms = "raise", fx = "orb" },
		{ upper = "thrust", legs = "lunge", fx = "release" },
	},
	Slash = {
		{ upper = "raise", legs = "brace", dy = 1, arms = "lift", weapon = "up" },
		{ upper = "cut", legs = "lunge", weapon = "fwd", fx = "swish", staff = { upper = "grip" } },
		{ upper = "low", legs = "lunge", weapon = "low" },
	},
	Shoot = {
		{
			upper = "cock",
			legs = "brace",
			dy = 1,
			fx = "needles",
			bow = { upper = "aim", weapon = "draw", fx = "" },
		},
		{ upper = "thrust", legs = "brace", fx = "needle", bow = { weapon = "loose", fx = "" } },
		{ upper = "low", legs = "stand", weapon = "lower" },
	},
}

-- LOOK -> PALETTE -------------------------------------------------------------------------

local function has(look: { [string]: any }, accessory: string): boolean
	return table.find(look.accessories or {}, accessory) ~= nil
end

-- Pale skin is Peach with a Sand shade (as in the approved mock), not the paper-like Cream.
local function skinOf(c: Color3?): Color3
	local s = Parts.snap(c, Palette.Peach)
	if Parts.same(s, Palette.Cream) then
		return Palette.Peach
	end
	return s
end

-- Snaps a colour that must stand out from the skin: when it lands on the skin's ramp, its
-- saturation is pushed and it is snapped again (pink hair stays pink instead of turning Peach).
local function contrastSnap(c: Color3?, skin: Color3, fallback: Color3): Color3
	local s = Parts.snap(c, fallback)
	if c and (s == skin or s == Parts.darker(skin) or s == Parts.lighter(skin)) then
		local hue, sat, val = c:ToHSV()
		local boosted = Parts.snap(Color3.fromHSV(hue, math.min(1, sat * 1.6 + 0.1), val), fallback)
		if boosted ~= skin and boosted ~= Parts.darker(skin) then
			return boosted
		end
		return Parts.darker(Parts.darker(skin))
	end
	return s
end

-- Near-black hair: its darker step is the Ink outline, so it shades with itself instead.
local function isDarkHair(c: Color3): boolean
	return Parts.same(c, Palette.Night) or Parts.same(c, Palette.DarkBrown)
end

local function lookPalette(look: { [string]: any }, techColor: Color3): { [string]: Color3 }
	local skin = skinOf(look.skin)
	local hair = contrastSnap(look.hair, skin, Palette.Brown)
	local hairShade = if isDarkHair(hair) then hair else Parts.darker(hair)
	local hairLight = Parts.lighter(hair)
	if Parts.same(hairLight, Palette.Peach) or Parts.same(hairLight, skin) then
		hairLight = Palette.White
	end
	local outfit = Parts.hueSnap(look.outfit, Palette.Night)
	local trim = Parts.accent(look.trim, skin, Palette.Red)
	local pants = if look.pants and Parts.isVivid(look.pants)
		then Parts.accent(look.pants, skin, Palette.Night)
		else Parts.snap(look.pants, Palette.Night)
	if Parts.same(pants, trim) then
		pants = Parts.darker(pants) -- keep the trim belt apart from the legs
	end
	local eyes = Parts.accent(look.eyes, skin, Palette.Ink)
	local glow = Parts.accent(techColor, skin, Palette.White)
	local coat = Parts.darker(outfit)
	if coat == Palette.Ink then
		coat = Parts.lighter(outfit)
	end
	-- a scarf in the hair's colour would read as hair down to the shoulders
	local scarf = trim
	if Parts.same(trim, hair) or Parts.same(trim, hairShade) or Parts.same(trim, hairLight) then
		scarf = Parts.darker(trim)
	end
	local orbs = Parts.accent(look.aura or look.trim or techColor, skin, glow)
	return {
		k = Palette.Ink,
		h = hair,
		H = hairShade,
		L = hairLight,
		z = if look.hairStreak then Palette.nearest(look.hairStreak) else hair,
		s = skin,
		S = Parts.darker(skin),
		e = eyes,
		o = outfit,
		O = Parts.darker(outfit),
		t = trim,
		T = Parts.darker(trim),
		p = pants,
		j = skin,
		x = glow,
		X = Parts.glowLight(glow, skin),
		c = coat,
		f = scarf,
		F = Parts.darker(scarf),
		u = orbs,
		U = Parts.glowLight(orbs, skin),
		V = Parts.darker(orbs),
		w = Palette.White,
		g = Palette.Amber,
		G = Palette.Yellow,
		m = Palette.Slate,
		n = Palette.Brown,
		a = Palette.Mist,
		A = Palette.White,
		v = Palette.Dusk,
		q = Palette.White,
		r = Palette.Red,
		b = Palette.Plum,
		y = trim,
	}
end

-- ACCESSORIES -----------------------------------------------------------------------------
-- Each draws at rest coordinates shifted by the pose's offset, in one of four layers: "back"
-- (before the body), "body" (after the body, before the head), "head" (right after the head,
-- before raised arms) or "front" (after everything but the weapon and glow).

type Ctx = {
	g: Grid,
	look: { [string]: any },
	dx: number,
	dy: number,
	frame: number,
	attacking: boolean,
}

local function at(ctx: Ctx, rows: Rows, x: number, y: number)
	Parts.stamp(ctx.g, rows, x + ctx.dx, y + ctx.dy)
end

-- Stamps only onto empty pixels (hangs behind what is already drawn).
local function under(ctx: Ctx, rows: Rows, x: number, y: number)
	Parts.stampUnder(ctx.g, rows, x + ctx.dx, y + ctx.dy)
end

-- Stamps over everything except the given keys (hands, sleeves and legs stay on top).
local function over(ctx: Ctx, rows: Rows, x: number, y: number, keep: { [string]: boolean })
	for r, row in rows do
		for c = 1, #row do
			local ch = string.sub(row, c, c)
			local px, py = x + ctx.dx + c - 1, y + ctx.dy + r - 1
			if ch ~= "." and not keep[Parts.get(ctx.g, px, py)] then
				Parts.put(ctx.g, px, py, ch)
			end
		end
	end
end

local BODY_KEYS = { j = true, o = true, O = true, t = true, p = true, m = true }
local HAIR_KEYS = { h = true, H = true, L = true, z = true }

local ACCESSORIES: { [string]: { [string]: (Ctx) -> () } } = {
	Hood = {
		-- the hood bunched behind the head, its rim across the shoulders
		body = function(ctx)
			at(ctx, { "..kk", ".kcc", ".kcccccccccck", ".kk" }, 0, 9)
		end,
	},
	Talismans = {
		-- paper tags with a red seal: one floating by the face, one at the back of the hip
		front = function(ctx)
			local bob = ctx.frame % 2
			at(ctx, { ".kk.", "kqqk", "krrk", "kqqk", ".kk." }, 12, -bob)
			over(ctx, { "kk.", "qqk", "rrk", "qqk", "kk." }, 0, 11 + bob, BODY_KEYS)
		end,
	},
	Headband = {
		head = function(ctx)
			-- the band runs across the forehead row wherever there is hair, knot and tails behind
			local y = 5 + ctx.dy
			for x = 0, W - 1 do
				if HAIR_KEYS[Parts.get(ctx.g, x, y)] then
					Parts.put(ctx.g, x, y, "t")
				end
			end
			over(ctx, { ".kk", "ktt", "kTk", "kT.", ".k." }, 0, 4, HAIR_KEYS)
		end,
	},
	Scarf = {
		body = function(ctx)
			at(ctx, { "ffffffffk", "FFFFFFFF" }, 4, 11)
			-- the tail streams back, then hangs (it never covers a hand or sleeve)
			if ctx.frame % 2 == 1 then
				over(ctx, { ".kk.", "kfff", "kFFk", ".kk." }, 0, 10, BODY_KEYS)
			else
				over(ctx, { "..kk", ".kff", "kfFk", "kFk.", ".k.." }, 0, 10, BODY_KEYS)
			end
		end,
	},
	Gauntlets = {}, -- the hands turn to stone (see compose)
	Sash = {
		-- a knot on the belt and two tails hanging beside the leg (never over it)
		front = function(ctx)
			at(ctx, { "kT" }, 2, 15)
			under(ctx, { "ktt", "ktT", ".kk" }, 1, 16)
		end,
	},
	BellStaff = {
		back = function(ctx)
			if not ctx.attacking then
				at(ctx, STAFF.rest.rows, STAFF.rest.x, STAFF.rest.y)
			end
		end,
	},
	Orbs = {
		-- two floating orbs (plus shapes, light core), bobbing against the body
		front = function(ctx)
			local up = ctx.frame % 2
			Parts.stamp(ctx.g, { ".u.", "uUu", ".u." }, 13, up)
			Parts.stamp(ctx.g, { ".u.", "uUu", ".u." }, 0, 12 - up)
		end,
	},
	KatanaBack = {
		-- worn across the back: the hilt over the head's back, the scabbard tip behind the hip
		back = function(ctx)
			if not ctx.attacking then
				at(ctx, { "kk..", "ktk.", ".ktk", "..gg" }, 0, 0)
			end
			at(ctx, { ".kv", "kvk", "kvk", ".k." }, 0, 15)
		end,
	},
	StarBow = {
		front = function(ctx)
			if not ctx.attacking then
				at(ctx, BOW.rest.rows, BOW.rest.x, BOW.rest.y)
			end
		end,
	},
	Haori = {
		-- a long open coat: the back of the jacket and the shoulders, a skirt with a trim hem
		body = function(ctx)
			local g, dx, dy = ctx.g, ctx.dx, ctx.dy
			for y = 12, 14 do
				for x = 3, 7 do
					local ch = Parts.get(g, x + dx, y + dy)
					if ch == "o" or ch == "O" then
						Parts.put(g, x + dx, y + dy, "c")
					end
				end
			end
			if Parts.get(g, 3 + dx, 12 + dy) == "k" then
				at(ctx, { ".k", "kc" }, 2, 11)
			end
			if Parts.get(g, 12 + dx, 12 + dy) == "k" then
				at(ctx, { "k.", "ck" }, 12, 11)
			end
			Parts.stamp(g, { "..kccccccccck...", "..ktttttttttk..." }, 0, 16)
			for x = 3, 11 do
				if Parts.get(g, x, 18) == "." then
					Parts.put(g, x, 18, "k")
				end
			end
		end,
	},
	KatanaHip = {
		-- at the hip pointing forward: hilt over the belt, scabbard out in front of the coat
		front = function(ctx)
			if not ctx.attacking then
				at(ctx, { "t.", ".t" }, 10, 13)
			end
			at(ctx, { "gk..", "kvk.", ".kvk", "..kv", "...k" }, 12, 15)
		end,
	},
	FoxMaskSide = {
		-- a white fox mask worn on the side of the head, eye markings in the trim colour
		head = function(ctx)
			at(ctx, { ".k.k.", "kwkwk", "kwwwk", "ktwtk", ".kwk.", "..k.." }, 1, 2)
		end,
	},
	Halo = {
		-- a fractured ring tilted behind the head (its front half hidden by the head)
		back = function(ctx)
			at(ctx, {
				"....uuu.uuuu....",
				"..uu........uu..",
				".u............u.",
				".u............u.",
				"..............u.",
			}, 0, 0)
		end,
	},
}

-- Special auras from the look, drawn behind everything in sprite pixels (2 alternating frames):
-- flame embers rising at the sides, or a void swirl around the feet.
local AURAS: { [string]: { Rows } } = {
	flame = {
		{ "", "", "...............X", "", "", "x", "", "", "", "", "...............x", "", "", "X" },
		{ "", "...............x", "", "", "X", "", "", "", "", "...............X", "", "", "x" },
	},
	void = {
		{
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"...............u",
			"",
			"",
			"",
			"",
			"u",
			"",
			"",
			"",
			"V..............V",
			".VV..........VV.",
		},
		{
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"...............u",
			"",
			"",
			"",
			"",
			"u",
			"",
			"",
			"",
			"",
			"",
			".V............V.",
			"VV............VV",
		},
	},
}

-- COMPOSE ---------------------------------------------------------------------------------

local function weaponFor(look: { [string]: any }, style: string): string?
	if has(look, "BellStaff") then
		return "staff"
	elseif has(look, "StarBow") then
		return "bow"
	elseif style == "Slash" then
		return if has(look, "KatanaBack") or has(look, "KatanaHip") then "katana" else "energy"
	end
	return nil
end

local function stampWeapon(ctx: Ctx, kind: string?, frame: string?)
	if not kind or not frame then
		return
	end
	local set = if kind == "staff" then STAFF elseif kind == "bow" then BOW else BLADE
	local w = set[frame]
	if not w or frame == "rest" then
		return -- a carried staff or bow is drawn by its accessory
	end
	local rows = w.rows
	if kind == "energy" then
		-- a blade of pure technique colour
		local out = table.create(#rows)
		for i, row in rows do
			out[i] = string.gsub(string.gsub(string.gsub(row, "a", "x"), "A", "X"), "[gv]", "x")
		end
		rows = out
	end
	at(ctx, rows, w.x, w.y)
end

local function pick(variant: Variant?, field: string, default: string?): string?
	local v = variant and (variant :: any)[field]
	if v == "" then
		return nil
	end
	return v or default
end

local function compose(
	look: { [string]: any },
	style: string,
	pose: Pose,
	frame: number,
	attacking: boolean
): Grid
	local g = Parts.grid(W, H)
	local hairStyle = look.hairStyle or "Short"
	local head = HEADS[hairStyle] or HEADS.Short
	local dx, dy = pose.dx or 0, pose.dy or 0
	local kind = weaponFor(look, style)
	local variant: Variant? = if kind == "bow" then pose.bow elseif kind == "staff" then pose.staff else nil
	local upper = pick(variant, "upper", pose.upper) or "idle"
	local armsName = pick(variant, "arms", pose.arms)
	local weapon = pick(variant, "weapon", pose.weapon)
	local fxName = pick(variant, "fx", pose.fx)
	local ctx: Ctx = {
		g = g,
		look = look,
		dx = dx,
		dy = dy,
		frame = frame,
		attacking = attacking,
	}
	local accessories = look.accessories or {}
	local function layer(name: string)
		for _, a in accessories do
			local acc = ACCESSORIES[a]
			local fn = acc and acc[name]
			if fn then
				fn(ctx)
			end
		end
	end

	layer("back")
	local aura = (look.flameAura and AURAS.flame) or (look.voidAura and AURAS.void)
	if aura then
		Parts.stamp(g, aura[(frame - 1) % 2 + 1], 0, 0)
	end
	local back = HAIR_BACK[hairStyle]
	if back then
		Parts.stamp(g, back.rows, dx, back.y + dy)
	end
	Parts.stamp(g, LEGS[pose.legs], 0, 16)
	Parts.stamp(g, UPPER[upper], dx, 11 + dy)
	layer("body")
	Parts.stamp(g, head, dx, dy)
	layer("head")
	local arms = armsName and ARMS[armsName]
	if arms then
		Parts.stamp(g, arms.rows, arms.x + dx, arms.y + dy)
	end
	layer("front")
	stampWeapon(ctx, kind, weapon)
	if has(look, "Gauntlets") then
		Parts.swap(g, "j", "m")
	end
	local fx = fxName and FX[fxName]
	if fx then
		local rows = fx.rows
		if has(look, "Talismans") then
			-- the paper seal technique throws talismans: paper and seal instead of a glow
			local out = table.create(#rows)
			for i, row in rows do
				out[i] = string.gsub(string.gsub(row, "x", "q"), "X", "r")
			end
			rows = out
		end
		Parts.stamp(g, rows, fx.x + dx, fx.y + dy)
	end
	return g
end

local GENERIC_LOOK = {
	skin = Color3.fromRGB(240, 206, 178),
	hair = Color3.fromRGB(60, 50, 44),
	hairStyle = "Short",
	outfit = Color3.fromRGB(36, 38, 56),
	trim = Color3.fromRGB(150, 160, 190),
	pants = Color3.fromRGB(30, 30, 40),
	eyes = Color3.fromRGB(70, 46, 36),
	accessories = {},
}
local GENERIC_COLOR = Color3.fromRGB(150, 160, 190)

export type SorcererArt = { idle: Def, attack: Def, color: Color3 }
local sorcererCache: { [string]: SorcererArt } = {}

-- Idle (2 frames) and attack (3 frames: wind-up, strike, follow-through) for a Sorcerer id.
function Characters.sorcerer(id: string): SorcererArt
	local cached = sorcererCache[id]
	if cached then
		return cached
	end
	local def = Sorcerers.get(id)
	local look = if def then def.look else GENERIC_LOOK
	local style = if def then def.style else "Punch"
	local techColor = if def then def.color else GENERIC_COLOR
	local palette = lookPalette(look, techColor)
	local idleGrids = {}
	for i, pose in IDLE do
		idleGrids[i] = compose(look, style, pose, i, false)
	end
	local attackGrids = {}
	for i, pose in ATTACKS[style] or ATTACKS.Punch do
		attackGrids[i] = compose(look, style, pose, i, true)
	end
	local result = {
		idle = Parts.define(id .. "Idle", idleGrids, palette, ANCHOR),
		attack = Parts.define(id .. "Attack", attackGrids, palette, ANCHOR),
		color = palette.x, -- the glow drawn on the strike, so orbs and effects match it
	}
	sorcererCache[id] = result
	return result
end

-- PORTRAITS ------------------------------------------------------------------------------
-- 24x24 head and shoulders facing front: the face and jacket, then the hair style and the
-- accessories that show from the front. Same keys as the Sorcerer frames, plus "M" mouth and
-- "R" the lit top of the shoulders (so dark jackets still read on a dark panel).

local PORTRAIT_BASE: Rows = {
	"........................",
	"........................",
	"........................",
	"......kkkkkkkkkkkk......",
	".....kssssssssssssk.....",
	"....kssssssssssssssk....",
	"....kssssssssssssssk....",
	"....kssssssssssssssk....",
	"....kssssssssssssssk....",
	"....kssssssssssssssk....",
	"....kssssssssssssssk....",
	"....ksskkssssssskkssk...",
	"....ksseessssssseessk...",
	"....ksseessssssseessk...",
	"....kssssssssssssssk....",
	"....kssssssMMsssssssk...",
	".....kssssssssssssk.....",
	"......kkSSSSSSSSkk......",
	"........kkSSSSkk........",
	"..kkkkkkkkottokkkkkkkk..",
	".kORRRRRRRRttRRRRRRRRk..",
	".kOoooooooottoooooooook.",
	".kOoooooooottoooooooook.",
	".kOoooooooottoooooooook.",
}

local PORTRAIT_HAIR: { [string]: { back: { y: number, rows: Rows }?, front: Rows } } = {
	Short = {
		front = {
			"........................",
			"........................",
			"......kkkkkkkkkkkk......",
			"....kkhhhhhhhhhhhhkk....",
			"...khhhhhhhhhhhhhhhLk...",
			"..khhhhhhhhhhhhhhhhhLk..",
			"..kHhzhhhhhhhhhhhhhhhk..",
			"..kHhzhhhhhhhhhhhhhhhk..",
			"..kHhhhhhhhhhhhhhhhhhk..",
			"..kHhhhshhhhhhhhshhhhk..",
			"..kHhssssshhhhsssssHhk..",
			"..kHk..............kHk..",
			"..kHk..............kHk..",
			"...k................k...",
		},
	},
	Spiky = {
		front = {
			"........................",
			"....k.kk.k.kk.k.kk.k....",
			"...khkhhkhkhhkhkhhkhk...",
			"..khhhhhhhhhhhhhhhhhhk..",
			".khhhhhhhhhhhhhhhhhhhLk.",
			"kHhhhhhhhhhhhhhhhhhhhLk.",
			".kHhzhhhhhhhhhhhhhhhhhk.",
			"..kHzhhhhhhhhhhhhhhhhk..",
			"..kHhhhhhhhhhhhhhhhhhk..",
			"..kHhhhshhhhhhhhshhhhk..",
			"..kHhssssshhhhsssssHhk..",
			"..kHk..............kHk..",
			"...k................k...",
		},
	},
	Bob = {
		front = {
			"........................",
			"........................",
			"......kkkkkkkkkkkk......",
			"....kkhhhhhhhhhhhhkk....",
			"...khhhhhhhhhhhhhhhLk...",
			"..khhhhhhhhhhhhhhhhhLk..",
			".kHhzhhhhhhhhhhhhhhhhhk.",
			".kHhzhhhhhhhhhhhhhhhhhk.",
			".kHhhhhhhhhhhhhhhhhhhhk.",
			".kHhhhhhhhhhhhhhhhhhhhk.",
			".kHhhk.............kHhk.",
			".kHhk..............kHhk.",
			".kHhk..............kHhk.",
			".kHhk..............kHhk.",
			".kHhk..............kHhk.",
			".kHhk..............kHhk.",
			".kkkk..............kkkk.",
		},
	},
	Long = {
		back = {
			y = 16,
			rows = {
				".kHhk..............kHhk.",
				".kHhk..............kHhk.",
				".kHhk..............kHhk.",
				".kHhk..............kHhk.",
				".kHhk..............kHhk.",
				".kHhk..............kHhk.",
				".kHhk..............kHhk.",
				".kHhk..............kHhk.",
			},
		},
		front = {
			"........................",
			"........................",
			"......kkkkkkkkkkkk......",
			"....kkhhhhhhhhhhhhkk....",
			"...khhhhhhhhhhhhhhhLk...",
			"..khhhhhhhhhhhhhhhhhLk..",
			".kHhzhhhhhhhhhhhhhhhhhk.",
			".kHhzhhhhhhhhhhhhhhhhhk.",
			".kHhhhhhhhhhhhhhhhhhhhk.",
			".kHhhhhshhhhhhhhshhhhhk.",
			".kHhhssssshhhhssssshhhk.",
			".kHhk..............kHhk.",
			".kHhk..............kHhk.",
			".kHhk..............kHhk.",
			".kHhk..............kHhk.",
			".kHhk..............kHhk.",
		},
	},
	Ponytail = {
		back = {
			y = 14,
			rows = {
				"khk",
				"khk",
				"khk",
				"kk",
			},
		},
		front = {
			"........................",
			"........................",
			"......kkkkkkkkkkkk......",
			"....kkhhhhhhhhhhhhkk....",
			"...khhhhhhhhhhhhhhhLk...",
			"..khhhhhhhhhhhhhhhhhLk..",
			"kkkHhzhhhhhhhhhhhhhhhk..",
			"kttkhzhhhhhhhhhhhhhhhk..",
			"kttkhhhhhhhhhhhhhhhhhk..",
			"kkHhhhhshhhhhhhhshhhhk..",
			"khkHhssssshhhhsssssHhk..",
			"khkHk..............kHk..",
			"khkHk..............kHk..",
			"khkk................k...",
		},
	},
	Swept = {
		front = {
			"........................",
			"........................",
			"......kkkkkkkkkkkk......",
			"....kkhhhhhhhhhhhhkk....",
			"...khhhhhhhhhhhhhhhLk...",
			"..khhhhhhhhhhhhhhhhhLk..",
			"..kHhzhhhhhhhhhhhhhhhk..",
			"..kHhzhhhhhhhhzzhhhhhk..",
			"..kHhhhhhhhhhhhzzhhhhk..",
			"..kHhhhhhhhhhhhhzzhhhk..",
			"..kHhssssshhhhhhhzhhhk..",
			"..kHk.........hhhhhhHk..",
			"..kHk...........hhhhHk..",
			"...k..............kkk...",
		},
	},
}

local PORTRAIT_ACCESSORIES: { [string]: { back: { y: number, rows: Rows }?, front: { y: number, rows: Rows }? } } =
	{
		Hood = {
			back = {
				y = 16,
				rows = {
					"..kkk..............kkk..",
					".kcccck..........kcccck.",
					".kccccckkk....kkkccccck.",
				},
			},
			front = {
				y = 20,
				rows = {
					"........t......t........",
					"........t......t........",
				},
			},
		},
		Talismans = {
			front = {
				y = 9,
				rows = {
					".kk.",
					"kqqk",
					"krrk",
					"kqqk",
					".kk.",
					"",
					"",
					"....................kk.",
					"...................kqqk",
					"...................krrk",
					"...................kqqk",
				},
			},
		},
		Headband = {
			front = {
				y = 6,
				rows = {
					"..kttttttttttttttttttk..",
					".tT",
					"tT",
				},
			},
		},
		Scarf = {
			front = {
				y = 18,
				rows = {
					"......kffffffffffk......",
					".....kffffffffffffk.....",
					"......kkkkkFFkkkkk......",
					"..........kFFk..........",
					"..........kFkk..........",
				},
			},
		},
		BellStaff = {
			back = {
				y = 1,
				rows = {
					"....................kgk.",
					"...................kgGgk",
					"....................kgk.",
					".....................n",
					".....................n",
					".....................n",
					".....................n",
					".....................n",
					".....................n",
					".....................n",
					".....................n",
					".....................n",
					".....................n",
					".....................n",
					".....................n",
					".....................n",
					".....................n",
					".....................n",
				},
			},
		},
		Orbs = {
			front = {
				y = 0,
				rows = {
					".u...................u..",
					"uUu.................uUu.",
					".u...................u..",
				},
			},
		},
		KatanaBack = {
			front = {
				y = 13,
				rows = {
					"......................kk",
					".....................ktk",
					".....................ktk",
					"....................kggk",
					"....................kvk.",
					"...................kvk..",
				},
			},
		},
		StarBow = {
			back = {
				y = 0,
				rows = {
					".....................kGk",
					"....................kGGG",
					".....................kbk",
					"......................kb",
					"......................kb",
					"......................kb",
					"......................kb",
					"......................kb",
					"......................kb",
					"......................kb",
					"......................kb",
					"......................kb",
					".....................kbk",
				},
			},
		},
		Haori = {
			front = {
				y = 19,
				rows = {
					"..kkkkkkk......kkkkkkk..",
					"..kccccccct..tccccccck..",
					".kccccccccct.tcccccccck.",
					".kccccccccct.tcccccccck.",
					".kccccccccct.tcccccccck.",
				},
			},
		},
		FoxMaskSide = {
			front = {
				y = 4,
				rows = {
					".k.k.",
					"kwkwk",
					"kwwwk",
					"ktwtk",
					"kwwwk",
					".kwk.",
					"..k..",
				},
			},
		},
		Halo = {
			back = {
				y = 0,
				rows = {
					".....uuuuuu..uuuuuu.....",
					"...uu..............uu...",
					"..u..................u..",
				},
			},
		},
	}

local portraitCache: { [string]: Def } = {}

-- 24x24 head and shoulders facing front, 1 frame.
function Characters.portrait(id: string): Def
	local cached = portraitCache[id]
	if cached then
		return cached
	end
	local def = Sorcerers.get(id)
	local look = if def then def.look else GENERIC_LOOK
	local palette = lookPalette(look, if def then def.color else GENERIC_COLOR)
	palette.M = Palette.Rust
	palette.R = Parts.lighter(palette.o)
	local g = Parts.grid(24, 24)
	local hair = PORTRAIT_HAIR[look.hairStyle or "Short"] or PORTRAIT_HAIR.Short
	local accessories = look.accessories or {}
	for _, a in accessories do
		local acc = PORTRAIT_ACCESSORIES[a]
		if acc and acc.back then
			Parts.stamp(g, acc.back.rows, 0, acc.back.y)
		end
	end
	if hair.back then
		Parts.stamp(g, hair.back.rows, 0, hair.back.y)
	end
	Parts.stamp(g, PORTRAIT_BASE, 0, 0)
	Parts.stamp(g, hair.front, 0, 0)
	for _, a in accessories do
		local acc = PORTRAIT_ACCESSORIES[a]
		if acc and acc.front then
			Parts.stamp(g, acc.front.rows, 0, acc.front.y)
		end
	end
	local result = Parts.define(id .. "Portrait", { g }, palette, { 12, 24 })
	portraitCache[id] = result
	return result
end

-- COMPANIONS -----------------------------------------------------------------------------
-- Spirits that sit or float beside their Sorcerer (colours from the old 3D models, snapped;
-- neon parts keep their hue). Light comes from the top right. 2 idle frames, at most 14x14,
-- anchor bottom middle.

local rgb = Color3.fromRGB
local snap = Palette.nearest
local vivid = Parts.vivid

local COMPANIONS: { [string]: { palette: { [string]: Color3 }, frames: { Rows } } } = {
	-- a squat toad in a straw hat; it puffs its throat
	Toad = {
		palette = {
			k = Palette.Ink,
			g = snap(rgb(92, 116, 70)),
			G = Palette.Leaf,
			d = Palette.Pine,
			c = snap(rgb(196, 186, 140)),
			y = snap(rgb(250, 210, 90)),
			a = snap(rgb(186, 150, 92)),
			A = Palette.Bark,
		},
		frames = {
			{
				"..............",
				"....kkkkk.....",
				"...kaaaaak....",
				".kkAAAAAAAkk..",
				"kaaaaaaaaaaak.",
				".kkggggGykykk.",
				".kgggggGyky.k.",
				"kdggggggggGGgk",
				"kdgkkkkkkkkkgk",
				"kdgccccccccggk",
				".kdgcccccdggk.",
				".kdgkkgggkgdk.",
				"..kk..kkk.kk..",
			},
			{
				"..............",
				"..............",
				"....kkkkk.....",
				"...kaaaaak....",
				".kkAAAAAAAkk..",
				"kaaaaaaaaaaak.",
				".kggggGgkkkk..",
				"kdgggggGgGGggk",
				"kdgkkkkkkkkkgk",
				"kdgcccccccccgk",
				"kdgcccccccccgk",
				".kdgkkgggkgdk.",
				"..kk..kkk.kk..",
			},
		},
	},
	-- a soft moth with glowing wings; the wings beat
	Moth = {
		palette = {
			k = Palette.Ink,
			b = snap(rgb(70, 74, 104)),
			a = vivid(rgb(170, 220, 255)),
			w = snap(rgb(220, 250, 255)),
		},
		frames = {
			{
				"...a......a...",
				"....k....k....",
				"kk...kbbk...kk",
				"kaak.kwwk.kaak",
				"kaaakkbbkkaaak",
				"kaaaakbbkaaaak",
				".kaaakbbkaaak.",
				"..kkkkbbkkkk..",
				".kaaakbbkaaak.",
				".kaak.kk.kaak.",
				"..kk......kk..",
				"..............",
			},
			{
				"..............",
				"...a......a...",
				"....k....k....",
				".....kbbk.....",
				"..kkkkwwkkkk..",
				".kaaakbbkaaak.",
				"kaaaakbbkaaaak",
				"kaaakkbbkkaaak",
				".kkkakbbkakkk.",
				"...kakkkkak...",
				"....k....k....",
				"..............",
			},
		},
	},
	-- a floating horned mask over a tattered cloak; it bobs
	Mask = {
		palette = {
			k = Palette.Ink,
			w = snap(rgb(238, 232, 222)),
			r = snap(rgb(196, 40, 60)),
			e = snap(rgb(255, 80, 110)),
			c = Palette.Night,
		},
		frames = {
			{
				".k........k.",
				"kwk......kwk",
				"kwwkkkkkkwwk",
				"kwwwwwwwwwwk",
				"kwrrwwwwrrwk",
				"kwkekwwkekwk",
				"kwwwwwwwwwwk",
				"kwkkkkkkkkwk",
				"kwkwkkkkwkwk",
				".kkwwwwwwkk.",
				"..kkkkkkkk..",
				"..kccccccck.",
				"..kckcckck..",
				"...k.kk.k...",
			},
			{
				"............",
				".k........k.",
				"kwk......kwk",
				"kwwkkkkkkwwk",
				"kwwwwwwwwwwk",
				"kwrrwwwwrrwk",
				"kwkekwwkekwk",
				"kwwwwwwwwwwk",
				"kwkkkkkkkkwk",
				"kwkwkkkkwkwk",
				".kkwwwwwwkk.",
				"..kkkkkkkk..",
				".kccccccck..",
				"..kckkckk...",
			},
		},
	},
	-- a pale wolf with yellow lightning marks, standing; its tail wags
	Wolf = {
		palette = {
			k = Palette.Ink,
			f = snap(rgb(236, 232, 214)),
			F = Palette.Slate,
			y = snap(rgb(255, 214, 60)),
			e = vivid(rgb(120, 220, 255)),
		},
		frames = {
			{
				"........k.k...",
				".......kykyk..",
				".......kffffk.",
				".......kfefffk",
				".......kffffkk",
				"kk....kfffk...",
				"kyk..kffffk...",
				".kfkkfffffk...",
				"..kffyfffyfk..",
				"..kFFFFFFFFk..",
				"..kfk.kfk.kfk.",
				"..kkk.kkk.kkk.",
			},
			{
				"........k.k...",
				".......kykyk..",
				".......kffffk.",
				".......kfefffk",
				".......kffffkk",
				"......kfffk...",
				"kkk..kffffk...",
				"kyfkkfffffk...",
				".kkffyfffyfk..",
				"..kFFFFFFFFk..",
				"..kfk.kfk.kfk.",
				"..kkk.kkk.kkk.",
			},
		},
	},
	-- a coiled serpent: tapering coils with cracks of light, an S-curved neck and a horned
	-- wedge of a head flicking its tongue; it sways
	Serpent = {
		palette = {
			k = Palette.Ink,
			b = snap(rgb(48, 40, 62)),
			B = Palette.Steel,
			v = vivid(rgb(186, 90, 255)),
			h = snap(rgb(220, 210, 230)),
			e = Palette.Hot,
			r = Palette.Rose,
		},
		frames = {
			{
				"........h.h...",
				".......khkhk..",
				"......kBBBBBk.",
				"......kbbbebkr",
				".......kbbbkk.",
				"........kbbk..",
				".......kbbk...",
				"....kkkbbk....",
				"...kBBBBbbkk..",
				"..kbbvbbbbbBk.",
				"..kkkkkkkkbbk.",
				".kBBBBBBBBkbbk",
				"kbbbvbbbbvbbbk",
				".kkkkkkkkkkkk.",
			},
			{
				".......h.h....",
				"......khkhk...",
				".....kBBBBBk..",
				".....kbbbebk..",
				"......kbbbk...",
				".......kbbk...",
				"........kbbk..",
				"....kkkkbbk...",
				"...kBBBBbbkk..",
				"..kbbbbvbbbBk.",
				"..kkkkkkkkbbk.",
				".kBBBBBBBBkbbk",
				"kbbbbbvbbbbvbk",
				".kkkkkkkkkkkk.",
			},
		},
	},
}

local companionCache: { [string]: Def } = {}

-- A companion spirit (2 idle frames), or nil for an unknown name.
function Characters.companion(name: string): Def?
	local cached = companionCache[name]
	if cached then
		return cached
	end
	local spec = COMPANIONS[name]
	if not spec then
		return nil
	end
	local w, h = 0, #spec.frames[1]
	for _, row in spec.frames[1] do
		w = math.max(w, #row)
	end
	local grids = {}
	for i, rows in spec.frames do
		local g = Parts.grid(w, h)
		Parts.stamp(g, rows, 0, 0)
		grids[i] = g
	end
	local def = Parts.define(name, grids, spec.palette, { math.floor(w / 2), h })
	companionCache[name] = def
	return def
end

-- PLAYER ----------------------------------------------------------------------------------
-- The local player and other players: a plain T-shirt chibi in their avatar colours (snapped
-- into the palette like everything else), short hair, three directions with a 2-step walk.

local PLAYER_HEAD: { [string]: Rows } = {
	down = {
		"................",
		"................",
		"....kkkkkkkk....",
		"...khhhhhhhhk...",
		"..khhhhhhhhhhk..",
		"..kHhhhhhhhhHk..",
		"..kHhhhhhhhhHk..",
		"..kHhsshhsshHk..",
		"..khsksssskshk..",
		"..khsksssskshk..",
		"...kssssssssk...",
	},
	up = {
		"................",
		"................",
		"....kkkkkkkk....",
		"...khhhhhhhhk...",
		"..khhhhhhhhhhk..",
		"..kHhhhhhhhhHk..",
		"..kHhhhhhhhhHk..",
		"..kHhhhhhhhhHk..",
		"..kHHhhhhhhHHk..",
		"..kHHHhhhhHHHk..",
		"...kkHHHHHHkk...",
	},
	side = {
		"................",
		"................",
		"....kkkkkkkk....",
		"...khhhhhhhhk...",
		"..khhhhhhhhhhk..",
		"..kHhhhhhhhhhk..",
		"..kHhhhhhhhhhk..",
		"..kHhhhsshhssk..",
		"..kHhhSssskssk..",
		"..kHhhSssskssk..",
		"...kkkSsssssk...",
	},
}

local PLAYER_BODY: { [string]: { upper: Rows, legs: { Rows } } } = {
	down = {
		upper = {
			"....kkkkkkkk....",
			"..kkooooooookk..",
			".koOooooooooOok.",
			".ksOooooooooOsk.",
			".kskppppppppksk.",
		},
		legs = {
			{ "...kppppppppk...", "...kpppkkpppk...", "...kpppkkpppk...", "...kkkk..kkkk..." },
			{ "...kppppppppk...", "...kpppkkpppk...", "...kkkkkkpppk...", "...kkkk..kkkk..." },
			{ "...kppppppppk...", "...kpppkkpppk...", "...kpppkkkkkk...", "...kkkk..kkkk..." },
		},
	},
	up = {
		upper = {
			"....kkkkkkkk....",
			"..kkooooooookk..",
			".koOooooooooOok.",
			".ksOooooooooOsk.",
			".kskppppppppksk.",
		},
		legs = {
			{ "...kppppppppk...", "...kpppkkpppk...", "...kpppkkpppk...", "...kkkk..kkkk..." },
			{ "...kppppppppk...", "...kpppkkpppk...", "...kkkkkkpppk...", "...kkkk..kkkk..." },
			{ "...kppppppppk...", "...kpppkkpppk...", "...kpppkkkkkk...", "...kkkk..kkkk..." },
		},
	},
	side = {
		upper = {
			"....kkkkkkkk....",
			"...kOooooooook..",
			"...kOooooooook..",
			"...kOoooooosok..",
			"...kpppppppkk...",
		},
		-- stand, then the two strides; the far leg is the darker one
		legs = {
			{ "....kppppppk....", "....kPPkkppk....", "....kPPkkppk....", "....kkkk.kkkk..." },
			{ "....kppppppk....", "...kppk.kPPk....", "..kppk...kPPk...", "..kkkk...kkkkk.." },
			{ "....kppppppk....", "...kPPk.kppk....", "..kPPk...kppk...", "..kkkk...kkkkk.." },
		},
	},
}

-- Upper body offset per frame: down a pixel at rest and on the second stride, so walking
-- bobs once per step pair.
local PLAYER_BOB = { 1, 0, 1 }

local function playerDef(dir: string, palette: { [string]: Color3 }): Def
	local grids = {}
	local body = PLAYER_BODY[dir]
	for i = 1, 3 do
		local g = Parts.grid(W, H)
		local bob = PLAYER_BOB[i]
		Parts.stamp(g, body.legs[i], 0, 16)
		Parts.stamp(g, body.upper, 0, 11 + bob)
		Parts.stamp(g, PLAYER_HEAD[dir], 0, bob)
		grids[i] = g
	end
	return Parts.define("Player" .. dir, grids, palette, ANCHOR)
end

local function shadeOf(c: Color3): Color3
	local d = Parts.darker(c)
	return if d == Palette.Ink then c else d
end

-- Player sprites in avatar colours: { down, up, side }, 3 frames each (stand, walk A, walk B).
function Characters.player(colors: { skin: Color3, shirt: Color3, pants: Color3, hair: Color3 }): {
	down: Def,
	up: Def,
	side: Def,
}
	local skin = skinOf(colors.skin)
	local shirt = Parts.snap(colors.shirt, Palette.Sky)
	local pants = Parts.snap(colors.pants, Palette.Dusk)
	local hair = Parts.snap(colors.hair, Palette.Brown)
	local palette = {
		k = Palette.Ink,
		s = skin,
		S = Parts.darker(skin),
		o = shirt,
		O = shadeOf(shirt),
		p = pants,
		P = shadeOf(pants),
		h = hair,
		-- very dark hair would vanish into the outline: its side locks go one step lighter
		H = if isDarkHair(hair) then Parts.lighter(hair) else Parts.darker(hair),
	}
	return {
		down = playerDef("down", palette),
		up = playerDef("up", palette),
		side = playerDef("side", palette),
	}
end

-- CARRY -----------------------------------------------------------------------------------
-- The Orb Box a player carries over their head: a wooden crate full of glowing Cursed Orbs.

Characters.carry = Parts.define("Carry", {
	(function()
		local g = Parts.grid(12, 10)
		Parts.stamp(g, {
			"..x.....X...",
			".kkkkkkkkkk.",
			"kbvvXvvvvvbk",
			"kbvXvvvXvvbk",
			"kkkkkkkkkkkk",
			"kwwwwwwwwwwk",
			"kWwwwwwwwwWk",
			"kddddddddddk",
			"kWddddddddWk",
			".kkkkkkkkkk.",
		}, 0, 0)
		return g
	end)(),
	(function()
		local g = Parts.grid(12, 10)
		Parts.stamp(g, {
			"......x...X.",
			".kkkkkkkkkk.",
			"kbvvvvXvvvbk",
			"kbvvvvvvXvbk",
			"kkkkkkkkkkkk",
			"kwwwwwwwwwwk",
			"kWwwwwwwwwWk",
			"kddddddddddk",
			"kWddddddddWk",
			".kkkkkkkkkk.",
		}, 0, 0)
		return g
	end)(),
}, {
	k = Palette.Ink,
	b = Palette.Bark,
	v = Palette.Plum,
	x = Palette.Orchid,
	X = Palette.Rose,
	w = Palette.Bark,
	W = Palette.Amber,
	d = Palette.Brown,
}, { 6, 10 })

return Characters
