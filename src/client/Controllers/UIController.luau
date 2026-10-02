--!nonstrict
-- Owns the HUD, the modal panels and toasts. Scales everything for the current screen so the
-- same layout works on phones, tablets and desktops.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared.Config.MapLayout)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent.UI
local UIKit = require(UI.UIKit)
local Theme = require(UI.Theme)

local UIController = {}

local player = Players.LocalPlayer
local new = UIKit.new

local registry: any
local gui: ScreenGui
local hudScale: UIScale
local overlay: Frame
local dim: TextButton
local toastHolder: Frame
local panels: { [string]: any } = {}
local current: string? = nil
local energyLabel: TextLabel
local rateLabel: TextLabel
local sealLabel: TextLabel
local wellLabel: TextLabel
local wellSetter: (number) -> ()
local wellHint: TextLabel
local energyIconHolder: Frame
local displayedEnergy = 0
local loading: Frame?

UIController.isTouch = false
UIController.panelScale = 1

local function isTouchDevice(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function computeScales()
	local camera = workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local touch = isTouchDevice()
	UIController.isTouch = touch
	local base = math.min(size.X / 1180, size.Y / 660)
	local hud = math.clamp(base * (if touch then 1.12 else 1), 0.62, 1.25)
	hudScale.Scale = hud
	UIController.panelScale = math.clamp(math.min(size.X * 0.95 / 820, (size.Y - 40) * 0.92 / 560), 0.45, 1.2)
	for _, panel in panels do
		panel.scale.Scale = UIController.panelScale
	end
end

-- Toasts ------------------------------------------------------------------------------------

local TONES = {
	info = Theme.PanelLighter,
	good = Color3.fromRGB(46, 110, 76),
	bad = Color3.fromRGB(130, 40, 56),
	rare = Color3.fromRGB(150, 96, 30),
	reward = Theme.VioletDark,
}

function UIController.toast(text: string, tone: string?, duration: number?)
	local color = TONES[tone or "info"] or TONES.info
	local frame = new("Frame", {
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.08,
		UIKit.corner(20),
		UIKit.stroke(Color3.new(1, 1, 1), 1, 0.8),
		UIKit.padding(0, 18),
		UIKit.text({
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = text,
			FontFace = Theme.BodyBold,
			TextSize = 17,
			TextWrapped = false,
		}),
		new("UIScale", { Scale = 0.6 }),
	})
	frame.Parent = toastHolder
	local scale = frame:FindFirstChildOfClass("UIScale") :: UIScale
	UIKit.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	local children = toastHolder:GetChildren()
	local count = 0
	for _, child in children do
		if child:IsA("Frame") then
			count += 1
		end
	end
	if count > 4 then
		for _, child in children do
			if child:IsA("Frame") and child ~= frame then
				child:Destroy()
				break
			end
		end
	end
	task.delay(duration or 3.2, function()
		if frame.Parent then
			UIKit.tween(scale, 0.2, { Scale = 0 })
			task.wait(0.2)
			frame:Destroy()
		end
	end)
end

-- Panels -----------------------------------------------------------------------------------

function UIController.register(name: string, panel: any)
	panels[name] = panel
	panel.root.Visible = false
	panel.root.Parent = overlay
	panel.scale.Scale = UIController.panelScale
end

function UIController.open(name: string, args: any?)
	local panel = panels[name]
	if not panel then
		return
	end
	if current and current ~= name then
		UIController.close(true)
	end
	current = name
	dim.Visible = true
	panel.root.Visible = true
	panel.scale.Scale = UIController.panelScale * 0.92
	UIKit.tween(panel.scale, 0.22, { Scale = UIController.panelScale }, Enum.EasingStyle.Back)
	if panel.onOpen then
		panel.onOpen(args)
	end
	registry.SoundController.play("open")
end

function UIController.close(silent: boolean?)
	if not current then
		return
	end
	local panel = panels[current]
	current = nil
	dim.Visible = false
	if panel then
		panel.root.Visible = false
		if panel.onClose then
			panel.onClose()
		end
	end
	if not silent then
		registry.SoundController.play("close")
	end
end

function UIController.toggle(name: string)
	if current == name then
		UIController.close()
	else
		UIController.open(name)
	end
end

function UIController.currentPanel(): string?
	return current
end

function UIController.getGui(): ScreenGui
	return gui
end

-- HUD -------------------------------------------------------------------------------------

local function statCard(parent: Instance, height: number, width: number, order: number): Frame
	return new("Frame", {
		Parent = parent,
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.12,
		LayoutOrder = order,
		UIKit.corner(14),
		UIKit.stroke(Theme.StrokeSoft, 1.5, 0.1),
	})
end

local function menuIcon(kind: string): Frame
	local icon = new("Frame", { Size = UDim2.fromOffset(34, 34), BackgroundTransparency = 1 })
	local white = Color3.fromRGB(240, 232, 255)
	if kind == "Summon" then
		new("Frame", {
			Parent = icon,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.95, 0.95),
			BackgroundTransparency = 1,
			UIKit.round(),
			UIKit.stroke(white, 2.5),
		})
		new("Frame", {
			Parent = icon,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.36, 0.36),
			Rotation = 45,
			BackgroundColor3 = Theme.Violet,
			UIKit.corner(2),
		})
	elseif kind == "Units" then
		for i = 0, 3 do
			new("Frame", {
				Parent = icon,
				Position = UDim2.fromScale((i % 2) * 0.55, math.floor(i / 2) * 0.55),
				Size = UDim2.fromScale(0.45, 0.45),
				BackgroundColor3 = if i == 0 then Theme.Violet else white,
				UIKit.corner(4),
			})
		end
	elseif kind == "Upgrades" then
		new("Frame", {
			Parent = icon,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.12),
			Size = UDim2.fromScale(0.5, 0.5),
			Rotation = 45,
			BackgroundColor3 = white,
			UIKit.corner(3),
		})
		new("Frame", {
			Parent = icon,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.42),
			Size = UDim2.fromScale(0.26, 0.52),
			BackgroundColor3 = white,
			UIKit.corner(2),
		})
	elseif kind == "Travel" then
		new("Frame", {
			Parent = icon,
			Position = UDim2.fromScale(0, 0.08),
			Size = UDim2.fromScale(1, 0.14),
			BackgroundColor3 = Theme.Seal,
			UIKit.corner(2),
		})
		new("Frame", {
			Parent = icon,
			Position = UDim2.fromScale(0.08, 0.32),
			Size = UDim2.fromScale(0.84, 0.1),
			BackgroundColor3 = Theme.Seal,
		})
		for _, x in { 0.18, 0.7 } do
			new("Frame", {
				Parent = icon,
				Position = UDim2.fromScale(x, 0.2),
				Size = UDim2.fromScale(0.12, 0.8),
				BackgroundColor3 = Theme.Seal,
			})
		end
	else -- Settings
		for i = 0, 2 do
			new("Frame", {
				Parent = icon,
				Position = UDim2.fromScale(0.08, 0.16 + i * 0.3),
				Size = UDim2.fromScale(0.84, 0.12),
				BackgroundColor3 = white,
				UIKit.round(),
			})
		end
	end
	return icon
