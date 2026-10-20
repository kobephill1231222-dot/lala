--!nocheck
-- Unit tests for the grid layout (FarmLayout) and the static world (WorldMap): everything fits,
-- nothing overlaps that shouldn't, every action is reachable within the server's ranges, and
-- art-pixel conversion is exact.
return function(ctx)
	local kit, sb = ctx.kit, ctx.sandbox
	local describe, it, expect = kit.describe, kit.it, kit.expect

	local Layout = sb.requirePath("ReplicatedStorage/Shared/Config/FarmLayout")
	local WorldMap = sb.requirePath("ReplicatedStorage/Shared/Config/WorldMap")
	local GameConfig = sb.requirePath("ReplicatedStorage/Shared/Config/GameConfig")
	local Vector3 = sb.globals.Vector3

	local map = WorldMap.get()

	local function inside(r, outer, margin)
		local m = margin or 0
		return r.x0 >= outer.x0 - m and r.x1 <= outer.x1 + m and r.z0 >= outer.z0 - m and r.z1 <= outer.z1 + m
	end
	local function overlaps(a, b)
		return a.x0 < b.x1 and b.x0 < a.x1 and a.z0 < b.z1 and b.z0 < a.z1
	end
	-- A walk spot as a tiny square, so a solid edge touching it counts but a neighbour doesn't.
	local function point(p)
		return { x0 = p.X - 0.01, z0 = p.Z - 0.01, x1 = p.X + 0.01, z1 = p.Z + 0.01 }
	end
	local function flat(a, b)
		return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end
	local function solids()
		local list = {}
		for _, o in map.objects do
			if o.solid then
				table.insert(list, o)
			end
		end
		return list
	end

	describe("FarmLayout grid", function()
		it("keeps every farm axis-aligned, facing the plaza", function()
			for i = 1, Layout.FarmCount do
				local look = Layout.farmCFrame(i).LookVector
				expect(math.abs(look.X)).toBeLessThan(1e-6)
				local center = Layout.farmCFrame(i).Position
				-- North farms look south (+Z) and sit above the plaza; south farms the reverse.
				expect(look.Z * center.Z < 0).toBeTruthy()
			end
		end)

		it("puts every tile-sized fitting on whole tiles", function()
			for _, v in
				{ Layout.SlotSize, Layout.BoxSize, Layout.FarmWidth, Layout.FarmDepth, Layout.LaneWidth }
			do
				expect(v % Layout.TileStuds).toBe(0)
			end
		end)

		it("puts home, slots, pads and the Orb Box inside the farm, and nowhere else", function()
			for i = 1, Layout.FarmCount do
				local probes = { Layout.homeCFrame(i).Position, Layout.boxWorld(i) }
				for s = 1, 10 do
					table.insert(probes, Layout.slotWorld(i, s).Position)
				end
				for p = 1, 4 do
					table.insert(probes, Layout.padWorld(i, p).Position)
				end
				for _, p in probes do
					expect(Layout.inFarm(i, p)).toBeTruthy()
					for j = 1, Layout.FarmCount do
						if j ~= i then
							expect(Layout.inFarm(j, p)).toBeFalsy()
						end
					end
				end
			end
		end)

		it("lets you Collect from home and from the Collect Pad", function()
			for i = 1, Layout.FarmCount do
				local box = Layout.boxWorld(i)
				expect(flat(Layout.homeCFrame(i).Position, box)).toBeLessThan(GameConfig.CollectRange)
				expect(flat(Layout.farmFloor(i) * Layout.CollectPoint, box)).toBeLessThan(
					GameConfig.CollectRange
				)
			end
		end)

		it("keeps the Sell Stand, shops and farms out of each other's server ranges", function()
			for i = 1, Layout.FarmCount do
				local box = Layout.boxWorld(i)
				expect(flat(box, Layout.SellStand) > GameConfig.SellRange).toBeTruthy()
				expect(flat(box, Layout.CrateShop) > GameConfig.ShopRange).toBeTruthy()
				expect(flat(box, Layout.UpgradeShop) > GameConfig.ShopRange).toBeTruthy()
			end
			expect(flat(Layout.CrateShop, Layout.SellStand) > GameConfig.ShopRange).toBeTruthy()
		end)
	end)

	describe("WorldMap", function()
		it("keeps everything inside the world", function()
			for _, g in map.ground do
				expect(inside(g.rect, map.bounds)).toBeTruthy()
			end
			for _, o in map.objects do
				assert(inside(o.rect, map.bounds), o.kind .. " outside the world")
			end
		end)

		it("doesn't let farms overlap each other or the plaza", function()
			local plaza
			for _, g in map.ground do
				if g.kind == "plaza" then
					plaza = g.rect
				end
			end
			for i, a in map.farms do
				expect(overlaps(a.floor, plaza)).toBeFalsy()
				for j, b in map.farms do
					if i ~= j then
						expect(overlaps(a.floor, b.floor)).toBeFalsy()
					end
				end
			end
		end)

		it(
			"keeps slots, pads, the lane, the Orb Box, the Collect Pad, the sign and the spawn spot inside the fences and apart",
			function()
				local half = Layout.SlotSize / 2
				for _, f in map.farms do
					local inner =
						{ x0 = f.floor.x0 + 1, z0 = f.floor.z0 + 1, x1 = f.floor.x1 - 1, z1 = f.floor.z1 - 1 }
					local home = Layout.homeCFrame(f.index).Position
					local rects = {
						lane = f.lane,
						box = f.box,
						collect = f.collect,
						sign = f.sign,
						home = { x0 = home.X - 1, z0 = home.Z - 1, x1 = home.X + 1, z1 = home.Z + 1 },
					}
					for s, p in f.slots do
						rects["slot" .. s] =
							{ x0 = p.X - half, z0 = p.Z - half, x1 = p.X + half, z1 = p.Z + half }
					end
					local ph = Layout.PadSize / 2
					for p, c in f.pads do
						rects["pad" .. p] = { x0 = c.X - ph, z0 = c.Z - ph, x1 = c.X + ph, z1 = c.Z + ph }
					end
					for name, r in rects do
						assert(
							inside(r, inner, 1e-3),
							name .. " of farm " .. f.index .. " pokes through the fence"
						)
					end
					for a, ra in rects do
						for b, rb in rects do
							if
								a < b and not ((a == "lane" and b == "box") or (a == "box" and b == "lane"))
							then
								assert(not overlaps(ra, rb), a .. " overlaps " .. b .. " on farm " .. f.index)
							end
						end
					end
				end
			end
		)

		it("never blocks a gate, a road, a slot, a pad or the Collect Pad with something solid", function()
			local walk = {}
			for _, g in map.ground do
				if g.kind == "road" then
					table.insert(walk, { name = "road " .. g.farm, rect = g.rect })
				end
			end
			for _, f in map.farms do
				table.insert(walk, { name = "collect " .. f.index, rect = f.collect })
				table.insert(walk, { name = "gate " .. f.index, rect = point(f.gate) })
				for s, p in f.slots do
					table.insert(walk, { name = "slot " .. f.index .. "/" .. s, rect = point(p) })
				end
				for p, c in f.pads do
					table.insert(walk, { name = "pad " .. f.index .. "/" .. p, rect = point(c) })
				end
			end
			table.insert(walk, { name = "sell pad", rect = map.sellPad })
			table.insert(walk, { name = "spawn", rect = point(Layout.SpawnPosition) })
			table.insert(walk, { name = "crate shop spot", rect = point(Layout.CrateShop) })
			table.insert(walk, { name = "upgrade shop spot", rect = point(Layout.UpgradeShop) })
			for _, o in solids() do
				if o.kind ~= "orbBox" then
					for _, w in walk do
						assert(not overlaps(o.rect, w.rect), o.kind .. " blocks " .. w.name)
					end
				end
			end
		end)

		it("puts every shop display within reach of the shop spot", function()
			for _, o in map.objects do
				if o.kind == "display" then
					local c = Vector3.new((o.rect.x0 + o.rect.x1) / 2, 0, (o.rect.z0 + o.rect.z1) / 2)
					expect(flat(c, Layout.CrateShop)).toBeLessThan(GameConfig.ShopRange)
				end
			end
		end)

		it("converts studs to art pixels exactly", function()
			local w, h = WorldMap.pixelSize()
			expect(w).toBe(Layout.WorldHalfWidth * 2 * Layout.PixelsPerStud)
			expect(h).toBe(Layout.WorldHalfDepth * 2 * Layout.PixelsPerStud)
			local x, y = WorldMap.toPixels(-Layout.WorldHalfWidth, -Layout.WorldHalfDepth)
			expect(x).toBe(0)
			expect(y).toBe(0)
			local x2, y2 = WorldMap.toPixels(1, 2)
			expect(x2 - x).toBe((1 + Layout.WorldHalfWidth) * Layout.PixelsPerStud)
			expect(y2 - y).toBe((2 + Layout.WorldHalfDepth) * Layout.PixelsPerStud)
		end)
	end)
end
