--!nonstrict
-- Makes production visible, in pixel art. For every farm on screen:
--   * each placed Sorcerer plays its technique (Punch / Slash / Cast / Shoot attack frames) on a
--     beat set by its Orbs per Second, and a Cursed Orb in its technique colour pops out;
--   * the orb arcs into the collection lane, rides the moving lane to the Orb Box and drops in;
--   * the Orb Box's glowing pile rises with its contents, and turns gold when full.
-- Purely cosmetic: the server's numbers (replicated as farm attributes) decide what the box
-- holds; this only animates them. Drawing goes through WorldView's farm handles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.FarmLayout)
local Sorcerers = require(Shared.Config.Sorcerers)
local Palette = require(Shared.Pixel.Palette)
local Sprite = require(Shared.Pixel.Sprite)
local Fx = require(Shared.Pixel.Art.Fx)
local WorldArt = require(Shared.Pixel.Art.World)
local Characters = require(Shared.Pixel.Art.Characters)
local Pixel = script.Parent.Parent:WaitForChild("Pixel")
local Screen = require(Pixel.Screen)
local Camera2D = require(Pixel.Camera2D)

local ProductionController = {}

local registry: any

local LANE_SPEED = 13 * Layout.PixelsPerStud -- art pixels per second
local MIN_INTERVAL = 0.85 -- fastest technique beat per Sorcerer
local DURATION = 0.55 -- one technique
local ARC_TIME = 0.4
local DROP_TIME = 0.35

type Worker = {
	slot: number,
	id: string,
	def: any,
	color: Color3, -- the technique glow drawn on the sprite (orbs and effects use it too)
	timer: number,
	anim: number, -- seconds into the technique (-1 = idle)
	phase: number,
	fired: boolean,
}

type Orb = {
	sprite: Frame,
	key: string,
	farm: number,
	stage: number, -- 1 arc into the lane, 2 ride the lane, 3 drop into the box
	t: number,
	x: number,
	y: number,
	fromX: number,
	fromY: number,
	toX: number,
	toY: number,
}

type FarmState = { workers: { [number]: Worker }, pulse: number, active: boolean }

local states: { [number]: FarmState } = {}
local orbs: { Orb } = {}
local pool: { [string]: { Frame } } = {}
local orbDefs: { [string]: any } = {}
local clock = 0
local lastOrbSound = 0

-- Orb Box contents of any farm, from the server's replicated numbers.
function ProductionController.boxOf(model: Instance?): (number, number, number, number)
	if not model then
		return 0, 0, 0, 0
	end
	local cap = model:GetAttribute("BoxCap") or 0
	local orbsAt = model:GetAttribute("BoxOrbs") or 0
	local value = model:GetAttribute("BoxValue") or 0
	local t = model:GetAttribute("BoxT") or 0
	local ops = model:GetAttribute("Ops") or 0
	local cash = model:GetAttribute("CashRate") or 0
	if ops > 0 and orbsAt < cap then
		local dt = math.clamp(workspace:GetServerTimeNow() - t, 0, GameConfig.MaxOfflineSeconds)
		local added = math.min(cap - orbsAt, ops * dt)
		orbsAt += added
		value += added * cash / ops
	end
	return orbsAt, value, cap, ops
end

local function colorKey(c: Color3): string
	return string.format(
		"%02x%02x%02x",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5)
	)
end

local function getOrb(color: Color3): (Frame, string)
	local key = colorKey(color)
	local list = pool[key]
	local sprite = list and table.remove(list)
	if not sprite then
		local def = orbDefs[key]
		if not def then
			def = Fx.orb(color)
			orbDefs[key] = def
		end
		sprite = Sprite.frames(def, { scale = 1, name = "Orb" })
		sprite:SetAttribute("AnchorX", def.anchor[1])
		sprite:SetAttribute("AnchorY", def.anchor[2])
	end
	sprite.Visible = true
	sprite.Parent = Screen.layers.Overlay
	return sprite, key
end

local function releaseOrb(orb: Orb)
	orb.sprite.Parent = nil
	pool[orb.key] = pool[orb.key] or {}
	if #pool[orb.key] < 40 then
		table.insert(pool[orb.key], orb.sprite)
	else
		orb.sprite:Destroy()
	end
end

local function placeOrb(orb: Orb, x: number, y: number)
	orb.x, orb.y = x, y
	local ax = orb.sprite:GetAttribute("AnchorX") or 3
	local ay = orb.sprite:GetAttribute("AnchorY") or 3
	orb.sprite.Position = UDim2.fromOffset(math.floor(x - ax + 0.5), math.floor(y - ay + 0.5))
