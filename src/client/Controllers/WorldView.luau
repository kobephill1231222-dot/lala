--!strict
-- Draws the live pixel world: the static map (StaticWorld), every farm's fittings (production
-- slots, Crate Pads, the lane, the Orb Box fill, the Collect Pad, the name sign), the Sorcerers
-- and Crates the server publishes on each farm, and every player (with the orbs they carry).
-- The camera follows your character. Other controllers animate through the handles here:
-- ProductionController drives Sorcerer attacks, lane slats, orbs and the Orb Box fill;
-- WorldController puts prompts and labels on the Overlay layer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared.Config.FarmLayout)
local WorldMap = require(Shared.Config.WorldMap)
local Canvas = require(Shared.Pixel.Canvas)
local Palette = require(Shared.Pixel.Palette)
local World = require(Shared.Pixel.Art.World)
local Characters = require(Shared.Pixel.Art.Characters)
local Crates = require(Shared.Pixel.Art.Crates)
local Format = require(Shared.Util.Format)

local Pixel = script.Parent.Parent:WaitForChild("Pixel")
local Screen = require(Pixel.Screen)
local Camera2D = require(Pixel.Camera2D)
local Actor = require(Pixel.Actor)
local Text = require(Pixel.Text)
local StaticWorld = require(Pixel.StaticWorld)

local WorldView = {}

export type SlotView = { frame: Frame, state: string, x: number, y: number, size: number }
export type FarmView = {
	index: number,
	info: WorldMap.FarmInfo,
	model: Model?,
	group: Frame, -- Floor-layer container for this farm's fittings
	rect: { number }, -- art rect x, y, w, h
	slots: { SlotView },
	pads: { SlotView },
	lane: { x: number, y: number, w: number, h: number },
	slats: Frame, -- scrolling slat strip inside the lane (ProductionController moves it)
	boxFill: Frame, -- the Orb Box's contents (ProductionController sizes and colours it)
	boxInterior: { x: number, y: number, w: number, h: number },
	sign: Frame, -- Text holder on the farm's name board
	sorcerers: { [number]: Actor.Actor }, -- by slot
	sorcererIds: { [number]: string },
	crates: { [number]: Actor.Actor }, -- by pad
	crateInfo: { [number]: { tier: string, readyAt: number, cid: string } },
	visible: boolean,
}

local registry: any
local farms: { FarmView } = {}
WorldView.farms = farms

type PlayerView = {
	actor: Actor.Actor,
	last: Vector3?,
	facing: string, -- "down" | "up" | "side" | "sideLeft"
	walkClock: number,
	carry: Actor.Actor?,
	carryLabel: Frame?,
	carried: number,
	name: Frame?,
}
local players: { [Player]: PlayerView } = {}
WorldView.players = players

local clock = 0
local reconcileClock = 0

-- Art pixel position of a world point (whole pixels).
function WorldView.toArt(position: Vector3): (number, number)
	return Camera2D.toArt(position)
end

function WorldView.farm(index: number): FarmView?
	return farms[index]
end

function WorldView.sorcerer(farmIndex: number, slot: number): Actor.Actor?
	local f = farms[farmIndex]
	return f and f.sorcerers[slot]
end

function WorldView.crate(farmIndex: number, pad: number): Actor.Actor?
	local f = farms[farmIndex]
	return f and f.crates[pad]
end

function WorldView.playerActor(player: Player): Actor.Actor?
	local view = players[player]
	return view and view.actor
end

-- Farm fittings ----------------------------------------------------------------------------

