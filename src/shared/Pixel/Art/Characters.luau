--!strict
-- Pixel-art characters: chibi 16x20 people in a top-down 3/4 view with a 1px Ink outline, in
-- ENDESGA 32. Sorcerers are generated from their look in Config/Sorcerers (hair style, colours,
-- accessories, streak), never drawn per id: a head per hair style, a body per pose, then the
-- accessories and the technique glow. Characters face RIGHT; the renderer mirrors for left.
-- Also: companions, 24x24 portraits, the player (avatar colours) and the carried Orb Box.

local Palette = require(script.Parent.Parent.Palette)
local Sprite = require(script.Parent.Parent.Sprite)
local Parts = require(script.Parent.CharacterParts)
local Sorcerers = require(script.Parent.Parent.Parent.Config.Sorcerers)

type Grid = Parts.Grid
type Def = Sprite.Def
type Rows = { string }

local Characters = {}

Characters.Size = { w = 16, h = 20 }
local W, H = 16, 20
local ANCHOR = { 8, 20 }

-- Grid keys used by every Sorcerer frame (colours come from the look, see lookPalette):
--   k outline   h/H/L hair, shade, light   z hair streak   s/S skin, shade   e eyes
--   o/O outfit, shade   t/T trim, shade   p pants   j hands (stone for Gauntlets)
--   x/X technique colour, light   c haori coat   u orbs / halo   w white   g/G gold, light
--   m/M stone, shade   n staff wood   b bow   a/A blade, edge   v scabbard   q/r paper, seal

