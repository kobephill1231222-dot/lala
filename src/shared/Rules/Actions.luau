--!strict
-- Authoritative game actions. Each function validates its inputs against the profile,
-- mutates the profile only when the action succeeds, and returns (ok, resultOrMessage).
-- These are pure Luau so they can be unit-tested outside Roblox; the server services call
-- them and handle replication, visuals, range checks and persistence around them.
--
-- The loop: Buy a Crate -> Place it on a Crate Pad -> Open it when its Opening Time is
-- over -> Place the Sorcerer on a slot -> its Cursed Orbs fill the Orb Box -> Collect the
-- box -> Sell it for Cash -> Upgrade.

local Config = script.Parent.Parent.Config
local Crates = require(Config.Crates)
local GameConfig = require(Config.GameConfig)
local Rarities = require(Config.Rarities)
local Sorcerers = require(Config.Sorcerers)
local Upgrades = require(Config.Upgrades)
local Economy = require(script.Parent.Economy)

-- Anything with Random's NextNumber() (Roblox Random, or Util/Prng in tests).
type Rng = any

local Actions = {}

local function count(map: { [any]: any }): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

function Actions.countUnits(profile: any): number
	return count(profile.units)
end

function Actions.countCrates(profile: any): number
	return count(profile.crates)
end

function Actions.slotOf(profile: any, uid: string): number?
	for slotKey, placed in profile.slots do
		if placed == uid then
			return tonumber(slotKey)
		end
	end
	return nil
end

function Actions.crateOnPad(profile: any, pad: number): (string?, any)
	for cid, crate in profile.crates do
		if crate.pad == pad then
			return cid, crate
		end
	end
	return nil, nil
end

local function isInteger(v: any): boolean
	return type(v) == "number" and v == math.floor(v)
end

-- Brings the Orb Box up to date. Must run before anything that changes production
-- (placing, picking up, upgrading) so orbs made so far keep the value they were made at.
function Actions.settleBox(profile: any, now: number)
	local orbs, value = Economy.boxAt(profile, now)
	profile.box.orbs = orbs
	profile.box.value = value
	profile.box.t = now
end

-- Offline progress. Called once when a profile is loaded: everything produced since the
-- box was last settled (at most GameConfig.MaxOfflineSeconds, and never more than the Orb
-- Box can hold) goes into the box, and the box's timestamp moves to `now`, so the same
-- absence can never be counted twice. The timestamp is saved with the profile.
function Actions.claimOffline(profile: any, now: number): any
	local before = profile.box.orbs
	local beforeValue = profile.box.value
	local away = math.max(0, now - profile.box.t)
	Actions.settleBox(profile, now)
	local ready = 0
	for _, crate in profile.crates do
		if crate.readyAt and crate.readyAt <= now and crate.readyAt > profile.lastSeen then
			ready += 1
		end
	end
	return {
		seconds = away,
		counted = math.min(away, GameConfig.MaxOfflineSeconds),
		capped = away > GameConfig.MaxOfflineSeconds,
		orbs = profile.box.orbs - before,
		value = profile.box.value - beforeValue,
		boxFull = profile.box.orbs >= Economy.boxCapacity(profile),
		cratesReady = ready,
	}
end

---------------------------------------------------------------------------------------
-- Crates

function Actions.buyCrate(profile: any, tier: any): (boolean, any)
	local def = if type(tier) == "string" then Crates.get(tier) else nil
	if not def or def.price <= 0 then
		return false, "That crate isn't sold here."
	end
	if Actions.countCrates(profile) >= GameConfig.CrateLimit then
		return false, string.format("You can hold %d Crates. Open some first.", GameConfig.CrateLimit)
	end
	if profile.cash < def.price then
		return false, "Not enough Cash."
	end
	profile.cash -= def.price
	local cid = tostring(profile.nextCid)
	profile.nextCid += 1
	profile.crates[cid] = { tier = def.id }
	profile.stats.cratesBought += 1
	return true, { cid = cid, tier = def.id, cost = def.price }
end

