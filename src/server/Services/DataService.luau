--!strict
-- Player data lifecycle: load on join, autosave, save + release on leave and shutdown.
--
-- Safety rules:
--  * A default profile is only created when the store confirms there is no record.
--  * Data that can't be read (wrong shape, or saved by a newer game version) is refused: the
--    player is asked to rejoin, nothing is written over it, and corrupt records are marked
--    in their metadata for manual recovery.
--  * The session lock is a lease (see ProfileStore). This server stops accepting changes
--    well before its lease could expire, so another server can never take over a profile
--    that is still being changed here. Each successful save renews the lease.
--  * When another server is waiting for a profile this server holds, it asks (via
--    MessagingService) for an immediate save-and-release.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
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
	offline: any?, -- Actions.claimOffline report for this join
	leaseUntil: number, -- wall-clock time after which changes are refused until a save lands
	retryPending: boolean,
}

local DataService = {}
DataService.Loaded = Signal.new()
DataService.Removing = Signal.new()
DataService.persistent = true

local sessions: { [Player]: Session } = {}
local profileStore: ProfileStore.ProfileStore
local shuttingDown = false
local jobId = ""

local RELEASE_TOPIC = "JJKFarm_ReleaseProfile"
-- Stop accepting changes this long before the lease could expire.
local LEASE_MARGIN = 60
local SAVE_RETRY_DELAY = 15

-- Wall clock used for leases (os.time on servers; tests may replace it).
DataService.clock = os.time

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
				"[JJK Farm] DataStore unavailable in Studio; using a temporary in-memory store (progress won't save)."
			)
			return MockDataStore.new(), false
		end
	elseif not ok then
		if RunService:IsStudio() then
			return MockDataStore.new(), false
		end
		warn("[JJK Farm] Could not open DataStore:", store)
		-- A store whose every call fails: players get the safe "please rejoin" kick.
		return {
			UpdateAsync = function()
				error("DataStore unavailable")
			end,
		}, true
	end
	return store, true
end

local function renewLease(session: Session, since: number)
	session.leaseUntil = since + GameConfig.SessionLockStaleSeconds - LEASE_MARGIN
end

local saveSession: (Session, boolean) -> ()

local function scheduleRetry(session: Session)
	if session.retryPending or session.left or session.released then
		return
	end
	session.retryPending = true
	task.delay(SAVE_RETRY_DELAY, function()
		session.retryPending = false
		if not session.left and not session.released then
			saveSession(session, false)
		end
	end)
end

function saveSession(session: Session, release: boolean)
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
	local started = DataService.clock()
	Actions.settleBox(session.profile, t)
	session.profile.lastSeen = t
	local status, reason = profileStore:save(session.key, session.profile, release, GameConfig.SaveRetries)
	session.saving = false
	if status == "ok" then
		if release then
			session.released = true
		else
			-- The lease was renewed at some point after `started`.
			renewLease(session, started)
		end
	elseif status == "lost" then
		-- Another server owns this profile now; stop writing and disconnect the stale copy.
		session.released = true
		warn("[JJK Farm] Lost session lock for", session.key, reason)
		if not session.left then
			session.player:Kick("Your farm was opened on another server. Please rejoin.")
		end
	else
		warn("[JJK Farm] Save failed for", session.key, reason)
		if not release then
			scheduleRetry(session)
		end
	end
end

local KICK = {
	error = "We couldn't load your farm right now. Your progress is safe - please rejoin in a moment.",
	locked = "Your farm is still open on another server. Please rejoin in a moment.",
	newer = "This server is running an older version of JJK Farm. Please rejoin to get an updated server.",
	corrupt = "We couldn't read your saved farm, so we haven't changed it. Please rejoin later; if this keeps happening, contact the game's creator.",
}

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
		offline = nil,
		leaseUntil = 0,
		retryPending = false,
	}
	sessions[player] = session

	local loadStarted = DataService.clock()
	local status, raw = profileStore:load(session.key)
	if session.left or shuttingDown then
		if status == "ok" then
			profileStore:releaseLock(session.key)
		end
		sessions[player] = nil
		return
	end
	local refusal: string? = if status ~= "ok" then status else nil
	if refusal == nil and raw ~= nil then
		-- The store has a record for this player: it must be readable, or we refuse it.
		local valid, problem, kind = ProfileSchema.validate(raw)
		if not valid then
			refusal = kind or "corrupt"
			warn("[JJK Farm] Refusing stored profile", session.key, problem)
			profileStore:releaseLock(session.key, if refusal == "corrupt" then problem else nil)
		end
	end
	if refusal then
		warn("[JJK Farm] Load refused for", session.key, refusal, raw)
		sessions[player] = nil
		player:Kick(KICK[refusal] or KICK.error)
		return
	end
	renewLease(session, loadStarted)

	local t = now()
	local profile
	if raw == nil then
		-- Only here, when the store confirmed there is no record, do we create defaults.
		profile = ProfileSchema.new(t)
		session.isNew = true
	else
		local issues
		profile, issues = ProfileSchema.sanitize(raw, t)
		if #issues > 0 then
			warn("[JJK Farm] Repaired profile", session.key, table.concat(issues, "; "))
		end
	end

	-- Offline progress is claimed exactly once per load: it moves the Orb Box timestamp to
	-- now, and that timestamp is what gets saved. The session lock guarantees no other server
	-- holds this profile at the same time, so the same absence can't be claimed twice.
	if not session.isNew then
		session.offline = Actions.claimOffline(profile, t)
	end
	profile.lastSeen = t
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

-- The session, if this server may change it right now. Refused while the lease is close to
-- expiring (saves have been failing): another server could otherwise take over a profile that
-- is still changing here.
function DataService.getSession(player: Player): Session?
	local session = sessions[player]
	if session and session.loaded and not session.released and DataService.clock() < session.leaseUntil then
		return session
	end
	return nil
end

-- The session for display only (state replication, farm visuals). Never use it to change data.
function DataService.peekSession(player: Player): Session?
	local session = sessions[player]
	if session and session.loaded and not session.released then
		return session
	end
	return nil
end

-- True when the player's data is loaded but changes are paused until a save renews the lease.
function DataService.isPaused(player: Player): boolean
	local session = sessions[player]
	return session ~= nil
		and session.loaded
		and not session.released
		and DataService.clock() >= session.leaseUntil
end

-- Another server wants a profile we hold: save and release it now. If the player is somehow
-- still here, they're disconnected first so nothing changes after the release.
local function onReleaseRequest(message: any)
	local data = type(message) == "table" and message.Data
	if type(data) ~= "table" or data.holder ~= jobId or type(data.key) ~= "string" then
		return
	end
	for player, session in sessions do
		if session.key == data.key and session.loaded and not session.released then
			if not session.left then
				session.left = true
				DataService.Removing:Fire(player, session)
				saveSession(session, true)
				player:Kick("You joined JJK Farm on another server.")
			end
			-- Otherwise the leave path is already saving and releasing.
		end
	end
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
	jobId = game.JobId
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
		now = function()
			return DataService.clock()
		end,
		wait = function(seconds: number)
			task.wait(seconds)
		end,
		maxVersion = GameConfig.DataVersion,
		requestRelease = function(key: string, holder: string)
			if persistent then
				MessagingService:PublishAsync(RELEASE_TOPIC, { key = key, holder = holder })
			end
		end,
	})
	if persistent then
		pcall(function()
			MessagingService:SubscribeAsync(RELEASE_TOPIC, onReleaseRequest)
		end)
	end
	DataService._onReleaseRequest = onReleaseRequest -- for tests

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
