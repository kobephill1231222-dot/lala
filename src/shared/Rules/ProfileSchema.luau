--!strict
-- Profile shape, defaults, migration and validation.
-- `sanitize` repairs malformed fields but never discards data it doesn't understand:
-- sorcerers with unknown ids are moved to `orphanUnits` and written back untouched.
--
-- Everything the farm needs to resume is persisted: owned Sorcerers and their levels,
-- slot placements, farm upgrades, Crates (including which pad they sit on and the
-- absolute time they finish opening), the Orb Box contents with the time it was last
-- settled, and the orbs the player is carrying.

local Config = script.Parent.Parent.Config
local Crates = require(Config.Crates)
local GameConfig = require(Config.GameConfig)
local Rarities = require(Config.Rarities)
local Sorcerers = require(Config.Sorcerers)
local Upgrades = require(Config.Upgrades)
local Tutorial = require(script.Parent.Tutorial)

local ProfileSchema = {}

local function isFiniteNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function nonNegative(v: any, fallback: number): number
	if isFiniteNumber(v) and v >= 0 then
		return v
	end
	return fallback
end

local function integerIn(v: any, lo: number, hi: number, fallback: number): number
	if isFiniteNumber(v) then
		return math.clamp(math.floor(v), lo, hi)
	end
	return fallback
end

local function emptyProfile(now: number): { [string]: any }
	local upgrades = {}
	for id in Upgrades.ById do
		upgrades[id] = 0
	end
	return {
		version = GameConfig.DataVersion,
		cash = 0,
		units = {},
		nextUid = 1,
		slots = {},
		crates = {},
		nextCid = 1,
		upgrades = upgrades,
		box = { orbs = 0, value = 0, t = now },
		carried = { orbs = 0, value = 0 },
		tutorial = 1,
		discovered = {},
		stats = { cratesBought = 0, cratesOpened = 0, orbsSold = 0, cashEarned = 0, sessions = 0 },
		settings = { music = true, sfx = true },
		orphanUnits = {},
		createdAt = now,
		lastSeen = now,
	}
end

-- Brand-new player: one free Starter Crate waiting to be placed on a Crate Pad.
function ProfileSchema.new(now: number): { [string]: any }
	local profile = emptyProfile(now)
	profile.crates["1"] = { tier = "starter" }
	profile.nextCid = 2
	return profile
end

function ProfileSchema.migrate(raw: { [string]: any }): { [string]: any }
	-- Version 1 is the first released shape. Future migrations go here, e.g.
	-- if raw.version == 1 then ...; raw.version = 2 end
	if type(raw.version) ~= "number" then
		raw.version = GameConfig.DataVersion
	end
	return raw
end

local function maxLevelOf(id: string): number
	local def = Sorcerers.get(id)
	local rarity = def and Rarities.get(def.rarity)
	return if rarity then rarity.maxLevel else 1
end

local function trackMax(key: string, current: number): number
	local n = tonumber(key)
	if n and n > current then
		return n
	end
	return current
end

