--!nonstrict
-- The interaction layer of the world: proximity prompts on Your Farm (Crate Pads, production
-- slots, the Orb Box) and in the plaza (Sell Stand, Crate Shop, Upgrade Shop), plus the
-- world labels: crate Opening Time timers, Orb Box counters, slot/pad hints, shop price tags,
-- farm signs and stats boards. Prompts only exist on the owner's client; the server
-- validates every request.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crates = require(Shared.Config.Crates)
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.FarmLayout)
local Sorcerers = require(Shared.Config.Sorcerers)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent.UI
local UIKit = require(UI.UIKit)
local Theme = require(UI.Theme)

local WorldController = {}

local player = Players.LocalPlayer
local new = UIKit.new
local registry: any
local map: Instance
local ownFarm: number? = nil
local guiFolder: Folder

type PadUi = {
	part: BasePart,
	main: ProximityPrompt,
	pick: ProximityPrompt,
	label: BillboardGui,
	text: TextLabel,
}
type SlotUi = {
	part: BasePart,
	main: ProximityPrompt,
	pick: ProximityPrompt,
	label: BillboardGui,
	text: TextLabel,
}

local padUi: { [number]: PadUi } = {}
local slotUi: { [number]: SlotUi } = {}
local collectPrompt: ProximityPrompt? = nil
local sellPrompt: ProximityPrompt? = nil
local crateLabels: { [Instance]: { gui: BillboardGui, title: TextLabel, timer: TextLabel, model: Model, ready: boolean } } =
	{}
local boxLabels: { [number]: { gui: BillboardGui, count: TextLabel, sub: TextLabel, setBar: (number) -> () } } =
	{}

