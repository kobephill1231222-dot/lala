--!nocheck
-- Unit tests for the pure game rules (economy, profile schema, actions, tutorial).
return function(ctx)
	local kit, sb = ctx.kit, ctx.sandbox
	local describe, it, expect = kit.describe, kit.it, kit.expect

	local Economy = sb.requirePath("ReplicatedStorage/Shared/Rules/Economy")
	local Actions = sb.requirePath("ReplicatedStorage/Shared/Rules/Actions")
	local Schema = sb.requirePath("ReplicatedStorage/Shared/Rules/ProfileSchema")
	local Tutorial = sb.requirePath("ReplicatedStorage/Shared/Rules/Tutorial")
	local Prng = sb.requirePath("ReplicatedStorage/Shared/Util/Prng")
	local Format = sb.requirePath("ReplicatedStorage/Shared/Util/Format")
	local RateLimiter = sb.requirePath("ReplicatedStorage/Shared/Util/RateLimiter")
	local GameConfig = sb.requirePath("ReplicatedStorage/Shared/Config/GameConfig")
	local Characters = sb.requirePath("ReplicatedStorage/Shared/Config/Characters")
	local Banners = sb.requirePath("ReplicatedStorage/Shared/Config/Banners")

	local T0 = 1_700_000_000

	describe("ProfileSchema", function()
		it("creates a new profile with the starter spirit placed and a pre-filled well", function()
			local p = Schema.new(T0)
			expect(p.units["1"].id).toBe("tomo")
			expect(p.spots["1"]).toBe("1")
			expect(p.well.stored).toBe(GameConfig.WellStartingEnergy)
			expect(p.unlockedSpots).toBe(2)
			expect(p.tutorial).toBe(1)
		end)

		it("repairs malformed values without losing valid data", function()
			local raw = {
				energy = 0 / 0,
				seals = -5,
				units = { ["4"] = { id = "suzu", level = 999 }, ["5"] = { id = "deleted_char", level = 3 }, ["6"] = "junk" },
				nextUid = 2,
				spots = { ["1"] = "4", ["2"] = "5", ["9"] = "4", ["3"] = "missing" },
				unlockedSpots = 50,
				upgrades = { production = -3, capacity = 2.7, luck = "x" },
				well = { stored = math.huge, t = T0 + 10_000 },
				tutorial = 99,
				settings = { music = "yes" },
			}
			local p, issues = Schema.sanitize(raw, T0)
			expect(p.energy).toBe(0)
			expect(p.seals).toBe(0)
			expect(p.units["4"].level).toBe(15) -- clamped to Rare max level
			expect(p.units["5"]).toBe(nil)
			expect(p.orphanUnits["5"].id).toBe("deleted_char") -- preserved, not deleted
			expect(p.nextUid).toBe(7)
			expect(p.unlockedSpots).toBe(10)
			expect(p.spots["1"]).toBe("4")
			expect(p.spots["2"]).toBe(nil) -- orphan unit can't be placed
			expect(p.upgrades.production).toBe(0)
			expect(p.upgrades.capacity).toBe(2)
			expect(p.upgrades.luck).toBe(0)
			expect(p.well.stored).toBe(0)
			expect(p.well.t).toBe(T0) -- future timestamps are clamped
			expect(p.tutorial).toBe(Tutorial.Done)
			expect(p.settings.music).toBe(true)
			expect(#issues).toBeGreaterThan(0)
		end)

		it("places each unit on at most one spot", function()
			local raw = Schema.new(T0)
			raw.unlockedSpots = 3
			raw.spots["2"] = "1"
			raw.spots["3"] = "1"
			local p = Schema.sanitize(raw, T0)
			local count = 0
			for _, uid in p.spots do
				if uid == "1" then
					count += 1
				end
			end
			expect(count).toBe(1)
		end)

		it("restores orphan units whose character exists again", function()
			local raw = Schema.new(T0)
			raw.orphanUnits = { ["9"] = { id = "kaito", level = 4 } }
			local p = Schema.sanitize(raw, T0)
			expect(p.units["9"].id).toBe("kaito")
			expect(p.nextUid).toBe(10)
		end)

		it("round-trips a sanitized profile unchanged", function()
			local p = Schema.new(T0)
			local again = Schema.sanitize(p, T0)
			expect(again.units["1"].id).toBe("tomo")
			expect(again.spots["1"]).toBe("1")
			expect(again.well.stored).toBe(p.well.stored)
		end)
	end)

	describe("Economy", function()
		it("computes unit rates with level and production upgrades", function()
			local p = Schema.new(T0)
			expect(Economy.totalRate(p)).toBeNear(1.0)
			p.units["1"].level = 3
			expect(Economy.totalRate(p)).toBeNear(1.5)
			p.upgrades.production = 2
			expect(Economy.totalRate(p)).toBeNear(1.8)
		end)

		it("scales well capacity with output but never below the minimum", function()
			local p = Schema.new(T0)
			expect(Economy.wellCapacity(p)).toBe(GameConfig.WellBaseSeconds) -- 1/s * base seconds
			p.spots = {}
			expect(Economy.wellCapacity(p)).toBe(GameConfig.WellMinCapacity)
			p.spots["1"] = "1"
			p.upgrades.capacity = 2
			expect(Economy.wellCapacity(p)).toBe(GameConfig.WellBaseSeconds + 2 * GameConfig.WellSecondsPerLevel)
		end)

		it("prices upgrades and stops at max level", function()
			expect(Economy.upgradeCost("production", 0)).toBe(40)
			expect(Economy.upgradeCost("production", 30)).toBe(nil)
			expect(Economy.upgradeCost("nope", 0)).toBe(nil)
		end)

		it("normalises banner chances to 1 and luck raises high rarities", function()
			for _, banner in Banners.List do
				local sum = 0
				for _, c in Economy.rarityChances(banner.id, 0) do
					sum += c
				end
				expect(sum).toBeNear(1, 1e-9)
			end
			local base = Economy.rarityChances("lantern", 0)
			local lucky = Economy.rarityChances("lantern", 10)
			expect(lucky.Epic).toBeGreaterThan(base.Epic)
			expect(lucky.Legendary).toBeGreaterThan(base.Legendary)
			expect(lucky.Common).toBeLessThan(base.Common)
		end)

		it("formats numbers for the HUD", function()
			expect(Format.abbreviate(999)).toBe("999")
			expect(Format.abbreviate(1234)).toBe("1.23K")
			expect(Format.abbreviate(45_600_000)).toBe("45.6M")
			expect(Format.abbreviate(2.5)).toBe("2.5")
			expect(Format.commas(1234567)).toBe("1,234,567")
		end)
	end)

	describe("Actions", function()
		it("collects the pre-filled well and accrues over time", function()
			local p = Schema.new(T0)
			local ok, res = Actions.collect(p, T0)
			expect(ok).toBe(true)
			expect(res.amount).toBe(60)
			expect(p.energy).toBe(60)
			local ok2 = Actions.collect(p, T0)
			expect(ok2).toBe(false)
			local ok3, res3 = Actions.collect(p, T0 + 30)
			expect(ok3).toBe(true)
			expect(res3.amount).toBe(30)
		end)

		it("caps well accrual at capacity", function()
			local p = Schema.new(T0)
			p.well.stored = 0
			Actions.settleWell(p, T0 + 100_000)
			expect(p.well.stored).toBe(Economy.wellCapacity(p))
		end)

		it("guarantees a Rare on the very first Lantern Ritual and charges energy", function()
			local p = Schema.new(T0)
			p.energy = 50
			local ok, res = Actions.summon(p, "lantern", 1, Prng.new(1), T0)
			expect(ok).toBe(true)
			expect(res.units[1].rarity).toBe("Rare")
			expect(p.energy).toBe(0)
			expect(p.units[res.units[1].uid]).toBeTruthy()
			expect(res.units[1].isNew).toBe(true)
		end)

		it("rejects summons the player cannot afford or that are malformed", function()
			local p = Schema.new(T0)
			p.energy = 10
			expect((Actions.summon(p, "lantern", 1, Prng.new(1), T0))).toBe(false)
			p.energy = 1e9
			expect((Actions.summon(p, "lantern", 2, Prng.new(1), T0))).toBe(false)
			expect((Actions.summon(p, "lantern", "1", Prng.new(1), T0))).toBe(false)
			expect((Actions.summon(p, "nope", 1, Prng.new(1), T0))).toBe(false)
			expect((Actions.summon(p, "sealed", 1, Prng.new(1), T0))).toBe(false) -- no seals
			expect(p.energy).toBe(1e9)
		end)

		it("enforces the roster limit", function()
			local p = Schema.new(T0)
			p.energy = 1e12
			for i = 2, GameConfig.InventoryLimit do
				p.units[tostring(i)] = { id = "ren", level = 1 }
			end
			local ok = Actions.summon(p, "lantern", 1, Prng.new(1), T0)
			expect(ok).toBe(false)
		end)

		it("applies pity after the threshold", function()
			local p = Schema.new(T0)
			p.energy = 1e12
			p.stats.summons = 10
			p.pity = Banners.PityThreshold - 1
			local rng = { NextNumber = function() return 0 end } -- would always roll Common
			local ok, res = Actions.summon(p, "lantern", 1, rng, T0)
			expect(ok).toBe(true)
			expect(res.units[1].rarity == "Legendary" or res.units[1].rarity == "Mythic").toBe(true)
			expect(p.pity).toBe(0)
		end)

		it("produces roughly the advertised odds", function()
			local p = Schema.new(T0)
			p.energy = 1e15
			p.stats.summons = 1
			local rng = Prng.new(42)
			local counts = {}
			local n = 20000
			for _ = 1, n do
				p.pity = 0
				local _, res = Actions.summon(p, "lantern", 1, rng, T0)
				local r = res.units[1].rarity
				counts[r] = (counts[r] or 0) + 1
				p.units[res.units[1].uid] = nil
			end
			expect((counts.Common or 0) / n).toBeNear(0.72, 0.02)
			expect((counts.Rare or 0) / n).toBeNear(0.24, 0.02)
			expect(counts.Mythic or 0).toBe(0)
		end)

		it("places, swaps and unplaces units while settling the well", function()
			local p = Schema.new(T0)
			p.units["2"] = { id = "suzu", level = 1 }
			p.unlockedSpots = 3
			expect((Actions.place(p, "2", 4, T0))).toBe(false) -- sealed
			expect((Actions.place(p, "2", 1.5, T0))).toBe(false)
			expect((Actions.place(p, "9", 2, T0))).toBe(false)
			local ok = Actions.place(p, "2", 2, T0 + 10)
			expect(ok).toBe(true)
			expect(p.well.stored).toBe(60 + 10) -- tomo produced for 10s before the change
			-- Move suzu onto tomo's spot: they swap.
			local ok2, res2 = Actions.place(p, "2", 1, T0 + 10)
			expect(ok2).toBe(true)
			expect(res2.swapped).toBe(true)
			expect(p.spots["1"]).toBe("2")
			expect(p.spots["2"]).toBe("1")
			local ok3 = Actions.unplace(p, 2, T0 + 10)
			expect(ok3).toBe(true)
			expect(p.spots["2"]).toBe(nil)
		end)

		it("trains units up to their max level", function()
			local p = Schema.new(T0)
			p.energy = 1e9
			for _ = 1, 20 do
				Actions.train(p, "1", T0)
			end
			expect(p.units["1"].level).toBe(10)
			local ok, msg = Actions.train(p, "1", T0)
			expect(ok).toBe(false)
			expect(msg).toBe("Already at max level.")
		end)

		it("refuses to release the last unit and refunds otherwise", function()
			local p = Schema.new(T0)
			expect((Actions.release(p, "1", T0))).toBe(false)
			p.units["2"] = { id = "suzu", level = 3 }
			p.spots["2"] = "2"
			local ok, res = Actions.release(p, "2", T0)
			expect(ok).toBe(true)
			expect(res.value).toBe(80)
			expect(p.spots["2"]).toBe(nil)
			expect(p.energy).toBe(80)
		end)

		it("buys upgrades and unlocks spots in order", function()
			local p = Schema.new(T0)
			p.energy = 40
			expect((Actions.buyUpgrade(p, "production", T0))).toBe(true)
			expect(p.upgrades.production).toBe(1)
			expect(p.energy).toBe(0)
			expect((Actions.buyUpgrade(p, "production", T0))).toBe(false)
			p.energy = 120
			local ok, res = Actions.unlockSpot(p, T0)
			expect(ok).toBe(true)
			expect(res.spot).toBe(3)
			p.unlockedSpots = 10
			p.energy = 1e12
			expect((Actions.unlockSpot(p, T0))).toBe(false)
		end)
	end)

	describe("Tutorial", function()
		it("advances only on the matching event and grants rewards", function()
			local p = Schema.new(T0)
			expect((Tutorial.advance(p, "summon"))).toBe(nil)
			expect(p.tutorial).toBe(1)
			Tutorial.advance(p, "collect")
			Tutorial.advance(p, "summon")
			local energy = p.energy
			local step, reward = Tutorial.advance(p, "place")
			expect(step.event).toBe("place")
			expect(reward.energy).toBe(60)
			expect(p.energy).toBe(energy + 60)
			Tutorial.skip(p)
			expect(p.tutorial).toBe(Tutorial.Done)
			expect((Tutorial.advance(p, "kill"))).toBe(nil)
		end)
	end)

	describe("RateLimiter", function()
		it("allows a burst then throttles and refills", function()
			local rl = RateLimiter.new(2, 3)
			expect(rl:allow("a", 0)).toBe(true)
			expect(rl:allow("a", 0)).toBe(true)
			expect(rl:allow("a", 0)).toBe(true)
			expect(rl:allow("a", 0)).toBe(false)
			expect(rl:allow("b", 0)).toBe(true)
			expect(rl:allow("a", 0.5)).toBe(true)
			expect(rl:allow("a", 0.5)).toBe(false)
		end)
	end)

	describe("Catalogue", function()
		it("has characters for every rarity a banner can roll", function()
			for _, banner in Banners.List do
				for rarity, w in banner.weights do
					if w > 0 then
						expect(Characters.ByRarity[rarity] ~= nil and #Characters.ByRarity[rarity] > 0).toBe(true)
					end
				end
			end
		end)
	end)
end
