--!nonstrict
-- Placement mode for Sorcerers (onto production slots) and Crates (onto Crate Pads), in pixel
-- art. Valid targets on Your Farm get a blinking gold outline; the selected one is outlined in
-- white and shows a pale preview of what you're placing (and the bar says who it would swap
-- with). Click a target, or tap it then Place. Works with mouse, touch and gamepad (cycle
-- targets with the d-pad, A to Place, B to cancel). While it's on, the camera frames the
-- targets (the selected one always in the part of the screen the HUD and cards leave clear).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crates = require(Shared.Config.Crates)
local Layout = require(Shared.Config.FarmLayout)
local Sorcerers = require(Shared.Config.Sorcerers)
local Economy = require(Shared.Rules.Economy)
local Palette = require(Shared.Pixel.Palette)
local Characters = require(Shared.Pixel.Art.Characters)
local CrateArt = require(Shared.Pixel.Art.Crates)

local WorldMap = require(Shared.Config.WorldMap)

local Pixel = script.Parent.Parent:WaitForChild("Pixel")
local Screen = require(Pixel.Screen)
local Camera2D = require(Pixel.Camera2D)
local Front = require(Pixel.Front)
local Actor = require(Pixel.Actor)
local Widgets = require(Pixel.Widgets)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local PlacementController = {}

local player = Players.LocalPlayer
local registry: any

type Mode = "sorcerer" | "crate"

type Marker = { frame: Frame, edges: { Frame }, x: number, y: number, size: number }

local active = false
local mode: Mode = "sorcerer"
local itemId: string? = nil -- uid or cid
local selected: number? = nil
local ghost: any = nil -- Actor
local markers: { [number]: Marker } = {}
local markerPool: { Marker } = {}
local connections: { RBXScriptConnection } = {}
local clock = 0
local mouseMoved = false
local settleAt: number? = nil -- re-frame once the cards have slid into place

