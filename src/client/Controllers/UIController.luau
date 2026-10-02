--!nonstrict
-- Owns the HUD, the modal panels and toasts. Scales everything for the current screen so the
-- same layout works on phones, tablets and desktops.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.FarmLayout)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent.UI
local UIKit = require(UI.UIKit)
local Theme = require(UI.Theme)

local UIController = {}

local player = Players.LocalPlayer
local new = UIKit.new

local registry: any
local gui: ScreenGui
-- The HUD's full-screen container is never scaled (scaling it would also scale the space
-- its edge anchors live in and push the right-hand menu off screen). Each anchored group
-- has its own UIScale, which scales around that group's AnchorPoint.
local hudGroupScales: { UIScale } = {}
local toastScale: UIScale
local scroller: ScrollingFrame
local overlay: Frame
local dim: TextButton
local toastHolder: Frame
local panels: { [string]: any } = {}
local current: string? = nil
local cashLabel: TextLabel
local incomeLabel: TextLabel
local cashIcon: Frame
local boxLabel: TextLabel
local boxSetter: (number) -> ()
local boxHint: TextLabel
local boxCard: TextButton
local carryCard: Frame
local carryLabel: TextLabel
local carryValue: TextLabel
local displayedCash = 0
local loading: Frame?
local menuButtons: { [string]: GuiObject } = {}

UIController.isTouch = false
UIController.panelScale = 1