end

local function buildHud()
	local root = new("Frame", {
		Name = "HUD",
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	hudScale = new("UIScale", { Parent = root })

	-- Stats column (top-left)
	local stats = new("Frame", {
		Parent = root,
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.fromOffset(270, 200),
		BackgroundTransparency = 1,
		UIKit.list(Enum.FillDirection.Vertical, 8),
	})
	local energyCard = statCard(stats, 62, 260, 1)
	energyIconHolder = UIKit.energyIcon(44)
	energyIconHolder.Position = UDim2.fromOffset(10, 9)
	energyIconHolder.Parent = energyCard
	energyLabel = UIKit.text({
		Parent = energyCard,
		Position = UDim2.fromOffset(62, 4),
		Size = UDim2.new(1, -70, 0, 34),
		Text = "0",
		FontFace = Theme.Heavy,
		TextSize = 30,
	})
	rateLabel = UIKit.text({
		Parent = energyCard,
		Position = UDim2.fromOffset(62, 36),
		Size = UDim2.new(1, -70, 0, 20),
		Text = "+0/s",
		TextColor3 = Theme.Violet,
		FontFace = Theme.BodyBold,
		TextSize = 15,
	})

	local sealCard = statCard(stats, 44, 150, 2)
	local sealIcon = UIKit.sealIcon(30)
	sealIcon.Position = UDim2.fromOffset(9, 7)
	sealIcon.Parent = sealCard
	sealLabel = UIKit.text({
		Parent = sealCard,
		Position = UDim2.fromOffset(48, 0),
		Size = UDim2.new(1, -56, 1, 0),
		Text = "0",
		FontFace = Theme.Heavy,
		TextSize = 22,
	})

	local wellCard = new("TextButton", {
		Parent = stats,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(260, 58),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.12,
		LayoutOrder = 3,
		UIKit.corner(14),
		UIKit.stroke(Theme.StrokeSoft, 1.5, 0.1),
	})
	UIKit.text({
		Parent = wellCard,
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(1, -24, 0, 20),
		Text = "SPIRIT WELL",
		FontFace = Theme.Heavy,
		TextSize = 12,
		TextColor3 = Theme.TextDim,
	})
	wellLabel = UIKit.text({
		Parent = wellCard,
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(1, -24, 0, 20),
		Text = "0 / 0",
		FontFace = Theme.BodyBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local bar, setter = UIKit.bar(UDim2.new(1, -24, 0, 10), Theme.Violet)
	bar.Position = UDim2.fromOffset(12, 27)
	bar.Parent = wellCard
	wellSetter = setter
	wellHint = UIKit.text({
		Parent = wellCard,
		Position = UDim2.fromOffset(12, 38),
		Size = UDim2.new(1, -24, 0, 16),
		Text = "Tap to travel home",
		FontFace = Theme.Body,
		TextSize = 12,
		TextColor3 = Theme.TextFaint,
	})
	wellCard.Activated:Connect(function()
		registry.SoundController.play("click")
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local profile = registry.StateController.profile
		if root and profile and profile.plot then
			local wellPos = (Layout.plotFloorCFrame(profile.plot) * CFrame.new(Layout.WellOffset)).Position
			if (root.Position - wellPos).Magnitude < 44 then
				registry.StateController.request("Collect")
				return
			end
		end
		registry.WorldController.travel("Home")
	end)

	-- Menu buttons (right side)
	local menu = new("Frame", {
		Parent = root,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.46, 0),
		Size = UDim2.fromOffset(84, 420),
		BackgroundTransparency = 1,
		UIKit.list(
			Enum.FillDirection.Vertical,
			10,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Center
		),
	})
	local buttons: { any } = {
		{ name = "Summon", panel = "Summon", hotkey = "F" },
		{ name = "Units", panel = "Units", hotkey = "G" },
		{ name = "Upgrades", panel = "Upgrades", hotkey = "U" },
		{ name = "Travel", panel = "Travel", hotkey = "T" },
		{ name = "Settings", panel = "Settings" },
	}
	for i, info in buttons do
		local scale = new("UIScale")
		local button = new("TextButton", {
			Parent = menu,
			Name = info.name,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = i,
			Size = UDim2.fromOffset(
				if info.name == "Settings" then 56 else 76,
				if info.name == "Settings" then 56 else 76
			),
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.08,
			UIKit.corner(18),
			UIKit.stroke(if info.name == "Summon" then Theme.Violet else Theme.StrokeSoft, 2, 0.1),
			scale,
		})
		local icon = menuIcon(info.name)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.fromScale(0.5, 0.14)
		icon.Size = if info.name == "Settings" then UDim2.fromOffset(26, 26) else UDim2.fromOffset(34, 34)
		icon.Parent = button
		if info.name ~= "Settings" then
			UIKit.text({
				Parent = button,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -5),
				Size = UDim2.new(1, 0, 0, 16),
				Text = info.name,
				FontFace = Theme.BodyBold,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
		end
		if info.hotkey then
			UIKit.text({
				Name = "Hotkey",
				Parent = button,
				Position = UDim2.fromOffset(6, 2),
				Size = UDim2.fromOffset(16, 16),
				Text = info.hotkey,
				FontFace = Theme.Heavy,
				TextSize = 11,
				TextColor3 = Theme.TextFaint,
				Visible = not isTouchDevice(),
			})
		end
		button.MouseEnter:Connect(function()
			UIKit.tween(scale, 0.12, { Scale = 1.07 })
		end)
		button.MouseLeave:Connect(function()
			UIKit.tween(scale, 0.12, { Scale = 1 })
		end)
		button.Activated:Connect(function()
			registry.SoundController.play("click")
			UIKit.tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
			if info.panel == "Summon" then
				registry.WorldController.openSummon()
			else
				UIController.toggle(info.panel)
			end
		end)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		for _, info in buttons do
			if info.hotkey and input.KeyCode == (Enum.KeyCode :: any)[info.hotkey] then
				if info.panel == "Summon" then
					registry.WorldController.openSummon()
				else
					UIController.toggle(info.panel)
				end
			end
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			UIController.close()
		end
	end)

	toastHolder = new("Frame", {
		Parent = root,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(600, 220),
		BackgroundTransparency = 1,
		UIKit.list(
			Enum.FillDirection.Vertical,
			6,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Bottom
		),
	})
end

local function refreshNumbers()
	local state = registry.StateController
	local profile = state.profile
	if not profile then
		return
	end
	-- Smoothly count toward the real balance
	local target = profile.energy
	if math.abs(target - displayedEnergy) < 1 then
		displayedEnergy = target
	else
		displayedEnergy += (target - displayedEnergy) * 0.18
	end
	energyLabel.Text = Format.abbreviate(displayedEnergy)
	rateLabel.Text = "+" .. Format.rate(state.rate())
	sealLabel.Text = Format.commas(profile.seals)
	local stored, cap = state.wellStored(), state.wellCapacity()
	wellLabel.Text = Format.abbreviate(stored) .. " / " .. Format.abbreviate(cap)
	wellSetter(if cap > 0 then stored / cap else 0)
	local full = cap > 0 and stored >= cap
	wellHint.Text = if full then "Full! Collect to keep earning" else "Tap: collect if near, else travel home"
	wellHint.TextColor3 = if full then Theme.Gold else Theme.TextFaint
end

function UIController.pulseEnergy()
	local scale = energyIconHolder:FindFirstChildOfClass("UIScale")
		or new("UIScale", { Parent = energyIconHolder })
	scale.Scale = 1.35
	UIKit.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

local function buildLoading()
	loading = new("Frame", {
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(12, 8, 18),
		ZIndex = 50,
		UIKit.text({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.46),
			Size = UDim2.fromOffset(600, 60),
			Text = "CURSEBOUND FARM",
			FontFace = Theme.TitleBold,
			TextSize = 44,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 51,
		}),
		UIKit.text({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.55),
			Size = UDim2.fromOffset(600, 30),
			Text = "Preparing your sanctuary...",
			TextColor3 = Theme.TextDim,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 51,
		}),
	})
end

function UIController.hideLoading()
	local frame = loading
	if not frame then
		return
	end
	loading = nil
	UIKit.tween(frame, 0.6, { BackgroundTransparency = 1 })
	for _, child in frame:GetChildren() do
		if child:IsA("TextLabel") then
			UIKit.tween(child, 0.4, { TextTransparency = 1 })
		end
	end
	task.delay(0.7, function()
		frame:Destroy()
	end)
end

function UIController.init(reg: any)
	registry = reg
	UIKit.onClick = function()
		registry.SoundController.play("click")
	end
	gui = new("ScreenGui", {
		Name = "CurseboundUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	buildHud()
	overlay = new("Frame", {
		Name = "Panels",
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 10,
	})
	dim = new("TextButton", {
		Name = "Dim",
		Parent = overlay,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Visible = false,
		Activated = function()
			UIController.close()
		end,
	})
	buildLoading()
	computeScales()
end

function UIController.start()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(computeScales)
	end
	UserInputService.LastInputTypeChanged:Connect(computeScales)
	RunService.RenderStepped:Connect(refreshNumbers)
	registry.StateController.Ready:Connect(function()
		UIController.hideLoading()
	end)
end

return UIController
