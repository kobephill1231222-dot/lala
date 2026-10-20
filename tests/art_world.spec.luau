--!nocheck
-- Pixel art for the world and its props: World (ground, map objects, farm fittings), Crates,
-- Icons and Fx. Checks the contract in docs/PIXEL_ARCHITECTURE.md (names, sizes, frame
-- counts), coverage of every config id, rectangle budgets, determinism, and the readability
-- rules (high art clear of a character in front, Ink outlines, orbs never in lane colours).
return function(ctx)
	local kit, sb = ctx.kit, ctx.sandbox
	local describe, it, expect = kit.describe, kit.it, kit.expect

	local World = sb.requirePath("ReplicatedStorage/Shared/Pixel/Art/World")
	local Crates = sb.requirePath("ReplicatedStorage/Shared/Pixel/Art/Crates")
	local Icons = sb.requirePath("ReplicatedStorage/Shared/Pixel/Art/Icons")
	local Fx = sb.requirePath("ReplicatedStorage/Shared/Pixel/Art/Fx")
	local Canvas = sb.requirePath("ReplicatedStorage/Shared/Pixel/Canvas")
	local Sprite = sb.requirePath("ReplicatedStorage/Shared/Pixel/Sprite")
	local Palette = sb.requirePath("ReplicatedStorage/Shared/Pixel/Palette")
	local WorldMap = sb.requirePath("ReplicatedStorage/Shared/Config/WorldMap")
	local Layout = sb.requirePath("ReplicatedStorage/Shared/Config/FarmLayout")
	local CrateConfig = sb.requirePath("ReplicatedStorage/Shared/Config/Crates")
	local Upgrades = sb.requirePath("ReplicatedStorage/Shared/Config/Upgrades")
	local Rarities = sb.requirePath("ReplicatedStorage/Shared/Config/Rarities")
	local Sorcerers = sb.requirePath("ReplicatedStorage/Shared/Config/Sorcerers")
	local Color3 = sb.globals.Color3

	local BUDGET = 40 -- rectangles per sprite frame
	local map = WorldMap.get()

	local function hex(c)
		return string.format(
			"%02x%02x%02x",
			math.floor(c.R * 255 + 0.5),
			math.floor(c.G * 255 + 0.5),
			math.floor(c.B * 255 + 0.5)
		)
	end

	local function dump(canvas)
		local parts = {}
		for _, r in canvas.rects do
			table.insert(parts, string.format("%d,%d,%d,%d,%s", r.x, r.y, r.w, r.h, hex(r.color)))
		end
		return table.concat(parts, ";")
	end

	-- First rectangle of `canvas` outside the box, or nil.
	local function outside(canvas, x0, y0, x1, y1)
		for _, r in canvas.rects do
			if r.x < x0 or r.y < y0 or r.x + r.w > x1 or r.y + r.h > y1 then
				return string.format(
					"rect %d,%d %dx%d outside %d,%d..%d,%d",
					r.x,
					r.y,
					r.w,
					r.h,
					x0,
					y0,
					x1,
					y1
				)
			end
		end
		return nil
	end

	local function wholePixels(canvas)
		for _, r in canvas.rects do
			if r.x % 1 ~= 0 or r.y % 1 ~= 0 or r.w % 1 ~= 0 or r.h % 1 ~= 0 or r.w <= 0 or r.h <= 0 then
				return false
			end
		end
		return true
	end

	local function artRect(rect)
		local x0, y0 = WorldMap.toPixels(rect.x0, rect.z0)
		local x1, y1 = WorldMap.toPixels(rect.x1, rect.z1)
		x0, y0, x1, y1 =
			math.floor(x0 + 0.5), math.floor(y0 + 0.5), math.floor(x1 + 0.5), math.floor(y1 + 0.5)
		return x0, y0, x1 - x0, y1 - y0
	end

	local function isDef(def)
		return type(def) == "table"
			and type(def.w) == "number"
			and type(def.h) == "number"
			and type(def.frames) == "table"
			and type(def.rects) == "table"
			and type(def.anchor) == "table"
	end

	local function maxCost(def)
		local m = 0
		for i = 1, #def.frames do
			m = math.max(m, Sprite.cost(def, i))
		end
		return m
	end

	describe("Art World", function()
		describe("ground", function()
			for _, kind in { "grass", "plaza", "road", "farmFloor" } do
				it(kind .. " is one base rect over the area plus detail inside it", function()
					local c = Canvas.new()
					World.ground(c, kind, 40, 320, 96, 80)
					local base = c.rects[1]
					expect(base.x).toBe(40)
					expect(base.y).toBe(320)
					expect(base.w).toBe(96)
					expect(base.h).toBe(80)
					expect(outside(c, 40, 320, 136, 400)).toBe(nil)
					expect(wholePixels(c)).toBe(true)
				end)
			end

			it("keeps grass over the whole world under 1500 rects", function()
				local c = Canvas.new()
				local w, h = WorldMap.pixelSize()
				World.ground(c, "grass", 0, 0, w, h)
				expect(#c.rects).toBeLessThan(1500)
				expect(#c.rects).toBeGreaterThan(600) -- tufts all over, as in the mock
			end)

			it("draws every ground area of the map in a modest number of rects", function()
				local c = Canvas.new()
				for _, g in map.ground do
					local before = #c.rects
					World.ground(c, g.kind, artRect(g.rect))
					expect(#c.rects > before).toBe(true)
				end
				expect(#c.rects).toBeLessThan(5000)
			end)

			it("leaves the plaza's curb open where a road comes in", function()
				local px, py, pw, ph = artRect({
					x0 = -Layout.PlazaHalfWidth,
					z0 = -Layout.PlazaHalfDepth,
					x1 = Layout.PlazaHalfWidth,
					z1 = Layout.PlazaHalfDepth,
				})
				local c = Canvas.new()
				World.ground(c, "plaza", px, py, pw, ph)
				local roads = 0
				for _, g in map.ground do
					if g.kind == "road" then
						roads += 1
						local rx, ry, rw, rh = artRect(g.rect)
						local edge = if ry + rh <= py + 1 then py else py + ph - 1
						for _, r in c.rects do
							local crosses = r.h == 1
								and r.y == edge
								and r.x < rx + rw - 1
								and r.x + r.w > rx + 1
								and r.color == Palette.Steel
							expect(crosses).toBe(false)
						end
					end
				end
				expect(roads).toBe(6)
			end)

			it("is deterministic", function()
				local a, b = Canvas.new(), Canvas.new()
				for _, g in map.ground do
					World.ground(a, g.kind, artRect(g.rect))
				end
				for _, g in map.ground do
					World.ground(b, g.kind, artRect(g.rect))
				end
				expect(dump(a)).toBe(dump(b))
			end)
		end)

		describe("objects", function()
			it("has art for every object kind the map uses", function()
				local kinds = {}
				for _, k in World.Kinds do
					kinds[k] = true
				end
				for _, o in map.objects do
					expect(kinds[o.kind] or o.kind).toBe(true)
				end
				for _, k in
					{
						"fence",
						"orbBox",
						"lantern",
						"sellStand",
						"pillar",
						"crateShop",
						"display",
						"upgradeShop",
						"upgradeBoard",
						"bench",
						"tree",
					}
				do
					expect(kinds[k] or k).toBe(true)
				end
			end)

			it("draws every map object on and just above its footprint", function()
				for _, o in map.objects do
					local x, y, w, h = artRect(o.rect)
					local low, high = Canvas.new(), Canvas.new()
					World.object(low, high, o, x, y, w, h)
					expect(#low.rects + #high.rects > 0).toBe(true)
					-- tall things rise up the screen; nothing hangs far below or wide of it
					local margin = if o.kind == "tree" then 14 else 6
					expect(outside(low, x - margin, y - 48, x + w + margin, y + h + 4) or "").toBe("")
					expect(outside(high, x - margin, y - 48, x + w + margin, y + h) or "").toBe("")
					expect(wholePixels(low) and wholePixels(high)).toBe(true)
				end
			end)

			it("puts roofs, canopies and the tops of lanterns and pillars in high", function()
				local seen = {}
				for _, o in map.objects do
					if
						o.kind == "tree"
						or o.kind == "crateShop"
						or o.kind == "upgradeShop"
						or o.kind == "lantern"
						or o.kind == "pillar"
					then
						local x, y, w, h = artRect(o.rect)
						local low, high = Canvas.new(), Canvas.new()
						World.object(low, high, o, x, y, w, h)
						expect(#low.rects > 0).toBe(true)
						expect(#high.rects > 0).toBe(true)
						-- the high part is above the low part
						local _, hy0 = high:bounds()
						local _, ly0, _, ly1 = low:bounds()
						expect(hy0 < ly1).toBe(true)
						expect(hy0 <= ly0).toBe(true)
						seen[o.kind] = true
					end
				end
				expect(seen.tree and seen.crateShop and seen.upgradeShop and seen.lantern and seen.pillar).toBe(
					true
				)
			end)

			it("never draws high art over a character standing just in front of an object", function()
				-- a 16 x 20 character, feet 2 px below the footprint, anywhere along it
				local function check(high, x, y, w, h, label)
					local feet = y + h + 2
					for _, r in high.rects do
						local overlap = r.x < x + w + 8
							and r.x + r.w > x - 8
							and r.y < feet
							and r.y + r.h > feet - 20
						expect(
							if overlap then label .. string.format(" %d,%d %dx%d", r.x, r.y, r.w, r.h) else ""
						).toBe("")
					end
				end
				for _, o in map.objects do
					local x, y, w, h = artRect(o.rect)
					local low, high = Canvas.new(), Canvas.new()
					World.object(low, high, o, x, y, w, h)
					check(high, x, y, w, h, o.kind)
					-- the design rule: nothing high within HeadRoom of the footprint's bottom
					if o.kind ~= "sellStand" then
						for _, r in high.rects do
							expect(r.y + r.h <= y + h - World.HeadRoom).toBe(true)
						end
					end
				end
				for _, variant in { "pine", "sakura", "maple" } do
					local low, high = Canvas.new(), Canvas.new()
					World.object(low, high, { kind = "tree", variant = variant }, 100, 100, 12, 12)
					check(high, 100, 100, 12, 12, variant)
				end
				-- the Sell Stand's beam and plaque stay clear of a character in front of the
				-- back pillars they stand on
				local stand
				local backBottom = math.huge
				for _, o in map.objects do
					if o.kind == "sellStand" then
						stand = o
					elseif o.kind == "pillar" then
						local _, py, _, ph = artRect(o.rect)
						backBottom = math.min(backBottom, py + ph)
					end
				end
				local x, y, w, h = artRect(stand.rect)
				local low, high = Canvas.new(), Canvas.new()
				World.object(low, high, stand, x, y, w, h)
				for _, r in high.rects do
					expect(r.y + r.h <= backBottom - World.HeadRoom).toBe(true)
				end
			end)

			it("draws thin props whole for y-sorting with World.prop", function()
				for _, o in map.objects do
					local x, y, w, h = artRect(o.rect)
					local prop = World.prop(o, x, y, w, h)
					if World.PropKinds[o.kind] then
						local low, high = Canvas.new(), Canvas.new()
						World.object(low, high, o, x, y, w, h)
						expect(prop and #prop.rects).toBe(#low.rects + #high.rects)
						expect(dump(prop)).toBe(dump(World.prop(o, x, y, w, h)))
					else
						expect(prop).toBe(nil)
					end
				end
				expect(World.PropKinds.pillar and World.PropKinds.lantern and World.PropKinds.upgradeBoard).toBe(
					true
				)
			end)

			it("draws a canopy wider than the trunk's footprint for every tree variant", function()
				local dumps = {}
				for _, variant in { "pine", "sakura", "maple" } do
					local low, high = Canvas.new(), Canvas.new()
					World.object(low, high, { kind = "tree", variant = variant }, 100, 100, 12, 12)
					local x0, _, x1 = high:bounds()
					expect(x1 - x0 > 12).toBe(true)
					dumps[variant] = dump(high)
				end
				expect(dumps.pine ~= dumps.sakura and dumps.sakura ~= dumps.maple).toBe(true)
			end)

			it("draws fences as rails with a post every 8 px or so", function()
				local low, high = Canvas.new(), Canvas.new()
				World.object(low, high, { kind = "fence", variant = "h" }, 0, 40, 224, 4)
				expect(#high.rects).toBe(0)
				local posts = 0
				for _, r in low.rects do
					if r.w == 4 and r.h == 12 then
						posts += 1
					end
				end
				expect(posts >= 224 / 8 - 2 and posts <= 224 / 8 + 2).toBe(true)
				local v = Canvas.new()
				World.object(v, v, { kind = "fence", variant = "v" }, 0, 0, 4, 256)
				expect(#v.rects > 256 / 8).toBe(true)
				-- a vertical run ends in standing posts exactly where the horizontal runs' end
				-- posts stand at the corners (on y + 4 and on y + h)
				local ends = {}
				for _, r in v.rects do
					if r.w == 4 and r.h == 12 then
						ends[r.y + r.h] = r.x
					end
				end
				expect(ends[4]).toBe(0)
				expect(ends[256]).toBe(0)
				local hrun = Canvas.new()
				World.object(hrun, hrun, { kind = "fence", variant = "h" }, 0, 252, 64, 4)
				expect(hrun.rects[1].x .. "," .. hrun.rects[1].y + hrun.rects[1].h).toBe("0,256")
			end)

			it("keeps the Sell Stand's dais clear of its corner pillars (any draw order)", function()
				local stand
				for _, o in map.objects do
					if o.kind == "sellStand" then
						stand = o
					end
				end
				local x, y, w, h = artRect(stand.rect)
				local low, high = Canvas.new(), Canvas.new()
				World.object(low, high, stand, x, y, w, h)
				local pillars = 0
				for _, o in map.objects do
					if o.kind == "pillar" then
						pillars += 1
						local px, py, pw, ph = artRect(o.rect)
						for _, r in low.rects do
							local overlap = r.x < px + pw
								and r.x + r.w > px
								and r.y < py + ph
								and r.y + r.h > py
							expect(overlap).toBe(false)
						end
					end
				end
				expect(pillars).toBe(4)
				-- the gold Sell Pad sits on the map's sellPad rectangle
				local sx, sy, sw, sh = artRect(map.sellPad)
				local found = false
				for _, r in low.rects do
					if r.x == sx and r.y == sy and r.w == sw and r.h == sh then
						found = true
					end
				end
				expect(found).toBe(true)
			end)

			it("pins one note per farm upgrade on the Upgrade Board", function()
				for _, o in map.objects do
					if o.kind == "upgradeBoard" then
						local x, y, w, h = artRect(o.rect)
						local low, high = Canvas.new(), Canvas.new()
						World.object(low, high, o, x, y, w, h)
						local notes = 0
						for _, r in low.rects do
							if r.color == Palette.Cream and r.h == 8 then
								notes += 1
								expect(r.x >= x and r.x + r.w <= x + w).toBe(true)
							end
						end
						expect(notes).toBe(#Upgrades.List)
					end
				end
			end)

			it("trims each display pedestal in its tier's colour", function()
				local seen = {}
				for _, tier in { "starter", "basic", "rare", "epic", "legendary" } do
					local low, high = Canvas.new(), Canvas.new()
					World.object(low, high, { kind = "display", variant = tier }, 0, 0, 24, 16)
					local d = dump(low)
					expect(seen[d]).toBe(nil)
					seen[d] = true
				end
			end)

			it("draws unknown kinds as a plain block instead of failing", function()
				local low, high = Canvas.new(), Canvas.new()
				World.object(low, high, { kind = "statue" }, 5, 5, 10, 10)
				expect(#low.rects > 0).toBe(true)
				expect(outside(low, 5, 5, 15, 15)).toBe(nil)
			end)

			it("is deterministic", function()
				local function all()
					local low, high = Canvas.new(), Canvas.new()
					for _, o in map.objects do
						World.object(low, high, o, artRect(o.rect))
					end
					return dump(low) .. "|" .. dump(high), #low.rects + #high.rects
				end
				local a, n = all()
				local b = all()
				expect(a).toBe(b)
				expect(n).toBeLessThan(6000)
			end)
		end)

		describe("farm fittings", function()
			local farm = map.farms[1]

			it("gives an Orb Box interior strictly inside the box", function()
				for _, f in map.farms do
					local x, y, w, h = artRect(f.box)
					local ix, iy, iw, ih = World.orbBoxInterior(x, y, w, h)
					expect(ix > x and iy > y and ix + iw < x + w and iy + ih < y + h).toBe(true)
					expect(iw > 0 and ih > 0).toBe(true)
					expect(ix % 1 + iy % 1 + iw % 1 + ih % 1).toBe(0)
				end
			end)

			it("draws the lane inside its rectangle", function()
				local x, y, w, h = artRect(farm.lane)
				local c = Canvas.new()
				World.lane(c, x, y, w, h)
				expect(#c.rects > 0).toBe(true)
				expect(outside(c, x, y, x + w, y + h)).toBe(nil)
			end)

			it("draws one repeat of slats, SlatSpacing tall, across the belt only", function()
				expect(type(World.SlatSpacing)).toBe("number")
				expect(World.SlatSpacing % 1).toBe(0)
				expect(World.SlatSpacing >= 2).toBe(true)
				local _, _, w = artRect(farm.lane)
				local c = Canvas.new()
				World.laneSlats(c, w, World.SlatSpacing)
				expect(#c.rects > 0).toBe(true)
				expect(outside(c, 1, 0, w - 1, World.SlatSpacing)).toBe(nil)
			end)

			it("draws open and locked slots inside their square, differently", function()
				local s = Layout.SlotSize * Layout.PixelsPerStud
				local open, locked = Canvas.new(), Canvas.new()
				World.slot(open, 0, 0, s, "open")
				World.slot(locked, 0, 0, s, "locked")
				expect(outside(open, 0, 0, s, s)).toBe(nil)
				expect(outside(locked, 0, 0, s, s)).toBe(nil)
				expect(dump(open) ~= dump(locked)).toBe(true)
				expect(#open.rects).toBeLessThan(BUDGET + 1)
				expect(#locked.rects).toBeLessThan(BUDGET + 1)
				-- the open slot has a gold rim
				local gold = false
				for _, r in open.rects do
					gold = gold or r.color == Palette.Amber
				end
				expect(gold).toBe(true)
				-- four equal checker tiles: joints every (s - 4) / 4 px inside the 2 px rim
				local joints = {}
				for _, r in open.rects do
					if r.color == Palette.Steel and r.w == 1 and r.h == s - 4 then
						table.insert(joints, r.x)
					end
				end
				table.sort(joints)
				local t = (s - 4) / 4
				local want = {}
				for k = 1, 3 do
					table.insert(want, 2 + math.floor(k * t + 0.5))
				end
				expect(table.concat(joints, ",")).toBe(table.concat(want, ","))
			end)

			it("draws open and locked Crate Pads inside their square, differently", function()
				local s = Layout.PadSize * Layout.PixelsPerStud
				local open, locked = Canvas.new(), Canvas.new()
				World.pad(open, 0, 0, s, "open")
				World.pad(locked, 0, 0, s, "locked")
				expect(outside(open, 0, 0, s, s)).toBe(nil)
				expect(outside(locked, 0, 0, s, s)).toBe(nil)
				expect(dump(open) ~= dump(locked)).toBe(true)
				expect(#open.rects).toBeLessThan(BUDGET + 1)
				expect(#locked.rects).toBeLessThan(BUDGET + 1)
			end)

			it("draws the Collect Pad and the farm sign inside their rectangles", function()
				local x, y, w, h = artRect(farm.collect)
				local c = Canvas.new()
				World.collectPad(c, x, y, w, h)
				expect(#c.rects > 0).toBe(true)
				expect(outside(c, x, y, x + w, y + h)).toBe(nil)
				local s = Canvas.new()
				World.sign(s, 10, 20, 72, 12)
				expect(outside(s, 10, 20, 82, 32)).toBe(nil)
				-- the renderer writes the name on a dark panel inset 2 px
				local panel = false
				for _, r in s.rects do
					panel = panel or (r.x == 12 and r.y == 22 and r.w == 68 and r.h == 8)
				end
				expect(panel).toBe(true)
			end)

			it("snaps fractional positions to whole pixels", function()
				local c = Canvas.new()
				World.slot(c, 10.4, 20.6, 32, "open")
				World.pad(c, 3.5, 7.2, 16, "locked")
				World.lane(c, 144.00001, 64, 32, 160)
				World.object(
					c,
					c,
					{ kind = "fence", variant = "h" },
					176.00001525878906,
					300,
					95.99998474121094,
					4
				)
				expect(wholePixels(c)).toBe(true)
				local x0, y0 = c:bounds()
				expect(x0 % 1 + y0 % 1).toBe(0)
			end)

			it("is deterministic", function()
				local function all()
					local c = Canvas.new()
					World.lane(c, artRect(farm.lane))
					World.laneSlats(c, 32, World.SlatSpacing)
					World.slot(c, 0, 0, 32, "open")
					World.slot(c, 0, 0, 32, "locked")
					World.pad(c, 0, 0, 16, "open")
					World.pad(c, 0, 0, 16, "locked")
					World.collectPad(c, artRect(farm.collect))
					World.sign(c, 0, 0, 72, 12)
					return dump(c)
				end
				expect(all()).toBe(all())
			end)
		end)
	end)

	describe("Art Crates", function()
		it("draws every tier: 16x16 with 4 frames, a lid and an icon", function()
			for _, crate in CrateConfig.List do
				local def = Crates.sprite(crate.id)
				expect(isDef(def)).toBe(true)
				expect(def.w).toBe(16)
				expect(def.h).toBe(16)
				expect(#def.frames).toBe(4)
				expect(def.anchor[1]).toBe(8)
				expect(def.anchor[2]).toBe(16)
				local lid = Crates.lid(crate.id)
				expect(isDef(lid)).toBe(true)
				expect(#lid.frames >= 1).toBe(true)
				expect(lid.w <= 16).toBe(true)
				local icon = Crates.icon(crate.id)
				expect(isDef(icon)).toBe(true)
				expect(icon.w >= 8 and icon.w <= 12 and icon.h >= 8 and icon.h <= 12).toBe(true)
			end
		end)

		it("stands every frame on its anchor (the bottom row is the crate's base)", function()
			for _, crate in CrateConfig.List do
				local def = Crates.sprite(crate.id)
				for _, rows in def.frames do
					expect(string.find(rows[def.anchor[2]], "k", 1, true) ~= nil).toBe(true)
				end
			end
		end)

		it("draws the Starter Crate plain and grey-banded, apart from the Basic Crate", function()
			local starter, basic = Crates.sprite("starter"), Crates.sprite("basic")
			expect(string.find(table.concat(starter.frames[1]), "p", 1, true)).toBe(nil)
			expect(string.find(table.concat(basic.frames[1]), "p", 1, true) ~= nil).toBe(true)
			expect(starter.palette.t).toBe(Palette.Mist)
			expect(starter.palette.h ~= basic.palette.h and starter.palette.b ~= basic.palette.b).toBe(true)
			expect(string.find(table.concat(Crates.icon("starter").frames[1]), "p", 1, true)).toBe(nil)
		end)

		it("gives every tier its own colours", function()
			local seen = {}
			for _, crate in CrateConfig.List do
				local p = Crates.sprite(crate.id).palette
				local key = hex(p.b) .. hex(p.t) .. hex(p.h)
				expect(seen[key]).toBe(nil)
				seen[key] = crate.id
			end
		end)

		it("shakes left, shakes right and opens with a glow", function()
			local def = Crates.sprite("rare")
			local f = def.frames
			expect(table.concat(f[1]) ~= table.concat(f[2])).toBe(true)
			expect(table.concat(f[2]) ~= table.concat(f[3])).toBe(true)
			expect(string.find(table.concat(f[4]), "g", 1, true) ~= nil).toBe(true)
			expect(string.find(table.concat(f[1]), "g", 1, true)).toBe(nil)
		end)

		it("stays within the rect budget", function()
			for _, crate in CrateConfig.List do
				expect(maxCost(Crates.sprite(crate.id))).toBeLessThan(BUDGET + 1)
				expect(maxCost(Crates.lid(crate.id))).toBeLessThan(BUDGET + 1)
				expect(maxCost(Crates.icon(crate.id))).toBeLessThan(BUDGET + 1)
			end
		end)

		it("draws an unknown tier as a plain crate instead of failing", function()
			local def = Crates.sprite("mythic")
			expect(def.w).toBe(16)
			expect(#def.frames).toBe(4)
		end)

		it("is deterministic", function()
			for _, crate in CrateConfig.List do
				local def = Crates.sprite(crate.id)
				for i, rows in def.frames do
					local again = Sprite.merge(rows)
					expect(#again).toBe(#def.rects[i])
				end
				expect(Crates.sprite(crate.id)).toBe(def)
			end
		end)
	end)

	describe("Art Icons", function()
		local contract = {
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
		}
		for _, u in Upgrades.List do
			table.insert(contract, u.id)
		end
		for _, r in Rarities.Order do
			table.insert(contract, "rarity_" .. r)
		end

		it("has a 10x10-ish icon for every contract name, upgrade id and rarity", function()
			for _, name in contract do
				local def = Icons.get(name)
				expect(isDef(def)).toBe(true)
				expect(def.w >= 8 and def.w <= 12 and def.h >= 8 and def.h <= 12).toBe(true)
				expect(#def.frames >= 1).toBe(true)
				expect(table.find(Icons.Names, name) ~= nil).toBe(true)
			end
		end)

		it("draws every icon differently", function()
			local seen = {}
			for _, name in contract do
				local def = Icons.get(name)
				local parts = {}
				for _, r in def.rects[1] do
					table.insert(
						parts,
						string.format("%d,%d,%d,%d,%s", r.x, r.y, r.w, r.h, hex(def.palette[r.key]))
					)
				end
				local key = table.concat(parts, ";")
				expect(seen[key] or name).toBe(name)
				seen[key] = name
			end
		end)

		it("stays within the rect budget", function()
			for _, name in contract do
				expect(maxCost(Icons.get(name))).toBeLessThan(BUDGET + 1)
			end
		end)

		it("outlines every icon in Ink", function()
			for _, name in contract do
				local def = Icons.get(name)
				expect(if def.palette.k == Palette.Ink then name else name .. " outline").toBe(name)
				-- pixels on the outside of the silhouette (found by flooding the transparent
				-- area from the border) are Ink, but for the odd accent such as speed lines
				local rows = def.frames[1]
				local function at(x, y)
					if y < 1 or y > def.h or x < 1 or x > def.w then
						return nil
					end
					return string.sub(rows[y], x, x)
				end
				local outside, stack = {}, {}
				for x = 0, def.w + 1 do
					table.insert(stack, { x, 0 })
					table.insert(stack, { x, def.h + 1 })
				end
				for y = 1, def.h do
					table.insert(stack, { 0, y })
					table.insert(stack, { def.w + 1, y })
				end
				while #stack > 0 do
					local p = table.remove(stack)
					local x, y = p[1], p[2]
					local k = x .. ":" .. y
					local c = at(x, y)
					if not outside[k] and x >= 0 and y >= 0 and x <= def.w + 1 and y <= def.h + 1 then
						if c == nil or c == "." then
							outside[k] = true
							table.insert(stack, { x + 1, y })
							table.insert(stack, { x - 1, y })
							table.insert(stack, { x, y + 1 })
							table.insert(stack, { x, y - 1 })
						end
					end
				end
				local edge, ink = 0, 0
				for y = 1, def.h do
					for x = 1, def.w do
						local c = at(x, y)
						if
							c ~= "."
							and (
								outside[(x - 1) .. ":" .. y]
								or outside[(x + 1) .. ":" .. y]
								or outside[x .. ":" .. (y - 1)]
								or outside[x .. ":" .. (y + 1)]
							)
						then
							edge += 1
							if def.palette[c] == Palette.Ink then
								ink += 1
							end
						end
					end
				end
				expect(if ink >= edge * 0.8 then name else string.format("%s %d/%d", name, ink, edge)).toBe(
					name
				)
			end
		end)

		it("returns a placeholder for unknown names", function()
			local def = Icons.get("no_such_icon")
			expect(isDef(def)).toBe(true)
			expect(def.w).toBe(10)
		end)

		it("is deterministic", function()
			for _, name in contract do
				expect(Icons.get(name)).toBe(Icons.get(name))
			end
		end)
	end)

	describe("Art Fx", function()
		it("has the contract sprites with their sizes and frame counts", function()
			local orb = Fx.orb(Palette.Orchid)
			expect(orb.w).toBe(6)
			expect(orb.h).toBe(6)
			expect(#orb.frames).toBe(2)
			expect(#Fx.spark.frames).toBe(3)
			expect(#Fx.coin.frames).toBe(4)
			local slash = Fx.slash(Palette.Cyan)
			expect(#slash.frames).toBe(3)
			expect(isDef(Fx.bolt(Palette.Sky))).toBe(true)
			expect(isDef(Fx.spark) and isDef(Fx.coin)).toBe(true)
		end)

		it("makes orbs, slashes and bolts for every Sorcerer's technique colour, in colour", function()
			for _, s in Sorcerers.List do
				for _, def in { Fx.orb(s.color), Fx.slash(s.color), Fx.bolt(s.color) } do
					expect(isDef(def)).toBe(true)
					expect(maxCost(def)).toBeLessThan(BUDGET + 1)
				end
				-- a saturated technique colour never turns into a grey orb
				local function saturation(c)
					local mx, mn = math.max(c.R, c.G, c.B), math.min(c.R, c.G, c.B)
					return if mx > 0 then (mx - mn) / mx else 0
				end
				if saturation(s.color) > 0.3 then
					expect(saturation(Fx.orb(s.color).palette.o) > 0.25).toBe(true)
				end
			end
			local violet = Fx.orb(Color3.fromRGB(180, 100, 255)).palette.o
			expect(violet ~= Palette.Slate and violet ~= Palette.Mist).toBe(true)
		end)

		it("never draws an orb in the lane's or the floor's colours", function()
			local lane =
				{ Palette.Steel, Palette.Dusk, Palette.Night, Palette.Ink, Palette.Slate, Palette.Mist }
			for _, s in Sorcerers.List do
				local orb = Fx.orb(s.color)
				for _, c in lane do
					expect(if orb.palette.o == c then s.id else "").toBe("")
				end
				expect(if orb.palette.o == Palette.Tan or orb.palette.l == Palette.Tan then s.id else "").toBe(
					""
				)
				-- an Ink ring in both frames
				for _, rows in orb.frames do
					expect(rows[1]).toBe(".kkkk.")
					expect(rows[6]).toBe(".kkkk.")
				end
				expect(orb.palette.k).toBe(Palette.Ink)
			end
			-- lavender and violet techniques keep a purple body
			local shion = Fx.orb(Color3.fromRGB(170, 140, 255)).palette
			expect(shion.o).toBe(Palette.Orchid)
			expect(shion.d).toBe(Palette.Plum)
		end)

		it("draws the slash as a crescent tapering to points inside its box", function()
			for _, s in Sorcerers.List do
				local rows = Fx.slash(s.color).frames[2]
				expect(rows[1]).toBe(string.rep(".", 16))
				expect(rows[16]).toBe(string.rep(".", 16))
				local mid = string.gsub(rows[9], "%.", "")
				expect(#mid >= 4).toBe(true)
				local _, base = string.gsub(table.concat(rows), "o", "")
				expect(base >= 20).toBe(true) -- mostly the technique colour
			end
		end)

		it("stays within the rect budget", function()
			for _, def in
				{ Fx.orb(Palette.Amber), Fx.spark, Fx.coin, Fx.slash(Palette.Red), Fx.bolt(Palette.Yellow) }
			do
				expect(maxCost(def)).toBeLessThan(BUDGET + 1)
			end
		end)

		it("draws a one-pixel ring with no gaps or overlaps", function()
			for _, r in { 1, 3, 8, 20, 52 } do
				local c = Canvas.new()
				Fx.ring(c, 100, 100, r, Palette.Yellow)
				local covered = {}
				local count = 0
				for _, rect in c.rects do
					for x = rect.x, rect.x + rect.w - 1 do
						for y = rect.y, rect.y + rect.h - 1 do
							local k = x .. ":" .. y
							expect(covered[k]).toBe(nil)
							covered[k] = true
							count += 1
							local d = math.sqrt((x - 100) ^ 2 + (y - 100) ^ 2)
							expect(math.abs(d - r) < 1).toBe(true)
						end
					end
				end
				-- the cardinal points are on the ring and it is symmetric
				expect(
					covered[(100 + r) .. ":100"]
						and covered[(100 - r) .. ":100"]
						and covered["100:" .. (100 + r)]
						and covered["100:" .. (100 - r)]
				).toBe(true)
				for k in covered do
					local x, y = string.match(k, "^(-?%d+):(-?%d+)$")
					expect(
						covered[(200 - tonumber(x)) .. ":" .. y] and covered[x .. ":" .. (200 - tonumber(y))]
					).toBe(true)
				end
				expect(count >= 4 * r).toBe(true)
				-- merged runs keep it cheap
				expect(#c.rects <= math.max(8, 3 * r)).toBe(true)
			end
		end)

		it("draws a light pillar rising from its foot", function()
			local c = Canvas.new()
			Fx.pillar(c, 50, 200, 10, 80, Palette.Orchid)
			expect(#c.rects > 0 and #c.rects <= 16).toBe(true)
			expect(outside(c, 50 - 5 - 3, 120, 50 + 5 + 3, 201)).toBe(nil)
			local _, y0, _, y1 = c:bounds()
			expect(y0).toBe(120)
			expect(y1 <= 201).toBe(true)
		end)

		it("is deterministic", function()
			local a, b = Canvas.new(), Canvas.new()
			Fx.ring(a, 10, 10, 9, Palette.Cyan)
			Fx.pillar(a, 10, 50, 6, 30, Palette.Amber)
			Fx.ring(b, 10, 10, 9, Palette.Cyan)
			Fx.pillar(b, 10, 50, 6, 30, Palette.Amber)
			expect(dump(a)).toBe(dump(b))
			expect(Fx.orb(Palette.Cyan)).toBe(Fx.orb(Palette.Cyan))
		end)
	end)
end