local function isTouchDevice(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Unscaled sizes of the HUD groups (see buildHud).
local STATS_WIDTH = 294
local MENU_WIDTH = 90
local MENU_HEIGHT = 5 * 70 + 56 + 5 * 8
local EDGE = 12
local MIN_PANEL_SCALE = 0.62

-- Usable screen size: the ScreenGui's own size, which already excludes the top bar inset
-- and device safe areas.
local function screenSize(): Vector2
	local size = Vector2.zero
	if gui then
		local ok, absolute = pcall(function()
			return gui.AbsoluteSize
		end)
		if ok and absolute then
			size = absolute
		end
	end
	if size.X < 2 or size.Y < 2 then
		local camera = workspace.CurrentCamera
		size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	end
	return size
end

local function hudScaleFor(size: Vector2, touch: boolean): number
	local base = math.min(size.X / 1180, size.Y / 660)
	local hud = math.clamp(base * (if touch then 1.12 else 1), 0.5, 1.25)
	-- The right-hand menu must fit top to bottom, and the stats column and menu side by side.
	hud = math.min(hud, (size.Y - 2 * EDGE) / MENU_HEIGHT)
	hud = math.min(hud, (size.X - 4 * EDGE) / (STATS_WIDTH + MENU_WIDTH))
	return hud
end
UIController._hudScaleFor = hudScaleFor -- for tests

-- Scale for one panel: as large as fits, never below MIN_PANEL_SCALE; a panel that still
-- doesn't fit becomes scrollable instead of shrinking into unreadable text.
local function panelScaleFor(panel: any, size: Vector2): number
	local w, h = panel.root.Size.X.Offset, panel.root.Size.Y.Offset
	return math.clamp(math.min(size.X * 0.96 / w, (size.Y - 16) * 0.94 / h), MIN_PANEL_SCALE, 1.2)
end

local function layoutPanel(panel: any, scale: number)
	local size = screenSize()
	local w = panel.root.Size.X.Offset * scale
	local h = panel.root.Size.Y.Offset * scale
	local canvas = Vector2.new(math.max(size.X, w + 24), math.max(size.Y, h + 24))
	scroller.CanvasSize = UDim2.fromOffset(canvas.X, canvas.Y)
	scroller.CanvasPosition = Vector2.new((canvas.X - size.X) / 2, (canvas.Y - size.Y) / 2)
	local frame = panel.root
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
end

local function computeScales()
	local size = screenSize()
	local touch = isTouchDevice()
	UIController.isTouch = touch
	local hud = hudScaleFor(size, touch)
	for _, scale in hudGroupScales do
		scale.Scale = hud
	end
	if toastScale then
		local holder = toastScale.Parent :: Frame
		holder.Size = UDim2.fromOffset(math.min(640, (size.X - 2 * EDGE) / hud), 240)
	end
	UIController.hudScale = hud
	UIController.panelScale =
		math.clamp(math.min(size.X * 0.95 / 860, (size.Y - 40) * 0.92 / 580), MIN_PANEL_SCALE, 1.2)
	if current and panels[current] then
		local panel = panels[current]
		local s = panelScaleFor(panel, size)
		panel.scale.Scale = s
		layoutPanel(panel, s)
	end
end

-- Toasts ------------------------------------------------------------------------------------

local TONES = {
	info = Theme.PanelLighter,
	good = Color3.fromRGB(46, 120, 76),
	bad = Color3.fromRGB(150, 44, 56),
	rare = Color3.fromRGB(160, 104, 30),
	reward = Theme.VioletDark,
	cash = Color3.fromRGB(40, 130, 60),
}

function UIController.toast(text: string, tone: string?, duration: number?)
	local color = TONES[tone or "info"] or TONES.info
	local frame = new("Frame", {
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.06,
		UIKit.corner(20),
		UIKit.stroke(Color3.new(1, 1, 1), 1, 0.75),
		UIKit.padding(9, 18),
		new("UISizeConstraint", { MaxSize = Vector2.new(620, 200) }),
		UIKit.text({
			Size = UDim2.new(0, 0, 0, 22),
			AutomaticSize = Enum.AutomaticSize.XY,
			Text = text,
			FontFace = Theme.BodyBold,
			TextSize = 17,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
		new("UIScale", { Scale = 0.6 }),
	})
	frame.Parent = toastHolder
	local scale = frame:FindFirstChildOfClass("UIScale") :: UIScale
	UIKit.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	local count = 0
	for _, child in toastHolder:GetChildren() do
		if child:IsA("Frame") then
			count += 1
		end
	end
	if count > 4 then
		for _, child in toastHolder:GetChildren() do
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
	panel.root.ZIndex = 2 -- above the click-to-close backdrop
	panel.root.Parent = scroller
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
	scroller.Visible = true
	panel.root.Visible = true
	local target = panelScaleFor(panel, screenSize())
	layoutPanel(panel, target)
	panel.scale.Scale = target * 0.92
	UIKit.tween(panel.scale, 0.22, { Scale = target }, Enum.EasingStyle.Back)
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
	scroller.Visible = false
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

function UIController.menuButton(name: string): GuiObject?
	return menuButtons[name]
end

-- Is the local character within `range` studs (flat) of `position`?
function UIController.near(position: Vector3, range: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local d = root.Position - position
	return Vector3.new(d.X, 0, d.Z).Magnitude <= range
end

function UIController.goHome()
	registry.SoundController.play("travel")
	registry.StateController.request("GoHome")
end

-- HUD -------------------------------------------------------------------------------------

local function card(parent: Instance, height: number, width: number, order: number, class: string?): any
	return new(class or "Frame", {
		Parent = parent,
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		LayoutOrder = order,
		UIKit.corner(14),
		UIKit.stroke(Theme.StrokeSoft, 1.5, 0.1),
	})
end

local MENU = {
	{ name = "Sorcerers", panel = "Sorcerers", hotkey = "G", color = Theme.Violet },
	{ name = "Crates", panel = "Crates", hotkey = "C", color = Theme.Gold },
	{ name = "Crate Shop", panel = "CrateShop", hotkey = "B", color = Theme.Gold },
	{ name = "Upgrade Shop", panel = "UpgradeShop", hotkey = "U", color = Theme.Cash },
	{ name = "Home", action = "home", hotkey = "H", color = Theme.Red },
	{ name = "Settings", panel = "Settings", color = Theme.StrokeSoft },
}

local function menuIcon(info: any): Frame
	local name = info.name
	if name == "Crates" or name == "Crate Shop" then
		return UIKit.crateIcon(if name == "Crates" then "basic" else "rare", 36)
	elseif name == "Sorcerers" then
		return UIKit.orbIcon(34, Theme.Violet)
	elseif name == "Upgrade Shop" then
		local icon = new("Frame", { Size = UDim2.fromOffset(34, 34), BackgroundTransparency = 1 })
		new("Frame", {
			Parent = icon,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.06),
			Size = UDim2.fromScale(0.52, 0.52),
			Rotation = 45,
			BackgroundColor3 = Theme.Cash,
			UIKit.corner(3),
		})
		new("Frame", {
			Parent = icon,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.4),
			Size = UDim2.fromScale(0.26, 0.56),
			BackgroundColor3 = Theme.Cash,
			UIKit.corner(2),
		})
		return icon
	elseif name == "Home" then
		local icon = new("Frame", { Size = UDim2.fromOffset(34, 34), BackgroundTransparency = 1 })
		-- A tiny torii
		new("Frame", {
			Parent = icon,
			Position = UDim2.fromScale(0, 0.1),
			Size = UDim2.fromScale(1, 0.14),
			BackgroundColor3 = Theme.Red,
			UIKit.corner(2),
		})
		new("Frame", {
			Parent = icon,
			Position = UDim2.fromScale(0.1, 0.34),
			Size = UDim2.fromScale(0.8, 0.1),
			BackgroundColor3 = Theme.Red,
		})
		for _, x in { 0.18, 0.7 } do
			new("Frame", {
				Parent = icon,
				Position = UDim2.fromScale(x, 0.2),
				Size = UDim2.fromScale(0.12, 0.8),
				BackgroundColor3 = Theme.Red,
			})
		end
		return icon
	end
	local icon = new("Frame", { Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1 })
	for i = 0, 2 do
		new("Frame", {
			Parent = icon,
			Position = UDim2.fromScale(0.08, 0.16 + i * 0.3),
			Size = UDim2.fromScale(0.84, 0.12),
			BackgroundColor3 = Theme.Text,
			UIKit.round(),
		})
	end
	return icon
end

local function runMenu(info: any)
	if info.action == "home" then
		UIController.close(true)
		UIController.goHome()
	else
		UIController.toggle(info.panel)
	end
end

local function buildHud()
	local root = new("Frame", {
		Name = "HUD",
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})

	-- Stats column (top-left)
	local stats = new("Frame", {
		Name = "Stats",
		Parent = root,
		AnchorPoint = Vector2.zero,
		Position = UDim2.fromOffset(EDGE, EDGE),
		Size = UDim2.fromOffset(STATS_WIDTH, 260),
		BackgroundTransparency = 1,
		UIKit.list(Enum.FillDirection.Vertical, 8),
	})
	table.insert(hudGroupScales, new("UIScale", { Parent = stats }))
	local cashCard = card(stats, 66, 280, 1)
	cashCard.Name = "CashCard"
	cashIcon = UIKit.cashIcon(46)
	cashIcon.Position = UDim2.fromOffset(10, 10)
	cashIcon.Parent = cashCard
	cashLabel = UIKit.text({
		Name = "Cash",
		Parent = cashCard,
		Position = UDim2.fromOffset(64, 4),
		Size = UDim2.new(1, -72, 0, 36),
		Text = "$0",
		FontFace = Theme.Heavy,
		TextSize = 30,
		TextColor3 = Theme.Text,
	})
	incomeLabel = UIKit.text({
		Name = "Income",
		Parent = cashCard,
		Position = UDim2.fromOffset(64, 38),
		Size = UDim2.new(1, -72, 0, 22),
		Text = "+$0/s",
		TextColor3 = Theme.Cash,
		FontFace = Theme.BodyBold,
		TextSize = 15,
	})

	boxCard = card(stats, 64, 280, 2, "TextButton")
	boxCard.Name = "OrbBoxCard"
	boxCard.Text = ""
	boxCard.AutoButtonColor = false
	local orb = UIKit.orbIcon(26)
	orb.Position = UDim2.fromOffset(10, 6)
	orb.Parent = boxCard
	UIKit.text({
		Parent = boxCard,
		Position = UDim2.fromOffset(42, 6),
		Size = UDim2.new(1, -54, 0, 22),
		Text = "ORB BOX",
		FontFace = Theme.Heavy,
		TextSize = 14,
		TextColor3 = Theme.TextDim,
	})
	boxLabel = UIKit.text({
		Name = "Count",
		Parent = boxCard,
		Position = UDim2.fromOffset(42, 6),
		Size = UDim2.new(1, -54, 0, 22),
		Text = "0 / 0",
		FontFace = Theme.BodyBold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local bar, setter = UIKit.bar(UDim2.new(1, -24, 0, 10), Theme.Violet)
	bar.Position = UDim2.fromOffset(12, 32)
	bar.Parent = boxCard
	boxSetter = setter
	boxHint = UIKit.text({
		Name = "Hint",
		Parent = boxCard,
		Position = UDim2.fromOffset(12, 44),
		Size = UDim2.new(1, -24, 0, 16),
		Text = "",
		FontFace = Theme.Body,
		TextSize = 12,
		TextColor3 = Theme.TextFaint,
	})
	boxCard.Activated:Connect(function()
		registry.SoundController.play("click")
		local farm = registry.StateController.farm()
		if farm and UIController.near(Layout.boxWorld(farm), GameConfig.CollectRange) then
			registry.StateController.request("Collect")
		else
			UIController.goHome()
		end
	end)

	carryCard = card(stats, 56, 280, 3)
	carryCard.Name = "CarryCard"
	carryCard.Visible = false
	carryCard.BackgroundColor3 = Theme.VioletDark
	local carryIcon = UIKit.crateIcon("basic", 34)
	carryIcon.Position = UDim2.fromOffset(10, 11)
	carryIcon.Parent = carryCard
	carryLabel = UIKit.text({
		Parent = carryCard,
		Position = UDim2.fromOffset(52, 4),
		Size = UDim2.new(1, -60, 0, 24),
		Text = "Carrying 0 Cursed Orbs",
		FontFace = Theme.BodyBold,
		TextSize = 15,
	})
	carryValue = UIKit.text({
		Parent = carryCard,
		Position = UDim2.fromOffset(52, 28),
		Size = UDim2.new(1, -60, 0, 20),
		Text = "Sell at the Sell Stand",
		TextColor3 = Theme.Gold,
		FontFace = Theme.Body,
		TextSize = 13,
	})

	-- Menu buttons (right side)
	local menu = new("Frame", {
		Name = "Menu",
		Parent = root,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -EDGE, 0.5, 0),
		Size = UDim2.fromOffset(MENU_WIDTH, MENU_HEIGHT),
		BackgroundTransparency = 1,
		UIKit.list(
			Enum.FillDirection.Vertical,
			8,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Center
		),
	})
	table.insert(hudGroupScales, new("UIScale", { Parent = menu }))
	for i, info in MENU do
		local small = info.name == "Settings"
		local scale = new("UIScale")
		local button = new("TextButton", {
			Parent = menu,
			Name = info.name,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = i,
			Size = UDim2.fromOffset(if small then 56 else 82, if small then 56 else 70),
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.08,
			UIKit.corner(16),
			UIKit.stroke(info.color, 2, 0.15),
			scale,
		})
		menuButtons[info.name] = button
		local icon = menuIcon(info)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.fromScale(0.5, if small then 0.27 else 0.1)
		icon.Parent = button
		if not small then
			UIKit.text({
				Parent = button,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -4),
				Size = UDim2.new(1, -4, 0, 16),
				Text = info.name,
				FontFace = Theme.BodyBold,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextWrapped = false,
				TextScaled = false,
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
			runMenu(info)
		end)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		for _, info in MENU do
			if info.hotkey and input.KeyCode == (Enum.KeyCode :: any)[info.hotkey] then
				runMenu(info)
			end
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			UIController.close()
		end
	end)

	toastHolder = new("Frame", {
		Name = "Toasts",
		Parent = root,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(640, 240),
		BackgroundTransparency = 1,
		UIKit.list(
			Enum.FillDirection.Vertical,
			6,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Bottom
		),
	})
	toastScale = new("UIScale", { Parent = toastHolder })
	table.insert(hudGroupScales, toastScale)
end

local function refreshNumbers()
	local state = registry.StateController
	local profile = state.profile
	if not profile then
		return
	end
	-- Smoothly count toward the real balance
	local target = profile.cash
	if math.abs(target - displayedCash) < 1 then
		displayedCash = target
	else
		displayedCash += (target - displayedCash) * 0.18
	end
	cashLabel.Text = Format.cash(displayedCash)
	local ops, income = state.totals()
	incomeLabel.Text = "+" .. Format.cash(income) .. "/s   " .. Format.abbreviate(ops) .. " Orbs per Second"
	local orbs, value, cap = state.box()
	boxLabel.Text = Format.commas(math.floor(orbs)) .. " / " .. Format.commas(cap)
	boxSetter(if cap > 0 then orbs / cap else 0)
	local full = cap > 0 and orbs >= cap
	if full then
		boxHint.Text = "FULL! Collect it to keep producing"
		boxHint.TextColor3 = Theme.Gold
	elseif ops <= 0 then
		boxHint.Text = "Place a Sorcerer to make Cursed Orbs"
		boxHint.TextColor3 = Theme.TextFaint
	else
		boxHint.Text = string.format("Worth %s  -  tap to Collect / go home", Format.cash(value))
		boxHint.TextColor3 = Theme.TextFaint
	end
	local carried = profile.carried
	carryCard.Visible = carried.orbs >= 1
	if carried.orbs >= 1 then
		carryLabel.Text = string.format("Carrying %s Cursed Orbs", Format.commas(carried.orbs))
		carryValue.Text =
			string.format("Sell at the Sell Stand for %s", Format.cash(math.floor(carried.value + 0.5)))
	end
end

function UIController.pulseCash()
	local scale = cashIcon:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = cashIcon })
	scale.Scale = 1.4
	UIKit.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

