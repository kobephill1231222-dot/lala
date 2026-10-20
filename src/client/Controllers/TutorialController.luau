--!nonstrict
-- Guided first loop: a pixel step card at the bottom of the screen (UIKit pixel helpers), and
-- a bobbing pixel arrow over each target (Crate Pad, slot, Orb Box, Sell Stand, Crate Shop,
-- Upgrade Shop), or, when the target is off screen, an arrow at the screen's edge pointing
-- toward it. After the tutorial the same pointer guides "Walk me there" requests (pointAt),
-- and a quiet arrow points to the Sell Stand while you carry Cursed Orbs.
-- The arrows are drawn in the front layer (Pixel/Front, above the HUD) and kept clear of the
-- HUD's cards: under the target when the HUD covers the space over it, or, when the target
-- itself is behind a card, just outside the card pointing at it.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.FarmLayout)
local Tutorial = require(Shared.Rules.Tutorial)
local Economy = require(Shared.Rules.Economy)
local Palette = require(Shared.Pixel.Palette)
local Sprite = require(Shared.Pixel.Sprite)
local Icons = require(Shared.Pixel.Art.Icons)

local Pixel = script.Parent.Parent:WaitForChild("Pixel")
local Screen = require(Pixel.Screen)
local Camera2D = require(Pixel.Camera2D)
local Text = require(Pixel.Text)
local Widgets = require(Pixel.Widgets)
local Arrows = require(Pixel.Arrows)
local Front = require(Pixel.Front)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local TutorialController = {}

local player = Players.LocalPlayer
local registry: any

-- Card (HUD, art pixels)
local hud: any
local card: Frame
local stepLabel: Frame
local titleLabel: Frame
local bodyLines: { Frame } = {}
local dots: { Frame } = {}
local skip: TextButton
local cardH = 40
local slide = 1 -- 0..1 slide-in progress
local shownStep = -1

