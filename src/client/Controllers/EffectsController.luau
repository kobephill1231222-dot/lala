--!nonstrict
-- One-shot visual effects and the reusable effect primitives the other controllers use
-- (bursts, rings, slash arcs, streaks, floating text). Driven by server Effect events for
-- things everyone should see: Collect, Sell, Place, Upgrade, crate purchases and placements.
-- Everything here is cosmetic; nothing affects gameplay state.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared.Config.FarmLayout)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent.UI
local UIKit = require(UI.UIKit)
local Theme = require(UI.Theme)

local EffectsController = {}

local player = Players.LocalPlayer
local registry: any
local fxFolder: Folder

local VIOLET = Color3.fromRGB(170, 90, 255)
local GOLD = Color3.fromRGB(255, 205, 90)
local CASH = Color3.fromRGB(120, 230, 120)
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

local function nearCamera(position: Vector3, radius: number): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude < radius
end

function EffectsController.burst(
	position: Vector3,
	color: Color3,
	count: number,
	speed: number?,
	size: number?
)
	local holder = fxPart(CFrame.new(position), Vector3.one, color, nil, 1)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, size or 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.4, 0.9)
	emitter.Speed = NumberRange.new((speed or 14) * 0.5, speed or 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 4
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(count)
	Debris:AddItem(holder, 1.5)
end

-- Expanding ring. `normal` is the ring's facing (default: flat on the ground).
function EffectsController.ring(
	position: Vector3,
	color: Color3,
	fromSize: number,
	toSize: number,
	seconds: number,
	normal: Vector3?
)
	local frame = if normal
		then CFrame.lookAt(position, position + normal) * CFrame.Angles(0, math.rad(90), 0)
		else CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	local part = fxPart(frame, Vector3.new(0.25, fromSize, fromSize), color, Enum.PartType.Cylinder, 0.2)
	tween(part, seconds, { Size = Vector3.new(0.25, toSize, toSize), Transparency = 1 })
	Debris:AddItem(part, seconds + 0.1)
end

-- A crescent of thin neon blades in front of `cf` (sorcerer slash techniques).
function EffectsController.slashArc(cf: CFrame, color: Color3)
	for i = -3, 3 do
		local a = math.rad(i * 18)
		local blade = fxPart(
			cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -2.4) * CFrame.Angles(0, 0, math.rad(i * 5)),
			Vector3.new(1.8, 0.2, 0.4),
			color,
			nil,
			0.1
		)
		tween(blade, 0.3, { Transparency = 1, Size = Vector3.new(2.6, 0.08, 0.2) })
		Debris:AddItem(blade, 0.35)
	end
end

-- A quick bolt from a to b (shooting techniques).
function EffectsController.streak(a: Vector3, b: Vector3, color: Color3)
	local length = (b - a).Magnitude
	local bolt = fxPart(CFrame.lookAt((a + b) / 2, b), Vector3.new(0.5, 0.5, length), color, nil, 0.05)
	tween(bolt, 0.25, { Size = Vector3.new(0.05, 0.05, length), Transparency = 1 })
	Debris:AddItem(bolt, 0.3)
end

function EffectsController.pillar(position: Vector3, color: Color3, height: number, seconds: number)
	local part = fxPart(
		CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(height, 4, 4),
		color,
		Enum.PartType.Cylinder,
		0.2
	)
	tween(part, seconds, { Size = Vector3.new(height, 0.2, 0.2), Transparency = 1 })
	Debris:AddItem(part, seconds + 0.1)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 28
	light.Brightness = 3
	light.Parent = part
	tween(light, seconds, { Brightness = 0 })
end