local function makePrompt(
	parent: Instance,
	action: string,
	object: string,
	key: Enum.KeyCode?,
	distance: number?
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = distance or 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = key or Enum.KeyCode.E
	prompt.GamepadKeyCode = if key == Enum.KeyCode.R then Enum.KeyCode.ButtonY else Enum.KeyCode.ButtonX
	prompt.Style = Enum.ProximityPromptStyle.Default
	if key == Enum.KeyCode.R then
		prompt.UIOffset = Vector2.new(0, 70)
	end
	prompt.Parent = parent
	return prompt
end

local function label(
	adornee: BasePart,
	height: number,
	width: number,
	lines: number,
	maxDistance: number?
): (BillboardGui, { TextLabel })
	local gui = new("BillboardGui", {
		Adornee = adornee,
		Size = UDim2.fromOffset(width, 26 * lines + 8),
		StudsOffsetWorldSpace = Vector3.new(0, height, 0),
		MaxDistance = maxDistance or 70,
		LightInfluence = 0,
		AlwaysOnTop = false,
		ResetOnSpawn = false,
		Parent = guiFolder,
	})
	local holder = new("Frame", {
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.25,
		UIKit.corner(10),
		UIKit.padding(4, 8),
		UIKit.list(Enum.FillDirection.Vertical, 0, Enum.HorizontalAlignment.Center),
	})
	local texts = {}
	for i = 1, lines do
		table.insert(
			texts,
			UIKit.text({
				Parent = holder,
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 26),
				Text = "",
				FontFace = if i == 1 then Theme.TitleBold else Theme.BodyBold,
				TextSize = if i == 1 then 20 else 16,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
		)
	end
	return gui, texts
end

local function bestUnplacedSorcerer(): string?
	for _, entry in registry.StateController.sortedUnits(true) do
		if not entry.slot then
			return entry.uid
		end
	end
	return nil
end

-- Actions ------------------------------------------------------------------------------

function WorldController.openCrate(pad: number)
	local state = registry.StateController
	if registry.RevealController.isPlaying() then
		return
	end
	local _, crate = state.crateOnPad(pad)
	local tier = crate and crate.tier
	local result = state.request("OpenCrate", { pad = pad })
	if result.ok then
		result.data.tier = result.data.tier or tier
		registry.RevealController.play(result.data)
	end
end

function WorldController.placeCrateOnPad(pad: number, cid: string?)
	local state = registry.StateController
	local chosen = cid
	if not chosen then
		local list = state.unplacedCrates()
		chosen = if list[1] then list[1].cid else nil
	end
	if not chosen then
		registry.UIController.toast("You have no Crates to place. Buy one at the Crate Shop!", "bad")
		return
	end
	local result = state.request("PlaceCrate", { cid = chosen, pad = pad })
	if result.ok then
		registry.SoundController.play("cratePlace")
	end
	return result
end

function WorldController.placeSorcererOnSlot(slot: number, uid: string?)
	local state = registry.StateController
	local chosen = uid or bestUnplacedSorcerer()
	if not chosen then
		registry.UIController.toast("All your Sorcerers are working. Open Crates to get more!", "info")
		return
	end
	local result = state.request("PlaceSorcerer", { uid = chosen, slot = slot })
	if result.ok then
		registry.SoundController.play("place")
	end
	return result
end

-- Own farm ------------------------------------------------------------------------------

local function refreshOwnFarm()
	local state = registry.StateController
	local profile = state.profile
	if not profile or not ownFarm then
		return
	end
	local now = state.now()
	local unlockedPads = Economy.unlockedPads(profile)
	local unplacedCrates = state.unplacedCrates()
	for pad, ui in padUi do
		local _, crate = state.crateOnPad(pad)
		local locked = pad > unlockedPads
		ui.pick.Enabled = crate ~= nil
		if locked then
			ui.main.Enabled = true
			ui.main.ActionText = "Upgrade"
			ui.main.ObjectText = "More Crate Pads"
			ui.label.Enabled = true
			ui.text.Text = "Locked - More Crate Pads"
		elseif crate then
			local def = Crates.get(crate.tier)
			local ready = now >= crate.readyAt
			ui.main.Enabled = ready
			ui.main.ActionText = "Open"
			ui.main.ObjectText = if def then def.name else "Crate"
			ui.label.Enabled = false
		else
			local nextCrate = unplacedCrates[1]
			local def = nextCrate and Crates.get(nextCrate.tier)
			ui.main.Enabled = nextCrate ~= nil
			ui.main.ActionText = "Place"
			ui.main.ObjectText = if def then def.name else "Crate"
			ui.label.Enabled = true
			ui.text.Text = if nextCrate
				then "Crate Pad - Place a Crate"
				else "Crate Pad - Buy Crates at the Crate Shop"
		end
	end
	local unlockedSlots = Economy.unlockedSlots(profile)
	local spare = bestUnplacedSorcerer()
	for slot, ui in slotUi do
		local uid = profile.slots[tostring(slot)]
		local unit = uid and profile.units[uid]
		ui.pick.Enabled = unit ~= nil
		if slot > unlockedSlots then
			ui.main.Enabled = true
			ui.main.ActionText = "Upgrade"
			ui.main.ObjectText = "More Slots"
			ui.label.Enabled = true
			ui.text.Text = "Locked slot - More Slots"
		elseif unit then
			local def = Sorcerers.get(unit.id)
			local cost = Economy.unitUpgradeCost(unit)
			ui.main.Enabled = cost ~= nil
			ui.main.ActionText = "Upgrade"
			ui.main.ObjectText = string.format(
				"%s Lv %d  %s",
				if def then def.name else "?",
				unit.level,
				if cost then Format.cash(cost) else "MAX"
			)
			ui.label.Enabled = false
		else
			local spareUnit = spare and profile.units[spare]
			local def = spareUnit and Sorcerers.get(spareUnit.id)
			ui.main.Enabled = spare ~= nil
			ui.main.ActionText = "Place"
			ui.main.ObjectText = if def then def.name else "Sorcerer"
			ui.label.Enabled = true
			ui.text.Text = if spare then "Empty slot - Place a Sorcerer" else "Empty slot"
		end
	end
	if collectPrompt then
		local orbs = state.box()
		collectPrompt.Enabled = orbs >= 1
		collectPrompt.ObjectText = Format.commas(math.floor(orbs)) .. " Cursed Orbs"
	end
	if sellPrompt then
		sellPrompt.Enabled = profile.carried.orbs >= 1
		sellPrompt.ObjectText = string.format(
			"%s Cursed Orbs (%s)",
			Format.commas(profile.carried.orbs),
			Format.cash(math.floor(profile.carried.value + 0.5))
		)
	end
end

local function setupOwnFarm(index: number)
	if ownFarm == index then
		return
	end
	ownFarm = index
	local farmsFolder = map:WaitForChild("Farms")
	local model = farmsFolder:WaitForChild("Farm" .. index)
	-- "Your Farm" on the gate for the owner
	local sign = model:WaitForChild("Sign")
	local title = sign:WaitForChild("SignGui"):WaitForChild("Title") :: TextLabel
	title.Text = "Your Farm"
	sign.ChildAdded:Connect(function()
		title.Text = "Your Farm"
	end)
	title:GetPropertyChangedSignal("Text"):Connect(function()
		if title.Text ~= "Your Farm" then
			title.Text = "Your Farm"
		end
	end)

	local pads = model:WaitForChild("Pads")
	for pad = 1, GameConfig.PadCount do
		local part = pads:WaitForChild("Pad" .. pad) :: BasePart
		local main = makePrompt(part, "Place", "Crate", Enum.KeyCode.E, 12)
		local pick = makePrompt(part, "Pick Up", "Crate", Enum.KeyCode.R, 12)
		main.Name = "MainPrompt"
		pick.Name = "PickUpPrompt"
		local gui, texts = label(part, 3.5, 300, 1, 60)
		padUi[pad] = { part = part, main = main, pick = pick, label = gui, text = texts[1] }
		main.Triggered:Connect(function()
			local state = registry.StateController
			local profile = state.profile
			if not profile then
				return
			end
			if pad > Economy.unlockedPads(profile) then
				registry.UIController.open("UpgradeShop")
				return
			end
			local _, crate = state.crateOnPad(pad)
			if crate then
				WorldController.openCrate(pad)
			else
				WorldController.placeCrateOnPad(pad)
			end
		end)
		pick.Triggered:Connect(function()
			local result = registry.StateController.request("PickUpCrate", { pad = pad })
			if result.ok then
				registry.SoundController.play("pickUp")
			end
		end)
	end

	local slots = model:WaitForChild("Slots")
	for slot = 1, GameConfig.SlotCount do
		local part = slots:WaitForChild("Slot" .. slot) :: BasePart
		local main = makePrompt(part, "Place", "Sorcerer", Enum.KeyCode.E, 13)
		local pick = makePrompt(part, "Pick Up", "Sorcerer", Enum.KeyCode.R, 13)
		main.Name = "MainPrompt"
		pick.Name = "PickUpPrompt"
		local gui, texts = label(part, 3, 280, 1, 55)
		slotUi[slot] = { part = part, main = main, pick = pick, label = gui, text = texts[1] }
		main.Triggered:Connect(function()
			local state = registry.StateController
			local profile = state.profile
			if not profile then
				return
			end
			if slot > Economy.unlockedSlots(profile) then
				registry.UIController.open("UpgradeShop")
				return
			end
			local uid = profile.slots[tostring(slot)]
			if uid then
				local result = state.request("UpgradeSorcerer", { uid = uid })
				if result.ok then
					registry.SoundController.play("upgrade")
				end
			else
				WorldController.placeSorcererOnSlot(slot)
			end
		end)
		pick.Triggered:Connect(function()
			local result = registry.StateController.request("PickUpSorcerer", { slot = slot })
			if result.ok then
				registry.SoundController.play("pickUp")
				registry.UIController.toast(
					"Picked up. Place it again from Sorcerers (G) or an empty slot.",
					"info"
				)
			end
		end)
	end

	local pad = model:WaitForChild("CollectPad") :: BasePart
	local prompt = makePrompt(pad, "Collect", "Orb Box", Enum.KeyCode.E, 14)
	collectPrompt = prompt
	prompt.Name = "CollectPrompt"
	prompt.Triggered:Connect(function()
		registry.StateController.request("Collect")
	end)
	refreshOwnFarm()
end

-- Labels for every farm ----------------------------------------------------------------------

local function trackCrate(model: Instance)
	if not model:IsA("Model") or crateLabels[model] then
		return
	end
	local root = model.PrimaryPart
	if not root then
		return
	end
	local tier = model:GetAttribute("Tier")
	local def = Crates.get(tier or "")
	local gui, texts = label(root, ((model:GetAttribute("Height") :: any) or 5) + 1.6, 200, 2, 80)
	texts[1].Text = if def then def.name else "Crate"
	texts[1].TextColor3 = if def then def.color:Lerp(Color3.new(1, 1, 1), 0.4) else Theme.Text
	crateLabels[model] = { gui = gui, title = texts[1], timer = texts[2], model = model, ready = false }
end

local function untrackCrate(model: Instance)
	local entry = crateLabels[model]
	if entry then
		entry.gui:Destroy()
		crateLabels[model] = nil
	end
end

local function setupFarmLabels(model: Instance, index: number)
	local box = model:WaitForChild("OrbBox")
	local anchor = box:WaitForChild("LabelAnchor") :: BasePart
	local gui = new("BillboardGui", {
		Adornee = anchor,
		Size = UDim2.fromOffset(230, 74),
		MaxDistance = 150,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Parent = guiFolder,
	})
	local frame = new("Frame", {
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.2,
		UIKit.corner(12),
		UIKit.stroke(Theme.Violet, 2, 0.2),
	})
	local count = UIKit.text({
		Parent = frame,
		Position = UDim2.fromOffset(10, 2),
		Size = UDim2.new(1, -20, 0, 30),
		Text = "ORB BOX",
		FontFace = Theme.TitleBold,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local bar, setBar = UIKit.bar(UDim2.new(1, -20, 0, 10), Theme.Violet)
	bar.Position = UDim2.fromOffset(10, 34)
	bar.Parent = frame
	local sub = UIKit.text({
		Parent = frame,
		Position = UDim2.fromOffset(10, 46),
		Size = UDim2.new(1, -20, 0, 22),
		Text = "",
		FontFace = Theme.BodyBold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	boxLabels[index] = { gui = gui, count = count, sub = sub, setBar = setBar }

	local runtime = model:WaitForChild("Runtime")
	local crates = runtime:WaitForChild("Crates")
	for _, child in crates:GetChildren() do
		trackCrate(child)
	end
	crates.ChildAdded:Connect(function(child)
		task.defer(trackCrate, child)
	end)
	crates.ChildRemoved:Connect(untrackCrate)
end

local function setupPlaza()
	local plaza = map:WaitForChild("Plaza")
	-- Sell Stand
	local stand = plaza:WaitForChild("SellStand")
	local sellPad = stand:WaitForChild("SellPad") :: BasePart
	local prompt = makePrompt(sellPad, "Sell", "Cursed Orbs", Enum.KeyCode.E, 18)
	sellPrompt = prompt
	prompt.Name = "SellPrompt"
	prompt.Triggered:Connect(function()
		registry.StateController.request("Sell")
	end)
	local _, sellTexts = label(sellPad, 9, 300, 2, 120)
	sellTexts[1].Text = "SELL STAND"
	sellTexts[1].TextColor3 = Theme.Gold
	sellTexts[2].Text = "Bring your Orb Box here and Sell"

	-- Crate Shop: Buy prompts and price tags on each display
	local shop = plaza:WaitForChild("CrateShop")
	local displays = shop:WaitForChild("Displays")
	for _, holder in displays:GetChildren() do
		local tier = holder:GetAttribute("Tier")
		local def = Crates.get(tier or "")
		local pedestal = holder:FindFirstChild("Pedestal")
		if def and pedestal and pedestal:IsA("BasePart") then
			local prompt =
				makePrompt(pedestal, "Buy", def.name .. "  " .. Format.cash(def.price), Enum.KeyCode.E, 10)
			prompt.Name = "BuyPrompt"
			prompt.Triggered:Connect(function()
				local result = registry.StateController.request("BuyCrate", { tier = def.id })
				if result.ok then
					registry.SoundController.play("buy")
					registry.EffectsController.boughtCrate(def.id)
					registry.UIController.toast(
						def.name .. " bought! Place it on a Crate Pad at Your Farm.",
						"good"
					)
				end
			end)
			local more = makePrompt(pedestal, "Browse", "Crate Shop", Enum.KeyCode.R, 10)
			more.Name = "BrowsePrompt"
			more.Triggered:Connect(function()
				registry.UIController.open("CrateShop")
			end)
			local _, texts = label(pedestal, 9.5, 220, 3, 90)
			texts[1].Text = def.name
			texts[1].TextColor3 = def.color:Lerp(Color3.new(1, 1, 1), 0.4)
			texts[2].Text = Format.cash(def.price)
			texts[2].TextColor3 = Theme.Gold
			texts[3].Text = "Opening Time " .. Format.duration(def.openingTime)
			texts[3].TextColor3 = Theme.TextDim
		end
	end
	local counter = shop:WaitForChild("Counter") :: BasePart
	local browse = makePrompt(counter, "Browse", "Crate Shop", Enum.KeyCode.E, 14)
	browse.Triggered:Connect(function()
		registry.UIController.open("CrateShop")
	end)

	-- Upgrade Shop
	local upgradeShop = plaza:WaitForChild("UpgradeShop")
	for _, name in { "UpgradeBoard", "Counter" } do
		local part = upgradeShop:WaitForChild(name) :: BasePart
		local prompt = makePrompt(part, "Upgrade", "Upgrade Shop", Enum.KeyCode.E, 16)
		prompt.Triggered:Connect(function()
			registry.UIController.open("UpgradeShop")
		end)
	end
end

local function refreshLabels()
	local now = workspace:GetServerTimeNow()
	for model, entry in crateLabels do
		if not model.Parent then
			untrackCrate(model)
			continue
		end
		local readyAt = model:GetAttribute("ReadyAt") or 0
		local remaining = readyAt - now
		if remaining > 0 then
			entry.timer.Text = "Opening Time " .. Format.clock(remaining)
			entry.timer.TextColor3 = Theme.Text
		else
			entry.timer.Text = "READY! Open"
			entry.timer.TextColor3 = Theme.Gold
			if not entry.ready then
				entry.ready = true
				if model:GetAttribute("Farm") == ownFarm then
					registry.SoundController.play("crateReady")
				end
			end
		end
	end
	local farmsFolder = map:FindFirstChild("Farms")
	for index, entry in boxLabels do
		local model = farmsFolder and farmsFolder:FindFirstChild("Farm" .. index)
		if model then
			local orbs, value, cap = registry.ProductionController.boxOf(model)
			local owner = model:GetAttribute("OwnerName")
			entry.gui.Enabled = owner ~= nil
			if owner then
				local full = cap > 0 and orbs >= cap - 0.01
				entry.count.Text =
					string.format("%s / %s", Format.commas(math.floor(orbs)), Format.commas(cap))
				entry.setBar(if cap > 0 then orbs / cap else 0)
				if index == ownFarm then
					entry.sub.Text = if full
						then "FULL!  Collect it"
						else Format.cash(value) .. "  -  Collect"
				else
					entry.sub.Text = owner .. "'s Orb Box"
				end
				entry.sub.TextColor3 = if full then Theme.Gold else Theme.TextDim
			end
			-- Stats board
			local board = model:FindFirstChild("StatsBoard", true)
			local boardGui = board and board:FindFirstChild("BoardGui")
			if boardGui then
				local ops = model:GetAttribute("Ops") or 0
				local cash = model:GetAttribute("CashRate") or 0
				local opsLabel = boardGui:FindFirstChild("Ops")
				local incomeLabel = boardGui:FindFirstChild("Income")
				local boxLabel = boardGui:FindFirstChild("Box")
				local titleLabel = boardGui:FindFirstChild("Title")
				if opsLabel then
					opsLabel.Text = "Orbs per Second: " .. Format.abbreviate(ops)
				end
				if incomeLabel then
					incomeLabel.Text = "Cash: " .. Format.cash(cash) .. "/s"
				end
				if boxLabel then
					boxLabel.Text =
						string.format("Orb Box: %s / %s", Format.commas(math.floor(orbs)), Format.commas(cap))
				end
				if titleLabel then
					titleLabel.Text = if index == ownFarm
						then "YOUR FARM"
						elseif owner then string.upper(owner) .. "'S FARM"
						else "EMPTY FARM"
				end
			end
		end
	end
end

function WorldController.ownFarm(): number?
	return ownFarm
end

function WorldController.padPrompt(pad: number): ProximityPrompt?
	local ui = padUi[pad]
	return ui and ui.main
end

function WorldController.slotPrompt(slot: number): ProximityPrompt?
	local ui = slotUi[slot]
	return ui and ui.main
end

function WorldController.init(reg: any)
	registry = reg
end

function WorldController.start()
	guiFolder = new("Folder", { Name = "WorldLabels", Parent = player:WaitForChild("PlayerGui") })
	map = workspace:WaitForChild("JJKFarmMap")
	task.spawn(setupPlaza)
	task.spawn(function()
		local farmsFolder = map:WaitForChild("Farms")
		for index = 1, Layout.FarmCount do
			local model = farmsFolder:WaitForChild("Farm" .. index)
			task.spawn(setupFarmLabels, model, index)
		end
	end)
	local state = registry.StateController
	local function onState(profile)
		if profile and profile.farm and profile.farm ~= ownFarm then
			task.spawn(setupOwnFarm, profile.farm)
		end
		refreshOwnFarm()
	end
	state.Changed:Connect(onState)
	if state.profile then
		onState(state.profile)
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		refreshLabels()
		refreshOwnFarm()
	end)
end

return WorldController
