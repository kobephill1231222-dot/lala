--!nonstrict
-- Makes production visible. For every farm near the camera:
--   * each placed Sorcerer performs its technique (Punch / Slash / Cast / Shoot) on a beat
--     set by its Orbs per Second, and a Cursed Orb in its technique colour appears;
--   * the orb arcs over the slot's chute into the collection lane, rides the moving lane to
--     the Orb Box and drops in;
--   * the Orb Box's glowing pile rises with its contents, and turns gold when full.
-- Purely cosmetic: the server's numbers (replicated as farm attributes) decide what the box
-- holds; this only animates them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.FarmLayout)
local Sorcerers = require(Shared.Config.Sorcerers)

local ProductionController = {}

local player = Players.LocalPlayer
local registry: any

local ACTIVE_RANGE = 260 -- farms further than this from the camera don't animate
local LANE_SPEED = 13 -- studs/s
local MIN_INTERVAL = 0.85 -- fastest visual beat per sorcerer
local ARC_TIME = 0.45
local DROP_TIME = 0.4
local GOLD = Color3.fromRGB(255, 205, 90)

type Worker = {
	model: Model,
	root: BasePart,
	base: CFrame,
	slot: number,
	def: any,
	timer: number,
	anim: number, -- seconds into the current technique animation (-1 = idle)
	phase: number,
}

type Orb = {
	part: BasePart,
	farm: any,
	stage: number, -- 1 arc, 2 lane, 3 drop
	t: number,
	from: Vector3,
	to: Vector3,
	z: number, -- lane-local z while riding
}

type FarmFx = {
	index: number,
	model: Model,
	floor: CFrame,
	workers: { [Model]: Worker },
	slats: { { part: BasePart, offset: number } },
	fill: BasePart?,
	fillBaseY: number,
	fillMax: number,
	fillSize: Vector3,
	boxCenter: CFrame,
	active: boolean,
	pulse: number,
}

local farms: { FarmFx } = {}
local orbs: { Orb } = {}
local pool: { BasePart } = {}
local fxFolder: Folder
local clock = 0
local lastOrbSound = 0

-- Orb Box contents of any farm, from the server's replicated numbers.
function ProductionController.boxOf(model: Instance): (number, number, number, number)
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

local function getOrbPart(color: Color3): BasePart
	local part = table.remove(pool)
	if not part then
		local p = Instance.new("Part")
		p.Name = "CursedOrb"
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(1.2, 1.2, 1.2)
		p.Material = Enum.Material.Neon
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		local a0 = Instance.new("Attachment")
		a0.Name = "A0"
		a0.Position = Vector3.new(0, 0.35, 0)
		a0.Parent = p
		local a1 = Instance.new("Attachment")
		a1.Name = "A1"
		a1.Position = Vector3.new(0, -0.35, 0)
		a1.Parent = p
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.25
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Transparency = NumberSequence.new(0.3, 1)
		trail.Parent = p
		part = p
	end
	assert(part)
	part.Color = color
	part.Transparency = 0
	part.Size = Vector3.new(1.2, 1.2, 1.2)
	local trail = part:FindFirstChildOfClass("Trail")
	if trail then
		trail.Color = ColorSequence.new(color)
		trail.Enabled = true
	end
	part.Parent = fxFolder
	return part
end

local function releaseOrb(part: BasePart)
	local trail = part:FindFirstChildOfClass("Trail")
	if trail then
		trail.Enabled = false
	end
	part.Parent = nil
	if #pool < 200 then
		table.insert(pool, part)
	else
		part:Destroy()
	end
end

local function arc(a: Vector3, b: Vector3, t: number, height: number): Vector3
	local p = a:Lerp(b, t)
	return p + Vector3.new(0, height * 4 * t * (1 - t), 0)
end

-- Technique animations: offsets applied to the sorcerer's base CFrame. `t` in 0..1.
local DURATION = 0.55
local function techniqueOffset(style: string, t: number): CFrame
	local s = math.sin(t * math.pi)
	if style == "Punch" then
		-- wind up back, then lunge forward
		local u = (t - 0.3) / 0.7
		local forward = if t < 0.3 then -0.4 * (t / 0.3) else -0.4 * (1 - u) + 1.9 * math.sin(u * math.pi)
		return CFrame.new(0, 0.15 * s, -forward)
	elseif style == "Slash" then
		-- a full sweeping turn
		local yaw = if t < 0.25 then -35 * (t / 0.25) else -35 + 395 * ((t - 0.25) / 0.75)
		return CFrame.new(0, 0.3 * s, 0) * CFrame.Angles(0, math.rad(yaw), 0)
	elseif style == "Shoot" then
		-- draw, release, recoil
		local u = (t - 0.5) / 0.5
		local back = if t < 0.5 then 0.2 * (t / 0.5) else 0.2 * (1 - u) + 0.6 * math.sin(u * math.pi)
		return CFrame.new(0, 0, back) * CFrame.Angles(math.rad(-6 * s), 0, 0)
	end
	-- Cast: rise and turn while the energy gathers
	return CFrame.new(0, 1.2 * s, 0) * CFrame.Angles(0, math.rad(25 * math.sin(t * math.pi * 2)), 0)