-- Pointer: by the target (in the front layer's world), or on the screen's edge (in its screen
-- layer). Both are above the HUD, so the HUD never hides them.
local pointer: Frame
local pointerUp: Frame -- under the target, pointing up at it
local pointerLabel: Frame
local edgeArrows: { [string]: Frame } = {}
local edgeLabel: Frame
local target: { position: Vector3, label: string?, subtle: boolean, lift: number }? = nil
local adHoc: { position: Vector3, label: string, until_: number }? = nil
local clock = 0

local Z_POINTER = 40
local LABEL_W = 120
local COMPACT_H = 260 -- on screens shorter than this (art pixels), the card shrinks while placing

-- Art pixels from a target's ground point up to where the arrow's tip hovers.
local LIFTS = { Pad = 12, Slot = 24, Box = 20, Sell = 26, CrateShop = 22, UpgradeShop = 22 }

local function targetPosition(kind: string, profile: any): (Vector3?, number?)
	local state = registry.StateController
	local farm = profile.farm
	if kind == "Pad" and farm then
		for pad = 1, Economy.unlockedPads(profile) do
			if state.crateOnPad(pad) then
				return Layout.padWorld(farm, pad).Position, 30 -- over the crate and its timer
			end
		end
		local pad = state.firstEmptyPad() or 1
		return Layout.padWorld(farm, pad).Position, LIFTS.Pad
	elseif kind == "Slot" and farm then
		local slot = state.firstEmptySlot() or 1
		return Layout.slotWorld(farm, slot).Position, LIFTS.Slot
	elseif kind == "Box" and farm then
		return Layout.boxWorld(farm), LIFTS.Box
	elseif kind == "Sell" then
		return Layout.SellStand, LIFTS.Sell
	elseif kind == "CrateShop" then
		return Layout.CrateShop + Vector3.new(0, 0, -8), LIFTS.CrateShop
	elseif kind == "UpgradeShop" then
		return Layout.UpgradeShop + Vector3.new(0, 0, -8), LIFTS.UpgradeShop
	end
	return nil, nil
end

local function pointTo(position: Vector3?, labelText: string?, subtle: boolean?, lift: number?)
	if not position then
		target = nil
		return
	end
	target = { position = position, label = labelText, subtle = subtle == true, lift = lift or 14 }
end

local function distanceTo(position: Vector3): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return math.huge
	end
	local d = root.CFrame.Position - position
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

local function panelOpen(): boolean
	local ui = registry.UIController
	local ok, open = pcall(function()
		return ui.currentPanel()
	end)
	return ok and open ~= nil
end

-- Card ----------------------------------------------------------------------------------------

local function cardWidth(): number
	return math.max(160, math.min(hud.w - 8, 296))
end

-- While placing on a short screen the card shows only the step and its title (the placement
-- bar says what to do), so the targets stay in view.
local function compact(): boolean
	local placement = registry.PlacementController
	return placement ~= nil and placement.isActive() and hud.h < COMPACT_H
end

local function layoutCard(stepText: string, title: string, body: string, step: number)
	local w = cardWidth()
	local maxChars = math.floor((w - 12) / 8)
	Widgets.setLabel(stepLabel, stepText, Palette.Amber)
	local titleLines = UIKit.wrap(string.upper(title), maxChars)
	Widgets.setLabel(titleLabel, titleLines[1] or "", Palette.White)
	local lines = if compact() then {} else UIKit.wrap(string.upper(body), maxChars)
	for i = 1, math.max(#lines, #bodyLines) do
		local line = bodyLines[i]
		if not line and lines[i] then
			line = UIKit.label(card, "", 6, 0, { color = Palette.Mist })
			bodyLines[i] = line
		end
		if line then
			line.Visible = lines[i] ~= nil
			if lines[i] then
				Widgets.setLabel(line, lines[i], Palette.Mist)
				line.Position = UDim2.fromOffset(6, 27 + (i - 1) * UIKit.LineHeight)
			end
		end
	end
	-- Progress dots after the step number, Skip on the right.
	local dx = 6 + Text.width(stepText) + 6
	for i, dot in dots do
		dot.Position = UDim2.fromOffset(dx + (i - 1) * 6, 6)
		dot.BackgroundColor3 = if i < step
			then Palette.Leaf
			elseif i == step then Palette.Yellow
			else Palette.Dusk
	end
	skip.Position = UDim2.fromOffset(w - 6 - skip.Size.X.Offset, 4)
	cardH = if #lines > 0 then 27 + #lines * UIKit.LineHeight + 3 else 26
	UIKit.paint(card, w, cardH, "window")
end

-- Bottom middle of the screen, above the placement bar while that's up; slides up into place.
local function placeCard()
	local w = cardWidth()
	local x = math.floor((hud.w - w) / 2)
	local gap = 4
	local placement = registry.PlacementController
	local barH = placement and placement.barHeight and placement.barHeight()
	if barH then
		gap += barH + 2
	end
	local rest = hud.h - cardH - gap
	local y = math.floor(hud.h + (rest - hud.h) * (1 - (1 - slide) ^ 2) + 0.5)
	card.Position = UDim2.fromOffset(x, y)
end

local function buildCard()
	hud = Widgets.screen("JJKGuide", -1)
	card = UIKit.box(hud.root, 0, 0, 200, 40, "window", nil, "TutorialCard")
	card.Visible = false
	stepLabel = UIKit.label(card, "", 6, 4, { color = Palette.Amber })
	titleLabel = UIKit.label(card, "", 6, 15, { color = Palette.White })
	for i = 1, #Tutorial.Steps do
		dots[i] = UIKit.rect(card, 0, 0, 4, 4, Palette.Dusk, "Dot" .. i)
	end
	skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.Text = ""
	skip.AutoButtonColor = false
	skip.BackgroundTransparency = 1
	skip.BorderSizePixel = 0
	skip.Size = UDim2.fromOffset(Text.width("SKIP TUTORIAL") + 1, 10)
	skip.ZIndex = UIKit.Z
	skip.Active = true
	skip.Parent = card
	local skipText = UIKit.label(skip, "SKIP TUTORIAL", 0, 1, { color = Palette.Slate })
	skip.MouseEnter:Connect(function()
		UIKit.setLabel(skipText, "SKIP TUTORIAL", Palette.Mist)
	end)
	skip.MouseLeave:Connect(function()
		UIKit.setLabel(skipText, "SKIP TUTORIAL", Palette.Slate)
	end)
	skip.Activated:Connect(function()
		if UIKit.onClick then
			UIKit.onClick()
		end
		registry.StateController.request("SkipTutorial")
	end)
	hud.Changed:Connect(function()
		if card.Visible then
			TutorialController.refresh()
		end
	end)
	-- The card is a card the world prompt keeps clear of.
	Front.addBlocker("tutorialCard", function()
		return hud.gui
	end, function()
		if not card.Visible then
			return {}
		end
		return {
			{
				x = card.Position.X.Offset,
				y = card.Position.Y.Offset,
				w = card.Size.X.Offset,
				h = card.Size.Y.Offset,
			},
		}
	end)
end

-- Pointer -------------------------------------------------------------------------------------

local function buildPointer()
	local world = Front.world :: Frame
	local screen = Front.screen :: Frame
	pointer = Sprite.build(Icons.get("arrow"), { scale = 1, zindex = Z_POINTER, name = "TutorialPointer" })
	pointer.Visible = false
	pointer.Parent = world
	pointerUp = Sprite.build(Arrows.get("n"), { scale = 1, zindex = Z_POINTER, name = "TutorialPointerUp" })
	pointerUp.Visible = false
	pointerUp.Parent = world
	pointerLabel = Text.centered(world, "", LABEL_W, { color = Palette.Yellow, zindex = Z_POINTER })
	pointerLabel.Name = "TutorialLabel"
	pointerLabel.Visible = false
	-- Edge arrows: on the front layer's screen (art pixels from the screen's top-left).
	for _, direction in Arrows.Directions do
		local f =
			Sprite.build(Arrows.get(direction), { scale = 1, zindex = 2, name = "EdgeArrow_" .. direction })
		f.Visible = false
		f.Parent = screen
		edgeArrows[direction] = f
	end
	edgeLabel = Text.centered(screen, "", LABEL_W, { color = Palette.Yellow, zindex = 2 })
	edgeLabel.Name = "TutorialEdgeLabel"
	edgeLabel.Visible = false
end

local function hideEdge()
	for _, f in edgeArrows do
		f.Visible = false
	end
	edgeLabel.Visible = false
end

-- Space kept free at the screen's top (the top bar) and bottom (the card), in art pixels.
local function margins(): (number, number)
	local inset = 0
	local ok, value = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if ok and typeof(value) == "Vector2" then
		inset = math.ceil(value.Y / math.max(1, Screen.scale))
	end
	local bottomGap = 10
	if card.Visible then
		bottomGap = hud.h - card.Position.Y.Offset + 4
	end
	return inset + 8, bottomGap
end

local function overlaps(blockers: { Front.Rect }, x0: number, y0: number, x1: number, y1: number): boolean
	return Front.overlap(blockers, x0, y0, x1, y1) > 0
end

local function drawPointer()
	if not target then
		pointer.Visible = false
		pointerUp.Visible = false
		pointerLabel.Visible = false
		hideEdge()
		return
	end
	local tx, ty = Camera2D.toArt(target.position)
	local x0, y0, x1, y1 = Camera2D.view()
	local topGap, bottomGap = margins()
	local blockers = Front.blockers()
	local bob = math.floor((math.sin(clock * 6) + 1) * 1.5 + 0.5) -- 0..3 px
	local showLabel = not target.subtle and target.label ~= nil
	local labelText = if showLabel then string.upper(target.label :: string) else ""
	local labelW = Text.width(labelText)
	local function inView(ax0: number, ay0: number, ax1: number, ay1: number): boolean
		return ax0 >= x0 + 2 and ax1 <= x1 - 2 and ay0 >= y0 + topGap and ay1 <= y1 - bottomGap
	end
	local function clearAt(ax0: number, ay0: number, ax1: number, ay1: number): boolean
		if not inView(ax0, ay0, ax1, ay1) or overlaps(blockers, ax0, ay0, ax1, ay1) then
			return false
		end
		return true
	end
	-- 1. Over the target (the arrow's tip just above it, the label over the arrow).
	local arrow = Icons.get("arrow")
	local tipY = ty - target.lift
	local ay = tipY - arrow.h
	local labelY = ay - 10
	local half = math.floor(labelW / 2)
	local aboveClear = clearAt(tx - 5, ay - 3, tx + 5, tipY)
		and (not showLabel or clearAt(tx - half, labelY - 3, tx + half + 1, labelY + 9))
	-- 2. Under it, pointing up (when the HUD covers the space over it).
	local below = ty + 8
	local belowClear = not aboveClear
		and clearAt(tx - 5, below, tx + 5, below + 12)
		and (not showLabel or clearAt(tx - half, below + 12, tx + half + 1, below + 24))
	if aboveClear or belowClear then
		hideEdge()
		pointer.Visible = aboveClear
		pointerUp.Visible = belowClear
		pointerLabel.Visible = showLabel
		if aboveClear then
			pointer.Position = UDim2.fromOffset(tx - math.floor(arrow.w / 2), ay - bob)
			if showLabel then
				Text.set(pointerLabel, labelText)
				pointerLabel.Position = UDim2.fromOffset(tx - LABEL_W / 2, labelY - bob)
			end
		else
			pointerUp.Position = UDim2.fromOffset(tx - 4, below + bob)
			if showLabel then
				Text.set(pointerLabel, labelText)
				pointerLabel.Position = UDim2.fromOffset(tx - LABEL_W / 2, below + 12 + bob)
			end
		end
		return
	end
	pointer.Visible = false
	pointerUp.Visible = false
	pointerLabel.Visible = false
	if panelOpen() then
		hideEdge()
		return
	end
	-- 3. An arrow on the line from the screen's middle to the target: at the screen's edge when
	-- the target is off screen, else just outside whatever card covers it. (Screen art pixels.)
	local screenBlockers = Front.screenBlockers()
	local vw, vh = Screen.viewArtSize()
	local sx, sy = tx - x0, ty - target.lift / 2 - y0
	local left, right = 8, vw - 8
	local top, bottom = topGap, vh - bottomGap
	if bottom - top < 16 then
		top = bottom - 16
	end
	local cx, cy = (left + right) / 2, (top + bottom) / 2
	local dx, dy = sx - cx, sy - cy
	local kx = if dx ~= 0 then ((if dx > 0 then right else left) - cx) / dx else math.huge
	local ky = if dy ~= 0 then ((if dy > 0 then bottom else top) - cy) / dy else math.huge
	local k = math.min(math.abs(kx), math.abs(ky), 1)
	local len = math.max(1, math.sqrt(dx * dx + dy * dy))
	local ux, uy = dx / len, dy / len
	local function labelSpot(ex: number, ey: number): (number, number)
		-- Beside the arrow, toward the middle of the screen, kept on screen.
		local lx = math.clamp(ex - math.floor(ux * 16), left + LABEL_W / 2, right - LABEL_W / 2)
		local ly = math.clamp(ey - math.floor(uy * 14) - 4, top, bottom - 8)
		return lx, ly
	end
	local function spotClear(ex: number, ey: number): boolean
		if Front.overlap(screenBlockers, ex - 5, ey - 5, ex + 5, ey + 5) > 0 then
			return false
		end
		if showLabel then
			local lx, ly = labelSpot(ex, ey)
			return Front.overlap(screenBlockers, lx - half, ly, lx + half + 1, ly + 9) == 0
		end
		return true
	end
	-- Walk in from the edge (or from the target) toward the middle until it's clear.
	local ex, ey = cx + dx * k, cy + dy * k
	local dist = len * k
	while dist > 0 and not spotClear(math.floor(ex + 0.5), math.floor(ey + 0.5)) do
		dist -= 3
		ex, ey = cx + ux * dist, cy + uy * dist
	end
	if dist <= 0 then
		ex, ey = cx + dx * k, cy + dy * k -- nowhere clear: on the edge (above the HUD anyway)
	end
	-- Bob toward the target.
	local fx = math.floor(ex + ux * bob + 0.5)
	local fy = math.floor(ey + uy * bob + 0.5)
	local direction = Arrows.direction(dx, dy)
	for name, f in edgeArrows do
		local show = name == direction
		f.Visible = show
		if show then
			f.Position = UDim2.fromOffset(fx - 4, fy - 4)
		end
	end
	edgeLabel.Visible = showLabel
	if showLabel then
		Text.set(edgeLabel, labelText)
		local lx, ly = labelSpot(math.floor(ex + 0.5), math.floor(ey + 0.5))
		edgeLabel.Position = UDim2.fromOffset(lx - LABEL_W / 2, ly)
	end
end

-- Refresh -------------------------------------------------------------------------------------

function TutorialController.refresh()
	local profile = registry.StateController.profile
	if not profile or not card then
		return
	end
	local step = Tutorial.current(profile)
	if not step then
		card.Visible = false
		if adHoc and (os.clock() > adHoc.until_ or distanceTo(adHoc.position) < 14) then
			adHoc = nil
		end
		if adHoc then
			pointTo(adHoc.position, adHoc.label, false, 14)
		elseif profile.carried.orbs >= 1 and distanceTo(Layout.SellStand) > GameConfig.SellRange then
			pointTo(Layout.SellStand, "Sell Stand", true, LIFTS.Sell)
		else
			pointTo(nil)
		end
		return
	end
	if shownStep ~= profile.tutorial then
		shownStep = profile.tutorial
		slide = 0
	end
	card.Visible = true
	local text, kind = Tutorial.guidance(profile, registry.StateController.now())
	layoutCard(
		string.format("STEP %d / %d", profile.tutorial, #Tutorial.Steps),
		step.title,
		text or step.text,
		profile.tutorial
	)
	placeCard()
	kind = kind or step.target
	local position, lift = targetPosition(kind, profile)
	pointTo(position, LABELS[kind], false, lift)
end

local refresh = TutorialController.refresh

-- What the pointer shows (for tests): position, label, and whether it's over the target or on
-- the screen's edge.
function TutorialController.pointer(): any
	if not target then
		return nil
	end
	local edge = false
	for _, f in edgeArrows do
		edge = edge or f.Visible
	end
	return {
		position = target.position,
		label = target.label,
		subtle = target.subtle,
		onScreen = pointer.Visible or pointerUp.Visible,
		below = pointerUp.Visible,
		edge = edge,
	}
end

function TutorialController.init(reg: any)
	registry = reg
end

function TutorialController.start()
	Screen.start()
	Front.start()
	buildCard()
	buildPointer()
	registry.StateController.Changed:Connect(refresh)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		refresh()
	end)
	refresh()
	local elapsed = 0
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		elapsed += dt
		if elapsed > 0.5 then
			elapsed = 0
			refresh()
		end
		if card.Visible then
			slide = math.min(1, slide + dt / 0.3)
			placeCard()
		end
		drawPointer()
	end)
end

return TutorialController