-- Returns a clean profile plus a list of repairs that were made (for logging).
function ProfileSchema.sanitize(raw: any, now: number): ({ [string]: any }, { string })
	local issues: { string } = {}
	if type(raw) ~= "table" then
		table.insert(issues, "profile was not a table; created new profile")
		return ProfileSchema.new(now), issues
	end
	raw = ProfileSchema.migrate(raw)
	local p = emptyProfile(now)
	p.version = raw.version

	p.cash = nonNegative(raw.cash, 0)
	if raw.cash ~= nil and p.cash ~= raw.cash then
		table.insert(issues, "cash repaired")
	end

	-- Sorcerers
	local maxUid = 0
	if type(raw.units) == "table" then
		for key, unit in raw.units do
			local uid = tostring(key)
			if type(unit) == "table" and type(unit.id) == "string" then
				if Sorcerers.get(unit.id) then
					p.units[uid] = { id = unit.id, level = integerIn(unit.level, 1, maxLevelOf(unit.id), 1) }
				else
					p.orphanUnits[uid] = unit
					table.insert(issues, "unknown sorcerer id preserved: " .. unit.id)
				end
			else
				table.insert(issues, "malformed sorcerer dropped: " .. uid)
			end
			-- Count every key (even dropped ones) so uids are never reused.
			maxUid = trackMax(uid, maxUid)
		end
	end
	if type(raw.orphanUnits) == "table" then
		for key, unit in raw.orphanUnits do
			local uid = tostring(key)
			if type(unit) == "table" and type(unit.id) == "string" and Sorcerers.get(unit.id) then
				-- A previously unknown sorcerer exists again: restore it.
				if p.units[uid] == nil then
					p.units[uid] = { id = unit.id, level = integerIn(unit.level, 1, maxLevelOf(unit.id), 1) }
				end
			else
				p.orphanUnits[uid] = unit
			end
			maxUid = trackMax(uid, maxUid)
		end
	end
	p.nextUid = math.max(integerIn(raw.nextUid, 1, 1e12, 1), maxUid + 1)

	if type(raw.upgrades) == "table" then
		for id, def in Upgrades.ById do
			p.upgrades[id] = integerIn(raw.upgrades[id], 0, def.maxLevel, 0)
		end
	end
	local unlockedSlots = GameConfig.StartingSlots + p.upgrades.slots
	local unlockedPads = GameConfig.StartingPads + p.upgrades.pads

	-- Slots: each unlocked slot holds at most one owned sorcerer, each sorcerer sits in at
	-- most one slot.
	if type(raw.slots) == "table" then
		local used: { [string]: boolean } = {}
		for slotKey, uid in raw.slots do
			local slot = tonumber(slotKey)
			local uidKey = tostring(uid)
			if
				slot
				and slot == math.floor(slot)
				and slot >= 1
				and slot <= unlockedSlots
				and p.units[uidKey]
				and not used[uidKey]
			then
				p.slots[tostring(slot)] = uidKey
				used[uidKey] = true
			else
				table.insert(issues, "invalid placement removed: " .. tostring(slotKey))
			end
		end
	end

	-- Crates: unknown tiers are dropped (a crate is not progress worth an orphan list);
	-- each unlocked pad holds at most one crate; opening timestamps are kept as absolute
	-- times so crates finish while the player is away.
	local maxCid = 0
	if type(raw.crates) == "table" then
		local padUsed: { [number]: boolean } = {}
		-- Oldest crate first so a pad conflict always resolves the same way.
		local keys = {}
		for key in raw.crates do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			return (tonumber(a) or math.huge) < (tonumber(b) or math.huge)
		end)
		for _, key in keys do
			local crate = raw.crates[key]
			local cid = tostring(key)
			maxCid = trackMax(cid, maxCid)
			if type(crate) == "table" and type(crate.tier) == "string" and Crates.get(crate.tier) then
				local clean: { [string]: any } = { tier = crate.tier }
				local pad = crate.pad
				if
					isFiniteNumber(pad)
					and pad == math.floor(pad)
					and pad >= 1
					and pad <= unlockedPads
					and not padUsed[pad]
					and isFiniteNumber(crate.readyAt)
				then
					padUsed[pad] = true
					clean.pad = pad
					clean.readyAt = crate.readyAt
				elseif pad ~= nil then
					table.insert(issues, "crate returned to inventory: " .. cid)
				end
				if clean.pad == nil and isFiniteNumber(crate.remaining) and crate.remaining > 0 then
					clean.remaining = crate.remaining
				end
				p.crates[cid] = clean
			else
				table.insert(issues, "unknown crate dropped: " .. cid)
			end
		end
	end
	p.nextCid = math.max(integerIn(raw.nextCid, 1, 1e12, 1), maxCid + 1)

	if type(raw.box) == "table" then
		p.box.orbs = nonNegative(raw.box.orbs, 0)
		p.box.value = nonNegative(raw.box.value, 0)
		-- A timestamp from the future (clock skew between servers) must not block or
		-- multiply production: clamp it to now.
		p.box.t = if isFiniteNumber(raw.box.t) then math.min(raw.box.t, now) else now
	end
	if type(raw.carried) == "table" then
		p.carried.orbs = math.floor(nonNegative(raw.carried.orbs, 0))
		p.carried.value = nonNegative(raw.carried.value, 0)
		if p.carried.orbs == 0 then
			p.carried.value = 0
		end
	end

	p.tutorial = integerIn(raw.tutorial, 1, Tutorial.Done, 1)

	if type(raw.discovered) == "table" then
		for id, flag in raw.discovered do
			if type(id) == "string" and flag == true then
				p.discovered[id] = true
			end
		end
	end
	for _, unit in p.units do
		p.discovered[unit.id] = true
	end

	if type(raw.stats) == "table" then
		for key in p.stats do
			p.stats[key] = math.floor(nonNegative(raw.stats[key], 0))
		end
	end
	if type(raw.settings) == "table" then
		for key, default in p.settings do
			local v = raw.settings[key]
			p.settings[key] = if type(v) == "boolean" then v else default
		end
	end

	p.createdAt = if isFiniteNumber(raw.createdAt) then raw.createdAt else now
	p.lastSeen = if isFiniteNumber(raw.lastSeen) then raw.lastSeen else now

	return p, issues
end

-- What the owning client receives. Strips internal bookkeeping.
function ProfileSchema.publicView(profile: { [string]: any }): { [string]: any }
	return {
		cash = profile.cash,
		units = profile.units,
		slots = profile.slots,
		crates = profile.crates,
		upgrades = profile.upgrades,
		box = profile.box,
		carried = profile.carried,
		tutorial = profile.tutorial,
		discovered = profile.discovered,
		stats = profile.stats,
		settings = profile.settings,
	}
end

return ProfileSchema