function Actions.placeCrate(profile: any, cid: any, pad: any, now: number): (boolean, any)
	local crate = if type(cid) == "string" then profile.crates[cid] else nil
	if not crate then
		return false, "You don't have that Crate."
	end
	if crate.pad then
		return false, "That Crate is already placed."
	end
	if not isInteger(pad) or pad < 1 or pad > GameConfig.PadCount then
		return false, "Invalid Crate Pad."
	end
	if pad > Economy.unlockedPads(profile) then
		return false, "Buy More Crate Pads at the Upgrade Shop to use this pad."
	end
	if Actions.crateOnPad(profile, pad) then
		return false, "There's already a Crate on that pad."
	end
	-- `remaining` is set once a crate has been placed before (0 = already finished opening);
	-- nil means it has never been placed and gets its full Opening Time.
	local duration = if crate.remaining ~= nil
		then crate.remaining
		else Economy.openingTime(crate.tier, profile)
	crate.pad = pad
	crate.readyAt = now + duration
	crate.remaining = nil
	return true, { cid = cid, tier = crate.tier, pad = pad, readyAt = crate.readyAt, duration = duration }
end

function Actions.pickUpCrate(profile: any, pad: any, now: number): (boolean, any)
	if not isInteger(pad) then
		return false, "Invalid Crate Pad."
	end
	local cid, crate = Actions.crateOnPad(profile, pad)
	if not cid or not crate then
		return false, "There's no Crate on that pad."
	end
	-- Keep the time already spent opening; placing it again continues from there. A crate
	-- that already finished keeps remaining = 0 and can be opened as soon as it's placed.
	crate.remaining = math.max(0, crate.readyAt - now)
	crate.pad = nil
	crate.readyAt = nil
	return true, { cid = cid, tier = crate.tier, pad = pad }
end

local function rollRarity(profile: any, tier: string, rng: Rng): string
	local weights = Economy.crateWeights(tier, Economy.upgradeLevel(profile, "luck"))
	local total = 0
	for _, rarity in Rarities.Order do
		total += weights[rarity] or 0
	end
	local roll = rng:NextNumber() * total
	local fallback = "Common"
	for _, rarity in Rarities.Order do
		local w = weights[rarity] or 0
		if w > 0 then
			fallback = rarity
			if roll < w then
				return rarity
			end
			roll -= w
		end
	end
	return fallback
end

