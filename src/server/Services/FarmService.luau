--!strict
-- Farm ownership and what each farm holds, published for every client to draw: which farm
-- belongs to whom, the Sorcerers on its production slots, the Crates on its Crate Pads, how
-- many slots and pads are unlocked, the Orb Box numbers clients animate from, and the orbs each
-- player is carrying. Everything is data (attributes and Folders): the pixel client draws it.
-- Interaction happens client-side; the server validates every request.
--
--   Workspace.JJKFarmMap.Farms.Farm<i>             OwnerId, OwnerName, Ops, CashRate, BoxOrbs,
--                                                 BoxValue, BoxT, BoxCap, UnlockedSlots, UnlockedPads
--     Runtime.Sorcerers.Sorcerer<slot> (Folder)   Uid, SorcererId, Level, Slot, Farm, Ops, OrbValue
--     Runtime.Crates.Crate<pad> (Folder)          Cid, Tier, Pad, Farm, ReadyAt
--   Player                                        CarriedOrbs, CarriedValue

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.FarmLayout)
local Sorcerers = require(Shared.Config.Sorcerers)
local Economy = require(Shared.Rules.Economy)

type SlotView = { uid: string?, id: string?, level: number?, item: Folder? }
type PadView = { cid: string?, tier: string?, readyAt: number?, item: Folder? }

type Farm = {
	index: number,
	model: Model,
	owner: Player?,
	sorcerers: Folder,
	crates: Folder,
	slots: { SlotView },
	pads: { PadView },
}

local FarmService = {}

local services: any
local farms: { Farm } = {}
local byPlayer: { [Player]: Farm } = {}

local function mapFolder(): Instance
	local map = workspace:FindFirstChild("JJKFarmMap")
	assert(map, "JJKFarmMap missing; MapService.ensure() must run first")
	return map
end

local function child(parent: Instance, name: string): Instance
	local found = parent:FindFirstChild(name)
	assert(found, "map is missing " .. parent:GetFullName() .. "." .. name)
	return found
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function clearSlot(view: SlotView)
	if view.item then
		view.item:Destroy()
	end
	view.item, view.uid, view.id, view.level = nil, nil, nil, nil
end

local function placeSorcerer(farm: Farm, slot: number, uid: string, unit: any, profile: any)
	local def = Sorcerers.get(unit.id)
	if not def then
		return
	end
	local view = farm.slots[slot]
	local item = Instance.new("Folder")
	item.Name = "Sorcerer" .. slot
	item:SetAttribute("Uid", uid)
	item:SetAttribute("SorcererId", def.id)
	item:SetAttribute("Level", unit.level)
	item:SetAttribute("Slot", slot)
	item:SetAttribute("Farm", farm.index)
	item:SetAttribute("Ops", Economy.ops(unit))
	item:SetAttribute("OrbValue", Economy.orbValue(unit, profile))
	item.Parent = farm.sorcerers
	view.item, view.uid, view.id, view.level = item, uid, unit.id, unit.level
end

local function clearPad(view: PadView)
	if view.item then
		view.item:Destroy()
	end
	view.item, view.cid, view.tier, view.readyAt = nil, nil, nil, nil
end

local function placeCrate(farm: Farm, pad: number, cid: string, crate: any)
	local view = farm.pads[pad]
	local item = Instance.new("Folder")
	item.Name = "Crate" .. pad
	item:SetAttribute("Cid", cid)
	item:SetAttribute("Tier", crate.tier)
	item:SetAttribute("Pad", pad)
	item:SetAttribute("Farm", farm.index)
	item:SetAttribute("ReadyAt", crate.readyAt)
	item.Parent = farm.crates
	view.item, view.cid, view.tier, view.readyAt = item, cid, crate.tier, crate.readyAt
end

-- Full sync of one farm with its owner's profile. Only rebuilds what changed.
local function renderFarm(farm: Farm)
	local session = farm.owner and services.DataService.peekSession(farm.owner)
	local profile = session and session.profile
	local unlockedSlots = if profile then Economy.unlockedSlots(profile) else 0
	local unlockedPads = if profile then Economy.unlockedPads(profile) else 0

	for slot = 1, GameConfig.SlotCount do
		local view = farm.slots[slot]
		local uid = profile and profile.slots[tostring(slot)]
		local unit = uid and profile.units[uid]
		if not unit then
			clearSlot(view)
		elseif view.uid ~= uid or view.id ~= unit.id or view.level ~= unit.level then
			clearSlot(view)
			placeSorcerer(farm, slot, uid, unit, profile)
		elseif view.item then
			view.item:SetAttribute("OrbValue", Economy.orbValue(unit, profile))
		end
	end

	local onPad: { [number]: { cid: string, crate: any } } = {}
	if profile then
		for cid, crate in profile.crates do
			if crate.pad then
				onPad[crate.pad] = { cid = cid, crate = crate }
			end
		end
	end
	for pad = 1, GameConfig.PadCount do
		local view = farm.pads[pad]
		local entry = onPad[pad]
		if not entry then
			clearPad(view)
		elseif view.cid ~= entry.cid or view.readyAt ~= entry.crate.readyAt then
			clearPad(view)
			placeCrate(farm, pad, entry.cid, entry.crate)
		end
	end
	farm.model:SetAttribute("UnlockedSlots", unlockedSlots)
	farm.model:SetAttribute("UnlockedPads", unlockedPads)
