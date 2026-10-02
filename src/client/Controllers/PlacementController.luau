--!nonstrict
-- Placement mode for Sorcerers (onto production slots) and Crates (onto Crate Pads).
-- Valid targets on Your Farm glow; the hovered/selected one shows a translucent preview of
-- what you're placing (and who it would swap with). Click a target, or tap it then Place.
-- Works with mouse, touch and gamepad (cycle targets with the d-pad, A to Place).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crates = require(Shared.Config.Crates)
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.FarmLayout)
local Rarities = require(Shared.Config.Rarities)
local Sorcerers = require(Shared.Config.Sorcerers)
local Economy = require(Shared.Rules.Economy)
local CharacterModels = require(Shared.Visuals.CharacterModels)
local CrateModels = require(Shared.Visuals.CrateModels)

local UI = script.Parent.Parent.UI
local UIKit = require(UI.UIKit)
local Theme = require(UI.Theme)

local PlacementController = {}

local player = Players.LocalPlayer
local new = UIKit.new
local registry: any

type Mode = "sorcerer" | "crate"

local active = false
local mode: Mode = "sorcerer"
local itemId: string? = nil -- uid or cid
local selected: number? = nil
local ghost: Model? = nil
local markers: { [number]: BasePart } = {}
local bar: Frame
local barTitle: TextLabel
local barHint: TextLabel
local confirmButton: any
local connections: { RBXScriptConnection } = {}

local function targetCFrame(index: number): CFrame?
	local farm = registry.StateController.farm()
	if not farm then
		return nil
	end
	if mode == "sorcerer" then
		return Layout.slotWorld(farm, index) * CFrame.new(0, 0.5, 0)
	end
	return Layout.padWorld(farm, index) * CFrame.new(0, 0.6, 0)
end

local function clearMarkers()
	for _, marker in markers do
		marker:Destroy()
	end
	table.clear(markers)
end

local function buildMarkers()
	clearMarkers()
	local profile = registry.StateController.profile
	if not profile then
		return
	end
	local count = if mode == "sorcerer" then Economy.unlockedSlots(profile) else Economy.unlockedPads(profile)
	for index = 1, count do
		local occupied = false
		if mode == "crate" then
			occupied = registry.StateController.crateOnPad(index) ~= nil
		end
		local cf = targetCFrame(index)
		if cf and not occupied then
			local size = if mode == "sorcerer" then Layout.SlotSize + 1.5 else 10.5
			local marker = new("Part", {
				Name = "PlacementMarker",
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Shape = Enum.PartType.Cylinder,
				Material = Enum.Material.Neon,
				Color = Theme.Gold,
				Transparency = 0.45,
				Size = Vector3.new(0.3, size, size),
				CFrame = cf * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Parent = workspace,
			})
			markers[index] = marker
		end
	end
end

local function setSelected(index: number?)
	if index == selected and ghost then
		return
	end
	selected = index
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	for i, marker in markers do
		marker.Transparency = if i == index then 0.05 else 0.45
	end
	UIKit.setEnabled(confirmButton, index ~= nil)
	local profile = registry.StateController.profile
	if not index or not itemId or not profile then
		barTitle.Text = if mode == "sorcerer" then "Choose a production slot" else "Choose a Crate Pad"
		return
	end
	local cf = targetCFrame(index) :: CFrame
	if mode == "sorcerer" then
		local unit = profile.units[itemId]
		local def = unit and Sorcerers.get(unit.id)
		if not def then
			return
		end
		local model = CharacterModels.build(def.id, cf, { ghost = true, scale = CharacterModels.FarmScale })
		local rarity = Rarities.get(def.rarity) :: any
		local highlight = Instance.new("Highlight")
		highlight.FillColor = rarity.color
		highlight.OutlineColor = rarity.glow
		highlight.FillTransparency = 0.6
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = model
		model.Parent = workspace
		ghost = model
		local occupant = profile.slots[tostring(index)]
		if occupant and occupant ~= itemId then
			local other = profile.units[occupant]
			local otherDef = other and Sorcerers.get(other.id)
			barTitle.Text =
				string.format("Slot %d: swap with %s", index, if otherDef then otherDef.name else "?")
		else
			barTitle.Text = string.format("Place %s on slot %d", def.name, index)
		end
	else
		local crate = profile.crates[itemId]
		local def = crate and Crates.get(crate.tier)
		if not def then
			return
		end
		local model = CrateModels.build(def.id, cf)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "Root" and d.Name ~= "LidRoot" then
				d.Transparency = 0.5
				d.CanCollide = false
				d.CanQuery = false
			end
		end
		model.Parent = workspace
		ghost = model
		barTitle.Text = string.format(
			"Place %s on Crate Pad %d  (Opening Time %ds)",
			def.name,
			index,
			Economy.openingTime(def.id, profile)
		)
	end
