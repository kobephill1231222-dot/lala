--!strict
-- Profile shape, defaults, migration and validation.
-- `validate` decides whether stored data can be loaded at all. Data that isn't shaped like a
-- profile (wrong types where tables or numbers belong, or a newer version than this server
-- understands) is refused, so the server never replaces real progress with defaults.
-- `sanitize` then repairs individual values but never discards data it doesn't understand:
-- unknown or malformed sorcerers go to `orphanUnits`, unknown or malformed crates go to
-- `orphanCrates`, and both are written back untouched (and restored if they become valid).
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
		orphanCrates = {},
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

local TABLE_FIELDS = {
	"units",
	"slots",
	"crates",
	"upgrades",
	"box",
	"carried",
	"discovered",
	"stats",
	"settings",
	"orphanUnits",
	"orphanCrates",
}
local NUMBER_FIELDS = { "version", "cash", "nextUid", "nextCid", "tutorial", "createdAt", "lastSeen" }

-- Can this stored value be loaded as a profile? Returns (true) or (false, reason, kind)
-- where kind is "corrupt" or "newer". Missing fields are fine (they get defaults); fields of
-- the wrong type are not, because "repairing" them would silently wipe progress.
function ProfileSchema.validate(raw: any): (boolean, string?, string?)
	if type(raw) ~= "table" then
		return false, "profile is a " .. type(raw) .. ", not a table", "corrupt"
	end
	for _, field in TABLE_FIELDS do
		local v = raw[field]
		if v ~= nil and type(v) ~= "table" then
			return false, string.format("%s is a %s", field, type(v)), "corrupt"
		end
	end
	for _, field in NUMBER_FIELDS do
		local v = raw[field]
		if v ~= nil and type(v) ~= "number" then
			return false, string.format("%s is a %s", field, type(v)), "corrupt"
		end
	end
	if type(raw.version) == "number" and raw.version > GameConfig.DataVersion then
		return false,
			string.format("saved by data version %d (this server: %d)", raw.version, GameConfig.DataVersion),
			"newer"
	end
	return true, nil, nil
end

-- Returns a clean profile plus a list of repairs that were made (for logging).
-- `raw` must have passed `validate`.
function ProfileSchema.sanitize(raw: any, now: number): ({ [string]: any }, { string })
	local issues: { string } = {}
	assert(ProfileSchema.validate(raw), "sanitize called on data that failed validate")
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
				p.orphanUnits[uid] = unit
				table.insert(issues, "malformed sorcerer preserved: " .. uid)
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

	-- Crates: each unlocked pad holds at most one crate; opening timestamps are kept as
	-- absolute times so crates finish while the player is away. Unknown tiers (renamed or
	-- from a newer release) go to `orphanCrates` and come back once the tier exists again;
	-- `Crates.Aliases` maps renamed tiers to their new id.
	local maxCid = 0
	local padUsed: { [number]: boolean } = {}
	local entries: { { key: any, crate: any } } = {}
	for _, source in { raw.crates, raw.orphanCrates } do
		if type(source) == "table" then
			for key, crate in source do
				table.insert(entries, { key = key, crate = crate })
			end
		end
	end
	-- Oldest crate first so a pad conflict always resolves the same way.
	table.sort(entries, function(a, b)
		return (tonumber(a.key) or math.huge) < (tonumber(b.key) or math.huge)
	end)
	do
		for _, entry in entries do
			local crate = entry.crate
			local cid = tostring(entry.key)
			if p.crates[cid] ~= nil or p.orphanCrates[cid] ~= nil then
				continue -- the same id in both lists: keep the first
			end
			maxCid = trackMax(cid, maxCid)
			local tier = if type(crate) == "table" and type(crate.tier) == "string"
				then Crates.Aliases[crate.tier] or crate.tier
				else nil
			if tier and Crates.get(tier) then
				local clean: { [string]: any } = { tier = tier }
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
				-- `remaining` 0 means the crate already finished opening: keep it.
				if clean.pad == nil and isFiniteNumber(crate.remaining) and crate.remaining >= 0 then
					clean.remaining = crate.remaining
				end
				p.crates[cid] = clean
			else
				p.orphanCrates[cid] = crate
				table.insert(issues, "unknown crate preserved: " .. cid)
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
