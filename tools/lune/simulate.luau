--!nocheck
-- Economy pacing simulation: a greedy bot plays the real rules for N minutes, including
-- the walk to the Sell Stand. Prints milestones and income over time.
-- Usage: lune run tools/lune/simulate.luau build/game.rbxl [minutes]
local process = require("@lune/process")
local Sandbox = require("./lib/Sandbox")

local game = Sandbox.loadPlace(process.args[1] or "build/game.rbxl")
local sb = Sandbox.new(game)
local function req(p)
	return sb.requirePath("ReplicatedStorage/Shared/" .. p)
end
local Economy, Actions, Schema, Tutorial =
	req("Rules/Economy"), req("Rules/Actions"), req("Rules/ProfileSchema"), req("Rules/Tutorial")
local Prng, Format = req("Util/Prng"), req("Util/Format")
local Crates, Sorcerers, Rarities, GameConfig, Upgrades =
	req("Config/Crates"),
	req("Config/Sorcerers"),
	req("Config/Rarities"),
	req("Config/GameConfig"),
	req("Config/Upgrades")

local minutes = tonumber(process.args[2]) or 120
local SELL_TRIP = 22 -- seconds from Orb Box to Sell Stand and back
local rng = Prng.new(7)
local p = Schema.new(0)
local t = 0
local milestones = {}

local function mark(name)
	local key = name:match("^first %a+") or name
	if not milestones[key] then
		milestones[key] = t
		local _, cash = Economy.totals(p)
		print(
			string.format(
				"[%s] %s  (income %s/s, cash %s)",
				Format.duration(t),
				name,
				Format.abbreviate(cash),
				Format.cash(p.cash)
			)
		)
	end
end

local function event(name)
	Tutorial.advance(p, name)
end

-- Expected Cash/s of one level-1 sorcerer from a crate tier.
local function expectedIncome(tier)
	local e = 0
	for rarity, c in Economy.crateChances(tier, Economy.upgradeLevel(p, "luck")) do
		local pool = Sorcerers.ByRarity[rarity] or {}
		local avg = 0
		for _, d in pool do
			avg += d.ops * d.orbValue
		end
		if #pool > 0 then
			e += c * avg / #pool
		end
	end
	return e
end

local function rankedUnits()
	local list = {}
	for uid, unit in p.units do
		table.insert(list, { uid = uid, income = Economy.income(unit, p) })
	end
	table.sort(list, function(a, b)
		return a.income > b.income
	end)
	return list
end

local function arrangeSlots()
	local list = rankedUnits()
	local slots = Economy.unlockedSlots(p)
	for i = 1, slots do
		local best = list[i]
		if best and p.slots[tostring(i)] ~= best.uid then
			if Actions.placeSorcerer(p, best.uid, i, t) then
				event("placeSorcerer")
			end
		end
	end
	-- Sell surplus that will never be placed again (keeps the inventory small).
	for i = slots + 6, #list do
		Actions.sellSorcerer(p, list[i].uid, t)
	end
end

local function handleCrates()
	for pad = 1, Economy.unlockedPads(p) do
		local cid, crate = Actions.crateOnPad(p, pad)
		if crate and t >= crate.readyAt then
			local ok, res = Actions.openCrate(p, pad, rng, t)
			if ok then
				event("openCrate")
				local def = Sorcerers.get(res.id)
				if res.rarity ~= "Common" then
					mark(
						"first " .. res.rarity .. " (" .. def.name .. ", " .. Crates.get(res.tier).name .. ")"
					)
				end
			end
			cid = nil
		end
		if not cid then
			for id, c in p.crates do
				if not c.pad then
					if Actions.placeCrate(p, id, pad, t) then
						event("placeCrate")
					end
					break
				end
			end
		end
	end
end

local function shop()
	local _, income = Economy.totals(p)
	-- Crates: best tier whose price is under ~3 minutes of income (or the first Basic).
	local waiting = 0
	for _, c in p.crates do
		if not c.pad then
			waiting += 1
		end
	end
	if waiting < Economy.unlockedPads(p) then
		for i = #Crates.List, 1, -1 do
			local def = Crates.List[i]
			if def.price > 0 and p.cash >= def.price and (def.price <= income * 180 or def.id == "basic") then
				if Actions.buyCrate(p, def.id) then
					event("buyCrate")
				end
				break
			end
		end
	end
	-- Farm upgrades: buy the cheapest one that is useful right now.
	local placedCount = 0
	for _ in p.slots do
		placedCount += 1
	end
	local candidates = {}
	local function consider(id, useful)
		local cost = Economy.upgradeCost(id, Economy.upgradeLevel(p, id))
		if cost and useful then
			table.insert(candidates, { id = id, cost = cost })
		end
	end
	consider("orbValue", true)
	consider("slots", placedCount >= Economy.unlockedSlots(p) and #rankedUnits() > placedCount)
	consider("boxSize", Economy.boxCapacity(p) < (Economy.totals(p)) * 90)
	consider("pads", true)
	consider("openSpeed", true)
	consider("luck", milestones["first Rare"] ~= nil)
	consider("walkSpeed", false)
	table.sort(candidates, function(a, b)
		return a.cost < b.cost
	end)
	local best = candidates[1]
	if best and p.cash >= best.cost then
		if Actions.buyUpgrade(p, best.id, t) then
			event("upgrade")
			if best.id == "slots" then
				mark(string.format("%d slots", Economy.unlockedSlots(p)))
			end
		end
	end
	-- Sorcerer upgrades when cheap relative to income.
	for _, entry in rankedUnits() do
		local unit = p.units[entry.uid]
		local cost = Economy.unitUpgradeCost(unit)
		if cost and Actions.slotOf(p, entry.uid) and cost <= income * 30 and p.cash >= cost then
			Actions.upgradeSorcerer(p, entry.uid, t)
		end
	end
end

local nextReport = 5 * 60
local lastTrip = 0
while t < minutes * 60 do
	handleCrates()
	arrangeSlots()
	-- Sell trip when the box is half full or a minute has passed.
	local orbs = Economy.boxAt(p, t)
	if orbs >= Economy.boxCapacity(p) * 0.5 or (orbs >= 1 and t - lastTrip >= 60) then
		if Actions.collect(p, t) then
			event("collect")
			t += SELL_TRIP
			if Actions.sell(p) then
				event("sell")
			end
			lastTrip = t
		end
	end
	shop()
	if p.tutorial == Tutorial.Done then
		mark("tutorial done")
	end
	if t >= nextReport then
		local ops, cash = Economy.totals(p)
		local units = 0
		for _ in p.units do
			units += 1
		end
		print(
			string.format(
				"  %3d min: %s orbs/s, %s/s, %d sorcerers, slots %d, pads %d, Orb Value lv %d, box %d",
				t // 60,
				Format.abbreviate(ops),
				Format.cash(cash),
				units,
				Economy.unlockedSlots(p),
				Economy.unlockedPads(p),
				p.upgrades.orbValue,
				Economy.boxCapacity(p)
			)
		)
		nextReport += 5 * 60
	end
	t += 1
end
print(
	"stats",
	p.stats.cratesBought,
	"crates bought,",
	p.stats.cratesOpened,
	"opened,",
	p.stats.orbsSold,
	"orbs sold"
)
local _ = Rarities, GameConfig, Upgrades
