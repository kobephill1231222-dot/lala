--!nonstrict
-- Guided first loop: a step card at the top of the screen and a glowing beam + marker that
-- lead the player to each target (Crate Pad, slot, Orb Box, Sell Stand, Crate Shop, Upgrade
-- Shop). After the tutorial the same pointer guides "Walk me there" requests, and a light
-- beam points to the Sell Stand while you carry Cursed Orbs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crates = require(Shared.Config.Crates)
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.FarmLayout)
local Tutorial = require(Shared.Rules.Tutorial)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent.UI
local UIKit = require(UI.UIKit)
local Theme = require(UI.Theme)

local TutorialController = {}

local player = Players.LocalPlayer
local new = UIKit.new
local registry: any
local card: Frame
local cardScale: UIScale
local titleLabel: TextLabel
local bodyLabel: TextLabel
local stepLabel: TextLabel
local dots: { Frame } = {}
local targetPart: Part
local targetAttachment: Attachment
local beam: Beam
local playerAttachment: Attachment? = nil
local marker: BillboardGui
local markerLabel: TextLabel
local shownStep = -1
local adHoc: { position: Vector3, label: string, until_: number }? = nil

local function targetPosition(target: string, profile: any): Vector3?
	local state = registry.StateController
	local farm = profile.farm
	if target == "Pad" and farm then
		for pad = 1, Economy.unlockedPads(profile) do
			if state.crateOnPad(pad) then
				return Layout.padWorld(farm, pad).Position + Vector3.new(0, 3, 0)
			end
		end
		local pad = state.firstEmptyPad() or 1
		return Layout.padWorld(farm, pad).Position + Vector3.new(0, 2, 0)
	elseif target == "Slot" and farm then
		local slot = state.firstEmptySlot() or 1
		return Layout.slotWorld(farm, slot).Position + Vector3.new(0, 2, 0)
	elseif target == "Box" and farm then
		return (Layout.farmFloor(farm) * CFrame.new(Layout.CollectPoint)).Position + Vector3.new(0, 2, 0)
	elseif target == "Sell" then
		return Layout.SellStand + Vector3.new(0, 3, 0)
	elseif target == "CrateShop" then
		return Layout.CrateShop + Vector3.new(0, 4, 8)
	elseif target == "UpgradeShop" then
		return Layout.UpgradeShop + Vector3.new(0, 4, -8)
	end
	return nil
end

local function hintFor(step: any, profile: any): string
	local state = registry.StateController
	if step.event == "openCrate" then
		for pad = 1, Economy.unlockedPads(profile) do
			local _, crate = state.crateOnPad(pad)
			if crate then
				local remaining = crate.readyAt - state.now()
				if remaining > 0 then
					return "Opening Time: "
						.. Format.clock(remaining)
						.. ". When it's ready, press Open on the crate."
				end
				return "Your crate is ready! Walk up to it and press Open."
			end
		end
	elseif step.event == "collect" then
		local orbs = state.box()
		if orbs < 1 then
			return "Watch your Sorcerer make Cursed Orbs. They roll down the lane into your Orb Box."
		end
	elseif step.event == "buyCrate" then
		local price = (Crates.get("basic") :: any).price
		if profile.cash < price then
			return string.format(
				"Collect and Sell more Cursed Orbs until you have %s for a Basic Crate.",
				Format.cash(price)
			)
		end
	elseif step.event == "upgrade" then
		local cost = Economy.upgradeCost("orbValue", Economy.upgradeLevel(profile, "orbValue")) or 0
		if profile.cash < cost then
			return string.format(
				"Earn %s, then visit the Upgrade Shop and Upgrade Orb Value.",
				Format.cash(cost)
			)
		end
	end
	return step.text
end

