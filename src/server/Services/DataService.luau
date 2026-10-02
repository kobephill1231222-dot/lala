--!strict
-- Player data lifecycle: load on join, autosave, save + release on leave and shutdown.
-- Players whose data fails to load are kicked with a friendly message rather than being
-- given a default profile that could later overwrite their real progress.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Actions = require(Shared.Rules.Actions)
local ProfileSchema = require(Shared.Rules.ProfileSchema)
local Signal = require(Shared.Util.Signal)

local MockDataStore = require(script.Parent.Data.MockDataStore)
local ProfileStore = require(script.Parent.Data.ProfileStore)

export type Session = {
	player: Player,
	key: string,
	profile: any,
	loaded: boolean,
	left: boolean,
	released: boolean,
	saving: boolean,
	isNew: boolean,
	offlineGain: number,
	offlineSeconds: number,
	plot: number?,
	cooldowns: { [string]: number },
	spawnedOnce: boolean,
	lastTravel: number,
	lastCollectTouch: number,
}

local DataService = {}
DataService.Loaded = Signal.new()
DataService.Removing = Signal.new()
DataService.persistent = true

local sessions: { [Player]: Session } = {}
local profileStore: ProfileStore.ProfileStore
local shuttingDown = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function createBackingStore(): (any, boolean)
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStoreName)
	end)
	if ok and RunService:IsStudio() then
		-- Studio without "Enable Studio Access to API Services" errors on every request.
		local probeOk = pcall(function()
			store:GetAsync("__probe")
		end)
		if not probeOk then
			warn(
				"[Cursebound] DataStore unavailable in Studio; using a temporary in-memory store (progress won't save)."
			)
			return MockDataStore.new(), false
		end
	elseif not ok then
		if RunService:IsStudio() then
			return MockDataStore.new(), false
		end
		warn("[Cursebound] Could not open DataStore:", store)
		-- A store whose every call fails: players get the safe "please rejoin" kick.
		return {
			UpdateAsync = function()
				error("DataStore unavailable")
			end,
		}, true
	end
	return store, true
end

local function saveSession(session: Session, release: boolean)
	if not session.loaded or session.released then
		return
	end
	while session.saving do
		task.wait(0.1)
	end
	if session.released then
		return
	end
	session.saving = true
	local t = now()
	Actions.settleWell(session.profile, t)
	session.profile.lastSeen = t
	local status, reason = profileStore:save(session.key, session.profile, release, GameConfig.SaveRetries)
	session.saving = false
	if status == "ok" then
		if release then
			session.released = true
		end
	elseif status == "lost" then
		-- Another server owns this profile now; stop writing and disconnect the stale copy.
		session.released = true
		warn("[Cursebound] Lost session lock for", session.key, reason)
		if not session.left then
			session.player:Kick("Your sanctuary was opened on another server. Please rejoin.")
		end
	else
		warn("[Cursebound] Save failed for", session.key, reason)
	end
end

local function onPlayerAdded(player: Player)
	local session: Session = {
		player = player,
		key = "u_" .. player.UserId,
		profile = nil,
		loaded = false,
		left = false,
		released = false,
		saving = false,
		isNew = false,
		offlineGain = 0,
		offlineSeconds = 0,
		plot = nil,
		cooldowns = {},
		spawnedOnce = false,
		lastTravel = 0,
		lastCollectTouch = 0,
	}
	sessions[player] = session

	local status, raw = profileStore:load(session.key)
	if session.left or shuttingDown then
		if status == "ok" then
			profileStore:releaseLock(session.key)
		end
		return
	end
	if status ~= "ok" then
		warn("[Cursebound] Load failed for", session.key, raw)
		sessions[player] = nil
		player:Kick(
			"We couldn't load your sanctuary right now. Your progress is safe - please rejoin in a moment."
		)
		return
	end

	local t = now()
	local profile
	if raw == nil then
		profile = ProfileSchema.new(t)
		session.isNew = true
	else
		local issues
		profile, issues = ProfileSchema.sanitize(raw, t)
		if #issues > 0 then
			warn("[Cursebound] Repaired profile", session.key, table.concat(issues, "; "))
		end
	end

	local before = profile.well.stored
	Actions.settleWell(profile, t)
	session.offlineGain = profile.well.stored - before
	session.offlineSeconds = math.max(0, t - profile.lastSeen)
	profile.stats.sessions += 1

	session.profile = profile
	session.loaded = true
	DataService.Loaded:Fire(player, session)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	session.left = true
	if session.loaded then
		DataService.Removing:Fire(player, session)
		saveSession(session, true)
	end
	sessions[player] = nil
end

function DataService.getSession(player: Player): Session?
	local session = sessions[player]
	if session and session.loaded and not session.released then
		return session
	end
	return nil
end

function DataService.allSessions(): { Session }
	local list = {}
	for _, session in sessions do
		if session.loaded and not session.released then
			table.insert(list, session)
		end
	end
	return list
end

function DataService.start()
	local jobId = game.JobId
	if jobId == "" then
		jobId = "studio-" .. HttpService:GenerateGUID(false)
	end
	local store, persistent = createBackingStore()
	DataService.persistent = persistent
	profileStore = ProfileStore.new(store, {
		jobId = jobId,
		staleSeconds = GameConfig.SessionLockStaleSeconds,
		retries = GameConfig.LoadRetries,
		retryDelay = GameConfig.LoadRetryDelay,
		now = os.time,
		wait = function(seconds: number)
			task.wait(seconds)
		end,
	})

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Autosave, staggered so saves don't burst the DataStore budget.
	task.spawn(function()
		while true do
			task.wait(GameConfig.AutosaveInterval)
			local list = DataService.allSessions()
			local spacing = math.min(2, GameConfig.AutosaveInterval / math.max(1, #list) / 2)
			for _, session in list do
				if not session.left and not shuttingDown then
					task.spawn(saveSession, session, false)
					task.wait(spacing)
				end
			end
		end
	end)

	game:BindToClose(function()
		shuttingDown = true
		local pending = 0
		for _, session in sessions do
			if session.loaded and not session.released then
				pending += 1
				task.spawn(function()
					saveSession(session, true)
					pending -= 1
				end)
			end
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
