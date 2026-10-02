--!nonstrict
-- Opening a Crate. In the world, the crate on its pad shakes harder and harder, glows in the
-- colour of what's inside, then the lid bursts off in a pillar of light and the Sorcerer's
-- silhouette rises out. For the owner, a card follows with the Sorcerer's rarity, technique,
-- Orb Value and Orbs per Second, and a Place button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crates = require(Shared.Config.Crates)
local Layout = require(Shared.Config.FarmLayout)
local Rarities = require(Shared.Config.Rarities)
local Sorcerers = require(Shared.Config.Sorcerers)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Util.Format)
local CharacterModels = require(Shared.Visuals.CharacterModels)
local CrateModels = require(Shared.Visuals.CrateModels)

local UI = script.Parent.Parent.UI
local UIKit = require(UI.UIKit)
local Theme = require(UI.Theme)

local RevealController = {}

local new = UIKit.new
local registry: any
local playing = false

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", c.R * 255, c.G * 255, c.B * 255)
end

local function shakeCamera(intensity: number, duration: number)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if t > duration then
			humanoid.CameraOffset = Vector3.zero
			connection:Disconnect()
			return
		end
		local falloff = 1 - t / duration
		humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * intensity * falloff
	end)
end

local function setTransparency(model: Instance, value: number)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Root" and d.Name ~= "LidRoot" then
			d.Transparency = math.max(d.Transparency, value)
		end
	end
end

-- World animation at the pad. Returns after the lid has burst (about 1.7 s).
function RevealController.playWorld(payload: any, mine: boolean)
	local farm, pad = payload.farm, payload.pad
	if not farm or not pad then
		return
	end
	local base = Layout.padWorld(farm, pad) * CFrame.new(0, 0.6, 0)
	local camera = workspace.CurrentCamera
	if not mine and camera and (camera.CFrame.Position - base.Position).Magnitude > 180 then
		return
	end
	local tier = payload.tier or "basic"
	if not Crates.get(tier) then
		tier = "basic"
	end
	local rarity = Rarities.get(payload.rarity) or Rarities.Info.Common
	local color = rarity.color
	local effects = registry.EffectsController
	local crate = CrateModels.build(tier, base)
	crate.Name = "RevealCrate"
	crate.Parent = workspace
	local root = crate.PrimaryPart :: BasePart
	local lid = crate:FindFirstChild("Lid") :: Model
	local lidRoot = lid.PrimaryPart :: BasePart
	local lidBase = lidRoot.CFrame
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = 0
	glow.Brightness = 3
	glow.Parent = root
	local duration = 1.5 + rarity.rank * 0.12
	local started = os.clock()
	local nextThud = 0
	while true do
		local t = (os.clock() - started) / duration
		if t >= 1 then
			break
		end
		local amp = 0.04 + t * t * 0.35
		local wobble = CFrame.Angles(
			math.rad((math.random() - 0.5) * 30 * amp),
			0,
			math.rad((math.random() - 0.5) * 30 * amp)
		)
		root.CFrame = base * CFrame.new(0, math.abs(math.sin(t * 40)) * amp, 0) * wobble
		lidRoot.CFrame = root.CFrame * base:ToObjectSpace(lidBase) * CFrame.new(0, amp * 0.6, 0)
		glow.Range = 4 + t * 18
		if mine and t >= nextThud then
			nextThud = t + 0.22 - t * 0.12
			registry.SoundController.play("crateShake")
		end
		RunService.Heartbeat:Wait()
	end
	root.CFrame = base
	-- Burst: lid flies off, pillar of rarity light
	effects.pillar(base.Position, color, 40 + rarity.rank * 12, 1.3)
	effects.ring(base.Position + Vector3.new(0, 1, 0), color, 4, 26, 0.8)
	effects.burst(base.Position + Vector3.new(0, 4, 0), color, 30 + rarity.rank * 12, 22, 1)
	registry.SoundController.playAt(
		if rarity.rank >= 4 then "revealLegendary" elseif rarity.rank >= 3 then "revealRare" else "reveal",
		base.Position
	)
	if mine and rarity.rank >= 4 then
		shakeCamera(if rarity.rank == 5 then 1.2 else 0.7, 0.7)
	end
	task.spawn(function()
		local spin = math.random() < 0.5 and -1 or 1
		local t0 = os.clock()
		local start = lidRoot.CFrame
		while os.clock() - t0 < 0.9 and lidRoot.Parent do
			local t = (os.clock() - t0) / 0.9
			lidRoot.CFrame = start
				* CFrame.new(spin * t * 6, 12 * t - 9 * t * t, 0)
				* CFrame.Angles(0, 0, spin * t * 4)
			RunService.Heartbeat:Wait()
		end
		crate:Destroy()
	end)
	-- The Sorcerer's silhouette rises from the crate
	local def = Sorcerers.get(payload.id or "")
	if def then
		local ghost = CharacterModels.build(
			def.id,
			base * CFrame.new(0, 1, 0),
			{ ghost = true, scale = CharacterModels.FarmScale, companion = false }
		)
		for _, d in ghost:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "Root" then
				d.Material = Enum.Material.Neon
				d.Color = d.Color:Lerp(color, 0.5)
			end
		end
		ghost.Parent = workspace
		task.spawn(function()
			local t0 = os.clock()
			local ghostRoot = ghost.PrimaryPart :: BasePart
			while os.clock() - t0 < 1.4 and ghost.Parent do
				local t = (os.clock() - t0) / 1.4
				ghostRoot.CFrame = base * CFrame.new(0, 1 + t * 5, 0) * CFrame.Angles(0, t * math.pi * 2, 0)
				setTransparency(ghost, 0.55 + t * 0.45)
				RunService.Heartbeat:Wait()
			end
			ghost:Destroy()
		end)
	end