local function buildLoading()
	loading = new("Frame", {
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(24, 18, 34),
		ZIndex = 50,
		UIKit.text({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.46),
			Size = UDim2.fromOffset(600, 70),
			Text = string.upper(GameConfig.GameName),
			FontFace = Theme.TitleBold,
			TextSize = 56,
			TextColor3 = Theme.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 51,
		}),
		UIKit.text({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.56),
			Size = UDim2.fromOffset(600, 30),
			Text = "Preparing Your Farm...",
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
		Name = "JJKFarmUI",
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
		BackgroundTransparency = 0.5,
		Visible = false,
	})
	-- Panels live in a scroller: if one can't fit at a readable scale it can be panned.
	scroller = new("ScrollingFrame", {
		Name = "PanelScroller",
		Parent = overlay,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.XY,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Gold,
		CanvasSize = UDim2.new(),
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Visible = false,
		ZIndex = 11,
	})
	-- Clicking outside the panel closes it.
	new("TextButton", {
		Name = "Backdrop",
		Parent = scroller,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		ZIndex = 1,
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
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(computeScales)
	UserInputService.LastInputTypeChanged:Connect(computeScales)
	RunService.RenderStepped:Connect(refreshNumbers)
	registry.StateController.Ready:Connect(function()
		UIController.hideLoading()
	end)
end

return UIController
