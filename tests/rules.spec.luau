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
	local Sorcerers = sb.requirePath("ReplicatedStorage/Shared/Config/Sorcerers")
	local Crates = sb.requirePath("ReplicatedStorage/Shared/Config/Crates")
	local Rarities = sb.requirePath("ReplicatedStorage/Shared/Config/Rarities")

	local T0 = 1_700_000_000

	-- New profile with the starter crate opened and Kai on slot 1.
	local function starterFarm()
		local p = Schema.new(T0)
		Actions.placeCrate(p, "1", 1, T0)
		local ok, res = Actions.openCrate(p, 1, Prng.new(1), T0 + 10)
		assert(ok, res)
		Actions.placeSorcerer(p, res.uid, 1, T0 + 10)
		return p, res.uid
	end

	describe("ProfileSchema", function()
		it("starts a new player with one unplaced Starter Crate and nothing else", function()
			local p = Schema.new(T0)
			expect(p.crates["1"].tier).toBe("starter")
			expect(p.crates["1"].pad).toBe(nil)
			expect(Actions.countUnits(p)).toBe(0)
			expect(p.cash).toBe(0)
			expect(p.nextCid).toBe(2)
			expect(p.box.orbs).toBe(0)
			expect(p.tutorial).toBe(1)
		end)

		it("repairs malformed values without losing valid data", function()
			local raw = {
				cash = 0 / 0,
				units = {
					["4"] = { id = "suzu", level = 999 },
					["5"] = { id = "deleted_char", level = 3 },
					["6"] = "junk",
				},
				nextUid = 2,
				slots = { ["1"] = "4", ["2"] = "5", ["9"] = "4", ["3"] = "missing" },
				crates = {
					["2"] = { tier = "rare", pad = 1, readyAt = T0 + 50 },
					["3"] = { tier = "basic", pad = 1, readyAt = T0 + 10 }, -- pad taken
					["4"] = { tier = "gone" },
					["5"] = { tier = "basic", pad = 4, readyAt = T0 }, -- pad locked
				},
				upgrades = { orbValue = -3, boxSize = 2.7, luck = "x", slots = 99 },
				box = { orbs = math.huge, value = -1, t = T0 + 10_000 },
				carried = { orbs = 3.5, value = 12 },
				tutorial = 99,
				settings = { music = "yes" },
			}
			local p, issues = Schema.sanitize(raw, T0)
			expect(p.cash).toBe(0)
			expect(p.units["4"].level).toBe(20) -- clamped to Rare max level
			expect(p.units["5"]).toBe(nil)
			expect(p.orphanUnits["5"].id).toBe("deleted_char") -- preserved, not deleted
			expect(p.nextUid).toBe(7)
			expect(p.upgrades.orbValue).toBe(0)
			expect(p.upgrades.boxSize).toBe(2)
			expect(p.upgrades.luck).toBe(0)
			expect(p.upgrades.slots).toBe(7)
			expect(p.slots["1"]).toBe("4")
			expect(p.slots["2"]).toBe(nil) -- orphan can't be placed
			expect(p.slots["9"]).toBe(nil) -- same sorcerer twice
			expect(p.crates["2"].pad).toBe(1)
			expect(p.crates["2"].readyAt).toBe(T0 + 50)
			expect(p.crates["3"].pad).toBe(nil) -- returned to inventory
			expect(p.crates["4"]).toBe(nil)
			expect(p.crates["5"].pad).toBe(nil)
			expect(p.nextCid).toBe(6)
			expect(p.box.orbs).toBe(0)
			expect(p.box.value).toBe(0)
			expect(p.box.t).toBe(T0) -- future timestamps are clamped
			expect(p.carried.orbs).toBe(3)
			expect(p.tutorial).toBe(Tutorial.Done)
			expect(p.settings.music).toBe(true)
			expect(#issues).toBeGreaterThan(0)
		end)

		it("restores orphaned sorcerers whose definition exists again", function()
			local raw = Schema.new(T0)
			raw.orphanUnits = { ["9"] = { id = "ryo", level = 4 } }
			local p = Schema.sanitize(raw, T0)
			expect(p.units["9"].id).toBe("ryo")
			expect(p.units["9"].level).toBe(4)
			expect(p.nextUid).toBe(10)
		end)

		it("round-trips a mid-game profile unchanged", function()
			local p = starterFarm()
			Actions.settleBox(p, T0 + 40)
			p.cash = 500
			Actions.buyCrate(p, "basic")
			Actions.placeCrate(p, "2", 2, T0 + 40)
			local again = Schema.sanitize(p, T0 + 41)
			expect(again.slots["1"]).toBe(p.slots["1"])
			expect(again.crates["2"].pad).toBe(2)
			expect(again.crates["2"].readyAt).toBe(p.crates["2"].readyAt)
			expect(again.box.orbs).toBe(p.box.orbs)
			expect(again.box.t).toBe(p.box.t)
			expect(again.cash).toBe(440)
		end)
	end)

	describe("Economy", function()
		it("computes Orb Value with sorcerer level and the Orb Value upgrade", function()
			local unit = { id = "kai", level = 1 }
			local p = Schema.new(T0)
			expect(Economy.orbValue(unit, p)).toBe(2)
			unit.level = 6
			expect(Economy.orbValue(unit, p)).toBeNear(4, 1e-9) -- +20%/level
			p.upgrades.orbValue = 5
			expect(Economy.orbValue(unit, p)).toBeNear(6, 1e-9) -- x1.5
			expect(Economy.income(unit, p)).toBeNear(6, 1e-9) -- 1 orb/s
		end)

		it("fills the Orb Box at Orbs per Second up to its capacity", function()
			local p = starterFarm()
			local t1 = T0 + 10
			local orbs, value = Economy.boxAt(p, t1 + 15)
			expect(orbs).toBeNear(15, 1e-9)
			expect(value).toBeNear(30, 1e-9)
			local cap = Economy.boxCapacity(p)
			expect(cap).toBe(GameConfig.BoxBaseCapacity)
			orbs = Economy.boxAt(p, t1 + 10_000)
			expect(orbs).toBe(cap)
			p.upgrades.boxSize = 2
			expect(Economy.boxCapacity(p)).toBe(math.floor(60 * 1.35 ^ 2))
		end)

		it("applies the Opening Speed upgrade with a floor", function()
			local p = Schema.new(T0)
			expect(Economy.openingTime("basic", p)).toBe(30)
			p.upgrades.openSpeed = 5
			expect(Economy.openingTime("basic", p)).toBe(21) -- 30 * 0.7
			p.upgrades.openSpeed = 10
			expect(Economy.openingTime("basic", p)).toBe(12) -- capped at -60%
			expect(Economy.openingTime("starter", p)).toBe(4)
		end)

		it("prices upgrades, including fixed-cost ones, and stops at max level", function()
			expect(Economy.upgradeCost("orbValue", 0)).toBe(25)
			expect(Economy.upgradeCost("orbValue", 1)).toBe(36)
			expect(Economy.upgradeCost("slots", 0)).toBe(150)
			expect(Economy.upgradeCost("slots", 6)).toBe(3000000)
			expect(Economy.upgradeCost("slots", 7)).toBe(nil)
			expect(Economy.upgradeCost("nope", 0)).toBe(nil)
		end)

		it("normalises crate chances to 1 and Luck raises rare chances", function()
			for _, crate in Crates.List do
				local sum = 0
				for _, c in Economy.crateChances(crate.id, 0) do
					sum += c
				end
				expect(sum).toBeNear(1, 1e-9)
			end
			local base = Economy.crateChances("epic", 0)
			local lucky = Economy.crateChances("epic", 10)
			expect(lucky.Legendary).toBeGreaterThan(base.Legendary)
			expect(lucky.Uncommon).toBeLessThan(base.Uncommon)
		end)

		it("formats numbers for the HUD", function()
			expect(Format.abbreviate(999)).toBe("999")
			expect(Format.abbreviate(1234)).toBe("1.23K")
			expect(Format.abbreviate(45_600_000)).toBe("45.6M")
			expect(Format.cash(950)).toBe("$950")
			expect(Format.cash(12_000)).toBe("$12.0K")
			expect(Format.clock(42)).toBe("0:42")
			expect(Format.clock(245.2)).toBe("4:06")
			expect(Format.clock(3729)).toBe("1:02:09")
		end)
	end)

	describe("Crates", function()
		it("places the Starter Crate, refuses to open early, then gives Kai", function()
			local p = Schema.new(T0)
			local ok, res = Actions.placeCrate(p, "1", 1, T0)
			expect(ok).toBe(true)
			expect(res.readyAt).toBe(T0 + 10)
			local early = Actions.openCrate(p, 1, Prng.new(1), T0 + 9.5)
			expect(early).toBe(false)
			local opened
			ok, opened = Actions.openCrate(p, 1, Prng.new(1), T0 + 10)
			expect(ok).toBe(true)
			expect(opened.id).toBe(Sorcerers.StarterId)
			expect(opened.rarity).toBe("Common")
			expect(opened.isNew).toBe(true)
			expect(p.crates["1"]).toBe(nil)
			expect(p.units[opened.uid].level).toBe(1)
			expect(p.stats.cratesOpened).toBe(1)
		end)

		it("keeps opening while offline: timestamps are absolute", function()
			local p = Schema.new(T0)
			Actions.placeCrate(p, "1", 1, T0)
			local saved = Schema.sanitize(p, T0 + 5) -- "log out" and back in much later
			local ok = Actions.openCrate(saved, 1, Prng.new(1), T0 + 3600)
			expect(ok).toBe(true)
		end)

		it("validates pads: locked, occupied, and bad input", function()
			local p = Schema.new(T0)
			p.cash = 1000
			Actions.buyCrate(p, "basic")
			expect((Actions.placeCrate(p, "1", 3, T0))).toBe(false) -- pad 3 locked
			expect((Actions.placeCrate(p, "1", 0, T0))).toBe(false)
			expect((Actions.placeCrate(p, "1", 1.5, T0))).toBe(false)
			expect((Actions.placeCrate(p, "1", "1", T0))).toBe(false)
			expect((Actions.placeCrate(p, "1", 1, T0))).toBe(true)
			expect((Actions.placeCrate(p, "2", 1, T0))).toBe(false) -- occupied
			expect((Actions.placeCrate(p, "1", 2, T0))).toBe(false) -- already placed
			expect((Actions.placeCrate(p, "99", 2, T0))).toBe(false)
			p.upgrades.pads = 1
			expect((Actions.placeCrate(p, "2", 3, T0))).toBe(true)
		end)

		it("picks a crate up keeping its remaining Opening Time", function()
			local p = Schema.new(T0)
			Actions.placeCrate(p, "1", 1, T0)
			local ok = Actions.pickUpCrate(p, 1, T0 + 4)
			expect(ok).toBe(true)
			expect(p.crates["1"].pad).toBe(nil)
			expect(p.crates["1"].remaining).toBe(6)
			local _, res = Actions.placeCrate(p, "1", 2, T0 + 100)
			expect(res.readyAt).toBe(T0 + 106)
			expect((Actions.pickUpCrate(p, 1, T0))).toBe(false)
		end)

		it("charges Cash for crates and enforces the crate limit", function()
			local p = Schema.new(T0)
			expect((Actions.buyCrate(p, "basic"))).toBe(false)
			expect((Actions.buyCrate(p, "starter"))).toBe(false) -- not for sale
			expect((Actions.buyCrate(p, "missing"))).toBe(false)
			p.cash = 1e9
			for _ = 1, GameConfig.CrateLimit - 1 do
				expect((Actions.buyCrate(p, "basic"))).toBe(true)
			end
			expect((Actions.buyCrate(p, "basic"))).toBe(false)
			expect(p.cash).toBe(1e9 - 60 * (GameConfig.CrateLimit - 1))
			expect(p.stats.cratesBought).toBe(GameConfig.CrateLimit - 1)
		end)

		it("produces roughly the advertised odds", function()
			local p = Schema.new(T0)
			p.crates = {}
			local rng = Prng.new(42)
			local counts = {}
			local n = 20000
			for i = 1, n do
				p.crates[tostring(i)] = { tier = "basic", pad = 1, readyAt = T0 }
				local ok, res = Actions.openCrate(p, 1, rng, T0)
				assert(ok, res)
				counts[res.rarity] = (counts[res.rarity] or 0) + 1
				p.units[res.uid] = nil
			end
			expect((counts.Common or 0) / n).toBeNear(0.75, 0.02)
			expect((counts.Uncommon or 0) / n).toBeNear(0.22, 0.02)
			expect((counts.Rare or 0) / n).toBeNear(0.03, 0.01)
			expect(counts.Epic or 0).toBe(0)
		end)

		it("refuses to open when the Sorcerer inventory is full", function()
			local p = Schema.new(T0)
			for i = 1, GameConfig.InventoryLimit do
				p.units[tostring(100 + i)] = { id = "kai", level = 1 }
			end
			Actions.placeCrate(p, "1", 1, T0)
			expect((Actions.openCrate(p, 1, Prng.new(1), T0 + 60))).toBe(false)
			expect(p.crates["1"] ~= nil).toBe(true) -- crate kept
		end)
	end)

	describe("Sorcerers", function()
		it("places, swaps and picks up while settling the Orb Box", function()
			local p, kai = starterFarm()
			p.units["50"] = { id = "rei", level = 1 }
			p.upgrades.slots = 1
			-- 20 s of Kai alone
			Actions.placeSorcerer(p, "50", 2, T0 + 30)
			expect(p.box.orbs).toBeNear(20, 1e-9)
			expect(p.box.value).toBeNear(40, 1e-9)
			-- swap
			local ok, res = Actions.placeSorcerer(p, kai, 2, T0 + 30)
			expect(ok).toBe(true)
			expect(p.slots["2"]).toBe(kai)
			expect(p.slots["1"]).toBe("50")
			expect(res.replaced).toBe("50")
			-- locked slot
			expect((Actions.placeSorcerer(p, kai, 5, T0))).toBe(false)
			expect((Actions.placeSorcerer(p, "nope", 1, T0))).toBe(false)
			-- pick up stops production of that sorcerer
			ok = Actions.pickUpSorcerer(p, 1, T0 + 30)
			expect(ok).toBe(true)
			expect(p.slots["1"]).toBe(nil)
			expect((Actions.pickUpSorcerer(p, 1, T0 + 30))).toBe(false)
			local _, ops = nil, Economy.totals(p)
			expect(ops).toBe(1)
		end)

		it("upgrades sorcerers to their max level", function()
			local p, kai = starterFarm()
			p.cash = 1e9
			local max = Rarities.get("Common").maxLevel
			for _ = 2, max do
				expect((Actions.upgradeSorcerer(p, kai, T0 + 20))).toBe(true)
			end
			expect(p.units[kai].level).toBe(max)
			expect((Actions.upgradeSorcerer(p, kai, T0 + 20))).toBe(false)
		end)

		it("refuses to sell the last Sorcerer and pays out otherwise", function()
			local p, kai = starterFarm()
			expect((Actions.sellSorcerer(p, kai, T0 + 20))).toBe(false)
			p.units["50"] = { id = "rei", level = 1 }
			local ok, res = Actions.sellSorcerer(p, kai, T0 + 20)
			expect(ok).toBe(true)
			expect(res.value).toBe(10)
			expect(res.slot).toBe(1)
			expect(p.slots["1"]).toBe(nil)
			expect(p.cash).toBe(10)
		end)
	end)

	describe("Orb Box", function()
		it("collects whole orbs, carries them, and sells them for Cash", function()
			local p = starterFarm()
			expect((Actions.sell(p))).toBe(false)
			local ok, res = Actions.collect(p, T0 + 10 + 12.5)
			expect(ok).toBe(true)
			expect(res.orbs).toBe(12)
			expect(p.box.orbs).toBeNear(0.5, 1e-9)
			expect(p.carried.orbs).toBe(12)
			-- collecting again before selling adds to the carried box
			Actions.collect(p, T0 + 10 + 20)
			expect(p.carried.orbs).toBe(20)
			local sold
			ok, sold = Actions.sell(p)
			expect(ok).toBe(true)
			expect(sold.cash).toBe(40)
			expect(p.cash).toBe(40)
			expect(p.carried.orbs).toBe(0)
			expect(p.stats.orbsSold).toBe(20)
		end)

		it("refuses to collect an empty box", function()
			local p = starterFarm()
			expect((Actions.collect(p, T0 + 10.5))).toBe(false)
		end)

		it("keeps the value orbs were made at when production changes", function()
			local p, kai = starterFarm()
			p.cash = 1e6
			-- 10 orbs at $2, then Orb Value +10%
			Actions.buyUpgrade(p, "orbValue", T0 + 20)
			-- 10 orbs at $2.2
			local _, res = Actions.collect(p, T0 + 30)
			expect(res.orbs).toBe(20)
			expect(res.value).toBeNear(42, 1e-9)
			expect(kai ~= nil).toBe(true)
		end)
	end)

	describe("Offline progress", function()
		it("fills the box for the time away, once", function()
			local p = starterFarm()
			p.upgrades.boxSize = 10 -- capacity 1205, so the time cap is what limits it
			Actions.settleBox(p, T0 + 10)
			local loaded = Schema.sanitize(p, T0 + 610)
			local report = Actions.claimOffline(loaded, T0 + 610)
			expect(report.seconds).toBe(600)
			expect(report.orbs).toBeNear(600, 1e-9)
			expect(report.value).toBeNear(1200, 1e-9)
			-- a second claim in the same session adds nothing
			local again = Actions.claimOffline(loaded, T0 + 610)
			expect(again.orbs).toBe(0)
		end)

		it("caps the time away at MaxOfflineSeconds and the box at its capacity", function()
			local p = starterFarm()
			p.upgrades.boxSize = 25
			Actions.settleBox(p, T0)
			local away = GameConfig.MaxOfflineSeconds * 3
			local report = Actions.claimOffline(p, T0 + away)
			expect(report.capped).toBe(true)
			expect(report.counted).toBe(GameConfig.MaxOfflineSeconds)
			expect(report.orbs).toBeNear(GameConfig.MaxOfflineSeconds, 1e-6)

			local small = starterFarm()
			Actions.settleBox(small, T0)
			report = Actions.claimOffline(small, T0 + 3600)
			expect(report.orbs).toBe(Economy.boxCapacity(small))
			expect(report.boxFull).toBe(true)
		end)

		it("ignores box timestamps from the future", function()
			local p = starterFarm()
			p.box.t = T0 + 99999
			local loaded = Schema.sanitize(p, T0 + 20)
			local report = Actions.claimOffline(loaded, T0 + 20)
			expect(report.orbs).toBe(0)
			expect(loaded.box.t).toBe(T0 + 20)
		end)

		it("reports crates that finished while away", function()
			local p = Schema.new(T0)
			Actions.placeCrate(p, "1", 1, T0)
			p.lastSeen = T0 + 1
			local report = Actions.claimOffline(p, T0 + 600)
			expect(report.cratesReady).toBe(1)
		end)
	end)

	describe("Upgrades", function()
		it("buys farm upgrades and unlocks slots and pads", function()
			local p = Schema.new(T0)
			expect((Actions.buyUpgrade(p, "slots", T0))).toBe(false)
			p.cash = 150
			local ok, res = Actions.buyUpgrade(p, "slots", T0)
			expect(ok).toBe(true)
			expect(res.level).toBe(1)
			expect(Economy.unlockedSlots(p)).toBe(GameConfig.StartingSlots + 1)
			expect(p.cash).toBe(0)
			p.cash = 1e12
			for _ = 2, 7 do
				Actions.buyUpgrade(p, "slots", T0)
			end
			expect(Economy.unlockedSlots(p)).toBe(GameConfig.SlotCount)
			expect((Actions.buyUpgrade(p, "slots", T0))).toBe(false)
			Actions.buyUpgrade(p, "pads", T0)
			Actions.buyUpgrade(p, "pads", T0)
			expect(Economy.unlockedPads(p)).toBe(GameConfig.PadCount)
			expect((Actions.buyUpgrade(p, "pads", T0))).toBe(false)
			expect((Actions.buyUpgrade(p, "teleport", T0))).toBe(false)
		end)
	end)

	describe("Tutorial", function()
		it("walks the whole loop in order and pays its rewards", function()
			local p = Schema.new(T0)
			expect((Tutorial.advance(p, "sell"))).toBe(nil)
			expect(p.tutorial).toBe(1)
			for _, event in { "placeCrate", "openCrate", "placeSorcerer", "collect" } do
				expect(Tutorial.advance(p, event).event).toBe(event)
			end
			local step, reward = Tutorial.advance(p, "sell")
			expect(step.event).toBe("sell")
			expect(reward.cash).toBe(50)
			expect(p.cash).toBe(50)
			Tutorial.advance(p, "buyCrate")
			Tutorial.advance(p, "upgrade")
			expect(p.tutorial).toBe(Tutorial.Done)
			expect(p.cash).toBe(125)
			expect((Tutorial.advance(p, "upgrade"))).toBe(nil)
		end)

		it("can be skipped", function()
			local p = Schema.new(T0)
			Tutorial.skip(p)
			expect(p.tutorial).toBe(Tutorial.Done)
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
		it("has sorcerers for every rarity a crate can roll", function()
			for _, crate in Crates.List do
				for rarity, w in crate.odds do
					if w > 0 then
						expect(Sorcerers.ByRarity[rarity] ~= nil and #Sorcerers.ByRarity[rarity] > 0).toBe(
							true
						)
					end
				end
				if crate.guaranteed then
					expect(Sorcerers.get(crate.guaranteed) ~= nil).toBe(true)
				end
			end
		end)

		it("uses short, distinct sorcerer names", function()
			local seen = {}
			for _, def in Sorcerers.List do
				expect(#def.name <= 6).toBe(true)
				expect(seen[def.name]).toBe(nil)
				seen[def.name] = true
			end
		end)
	end)
end
