--!strict
-- Profile shape, defaults, migration and validation.
-- `sanitize` repairs malformed fields but never discards data it doesn't understand:
-- units with unknown ids are moved to `orphanUnits` and written back untouched.

local Config = script.Parent.Parent.Config
local Characters = require(Config.Characters)
local GameConfig = require(Config.GameConfig)
local Rarities = require(Config.Rarities)
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
	return {
		version = GameConfig.DataVersion,
		energy = 0,
		seals = 0,
		lifetimeEnergy = 0,
		units = {},
		nextUid = 1,
		spots = {},
		unlockedSpots = GameConfig.StartingSpots,
		upgrades = { production = 0, capacity = 0, combat = 0, luck = 0 },
		well = { stored = 0, t = now },
		tutorial = 1,
		pity = 0,
		discovered = {},
		stats = { summons = 0, kills = 0, collected = 0, sessions = 0 },
		settings = { music = true, sfx = true },
		orphanUnits = {},
		createdAt = now,
		lastSeen = now,
	}
end

-- Brand-new player: starter spirit already working on spot 1 and a pre-filled well.
function ProfileSchema.new(now: number): { [string]: any }
	local profile = emptyProfile(now)
	profile.units["1"] = { id = Characters.StarterId, level = 1, t = now }
	profile.nextUid = 2
	profile.spots["1"] = "1"
	profile.discovered[Characters.StarterId] = true
	profile.well.stored = GameConfig.WellStartingEnergy
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

	p.energy = nonNegative(raw.energy, 0)
	p.seals = math.floor(nonNegative(raw.seals, 0))
	p.lifetimeEnergy = nonNegative(raw.lifetimeEnergy, p.energy)
	if raw.energy ~= nil and p.energy ~= raw.energy then
		table.insert(issues, "energy repaired")
	end

	-- Units
	local maxUid = 0
	if type(raw.units) == "table" then
		for key, unit in raw.units do
			local uid = tostring(key)
			if type(unit) == "table" and type(unit.id) == "string" then
				local def = Characters.get(unit.id)
				if def then
					local rarity = Rarities.get(def.rarity)
					local maxLevel = if rarity then rarity.maxLevel else 1
					p.units[uid] = {
						id = unit.id,
						level = integerIn(unit.level, 1, maxLevel, 1),
						t = if isFiniteNumber(unit.t) then unit.t else now,
					}
				else
					p.orphanUnits[uid] = unit
					table.insert(issues, "unknown unit id preserved: " .. unit.id)
				end
			else
				table.insert(issues, "malformed unit dropped: " .. uid)
			end
			-- Count every key (even dropped ones) so uids are never reused.
			local n = tonumber(uid)
			if n and n > maxUid then
				maxUid = n
			end
		end
	end
	if type(raw.orphanUnits) == "table" then
		for uid, unit in raw.orphanUnits do
			local key = tostring(uid)
			if type(unit) == "table" and type(unit.id) == "string" and Characters.get(unit.id) then
				-- A previously unknown character exists again: restore it.
				if p.units[key] == nil then
					local def = Characters.get(unit.id) :: any
					local rarity = Rarities.get(def.rarity)
					local maxLevel = if rarity then rarity.maxLevel else 1
					p.units[key] = { id = unit.id, level = integerIn(unit.level, 1, maxLevel, 1), t = now }
				end
			else
				p.orphanUnits[key] = unit
			end
			local n = tonumber(key)
			if n and n > maxUid then
				maxUid = n
			end
		end
	end
	p.nextUid = math.max(integerIn(raw.nextUid, 1, 1e12, 1), maxUid + 1)

	p.unlockedSpots =
		integerIn(raw.unlockedSpots, GameConfig.StartingSpots, GameConfig.SpotCount, GameConfig.StartingSpots)

	-- Placements: each spot within the unlocked range holds at most one existing unit,
	-- and each unit occupies at most one spot.
	if type(raw.spots) == "table" then
		local used: { [string]: boolean } = {}
		for spotKey, uid in raw.spots do
			local spot = tonumber(spotKey)
			local uidKey = tostring(uid)
			if
				spot
				and spot == math.floor(spot)
				and spot >= 1
				and spot <= p.unlockedSpots
				and p.units[uidKey]
				and not used[uidKey]
			then
				p.spots[tostring(spot)] = uidKey
				used[uidKey] = true
			else
				table.insert(issues, "invalid placement removed: " .. tostring(spotKey))
			end
		end
	end

	if type(raw.upgrades) == "table" then
		for id, def in Upgrades.ById do
			p.upgrades[id] = integerIn(raw.upgrades[id], 0, def.maxLevel, 0)
		end
	end

	if type(raw.well) == "table" then
		p.well.stored = nonNegative(raw.well.stored, 0)
		p.well.t = if isFiniteNumber(raw.well.t) then math.min(raw.well.t, now) else now
	end

	p.tutorial = integerIn(raw.tutorial, 1, Tutorial.Done, 1)
	p.pity = integerIn(raw.pity, 0, 1e9, 0)

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
		energy = profile.energy,
		seals = profile.seals,
		lifetimeEnergy = profile.lifetimeEnergy,
		units = profile.units,
		spots = profile.spots,
		unlockedSpots = profile.unlockedSpots,
		upgrades = profile.upgrades,
		well = profile.well,
		tutorial = profile.tutorial,
		pity = profile.pity,
		discovered = profile.discovered,
		stats = profile.stats,
		settings = profile.settings,
	}
end

return ProfileSchema
