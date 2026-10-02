--!strict
-- Pure economy formulas shared by server (authoritative) and client (display only).
-- Nothing in here mutates state or touches Roblox services.

local Config = script.Parent.Parent.Config
local Abilities = require(Config.Abilities)
local Banners = require(Config.Banners)
local Characters = require(Config.Characters)
local Enemies = require(Config.Enemies)
local GameConfig = require(Config.GameConfig)
local Rarities = require(Config.Rarities)
local Upgrades = require(Config.Upgrades)

export type Unit = { id: string, level: number, t: number? }

local Economy = {}

local function upgradeLevel(profile: any, id: string): number
	local upgrades = profile and profile.upgrades
	return if upgrades and type(upgrades[id]) == "number" then upgrades[id] else 0
end
Economy.upgradeLevel = upgradeLevel

function Economy.maxLevel(unit: Unit): number
	local def = Characters.get(unit.id)
	local rarity = def and Rarities.get(def.rarity)
	return if rarity then rarity.maxLevel else 1
end

function Economy.levelMultiplier(level: number): number
	return 1 + GameConfig.RatePerLevel * (level - 1)
end

function Economy.productionMultiplier(profile: any): number
	return 1 + GameConfig.ProductionPerUpgrade * upgradeLevel(profile, "production")
end

-- Energy per second of a single unit before sanctuary-wide multipliers.
function Economy.unitBaseRate(unit: Unit): number
	local def = Characters.get(unit.id)
	if not def then
		return 0
	end
	return def.rate * Economy.levelMultiplier(unit.level)
end

function Economy.unitRate(unit: Unit, profile: any): number
	return Economy.unitBaseRate(unit) * Economy.productionMultiplier(profile)
end

function Economy.unitPower(unit: Unit): number
	local def = Characters.get(unit.id)
	if not def then
		return 0
	end
	return math.floor(def.power * (1 + GameConfig.PowerPerLevel * (unit.level - 1)) + 0.5)
end

-- Iterates placed, valid units: callback(spotIndex, uid, unit)
function Economy.forEachPlaced(profile: any, callback: (number, string, Unit) -> ())
	for spotKey, uid in profile.spots do
		local unit = profile.units[uid]
		local spot = tonumber(spotKey)
		if unit and spot and Characters.get(unit.id) then
			callback(spot, uid, unit)
		end
	end
end

function Economy.totalRate(profile: any): number
	local total = 0
	Economy.forEachPlaced(profile, function(_, _, unit)
		total += Economy.unitBaseRate(unit)
	end)
	return total * Economy.productionMultiplier(profile)
end

function Economy.teamPower(profile: any): number
	local total = 0
	Economy.forEachPlaced(profile, function(_, _, unit)
		total += Economy.unitPower(unit)
	end)
	return total
end

function Economy.wellCapacitySeconds(profile: any): number
	return GameConfig.WellBaseSeconds + GameConfig.WellSecondsPerLevel * upgradeLevel(profile, "capacity")
end

function Economy.wellCapacity(profile: any, rate: number?): number
	local r = rate or Economy.totalRate(profile)
	return math.max(GameConfig.WellMinCapacity, math.floor(r * Economy.wellCapacitySeconds(profile)))
end

-- Stored energy at time `now` without mutating the profile (used by UI extrapolation too).
function Economy.wellStoredAt(profile: any, now: number): number
	local well = profile.well
	local rate = Economy.totalRate(profile)
	local cap = Economy.wellCapacity(profile, rate)
	if well.stored >= cap then
		return well.stored
	end
	local dt = math.clamp(now - well.t, 0, GameConfig.MaxOfflineSeconds)
	return math.min(cap, well.stored + rate * dt)
end

function Economy.trainCost(unit: Unit): number?
	local def = Characters.get(unit.id)
	local rarity = def and Rarities.get(def.rarity)
	if not rarity or unit.level >= rarity.maxLevel then
		return nil
	end
	return math.floor(rarity.trainBase * rarity.trainGrowth ^ (unit.level - 1))
end

function Economy.releaseValue(unit: Unit): number
	local def = Characters.get(unit.id)
	local rarity = def and Rarities.get(def.rarity)
	if not rarity then
		return 0
	end
	return math.floor(rarity.releaseValue * (1 + 0.5 * (unit.level - 1)))
end

function Economy.upgradeCost(id: string, level: number): number?
	local def = Upgrades.get(id)
	if not def or level >= def.maxLevel then
		return nil
	end
	return math.floor(def.baseCost * def.growth ^ level)
end

function Economy.spotUnlockCost(spot: number): number?
	return GameConfig.SpotUnlockCosts[spot]
end

function Economy.damageMultiplier(profile: any): number
	local mastery = 1 + GameConfig.CombatPerUpgrade * upgradeLevel(profile, "combat")
	local team = 1 + Economy.teamPower(profile) / GameConfig.TeamPowerDivisor
	return mastery * team
end

function Economy.abilityDamage(profile: any, abilityId: string): number
	local ability = Abilities.ById[abilityId]
	if not ability then
		return 0
	end
	return math.floor(Abilities.BaseDamage * ability.damageScale * Economy.damageMultiplier(profile) + 0.5)
end

function Economy.combatReward(enemyId: string, profile: any): number
	local enemy = Enemies.ById[enemyId]
	if not enemy then
		return 0
	end
	return math.floor(enemy.rewardEnergy + Economy.totalRate(profile) * enemy.rewardIncomeSeconds)
end

-- Rarity weights for a banner after Ritual Fortune is applied.
function Economy.rarityWeights(bannerId: string, luckLevel: number): { [string]: number }
	local banner = Banners.get(bannerId)
	local weights = {}
	if not banner then
		return weights
	end
	for _, rarity in Rarities.Order do
		local base = banner.weights[rarity] or 0
		local bonus = Banners.LuckPerLevel[rarity] or 0
		weights[rarity] = base * (1 + bonus * luckLevel)
	end
	return weights
end

-- Normalised probabilities (0..1) for display.
function Economy.rarityChances(bannerId: string, luckLevel: number): { [string]: number }
	local weights = Economy.rarityWeights(bannerId, luckLevel)
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