end

function PlacementController.cancel()
	if not active then
		return
	end
	active = false
	itemId = nil
	selected = nil
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	clearMarkers()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	bar.Visible = false
end

local function confirm()
	local index = selected
	local id = itemId
	if not index or not id then
		return
	end
	local result
	if mode == "sorcerer" then
		result = registry.StateController.request("PlaceSorcerer", { uid = id, slot = index })
		if result.ok then
			registry.SoundController.play("place")
		end
	else
		result = registry.StateController.request("PlaceCrate", { cid = id, pad = index })
		if result.ok then
			registry.SoundController.play("cratePlace")
		end
	end
	if result.ok then
		PlacementController.cancel()
	end
end

-- Two coordinate spaces are in play: UserInputService:GetMouseLocation() is in viewport
-- space (including the top bar inset) and pairs with ViewportPointToRay; InputObject.Position
-- (clicks and taps) is in GUI space (below the inset) and pairs with ScreenPointToRay.
-- Mixing them shifts the ray by the inset, so hover and click could pick different targets.
local function targetFromScreen(position: Vector2, space: "viewport" | "gui"): number?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = if space == "viewport"
		then camera:ViewportPointToRay(position.X, position.Y)
		else camera:ScreenPointToRay(position.X, position.Y)
	local params = RaycastParams.new()
	local ignore: { Instance } = {}
	if player.Character then
		table.insert(ignore, player.Character)
	end
	if ghost then
		table.insert(ignore, ghost)
	end
	params.FilterDescendantsInstances = ignore
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if not hit then
		return nil
	end
	local point = hit.Position
	local best, bestDist = nil, (if mode == "sorcerer" then Layout.SlotSize * 0.7 else 7)
	for index, marker in markers do
		local p = marker.Position
		local d = (Vector3.new(point.X, 0, point.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude
		if d < bestDist then
			best, bestDist = index, d
		end
	end
	return best
end

local function begin(newMode: Mode, id: string, preselect: number?)
	local state = registry.StateController
	local farm = state.farm()
	if not farm then
		return
	end
	PlacementController.cancel()
	-- Placing happens on Your Farm; bring the player home first if they're elsewhere.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and not Layout.inFarm(farm, root.Position) then
		registry.UIController.goHome()
		task.wait(0.3)
	end
	active = true
	mode = newMode
	itemId = id
	selected = nil
	buildMarkers()
	if next(markers) == nil then
		active = false
		registry.UIController.toast(
			if mode == "crate"
				then "Every Crate Pad is busy. Open a crate or buy More Crate Pads."
				else "No free slots.",
			"bad"
		)
		return
	end
	bar.Visible = true
	barHint.Text = if UserInputService.TouchEnabled
		then "Tap a glowing " .. (if mode == "sorcerer" then "slot" else "pad") .. ", then Place."
		else "Click a glowing "
			.. (if mode == "sorcerer" then "slot" else "pad")
			.. " to Place. Esc to cancel."
	setSelected(preselect)
	if not preselect then
		-- Preselect the first free target so a single press of Place works.
		local list = {}
		for index in markers do
			table.insert(list, index)
		end
		table.sort(list)
		local first = list[1]
		if mode == "sorcerer" then
			for _, index in list do
				if not state.profile.slots[tostring(index)] then
					first = index
					break
				end
			end
		end
		setSelected(first)
	end
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function()
			if not active or UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
				return
			end
			local index = targetFromScreen(UserInputService:GetMouseLocation(), "viewport")
			if index then
				setSelected(index)
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if not active then
				return
			end
			if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
				PlacementController.cancel()
				return
			end
			if processed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				local index = targetFromScreen(Vector2.new(input.Position.X, input.Position.Y), "gui")
				if index then
					setSelected(index)
					confirm()
				end
			elseif input.UserInputType == Enum.UserInputType.Touch then
				local index = targetFromScreen(Vector2.new(input.Position.X, input.Position.Y), "gui")
				if index then
					setSelected(index)
				end
			elseif input.KeyCode == Enum.KeyCode.ButtonA then
				confirm()
			elseif input.KeyCode == Enum.KeyCode.DPadRight or input.KeyCode == Enum.KeyCode.DPadLeft then
				local list = {}
				for index in markers do
					table.insert(list, index)
				end
				table.sort(list)
				local at = table.find(list, selected or list[1]) or 1
				local step = if input.KeyCode == Enum.KeyCode.DPadRight then 1 else -1
				setSelected(list[((at - 1 + step) % #list) + 1])
			end
		end)
	)
end

function PlacementController.beginSorcerer(uid: string, slot: number?)
	local profile = registry.StateController.profile
	if not profile or not profile.units[uid] then
		return
	end
	task.spawn(begin, "sorcerer" :: Mode, uid, slot)
end

-- Place crate `cid` (or, when nil, your best waiting crate). With `pad` given, places it
-- straight onto that pad without a preview.
function PlacementController.beginCrate(cid: string?, pad: number?)
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
	if pad then
		task.spawn(function()
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local farm = state.farm()
			if farm and root and not Layout.inFarm(farm, root.Position) then
				registry.UIController.goHome()
				task.wait(0.3)
			end
			registry.WorldController.placeCrateOnPad(pad, chosen)
		end)
		return
	end
	task.spawn(begin, "crate" :: Mode, chosen, nil)
end

function PlacementController.isActive(): boolean
	return active
end

function PlacementController.mode(): string
	return mode
end

function PlacementController.selected(): number?
	return selected
end

function PlacementController.confirm()
	confirm()
end

function PlacementController.init(reg: any)
	registry = reg
	bar = new("Frame", {
		Name = "PlacementBar",
		Parent = registry.UIController.getGui(),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(620, 76),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 5,
		UIKit.corner(16),
		UIKit.stroke(Theme.Gold, 2, 0.1),
		new("UIScale", { Name = "Scale" }),
	})
	barTitle = UIKit.text({
		Parent = bar,
		Position = UDim2.fromOffset(18, 6),
		Size = UDim2.new(1, -300, 0, 34),
		Text = "",
		FontFace = Theme.BodyBold,
		TextSize = 18,
	})
	barHint = UIKit.text({
		Parent = bar,
		Position = UDim2.fromOffset(18, 40),
		Size = UDim2.new(1, -300, 0, 26),
		Text = "",
		TextColor3 = Theme.TextDim,
		TextSize = 13,
	})
	confirmButton = UIKit.button({
		parent = bar,
		text = "Place",
		style = "gold",
		size = UDim2.fromOffset(130, 50),
		position = UDim2.new(1, -278, 0.5, -25),
		onClick = confirm,
	})
	UIKit.button({
		parent = bar,
		text = "Cancel",
		style = "secondary",
		size = UDim2.fromOffset(120, 50),
		position = UDim2.new(1, -136, 0.5, -25),
		onClick = PlacementController.cancel,
	})
end

function PlacementController.start()
	local scale = bar:FindFirstChild("Scale") :: UIScale
	RunService.RenderStepped:Connect(function()
		if bar.Visible then
			scale.Scale = math.clamp(registry.UIController.panelScale * 1.05, 0.6, 1.2)
		end
	end)
	player.CharacterRemoving:Connect(function()
		PlacementController.cancel()
	end)
	local _ = GameConfig
end

return PlacementController
