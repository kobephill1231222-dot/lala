--!nocheck
-- A minimal stand-in for the Roblox engine so the real server scripts can run inside Lune.
-- Provides signals (PlayerAdded, Heartbeat, Touched, remotes...), players and characters,
-- a controllable server clock, a shared mock DataStore, and records everything the server
-- sends to clients. It does not simulate physics or rendering.

local roblox = require("@lune/roblox")
local task = require("@lune/task")

local EngineShim = {}

-- Signals -----------------------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

function Signal.new(name)
	return setmetatable({ name = name, handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local entry = { fn = fn, connected = true }
	table.insert(self.handlers, entry)
	return {
		Connected = true,
		Disconnect = function(conn)
			entry.connected = false
			conn.Connected = false
		end,
	}
end

function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Fire(...)
	for _, entry in table.clone(self.handlers) do
		if entry.connected then
			task.spawn(entry.fn, ...)
		end
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:FireSync(...)
	for _, entry in table.clone(self.handlers) do
		if entry.connected then
			entry.fn(...)
		end
	end
end

EngineShim.Signal = Signal

-- Per-instance storage keyed by a hidden attribute id (Lune userdata aren't stable keys).
local nextId = 0
local store = {}
local function slot(inst)
	local id = inst:GetAttribute("__shimId")
	if not id then
		nextId += 1
		id = nextId
		inst:SetAttribute("__shimId", id)
	end
	store[id] = store[id] or {}
	return store[id]
end

local function signalProperty(className, prop)
	roblox.implementProperty(className, prop, function(inst)
		local s = slot(inst)
		s[prop] = s[prop] or Signal.new(prop)
		return s[prop]
	end)
end

-- Install ----------------------------------------------------------------------------------

function EngineShim.install(game, options)
	options = options or {}
	local state = {
		now = options.startTime or 1_700_000_000,
		outbox = {}, -- { remote, target, args }
		kicked = {},
		bindToClose = {},
		invokeHandlers = {},
		moveTargets = {},
		players = {},
		dataStore = options.dataStore,
	}
	EngineShim.state = state

	-- DataModel / services
	-- Reflected properties can't be re-implemented in Lune, but they can be written.
	game.JobId = options.jobId or "lune-server-1"
	roblox.implementMethod("DataModel", "BindToClose", function(_, fn)
		table.insert(state.bindToClose, fn)
	end)
	roblox.implementMethod("Workspace", "GetServerTimeNow", function()
		return state.now
	end)
	roblox.implementMethod("RunService", "IsStudio", function()
		return false
	end)
	roblox.implementMethod("RunService", "IsServer", function()
		return true
	end)
	signalProperty("RunService", "Heartbeat")
	signalProperty("RunService", "RenderStepped")
	roblox.implementMethod("DataStoreService", "GetDataStore", function()
		return state.dataStore
	end)

	-- Players
	signalProperty("Players", "PlayerAdded")
	signalProperty("Players", "PlayerRemoving")
	signalProperty("Player", "CharacterAdded")
	signalProperty("Player", "CharacterRemoving")
	roblox.implementMethod("Players", "GetPlayers", function(players)
		local list = {}
		for _, child in players:GetChildren() do
			if child:IsA("Player") then
				table.insert(list, child)
			end
		end
		return list
	end)
	roblox.implementMethod("Players", "GetPlayerFromCharacter", function(_, character)
		-- Return the same Player object the game was given (Lune creates a fresh userdata for
		-- every GetChildren call, and game code keys tables by Player like Roblox allows).
		for _, player in state.players do
			if player.Parent and player.Character == character then
				return player
			end
		end
		return nil
	end)
	roblox.implementMethod("Player", "Kick", function(player, message)
		table.insert(state.kicked, { player = player.Name, message = message })
	end)

	-- Remotes
	roblox.implementProperty("RemoteFunction", "OnServerInvoke", function(remote)
		return state.invokeHandlers[remote.Name]
	end, function(remote, fn)
		state.invokeHandlers[remote.Name] = fn
	end)
	signalProperty("RemoteEvent", "OnServerEvent")
	roblox.implementMethod("RemoteEvent", "FireClient", function(remote, player, ...)
		table.insert(state.outbox, { remote = remote.Name, target = player.Name, args = { ... } })
	end)
	roblox.implementMethod("RemoteEvent", "FireAllClients", function(remote, ...)
		table.insert(state.outbox, { remote = remote.Name, target = "*", args = { ... } })
	end)

	-- Parts, models, humanoids
	signalProperty("BasePart", "Touched")
	roblox.implementMethod("BasePart", "SetNetworkOwner", function() end)
	roblox.implementMethod("Model", "PivotTo", function(model, cf)
		local primary = model.PrimaryPart
		if not primary then
			return
		end
		local delta = cf * primary.CFrame:Inverse()
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.CFrame = delta * part.CFrame
			end
		end
	end)
	roblox.implementMethod("Model", "GetPivot", function(model)
		return if model.PrimaryPart then model.PrimaryPart.CFrame else roblox.CFrame.new()
	end)
	roblox.implementMethod("Humanoid", "MoveTo", function(humanoid, position)
		state.moveTargets[humanoid:GetFullName()] = position
	end)
	roblox.implementMethod("Humanoid", "TakeDamage", function(humanoid, amount)
		humanoid.Health = math.max(0, humanoid.Health - amount)
	end)

	-- Terrain: record calls only
	local terrainOps = 0
	for _, method in { "FillBlock", "FillBall", "FillCylinder", "FillWedge", "SetMaterialColor" } do
		roblox.implementMethod("Terrain", method, function()
			terrainOps += 1
		end)
	end
	state.terrainOps = function()
		return terrainOps
	end

	local workspace = game:GetService("Workspace")
	if not workspace:FindFirstChildOfClass("Terrain") then
		local terrain = roblox.Instance.new("Terrain")
		terrain.Parent = workspace
	end
	roblox.implementProperty("Workspace", "Terrain", function(ws)
		return ws:FindFirstChildOfClass("Terrain")
	end)
	return state
end

-- Roblox's Random, backed by a deterministic generator.
function EngineShim.Random()
	local Random = {}
	function Random.new(seed)
		local s = (seed or 12345) % 4294967296
		local r = {}
		function r:NextNumber(min, max)
			s = (s * 1664525 + 1013904223) % 4294967296
			local u = s / 4294967296
			if min and max then
				return min + (max - min) * u
			end
			return u
		end
		function r:NextInteger(min, max)
			return min + math.floor(r:NextNumber() * (max - min + 1))
		end
		return r
	end
	return Random
end

-- Helpers for scenarios ------------------------------------------------------------------

-- Creates a player with a simple R15-ish character standing at `position`.
function EngineShim.addPlayer(game, name, userId, position)
	local players = game:GetService("Players")
	local player = roblox.Instance.new("Player")
	player.Name = name
	player.UserId = userId
	player.DisplayName = name
	player.Parent = players
	EngineShim.state.players[userId] = player
	players.PlayerAdded:Fire(player)
	return player
end

function EngineShim.spawnCharacter(game, player, position)
	local character = roblox.Instance.new("Model")
	character.Name = player.Name
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = roblox.Vector3.new(2, 2, 1)
	root.CFrame = roblox.CFrame.new(position)
	root.Anchored = false
	root.Parent = character
	character.PrimaryPart = root
	local humanoid = roblox.Instance.new("Humanoid")
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.Parent = character
	character.Parent = game:GetService("Workspace")
	player.Character = character
	player.CharacterAdded:Fire(character)
	return character
end

function EngineShim.removePlayer(game, player)
	local players = game:GetService("Players")
	players.PlayerRemoving:FireSync(player)
	task.wait(0.05)
	if player.Character then
		player.Character:Destroy()
	end
	player.Parent = nil
end

function EngineShim.invoke(player, action, payload)
	local handler = EngineShim.state.invokeHandlers.Request
	assert(handler, "Request handler not registered")
	return handler(player, action, payload)
end

function EngineShim.heartbeat(game, dt, steps)
	local runService = game:GetService("RunService")
	for _ = 1, steps or 1 do
		runService.Heartbeat:FireSync(dt)
	end
end

-- Last message sent on `remote` to `playerName` (or broadcast with "*").
function EngineShim.lastSent(remote, playerName, filter)
	local outbox = EngineShim.state.outbox
	for i = #outbox, 1, -1 do
		local msg = outbox[i]
		if
			msg.remote == remote and (msg.target == playerName or (playerName == "*" and msg.target == "*"))
		then
			if not filter or filter(msg.args) then
				return msg.args
			end
		end
	end
	return nil
end

return EngineShim
