--!nocheck
-- Economy pacing simulation: a greedy bot plays the real rules for N minutes.
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
local Characters, Banners, GameConfig, Enemies =
	req("Config/Characters"), req("Config/Banners"), req("Config/GameConfig"), req("Config/Enemies")

local minutes = tonumber(process.args[2]) or 120
local rng = Prng.new(7)
local p = Schema.new(0)
local t = 0
local milestones = {}
local function mark(name)
	if not milestones[name] then
		milestones[name] = t
		print(
			string.format(
				"[%s] %s  (rate %s, energy %s)",
				Format.duration(t),
				name,
				Format.rate(Economy.totalRate(p)),
				Format.abbreviate(p.energy)
			)
		)
	end
end

local function expectedBaseRate(bannerId)
	local chances = Economy.rarityChances(bannerId, p.upgrades.luck)
	local e = 0
	for rarity, c in chances do
		local pool = Characters.ByRarity[rarity]
		local avg = 0
		for _, d in pool do
			avg += d.rate
		end
		e += c * avg / #pool
	end
	return e
end

local function placedList()
	local list = {}
	Economy.forEachPlaced(p, function(spot, uid, unit)
		table.insert(list, { spot = spot, uid = uid, rate = Economy.unitBaseRate(unit) })
	end)
	table.sort(list, function(a, b)
		return a.rate < b.rate
	end)
	return list
end

local function freeSpot()
	for s = 1, p.unlockedSpots do
		if not p.spots[tostring(s)] then
			return s
		end
	end
end

local function autoPlace()
	-- Fill empty spots / replace weaker units with the best unplaced units.
	local changed = true
	while changed do
		changed = false
		local best, bestRate = nil, -1
		for uid, unit in p.units do
			if not Actions.spotOf(p, uid) then
				local r = Economy.unitBaseRate(unit)
				if r > bestRate then
					best, bestRate = uid, r
				end
			end
		end
		if not best then
			return
		end
		local s = freeSpot()
		if s then
			Actions.place(p, best, s, t)
			changed = true
			if Tutorial.advance(p, "place") then
				mark("tutorial: placed")
			end
		else
			local placed = placedList()
			if placed[1] and placed[1].rate < bestRate then
				Actions.unplace(p, placed[1].spot, t)
				Actions.place(p, best, placed[1].spot, t)
				changed = true
			end
		end
	end
end

local function releaseJunk()
	-- Keep roster small: release unplaced units worse than the weakest placed one.
	local placed = placedList()
	local floor = placed[1] and placed[1].rate or 0
	for uid, unit in p.units do
		if
			not Actions.spotOf(p, uid)
			and Economy.unitBaseRate(unit) <= floor
			and Actions.countUnits(p) > 12
		then
			Actions.release(p, uid, t)
		end
	end
end

local function options()
	local opts = {}
	local mult = Economy.productionMultiplier(p)
	local placed = placedList()
	local worst = (freeSpot() and 0) or (placed[1] and placed[1].rate) or 0
	for _, b in Banners.List do
		if b.currency == "energy" then
			local gain = math.max(0, expectedBaseRate(b.id) - worst) * mult
			if Actions.countUnits(p) < GameConfig.InventoryLimit then
				table.insert(opts, { kind = "summon", id = b.id, cost = b.cost, gain = gain })
			end
		end
	end
	local c = Economy.spotUnlockCost(p.unlockedSpots + 1)
	if c then
		table.insert(opts, { kind = "unlock", cost = c, gain = expectedBaseRate("lantern") * mult * 0.9 })
	end
	for _, entry in placed do
		local unit = p.units[entry.uid]
		local tc = Economy.trainCost(unit)
		if tc then
			local def = Characters.get(unit.id)
			table.insert(opts, {
				kind = "train",
				uid = entry.uid,
				cost = tc,
				gain = def.rate * GameConfig.RatePerLevel * mult,
			})
		end
	end
	local pc = Economy.upgradeCost("production", p.upgrades.production)
	if pc then
		local base = 0
		for _, e in placed do
			base += e.rate
		end
		table.insert(opts, { kind = "production", cost = pc, gain = base * GameConfig.ProductionPerUpgrade })
	end
	return opts
end

local nextCollect = 0
local nextFight = 300
local totalCombat = 0
while t < minutes * 60 do
	-- The well is visited about every 45s (players roam), or immediately during the tutorial.
	if t >= nextCollect then
		local ok = Actions.collect(p, t)
		if ok then
			mark("first collect")
			Tutorial.advance(p, "collect")
		end
		nextCollect = t + (p.tutorial <= 2 and 1 or 45)
	end
	-- Tutorial-shaped opening.
	if p.tutorial == 2 and p.energy >= 50 then
		local ok = Actions.summon(p, "lantern", 1, rng, t)
		if ok then
			Tutorial.advance(p, "summon")
			mark("first summon")
		end
	end
	autoPlace()
	if p.tutorial == 4 and p.energy >= Economy.upgradeCost("production", 0) then
		Actions.buyUpgrade(p, "production", t)
		Tutorial.advance(p, "upgrade")
		mark("first upgrade (tutorial)")
	end
	if p.tutorial >= 5 then
		-- Greedy spending on the best value-per-cost option; wait if it isn't affordable yet.
		for _ = 1, 20 do
			local best, bestScore = nil, -1
			for _, o in options() do
				local score = o.gain / o.cost
				if score > bestScore then
					best, bestScore = o, score
				end
			end
			if not best or best.cost > p.energy then
				break
			end
			if best.kind == "summon" then
				local ok, res = Actions.summon(p, best.id, 1, rng, t)
				if ok then
					for _, u in res.units do
						mark("first " .. u.rarity)
					end
				end
			elseif best.kind == "unlock" then
				local ok, res = Actions.unlockSpot(p, t)
				if ok then
					mark("spot " .. res.spot)
				end
			elseif best.kind == "train" then
				Actions.train(p, best.uid, t)
			elseif best.kind == "production" then
				Actions.buyUpgrade(p, "production", t)
			end
			autoPlace()
			releaseJunk()
		end
	end
	-- Every 5 minutes the bot spends a minute in the forest: ~8 Gloomlings + 2 Wailers.
	if t >= nextFight then
		local reward = 8 * Economy.combatReward("gloomling", p) + 2 * Economy.combatReward("wailer", p)
		local seals =
			math.floor(8 * Enemies.ById.gloomling.sealChance + 2 * Enemies.ById.wailer.sealChance + 0.5)
		Actions.grantReward(p, reward, seals)
		totalCombat += reward
		if Tutorial.advance(p, "kill") then
			mark("tutorial complete")
		end
		if p.seals >= 12 then
			local ok, res = Actions.summon(p, "sealed", 1, rng, t)
			if ok then
				for _, u in res.units do
					mark("first " .. u.rarity)
				end
			end
		end
		nextFight = t + 300
		t += 60
	end
	t += 1
	if t % 600 == 0 then
		print(
			string.format(
				"  t=%s rate=%s energy=%s spots=%d units=%d prod=%d seals=%d combatTotal=%s",
				Format.duration(t),
				Format.rate(Economy.totalRate(p)),
				Format.abbreviate(p.energy),
				p.unlockedSpots,
				Actions.countUnits(p),
				p.upgrades.production,
				p.seals,
				Format.abbreviate(totalCombat)
			)
		)
	end
end