-- Floating "+$123" style label at a world position.
function EffectsController.floatText(position: Vector3, text: string, color: Color3, size: number?)
	local anchor = fxPart(CFrame.new(position), Vector3.new(0.2, 0.2, 0.2), color, nil, 1)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 56)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.Adornee = anchor
	gui.Parent = anchor
	local label = UIKit.text({
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		Text = text,
		FontFace = Theme.Heavy,
		TextSize = size or 30,
		TextColor3 = color,
		TextStrokeTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	tween(anchor, 1.2, { CFrame = CFrame.new(position + Vector3.new(0, 6, 0)) })
	task.delay(0.7, function()
		tween(label, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	Debris:AddItem(anchor, 1.3)
end

-- A stream of orbs flying from `from` to the local character (Collect).
local function orbStream(from: Vector3, count: number, color: Color3)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	for i = 1, math.min(count, 14) do
		task.delay(i * 0.04, function()
			local orb = fxPart(
				CFrame.new(
					from + Vector3.new(math.random() * 4 - 2, math.random() * 2, math.random() * 4 - 2)
				),
				Vector3.new(0.9, 0.9, 0.9),
				color,
				Enum.PartType.Ball
			)
			local start = orb.CFrame.Position
			local elapsed = 0
			local connection
			connection = RunService.Heartbeat:Connect(function(dt)
				elapsed += dt
				local t = math.min(1, elapsed / 0.45)
				local target = root.Position + Vector3.new(0, 0.5, -1.5)
				local p = start:Lerp(target, t) + Vector3.new(0, 5 * 4 * t * (1 - t), 0)
				orb.CFrame = CFrame.new(p)
				if t >= 1 then
					connection:Disconnect()
					orb:Destroy()
				end
			end)
		end)
	end
end

-- A fountain of coins at a position (Sell).
local function coinFountain(position: Vector3, count: number)
	for i = 1, math.min(count, 18) do
		local coin = fxPart(
			CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0),
			Vector3.new(0.2, 1.1, 1.1),
			GOLD,
			Enum.PartType.Cylinder
		)
		coin.Material = Enum.Material.Metal
		local velocity = Vector3.new(math.random() * 16 - 8, 18 + math.random() * 10, math.random() * 16 - 8)
		local p = position
		local elapsed = 0
		local spin = math.random() * 20
		local connection
		connection = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			velocity += Vector3.new(0, -60 * dt, 0)
			p += velocity * dt
			coin.CFrame = CFrame.new(p) * CFrame.Angles(elapsed * spin, elapsed * 6, 0)
			if elapsed > 1.1 then
				connection:Disconnect()
				coin:Destroy()
			end
		end)
		local _ = i
	end
end

-- Server effects -----------------------------------------------------------------------------

local handlers: { [string]: (any) -> () } = {}

handlers.Collected = function(payload)
	local box = Layout.boxWorld(payload.farm) + Vector3.new(0, 6, 0)
	local mine = payload.userId == player.UserId
	if mine or nearCamera(box, 140) then
		EffectsController.burst(box, VIOLET, if mine then 36 else 14, 16)
		EffectsController.ring(box - Vector3.new(0, 5, 0), VIOLET, 4, 18, 0.6)
	end
	if mine then
		orbStream(box, payload.orbs, VIOLET)
		EffectsController.floatText(
			box + Vector3.new(0, 3, 0),
			"+" .. Format.commas(payload.orbs) .. " Cursed Orbs",
			Color3.fromRGB(220, 180, 255),
			30
		)
		registry.SoundController.play("collect")
	end
end

handlers.Sold = function(payload)
	local stand = Layout.SellStand + Vector3.new(0, 3, 0)
	local mine = payload.userId == player.UserId
	if mine or nearCamera(stand, 160) then
		coinFountain(stand, if mine then 18 else 8)
		EffectsController.ring(stand - Vector3.new(0, 1, 0), GOLD, 6, 30, 0.7)
		EffectsController.burst(stand, GOLD, if mine then 40 else 16, 18, 0.8)
	end
	if mine then
		EffectsController.floatText(stand + Vector3.new(0, 5, 0), "+" .. Format.cash(payload.cash), CASH, 40)
		registry.SoundController.play("sell")
		task.delay(0.1, function()
			registry.SoundController.play("coin")
		end)
		registry.UIController.pulseCash()
	end
end

handlers.Placed = function(payload)
	local position = Layout.slotWorld(payload.farm, payload.slot).Position
	if not nearCamera(position, 180) then
		return
	end
	EffectsController.pillar(position, VIOLET, 24, 0.8)
	EffectsController.ring(position + Vector3.new(0, 0.8, 0), Color3.fromRGB(220, 180, 255), 3, 16, 0.6)
	EffectsController.burst(position + Vector3.new(0, 3, 0), VIOLET, 24, 12)
	registry.SoundController.playAt("place", position)
end

handlers.Upgraded = function(payload)
	local position = Layout.slotWorld(payload.farm, payload.slot).Position
	if nearCamera(position, 180) then
		EffectsController.burst(position + Vector3.new(0, 4, 0), GOLD, 26, 12)
		EffectsController.ring(position + Vector3.new(0, 0.8, 0), GOLD, 3, 14, 0.5)
		EffectsController.floatText(position + Vector3.new(0, 9, 0), "LEVEL UP!", GOLD, 28)
	end
end

handlers.CratePlaced = function(payload)
	local position = Layout.padWorld(payload.farm, payload.pad).Position
	if nearCamera(position, 180) then
		EffectsController.ring(position + Vector3.new(0, 0.8, 0), Color3.fromRGB(240, 220, 190), 4, 16, 0.5)
		EffectsController.burst(position + Vector3.new(0, 1.5, 0), Color3.fromRGB(240, 220, 190), 18, 10, 0.7)
		registry.SoundController.playAt("cratePlace", position)
	end
end

handlers.Bought = function(payload)
	if payload.userId == player.UserId then
		return -- played locally on purchase
	end
	local position = Layout.CrateShop + Vector3.new(0, 4, 4)
	if nearCamera(position, 120) then
		EffectsController.burst(position, GOLD, 12, 10)
	end
end

handlers.CrateOpened = function(payload)
	if payload.userId == player.UserId then
		return -- the local reveal plays the full animation
	end
	registry.RevealController.playWorld(payload, false)
end

-- Local feedback ---------------------------------------------------------------------------

function EffectsController.upgradeFlash()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		EffectsController.burst(root.Position, GOLD, 30, 12)
		EffectsController.ring(root.Position - Vector3.new(0, 2.8, 0), GOLD, 3, 14, 0.6)
	end
end

-- Sparkle over the bought crate's display in the Crate Shop.
function EffectsController.boughtCrate(tier: string)
	local map = workspace:FindFirstChild("JJKFarmMap")
	local display = map and map:FindFirstChild(tier, true)
	local pedestal = display and display:FindFirstChild("Pedestal")
	local position = if pedestal and pedestal:IsA("BasePart")
		then pedestal.CFrame.Position + Vector3.new(0, 5, 0)
		else Layout.CrateShop
	EffectsController.burst(position, GOLD, 30, 14, 0.8)
	EffectsController.ring(position - Vector3.new(0, 2, 0), GOLD, 3, 12, 0.5)
end

function EffectsController.init(reg: any)
	registry = reg
end

function EffectsController.start()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "Effects"
	fxFolder.Parent = workspace
	registry.StateController.Effect:Connect(function(name: string, payload: any)
		local handler = handlers[name]
		if handler and type(payload) == "table" then
			-- Own thread per effect: some (crate reveals) animate over several frames.
			task.spawn(function()
				local ok, err = pcall(handler, payload)
				if not ok then
					warn("[JJK Farm] effect", name, err)
				end
			end)
		end
	end)
	-- Spin the Sell Stand's coin
	task.spawn(function()
		local map = workspace:WaitForChild("JJKFarmMap", 60)
		local coin = map and map:FindFirstChild("Coin", true)
		if coin and coin:IsA("BasePart") then
			local base = coin.CFrame
			local t = 0
			RunService.Heartbeat:Connect(function(dt)
				t += dt
				coin.CFrame = CFrame.new(base.Position + Vector3.new(0, math.sin(t * 1.5) * 0.8, 0))
					* CFrame.Angles(0, t * 1.2, 0)
					* (base - base.Position)
			end)
		end
	end)
end

return EffectsController
