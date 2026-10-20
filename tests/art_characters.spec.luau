--!nocheck
-- Specs for Pixel/Art/Characters: the contract in docs/PIXEL_ARCHITECTURE.md (sizes, frame
-- counts, anchors, the snapped technique colour), coverage of every Sorcerer, hair style,
-- accessory and companion in the config, colour rules (palette only, accents keep their hue,
-- nothing glows in skin colours), readability checks (every accessory shows, nothing cuts the
-- leg outlines, no stray outline pixels), rectangle budgets and determinism.
local roblox = require("@lune/roblox")

return function(ctx)
	local kit, sb = ctx.kit, ctx.sandbox
	local describe, it, expect = kit.describe, kit.it, kit.expect

	local Characters = sb.requirePath("ReplicatedStorage/Shared/Pixel/Art/Characters")
	local Parts = sb.requirePath("ReplicatedStorage/Shared/Pixel/Art/CharacterParts")
	local Sprite = sb.requirePath("ReplicatedStorage/Shared/Pixel/Sprite")
	local Palette = sb.requirePath("ReplicatedStorage/Shared/Pixel/Palette")
	local Sorcerers = sb.requirePath("ReplicatedStorage/Shared/Config/Sorcerers")

	-- Rectangles per frame (Sprite.cost). The contract asks for "about 40"; outlined 16x20
	-- chibis in the approved mock's style cost 50-85 (the mock's own Kai is 72), portraits up
	-- to ~105. These are hard ceilings at today's maxima (85, 104, 49, 46, 27) so any growth
	-- is a deliberate change; the overrun is reported to the contract owner.
	local BUDGET = { sorcerer = 85, portrait = 104, companion = 49, player = 46, carry = 27 }

	local STYLE_FRAMES = { Punch = 3, Cast = 3, Slash = 3, Shoot = 3 }
	local COMPANIONS = { "Toad", "Moth", "Mask", "Wolf", "Serpent" }
	local C = roblox.Color3.fromRGB
	local PLAYER_COLORS =
		{ skin = C(234, 184, 146), shirt = Palette.Sky, pants = Palette.Dusk, hair = Palette.DarkBrown }

	local function hex(c): string
		return string.format(
			"%02x%02x%02x",
			math.floor(c.R * 255 + 0.5),
			math.floor(c.G * 255 + 0.5),
			math.floor(c.B * 255 + 0.5)
		)
	end
	local INK = hex(Palette.Ink)

	-- The skin colour the module draws for a look (pale skin is Peach, not Cream).
	local function skinOf(c)
		local s = Parts.snap(c, Palette.Peach)
		return if hex(s) == hex(Palette.Cream) then Palette.Peach else s
	end

	-- Colour of every pixel of one frame ("." for transparent), from the rows and the palette.
	local function pixels(def, frame)
		local out = {}
		for y, row in def.frames[frame] do
			out[y] = {}
			for x = 1, #row do
				local ch = string.sub(row, x, x)
				out[y][x] = if ch == "." or ch == " " then "." else hex(def.palette[ch])
			end
		end
		return out
	end

	local function diff(a, b)
		local n = 0
		for y, row in a do
			for x, c in row do
				if b[y] == nil or b[y][x] ~= c then
					n += 1
				end
			end
		end
		return n
	end

	local function frameHas(def, frame, colour)
		for _, row in pixels(def, frame) do
			for _, c in row do
				if c == hex(colour) then
					return true
				end
			end
		end
		return false
	end

	local function sameRects(a, b)
		if #a.rects ~= #b.rects then
			return false
		end
		for f, rects in a.rects do
			local other = b.rects[f]
			if #rects ~= #other then
				return false
			end
			for i, r in rects do
				local o = other[i]
				if
					r.x ~= o.x
					or r.y ~= o.y
					or r.w ~= o.w
					or r.h ~= o.h
					or hex(a.palette[r.key]) ~= hex(b.palette[o.key])
				then
					return false
				end
			end
		end
		return true
	end

	local function maxCost(def)
		local m = 0
		for f = 1, #def.frames do
			m = math.max(m, Sprite.cost(def, f))
		end
		return m
	end

	local inPalette = {}
	for _, c in Palette.All do
		inPalette[hex(c)] = true
	end
	local function allPaletteColours(def)
		for _, c in def.palette do
			if not inPalette[hex(c)] then
				return false, hex(c)
			end
		end
		return true
	end

	-- Mean x of the skin pixels in the head rows: > the middle when the face looks right.
	local function faceX(def, frame, skin, rows)
		local sum, n = 0, 0
		for y, row in pixels(def, frame) do
			if y <= rows then
				for x, c in row do
					if c == skin then
						sum += x - 1
						n += 1
					end
				end
			end
		end
		return if n > 0 then sum / n else -1
	end

	local function touchesGround(def, frame)
		local last = def.frames[frame][def.h]
		return string.find(last, "[^%. ]") ~= nil
	end

	-- Ink pixels with nothing drawn on any of their four sides (stray outline crumbs).
	local function strayInk(def, frame)
		local px = pixels(def, frame)
		local n = 0
		for y, row in px do
			for x, c in row do
				if c == INK then
					local alone = true
					for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
						local r = px[y + d[2]]
						if r and r[x + d[1]] and r[x + d[1]] ~= "." then
							alone = false
						end
					end
					if alone then
						n += 1
					end
				end
			end
		end
		return n
	end

	local function hueGap(a, b)
		local ha, hb = a:ToHSV(), b:ToHSV()
		local d = math.abs(ha - hb) % 1
		return math.min(d, 1 - d) * 360
	end

	-- A Sorcerer built from an edited copy of a look, registered in this sandbox's config so
	-- Characters reads it like a real one.
	local probes = 0
	local function probeArt(source, edit)
		probes += 1
		local look = table.clone(source.look)
		look.accessories = table.clone(source.look.accessories or {})
		edit(look)
		local id = "probe_" .. probes
		Sorcerers.ById[id] = {
			id = id,
			name = id,
			rarity = source.rarity,
			ops = 1,
			orbValue = 1,
			technique = "Probe",
			style = source.style,
			color = source.color,
			look = look,
		}
		local art = Characters.sorcerer(id)
		Sorcerers.ById[id] = nil
		return art
	end

	describe("Characters", function()
		it("has the documented size", function()
			expect(Characters.Size.w).toBe(16)
			expect(Characters.Size.h).toBe(20)
		end)
	end)

	describe("Characters.sorcerer", function()
		for _, s in Sorcerers.List do
			it(s.id .. " has idle (2) and attack (3) frames at 16x20 anchored at the feet", function()
				local art = Characters.sorcerer(s.id)
				for name, count in { idle = 2, attack = STYLE_FRAMES[s.style] } do
					local def = art[name]
					expect(def ~= nil).toBe(true)
					expect(def.w).toBe(16)
					expect(def.h).toBe(20)
					expect(#def.frames).toBe(count)
					expect(def.anchor[1]).toBe(8)
					expect(def.anchor[2]).toBe(20)
					for f = 1, count do
						expect(#def.rects[f]).toBeGreaterThan(10)
						expect(touchesGround(def, f)).toBe(true)
					end
				end
			end)

			it(s.id .. " returns its technique glow colour and glows on the strike", function()
				local art = Characters.sorcerer(s.id)
				expect(typeof(art.color)).toBe("Color3")
				-- the in-sprite glow keeps the technique's hue and is never a skin colour, and the
				-- returned colour (orbs, effects) is that same glow
				local skin = skinOf(s.look.skin)
				local glow = Parts.accent(s.color, skin, Palette.White)
				expect(hex(art.color)).toBe(hex(glow))
				expect(frameHas(art.attack, 2, glow)).toBe(true)
				local ramp = Parts.skinRamp(skin)
				for _, c in { glow, Parts.glowLight(glow, skin) } do
					expect(ramp[tonumber(hex(c), 16)] or false).toBe(false)
					expect(hex(c) ~= hex(skin)).toBe(true)
					expect(hex(c) ~= hex(Parts.darker(skin))).toBe(true)
					expect(hex(c) ~= hex(Parts.lighter(skin))).toBe(true)
				end
				if Parts.isVivid(s.color) then
					expect(hueGap(glow, s.color) <= 75).toBe(true)
				end
			end)

			it(s.id .. " keeps the hue of its trim and eyes", function()
				local art = Characters.sorcerer(s.id)
				local skin = skinOf(s.look.skin)
				for _, key in { "trim", "eyes" } do
					local source = s.look[key]
					local snapped = Parts.accent(source, skin, Palette.Ink)
					expect(frameHas(art.idle, 1, snapped)).toBe(true)
					if Parts.isVivid(source) then
						expect(hueGap(snapped, source) <= 75).toBe(true)
					end
					expect(hex(snapped) ~= hex(skin)).toBe(true)
				end
			end)

			it(s.id .. " animates: idle bobs and every attack frame is different", function()
				local art = Characters.sorcerer(s.id)
				expect(diff(pixels(art.idle, 1), pixels(art.idle, 2))).toBeGreaterThan(0)
				local rest = pixels(art.idle, 1)
				for f = 1, 3 do
					expect(diff(rest, pixels(art.attack, f))).toBeGreaterThan(0)
				end
				-- wind-up, strike and follow-through are three poses, not a held frame
				expect(diff(pixels(art.attack, 1), pixels(art.attack, 2))).toBeGreaterThan(19)
				expect(diff(pixels(art.attack, 2), pixels(art.attack, 3))).toBeGreaterThan(19)
			end)

			it(s.id .. " faces right, uses only palette colours and has no stray outline pixels", function()
				local art = Characters.sorcerer(s.id)
				local skin = hex(skinOf(s.look.skin))
				expect(faceX(art.idle, 1, skin, 11)).toBeGreaterThan(7.5)
				expect((allPaletteColours(art.idle))).toBe(true)
				expect((allPaletteColours(art.attack))).toBe(true)
				for f = 1, 2 do
					expect(strayInk(art.idle, f)).toBe(0)
				end
				for f = 1, 3 do
					expect(strayInk(art.attack, f)).toBe(0)
				end
			end)

			it(s.id .. " stays inside the rectangle budget", function()
				local art = Characters.sorcerer(s.id)
				expect(maxCost(art.idle) <= BUDGET.sorcerer).toBe(true)
				expect(maxCost(art.attack) <= BUDGET.sorcerer).toBe(true)
			end)

			for _, accessory in s.look.accessories or {} do
				it(
					s.id .. " shows its " .. accessory .. " (at least 4 pixels) without cutting the legs",
					function()
						local with = pixels(Characters.sorcerer(s.id).idle, 1)
						local without = pixels(
							probeArt(s, function(look)
								table.remove(look.accessories, table.find(look.accessories, accessory))
							end).idle,
							1
						)
						expect(diff(with, without) >= 4).toBe(true)
						-- the leg and boot outlines (rows 16-19) stay whole; a coat may cover them
						if accessory ~= "Haori" then
							for y = 17, 20 do
								for x, c in without[y] do
									if c == INK then
										expect(with[y][x]).toBe(INK)
									end
								end
							end
						end
					end
				)
			end
		end

		it("draws every Sorcerer differently (idle frames at least 50 pixels apart)", function()
			local list = Sorcerers.List
			local frames = {}
			for i, s in list do
				frames[i] = pixels(Characters.sorcerer(s.id).idle, 1)
			end
			local closest = math.huge
			for i = 1, #list do
				for j = i + 1, #list do
					closest = math.min(closest, diff(frames[i], frames[j]))
				end
			end
			expect(closest >= 50).toBe(true)
		end)

		it("gives unknown ids a generic Sorcerer of the same shape", function()
			local art = Characters.sorcerer("no_such_sorcerer")
			expect(art.idle.w).toBe(16)
			expect(art.idle.h).toBe(20)
			expect(#art.idle.frames).toBe(2)
			expect(#art.attack.frames).toBe(3)
			expect(typeof(art.color)).toBe("Color3")
		end)

		it("returns identical rectangles when called twice", function()
			for _, s in Sorcerers.List do
				local a = Characters.sorcerer(s.id)
				local b = Characters.sorcerer(s.id)
				expect(sameRects(a.idle, b.idle)).toBe(true)
				expect(sameRects(a.attack, b.attack)).toBe(true)
			end
		end)
	end)

	describe("Characters looks", function()
		-- Probes: Kai's look with one hair style or one accessory, everything else the same.
		local base = Sorcerers.get("kai")
		local function probe(edit)
			return pixels(
				probeArt(base, function(look)
					look.accessories = {}
					edit(look)
				end).idle,
				1
			)
		end

		local plain = probe(function(look)
			look.hairStyle = "Short"
		end)

		local styles, accessories = {}, {}
		for _, s in Sorcerers.List do
			styles[s.look.hairStyle] = true
			for _, a in s.look.accessories or {} do
				accessories[a] = true
			end
		end

		for style in styles do
			it("draws hair style " .. style, function()
				local other = if style == "Short" then "Spiky" else "Short"
				local a = probe(function(look)
					look.hairStyle = style
				end)
				local b = probe(function(look)
					look.hairStyle = other
				end)
				expect(diff(a, b)).toBeGreaterThan(4)
			end)
		end

		it("covers the six hair styles", function()
			local n = 0
			for _ in styles do
				n += 1
			end
			expect(n).toBe(6)
		end)

		for name in accessories do
			it("draws accessory " .. name .. " on any hair style", function()
				for _, style in { "Short", "Ponytail", "Long" } do
					local bare = probe(function(look)
						look.hairStyle = style
					end)
					local a = probe(function(look)
						look.hairStyle = style
						look.accessories = { name }
					end)
					expect(diff(bare, a) >= 4).toBe(true)
				end
			end)
		end

		it("covers the fourteen accessories", function()
			local n = 0
			for _ in accessories do
				n += 1
			end
			expect(n).toBe(14)
		end)

		it("draws a hair streak", function()
			for _, style in { "Short", "Spiky", "Bob", "Long", "Ponytail", "Swept" } do
				local a = probe(function(look)
					look.hairStyle = style
				end)
				local b = probe(function(look)
					look.hairStyle = style
					look.hairStreak = C(240, 236, 255)
				end)
				expect(diff(a, b)).toBeGreaterThan(1)
			end
		end)

		it("keeps pink hair pink on pale skin", function()
			local hana = Characters.sorcerer("hana")
			local skin = hex(skinOf(Sorcerers.get("hana").look.skin))
			local hair = pixels(hana.idle, 1)[4][6]
			expect(hair ~= skin).toBe(true)
			expect(hair).toBe(hex(Palette.Rose))
		end)

		it("keeps pastel and violet accents coloured instead of grey", function()
			local function idleHas(id, colour)
				return frameHas(Characters.sorcerer(id).idle, 1, colour)
			end
			expect(idleHas("rei", Palette.Cyan)).toBe(true)
			expect(idleHas("nao", Palette.Cyan)).toBe(true)
			expect(idleHas("shion", Palette.Orchid)).toBe(true)
			expect(idleHas("yoru", Palette.Orchid)).toBe(true)
			expect(frameHas(Characters.companion("Serpent"), 1, Palette.Orchid)).toBe(true)
		end)

		it("draws pale skin in Peach like the approved mock", function()
			expect(frameHas(Characters.sorcerer("kai").idle, 1, Palette.Peach)).toBe(true)
			expect(frameHas(Characters.sorcerer("kai").idle, 1, Palette.Cream)).toBe(false)
		end)
	end)

	describe("Characters.portrait", function()
		it("is a 24x24 single frame for every Sorcerer and unknown ids", function()
			for _, s in Sorcerers.List do
				local def = Characters.portrait(s.id)
				expect(def.w).toBe(24)
				expect(def.h).toBe(24)
				expect(#def.frames).toBe(1)
				expect((allPaletteColours(def))).toBe(true)
				expect(Sprite.cost(def, 1) <= BUDGET.portrait).toBe(true)
			end
			local generic = Characters.portrait("no_such_sorcerer")
			expect(generic.w).toBe(24)
			expect(#generic.frames).toBe(1)
		end)

		it("faces front (the face is centred) and every portrait is different", function()
			local list = Sorcerers.List
			local frames = {}
			for i, s in list do
				local def = Characters.portrait(s.id)
				local x = faceX(def, 1, hex(skinOf(s.look.skin)), 18)
				expect(math.abs(x - 11.5) < 1.5).toBe(true)
				frames[i] = pixels(def, 1)
			end
			for i = 1, #list do
				for j = i + 1, #list do
					expect(diff(frames[i], frames[j])).toBeGreaterThan(20)
				end
			end
		end)

		it("lights the top of the shoulders so dark jackets read on a dark panel", function()
			local def = Characters.portrait("kai")
			expect(pixels(def, 1)[21][6]).toBe(hex(Palette.Dusk))
		end)
	end)

	describe("Characters.companion", function()
		for _, name in COMPANIONS do
			it(name .. " has 2 frames, fits 14x14 and sits on its bottom middle", function()
				local def = Characters.companion(name)
				expect(def ~= nil).toBe(true)
				expect(#def.frames).toBe(2)
				expect(def.w <= 14).toBe(true)
				expect(def.h <= 14).toBe(true)
				expect(def.anchor[1]).toBe(math.floor(def.w / 2))
				expect(def.anchor[2]).toBe(def.h)
				expect(diff(pixels(def, 1), pixels(def, 2))).toBeGreaterThan(0)
				expect((allPaletteColours(def))).toBe(true)
				expect(maxCost(def) <= BUDGET.companion).toBe(true)
			end)
		end

		it("covers every companion in the config and returns nil for unknown names", function()
			for _, s in Sorcerers.List do
				if s.look.companion then
					expect(Characters.companion(s.look.companion) ~= nil).toBe(true)
				end
			end
			expect(Characters.companion("Dragon")).toBe(nil)
		end)
	end)

	describe("Characters.player", function()
		it("has down, up and side with 3 frames each at 16x20", function()
			local p = Characters.player(PLAYER_COLORS)
			for _, dir in { "down", "up", "side" } do
				local def = p[dir]
				expect(def.w).toBe(16)
				expect(def.h).toBe(20)
				expect(#def.frames).toBe(3)
				expect(def.anchor[1]).toBe(8)
				expect(def.anchor[2]).toBe(20)
				expect(diff(pixels(def, 1), pixels(def, 2))).toBeGreaterThan(0)
				expect(diff(pixels(def, 2), pixels(def, 3))).toBeGreaterThan(0)
				expect(maxCost(def) <= BUDGET.player).toBe(true)
			end
		end)

		it("snaps the avatar colours into the palette and faces the right way", function()
			local p = Characters.player(PLAYER_COLORS)
			local skin = hex(skinOf(PLAYER_COLORS.skin))
			for _, dir in { "down", "up", "side" } do
				expect((allPaletteColours(p[dir]))).toBe(true)
				for _, key in { "shirt", "pants", "hair" } do
					expect(frameHas(p[dir], 1, PLAYER_COLORS[key])).toBe(true)
				end
			end
			expect(faceX(p.side, 1, skin, 11)).toBeGreaterThan(7.5)
			expect(math.abs(faceX(p.down, 1, skin, 11) - 7.5) < 1).toBe(true)
		end)

		it("walks: the two strides mirror each other and only one of them bobs", function()
			local p = Characters.player(PLAYER_COLORS)
			local function top(def, frame)
				for y, row in def.frames[frame] do
					if string.find(row, "[^%.]") then
						return y
					end
				end
				return 0
			end
			for _, dir in { "down", "up", "side" } do
				expect(top(p[dir], 2) ~= top(p[dir], 3)).toBe(true)
			end
			-- the stand pose has symmetric feet
			expect(p.down.frames[1][20]).toBe(string.reverse(p.down.frames[1][20]))
		end)
	end)

	describe("Characters.carry", function()
		it("is about 12x10 with 2 glow frames, anchored at the bottom middle", function()
			local def = Characters.carry
			expect(def.w >= 10 and def.w <= 14).toBe(true)
			expect(def.h >= 8 and def.h <= 12).toBe(true)
			expect(#def.frames).toBe(2)
			expect(def.anchor[1]).toBe(math.floor(def.w / 2))
			expect(def.anchor[2]).toBe(def.h)
			expect(diff(pixels(def, 1), pixels(def, 2))).toBeGreaterThan(0)
			expect(maxCost(def) <= BUDGET.carry).toBe(true)
		end)
	end)

	describe("Characters determinism", function()
		it("builds identical rectangles in a fresh sandbox", function()
			local other = ctx.Sandbox.new(ctx.game)
			local Again = other.requirePath("ReplicatedStorage/Shared/Pixel/Art/Characters")
			for _, s in Sorcerers.List do
				local a, b = Characters.sorcerer(s.id), Again.sorcerer(s.id)
				expect(sameRects(a.idle, b.idle)).toBe(true)
				expect(sameRects(a.attack, b.attack)).toBe(true)
				expect(sameRects(Characters.portrait(s.id), Again.portrait(s.id))).toBe(true)
			end
			for _, name in COMPANIONS do
				expect(sameRects(Characters.companion(name), Again.companion(name))).toBe(true)
			end
			local p, q = Characters.player(PLAYER_COLORS), Again.player(PLAYER_COLORS)
			for _, dir in { "down", "up", "side" } do
				expect(sameRects(p[dir], q[dir])).toBe(true)
			end
			expect(sameRects(Characters.carry, Again.carry)).toBe(true)
		end)
	end)
end