end

local function techniqueFx(worker: Worker, farm: FarmFx)
	local root = worker.root
	local color = worker.def.color
	local cast = root:FindFirstChild("Cast") :: Attachment?
	local origin = if cast
		then (root.CFrame * cast.CFrame).Position
		else root.CFrame.Position + Vector3.new(0, 3, 0)
	local style = worker.def.style
	local effects = registry.EffectsController
	if style == "Punch" then
		effects.ring(origin, color, 1, 7, 0.35, worker.base.LookVector)
	elseif style == "Slash" then
		effects.slashArc(worker.base * CFrame.new(0, 3.2, -1.5), color)
	elseif style == "Cast" then
		effects.ring((worker.base * CFrame.new(0, 0.7, 0)).Position, color, 3, 9, 0.6)
	else
		effects.streak(origin, origin + worker.base.LookVector * 6, color)
	end
	local _ = farm
end

local function spawnOrb(farm: FarmFx, worker: Worker)
	local cast = worker.root:FindFirstChild("Cast") :: Attachment?
	local from = if cast
		then (worker.root.CFrame * cast.CFrame).Position
		else worker.root.CFrame.Position + Vector3.new(0, 3, 0)
	local entry = farm.floor * CFrame.new(Layout.laneEntry(worker.slot))
	local part = getOrbPart(worker.def.color)
	part.CFrame = CFrame.new(from)
	table.insert(orbs, {
		part = part,
		farm = farm,
		stage = 1,
		t = 0,
		from = from,
		to = entry.Position,
		z = Layout.laneEntry(worker.slot).Z,
	})
end

local function addWorker(farm: FarmFx, model: Instance)
	if not model:IsA("Model") then
		return
	end
	local root = model.PrimaryPart
	local def = Sorcerers.get((model:GetAttribute("SorcererId") :: any) or "")
	local slot = model:GetAttribute("Slot")
	if not root or not def or not slot then
		return
	end
	farm.workers[model] = {
		model = model,
		root = root,
		base = root.CFrame,
		slot = slot,
		def = def,
		timer = math.random() * 1.2,
		anim = -1,
		phase = math.random() * math.pi * 2,
	}
end

local function setupFarm(model: Model, index: number)
	local fx: FarmFx = {
		index = index,
		model = model,
		floor = Layout.farmFloor(index),
		workers = {},
		slats = {},
		fill = nil,
		fillBaseY = 0,
		fillMax = 1,
		fillSize = Vector3.one,
		boxCenter = Layout.farmFloor(index) * CFrame.new(Layout.BoxPosition),
		active = false,
		pulse = 0,
	}
	local lane = model:FindFirstChild("Lane")
	local slats = lane and lane:FindFirstChild("Slats")
	if slats then
		for _, slat in slats:GetChildren() do
			if slat:IsA("BasePart") then
				table.insert(fx.slats, { part = slat, offset = slat:GetAttribute("Offset") or 0 })
			end
		end
	end
	local box = model:FindFirstChild("OrbBox")
	local fill = box and box:FindFirstChild("Fill")
	if fill and fill:IsA("BasePart") then
		fx.fill = fill
		fx.fillBaseY = fill:GetAttribute("BaseY") or 1.4
		fx.fillMax = fill:GetAttribute("MaxHeight") or 5
		fx.fillSize = fill.Size
	end
	local runtime = model:WaitForChild("Runtime", 10)
	local folder = runtime and runtime:WaitForChild("Sorcerers", 10)
	if folder then
		for _, child in folder:GetChildren() do
			addWorker(fx, child)
		end
		folder.ChildAdded:Connect(function(child)
			-- Attributes are set before parenting on the server, but give replication a frame.
			task.defer(addWorker, fx, child)
		end)
		folder.ChildRemoved:Connect(function(child)
			fx.workers[child] = nil
		end)
	end
	farms[index] = fx
end

local function boxFull(farm: FarmFx): boolean
	local orbsNow, _, cap = ProductionController.boxOf(farm.model)
	return cap > 0 and orbsNow >= cap - 0.01
end