-- HEADS -----------------------------------------------------------------------------------
-- Rows y0..y11 at rest; the face is the same in every style.

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
	Spiky = {
		"................",
		"...kk...kk......",
		"..khhk.khhk.....",
		"..khhkkkhhkkkk..",
		".khhhhhhhhhhhLk.",
		"kHHhzhhhhhhhhk..",
		".kHhzhhhhhhhhk..",
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
		"..kHhhhhhhhzssk.",
		"..kHhhShhhhksk..",
		"..kHhhSshhsesk..",
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
-- Upper body rows y11..y15 (moves with the head) and legs y16..y19. The jacket is the outfit
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
		"...kOoootookk...",
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
	-- near arm raised (the hand is the "raise" arms stamp)
	raise = {
		"....kkkkkkkk....",
		"...kOoootook....",
		"..kjOoootook....",
		"..kjOoootook....",
		"...kttttttttk...",
	},
	-- both hands on a held weapon in front of the belly
	grip = {
		"....kkkkkkkk....",
		"...kOoootoook...",
		"...kOoojjoook...",
		"...kOoojjoook...",
		"...kttttttttk...",
	},
	-- hands low and forward (weapon swung through)
	low = {
		"....kkkkkkkk....",
		"...kOoootoook...",
		"..kjOoootoookk..",
		"..kjOoootooojjk.",
		"...kttttttttjjk.",
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

-- Arms drawn after the head (in front of the face): the near arm raised straight up.
local ARMS: { [string]: { x: number, y: number, rows: Rows } } = {
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
}

-- TECHNIQUE GLOW --------------------------------------------------------------------------
-- Stamps in the technique colour (x) and its light (X), in sprite pixels at rest.

local FX: { [string]: { x: number, y: number, rows: Rows } } = {
	charge = { x = 0, y = 12, rows = { "x..", "X..", "X..", "x.." } },
	impact = { x = 15, y = 11, rows = { "x", "X", "X", "x" } },
	burst = { x = 14, y = 10, rows = { "x.", "..", ".X", ".X", "..", "x." } },
	spark = { x = 15, y = 12, rows = { "x", "X", "X", "x" } },
	orb = { x = 12, y = 0, rows = { ".xx.", "xXXx", ".xx." } },
	release = { x = 15, y = 11, rows = { "x", "X", "X", "x" } },
	needle = { x = 15, y = 12, rows = { "X", "x" } },
	streak = { x = 12, y = 11, rows = { "xxxX" } },
	swish = { x = 11, y = 11, rows = { "xxxxx" } },
}

-- WEAPONS ---------------------------------------------------------------------------------
-- Held weapons per frame, in sprite pixels at rest (the pose's hands grip them).

local BLADE: { [string]: { x: number, y: number, rows: Rows } } = {
	up = { x = 13, y = 1, rows = { ".A", ".a", ".a", ".a", ".a", ".a", ".a", ".a", "gg", ".v" } },
	fwd = { x = 10, y = 13, rows = { "gaaaaA" } },
	low = { x = 14, y = 15, rows = { "v.", ".a", ".a", ".A" } },
}

local STAFF: { [string]: { x: number, y: number, rows: Rows } } = {
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
	up = {
		x = 13,
		y = 0,
		rows = { ".g.", "gGg", ".n.", ".n.", ".n.", ".n.", ".n.", ".n.", ".n.", ".n.", ".n.", ".n." },
	},
	fwd = { x = 6, y = 12, rows = { ".........g", "nnnnnnnngG", ".........g" } },
	low = { x = 13, y = 15, rows = { "n..", ".n.", ".gg", ".gG" } },
}

local BOW: { [string]: { x: number, y: number, rows: Rows } } = {
	rest = { x = 13, y = 10, rows = { "G.", "b.", "tb", "tb", "tb", "tb", "tb", "b." } },
	draw = { x = 14, y = 7, rows = { "G.", "b.", "tb", "tb", "tb", "tb", "tb", "tb", "tb", "b." } },
	loose = { x = 14, y = 7, rows = { "G.", "b.", "tb", "tb", "tb", "tb", "tb", "tb", "tb", "b." } },
	lower = { x = 14, y = 10, rows = { "G.", "b.", "tb", "tb", "tb", "tb", "tb", "b." } },
}

-- POSES -----------------------------------------------------------------------------------

type Pose = {
	upper: string,
	legs: string,
	dx: number?, -- head and upper body offset
	dy: number?,
	arms: string?,
	weapon: string?, -- frame of the held weapon
	fx: string?,
}

local IDLE: { Pose } = {
	{ upper = "idle", legs = "stand", weapon = "rest" },
	{ upper = "idle", legs = "stand", dy = 1, weapon = "rest" },
}

local ATTACKS: { [string]: { Pose } } = {
	Punch = {
		{ upper = "cock", legs = "brace", dy = 1, fx = "charge" },
		{ upper = "thrust", legs = "lunge", fx = "impact" },
		{ upper = "thrust", legs = "lunge", fx = "burst" },
	},
	Cast = {
		{ upper = "gather", legs = "stand", fx = "spark" },
		{ upper = "raise", legs = "stand", arms = "raise", fx = "orb" },
		{ upper = "thrust", legs = "lunge", fx = "release" },
	},
	Slash = {
		{ upper = "thrust", legs = "brace", dy = 1, weapon = "up" },
		{ upper = "grip", legs = "lunge", weapon = "fwd", fx = "swish" },
		{ upper = "low", legs = "lunge", weapon = "low" },
	},
	Shoot = {
		{ upper = "aim", legs = "brace", weapon = "draw", fx = "needle" },
		{ upper = "aim", legs = "brace", weapon = "loose", fx = "streak" },
		{ upper = "low", legs = "stand", weapon = "lower" },
	},
}

-- LOOK -> PALETTE -------------------------------------------------------------------------

local function has(look: { [string]: any }, accessory: string): boolean
	return table.find(look.accessories or {}, accessory) ~= nil
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

local function lookPalette(look: { [string]: any }, techColor: Color3): { [string]: Color3 }
	local skin = Parts.snap(look.skin, Palette.Peach)
	local hair = contrastSnap(look.hair, skin, Palette.Brown)
	local outfit = Parts.snap(look.outfit, Palette.Night)
	local trim = Parts.snap(look.trim, Palette.Red)
	local pants = Parts.snap(look.pants, Palette.Night)
	local eyes = if look.eyes then contrastSnap(look.eyes, skin, Palette.Ink) else Palette.Ink
	local tech = Palette.nearest(techColor)
	local coat = Parts.darker(outfit)
	if coat == Palette.Ink then
		coat = Parts.lighter(outfit)
	end
	return {
		k = Palette.Ink,
		h = hair,
		H = Parts.darker(hair),
		L = Parts.lighter(hair),
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
		x = tech,
		X = Parts.lighter(tech),
		c = coat,
		u = Palette.nearest(look.aura or look.trim or techColor),
		w = Palette.White,
		g = Palette.Amber,
		G = Palette.Yellow,
		m = Palette.Slate,
		M = Palette.Steel,
		n = Palette.Brown,
		b = Palette.nearest(Color3.fromRGB(60, 50, 90)),
		a = Palette.Mist,
		A = Palette.White,
		v = Palette.Dusk,
		q = Palette.Cream,
		r = Palette.Red,
	}
end

-- ACCESSORIES -----------------------------------------------------------------------------
-- Each draws at rest coordinates shifted by (dx, dy) (the pose's head/upper offset). `layer`
-- is "back" (before the body), "body" (after the body, before the head) or "front".

type Ctx = {
	g: Grid,
	look: { [string]: any },
	pose: Pose,
	dx: number,
	dy: number,
	frame: number,
	attacking: boolean,
}

local function at(ctx: Ctx, rows: Rows, x: number, y: number)
	Parts.stamp(ctx.g, rows, x + ctx.dx, y + ctx.dy)
end

local ACCESSORIES: { [string]: { [string]: (Ctx) -> () } } = {
	Hood = {
		-- the hood resting on the shoulders behind the head, drawstrings on the chest
		body = function(ctx)
			at(ctx, { ".kk", "kcc", "kcc" }, 1, 9)
			at(ctx, { "cccccccc" }, 4, 11)
		end,
		front = function(ctx)
			at(ctx, { "t.t" }, 6, 12)
		end,
	},
	Talismans = {
		back = function(ctx)
			local bob = ctx.frame % 2
			at(ctx, { "q", "q", "r" }, 0, 6 + bob)
			at(ctx, { "q", "q", "r" }, 15, 8 - bob)
		end,
	},
	Headband = {
		front = function(ctx)
			-- the band runs across the hair at the forehead row, wherever the hair is
			local head = HEADS[ctx.look.hairStyle or "Short"] or HEADS.Short
			local y = 5
			local row = head[y + 1]
			for x = 1, #row do
				local ch = string.sub(row, x, x)
				if ch == "h" or ch == "H" or ch == "z" or ch == "L" then
					Parts.put(ctx.g, x - 1 + ctx.dx, y + ctx.dy, "t")
				end
			end
			at(ctx, { "t", "T" }, 1, 6)
		end,
	},
	Scarf = {
		body = function(ctx)
			at(ctx, { "tttttttt" }, 4, 11)
			if ctx.frame % 2 == 1 then
				at(ctx, { "ktt", "kT.", ".T." }, 1, 11)
			else
				at(ctx, { "kttt", "kTT.", "k..." }, 0, 11)
			end
		end,
	},
	Gauntlets = {},
	Sash = {
		front = function(ctx)
			at(ctx, { "T", "T" }, 4, 16)
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
		front = function(ctx)
			local up = ctx.frame % 2
			Parts.put(ctx.g, 0, 7 + up, "u")
			Parts.put(ctx.g, 15, 4 + up, "u")
			Parts.put(ctx.g, 1, 15 - up, "u")
		end,
	},
	KatanaBack = {
		-- scabbard across the back; the hilt shows over the far shoulder
		back = function(ctx)
			at(ctx, { "..t", ".tk", "gk.", "v..", "v.." }, 0, 6)
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
		-- a long open coat: wide shoulders and a skirt over the thighs with a trim hem
		body = function(ctx)
			at(ctx, { "kcck", "kc", "kc" }, 2, 11)
			at(ctx, { "kcck", ".kc", ".kc" }, 10, 11)
			Parts.stamp(ctx.g, { "..kccccccccck...", "..ktttttttttk..." }, 0, 16)
		end,
	},
	KatanaHip = {
		back = function(ctx)
			at(ctx, { "vk", "v." }, 2, 15)
		end,
		front = function(ctx)
			if not ctx.attacking then
				at(ctx, { ".t", "g." }, 11, 13)
			end
		end,
	},
	FoxMaskSide = {
		front = function(ctx)
			at(ctx, { "w.w", "www", "ttw" }, 2, 4)
		end,
	},
	Halo = {
		back = function(ctx)
			at(ctx, { "...uuu.uuu.." }, 2, 1)
			at(ctx, { "u", "u", ".", "u" }, 1, 2)
		end,
	},
}

local LAYER_ORDER = { "back", "body", "front" }

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
	if not w or (kind == "bow" and frame == "rest") or (kind == "staff" and frame == "rest") then
		return
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

local function compose(look: { [string]: any }, style: string, pose: Pose, frame: number, attacking: boolean): Grid
	local g = Parts.grid(W, H)
	local hairStyle = look.hairStyle or "Short"
	local head = HEADS[hairStyle] or HEADS.Short
	local dx, dy = pose.dx or 0, pose.dy or 0
	local ctx: Ctx = {
		g = g,
		look = look,
		pose = pose,
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
	local back = HAIR_BACK[hairStyle]
	if back then
		Parts.stamp(g, back.rows, dx, back.y + dy)
	end
	Parts.stamp(g, LEGS[pose.legs], 0, 16)
	Parts.stamp(g, UPPER[pose.upper], dx, 11 + dy)
	layer("body")
	Parts.stamp(g, head, dx, dy)
	local arms = pose.arms and ARMS[pose.arms]
	if arms then
		Parts.stamp(g, arms.rows, arms.x + dx, arms.y + dy)
	end
	layer("front")
	stampWeapon(ctx, weaponFor(look, style), pose.weapon)
	if has(look, "Gauntlets") then
		Parts.swap(g, "j", "m")
	end
	local fx = pose.fx and FX[pose.fx]
	if fx then
		Parts.stamp(g, fx.rows, fx.x + dx, fx.y + dy)
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
		attackGrids[i] = compose(look, style, pose, i)
	end
	local result = {
		idle = Parts.define(id .. "Idle", idleGrids, palette, ANCHOR),
		attack = Parts.define(id .. "Attack", attackGrids, palette, ANCHOR),
		color = Palette.nearest(techColor),
	}
	sorcererCache[id] = result
	return result
end

-- PORTRAITS ------------------------------------------------------------------------------
-- 24x24 head and shoulders facing front: the face and jacket, then the hair style and the
-- accessories that show from the front. Same keys as the Sorcerer frames (plus "y" mouth).

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
	"...kSsskksssssskkssSk...",
	"...kSsswesssssswessSk...",
	"...kSsseesssssseessSk...",
	"...kSssssssssssssssSk...",
	"...kSsssssssyysssssSk...",
	"....kSssssssssssssSk....",
	".....kkSssssssssSkk.....",
	".......kkkSSSSkkk.......",
	"..kkkkkkkottttokkkkkkk..",
	"..kOoooooottttoooooooOk.",
	".kOooooooootooooooooOk..",
	".kOoooooooottooooooooOk.",
	".kOoooooooottooooooooOk.",
}

local PORTRAIT_HAIR: { [string]: { back: Rows?, front: Rows } } = {
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
			"..kHhhhhhhhhhhhhhhhhHk..",
			"..kHhhhhshhhhhhhshhhHk..",
			"..kHhhsssshhhhsssshhHk..",
			"..kHh.............hHk...",
			"..kHh.............hHk...",
			"...kk.............kk....",
		},
	},
	Spiky = {
		front = {
			"....k...k....k...k......",
			"...khk.khk..khk.khk.....",
			"..khhhkhhhkkhhhkhhhkk...",
			"..khhhhhhhhhhhhhhhhhhk..",
			".khhhhhhhhhhhhhhhhhhhLk.",
			"kHhhhhhhhhhhhhhhhhhhhhLk",
			".kHhzhhhhhhhhhhhhhhhhk..",
			"kHHhzhhhhhhhhhhhhhhhhHk.",
			".kHhhhhhhhhhhhhhhhhhHk..",
			"..kHhhhhshhhhhhhshhhHk..",
			"..kHhhsssshhhhsssshhHk..",
			"..kHh.............hHk...",
			"...kk.............kk....",
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
			".khhzhhhhhhhhhhhhhhhhhk.",
			".kHhzhhhhhhhhhhhhhhhhhk.",
			".kHhhhhhhhhhhhhhhhhhhHk.",
			".kHhhhhhhhhhhhhhhhhhhHk.",
			".kHhhh............hhHHk.",
			".kHhh..............hHHk.",
			".kHhh..............hHHk.",
			".kHhh..............hHHk.",
			".kHhh..............hHHk.",
			".kHHh..............hHHk.",
			".kkkkk............kkkkk.",
		},
	},
	Long = {
		back = {
			"........................",
			"........................",
			"........................",
			"........................",
			"........................",
			"........................",
			"........................",
			"........................",
			"........................",
			"........................",
			"........................",
			"........................",
			"........................",
			"........................",
			"........................",
			".kHhh..............hHHk.",
			".kHhhk............khHHk.",
			".kHhhk............khHHk.",
			".kHhhk............khHHk.",
			".kHhhk............khHHk.",
			".kHhhk............khHHk.",
			".kHhk..............kHHk.",
			".kHhk..............kHHk.",
			".kHhk..............kHHk.",
		},
		front = {
			"........................",
			"........................",
			"......kkkkkkkkkkkk......",
			"....kkhhhhhhhhhhhhkk....",
			"...khhhhhhhhhhhhhhhLk...",
			"..khhhhhhhhhhhhhhhhhLk..",
			".khhzhhhhhhhhhhhhhhhhhk.",
			".kHhzhhhhhhhhhhhhhhhhhk.",
			".kHhhhhhhhhhhhhhhhhhhHk.",
			".kHhhhhshhhhhhhshhhhHHk.",
			".kHhhsssshhhhsssshhhHHk.",
			".kHhh..............hHHk.",
			".kHhh..............hHHk.",
			".kHhh..............hHHk.",
			".kHhh..............hHHk.",
		},
	},
	Ponytail = {
		back = {
			"........................",
			"........................",
			"........................",
			"........................",
			"........................",
			"........................",
			"...........kkk..........",
			"..........khhhk.........",
			"........................",
		},
		front = {
			"........................",
			"..........kkkk..........",
			"......kkkkttttkkkk......",
			"....kkhhhhkttkhhhhkk....",
			"...khhhhhhhhhhhhhhhLk...",
			"..khhhhhhhhhhhhhhhhhLk..",
			"..kHhzhhhhhhhhhhhhhhhk..",
			"..kHhzhhhhhhhhhhhhhhhk..",
			"..kHhhhhhhhhhhhhhhhhHk..",
			"..kHhhhhshhhhhhhshhhHk..",
			"..kHhhsssshhhhsssshhHk..",
			"..kHh.............hHk...",
			"..kHh.............hHk...",
			"...kk.............kk....",
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
			"..kHhhhhhhhhhhhzzhhhHk..",
			"..kHhhsshhhhhhhhzzhhHk..",
			"..kHhsssshhhhhhhhzhhHk..",
			"..kHh..........hhhhhHk..",
			"..kHh............hhhHk..",
			"...kk.............kkk...",
		},
	},
}

local PORTRAIT_ACCESSORIES: { [string]: { back: Rows?, front: Rows? } } = {
	Hood = {
		back = {
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"..kkk..............kkk..",
			".kcccck..........kcccck.",
			".kccccckkk....kkkccccck.",
		},
		front = {
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"..........t..t..........",
			"..........t..t..........",
		},
	},
	Talismans = {
		front = {
			"",
			"",
			"",
			"",
			"",
			"",
			"qq",
			"qq",
			"rr",
			"qq",
			"",
			"",
			"......................qq",
			"......................qq",
			"......................rr",
			"......................qq",
		},
	},
	Headband = {
		front = {
			"",
			"",
			"",
			"",
			"",
			"",
			"..kttttttttttttttttttk..",
			".tT",
			"tT",
		},
	},
	Scarf = {
		front = {
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"......kttttttttttk......",
			".....kttttttttttttk.....",
			"......kkkkkTTkkkkk......",
			"...........TT...........",
			"...........Tk...........",
		},
	},
	BellStaff = {
		back = {
			"",
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
	Orbs = {
		front = {
			"",
			"",
			"",
			"",
			"uu",
			"uu",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"......................uu",
			"......................uu",
		},
	},
	KatanaBack = {
		back = {
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"kt",
			"ktk",
			".ggk",
			"..vk",
		},
	},
	StarBow = {
		back = {
			"",
			"",
			"",
			"",
			"",
			".....................G..",
			"....................GGG.",
			".....................b..",
			"....................tb..",
			"....................t.b.",
			"....................t.b.",
			"....................t.b.",
			"....................t.b.",
			"....................t.b.",
			"....................t.b.",
			"....................tb..",
			".....................b..",
		},
	},
	Haori = {
		front = {
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"..kkkkkkk......kkkkkkk..",
			"..kccccccct..tccccccck..",
			".kccccccccct.tcccccccck.",
			".kccccccccct.tcccccccck.",
			".kccccccccct.tcccccccck.",
		},
	},
	FoxMaskSide = {
		front = {
			"",
			"",
			"k...k",
			"wk.kw",
			"wwkww",
			"wwwww",
			"twwwt",
			"wwwww",
			".www",
		},
	},
	Halo = {
		back = {
			"....uuuuuu..uuuuuu......",
			"..uu..............uu....",
			".u..................u...",
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
	palette.y = Palette.Rust
	local g = Parts.grid(24, 24)
	local hair = PORTRAIT_HAIR[look.hairStyle or "Short"] or PORTRAIT_HAIR.Short
	local accessories = look.accessories or {}
	for _, a in accessories do
		local acc = PORTRAIT_ACCESSORIES[a]
		if acc and acc.back then
			Parts.stamp(g, acc.back, 0, 0)
		end
	end
	if hair.back then
		Parts.stamp(g, hair.back, 0, 0)
	end
	Parts.stamp(g, PORTRAIT_BASE, 0, 0)
	Parts.stamp(g, hair.front, 0, 0)
	if look.hairStyle == "Swept" then
		-- the swept fringe hides the right eye
		Parts.fill(g, 15, 11, 3, 3, "h")
	end
	for _, a in accessories do
		local acc = PORTRAIT_ACCESSORIES[a]
		if acc and acc.front then
			Parts.stamp(g, acc.front, 0, 0)
		end
	end
	local result = Parts.define(id .. "Portrait", { g }, palette, { 12, 24 })
	portraitCache[id] = result
	return result
end

-- COMPANIONS -----------------------------------------------------------------------------
-- Spirits that sit or float beside their Sorcerer (colours from the old 3D models, snapped).
-- 2 idle frames, at most 14x14, anchor bottom middle.

local rgb = Color3.fromRGB
local snap = Palette.nearest

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
				".kkgGgggykykk.",
				".kgGggggyky.k.",
				"kdgggggggggggk",
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
				".kgGggggkkkk..",
				"kdgGgggggggggk",
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
			a = snap(rgb(170, 220, 255)),
			A = snap(rgb(90, 130, 220)),
			w = snap(rgb(220, 250, 255)),
		},
		frames = {
			{
				"...a......a...",
				"....k....k....",
				"kk...kbbk...kk",
				"kaak.kwwk.kaak",
				"kaaakkbbkkaaak",
				"kAaaakbbkaaaAk",
				".kAaakbbkaaAk.",
				"..kkkkbbkkkk..",
				".kaaakbbkaaak.",
				".kAak.kk.kaAk.",
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
				"kAaaakbbkaaaAk",
				"kAAakkbbkkaAAk",
				".kkkakbbkakkk.",
				"...kAkkkkAk...",
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
			W = Palette.Mist,
			r = snap(rgb(196, 40, 60)),
			e = snap(rgb(255, 80, 110)),
			c = Palette.Night,
			C = Palette.Dusk,
		},
		frames = {
			{
				".k........k.",
				"kwk......kwk",
				"kwwkkkkkkwwk",
				".kwwwwwwwwk.",
				"kwrwwwwwwrwk",
				"kwkekwwkekWk",
				"kwwwwwwwwwWk",
				"kwkkkkkkkkWk",
				"kWkwkwwkwkWk",
				".kWwwwwwwWk.",
				"..kkccccck..",
				".kcCccccCck.",
				".kccckcccck.",
				"..kck.kck...",
			},
			{
				"............",
				".k........k.",
				"kwk......kwk",
				"kwwkkkkkkwwk",
				".kwwwwwwwwk.",
				"kwrwwwwwwrwk",
				"kwkekwwkekWk",
				"kwwwwwwwwwWk",
				"kwkkkkkkkkWk",
				"kWkwkwwkwkWk",
				".kWwwwwwwWk.",
				"..kkccccck..",
				".kcCcccccck.",
				"..kckkckck..",
			},
		},
	},
	-- a pale wolf with yellow lightning marks, sitting; its tail wags
	Wolf = {
		palette = {
			k = Palette.Ink,
			f = snap(rgb(236, 232, 214)),
			F = Palette.Slate,
			y = snap(rgb(255, 214, 60)),
			e = snap(rgb(120, 220, 255)),
		},
		frames = {
			{
				"..........k.k.",
				".........kykyk",
				"........kfffffk",
				"........kffekfk",
				"........kffffkk",
				"......kkffffk..",
				"..k..kfffffk...",
				".kyk.kfyFffk...",
				".kfk.kffyfFk...",
				"..kfkkFfffFk...",
				"...kFfFfFFfk...",
				"...kffkkfffkk..",
				"...kkk..kkkkk..",
			},
			{
				"..........k.k.",
				".........kykyk",
				"........kfffffk",
				"........kffekfk",
				"........kffffkk",
				"......kkffffk..",
				".....kfffffk...",
				".....kfyFffk...",
				"kk...kffyfFk...",
				"kykkkkFfffFk...",
				".kffFfFfFFfk...",
				"..kkfkkkfffkk..",
				"...kkk..kkkkk..",
			},
		},
	},
	-- a coiled serpent with cracks of light and a horned head; it sways
	Serpent = {
		palette = {
			k = Palette.Ink,
			b = snap(rgb(48, 40, 62)),
			B = Palette.Dusk,
			v = snap(rgb(186, 90, 255)),
			h = snap(rgb(220, 210, 230)),
			e = snap(rgb(255, 70, 120)),
		},
		frames = {
			{
				".......h.h....",
				"......kkkkk...",
				".....kbbbbbkk.",
				".....kbbekbbk.",
				"......kbbbkkk.",
				"...kkk.kbbk...",
				"..kbbBkkbbk...",
				"..kbvkbbbbk...",
				"..kbbbbkkk....",
				".kkkkkkbbbkk..",
				"kbbvbbbbvbbbk.",
				"kBbbbbbbbbbBk.",
				".kbbbvbbbbbk..",
				"..kkkkkkkkk...",
			},
			{
				"......h.h.....",
				".....kkkkk....",
				"....kbbbbbkk..",
				"....kbbekbbk..",
				".....kbbbkkk..",
				"...kkkkbbk....",
				"..kbbBkbbk....",
				"..kbvkbbbbk...",
				"..kbbbbkkk....",
				".kkkkkkbbbkk..",
				"kbbvbbbbvbbbk.",
				"kBbbbbbbbbbBk.",
				".kbbbvbbbbbk..",
				"..kkkkkkkkk...",
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
-- The local player and other players: a plain T-shirt chibi in their avatar colours (not
-- snapped), short hair, three directions with a 2-step walk.

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
		"..khsksssksshk..",
		"..khsksssksshk..",
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
			{ "...kppppppppk...", "...kpppkkpppk...", "...kpppkkpppk...", "...kkkkk.kkkk..." },
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
			{ "...kppppppppk...", "...kpppkkpppk...", "...kpppkkpppk...", "...kkkkk.kkkk..." },
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
		legs = {
			{ "....kppppppk....", "....kppkkppk....", "....kppkkppk....", "....kkkk.kkkk..." },
			{ "....kppppppk....", "...kppk.kppk....", "..kppk...kppk...", "..kkkk...kkkkk.." },
			{ "....kppppppk....", ".....kppppk.....", ".....kkppkk.....", ".....kkkkkk....." },
		},
	},
}

-- Walk frames: the upper body bobs up on the passing steps.
local PLAYER_BOB = { 0, -1, -1 }

local function playerDef(dir: string, palette: { [string]: Color3 }): Def
	local grids = {}
	local body = PLAYER_BODY[dir]
	for i = 1, 3 do
		local g = Parts.grid(W, H)
		local bob = PLAYER_BOB[i] + 1
		Parts.stamp(g, body.legs[i], 0, 16)
		Parts.stamp(g, body.upper, 0, 11 + bob)
		Parts.stamp(g, PLAYER_HEAD[dir], 0, bob)
		grids[i] = g
	end
	return Parts.define("Player" .. dir, grids, palette, ANCHOR)
end

-- Player sprites in avatar colours: { down, up, side }, 3 frames each (stand, walk A, walk B).
function Characters.player(colors: { skin: Color3, shirt: Color3, pants: Color3, hair: Color3 }): {
	down: Def,
	up: Def,
	side: Def,
}
	local palette = {
		k = Palette.Ink,
		s = colors.skin,
		S = Palette.shade(colors.skin, 0.18),
		o = colors.shirt,
		O = Palette.shade(colors.shirt, 0.3),
		p = colors.pants,
		h = colors.hair,
		H = Palette.shade(colors.hair, 0.3),
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