end

-- What a player carries (drawn by every client above that player).
local function updateCarried(player: Player, orbs: number, value: number)
	local whole = math.floor(orbs)
	if player:GetAttribute("CarriedOrbs") ~= whole then
		player:SetAttribute("CarriedOrbs", whole)
	end
	if player:GetAttribute("CarriedValue") ~= value then
		player:SetAttribute("CarriedValue", value)
	end
end

---------------------------------------------------------------------------------------

function FarmService.farmOf(player: Player): number?
	local farm = byPlayer[player]
	return if farm then farm.index else nil
end

function FarmService.ownerOf(index: number): Player?
	local farm = farms[index]
	return farm and farm.owner
end

function FarmService.model(index: number): Model?
	local farm = farms[index]
	return farm and farm.model
end

function FarmService.assign(player: Player): number?
	if byPlayer[player] then
		return byPlayer[player].index
	end
	for _, farm in farms do
		if not farm.owner then
			farm.owner = player
			byPlayer[player] = farm
			farm.model:SetAttribute("OwnerId", player.UserId)
			farm.model:SetAttribute("OwnerName", player.DisplayName)
			return farm.index
		end
	end
	return nil
end

function FarmService.release(player: Player)
	local farm = byPlayer[player]
	if not farm then
		return
	end
	byPlayer[player] = nil
	farm.owner = nil
	for _, view in farm.slots do
		clearSlot(view)
	end
	for _, view in farm.pads do
		clearPad(view)
	end
	for _, name in { "OwnerId", "OwnerName", "Ops", "BoxOrbs", "BoxValue", "BoxT", "BoxCap" } do
		farm.model:SetAttribute(name, nil)
	end
	renderFarm(farm)
end

function FarmService.render(player: Player)
	local farm = byPlayer[player]
	if farm then
		renderFarm(farm)
	end
end

-- Cheap per-state-change update: Orb Box numbers and what the player carries.
function FarmService.sync(player: Player)
	local session = services.DataService.peekSession(player)
	if not session then
		return
	end
	local profile = session.profile
	local farm = byPlayer[player]
	if farm then
		local ops, cash = Economy.totals(profile)
		local m = farm.model
		m:SetAttribute("Ops", ops)
		m:SetAttribute("CashRate", cash)
		m:SetAttribute("BoxOrbs", profile.box.orbs)
		m:SetAttribute("BoxValue", profile.box.value)
		m:SetAttribute("BoxT", profile.box.t)
		m:SetAttribute("BoxCap", Economy.boxCapacity(profile))
	end
	updateCarried(player, profile.carried.orbs, profile.carried.value)
end

function FarmService.homeCFrame(player: Player): CFrame
	local farm = byPlayer[player]
	if farm then
		return Layout.homeCFrame(farm.index)
	end
	return CFrame.new(Layout.SpawnPosition + Vector3.new(0, 3, 0))
end

function FarmService.inOwnFarm(player: Player, position: Vector3): boolean
	local farm = byPlayer[player]
	return farm ~= nil and Layout.inFarm(farm.index, position)
end

local function applyCharacter(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local session = services.DataService.peekSession(player)
	if humanoid and session then
		humanoid.WalkSpeed = Economy.walkSpeed(session.profile)
	end
end

function FarmService.applyWalkSpeed(player: Player)
	if player.Character then
		applyCharacter(player, player.Character)
	end
end

function FarmService.spawnAtFarm(player: Player)
	local character = player.Character
	if character then
		character:PivotTo(FarmService.homeCFrame(player))
		applyCharacter(player, character)
		FarmService.sync(player)
	end
end

function FarmService.init(registry: any)
	services = registry
end

function FarmService.start()
	local farmsFolder = child(mapFolder(), "Farms")
	for index = 1, Layout.FarmCount do
		local model = child(farmsFolder, "Farm" .. index) :: Model
		local runtime = model:FindFirstChild("Runtime")
		if runtime then
			runtime:Destroy()
		end
		local newRuntime = folder(model, "Runtime")
		local farm: Farm = {
			index = index,
			model = model,
			owner = nil,
			sorcerers = folder(newRuntime, "Sorcerers"),
			crates = folder(newRuntime, "Crates"),
			slots = {},
			pads = {},
		}
		for slot = 1, GameConfig.SlotCount do
			farm.slots[slot] = {}
		end
		for pad = 1, GameConfig.PadCount do
			farm.pads[pad] = {}
		end
		farms[index] = farm
		renderFarm(farm)
	end

	local function hookCharacter(player: Player)
		player.CharacterAdded:Connect(function(character)
			-- Wait a frame so the default spawn has finished positioning the character.
			task.defer(function()
				if character.Parent and byPlayer[player] then
					character:PivotTo(FarmService.homeCFrame(player))
				end
				applyCharacter(player, character)
				FarmService.sync(player)
			end)
		end)
	end
	Players.PlayerAdded:Connect(hookCharacter)
	for _, player in Players:GetPlayers() do
		hookCharacter(player)
	end
end

return FarmService
