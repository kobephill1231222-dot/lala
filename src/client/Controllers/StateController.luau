--!nonstrict
-- Mirrors the server's view of the local player's profile and wraps requests.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Rules.Economy)
local Signal = require(Shared.Util.Signal)

local StateController = {}

StateController.profile = nil :: any
StateController.Changed = Signal.new()
StateController.Notified = Signal.new()
StateController.Effect = Signal.new()
StateController.Ready = Signal.new()

local remotes: any
local readyFired = false
local busy: { [string]: boolean } = {}

function StateController.init(registry: any)
	remotes = registry.Remotes
	remotes.State.OnClientEvent:Connect(function(view)
		local previous = StateController.profile
		StateController.profile = view
		StateController.Changed:Fire(view, previous)
		if not readyFired then
			readyFired = true
			StateController.Ready:Fire(view)
		end
	end)
	remotes.Notify.OnClientEvent:Connect(function(kind, payload)
		StateController.Notified:Fire(kind, payload)
	end)
	remotes.Effect.OnClientEvent:Connect(function(name, payload)
		StateController.Effect:Fire(name, payload)
	end)
end

function StateController.start()
	task.spawn(function()
		-- Ask for a snapshot in case the initial push arrived before we connected.
		while not readyFired do
			pcall(function()
				remotes.Request:InvokeServer("GetState", {})
			end)
			task.wait(3)
		end
	end)
end

function StateController.isReady(): boolean
	return readyFired
end

-- Sends an action. Returns the server result table. Failures are surfaced as toasts unless
-- `silent` is true. Prevents double-submits of the same action while one is in flight.
function StateController.request(action: string, payload: { [string]: any }?, silent: boolean?): any
	local key = action .. (if payload and payload.uid then payload.uid else "")
	if busy[key] then
		return { ok = false, message = "Working..." }
	end
	busy[key] = true
	local ok, result = pcall(function()
		return remotes.Request:InvokeServer(action, payload or {})
	end)
	busy[key] = nil
	if not ok or type(result) ~= "table" then
		result = { ok = false, message = "Connection hiccup. Please try again." }
	end
	if not result.ok and not silent and result.message then
		StateController.Notified:Fire("Toast", { text = result.message, tone = "bad" })
	end
	return result
end

-- Derived values -----------------------------------------------------------------------

function StateController.now(): number
	return workspace:GetServerTimeNow()
end

function StateController.rate(): number
	local p = StateController.profile
	return if p then Economy.totalRate(p) else 0
end

function StateController.wellCapacity(): number
	local p = StateController.profile
	return if p then Economy.wellCapacity(p) else 0
end

function StateController.wellStored(): number
	local p = StateController.profile
	if not p then
		return 0
	end
	return Economy.wellStoredAt(p, StateController.now())
end

function StateController.placedSpot(uid: string): number?
	local p = StateController.profile
	if not p then
		return nil
	end
	for spot, placed in p.spots do
		if placed == uid then
			return tonumber(spot)
		end
	end
	return nil
end

return StateController
