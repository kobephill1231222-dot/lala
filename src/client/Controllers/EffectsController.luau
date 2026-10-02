--!nonstrict
-- Client-side visual polish. Ambient animation (ritual circle, tree shards, well crystals,
-- idle units) and one-shot effects driven by server Effect events. Everything here is
-- cosmetic; nothing affects gameplay state.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Abilities = require(Shared.Config.Abilities)
local Layout = require(Shared.Config.MapLayout)
local Rarities = require(Shared.Config.Rarities)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent.UI
local UIKit = require(UI.UIKit)
local Theme = require(UI.Theme)

local EffectsController = {}

local player = Players.LocalPlayer
local registry: any
local fxFolder: Folder
local map: Instance

local VIOLET = Color3.fromRGB(170, 90, 255)
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local function fxPart(
	cf: CFrame,
	size: Vector3,
	color: Color3,
	shape: Enum.PartType?,
	transparency: number?
): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = size
	part.CFrame = cf
	part.Transparency = transparency or 0
	if shape then
		part.Shape = shape
	end
	part.Parent = fxFolder
	return part
end

local function tween(inst: Instance, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?)
	local t = TweenService:Create(
		inst,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

local function burst(position: Vector3, color: Color3, count: number, speed: number?, size: number?)
	local holder = fxPart(CFrame.new(position), Vector3.one, color, nil, 1)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, size or 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.5, 1.1)
	emitter.Speed = NumberRange.new((speed or 14) * 0.5, speed or 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 4
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(count)
	Debris:AddItem(holder, 2)
end

local function ring(position: Vector3, color: Color3, fromSize: number, toSize: number, seconds: number)
	local part = fxPart(
		CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(0.3, fromSize, fromSize),
		color,
		Enum.PartType.Cylinder,
		0.15
	)
	tween(part, seconds, { Size = Vector3.new(0.3, toSize, toSize), Transparency = 1 })
	Debris:AddItem(part, seconds + 0.1)
end

local function pillar(position: Vector3, color: Color3, height: number, seconds: number)
	local part = fxPart(
		CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(height, 3, 3),
		color,
		Enum.PartType.Cylinder,
		0.2
	)
	tween(part, seconds, { Size = Vector3.new(height, 0.2, 0.2), Transparency = 1 })
	Debris:AddItem(part, seconds + 0.1)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 24
	light.Brightness = 3
	light.Parent = part
	tween(light, seconds, { Brightness = 0 })
end

-- Floating "+123" style label at a world position.
function EffectsController.floatText(position: Vector3, text: string, color: Color3, size: number?)
	local anchor = fxPart(CFrame.new(position), Vector3.new(0.2, 0.2, 0.2), color, nil, 1)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 50)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Adornee = anchor
	gui.Parent = anchor
	local label = UIKit.text({
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		Text = text,
		FontFace = Theme.Heavy,
		TextSize = size or 30,
		TextColor3 = color,
		TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	tween(anchor, 1.1, { CFrame = CFrame.new(position + Vector3.new(0, 5, 0)) })
	task.delay(0.6, function()
		tween(label, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	Debris:AddItem(anchor, 1.2)
end

-- World lookups ----------------------------------------------------------------------------

local function wellPosition(plot: number): Vector3
	return (Layout.plotFloorCFrame(plot) * CFrame.new(Layout.WellOffset)).Position
end

local function spotPosition(plot: number, spot: number): Vector3
	return (Layout.plotFloorCFrame(plot) * Layout.spotLocalCFrame(spot)).Position
end

local function nearCamera(position: Vector3, radius: number): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude < radius
end

-- Server effects -----------------------------------------------------------------------------

local handlers: { [string]: (any) -> () } = {}

handlers.Collect = function(payload)
	local position = wellPosition(payload.plot) + Vector3.new(0, 3, 0)
	local mine = payload.userId == player.UserId
	if mine or nearCamera(position, 120) then
		burst(position, VIOLET, if mine then 40 else 16, 18)
		ring(position - Vector3.new(0, 1.5, 0), VIOLET, 4, 18, 0.6)
	end
	if mine then
		EffectsController.floatText(
			position + Vector3.new(0, 4, 0),
			"+" .. Format.abbreviate(payload.amount),
			Color3.fromRGB(220, 180, 255),
			34
		)
		registry.SoundController.play("collect")
		task.delay(0.12, function()
			registry.SoundController.play("coin")
		end)
		registry.UIController.pulseEnergy()
	end
end

local circleBoost = 0
local circleColor: Color3? = nil

handlers.Summon = function(payload)
	local center = Layout.CourtyardCenter + Vector3.new(0, 1.5, 0)
	if not nearCamera(center, 220) then
		return
	end
	local rarity = Rarities.get(payload.rarity)
	local color = if rarity then rarity.color else VIOLET
	circleBoost = 1
	circleColor = color
	pillar(center, color, 70, 1.6)
	ring(center, color, 6, 40, 1)
	burst(center + Vector3.new(0, 2, 0), color, 50, 26, 1)
	if payload.userId ~= player.UserId then
		registry.SoundController.playAt("revealRare", center)
	end
end

handlers.Place = function(payload)
	local position = spotPosition(payload.plot, payload.spot)
	if not nearCamera(position, 160) then
		return
	end
	pillar(position, VIOLET, 22, 0.9)
	ring(position + Vector3.new(0, 1.3, 0), Color3.fromRGB(220, 180, 255), 3, 14, 0.7)
	burst(position + Vector3.new(0, 3, 0), VIOLET, 24, 12)
	registry.SoundController.playAt("place", position)
end

handlers.Unlock = function(payload)
	local position = spotPosition(payload.plot, payload.spot)
	if not nearCamera(position, 160) then
		return
	end
	burst(position + Vector3.new(0, 2.5, 0), Color3.fromRGB(255, 230, 180), 40, 16, 0.8)
	ring(position + Vector3.new(0, 1.3, 0), Color3.fromRGB(255, 200, 120), 3, 16, 0.8)
	registry.SoundController.playAt("unlock", position)
end

handlers.Train = function(payload)
	local position = spotPosition(payload.plot, payload.spot)
	if nearCamera(position, 160) then
		burst(position + Vector3.new(0, 3, 0), Color3.fromRGB(255, 220, 140), 20, 10)
		ring(position + Vector3.new(0, 1.3, 0), Color3.fromRGB(255, 220, 140), 3, 10, 0.5)
	end
end

handlers.Cast = function(payload)
	if payload.userId == player.UserId then
		return -- already played locally for responsiveness
	end
	if nearCamera(payload.origin, 200) then
		EffectsController.abilityVfx(payload.ability, payload.origin, payload.direction)
	end
end

handlers.Hits = function(payload)
	for _, hit in payload.hits do
		EffectsController.floatText(
			hit.position + Vector3.new(math.random() * 2 - 1, 3, math.random() * 2 - 1),
			Format.abbreviate(hit.damage),
			Color3.fromRGB(255, 230, 140),
			26
		)
		burst(hit.position, Color3.fromRGB(255, 200, 255), 10, 10, 0.5)
		if hit.dummy then
			local dojo = map:FindFirstChild("Dojo")
			local dummies = dojo and dojo:FindFirstChild("Dummies")
			local dummy = dummies and dummies:FindFirstChild(hit.dummy) :: Model?
			local post = dummy and dummy.PrimaryPart
			if post then
				local original = post.CFrame
				tween(post, 0.08, { CFrame = original * CFrame.Angles(math.rad(8), 0, 0) })
				task.delay(0.1, function()
					tween(post, 0.3, { CFrame = original }, Enum.EasingStyle.Elastic)
				end)
			end
		end
	end
	registry.SoundController.play("hit")
end

handlers.CurseDeath = function(payload)
	burst(payload.position, Color3.fromRGB(150, 60, 255), 50, 20, 1.2)
	ring(payload.position - Vector3.new(0, 2, 0), Color3.fromRGB(120, 40, 200), 4, 22, 0.8)
	registry.SoundController.playAt("curseDeath", payload.position)
end

handlers.CurseStrike = function(payload)
	ring(payload.position - Vector3.new(0, 2, 0), Color3.fromRGB(255, 60, 110), 2, payload.radius * 2, 0.4)
	registry.SoundController.playAt("curseStrike", payload.position)
end

-- Local ability visuals (also used for other players' casts).
function EffectsController.abilityVfx(abilityId: string, origin: Vector3, direction: Vector3)
	local ability = Abilities.ById[abilityId]
	if not ability then
		return
	end
	local color = ability.color
	local facing = CFrame.lookAt(origin, origin + direction)
	if ability.shape == "Arc" then
		for i = -3, 3 do
			local a = math.rad(i * 16)
			local cf = facing
				* CFrame.Angles(0, a, 0)
				* CFrame.new(0, 0.5, -6)
				* CFrame.Angles(0, 0, math.rad(i * 6))
			local slash = fxPart(cf, Vector3.new(2.6, 0.25, 0.6), color, nil, 0.1)
			tween(slash, 0.25, { Transparency = 1, Size = Vector3.new(3.6, 0.1, 0.3) })
			Debris:AddItem(slash, 0.3)
		end
		registry.SoundController.playAt("strike", origin)
	elseif ability.shape == "Line" then
		local length = ability.range
		local beam =
			fxPart(facing * CFrame.new(0, 0.5, -length / 2), Vector3.new(1.4, 1.4, length), color, nil, 0.05)
		tween(beam, 0.4, { Size = Vector3.new(0.1, 0.1, length), Transparency = 1 })
		Debris:AddItem(beam, 0.45)
		burst((facing * CFrame.new(0, 0.5, -length)).Position, color, 20, 12)
		registry.SoundController.playAt("lance", origin)
	else
		local sphere = fxPart(CFrame.new(origin), Vector3.new(3, 3, 3), color, Enum.PartType.Ball, 0.2)
		local d = ability.range * 2
		tween(sphere, 0.45, { Size = Vector3.new(d, d, d), Transparency = 1 })
		Debris:AddItem(sphere, 0.5)
		ring(origin - Vector3.new(0, 2.5, 0), color, 4, d, 0.5)
		burst(origin, color, 40, 24, 0.9)
		registry.SoundController.playAt("burst", origin)
	end
end

-- Celebrate an upgrade purchase with a quick sparkle around the player.
function EffectsController.upgradeFlash()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		burst(root.Position, Color3.fromRGB(255, 210, 120), 30, 12)
		ring(root.Position - Vector3.new(0, 2.8, 0), Color3.fromRGB(255, 210, 120), 3, 14, 0.6)
	end
end

-- Ambient animation ----------------------------------------------------------------------

type Spinner = { root: BasePart, base: CFrame, speed: number }

local spinners: { Spinner } = {}
local shards: { any } = {}
local crystals: { { root: BasePart, base: CFrame } } = {}

local function collectAnimated()
	local courtyard = map:WaitForChild("Courtyard")
	local circle = courtyard:WaitForChild("Circle")
	local speeds: { [string]: number } =
		{ OuterRing = 0.12, MiddleRing = -0.2, Sigil = 0.06, InnerRing = -0.45 }
	for name, speed in speeds do
		local model = circle:WaitForChild(name, 10)
		local root = model and (model :: Model).PrimaryPart
		if root then
			table.insert(spinners, { root = root, base = root.CFrame, speed = speed })
		end
	end
	local tree = map:WaitForChild("Shrine"):WaitForChild("SpiritTree")
	local shardFolder = tree:FindFirstChild("Shards")
	if shardFolder then
		for _, part in shardFolder:GetChildren() do
			if part:IsA("BasePart") then
				table.insert(shards, {
					part = part,
					radius = part:GetAttribute("OrbitRadius") or 15,
					height = part:GetAttribute("OrbitHeight") or 30,
					phase = part:GetAttribute("OrbitPhase") or 0,
				})
			end
		end
	end
	for _, sanctuary in map:WaitForChild("Sanctuaries"):GetChildren() do
		local well = sanctuary:FindFirstChild("Well")
		local crystal = well and well:FindFirstChild("Crystal")
		local root = crystal and (crystal :: Model).PrimaryPart
		if root then
			table.insert(crystals, { root = root, base = root.CFrame })
		end
	end
end

-- Idle motion for placed units: a gentle bob on their anchored root (welded parts follow).
local function animateUnit(model: Instance)
	if not model:IsA("Model") then
		return
	end
	task.defer(function()
		local root = model.PrimaryPart
		if not root then
			return
		end
		local base = root.CFrame
		root.CFrame = base * CFrame.new(0, -1.5, 0)
		tween(root, 0.5, { CFrame = base }, Enum.EasingStyle.Back)
		task.wait(0.55 + math.random() * 0.8)
		if model.Parent then
			local info = TweenInfo.new(
				1.6 + math.random() * 0.6,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut,
				-1,
				true
			)
			TweenService:Create(root, info, { CFrame = base * CFrame.new(0, 0.35, 0) }):Play()
		end
	end)
end

-- Curse health bars and attack telegraphs.
local function trackCurse(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local root = model:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not root then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "CurseHealth"
	gui.Adornee = root
	gui.Size = UDim2.fromOffset(120, 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, root.Size.Y * 1.6 + 2, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Parent = root
	UIKit.text({
		Parent = gui,
		Size = UDim2.new(1, 0, 0, 16),
		Text = model.Name,
		FontFace = Theme.BodyBold,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(255, 200, 220),
		TextStrokeTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local bar, setter = UIKit.bar(UDim2.new(1, 0, 0, 10), Color3.fromRGB(220, 60, 110))
	bar.Position = UDim2.fromOffset(0, 18)
	bar.Parent = gui
	local function update()
		local maxHealth = tonumber(model:GetAttribute("MaxHealth")) or 1
		local health = tonumber(model:GetAttribute("Health")) or maxHealth
		setter(health / maxHealth)
	end
	model:GetAttributeChangedSignal("Health"):Connect(function()
		update()
		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.new(1, 1, 1)
		highlight.FillTransparency = 0.4
		highlight.OutlineTransparency = 1
		highlight.Parent = model
		Debris:AddItem(highlight, 0.12)
	end)
	update()
	local telegraph: Highlight? = nil
	model:GetAttributeChangedSignal("Telegraph"):Connect(function()
		if model:GetAttribute("Telegraph") then
			local h = Instance.new("Highlight")
			h.FillColor = Color3.fromRGB(255, 40, 90)
			h.OutlineColor = Color3.fromRGB(255, 120, 160)
			h.FillTransparency = 0.6
			h.Parent = model
			telegraph = h
			tween(h, 0.5, { FillTransparency = 0.15 })
		elseif telegraph then
			telegraph:Destroy()
			telegraph = nil
		end
	end)
	model:GetAttributeChangedSignal("Dead"):Connect(function()
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 1 then
				tween(part, 0.9, { Transparency = 1 })
			end
		end
		gui.Enabled = false
	end)
end

function EffectsController.init(reg: any)
	registry = reg
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ClientFx"
	fxFolder.Parent = workspace
end

function EffectsController.start()
	map = workspace:WaitForChild("CurseboundMap")
	registry.StateController.Effect:Connect(function(name, payload)
		local handler = handlers[name]
		if handler and type(payload) == "table" then
			handler(payload)
		end
	end)
	task.spawn(collectAnimated)
	task.spawn(function()
		for _, sanctuary in map:WaitForChild("Sanctuaries"):GetChildren() do
			local units = sanctuary:WaitForChild("Units")
			units.ChildAdded:Connect(animateUnit)
			for _, unit in units:GetChildren() do
				animateUnit(unit)
			end
		end
	end)
	task.spawn(function()
		local curses = workspace:WaitForChild("Curses")
		curses.ChildAdded:Connect(trackCurse)
		for _, curse in curses:GetChildren() do
			task.spawn(trackCurse, curse)
		end
	end)

	local t = 0
	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		accumulator += dt
		if accumulator < 1 / 30 then
			return
		end
		local step = accumulator
		accumulator = 0
		circleBoost = math.max(0, circleBoost - step * 0.5)
		local boost = 1 + circleBoost * 8
		for _, spinner in spinners do
			spinner.base = spinner.base * CFrame.Angles(0, spinner.speed * step * boost, 0)
			spinner.root.CFrame = spinner.base
		end
		if circleColor and circleBoost <= 0 then
			circleColor = nil
		end
		local base = Layout.TreeBase
		for _, shard in shards do
			local a = shard.phase + t * 0.15
			local y = shard.height + math.sin(t * 0.8 + shard.phase) * 1.5
			shard.part.CFrame = CFrame.new(
				base + Vector3.new(math.sin(a) * shard.radius, y, -math.cos(a) * shard.radius)
			) * CFrame.Angles(t * 0.4 + shard.phase, t * 0.6, 0)
		end
		for i, crystal in crystals do
			crystal.root.CFrame = crystal.base
				* CFrame.new(0, math.sin(t * 1.4 + i) * 0.4, 0)
				* CFrame.Angles(0, t * 0.9, 0)
		end
	end)
end

return EffectsController
