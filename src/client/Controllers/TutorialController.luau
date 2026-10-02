--!nonstrict
-- Guided introduction: a step card at the top of the screen and a glowing beam + marker that
-- lead the player to each target (well, altar, empty spot, shop, forest gate).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared.Config.MapLayout)
local Tutorial = require(Shared.Rules.Tutorial)
local Banners = require(Shared.Config.Banners)
local Economy = require(Shared.Rules.Economy)

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
local shownStep = -1

local function targetPosition(target: string, profile: any): Vector3?
	if target == "Well" and profile.plot then
		return (Layout.plotFloorCFrame(profile.plot) * CFrame.new(Layout.WellOffset)).Position
			+ Vector3.new(0, 3, 0)
	elseif target == "Altar" then
		return Layout.AltarPosition + Vector3.new(0, 4, 0)
	elseif target == "Spot" and profile.plot then
		for spot = 1, profile.unlockedSpots do
			if not profile.spots[tostring(spot)] then
				return (Layout.plotFloorCFrame(profile.plot) * Layout.spotLocalCFrame(spot)).Position
					+ Vector3.new(0, 2, 0)
			end
		end
		return (Layout.plotFloorCFrame(profile.plot) * CFrame.new(Layout.WellOffset)).Position
	elseif target == "Shop" then
		return Layout.ShopCounter + Vector3.new(0, 4, 0)
	elseif target == "Forest" then
		return Layout.ForestGate + Vector3.new(0, 5, -16)
	end
	return nil
end

local function hintFor(step: any, profile: any): string
	if step.event == "summon" and profile.energy < Banners.ById.lantern.cost then
		return "Collect more energy from your Spirit Well first (50 needed)."
	elseif step.event == "upgrade" then
		local cost = Economy.upgradeCost("production", profile.upgrades.production or 0) or 0
		if profile.energy < cost then
			return "Collect energy until you can afford Focus Training (" .. cost .. ")."
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

local function refresh()
	local profile = registry.StateController.profile
	if not profile then
		return
	end
	local step = Tutorial.current(profile)
	if not step then
		card.Visible = false
		beam.Enabled = false
		marker.Enabled = false
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
	-- When summoning is next but the player is broke, point back at the well.
	local target = step.target
	if step.event == "summon" and profile.energy < Banners.ById.lantern.cost then
		target = "Well"
	end
	local position = targetPosition(target, profile)
	if position then
		targetPart.Position = position
		local attachment = ensurePlayerAttachment()
		beam.Attachment0 = attachment
		beam.Enabled = attachment ~= nil
		marker.Enabled = true
	else
		beam.Enabled = false
		marker.Enabled = false
	end
end

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
		StudsOffsetWorldSpace = Vector3.new(0, 4, 0),
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
		if elapsed > 1 then
			elapsed = 0
			refresh()
		end
	end)
end

return TutorialController