end

local function revealCard(gui: ScreenGui, payload: any): string
	local def = Sorcerers.get(payload.id)
	local rarity = Rarities.get(payload.rarity)
	if not def or not rarity then
		return "close"
	end
	local profile = registry.StateController.profile
	local unit = { id = def.id, level = 1 }
	local burstFrame = new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = rarity.color,
		BackgroundTransparency = 0.1,
		UIKit.round(),
	})
	UIKit.tween(
		burstFrame,
		0.6,
		{ Size = UDim2.fromOffset(900, 900), BackgroundTransparency = 1 },
		Enum.EasingStyle.Quart
	)
	task.delay(0.7, function()
		burstFrame:Destroy()
	end)

	local cardScale = new("UIScale", { Scale = 0.3 })
	local card = new("Frame", {
		Name = "RevealCard",
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 540),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.04,
		cardScale,
		UIKit.corner(18),
		UIKit.stroke(rarity.color, 3, 0),
		UIKit.gradient(rarity.color:Lerp(Theme.Panel, 0.6), Theme.Panel, 90),
	})
	UIKit.tween(cardScale, 0.45, { Scale = registry.UIController.panelScale }, Enum.EasingStyle.Back)
	local viewport = UIKit.viewport(def.id, UDim2.fromOffset(260, 250), { spin = true })
	viewport.AnchorPoint = Vector2.new(0.5, 0)
	viewport.Position = UDim2.new(0.5, 0, 0, 10)
	viewport.Parent = card
	local badge = UIKit.rarityBadge(payload.rarity, 26)
	badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.Position = UDim2.new(0.5, 0, 0, 262)
	badge.Parent = card
	UIKit.text({
		Name = "SorcererName",
		Parent = card,
		Position = UDim2.fromOffset(16, 292),
		Size = UDim2.new(1, -32, 0, 44),
		Text = def.name,
		FontFace = Theme.TitleBold,
		TextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = rarity.glow,
	})
	UIKit.text({
		Parent = card,
		Position = UDim2.fromOffset(16, 336),
		Size = UDim2.new(1, -32, 0, 22),
		Text = string.format("Technique: <font color='%s'><b>%s</b></font>", hex(def.color), def.technique),
		TextColor3 = Theme.TextDim,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	UIKit.text({
		Name = "Stats",
		Parent = card,
		Position = UDim2.fromOffset(16, 364),
		Size = UDim2.new(1, -32, 0, 70),
		Text = string.format(
			"Orb Value <b>%s</b>   -   Orbs per Second <b>%s</b>\n<font color='#78e678'>Earns %s/s on a slot</font>",
			Format.cash(Economy.orbValue(unit, profile)),
			Format.abbreviate(def.ops),
			Format.cash(Economy.income(unit, profile))
		),
		FontFace = Theme.BodyBold,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	if payload.isNew then
		new("Frame", {
			Parent = card,
			Position = UDim2.fromOffset(14, 14),
			Size = UDim2.fromOffset(70, 30),
			BackgroundColor3 = Theme.Gold,
			Rotation = -8,
			UIKit.corner(8),
			UIKit.text({
				Size = UDim2.fromScale(1, 1),
				Text = "NEW!",
				FontFace = Theme.Heavy,
				TextSize = 17,
				TextColor3 = Color3.fromRGB(40, 20, 10),
				TextXAlignment = Enum.TextXAlignment.Center,
			}),
		})
	end
	local choice: string? = nil
	UIKit.button({
		parent = card,
		text = "Place",
		style = "gold",
		size = UDim2.fromOffset(180, 50),
		position = UDim2.new(0.5, -190, 1, -70),
		textSize = 20,
		onClick = function()
			choice = "place"
		end,
	})
	UIKit.button({
		parent = card,
		text = "Later",
		style = "secondary",
		size = UDim2.fromOffset(180, 50),
		position = UDim2.new(0.5, 10, 1, -70),
		textSize = 20,
		onClick = function()
			choice = "close"
		end,
	})
	local keyConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonA then
			choice = "place"
		elseif input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			choice = "close"
		end
	end)
	while not choice and card.Parent do
		task.wait()
	end
	keyConnection:Disconnect()
	UIKit.tween(cardScale, 0.18, { Scale = 0 })
	task.wait(0.18)
	card:Destroy()
	return choice or "close"
end

-- Full reveal for the local player's own crate (result of OpenCrate).
function RevealController.play(result: any, onFinished: (() -> ())?)
	if playing then
		return
	end
	playing = true
	local farm = registry.StateController.farm()
	local payload = table.clone(result)
	payload.farm = payload.farm or farm
	RevealController.playWorld(payload, true)
	local gui = new("ScreenGui", {
		Name = "Reveal",
		DisplayOrder = 20,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local backdrop = new("Frame", {
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(10, 6, 18),
		BackgroundTransparency = 1,
	})
	UIKit.tween(backdrop, 0.3, { BackgroundTransparency = 0.35 })
	local choice = revealCard(gui, payload)
	UIKit.tween(backdrop, 0.25, { BackgroundTransparency = 1 })
	task.wait(0.25)
	gui:Destroy()
	playing = false
	if choice == "place" and payload.uid then
		task.defer(function()
			registry.PlacementController.beginSorcerer(payload.uid)
		end)
	end
	if onFinished then
		onFinished()
	end
end

function RevealController.isPlaying(): boolean
	return playing
end

function RevealController.init(reg: any)
	registry = reg
end

function RevealController.start() end

return RevealController