end

-- Pixel offset of a technique at time t (0..1): a lunge, a hop or a recoil, toward the lane.
local function techniquePose(style: string, t: number): (number, number, number)
	local frame = if t < 0.3 then 1 elseif t < 0.65 then 2 else 3
	local s = math.sin(t * math.pi)
	if style == "Punch" then
		return frame, if frame == 2 then 2 elseif frame == 1 then -1 else 0, 0
	elseif style == "Cast" then
		return frame, 0, -math.floor(2 * s + 0.5)
	elseif style == "Shoot" then
		return frame, if frame == 3 then -1 else 0, 0
	end
	return frame, 0, -math.floor(s + 0.5) -- Slash
end

local function techniqueFx(farm: any, worker: Worker, sx: number, sy: number, dir: number)
	local effects = registry.EffectsController
	local here = Camera2D.toWorld(sx, sy)
	local color = worker.color
	local style = worker.def.style
	if style == "Punch" then
		effects.ring(here + Vector3.new(dir * 2, 0, -2), color, 1, 4, 0.3)
	elseif style == "Slash" then
		effects.slashArc(CFrame.lookAt(here, here + Vector3.new(dir, 0, 0)) * CFrame.new(0, 0, -1.5), color)
	elseif style == "Cast" then
		effects.ring(here, color, 2, 5, 0.5)
	else
		effects.streak(here + Vector3.new(0, 0, -2.5), here + Vector3.new(dir * 5, 0, -2.5), color)
	end
	local _ = farm
end

local function spawnOrb(farm: any, worker: Worker, sx: number, sy: number, dir: number)
	local sprite, key = getOrb(worker.color)
	local laneX = farm.lane.x + farm.lane.w / 2
	local orb: Orb = {
		sprite = sprite,
		key = key,
		farm = farm.index,
		stage = 1,
		t = 0,
		x = sx,
		y = sy,
		fromX = sx + dir * 4,
		fromY = sy - 12,
		toX = laneX,
		toY = sy - 2,
	}
	placeOrb(orb, orb.fromX, orb.fromY)
	table.insert(orbs, orb)
end

local function boxFull(model: Instance?): boolean
	local orbsNow, _, cap = ProductionController.boxOf(model)
	return cap > 0 and orbsNow >= cap - 0.01
end

local function stepFarm(farm: any, dt: number)
	local state = states[farm.index]
	if not state then
		state = { workers = {}, pulse = 0, active = false }
		states[farm.index] = state
	end
	state.active = farm.visible
	if not farm.visible then
		return
	end
	local orbsNow, _, cap, ops = ProductionController.boxOf(farm.model)
	local full = cap > 0 and orbsNow >= cap - 0.01
	local north = farm.info.north

	-- Lane slats move toward the Orb Box while anything is producing
	if ops > 0 and not full then
		local spacing = WorldArt.SlatSpacing
		local travel = math.floor(clock * LANE_SPEED) % spacing
		farm.slats.Position = UDim2.fromOffset(0, if north then -spacing + travel else -travel)
	end

	-- Orb Box pile
	local inner = farm.boxInterior
	local frac = if cap > 0 then math.clamp(orbsNow / cap, 0, 1) else 0
	local h = math.floor(frac * inner.h + 0.5)
	if orbsNow > 0 then
		h = math.max(h, 1)
	end
	state.pulse = math.max(0, state.pulse - dt * 4)
	local top = if north then inner.y + inner.h - h else inner.y
	farm.boxFill.Position = UDim2.fromOffset(inner.x, top)
	farm.boxFill.Size = UDim2.fromOffset(inner.w, h)
	if full then
		farm.boxFill.BackgroundColor3 = if math.floor(clock * 4) % 2 == 0
			then Palette.Amber
			else Palette.Yellow
	else
		farm.boxFill.BackgroundColor3 = if state.pulse > 0.5 then Palette.Rose else Palette.Orchid
	end

	-- Sorcerers
	local laneX = farm.lane.x + farm.lane.w / 2
	for slot, actor in farm.sorcerers do
		local id = farm.sorcererIds[slot]
		local worker = state.workers[slot]
		if not worker or worker.id ~= id then
			local def = Sorcerers.get(id)
			if not def then
				continue
			end
			worker = {
				slot = slot,
				id = id,
				def = def,
				color = Characters.sorcerer(id).color,
				timer = math.random() * 1.2,
				anim = -1,
				phase = math.random() * 2,
				fired = false,
			}
			state.workers[slot] = worker
		end
		local bx, by = Camera2D.toArt(farm.info.slots[slot])
		by += 3
		local dir = if bx < laneX then 1 else -1
		if worker.anim >= 0 then
			worker.anim += dt
			local t = worker.anim / DURATION
			if t >= 1 then
				worker.anim = -1
				actor:play("idle", 1)
				actor:moveTo(bx, by)
			else
				local frame, ox, oy = techniquePose(worker.def.style, t)
				actor:play("attack", frame)
				actor:moveTo(bx + ox * dir, by + oy)
				if t >= 0.5 and not worker.fired then
					worker.fired = true
					techniqueFx(farm, worker, bx, by - 10, dir)
					spawnOrb(farm, worker, bx, by, dir)
				end
			end
		else
			actor:play("idle", if math.floor(clock * 2 + worker.phase) % 2 == 0 then 1 else 2)
			actor:moveTo(bx, by)
			if not full then
				worker.timer -= dt
				if worker.timer <= 0 then
					worker.timer = math.max(MIN_INTERVAL, 1 / math.max(worker.def.ops, 0.01))
						* (0.9 + math.random() * 0.2)
					worker.anim = 0
					worker.fired = false
				end
			end
		end
	end
	for slot in state.workers do
		if not farm.sorcerers[slot] then
			state.workers[slot] = nil
		end
	end
