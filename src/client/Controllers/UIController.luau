--!nonstrict
-- Owns the HUD, the modal panels and toasts, drawn as pixel art. Everything is built in art
-- pixels inside groups blown up by a whole-number UIScale (the world's scale S from
-- Pixel/Screen), and placed at whole multiples of S, so the HUD sits on the same pixel grid
-- at every screen size (phone S=2 up to 1440p S=7). Panels use the largest whole scale up to
-- S that fits the screen (they scroll when even that doesn't fit).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.FarmLayout)
local Format = require(Shared.Util.Format)
local Palette = require(Shared.Pixel.Palette)
local Sprite = require(Shared.Pixel.Sprite)
local Icons = require(Shared.Pixel.Art.Icons)
local Fx = require(Shared.Pixel.Art.Fx)

local Client = script.Parent.Parent
local Screen = require(Client.Pixel.Screen)
local UIKit = require(Client.UI.UIKit)

local UIController = {}

local P = Palette
local fromOffset = UDim2.fromOffset
local player = Players.LocalPlayer
local new = UIKit.new

-- Layout in art pixels.
local EDGE = 3 -- from the screen edges
local GAP = 2 -- between cards / buttons
local CARD_W = 136
local CASH_H = 34
local BOX_H = 39 -- title and count, fill bar, two hint lines
local CARRY_MIN_W = 96 -- narrowest the carried-orbs card may get when it moves beside the column
local MAX_TOASTS = 4
local COUNT_CHARS = 14 -- the Orb Box count abbreviates beyond this (room left of the icon)
local MENU_BUTTON_H = 16
local MENU_W = 100
local MENU_COMPACT_W = 18
local TOAST_MAX_W = 184
local DEFAULT_PANEL = Vector2.new(316, 164) -- for panelPixelScale before any panel is open

local registry: any
local gui: ScreenGui
local hud: Frame
local groups: { [string]: Frame } = {} -- Stats, Menu, Toasts (each has its own UIScale)
local groupScales: { UIScale } = {}
local overlay: Frame
local dim: TextButton
local scroller: ScrollingFrame
local backdrop: TextButton
local panels: { [string]: any } = {}
local current: string? = nil
local menuButtons: { [string]: GuiObject } = {}
local menuParts: { [string]: any } = {}
local loading: Frame?
local loadingArt: Frame?
local loadingCoin: Frame?

-- HUD parts
local cashCard: Frame
local coin: Frame
local coinFlash: Frame
local cashLabel: Frame
local incomeLabel: Frame
local opsLabel: Frame
local boxCard: TextButton
local boxCount: Frame
local boxTitle: Frame
local boxSetter: (number) -> ()
local boxHint: any -- UIKit.para, two lines
local boxHintKey = ""
local carryCard: Frame
local carryText: any
local carryLines = 0
local carryShown = false
local displayedCash = 0
local pulsing = false

-- Toasts
local toasts: { { frame: Frame, w: number, h: number, offset: number } } = {}
local toastArea = { x0 = 0, x1 = 320, cx = 160, bottom = 160, max = TOAST_MAX_W, clearable = true }
local hudLayout = { w = 0, h = 0, s = 0, touch = false, menuX = 0, menuY = 0, compact = false, carryW = 0 }

UIController.isTouch = false
UIController.panelScale = 1 -- legacy multiplier for screen-pixel UIs (about 1 at 720p)
UIController.pixelScale = 1 -- the HUD's whole-number scale (art pixel -> screen pixels)
UIController.panelPixelScale = 1 -- the whole-number scale panels open at
UIController.hudScale = 1

local function isTouchDevice(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Usable screen size: the ScreenGui's own size (it excludes the top bar inset and safe areas).
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

-- The world's pixel scale: Screen's once it has started, else the same rule from the viewport.
local function worldScale(): number
	if Screen.gui then
		return math.max(1, Screen.scale)
	end
	local camera = workspace.CurrentCamera
	local h = if camera then camera.ViewportSize.Y else 720
	return Screen.scaleFor(h)
end

-- Whole-number HUD scale for a usable screen size: the world's scale, reduced only when the
-- screen is too narrow for the HUD at that scale (portrait phones).
local function hudScaleFor(size: Vector2, _touch: boolean?, s: number?): number
	local scale = s or worldScale()
	local minW = EDGE + CARD_W + GAP + MENU_COMPACT_W + EDGE
	while scale > 1 and math.floor(size.X / scale) < minW do
		scale -= 1
	end
	return math.max(1, scale)
end
UIController._hudScaleFor = hudScaleFor -- for tests

-- Largest whole scale (up to the HUD's) at which a panel fits; never below 2 when the HUD is
-- at 2 or more (the panel scrolls instead of shrinking into unreadable text).
local function panelScaleFor(w: number, h: number, size: Vector2): number
	local s = UIController.pixelScale
	local floor = math.min(s, 2)
	for k = s, floor, -1 do
		if w * k <= size.X - 2 and h * k <= size.Y - 2 then
			return k
		end
	end
	return floor
end

-- Toasts ------------------------------------------------------------------------------------

local TONES = {
	info = { fill = P.Dusk, light = P.Steel, dark = P.Night, edge = P.Ink, text = P.White },
	good = { fill = P.Grass, light = P.Leaf, dark = P.Pine, edge = P.Ink, text = P.White },
	bad = { fill = P.Crimson, light = P.Red, dark = P.DarkBrown, edge = P.Ink, text = P.White },
	rare = { fill = P.Orange, light = P.Amber, dark = P.Rust, edge = P.Ink, text = P.White },
	reward = { fill = P.Plum, light = P.Orchid, dark = P.Ink, edge = P.Ink, text = P.White },
	cash = { fill = P.Pine, light = P.Grass, dark = P.DeepTeal, edge = P.Ink, text = P.Yellow, icon = "cash" },
}
UIController.ToastTones = TONES

local clearances: { [string]: any } = {}

-- Keeps the toasts `pixels` art pixels above the bottom edge while something (a card, a bar)
-- sits there; 0 or nil removes it.
function UIController.setToastClearance(key: string, pixels: number?)
	local px = pixels or 0
	clearances[key] = if px > 0 then math.floor(px) else nil
	if groups.Toasts then
		UIController._layoutToasts()
	end
end

-- Space taken at the bottom of the screen by the guide card (TutorialController's
-- JJKGuide.TutorialCard, built in art pixels at the same scale) and any registered clearance.
local function bottomClearance(h: number): number
	local clear = 0
	for _, px in clearances do
		clear = math.max(clear, px)
	end
	pcall(function()
		local guide = player.PlayerGui:FindFirstChild("JJKGuide")
		local card = guide and guide:FindFirstChild("TutorialCard", true)
		if card and card.Visible and guide.Enabled then
			clear = math.max(clear, h - card.Position.Y.Offset + GAP)
		end
	end)
	return clear
end

export type HudRect = { x: number, y: number, w: number, h: number, name: string }

-- The art-pixel rectangles the HUD's cards and menu cover (at UIController.pixelScale, from
-- the HUD gui's top-left, which is below the top bar), so world prompts and toasts can stay
-- clear of them. One rectangle per card: Cash, OrbBox, Carry (while shown), Menu.
function UIController.hudRects(): { HudRect }
	local out: { HudRect } = {}
	local s = math.max(1, hudLayout.s)
	local stats = groups.Stats
	if stats and stats.Visible and cashCard then
		local sx, sy = stats.Position.X.Offset // s, stats.Position.Y.Offset // s
		for _, card in { cashCard, boxCard, carryCard } do
			if card.Visible then
				table.insert(out, {
					name = if card == cashCard then "Cash" elseif card == boxCard then "OrbBox" else "Carry",
					x = sx + card.Position.X.Offset,
					y = sy + card.Position.Y.Offset,
					w = card.Size.X.Offset,
					h = card.Size.Y.Offset,
				})
			end
		end
	end
	local menu = groups.Menu
	if menu and menu.Visible then
		table.insert(out, {
			name = "Menu",
			x = menu.Position.X.Offset // s,
			y = menu.Position.Y.Offset // s,
			w = menu.Size.X.Offset,
			h = menu.Size.Y.Offset,
		})
	end
	return out
end

-- Stacks the toasts upward from the bottom (newest lowest), each as close to the middle of the
-- toast area as it can be without reaching under the menu, and never over the HUD's cards:
-- a toast stops at the lowest card above it. When the stack doesn't fit, the oldest go early;
-- the newest always shows (over the guide card if that's the only room left).
local function layoutToasts()
	local holder = groups.Toasts
	if not holder or #toasts == 0 then
		return
	end
	local floorY = toastArea.bottom
	if toastArea.clearable then
		floorY = math.min(floorY, hudLayout.h - bottomClearance(hudLayout.h) - GAP)
	end
	local rects = UIController.hudRects()
	local cx = toastArea.cx
	local y = floorY
	for i = #toasts, 1, -1 do
		local t = toasts[i]
		local x =
			math.clamp(cx - math.floor(t.w / 2), toastArea.x0, math.max(toastArea.x0, toastArea.x1 - t.w))
		local ceiling = EDGE
		for _, r in rects do
			if x < r.x + r.w + GAP and r.x - GAP < x + t.w then
				ceiling = math.max(ceiling, r.y + r.h + GAP)
			end
		end
		local top = y - t.h
		if top < ceiling then
			if i < #toasts then
				-- No room: this toast and every older one go now.
				for _ = 1, i do
					local old = table.remove(toasts, 1)
					if old then
						old.frame:Destroy()
					end
				end
				break
			end
			top = math.max(EDGE, math.min(ceiling, toastArea.bottom - t.h))
		end
		t.frame.Position = fromOffset(x, top + t.offset)
		y = top - GAP
	end
end

UIController._layoutToasts = layoutToasts

function UIController.toast(text: string, tone: string?, duration: number?)
	local holder = groups.Toasts
	if not holder then
		return
	end
	local style = TONES[tone or "info"] or TONES.info
	local iconW = if style.icon then 12 else 0
	local maxW = math.max(64, math.min(toastArea.max, toastArea.x1 - toastArea.x0))
	local chars = math.max(6, math.floor((maxW - 8 - iconW) / 8))
	local lines = UIKit.wrap(text, chars)
	local longest = 0
	for _, line in lines do
		longest = math.max(longest, #line)
	end
	local w = 8 + iconW + longest * 8
	local h = 5 + #lines * UIKit.LineHeight
	local frame = UIKit.box(holder, 0, 0, w, h, style, "Frame", "Toast")
	frame.Active = false
	if style.icon then
		local icon = UIKit.icon(style.icon)
		icon.Position = fromOffset(3, math.floor((h - 10) / 2))
		icon.Parent = frame
	end
	for i, line in lines do
		UIKit.label(
			frame,
			line,
			4 + iconW,
			3 + (i - 1) * UIKit.LineHeight,
			{ color = style.text, name = "Line" .. i }
		)
	end
	frame:SetAttribute("Text", text)
	frame:SetAttribute("Tone", tone or "info")
	local entry = { frame = frame, w = w, h = h, offset = 3 }
	table.insert(toasts, entry)
	while #toasts > MAX_TOASTS do
		local oldest = table.remove(toasts, 1)
		if oldest then
			oldest.frame:Destroy()
		end
	end
	layoutToasts()
	-- Slides up into place a pixel at a time.
	task.spawn(function()
		for offset = 2, 0, -1 do
			task.wait(0.03)
			entry.offset = offset
			if frame.Parent then
				layoutToasts()
			end
		end
	end)
	task.delay(duration or 3.2, function()
		local index = table.find(toasts, entry)
		if index then
			table.remove(toasts, index)
			frame:Destroy()
			layoutToasts()
		end
	end)
end

-- Panels -----------------------------------------------------------------------------------

local function layoutPanel(panel: any)
	local size = screenSize()
	local w, h = panel.root.Size.X.Offset, panel.root.Size.Y.Offset
	local k = panelScaleFor(w, h, size)
	UIController.panelPixelScale = k
	if panel.scale.Scale ~= k then
		panel.scale.Scale = k
	end
	local pw, ph = w * k, h * k
	local cw, ch = math.max(size.X, pw + 2 * k), math.max(size.Y, ph + 2 * k)
	cw, ch = math.floor(cw), math.floor(ch)
	scroller.CanvasSize = fromOffset(cw, ch)
	scroller.CanvasPosition = Vector2.new(math.floor((cw - size.X) / 2), math.floor((ch - size.Y) / 2))
	local window = panel.root
	window.AnchorPoint = Vector2.zero
	window.Position = fromOffset(math.floor((cw - pw) / 2), math.floor((ch - ph) / 2))
	backdrop.Size = fromOffset(cw, ch)
end

function UIController.register(name: string, panel: any)
	panels[name] = panel
	panel.root.Visible = false
	panel.root.ZIndex = 2 -- above the click-to-close backdrop
	panel.root.Parent = scroller
	panel.scale.Scale = UIController.panelPixelScale
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
	layoutPanel(panel)
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

-- Is your Orb Box close enough to Collect from (the server's CollectRange)?
local function boxInRange(): boolean
	local farm = registry.StateController.farm()
	return farm ~= nil and UIController.near(Layout.boxWorld(farm), GameConfig.CollectRange)
end

-- HUD -------------------------------------------------------------------------------------

local MENU = {
	{ name = "Sorcerers", label = "SORCERERS", panel = "Sorcerers", hotkey = "G", icon = "sorcerers" },
	{ name = "Crates", label = "CRATES", panel = "Crates", hotkey = "C", icon = "crates" },
	{ name = "Crate Shop", label = "CRATE SHOP", panel = "CrateShop", hotkey = "B", icon = "crateShop" },
	{ name = "Upgrade Shop", label = "UPGRADES", panel = "UpgradeShop", hotkey = "U", icon = "upgradeShop" },
	{ name = "Home", label = "HOME", action = "home", hotkey = "H", icon = "home" },
	{ name = "Settings", label = "SETTINGS", panel = "Settings", icon = "settings" },
}
local MENU_H = #MENU * MENU_BUTTON_H + (#MENU - 1) * GAP

local function runMenu(info: any)
	if info.action == "home" then
		UIController.close(true)
		UIController.goHome()
	else
		UIController.toggle(info.panel)
	end
end

local function group(name: string): Frame
	local f = new("Frame", {
		Name = name,
		Parent = hud,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	table.insert(groupScales, new("UIScale", { Parent = f }))
	groups[name] = f
	return f
end

local function buildMenuButton(menu: Frame, info: any, order: number)
	local button =
		UIKit.box(menu, 0, 0, MENU_W, MENU_BUTTON_H, UIKit.Styles.secondary, "TextButton", info.name)
	button.LayoutOrder = order
	button.Selectable = true
	local face = new("Frame", {
		Name = "Face",
		Parent = button,
		BackgroundTransparency = 1,
		Size = fromOffset(MENU_W, MENU_BUTTON_H),
		ZIndex = UIKit.Z,
	})
	-- The icon shows only in the narrow (icon-only) menu.
	local icon = UIKit.sprite(Icons.get(info.icon), 1, { name = "Icon" })
	icon.Position = fromOffset(4, 3)
	icon.Visible = false
	icon.Parent = face
	local textW = UIKit.textWidth(info.label)
	local label = UIKit.label(face, info.label, 2 + math.floor((MENU_W - 18 - textW) / 2), 4, {
		name = "Label",
		color = P.White,
	})
	local cap = nil
	if info.hotkey then
		cap = UIKit.keycap(face, info.hotkey, MENU_W - 14, 2)
		cap.Name = "Hotkey"
	end
	local press = UIKit.pressable(button, MENU_W, MENU_BUTTON_H, UIKit.Styles.secondary, face)
	button.Activated:Connect(function()
		registry.SoundController.play("click")
		runMenu(info)
	end)
	menuButtons[info.name] = button
	menuParts[info.name] =
		{ button = button, face = face, icon = icon, label = label, cap = cap, press = press }
end

local function buildHud()
	hud = new("Frame", {
		Name = "HUD",
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})

	-- Stats column (top-left): Cash, Orb Box, carried orbs.
	local stats = group("Stats")
	cashCard = UIKit.box(stats, 0, 0, CARD_W, CASH_H, UIKit.Styles.card, "Frame", "CashCard")
	local coinHolder = new("Frame", {
		Name = "Coin",
		Parent = cashCard,
		BackgroundTransparency = 1,
		Position = fromOffset(3, 3),
		Size = fromOffset(10, 10),
		ZIndex = UIKit.Z,
	})
	local coinDef = Icons.get("cash")
	coin = UIKit.sprite(coinDef, 1, { name = "Normal" })
	coin.Parent = coinHolder
	coinFlash = UIKit.sprite(coinDef, 1, {
		name = "Flash",
		palette = { k = P.Orange, y = P.White, a = P.Yellow, o = P.Amber, d = P.Amber, c = P.Orange },
	})
	coinFlash.Visible = false
	coinFlash.Parent = coinHolder
	local textW = CARD_W - 18
	cashLabel = UIKit.label(cashCard, "$0", 15, 4, { name = "Cash", color = P.Yellow, width = textW })
	incomeLabel = UIKit.label(cashCard, "+$0/s", 15, 13, { name = "Income", color = P.Leaf, width = textW })
	local orb = UIKit.orbIcon(10)
	orb.Position = fromOffset(3, 22)
	orb.Parent = cashCard
	opsLabel =
		UIKit.label(cashCard, "0 Orbs/s", 15, 23, { name = "OrbsPerSecond", color = P.Mist, width = textW })

	boxCard = UIKit.box(stats, 0, CASH_H + GAP, CARD_W, BOX_H, UIKit.Styles.card, "TextButton", "OrbBoxCard")
	local boxFace = new("Frame", {
		Name = "Face",
		Parent = boxCard,
		BackgroundTransparency = 1,
		Size = fromOffset(CARD_W, BOX_H),
		ZIndex = UIKit.Z,
	})
	local boxOrb = UIKit.orbIcon(10)
	boxOrb.Position = fromOffset(3, 3)
	boxOrb.Parent = boxFace
	boxTitle = UIKit.label(boxFace, "ORB BOX", 15, 4, { name = "Title", color = P.Mist })
	boxCount = UIKit.label(boxFace, "0/0", 15, 4, {
		name = "Count",
		color = P.White,
		width = CARD_W - 19,
		align = Enum.TextXAlignment.Right,
	})
	local bar, setter = UIKit.bar(fromOffset(CARD_W - 6, 5), P.Orchid)
	bar.Position = fromOffset(3, 14)
	bar.Parent = boxFace
	boxSetter = setter
	boxHint = UIKit.para(boxFace, 4, 20, CARD_W - 8, 2, { name = "Hint", color = P.Slate })
	UIKit.pressable(boxCard, CARD_W, BOX_H, UIKit.Styles.card, boxFace)
	boxCard.Activated:Connect(function()
		registry.SoundController.play("click")
		if boxInRange() then
			registry.StateController.request("Collect")
		else
			UIController.goHome()
		end
	end)

	carryCard = UIKit.box(stats, 0, 0, CARD_W, 33, UIKit.Styles.carry, "Frame", "CarryCard")
	carryCard.Visible = false
	carryText = UIKit.para(carryCard, 4, 3, CARD_W - 8, 5, { name = "Text", color = P.White })

	-- Menu (right side)
	local menu = group("Menu")
	for i, info in MENU do
		buildMenuButton(menu, info, i)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		for _, info in MENU do
			if info.hotkey and input.KeyCode == (Enum.KeyCode :: any)[info.hotkey] then
				local parts = menuParts[info.name]
				if parts and parts.cap then
					UIKit.flashKeycap(parts.cap)
				end
				runMenu(info)
			end
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			UIController.close()
		end
	end)

	group("Toasts")
end

-- Lines of the carried-orbs card for a card `width` art pixels wide.
local function carryLinesFor(width: number): string
	local profile = registry.StateController.profile
	local carried = profile and profile.carried
	if not carried or carried.orbs < 1 then
		return ""
	end
	local chars = math.floor((width - 8) / 8)
	local out = {}
	for _, line in UIKit.wrap(string.format("Carrying %s Cursed Orbs", Format.commas(carried.orbs)), chars) do
		table.insert(out, line)
	end
	for _, line in
		UIKit.wrap(
			string.format("Sell at the Sell Stand for %s", Format.cash(math.floor(carried.value + 0.5))),
			chars
		)
	do
		table.insert(out, line)
	end
	return table.concat(out, "\n")
end

hudLayout.carryW = CARD_W

-- Places every HUD group for the current screen (art pixels -> whole screen pixels).
local function layoutHud()
	if not hud then
		return
	end
	local size = screenSize()
	local touch = isTouchDevice()
	UIController.isTouch = touch
	local s = hudScaleFor(size, touch)
	UIController.pixelScale = s
	UIController.hudScale = s
	for _, scale in groupScales do
		if scale.Scale ~= s then
			scale.Scale = s
		end
	end
	local W, H = math.floor(size.X / s), math.floor(size.Y / s)
	hudLayout.w, hudLayout.h, hudLayout.s, hudLayout.touch = W, H, s, touch

	-- Menu: labelled buttons with keycaps when they fit beside the stats column; icon-only on
	-- touch screens (it keeps the middle of the screen free for toasts, clear of the thumbstick
	-- and jump button) and on narrow screens.
	local compact = touch or W < EDGE + CARD_W + GAP * 2 + MENU_W + EDGE
	local menuW = if compact then MENU_COMPACT_W else MENU_W
	local menuX = W - EDGE - menuW
	local menuY = EDGE -- top-right, as in the approved mock (and clear of the jump button)
	hudLayout.menuX, hudLayout.menuY, hudLayout.compact = menuX, menuY, compact
	local menu = groups.Menu
	menu.Position = fromOffset(menuX * s, menuY * s)
	menu.Size = fromOffset(menuW, MENU_H)
	for i, info in MENU do
		local parts = menuParts[info.name]
		parts.button.Position = fromOffset(0, (i - 1) * (MENU_BUTTON_H + GAP))
		parts.label.Visible = not compact
		parts.icon.Visible = compact
		if parts.cap then
			parts.cap.Visible = not compact and not touch
		end
		parts.face.Size = fromOffset(menuW, MENU_BUTTON_H)
		parts.press.setSize(menuW, MENU_BUTTON_H)
	end

	-- Stats, top-left: the Cash and Orb Box cards side by side when the screen is wide enough
	-- (as in the mock), else stacked. The carry card goes under the Orb Box, except on touch
	-- screens where that would reach into the thumbstick's quarter: then beside the column.
	local stats = groups.Stats
	stats.Position = fromOffset(EDGE * s, EDGE * s)
	local side = not compact and EDGE + 2 * CARD_W + 2 * GAP + menuW + EDGE <= W
	local boxX, boxY = if side then CARD_W + GAP else 0, if side then 0 else CASH_H + GAP
	boxCard.Position = fromOffset(boxX, boxY)
	local boxBottom = boxY + BOX_H
	-- The card's text (and so its height) is worked out for the width it would have in each
	-- place before deciding where it goes.
	local function carryFor(width: number): (string, number, number)
		local text = carryLinesFor(width)
		local lines = if text == "" then 0 else #string.split(text, "\n")
		return text, lines, 3 + math.max(1, lines) * UIKit.LineHeight + 2
	end
	local carryX, carryY, carryW = boxX, boxBottom + GAP, CARD_W
	local text, lines, carryH = carryFor(carryW)
	if touch and EDGE + carryY + carryH > H / 2 then
		local x = boxX + CARD_W + GAP
		local besideText, besideLines, besideH = carryFor(CARD_W)
		local right = (if menuY <= EDGE + besideH then menuX else W - EDGE) - GAP - EDGE
		local w = math.min(CARD_W, right - x)
		if w >= CARRY_MIN_W then
			if w ~= CARD_W then
				besideText, besideLines, besideH = carryFor(w)
			end
			carryX, carryY, carryW = x, 0, w
			text, lines, carryH = besideText, besideLines, besideH
		end
	end
	hudLayout.carryW = carryW
	carryLines = lines
	carryText.set(text)
	carryCard.Position = fromOffset(carryX, carryY)
	UIKit.paint(carryCard, carryW, carryH, UIKit.Styles.carry)
	stats.Size = fromOffset(
		math.max(boxX + CARD_W, carryX + carryW),
		math.max(boxBottom, if carryShown then carryY + carryH else 0)
	)

	-- Toasts: bottom centre, left of the menu column (a wide toast slides left rather than
	-- under it); on touch screens in the bottom-right half (clear of the thumbstick and the
	-- jump button) when that leaves room for them. layoutToasts keeps them below the cards.
	local toastsGroup = groups.Toasts
	toastsGroup.Position = fromOffset(0, 0)
	toastsGroup.Size = fromOffset(W, H)
	toastArea.x0, toastArea.x1, toastArea.bottom = EDGE, menuX - GAP, H - 10
	toastArea.cx = math.floor(W / 2)
	toastArea.clearable = true
	if touch then
		-- Right half, above the jump button (Roblox's: 70px at 95px from the bottom-right on
		-- small screens, 120px at 170px on large ones).
		local short = math.min(size.X, size.Y)
		local jump = math.ceil((if short <= 500 then 95 else 170) / s)
		local x0, x1 = math.floor(W / 2) + GAP, menuX - GAP
		if x1 - x0 >= 96 then
			toastArea.x0, toastArea.x1, toastArea.bottom = x0, x1, H - jump - GAP
			toastArea.cx = math.floor((x0 + x1) / 2)
		end
	end
	toastArea.max = math.min(TOAST_MAX_W, toastArea.x1 - toastArea.x0)
	layoutToasts()

	-- Loading screen art
	if loading and loadingArt then
		loadingArt.Position =
			fromOffset(math.floor((size.X - 200 * s) / 2), math.floor((size.Y - 52 * s) / 2))
		local art = loadingArt:FindFirstChildOfClass("UIScale")
		if art then
			art.Scale = s
		end
	end
end

local carryKey = ""

local function refreshCarry(profile: any)
	local carried = profile.carried
	local show = carried ~= nil and carried.orbs >= 1
	if show ~= carryShown then
		carryShown = show
		carryCard.Visible = show
		carryKey = ""
		layoutHud()
	end
	if show then
		local key = string.format("%d:%d:%d", carried.orbs, math.floor(carried.value + 0.5), hudLayout.carryW)
		if key == carryKey then
			return
		end
		carryKey = key
		local text = carryLinesFor(hudLayout.carryW)
		local lines = #string.split(text, "\n")
		if lines ~= carryLines then
			carryLines = lines
			layoutHud()
		else
			carryText.set(text)
		end
	end
end

local function refreshNumbers()
	local state = registry.StateController
	local profile = state.profile
	if not profile then
		return
	end
	-- Count toward the real balance
	local target = profile.cash
	if math.abs(target - displayedCash) < 1 then
		displayedCash = target
	else
		displayedCash += (target - displayedCash) * 0.18
	end
	UIKit.setLabel(cashLabel, Format.cash(displayedCash), if pulsing then P.White else P.Yellow)
	local ops, income = state.totals()
	UIKit.setLabel(incomeLabel, "+" .. Format.cash(income) .. "/s")
	UIKit.setLabel(opsLabel, Format.abbreviate(ops) .. " Orbs/s")
	local orbs, value, cap = state.box()
	local count = Format.commas(math.floor(orbs)) .. "/" .. Format.commas(cap)
	if #count > COUNT_CHARS then
		count = Format.abbreviate(math.floor(orbs)) .. "/" .. Format.abbreviate(cap)
	end
	UIKit.setLabel(boxCount, count)
	boxTitle.Visible = #count <= 6
	boxSetter(if cap > 0 then orbs / cap else 0)
	local full = cap > 0 and orbs >= cap
	local hint, color
	if full then
		-- Blinks while full: the box has stopped filling.
		hint, color = "FULL! Collect to\nkeep producing", if os.clock() % 1 < 0.6 then P.Yellow else P.Amber
	elseif ops <= 0 then
		hint, color = "Place a Sorcerer\nto make Orbs", P.Slate
	else
		-- What tapping the card does from here: Collect in range, else go home.
		hint = "Worth "
			.. Format.cash(value)
			.. (if boxInRange() then "\ntap to Collect" else "\ntap to go home")
		color = P.Slate
	end
	local key = hint .. tostring(color)
	if key ~= boxHintKey then
		boxHintKey = key
		boxHint.set(hint, color)
	end
	refreshCarry(profile)
end

-- A short flash of the coin (and the Cash figure) when Cash comes in.
function UIController.pulseCash()
	if pulsing or not coin then
		return
	end
	pulsing = true
	task.spawn(function()
		local holder = coin.Parent :: Frame
		for i = 1, 2 do
			coin.Visible, coinFlash.Visible = false, true
			holder.Position = fromOffset(3, 2)
			task.wait(0.08)
			coin.Visible, coinFlash.Visible = true, false
			holder.Position = fromOffset(3, 3)
			if i == 1 then
				task.wait(0.08)
			end
		end
		pulsing = false
	end)
end

local function buildLoading()
	local inset = Vector2.zero
	pcall(function()
		inset = GuiService:GetGuiInset()
	end)
	loading = new("Frame", {
		Name = "Loading",
		Parent = gui,
		Position = UDim2.new(0, 0, 0, -inset.Y),
		Size = UDim2.new(1, 0, 1, inset.Y),
		BackgroundColor3 = P.Ink,
		BorderSizePixel = 0,
		ZIndex = 50,
	})
	loadingArt = new("Frame", {
		Name = "Art",
		Parent = loading,
		BackgroundTransparency = 1,
		Size = fromOffset(200, 52),
		ZIndex = 51,
		new("UIScale", { Scale = 1 }),
	})
	local title = string.upper(GameConfig.GameName)
	UIKit.label(loadingArt, title, math.floor((200 - #title * 16) / 2), 20, {
		name = "Title",
		size = 16,
		color = P.Yellow,
		shadow = P.Crimson,
	})
	local sub = "Preparing Your Farm..."
	UIKit.label(loadingArt, sub, math.floor((200 - #sub * 8) / 2), 43, { name = "Subtitle", color = P.Mist })
	local spinner = Sprite.frames(Fx.coin, { scale = 2, name = "Coin", zindex = 2 })
	spinner.Position = fromOffset(92, 0)
	spinner.Parent = loadingArt
	loadingCoin = spinner
end

function UIController.hideLoading()
	local frame = loading
	if not frame then
		return
	end
	loading = nil
	loadingCoin = nil
	if loadingArt then
		loadingArt.Visible = false
		loadingArt = nil
	end
	-- Fades in whole steps, then goes.
	task.spawn(function()
		for _, t in { 0.3, 0.6, 0.85 } do
			frame.BackgroundTransparency = t
			task.wait(0.08)
		end
		frame:Destroy()
	end)
end

local function computeScales()
	layoutHud()
	local size = screenSize()
	UIController.panelScale = math.clamp(math.min(size.X * 0.95 / 860, (size.Y - 40) * 0.92 / 580), 0.62, 1.2)
	if current and panels[current] then
		layoutPanel(panels[current])
	else
		UIController.panelPixelScale = panelScaleFor(DEFAULT_PANEL.X, DEFAULT_PANEL.Y, size)
	end
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
		DisplayOrder = 10, -- above the pixel world (JJKWorld, -10)
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
		BackgroundColor3 = P.Ink,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Visible = false,
	})
	-- Panels live in a scroller: one that can't fit at a readable scale can be panned (by
	-- dragging or the wheel; no native scroll bar, its images aren't pixel art).
	scroller = new("ScrollingFrame", {
		Name = "PanelScroller",
		Parent = overlay,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.XY,
		ScrollBarThickness = 0,
		TopImage = "",
		MidImage = "",
		BottomImage = "",
		CanvasSize = UDim2.new(),
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Visible = false,
		ZIndex = 11,
	})
	-- Clicking outside the panel closes it.
	backdrop = new("TextButton", {
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
	local screenChanged: any = Screen.Changed
	screenChanged:Connect(function()
		computeScales()
	end)
	computeScales()
	local spin = 0
	local toastClock = 0
	RunService.RenderStepped:Connect(function(dt)
		refreshNumbers()
		-- Keep the toasts above the guide card while it slides in and out.
		toastClock += dt
		if toastClock >= 0.2 and #toasts > 0 then
			toastClock = 0
			layoutToasts()
		end
		if loadingCoin then
			spin += dt
			Sprite.show(loadingCoin, math.floor(spin * 8) % 4 + 1)
		end
	end)
	registry.StateController.Ready:Connect(function()
		UIController.hideLoading()
	end)
end

return UIController