-- Camera framing (art pixels of the screen's centre): glides from where it was to the goal.
local focusX: number? = nil
local focusY: number? = nil
local goalX: number? = nil
local goalY: number? = nil

-- Bar (HUD, art pixels)
local hud: any
local bar: Frame
local titleLines: { Frame } = {}
local hintLines: { Frame } = {}
local confirmButton: any
local cancelButton: any
local barTitle = ""
local barHint = ""

local MARKER_Z = 6

local function targetPosition(index: number): Vector3?
	local farm = registry.StateController.farm()
	if not farm then
		return nil
	end
	if mode == "sorcerer" then
		return Layout.slotWorld(farm, index).Position
	end
	return Layout.padWorld(farm, index).Position
end

-- Markers ---------------------------------------------------------------------------------------

local function newMarker(): Marker
	local frame = Instance.new("Frame")
	frame.Name = "PlacementMarker"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ZIndex = MARKER_Z
	local edges = {}
	for i = 1, 8 do
		edges[i] = Widgets.rect(frame, "Edge" .. i, 0, 0, 0, 0, Palette.Amber, MARKER_Z)
	end
	return { frame = frame, edges = edges, x = 0, y = 0, size = 0 }
end

-- An outline `thickness` pixels wide around a square of `size` (outer edges first, then an
-- inner ring for the selected one).
local function paintMarker(marker: Marker, selectedOne: boolean, on: boolean)
	local s = marker.size
	local color = if selectedOne
		then (if on then Palette.White else Palette.Yellow)
		else (if on then Palette.Yellow else Palette.Orange)
	local e = marker.edges
	local function set(i: number, x: number, y: number, w: number, h: number, visible: boolean)
		e[i].Position = UDim2.fromOffset(x, y)
		e[i].Size = UDim2.fromOffset(w, h)
		e[i].BackgroundColor3 = color
		e[i].Visible = visible
	end
	-- Corner brackets for the others, a full frame for the selected one.
	if selectedOne then
		set(1, -1, -1, s + 2, 1, true)
		set(2, -1, s, s + 2, 1, true)
		set(3, -1, 0, 1, s, true)
		set(4, s, 0, 1, s, true)
		set(5, 0, 0, s, 1, true)
		set(6, 0, s - 1, s, 1, true)
		set(7, 0, 1, 1, s - 2, true)
		set(8, s - 1, 1, 1, s - 2, true)
	else
		local c = math.max(3, math.floor(s / 4))
		set(1, -1, -1, c, 1, true)
		set(2, s + 1 - c, -1, c, 1, true)
		set(3, -1, s, c, 1, true)
		set(4, s + 1 - c, s, c, 1, true)
		set(5, -1, 0, 1, c - 1, true)
		set(6, s, 0, 1, c - 1, true)
		set(7, -1, s + 1 - c, 1, c - 1, true)
		set(8, s, s + 1 - c, 1, c - 1, true)
	end
end

local function clearMarkers()
	for _, marker in markers do
		marker.frame.Parent = nil
		table.insert(markerPool, marker)
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
	local size = (if mode == "sorcerer" then Layout.SlotSize else Layout.PadSize) * Layout.PixelsPerStud
	for index = 1, count do
		local occupied = false
		if mode == "crate" then
			occupied = registry.StateController.crateOnPad(index) ~= nil
		end
		local position = targetPosition(index)
		if position and not occupied then
			local marker = table.remove(markerPool) or newMarker()
			local px, py = Camera2D.toArt(position)
			marker.x, marker.y, marker.size = px, py, size
			marker.frame.Position = UDim2.fromOffset(px - size / 2, py - size / 2)
			marker.frame.Size = UDim2.fromOffset(size, size)
			marker.frame.Parent = Screen.layers.Overlay
			markers[index] = marker
		end
	end
end

local function paintMarkers()
	local on = math.floor(clock * 4) % 2 == 0
	for index, marker in markers do
		paintMarker(marker, index == selected, on)
	end
end

-- Bar -------------------------------------------------------------------------------------------

local function setLines(lines: { Frame }, texts: { string }, color: Color3, y: number): number
	for i = 1, math.max(#texts, #lines) do
		local line = lines[i]
		if not line and texts[i] then
			line = UIKit.label(bar, "", 6, 0, { color = color })
			lines[i] = line
		end
		if line then
			line.Visible = texts[i] ~= nil
			if texts[i] then
				Widgets.setLabel(line, texts[i], color)
				line.Position = UDim2.fromOffset(6, y)
				y += 9
			end
		end
	end
	return y
end

-- Title and hint text, with Place / Cancel on the right: beside the title when it fits on
-- one line, else beside the hint's last lines.
local function layoutBar()
	if not hud then
		return
	end
	local w = math.max(160, math.min(hud.w - 8, 320))
	local cw = confirmButton.Size.X.Offset
	local kw = cancelButton.Size.X.Offset
	local buttonsW = cw + 4 + kw
	local fullChars = math.floor((w - 12) / 8)
	local sideChars = math.max(8, math.floor((w - 16 - buttonsW) / 8))
	local title = string.upper(barTitle)
	local hint = string.upper(barHint)
	local buttonsY, h
	if #title <= sideChars then
		buttonsY = 5
		setLines(titleLines, { title }, Palette.White, 9)
		local bottom = setLines(hintLines, UIKit.wrap(hint, fullChars), Palette.Slate, 23)
		h = bottom + 4
	else
		local y = setLines(titleLines, UIKit.wrap(title, fullChars), Palette.White, 5)
		local hintTop = y + 1
		local hintBottom = setLines(hintLines, UIKit.wrap(hint, sideChars), Palette.Slate, hintTop)
		buttonsY = math.max(hintTop, hintBottom - 16)
		h = math.max(hintBottom, buttonsY + 16) + 5
	end
	cancelButton.Position = UDim2.fromOffset(w - 5 - kw, buttonsY)
	confirmButton.Position = UDim2.fromOffset(w - 5 - buttonsW, buttonsY)
	UIKit.paint(bar, w, h, "window")
	bar.Position = UDim2.fromOffset(math.floor((hud.w - w) / 2), hud.h - h - 4)
end

local function setBar(title: string?, hint: string?)
	if title then
		barTitle = title
	end
	if hint then
		barHint = hint
	end
	layoutBar()
end

-- Framing ---------------------------------------------------------------------------------------

-- Where the camera should look so the selected target (with its preview) sits in the clear part
-- of the screen, with as many other targets as possible clear too, near the screen's middle.
local function frameGoal(): (number?, number?)
	local sel = selected and markers[selected]
	if not sel then
		return nil, nil
	end
	local w, h = Screen.viewArtSize()
	local worldW, worldH = WorldMap.pixelSize()
	local blockers = Front.screenBlockers()
	local function box(m: Marker, left: number, top: number, preview: boolean): (number, number, number, number)
		local half = math.floor(m.size / 2) + 3
		local x, y = m.x - left, m.y - top
		return x - half, y - half - (if preview then 22 else 0), x + half, y + half
	end
	local function clear(x0: number, y0: number, x1: number, y1: number): boolean
		return x0 >= 2 and y0 >= 2 and x1 <= w - 2 and y1 <= h - 2 and Front.overlap(blockers, x0, y0, x1, y1) == 0
	end
	local bestLeft, bestTop, bestScore = nil, nil, math.huge
	local seen: { [number]: boolean } = {}
	local step = 6
	for sy = 0, h, step do
		for sx = 0, w, step do
			local left = sel.x - sx
			local top = sel.y - sy
			left = if worldW <= w then math.floor((worldW - w) / 2) else math.clamp(left, 0, worldW - w)
			top = if worldH <= h then math.floor((worldH - h) / 2) else math.clamp(top, 0, worldH - h)
			local key = left * 100000 + top
			if not seen[key] then
				seen[key] = true
				local x0, y0, x1, y1 = box(sel, left, top, true)
				local score
				if clear(x0, y0, x1, y1) then
					score = 0
				else
					local cx0, cy0 = math.max(x0, 0), math.max(y0, 0)
					local cx1, cy1 = math.min(x1, w), math.min(y1, h)
					local inside = math.max(0, cx1 - cx0) * math.max(0, cy1 - cy0)
					local area = (x1 - x0) * (y1 - y0)
					score = 100000 + (area - inside) * 100 + Front.overlap(blockers, x0, y0, x1, y1) * 100
				end
				for index, m in markers do
					if index ~= selected then
						local a0, b0, a1, b1 = box(m, left, top, false)
						if not clear(a0, b0, a1, b1) then
							score += 400
						end
					end
				end
				-- Near the middle of the screen (and of the farm), with as little camera move as
				-- possible from the character.
				local mx, my = sel.x - left - w / 2, sel.y - top - h / 2
				score += math.sqrt(mx * mx + my * my)
				if score < bestScore then
					bestLeft, bestTop, bestScore = left, top, score
				end
			end
		end
	end
	if not bestLeft or not bestTop then
		return nil, nil
	end
	return bestLeft + math.floor(w / 2), bestTop + math.floor(h / 2)
end

-- Re-frames the camera for the selected target (begin, d-pad cycling, select()).
local function frameSelected()
	local x, y = frameGoal()
	if x and y then
		goalX, goalY = x, y
		if not focusX or not focusY then
			local w, h = Screen.viewArtSize()
			focusX, focusY = Camera2D.left + math.floor(w / 2), Camera2D.top + math.floor(h / 2)
		end
	end
end

local function stepCamera(dt: number)
	if not goalX or not goalY or not focusX or not focusY then
		return
	end
	local k = math.min(1, dt * 10)
	focusX += (goalX - focusX) * k
	focusY += (goalY - focusY) * k
	if math.abs(goalX - focusX) < 0.5 and math.abs(goalY - focusY) < 0.5 then
		focusX, focusY = goalX, goalY
	end
	Camera2D.setFocus(Camera2D.toWorld(math.floor(focusX + 0.5), math.floor(focusY + 0.5)))
end

local function releaseCamera()
	if goalX then
		Camera2D.setFocus(nil)
	end
	focusX, focusY, goalX, goalY = nil, nil, nil, nil
end

-- Selection ---------------------------------------------------------------------------------

local function setSelected(index: number?)
	if index == selected and (ghost or not index) then
		return
	end
	selected = index
	if ghost then
		ghost:destroy()
		ghost = nil
	end
	paintMarkers()
	UIKit.setEnabled(confirmButton, index ~= nil)
	local profile = registry.StateController.profile
	if not index or not itemId or not profile then
		setBar(if mode == "sorcerer" then "Choose a production slot" else "Choose a Crate Pad")
		return
	end
	local position = targetPosition(index) :: Vector3
	local px, py = Camera2D.toArt(position)
	if mode == "sorcerer" then
		local unit = profile.units[itemId]
		local def = unit and Sorcerers.get(unit.id)
		if not def then
			return
		end
		local art = Characters.sorcerer(def.id)
		-- A pale copy of the Sorcerer, facing the lane like the real one will.
		local farm = registry.StateController.farm()
		local WorldView = registry.WorldView
		local view = WorldView and farm and WorldView.farm(farm)
		local laneX = if view then view.lane.x + view.lane.w / 2 else px
		ghost = Actor.new(Screen.layers.Actors, { idle = art.idle }, {
			name = "PlacementGhost",
			flip = px > laneX,
			zBias = 3,
			palette = Widgets.tint(art.idle, Palette.White, 0.55),
		})
		ghost:moveTo(px, py + 3)
		ghost:play("idle", 1)
		local occupant = profile.slots[tostring(index)]
		if occupant and occupant ~= itemId then
			local other = profile.units[occupant]
			local otherDef = other and Sorcerers.get(other.id)
			setBar(string.format("Slot %d: swap with %s", index, if otherDef then otherDef.name else "?"))
		else
			setBar(string.format("Place %s on slot %d", def.name, index))
		end
	else
		local crate = profile.crates[itemId]
		local def = crate and Crates.get(crate.tier)
		if not def then
			return
		end
		local sprite = CrateArt.sprite(def.id)
		ghost = Actor.new(Screen.layers.Actors, { crate = sprite }, {
			name = "PlacementGhost",
			zBias = 3,
			palette = Widgets.tint(sprite, Palette.White, 0.55),
		})
		ghost:moveTo(px, py + 6)
		ghost:play("crate", 1)
		setBar(
			string.format(
				"Place %s on Crate Pad %d  (Opening Time %ds)",
				def.name,
				index,
				Economy.openingTime(def.id, profile)
			)
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
		ghost:destroy()
		ghost = nil
	end
	clearMarkers()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	bar.Visible = false
	releaseCamera()
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

-- Screen points: UserInputService:GetMouseLocation() is in viewport space (the world's
-- ScreenGui ignores the top bar inset, so it matches); InputObject.Position (clicks and taps) is
-- below the inset, so the inset is added back before converting.
local function insetY(): number
	local ok, inset = pcall(function()
		return GuiService:GetGuiInset()
	end)
	return if ok and typeof(inset) == "Vector2" then inset.Y else 0
end

local function targetFromScreen(position: Vector2, space: "viewport" | "gui"): number?
	local point = if space == "gui" then position + Vector2.new(0, insetY()) else position
	local world = Camera2D.screenToWorld(point)
	local px, py = Camera2D.toArt(world)
	local best, bestDist = nil, math.huge
	for index, marker in markers do
		local half = marker.size / 2 + 3
		local dx, dy = math.abs(px - marker.x), math.abs(py - marker.y)
		if dx <= half and dy <= half then
			local d = dx * dx + dy * dy
			if d < bestDist then
				best, bestDist = index, d
			end
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
	if root and root:IsA("BasePart") and not Layout.inFarm(farm, root.CFrame.Position) then
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
	setBar(
		nil,
		if UserInputService.TouchEnabled
			then "Tap a glowing " .. (if mode == "sorcerer" then "slot" else "pad") .. ", then Place."
			else "Click a glowing "
				.. (if mode == "sorcerer" then "slot" else "pad")
				.. " to Place. Esc to cancel."
	)
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
	mouseMoved = false
	frameSelected()
	settleAt = clock + 0.6
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function(dt)
			clock += dt
			paintMarkers()
			if settleAt and clock >= settleAt then
				settleAt = nil
				if not mouseMoved then
					frameSelected()
				end
			end
			stepCamera(dt)
			-- Hover selects (once the mouse has moved: the camera glides under a resting one).
			if not active or not mouseMoved or UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
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
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				mouseMoved = true
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
				frameSelected()
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
			if farm and root and root:IsA("BasePart") and not Layout.inFarm(farm, root.CFrame.Position) then
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

-- Selects a target (for tests and tools).
function PlacementController.select(index: number?)
	if active and (index == nil or markers[index]) then
		setSelected(index)
		frameSelected()
	end
end

-- The free targets currently marked (for tests).
function PlacementController.targets(): { number }
	local list = {}
	for index in markers do
		table.insert(list, index)
	end
	table.sort(list)
	return list
end

-- The placement bar's height in HUD art pixels while it's showing (the tutorial card sits
-- above it), else nil.
function PlacementController.barHeight(): number?
	if bar and bar.Visible then
		return bar.Size.Y.Offset
	end
	return nil
end

-- The preview Actor (for tests).
function PlacementController.ghost(): any
	return ghost
end

function PlacementController.init(reg: any)
	registry = reg
end

function PlacementController.start()
	hud = Widgets.screen("JJKPlacement", -1)
	bar = UIKit.box(hud.root, 0, 0, 200, 40, "window", nil, "PlacementBar")
	bar.Visible = false
	confirmButton = UIKit.button({
		parent = bar,
		text = "Place",
		style = "gold",
		size = UDim2.fromOffset(56, 16),
		onClick = confirm,
	})
	cancelButton = UIKit.button({
		parent = bar,
		text = "Cancel",
		style = "secondary",
		size = UDim2.fromOffset(60, 16),
		onClick = PlacementController.cancel,
	})
	hud.Changed:Connect(function()
		layoutBar()
		if active then
			frameSelected()
		end
	end)
	layoutBar()
	-- The bar is a card the world prompt and the guide arrows keep clear of.
	Front.addBlocker("placementBar", function()
		return hud.gui
	end, function()
		if not bar.Visible then
			return {}
		end
		return {
			{
				x = bar.Position.X.Offset,
				y = bar.Position.Y.Offset,
				w = bar.Size.X.Offset,
				h = bar.Size.Y.Offset,
			},
		}
	end)
	player.CharacterRemoving:Connect(function()
		PlacementController.cancel()
	end)
end

return PlacementController
