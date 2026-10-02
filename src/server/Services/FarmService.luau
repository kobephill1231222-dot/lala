--!strict
-- Farm ownership and the farm's world representation: which farm belongs to whom, the
-- Sorcerers standing on production slots, Crates sitting on Crate Pads, lock states, the
-- owner's sign, the Orb Box numbers clients animate from, and the orb box a player carries.
-- Interaction prompts are created client-side; the server validates every request.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.FarmLayout)
local Rarities = require(Shared.Config.Rarities)
local Sorcerers = require(Shared.Config.Sorcerers)
local Economy = require(Shared.Rules.Economy)
local CharacterModels = require(Shared.Visuals.CharacterModels)
local CrateModels = require(Shared.Visuals.CrateModels)

type SlotView = { uid: string?, id: string?, level: number?, model: Model? }
type PadView = { cid: string?, tier: string?, readyAt: number?, model: Model? }

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

local RING = {
	Locked = Color3.fromRGB(70, 66, 76),
	Empty = Color3.fromRGB(255, 214, 120),
}

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

local function setSign(farm: Farm)
	local sign = farm.model:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("SignGui")
	local title = gui and gui:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = if farm.owner then farm.owner.DisplayName .. "'s Farm" else "Empty Farm"
	end
end

local function makeLabel(parent: BasePart, height: number, lines: { { text: string, color: Color3 } })
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(180, 22 * #lines)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height + 1.2, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.Name = "Line" .. i
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0, (i - 1) / #lines)
		label.Size = UDim2.fromScale(1, 1 / #lines)
		label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
		label.TextScaled = true
		label.Text = line.text
		label.TextColor3 = line.color
		label.TextStrokeTransparency = 0.25
		label.Parent = gui
	end
	gui.Parent = parent
end

local function clearSlot(view: SlotView)
	if view.model then
		view.model:Destroy()
	end
	view.model, view.uid, view.id, view.level = nil, nil, nil, nil
end

local function placeSorcerer(farm: Farm, slot: number, uid: string, unit: any, profile: any)
	local def = Sorcerers.get(unit.id)
	if not def then
		return
	end
	local view = farm.slots[slot]
	local cf = Layout.slotWorld(farm.index, slot) * CFrame.new(0, 0.5, 0)
	local model = CharacterModels.build(def.id, cf, { aura = true, scale = CharacterModels.FarmScale })
	model.Name = "Sorcerer" .. slot
	model:SetAttribute("Uid", uid)
	model:SetAttribute("SorcererId", def.id)
	model:SetAttribute("Level", unit.level)
	model:SetAttribute("Slot", slot)
	model:SetAttribute("Farm", farm.index)
	model:SetAttribute("Ops", Economy.ops(unit))
	model:SetAttribute("OrbValue", Economy.orbValue(unit, profile))
	local rarity = Rarities.get(def.rarity)
	if model.PrimaryPart then
		makeLabel(model.PrimaryPart, CharacterModels.heightOf(def.id, CharacterModels.FarmScale), {
			{
				text = def.name .. "  Lv " .. unit.level,
				color = if rarity then rarity.glow else Color3.new(1, 1, 1),
			},
			{ text = def.rarity, color = if rarity then rarity.color else Color3.new(1, 1, 1) },
		})
	end
	model.Parent = farm.sorcerers
	view.model, view.uid, view.id, view.level = model, uid, unit.id, unit.level
end

local function clearPad(view: PadView)
	if view.model then
		view.model:Destroy()
	end
	view.model, view.cid, view.tier, view.readyAt = nil, nil, nil, nil
end

local function placeCrate(farm: Farm, pad: number, cid: string, crate: any)
	local view = farm.pads[pad]
	local cf = Layout.padWorld(farm.index, pad) * CFrame.new(0, 0.6, 0)
	local model = CrateModels.build(crate.tier, cf)
	model.Name = "Crate" .. pad
	model:SetAttribute("Cid", cid)
	model:SetAttribute("Pad", pad)
	model:SetAttribute("Farm", farm.index)
	model:SetAttribute("ReadyAt", crate.readyAt)
	model.Parent = farm.crates
	view.model, view.cid, view.tier, view.readyAt = model, cid, crate.tier, crate.readyAt
end

local function setLocked(part: Instance?, locked: boolean)
	if not part or not part:IsA("BasePart") then
		return
	end
	part:SetAttribute("Locked", locked)
	local ring = part:FindFirstChild("Ring")
	if ring and ring:IsA("BasePart") then
		ring.Color = if locked then RING.Locked else RING.Empty
		ring.Material = if locked then Enum.Material.Slate else Enum.Material.Neon
	end
	local lock = part:FindFirstChild("Lock")
	if lock and lock:IsA("BasePart") then
		lock.Transparency = if locked then 0 else 1
		for _, d in lock:GetDescendants() do
			if d:IsA("BasePart") then
				d.Transparency = if locked then 0 else 1
			end
		end
	end
end

-- Full sync of one farm with its owner's profile. Only rebuilds what changed.
local function renderFarm(farm: Farm)
	local session = farm.owner and services.DataService.getSession(farm.owner)
	local profile = session and session.profile
	local slotsFolder = farm.model:FindFirstChild("Slots")
	local padsFolder = farm.model:FindFirstChild("Pads")
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
		elseif view.model then
			view.model:SetAttribute("OrbValue", Economy.orbValue(unit, profile))
		end
		setLocked(slotsFolder and slotsFolder:FindFirstChild("Slot" .. slot), slot > unlockedSlots)
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
		setLocked(padsFolder and padsFolder:FindFirstChild("Pad" .. pad), pad > unlockedPads)
	end
	farm.model:SetAttribute("UnlockedSlots", unlockedSlots)
	farm.model:SetAttribute("UnlockedPads", unlockedPads)
end

-- The carried Orb Box: a glowing chest the player holds in front of them until they Sell.
-- It is welded to the character, so it is only ever positioned before the weld exists; a
-- change of size rebuilds it instead of moving a welded part (which would drag the player).
local function buildCarriedBox(root: BasePart, size: number): BasePart
	local cf = root.CFrame * CFrame.new(0, 0.3, -(1.1 + size / 2))
	local part = Instance.new("Part")
	part.Name = "CarriedOrbBox"
	part.Material = Enum.Material.WoodPlanks
	part.Color = Color3.fromRGB(110, 78, 54)
	part.Size = Vector3.new(size, size * 0.8, size)
	part.CFrame = cf
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part:SetAttribute("SizeKey", size)
	local glow = Instance.new("Part")
	glow.Name = "Glow"
	glow.Material = Enum.Material.Neon
	glow.Color = Color3.fromRGB(190, 110, 255)
	glow.Size = Vector3.new(size * 0.8, 0.2, size * 0.8)
	glow.CFrame = cf * CFrame.new(0, size * 0.4 + 0.05, 0)
	glow.CanCollide = false
	glow.CanQuery = false
	glow.CanTouch = false
	glow.Massless = true
	glow.CastShadow = false
	glow.Parent = part
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(190, 110, 255)
	light.Range = 8
	light.Brightness = 1.5
	light.Parent = glow
	local glowWeld = Instance.new("WeldConstraint")
	glowWeld.Part0 = part
	glowWeld.Part1 = glow
	glowWeld.Parent = glow
	local gui = Instance.new("BillboardGui")
	gui.Name = "Count"
	gui.Size = UDim2.fromOffset(150, 26)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(240, 220, 255)
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	gui.Parent = part
	local weld = Instance.new("WeldConstraint")
	weld.Name = "Weld"
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	return part
end

local function updateCarried(player: Player, orbs: number, value: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not root or not root:IsA("BasePart") then
		return
	end
	local existing = character:FindFirstChild("CarriedOrbBox")
	if orbs < 1 then
		if existing then
			existing:Destroy()
		end
		return
	end
	-- Grows with what you carry, in steps so it isn't rebuilt on every orb.
	local size = 1.6 + math.floor(math.min(1.4, math.log10(orbs) * 0.45) * 5 + 0.5) / 5
	if existing and existing:GetAttribute("SizeKey") ~= size then
		existing:Destroy()
		existing = nil
	end
	local box: Instance = existing or buildCarriedBox(root, size)
	box.Parent = character
	local gui = box:FindFirstChild("Count")
	local label = gui and gui:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = string.format("%d Cursed Orbs", orbs)
	end
	box:SetAttribute("Orbs", orbs)
	box:SetAttribute("Value", value)
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
			setSign(farm)
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
	setSign(farm)
	renderFarm(farm)
end

function FarmService.render(player: Player)
	local farm = byPlayer[player]
	if farm then
		renderFarm(farm)
	end
end

-- Cheap per-state-change update: Orb Box numbers and the carried box.
function FarmService.sync(player: Player)
	local session = services.DataService.getSession(player)
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
	local session = services.DataService.getSession(player)
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
	local folder = child(mapFolder(), "Farms")
	for index = 1, Layout.FarmCount do
		local model = child(folder, "Farm" .. index) :: Model
		local runtime = model:FindFirstChild("Runtime")
		if runtime then
			runtime:Destroy()
		end
		local newRuntime = Instance.new("Folder")
		newRuntime.Name = "Runtime"
		newRuntime.Parent = model
		local sorcerers = Instance.new("Folder")
		sorcerers.Name = "Sorcerers"
		sorcerers.Parent = newRuntime
		local crates = Instance.new("Folder")
		crates.Name = "Crates"
		crates.Parent = newRuntime
		local farm: Farm = {
			index = index,
			model = model,
			owner = nil,
			sorcerers = sorcerers,
			crates = crates,
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
		setSign(farm)
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