end

local function arc(
	ax: number,
	ay: number,
	bx: number,
	by: number,
	t: number,
	height: number
): (number, number)
	return ax + (bx - ax) * t, ay + (by - ay) * t - height * 4 * t * (1 - t)
end

local function stepOrbs(dt: number)
	local WorldView = registry.WorldView
	local i = 1
	while i <= #orbs do
		local orb = orbs[i]
		local farm = WorldView.farm(orb.farm)
		local state = states[orb.farm]
		local done = not farm or not state or not state.active
		if not done then
			orb.t += dt
			local north = farm.info.north
			local laneEndY = if north then farm.lane.y + farm.lane.h else farm.lane.y
			local inner = farm.boxInterior
			if orb.stage == 1 then
				local t = math.min(1, orb.t / ARC_TIME)
				local x, y = arc(orb.fromX, orb.fromY, orb.toX, orb.toY, t, 10)
				placeOrb(orb, x, y)
				if t >= 1 then
					orb.stage, orb.t = 2, 0
				end
			elseif orb.stage == 2 then
				local y = orb.y + (if north then 1 else -1) * LANE_SPEED * dt
				if (north and y >= laneEndY) or (not north and y <= laneEndY) then
					orb.stage, orb.t = 3, 0
					orb.fromX, orb.fromY = orb.x, laneEndY
					orb.toX, orb.toY = inner.x + inner.w / 2, inner.y + inner.h / 2
				else
					placeOrb(orb, orb.x, y)
				end
			else
				local t = math.min(1, orb.t / DROP_TIME)
				local x, y = arc(orb.fromX, orb.fromY, orb.toX, orb.toY, t, 6)
				placeOrb(orb, x, y)
				if t >= 1 then
					done = true
					local at = Camera2D.toWorld(orb.toX, orb.toY)
					if boxFull(farm.model) then
						registry.EffectsController.burst(at, Palette.Rose, 4, 6, 0.4)
					else
						state.pulse = 1
						registry.EffectsController.burst(at, Palette.Orchid, 5, 7, 0.45)
						if farm.index == registry.StateController.farm() and clock - lastOrbSound > 0.18 then
							lastOrbSound = clock
							registry.SoundController.play("orb")
						end
					end
				end
			end
		end
		if done then
			releaseOrb(orb)
			table.remove(orbs, i)
		else
			i += 1
		end
	end
end

function ProductionController.farmFx(index: number): any
	return states[index]
end

function ProductionController.orbCount(): number
	return #orbs
end

-- One frame (exposed for tests).
function ProductionController.step(dt: number)
	clock += dt
	local WorldView = registry.WorldView
	for _, farm in WorldView.farms do
		stepFarm(farm, dt)
	end
	stepOrbs(dt)
end

function ProductionController.init(reg: any)
	registry = reg
end

function ProductionController.start()
	RunService.Heartbeat:Connect(ProductionController.step)
end

return ProductionController
