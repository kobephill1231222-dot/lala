--!strict
-- Pure economy formulas shared by the server (authoritative) and the client (display only).

local Config = script.Parent.Parent.Config
local Crates = require(Config.Crates)
local GameConfig = require(Config.GameConfig)
local Rarities = require(Config.Rarities)
local Sorcerers = require(Config.Sorcerers)
local Upgrades = require(Config.Upgrades)

export type Unit = { id: string, level: number }

local Economy = {}

function Economy.upgradeLevel(profile: any, id: string): number
	local upgrades = profile and profile.upgrades
	return if upgrades and type(upgrades[id]) == "number" then upgrades[id] else 0
end

function Economy.maxLevel(unit: Unit): number
	local def = Sorcerers.get(unit.id)
	local rarity = def and Rarities.get(def.rarity)
	return if rarity then rarity.maxLevel else 1
end

-- Orb Value of one sorcerer (Cash per Cursed Orb), including the farm's Orb Value upgrade.
function Economy.orbValue(unit: Unit, profile: any): number
	local def = Sorcerers.get(unit.id)
	if not def then
		return 0
	end
	local levelMult = 1 + GameConfig.OrbValuePerLevel * (unit.level - 1)
	local farmMult = 1 + GameConfig.OrbValuePerUpgrade * Economy.upgradeLevel(profile, "orbValue")
	return def.orbValue * levelMult * farmMult
end

function Economy.ops(unit: Unit): number
	local def = Sorcerers.get(unit.id)
	return if def then def.ops else 0
end

function Economy.income(unit: Unit, profile: any): number
	return Economy.ops(unit) * Economy.orbValue(unit, profile)
end

function Economy.forEachPlaced(profile: any, callback: (number, string, Unit) -> ())
	for slotKey, uid in profile.slots do
		local unit = profile.units[uid]
		local slot = tonumber(slotKey)
		if unit and slot and Sorcerers.get(unit.id) then
			callback(slot, uid, unit)
		end
	end
end

-- Orbs per Second and Cash per second of the whole farm.
function Economy.totals(profile: any): (number, number)
	local ops, cash = 0, 0
	Economy.forEachPlaced(profile, function(_, _, unit)
		ops += Economy.ops(unit)
		cash += Economy.income(unit, profile)
	end)
	return ops, cash
end

function Economy.boxCapacity(profile: any): number
	return math.floor(
		GameConfig.BoxBaseCapacity * GameConfig.BoxGrowthPerLevel ^ Economy.upgradeLevel(profile, "boxSize")
	)
end

-- Orb Box contents at time `now` (does not modify the profile).
function Economy.boxAt(profile: any, now: number): (number, number)
	local box = profile.box
	local cap = Economy.boxCapacity(profile)
	local ops, cash = Economy.totals(profile)
	if ops <= 0 or box.orbs >= cap then
		return box.orbs, box.value
	end
	local dt = math.clamp(now - box.t, 0, GameConfig.MaxOfflineSeconds)
	local added = math.min(cap - box.orbs, ops * dt)
	return box.orbs + added, box.value + added * (cash / ops)
end

function Economy.unitUpgradeCost(unit: Unit): number?
	local def = Sorcerers.get(unit.id)
	local rarity = def and Rarities.get(def.rarity)
	if not rarity or unit.level >= rarity.maxLevel then
		return nil
	end
	return math.floor(rarity.upgradeBase * rarity.upgradeGrowth ^ (unit.level - 1))
end

function Economy.sellValue(unit: Unit): number
	local def = Sorcerers.get(unit.id)
	local rarity = def and Rarities.get(def.rarity)
	if not rarity then
		return 0
	end
	return math.floor(rarity.sellValue * (1 + 0.5 * (unit.level - 1)))
end

function Economy.upgradeCost(id: string, level: number): number?
	local def = Upgrades.get(id)
	if not def or level >= def.maxLevel then
		return nil
	end
	if def.costs then
		return def.costs[level + 1]
	end
	return math.floor(def.baseCost * def.growth ^ level)
end

function Economy.unlockedSlots(profile: any): number
	return GameConfig.StartingSlots + Economy.upgradeLevel(profile, "slots")
end

function Economy.unlockedPads(profile: any): number
	return GameConfig.StartingPads + Economy.upgradeLevel(profile, "pads")
end

function Economy.walkSpeed(profile: any): number
	return GameConfig.BaseWalkSpeed
		+ GameConfig.WalkSpeedPerLevel * Economy.upgradeLevel(profile, "walkSpeed")
end

-- Opening Time of a crate tier after the Opening Speed upgrade.
function Economy.openingTime(crateId: string, profile: any): number
	local def = Crates.get(crateId)
	if not def then
		return 0
	end
	local speed = math.min(0.6, GameConfig.OpenSpeedPerLevel * Economy.upgradeLevel(profile, "openSpeed"))
	return math.max(3, math.floor(def.openingTime * (1 - speed) + 0.5))
end

function Economy.crateWeights(crateId: string, luckLevel: number): { [string]: number }
	local def = Crates.get(crateId)
	local weights = {}
	if not def then
		return weights
	end
	for _, rarity in Rarities.Order do
		local base = def.odds[rarity] or 0
		weights[rarity] = base * (1 + (Crates.LuckPerLevel[rarity] or 0) * luckLevel)
	end
	return weights
end

function Economy.crateChances(crateId: string, luckLevel: number): { [string]: number }
	local weights = Economy.crateWeights(crateId, luckLevel)
	local total = 0
	for _, w in weights do
		total += w
	end
	local chances = {}
	for rarity, w in weights do
		chances[rarity] = if total > 0 then w / total else 0
	end
	return chances
end

return Economy
