--!strict
-- Authoritative game actions. Each function validates its inputs against the profile,
-- mutates the profile only when the action succeeds, and returns (ok, resultOrMessage).
-- These are pure Luau so they can be unit-tested outside Roblox; the server services call
-- them and handle replication, visuals and persistence around them.

local Config = script.Parent.Parent.Config
local Banners = require(Config.Banners)
local Characters = require(Config.Characters)
local GameConfig = require(Config.GameConfig)
local Rarities = require(Config.Rarities)
local Upgrades = require(Config.Upgrades)
local Economy = require(script.Parent.Economy)

type Rng = { NextNumber: (self: any) -> number }

local Actions = {}

local function countUnits(profile: any): number
	local n = 0
	for _ in profile.units do
		n += 1
	end
	return n
end
Actions.countUnits = countUnits

local function spotOf(profile: any, uid: string): number?
	for spotKey, placed in profile.spots do
		if placed == uid then
			return tonumber(spotKey)
		end
	end
	return nil
end
Actions.spotOf = spotOf

local function spend(profile: any, currency: string, amount: number): boolean
	if currency == "seals" then
		if profile.seals < amount then
			return false
		end
		profile.seals -= amount
		return true
	end
	if profile.energy < amount then
		return false
	end
	profile.energy -= amount
	return true
end

-- Brings the Spirit Well up to date. Must run before anything that changes output or capacity.
function Actions.settleWell(profile: any, now: number)
	profile.well.stored = Economy.wellStoredAt(profile, now)
	profile.well.t = now
end

function Actions.collect(profile: any, now: number): (boolean, any)
	Actions.settleWell(profile, now)
	local amount = math.floor(profile.well.stored)
	if amount < 1 then
		return false, "The well is empty. Give your spirits a moment."
	end
	profile.well.stored -= amount
	profile.energy += amount
	profile.lifetimeEnergy += amount
	profile.stats.collected += amount
	return true, { amount = amount }
end

local function rollRarity(profile: any, bannerId: string, rng: Rng, onlyHigh: boolean): string
	local weights = Economy.rarityWeights(bannerId, Economy.upgradeLevel(profile, "luck"))
	local total = 0
	for _, rarity in Rarities.Order do
		if not onlyHigh or Rarities.rank(rarity) >= 4 then
			total += weights[rarity] or 0
		end
	end
	local roll = rng:NextNumber() * total
	local fallback = "Common"
	for _, rarity in Rarities.Order do
		local w = weights[rarity] or 0
		if (not onlyHigh or Rarities.rank(rarity) >= 4) and w > 0 then
			fallback = rarity
			if roll < w then
				return rarity
			end
			roll -= w
		end
	end
	return fallback
end