local function ensurePlayerAttachment(): Attachment?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	if not playerAttachment or playerAttachment.Parent ~= root then
		local a = Instance.new("Attachment")
		a.Name = "TutorialBeam"
		a.Position = Vector3.new(0, -1.5, 0)
		a.Parent = root
		playerAttachment = a
	end
	return playerAttachment
end

local function pointTo(position: Vector3?, labelText: string?, subtle: boolean?)
	if not position then
		beam.Enabled = false
		marker.Enabled = false
		return
	end
	targetPart.Position = position
	local attachment = ensurePlayerAttachment()
	beam.Attachment0 = attachment
	beam.Enabled = attachment ~= nil
	beam.Transparency = if subtle
		then NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.85) })
		else NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 0.6),
		})
	marker.Enabled = not subtle
	markerLabel.Text = labelText or ""
end

local function distanceTo(position: Vector3): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return math.huge
	end
	local d = root.Position - position
	return Vector3.new(d.X, 0, d.Z).Magnitude
end

-- Point the player at somewhere (until they get there, or a minute passes).
function TutorialController.pointAt(position: Vector3, labelText: string)
	adHoc = { position = position, label = labelText, until_ = os.clock() + 60 }
	TutorialController.refresh()
end

local LABELS = {
	Pad = "Crate Pad",
	Slot = "Slot",
	Box = "Orb Box",
	Sell = "Sell Stand",
	CrateShop = "Crate Shop",
	UpgradeShop = "Upgrade Shop",
}

