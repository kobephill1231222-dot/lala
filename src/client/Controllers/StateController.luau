--!nonstrict
-- Mirrors the server's view of the local player's profile and wraps requests.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crates = require(Shared.Config.Crates)
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
	local key = action
		.. (if payload and payload.uid then payload.uid else "")
		.. (if payload and payload.pad then "p" .. payload.pad else "")
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

-- Orbs per Second and Cash per second of Your Farm.
function StateController.totals(): (number, number)
	local p = StateController.profile
	if not p then
		return 0, 0
	end
	return Economy.totals(p)
end

-- Orb Box contents right now (orbs, value) and its capacity.
function StateController.box(): (number, number, number)
	local p = StateController.profile
	if not p then
		return 0, 0, 0
	end
	local orbs, value = Economy.boxAt(p, StateController.now())
	return orbs, value, Economy.boxCapacity(p)
end

function StateController.farm(): number?
	local p = StateController.profile
	return p and p.farm
end

function StateController.farmModel(index: number?): Model?
	local i = index or StateController.farm()
	if not i then
		return nil
	end
	local map = workspace:FindFirstChild("JJKFarmMap")
	local farms = map and map:FindFirstChild("Farms")
	return farms and farms:FindFirstChild("Farm" .. i) :: Model?
end

function StateController.slotOf(uid: string): number?
	local p = StateController.profile
	if not p then
		return nil
	end
	for slot, placed in p.slots do
		if placed == uid then
			return tonumber(slot)
		end
	end
	return nil
end

-- (cid, crate) on a pad of Your Farm
function StateController.crateOnPad(pad: number): (string?, any)
	local p = StateController.profile
	if not p then
		return nil, nil
	end
	for cid, crate in p.crates do
		if crate.pad == pad then
			return cid, crate
		end
	end
	return nil, nil
end

-- Unplaced crates, best tier first, then oldest.
function StateController.unplacedCrates(): { { cid: string, tier: string } }
	local p = StateController.profile
	local list = {}
	if not p then
		return list
	end
	for cid, crate in p.crates do
		if not crate.pad then
			table.insert(list, { cid = cid, tier = crate.tier })
		end
	end
	table.sort(list, function(a, b)
		local ca, cb = Crates.get(a.tier), Crates.get(b.tier)
		local oa, ob = if ca then ca.order else 0, if cb then cb.order else 0
		if oa ~= ob then
			return oa > ob
		end
		return (tonumber(a.cid) or 0) < (tonumber(b.cid) or 0)
	end)
	return list
end

-- Owned sorcerers sorted by income, best first; not-yet-placed ones first when asked.
function StateController.sortedUnits(
	unplacedFirst: boolean?
): { { uid: string, unit: any, income: number, slot: number? } }
	local p = StateController.profile
	local list = {}
	if not p then
		return list
	end
	for uid, unit in p.units do
		table.insert(
			list,
			{ uid = uid, unit = unit, income = Economy.income(unit, p), slot = StateController.slotOf(uid) }
		)
	end
	table.sort(list, function(a, b)
		if unplacedFirst and (a.slot == nil) ~= (b.slot == nil) then
			return a.slot == nil
		end
		if a.income ~= b.income then
			return a.income > b.income
		end
		return (tonumber(a.uid) or 0) < (tonumber(b.uid) or 0)
	end)
	return list
end

function StateController.firstEmptySlot(): number?
	local p = StateController.profile
	if not p then
		return nil
	end
	for slot = 1, Economy.unlockedSlots(p) do
		if not p.slots[tostring(slot)] then
			return slot
		end
	end
	return nil
end

function StateController.firstEmptyPad(): number?
	local p = StateController.profile
	if not p then
		return nil
	end
	for pad = 1, Economy.unlockedPads(p) do
		if not StateController.crateOnPad(pad) then
			return pad
		end
	end
	return nil
end

return StateController