function Actions.summon(profile: any, bannerId: any, count: any, rng: Rng, now: number): (boolean, any)
	local banner = if type(bannerId) == "string" then Banners.get(bannerId) else nil
	if not banner then
		return false, "Unknown ritual."
	end
	if type(count) ~= "number" or not Banners.AllowedCounts[count] then
		return false, "Invalid summon amount."
	end
	if countUnits(profile) + count > GameConfig.InventoryLimit then
		return false, string.format("Your roster is full (%d). Release some units first.", GameConfig.InventoryLimit)
	end
	local cost = banner.cost * count
	if not spend(profile, banner.currency, cost) then
		return false, if banner.currency == "seals" then "Not enough Curse Seals." else "Not enough cursed energy."
	end

	local weights = Economy.rarityWeights(banner.id, 0)
	local canPity = (weights.Legendary or 0) + (weights.Mythic or 0) > 0
	local results = {}
	for _ = 1, count do
		local rarity: string
		if profile.stats.summons == 0 and banner.id == "lantern" then
			-- The very first ritual is guaranteed to feel good.
			rarity = "Rare"
		elseif canPity and profile.pity >= Banners.PityThreshold - 1 then
			rarity = rollRarity(profile, banner.id, rng, true)
		else
			rarity = rollRarity(profile, banner.id, rng, false)
		end
		local pool = Characters.ByRarity[rarity]
		local def = pool[math.floor(rng:NextNumber() * #pool) + 1] or pool[1]

		local uid = tostring(profile.nextUid)
		profile.nextUid += 1
		profile.units[uid] = { id = def.id, level = 1, t = now }
		local isNew = not profile.discovered[def.id]
		profile.discovered[def.id] = true
		profile.stats.summons += 1
		if Rarities.rank(rarity) >= 4 then
			profile.pity = 0
		else
			profile.pity += 1
		end
		table.insert(results, { uid = uid, id = def.id, rarity = rarity, isNew = isNew })
	end
	return true, { units = results, banner = banner.id, cost = cost, currency = banner.currency }
end

local function validSpot(profile: any, spot: any): number?
	if type(spot) ~= "number" or spot ~= math.floor(spot) then
		return nil
	end
	if spot < 1 or spot > profile.unlockedSpots then
		return nil
	end
	return spot
end

function Actions.place(profile: any, uid: any, spot: any, now: number): (boolean, any)
	if type(uid) ~= "string" or not profile.units[uid] then
		return false, "You don't own that unit."
	end
	local target = validSpot(profile, spot)
	if not target then
		return false, "That training spot is sealed."
	end
	Actions.settleWell(profile, now)
	local from = spotOf(profile, uid)
	if from == target then
		return true, { spot = target, unchanged = true }
	end
	local key = tostring(target)
	local replaced = profile.spots[key]
	if from then
		-- Moving between spots swaps with whoever was on the target spot.
		profile.spots[tostring(from)] = replaced
	end
	profile.spots[key] = uid
	return true, { spot = target, from = from, replaced = replaced, swapped = from ~= nil and replaced ~= nil }
end

function Actions.unplace(profile: any, spot: any, now: number): (boolean, any)
	if type(spot) ~= "number" then
		return false, "Invalid spot."
	end
	local key = tostring(spot)
	local uid = profile.spots[key]
	if not uid then
		return false, "Nothing is training there."
	end
	Actions.settleWell(profile, now)
	profile.spots[key] = nil
	return true, { spot = spot, uid = uid }
end

function Actions.train(profile: any, uid: any, now: number): (boolean, any)
	local unit = if type(uid) == "string" then profile.units[uid] else nil
	if not unit then
		return false, "You don't own that unit."
	end
	local cost = Economy.trainCost(unit)
	if not cost then
		return false, "Already at max level."
	end
	if profile.energy < cost then
		return false, "Not enough cursed energy."
	end
	Actions.settleWell(profile, now)
	profile.energy -= cost
	unit.level += 1
	return true, { uid = uid, level = unit.level, cost = cost }
end

function Actions.release(profile: any, uid: any, now: number): (boolean, any)
	local unit = if type(uid) == "string" then profile.units[uid] else nil
	if not unit then
		return false, "You don't own that unit."
	end
	if countUnits(profile) <= 1 then
		return false, "You can't release your last unit."
	end
	local spot = spotOf(profile, uid)
	if spot then
		Actions.settleWell(profile, now)
		profile.spots[tostring(spot)] = nil
	end
	local value = Economy.releaseValue(unit)
	profile.units[uid] = nil
	profile.energy += value
	return true, { uid = uid, value = value, spot = spot }
end

function Actions.buyUpgrade(profile: any, upgradeId: any, now: number): (boolean, any)
	local def = if type(upgradeId) == "string" then Upgrades.get(upgradeId) else nil
	if not def then
		return false, "Unknown upgrade."
	end
	local level = profile.upgrades[def.id] or 0
	local cost = Economy.upgradeCost(def.id, level)
	if not cost then
		return false, "Already at max level."
	end
	if profile.energy < cost then
		return false, "Not enough cursed energy."
	end
	Actions.settleWell(profile, now)
	profile.energy -= cost
	profile.upgrades[def.id] = level + 1
	return true, { id = def.id, level = level + 1, cost = cost }
end

function Actions.unlockSpot(profile: any, now: number): (boolean, any)
	local nextSpot = profile.unlockedSpots + 1
	local cost = Economy.spotUnlockCost(nextSpot)
	if nextSpot > GameConfig.SpotCount or not cost then
		return false, "Every spot is already unlocked."
	end
	if profile.energy < cost then
		return false, "Not enough cursed energy."
	end
	Actions.settleWell(profile, now)
	profile.energy -= cost
	profile.unlockedSpots = nextSpot
	return true, { spot = nextSpot, cost = cost }
end

function Actions.grantReward(profile: any, energy: number, seals: number)
	if energy > 0 then
		profile.energy += energy
		profile.lifetimeEnergy += energy
	end
	if seals > 0 then
		profile.seals += seals
	end
end

return Actions