function Actions.openCrate(profile: any, pad: any, rng: Rng, now: number): (boolean, any)
	if not isInteger(pad) then
		return false, "Invalid Crate Pad."
	end
	local cid, crate = Actions.crateOnPad(profile, pad)
	if not cid or not crate then
		return false, "There's no Crate on that pad."
	end
	if now < crate.readyAt then
		return false, "This Crate is still opening."
	end
	if Actions.countUnits(profile) >= GameConfig.InventoryLimit then
		return false, string.format("You can own %d Sorcerers. Sell some first.", GameConfig.InventoryLimit)
	end
	local def = Crates.get(crate.tier) :: Crates.CrateDef
	local sorcerer
	if def.guaranteed then
		sorcerer = Sorcerers.get(def.guaranteed)
	end
	if not sorcerer then
		local rarity = rollRarity(profile, def.id, rng)
		local pool = Sorcerers.ByRarity[rarity]
		sorcerer = pool[math.floor(rng:NextNumber() * #pool) + 1] or pool[1]
	end
	assert(sorcerer, "crate produced no sorcerer")

	profile.crates[cid] = nil
	local uid = tostring(profile.nextUid)
	profile.nextUid += 1
	profile.units[uid] = { id = sorcerer.id, level = 1 }
	local isNew = not profile.discovered[sorcerer.id]
	profile.discovered[sorcerer.id] = true
	profile.stats.cratesOpened += 1
	return true,
		{ uid = uid, id = sorcerer.id, rarity = sorcerer.rarity, isNew = isNew, tier = def.id, pad = pad }
end

---------------------------------------------------------------------------------------
-- Sorcerers

function Actions.placeSorcerer(profile: any, uid: any, slot: any, now: number): (boolean, any)
	if type(uid) ~= "string" or not profile.units[uid] then
		return false, "You don't own that Sorcerer."
	end
	if not isInteger(slot) or slot < 1 or slot > GameConfig.SlotCount then
		return false, "Invalid slot."
	end
	if slot > Economy.unlockedSlots(profile) then
		return false, "Buy More Slots at the Upgrade Shop to use this slot."
	end
	Actions.settleBox(profile, now)
	local from = Actions.slotOf(profile, uid)
	if from == slot then
		return true, { slot = slot, unchanged = true }
	end
	local key = tostring(slot)
	local replaced = profile.slots[key]
	if from then
		-- Moving between slots swaps with whoever was on the target slot.
		profile.slots[tostring(from)] = replaced
	end
	profile.slots[key] = uid
	return true, { slot = slot, uid = uid, from = from, replaced = replaced }
end

function Actions.pickUpSorcerer(profile: any, slot: any, now: number): (boolean, any)
	if not isInteger(slot) then
		return false, "Invalid slot."
	end
	local key = tostring(slot)
	local uid = profile.slots[key]
	if not uid then
		return false, "That slot is empty."
	end
	Actions.settleBox(profile, now)
	profile.slots[key] = nil
	return true, { slot = slot, uid = uid }
end

function Actions.upgradeSorcerer(profile: any, uid: any, now: number): (boolean, any)
	local unit = if type(uid) == "string" then profile.units[uid] else nil
	if not unit then
		return false, "You don't own that Sorcerer."
	end
	local cost = Economy.unitUpgradeCost(unit)
	if not cost then
		return false, "Already at max level."
	end
	if profile.cash < cost then
		return false, "Not enough Cash."
	end
	Actions.settleBox(profile, now)
	profile.cash -= cost
	unit.level += 1
	return true, { uid = uid, level = unit.level, cost = cost }
end

function Actions.sellSorcerer(profile: any, uid: any, now: number): (boolean, any)
	local unit = if type(uid) == "string" then profile.units[uid] else nil
	if not unit then
		return false, "You don't own that Sorcerer."
	end
	if Actions.countUnits(profile) <= 1 then
		return false, "You can't sell your last Sorcerer."
	end
	local slot = Actions.slotOf(profile, uid)
	if slot then
		Actions.settleBox(profile, now)
		profile.slots[tostring(slot)] = nil
	end
	local value = Economy.sellValue(unit)
	profile.units[uid] = nil
	profile.cash += value
	profile.stats.cashEarned += value
	return true, { uid = uid, id = unit.id, value = value, slot = slot }
end

---------------------------------------------------------------------------------------
-- Orb Box

-- Takes every whole Cursed Orb out of the Orb Box. The player carries them to the Sell
-- Stand; collecting again before selling adds to what they carry.
function Actions.collect(profile: any, now: number): (boolean, any)
	Actions.settleBox(profile, now)
	local box = profile.box
	local orbs = math.floor(box.orbs)
	if orbs < 1 then
		return false, "Your Orb Box is empty."
	end
	local value = box.value * (orbs / box.orbs)
	box.orbs -= orbs
	box.value = math.max(0, box.value - value)
	if box.orbs < 1e-9 then
		box.orbs = 0
		box.value = 0
	end
	profile.carried.orbs += orbs
	profile.carried.value += value
	return true, { orbs = orbs, value = value, carried = profile.carried.orbs }
end

function Actions.sell(profile: any): (boolean, any)
	local carried = profile.carried
	if carried.orbs < 1 then
		return false, "Collect your Orb Box first."
	end
	local cash = math.max(1, math.floor(carried.value + 0.5))
	local orbs = carried.orbs
	carried.orbs = 0
	carried.value = 0
	profile.cash += cash
	profile.stats.orbsSold += orbs
	profile.stats.cashEarned += cash
	return true, { orbs = orbs, cash = cash }
end

---------------------------------------------------------------------------------------
-- Farm upgrades

function Actions.buyUpgrade(profile: any, upgradeId: any, now: number): (boolean, any)
	local def = if type(upgradeId) == "string" then Upgrades.get(upgradeId) else nil
	if not def then
		return false, "Unknown upgrade."
	end
	local level = Economy.upgradeLevel(profile, def.id)
	local cost = Economy.upgradeCost(def.id, level)
	if not cost then
		return false, "Already at max level."
	end
	if profile.cash < cost then
		return false, "Not enough Cash."
	end
	Actions.settleBox(profile, now)
	profile.cash -= cost
	profile.upgrades[def.id] = level + 1
	return true, { id = def.id, level = level + 1, cost = cost }
end

return Actions