local function canvasFrame(parent: Instance, name: string, canvas: Canvas.Canvas, x: number, y: number, w: number, h: number, z: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.ZIndex = z or 1
	canvas:build(f, 1, x, y)
	f.Parent = parent
	return f
end

local function drawSlot(farm: FarmView, view: SlotView, kind: string, state: string)
	if view.state == state and view.frame.Parent then
		return
	end
	for _, child in view.frame:GetChildren() do
		child:Destroy()
	end
	local c = Canvas.new()
	if kind == "slot" then
		World.slot(c, view.x, view.y, view.size, state)
	else
		World.pad(c, view.x, view.y, view.size, state)
	end
	c:build(view.frame, 1, view.x, view.y)
	view.state = state
	local _ = farm
end

local function newSlot(farm: FarmView, kind: string, n: number, position: Vector3, size: number): SlotView
	local px, py = Camera2D.toArt(position)
	local s = size * Layout.PixelsPerStud
	local x, y = px - s / 2, py - s / 2
	local f = Instance.new("Frame")
	f.Name = (if kind == "slot" then "Slot" else "Pad") .. n
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(s, s)
	f.ZIndex = 2
	f.Parent = farm.group
	local view = { frame = f, state = "", x = x, y = y, size = s }
	-- Frames inside are positioned relative to the slot frame
	local inner = Instance.new("Frame")
	inner.Name = "Art"
	inner.BackgroundTransparency = 1
	inner.Size = UDim2.fromOffset(s, s)
	inner.Parent = f
	view.frame = inner
	view.x, view.y = 0, 0
	return view
end

local function buildFarm(info: WorldMap.FarmInfo): FarmView
	local layer = Screen.layers.Floor
	local fx, fy, fw, fh = StaticWorld.artRect(info.floor)
	local group = Instance.new("Frame")
	group.Name = "Farm" .. info.index
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.Size = UDim2.fromOffset(0, 0)
	group.Parent = layer

	-- Lane bed and rails
	local lx, ly, lw, lh = StaticWorld.artRect(info.lane)
	local laneCanvas = Canvas.new()
	World.lane(laneCanvas, lx, ly, lw, lh)
	canvasFrame(group, "Lane", laneCanvas, lx, ly, lw, lh, 1)
	-- Moving slats: a strip one repeat taller than the lane, clipped to the lane, scrolled by
	-- ProductionController (Position.Y from -SlatSpacing to 0).
	local clip = Instance.new("Frame")
	clip.Name = "SlatClip"
	clip.BackgroundTransparency = 1
	clip.BorderSizePixel = 0
	clip.ClipsDescendants = true
	clip.Position = UDim2.fromOffset(lx, ly)
	clip.Size = UDim2.fromOffset(lw, lh)
	clip.ZIndex = 2
	clip.Parent = group
	local spacing = World.SlatSpacing
	local strip = Canvas.new()
	for i = 0, math.ceil(lh / spacing) + 1 do
		strip:offset(0, i * spacing, function()
			World.laneSlats(strip, lw, spacing)
		end)
	end
	local slats = Instance.new("Frame")
	slats.Name = "Slats"
	slats.BackgroundTransparency = 1
	slats.BorderSizePixel = 0
	slats.Size = UDim2.fromOffset(lw, lh + spacing * 2)
	slats.Position = UDim2.fromOffset(0, -spacing)
	strip:build(slats, 1, 0, 0)
	slats.Parent = clip

	-- Orb Box fill (inside the box drawn by StaticWorld)
	local bx, by, bw, bh = StaticWorld.artRect(info.box)
	local ix, iy, iw, ih = World.orbBoxInterior(bx, by, bw, bh)
	local fill = Instance.new("Frame")
	fill.Name = "BoxFill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Palette.Orchid
	fill.Position = UDim2.fromOffset(ix, iy + ih)
	fill.Size = UDim2.fromOffset(iw, 0)
	fill.ZIndex = 3
	fill.Parent = group

	-- Collect Pad
	local cx, cy, cw, ch = StaticWorld.artRect(info.collect)
	local collectCanvas = Canvas.new()
	World.collectPad(collectCanvas, cx, cy, cw, ch)
	canvasFrame(group, "CollectPad", collectCanvas, cx, cy, cw, ch, 1)

	-- Name board beside the gate (outside the fence, on the road side)
	local gx, gy = Camera2D.toArt(info.gate)
	local signW, signH = 72, 12
	local sy = if info.north then fy + fh + 2 else fy - signH - 2
	local sx = gx + 12
	local signCanvas = Canvas.new()
	World.sign(signCanvas, sx, sy, signW, signH)
	local sign = canvasFrame(group, "Sign", signCanvas, sx, sy, signW, signH, 4)
	local text = Text.centered(sign, "EMPTY FARM", signW - 4, { color = Palette.Cream, zindex = 5 })
	text.Position = UDim2.fromOffset(2, 2)
	text.Name = "Title"

	local view: FarmView = {
		index = info.index,
		info = info,
		model = nil,
		group = group,
		rect = { fx, fy, fw, fh },
		slots = {},
		pads = {},
		lane = { x = lx, y = ly, w = lw, h = lh },
		slats = slats,
		boxFill = fill,
		boxInterior = { x = ix, y = iy, w = iw, h = ih },
		sign = text,
		sorcerers = {},
		sorcererIds = {},
		crates = {},
		crateInfo = {},
		visible = true,
	}
	for slot, position in info.slots do
		view.slots[slot] = newSlot(view, "slot", slot, position, Layout.SlotSize)
		drawSlot(view, view.slots[slot], "slot", "locked")
	end
	for pad, position in info.pads do
		view.pads[pad] = newSlot(view, "pad", pad, position, Layout.PadSize)
		drawSlot(view, view.pads[pad], "pad", "locked")
	end
	return view
end

local function farmModel(index: number): Model?
	local map = workspace:FindFirstChild("JJKFarmMap")
	local folder = map and map:FindFirstChild("Farms")
	local model = folder and folder:FindFirstChild("Farm" .. index)
	return if model and model:IsA("Model") then model else nil
end

local function attr(inst: Instance?, name: string): any
	return inst and inst:GetAttribute(name)
end

-- Brings one farm's slots, pads, Sorcerers, Crates and sign up to date with its model.
local function reconcileFarm(farm: FarmView)
	local model = farm.model or farmModel(farm.index)
	farm.model = model
	local unlockedSlots = attr(model, "UnlockedSlots") or 0
	local unlockedPads = attr(model, "UnlockedPads") or 0
	local owned = attr(model, "OwnerId") ~= nil
	for slot, view in farm.slots do
		drawSlot(farm, view, "slot", if owned and slot <= unlockedSlots then "open" else "locked")
	end
	for pad, view in farm.pads do
		drawSlot(farm, view, "pad", if owned and pad <= unlockedPads then "open" else "locked")
	end
	local mine = attr(model, "OwnerId") == Players.LocalPlayer.UserId
	local owner = attr(model, "OwnerName")
	Text.set(
		farm.sign,
		if mine then "YOUR FARM" elseif type(owner) == "string" then string.upper(string.sub(owner, 1, 9)) else "EMPTY FARM",
		if mine then Palette.Yellow else Palette.Cream
	)

	-- Sorcerers
	local runtime = model and model:FindFirstChild("Runtime")
	local sorcererFolder = runtime and runtime:FindFirstChild("Sorcerers")
	local present: { [number]: boolean } = {}
	if sorcererFolder then
		for _, item in sorcererFolder:GetChildren() do
			local slot = item:GetAttribute("Slot")
			local id = item:GetAttribute("SorcererId")
			if type(slot) == "number" and type(id) == "string" and farm.info.slots[slot] then
				present[slot] = true
				if farm.sorcererIds[slot] ~= id then
					if farm.sorcerers[slot] then
						farm.sorcerers[slot]:destroy()
					end
					local art = Characters.sorcerer(id)
					-- Face the lane: slots on the lane's left look right, the others look left.
					local px = Camera2D.toArt(farm.info.slots[slot])
					local laneX = farm.lane.x + farm.lane.w / 2
					local actor = Actor.new(
						Screen.layers.Actors,
						{ idle = art.idle, attack = art.attack },
						{ flip = px > laneX, name = "Sorcerer" .. farm.index .. "_" .. slot }
					)
					local _, py = Camera2D.toArt(farm.info.slots[slot])
					actor:moveTo(px, py + 3)
					actor:play("idle", 1)
					farm.sorcerers[slot] = actor
					farm.sorcererIds[slot] = id
				end
			end
		end
	end
	for slot, actor in farm.sorcerers do
		if not present[slot] then
			actor:destroy()
			farm.sorcerers[slot] = nil
			farm.sorcererIds[slot] = nil
		end
	end

	-- Crates
	local crateFolder = runtime and runtime:FindFirstChild("Crates")
	local onPad: { [number]: boolean } = {}
	if crateFolder then
		for _, item in crateFolder:GetChildren() do
			local pad = item:GetAttribute("Pad")
			local tier = item:GetAttribute("Tier")
			local readyAt = item:GetAttribute("ReadyAt")
			local cid = item:GetAttribute("Cid")
			if type(pad) == "number" and type(tier) == "string" and farm.info.pads[pad] then
				onPad[pad] = true
				local info = farm.crateInfo[pad]
				if not info or info.tier ~= tier or info.cid ~= cid then
					if farm.crates[pad] then
						farm.crates[pad]:destroy()
					end
					local actor = Actor.new(
						Screen.layers.Actors,
						{ crate = Crates.sprite(tier) },
						{ name = "Crate" .. farm.index .. "_" .. pad }
					)
					local px, py = Camera2D.toArt(farm.info.pads[pad])
					actor:moveTo(px, py + 6)
					actor:play("crate", 1)
					local label = Text.centered(nil, "", 40, { zindex = 2 })
					label.Name = "Timer"
					actor:attach("Timer", label, -20, -28)
					farm.crates[pad] = actor
				end
				farm.crateInfo[pad] = {
					tier = tier,
					readyAt = if type(readyAt) == "number" then readyAt else 0,
					cid = if type(cid) == "string" then cid else "",
				}
			end
		end
	end
	for pad, actor in farm.crates do
		if not onPad[pad] then
			actor:destroy()
			farm.crates[pad] = nil
			farm.crateInfo[pad] = nil
		end
	end
end

-- Crate timers: "0:42" while opening, "READY" (blinking) when done.
local function updateCrateLabels(farm: FarmView, now: number)
	for pad, actor in farm.crates do
		local info = farm.crateInfo[pad]
		local label = actor:attachment("Timer")
		if info and label then
			local left = info.readyAt - now
			if left > 0 then
				Text.set(label, Format.clock(left), Palette.White)
			else
				Text.set(label, if math.floor(clock * 3) % 2 == 0 then "READY" else "", Palette.Yellow)
			end
		end
	end
end

-- Players ----------------------------------------------------------------------------------

local SHIRTS = { Palette.Sky, Palette.Red, Palette.Leaf, Palette.Orange, Palette.Orchid, Palette.Cyan, Palette.Amber, Palette.Rose }

local function colorsFor(player: Player): { skin: Color3, shirt: Color3, pants: Color3, hair: Color3 }
	local skin = Palette.Peach
	local character = player.Character
	local body = character and character:FindFirstChildOfClass("BodyColors")
	if body then
		skin = body.HeadColor3
	end
	local shirt = SHIRTS[(math.abs(player.UserId) % #SHIRTS) + 1]
	return { skin = skin, shirt = shirt, pants = Palette.Dusk, hair = Palette.DarkBrown }
end

local function addPlayer(player: Player)
	if players[player] then
		return
	end
	local art = Characters.player(colorsFor(player))
	local actor = Actor.new(Screen.layers.Actors, {
		down = art.down,
		up = art.up,
		side = art.side,
	}, { name = "Player_" .. player.Name, zBias = 1, mirrors = { sideLeft = "side" } })
	local view: PlayerView = {
		actor = actor,
		last = nil,
		facing = "down",
		walkClock = 0,
		carry = nil,
		carryLabel = nil,
		carried = 0,
		name = nil,
	}
	if player ~= Players.LocalPlayer then
		local name = Text.centered(nil, string.upper(string.sub(player.DisplayName, 1, 10)), 80, { color = Palette.Mist, zindex = 3 })
		actor:attach("Name", name, -40, -32)
		view.name = name
	end
	actor:play("down", 1)
	players[player] = view
end

local function removePlayer(player: Player)
	local view = players[player]
	if view then
		view.actor:destroy()
		players[player] = nil
	end
end

local function updateCarry(view: PlayerView, player: Player)
	local carried = player:GetAttribute("CarriedOrbs")
	local n = if type(carried) == "number" then carried else 0
	if n >= 1 and not view.carry then
		-- Held above the head, drawn over the character.
		local carry = Actor.new(view.actor.frame, { carry = Characters.carry }, { name = "Carry" })
		carry.frame.Position = UDim2.fromOffset(0, -Characters.Size.h + 2)
		carry.frame.ZIndex = 2
		carry:play("carry", 1)
		view.carry = carry
		local label = Text.centered(nil, "", 48, { color = Palette.Orchid, zindex = 3 })
		label.Position = UDim2.fromOffset(-24, -40)
		label.Parent = view.actor.frame
		view.carryLabel = label
	elseif n < 1 and view.carry then
		view.carry:destroy()
		view.carry = nil
		if view.carryLabel then
			view.carryLabel:Destroy()
			view.carryLabel = nil
		end
	end
	if view.carry then
		view.carry:play("carry", if math.floor(clock * 4) % 2 == 0 then 1 else 2)
		if view.carryLabel and view.carried ~= n then
			Text.set(view.carryLabel, "x" .. Format.abbreviate(n))
		end
	end
	view.carried = n
	if view.name then
		view.name.Position = UDim2.fromOffset(-40, if view.carry then -48 else -32)
	end
end

local function updatePlayer(player: Player, view: PlayerView, dt: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		view.actor:setVisible(false)
		return
	end
	view.actor:setVisible(true)
	local position = root.CFrame.Position
	local px, py = Camera2D.toArt(position)
	local moving = false
	if view.last then
		local delta = position - view.last
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude > 0.02 then
			moving = true
			if math.abs(delta.Z) > math.abs(delta.X) then
				view.facing = if delta.Z > 0 then "down" else "up"
			else
				view.facing = if delta.X > 0 then "side" else "sideLeft"
			end
		end
	end
	view.last = position
	if moving then
		view.walkClock += dt
	else
		view.walkClock = 0
	end
	local frame = if moving then 2 + (math.floor(view.walkClock * 8) % 2) else 1
	view.actor:play(view.facing, frame)
	view.actor:moveTo(px, py + 4)
	updateCarry(view, player)
end

-- Frame loop -------------------------------------------------------------------------------

local function within(rect: { number }, x0: number, y0: number, x1: number, y1: number, margin: number): boolean
	return rect[1] + rect[3] >= x0 - margin and rect[1] <= x1 + margin and rect[2] + rect[4] >= y0 - margin and rect[2] <= y1 + margin
end

function WorldView.step(dt: number)
	clock += dt
	Camera2D.update()
	local x0, y0, x1, y1 = Camera2D.view()
	StaticWorld.cull(x0, y0, x1, y1)
	reconcileClock -= dt
	local reconcile = reconcileClock <= 0
	if reconcile then
		reconcileClock = 0.2
	end
	local now = workspace:GetServerTimeNow()
	for _, farm in farms do
		local visible = within(farm.rect, x0, y0, x1, y1, 64)
		if visible ~= farm.visible then
			farm.group.Visible = visible
			for _, actor in farm.sorcerers do
				actor:setVisible(visible)
			end
			for _, actor in farm.crates do
				actor:setVisible(visible)
			end
			farm.visible = visible
		end
		if reconcile then
			reconcileFarm(farm)
			if not farm.visible then
				for _, actor in farm.sorcerers do
					actor:setVisible(false)
				end
				for _, actor in farm.crates do
					actor:setVisible(false)
				end
			end
		end
		if farm.visible then
			updateCrateLabels(farm, now)
		end
	end
	for player, view in players do
		if player.Parent == nil then
			removePlayer(player)
		else
			updatePlayer(player, view, dt)
		end
	end
end

function WorldView.init(r: any)
	registry = r
end

function WorldView.start()
	Screen.start()
	StaticWorld.build()
	for _, info in WorldMap.get().farms do
		farms[info.index] = buildFarm(info)
	end
	for _, player in Players:GetPlayers() do
		addPlayer(player)
	end
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(removePlayer)
	RunService.RenderStepped:Connect(WorldView.step)
	WorldView.step(0)
	local _ = registry
end

return WorldView