function TutorialController.refresh()
	local profile = registry.StateController.profile
	if not profile then
		return
	end
	local step = Tutorial.current(profile)
	if not step then
		card.Visible = false
		if adHoc and (os.clock() > adHoc.until_ or distanceTo(adHoc.position) < 14) then
			adHoc = nil
		end
		if adHoc then
			pointTo(adHoc.position, adHoc.label)
		elseif profile.carried.orbs >= 1 and distanceTo(Layout.SellStand) > GameConfig.SellRange then
			pointTo(Layout.SellStand + Vector3.new(0, 3, 0), "Sell Stand", true)
		else
			pointTo(nil)
		end
		return
	end
	if shownStep ~= profile.tutorial then
		shownStep = profile.tutorial
		card.Visible = true
		cardScale.Scale = 0.8
		UIKit.tween(
			cardScale,
			0.3,
			{ Scale = math.clamp(registry.UIController.panelScale, 0.6, 1) },
			Enum.EasingStyle.Back
		)
	end
	stepLabel.Text = string.format("STEP %d / %d", profile.tutorial, #Tutorial.Steps)
	titleLabel.Text = step.title
	bodyLabel.Text = hintFor(step, profile)
	for i, dot in dots do
		dot.BackgroundColor3 = if i < profile.tutorial
			then Theme.Good
			elseif i == profile.tutorial then Theme.Gold
			else Theme.PanelLighter
	end
	local target = step.target
	-- Need Cash for the shop steps? Point back at the Orb Box first.
	if
		step.event == "buyCrate"
		and profile.cash < (Crates.get("basic") :: any).price
		and profile.carried.orbs < 1
	then
		target = "Box"
	elseif step.event == "buyCrate" and profile.cash < (Crates.get("basic") :: any).price then
		target = "Sell"
	end
	pointTo(targetPosition(target, profile), LABELS[target])
end

local refresh = TutorialController.refresh

function TutorialController.init(reg: any)
	registry = reg
	cardScale = new("UIScale", { Scale = 1 })
	card = new("Frame", {
		Name = "TutorialCard",
		Parent = registry.UIController.getGui(),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(470, 112),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.06,
		Visible = false,
		cardScale,
		UIKit.corner(16),
		UIKit.stroke(Theme.Gold, 2, 0.15),
	})
	stepLabel = UIKit.text({
		Parent = card,
		Position = UDim2.fromOffset(18, 8),
		Size = UDim2.fromOffset(200, 18),
		Text = "",
		FontFace = Theme.Heavy,
		TextSize = 12,
		TextColor3 = Theme.Gold,
	})
	titleLabel = UIKit.text({
		Parent = card,
		Position = UDim2.fromOffset(18, 26),
		Size = UDim2.new(1, -36, 0, 30),
		Text = "",
		FontFace = Theme.TitleBold,
		TextSize = 26,
	})
	bodyLabel = UIKit.text({
		Parent = card,
		Position = UDim2.fromOffset(18, 56),
		Size = UDim2.new(1, -36, 0, 44),
		Text = "",
		TextColor3 = Theme.TextDim,
		TextSize = 15,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local dotRow = new("Frame", {
		Parent = card,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12),
		Size = UDim2.fromOffset(120, 12),
		BackgroundTransparency = 1,
		UIKit.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right),
	})
	for i = 1, #Tutorial.Steps do
		table.insert(
			dots,
			new("Frame", {
				Parent = dotRow,
				LayoutOrder = i,
				Size = UDim2.fromOffset(12, 12),
				BackgroundColor3 = Theme.PanelLighter,
				UIKit.round(),
			})
		)
	end
	local skip = new("TextButton", {
		Parent = card,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -8),
		Size = UDim2.fromOffset(110, 22),
		BackgroundTransparency = 1,
		Text = "Skip tutorial",
		FontFace = Theme.Body,
		TextSize = 13,
		TextColor3 = Theme.TextFaint,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	skip.Activated:Connect(function()
		registry.StateController.request("SkipTutorial")
	end)

	-- World guidance
	targetPart = Instance.new("Part")
	targetPart.Name = "TutorialTarget"
	targetPart.Anchored = true
	targetPart.CanCollide = false
	targetPart.CanQuery = false
	targetPart.CanTouch = false
	targetPart.Transparency = 1
	targetPart.Size = Vector3.one
	targetPart.Parent = workspace
	targetAttachment = Instance.new("Attachment")
	targetAttachment.Parent = targetPart
	beam = Instance.new("Beam")
	beam.Attachment1 = targetAttachment
	beam.Color = ColorSequence.new(Theme.Gold, Theme.Violet)
	beam.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.6) })
	beam.Width0 = 0.8
	beam.Width1 = 0.8
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureMode = Enum.TextureMode.Static
	beam.TextureLength = 4
	beam.TextureSpeed = 1.6
	beam.Segments = 20
	beam.CurveSize0 = 0
	beam.CurveSize1 = 0
	beam.Enabled = false
	beam.Parent = targetPart
	marker = new("BillboardGui", {
		Name = "TutorialMarker",
		Adornee = targetPart,
		Size = UDim2.fromOffset(70, 80),
		StudsOffsetWorldSpace = Vector3.new(0, 5, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Enabled = false,
		ResetOnSpawn = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local arrow = new("Frame", {
		Parent = marker,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(34, 34),
		Rotation = 45,
		BackgroundColor3 = Theme.Gold,
		UIKit.corner(6),
		UIKit.stroke(Color3.new(1, 1, 1), 2, 0.2),
	})
	markerLabel = UIKit.text({
		Parent = marker,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -2),
		Size = UDim2.fromOffset(200, 24),
		Text = "",
		FontFace = Theme.TitleBold,
		TextSize = 20,
		TextColor3 = Theme.Gold,
		TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	task.spawn(function()
		while true do
			UIKit.tween(arrow, 0.5, { Position = UDim2.new(0.5, 0, 0, 14) }, Enum.EasingStyle.Sine).Completed
				:Wait()
			UIKit.tween(arrow, 0.5, { Position = UDim2.new(0.5, 0, 0, 0) }, Enum.EasingStyle.Sine).Completed
				:Wait()
		end
	end)
end

function TutorialController.start()
	registry.StateController.Changed:Connect(refresh)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		refresh()
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed > 0.5 then
			elapsed = 0
			refresh()
		end
	end)
end

return TutorialController