local function stepFarm(farm: FarmFx, dt: number, camPos: Vector3)
	local center = farm.floor.Position
	farm.active = (camPos - center).Magnitude < ACTIVE_RANGE
	if not farm.active then
		return
	end
	local orbsNow, _, cap, ops = ProductionController.boxOf(farm.model)
	local full = cap > 0 and orbsNow >= cap - 0.01

	-- Lane slats move while anything is producing
	if ops > 0 and not full then
		local length = Layout.LaneStart.Z - Layout.LaneEnd.Z
		for _, slat in farm.slats do
			local z = Layout.LaneEnd.Z + ((slat.offset - clock * LANE_SPEED) % length)
			slat.part.CFrame = farm.floor * CFrame.new(0, Layout.LaneHeight + 0.06, z)
		end
	end

	-- Orb Box pile
	local fill = farm.fill
	if fill then
		local frac = if cap > 0 then math.clamp(orbsNow / cap, 0, 1) else 0
		local h = math.max(0.25, frac * farm.fillMax)
		farm.pulse = math.max(0, farm.pulse - dt * 3)
		local bump = farm.pulse * 0.25
		fill.Size = Vector3.new(farm.fillSize.X, h + bump, farm.fillSize.Z)
		fill.CFrame = farm.boxCenter * CFrame.new(0, farm.fillBaseY + (h + bump) / 2, 0)
		if full then
			local glow = 0.5 + 0.5 * math.sin(clock * 5)
			fill.Color = GOLD:Lerp(Color3.new(1, 1, 1), glow * 0.3)
		else
			fill.Color = Color3.fromRGB(170, 90, 255):Lerp(Color3.new(1, 1, 1), farm.pulse * 0.4)
		end
	end

	-- Sorcerers
	for model, worker in farm.workers do
		if not model.Parent then
			farm.workers[model] = nil
			continue
		end
		local idle = CFrame.new(0, 0.08 * math.sin(clock * 2 + worker.phase), 0)
		if worker.anim >= 0 then
			worker.anim += dt
			local t = worker.anim / DURATION
			if t >= 1 then
				worker.anim = -1
				worker.root.CFrame = worker.base * idle
			else
				worker.root.CFrame = worker.base * techniqueOffset(worker.def.style, t) * idle
				-- Release the orb at the technique's peak
				if t >= 0.5 and t - dt / DURATION < 0.5 then
					techniqueFx(worker, farm)
					spawnOrb(farm, worker)
				end
			end
		else
			worker.root.CFrame = worker.base * idle
			if not full then
				worker.timer -= dt
				if worker.timer <= 0 then
					worker.timer = math.max(MIN_INTERVAL, 1 / math.max(worker.def.ops, 0.01))
						* (0.9 + math.random() * 0.2)
					worker.anim = 0
				end
			end
		end
	end
end

local function stepOrbs(dt: number)
	local laneEndZ = Layout.LaneEnd.Z
	local i = 1
	while i <= #orbs do
		local orb = orbs[i]
		local farm = orb.farm
		local done = false
		orb.t += dt
		if orb.stage == 1 then
			local t = math.min(1, orb.t / ARC_TIME)
			orb.part.CFrame = CFrame.new(arc(orb.from, orb.to, t, 3.5))
			if t >= 1 then
				orb.stage, orb.t = 2, 0
			end
		elseif orb.stage == 2 then
			orb.z -= LANE_SPEED * dt
			if orb.z <= laneEndZ then
				orb.stage, orb.t = 3, 0
				orb.from = (farm.floor * CFrame.new(0, Layout.LaneHeight + 0.8, laneEndZ)).Position
				orb.to = (farm.boxCenter * CFrame.new(0, farm.fillBaseY + farm.fillMax * 0.6, 0)).Position
			else
				orb.part.CFrame = farm.floor * CFrame.new(0, Layout.LaneHeight + 0.8, orb.z)
			end
		else
			local t = math.min(1, orb.t / DROP_TIME)
			orb.part.CFrame = CFrame.new(arc(orb.from, orb.to, t, 4))
			if t >= 1 then
				done = true
				if boxFull(farm) then
					registry.EffectsController.burst(
						orb.to + Vector3.new(0, 1.5, 0),
						Color3.fromRGB(255, 120, 120),
						4,
						6,
						0.4
					)
				else
					farm.pulse = 1
					registry.EffectsController.burst(orb.to, orb.part.Color, 5, 7, 0.45)
					if farm.index == registry.StateController.farm() and clock - lastOrbSound > 0.18 then
						lastOrbSound = clock
						registry.SoundController.play("orb")
					end
				end
			end
		end
		if done or not farm.active then
			releaseOrb(orb.part)
			table.remove(orbs, i)
		else
			i += 1
		end
	end
end

function ProductionController.farmFx(index: number): any
	return farms[index]
end

function ProductionController.orbCount(): number
	return #orbs
end

function ProductionController.init(reg: any)
	registry = reg
end

function ProductionController.start()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ProductionFx"
	fxFolder.Parent = workspace
	task.spawn(function()
		local map = workspace:WaitForChild("JJKFarmMap", 60)
		local folder = map and map:WaitForChild("Farms", 30)
		if not folder then
			return
		end
		for index = 1, Layout.FarmCount do
			local model = folder:WaitForChild("Farm" .. index, 30)
			if model then
				task.spawn(setupFarm, model, index)
			end
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		clock += dt
		local camera = workspace.CurrentCamera
		local camPos = if camera then camera.CFrame.Position else Vector3.zero
		for _, farm in farms do
			stepFarm(farm, dt, camPos)
		end
		stepOrbs(dt)
	end)
	local _ = player
end

return ProductionController
