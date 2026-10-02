--!nonstrict
-- Full-screen recruitment reveal: a charging rune circle, then each unit bursts in with a
-- rarity-coloured flash, its 3D portrait and stats. Legendary+ adds a screen flash and shake.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Characters = require(Shared.Config.Characters)
local Rarities = require(Shared.Config.Rarities)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent.UI
local UIKit = require(UI.UIKit)
local Theme = require(UI.Theme)

local RevealController = {}

local new = UIKit.new
local registry: any
local playing = false

local function waitForTap(gui: Instance, minimum: number)
	local started = os.clock()
	local tapped = false
	local connection = UserInputService.InputBegan:Connect(function(input)
		if os.clock() - started < minimum then
			return
		end
		local t = input.UserInputType
		if
			t == Enum.UserInputType.MouseButton1
			or t == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.Space
			or input.KeyCode == Enum.KeyCode.ButtonA
		then
			tapped = true
		end
	end)
	while not tapped and gui.Parent do
		task.wait()
	end
	connection:Disconnect()
end

local function shake(intensity: number, duration: number)
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

local function runeCircle(parent: Instance, color: Color3): (Frame, () -> ())
	local holder = new("Frame", {
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 380),
		BackgroundTransparency = 1,
	})
	new("UIAspectRatioConstraint", { Parent = holder })
	local rings = {}
	for i, s in { 1, 0.78, 0.5 } do
		local ring = new("Frame", {
			Parent = holder,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(s, s),
			BackgroundTransparency = 1,
			UIKit.round(),
			UIKit.stroke(color, 4 - i, 0.1),
		})
		for k = 0, 7 do
			local a = math.rad(k * 45)
			new("Frame", {
				Parent = ring,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5 + math.cos(a) * 0.5, 0.5 + math.sin(a) * 0.5),
				Size = UDim2.fromOffset(12 - i * 2, 12 - i * 2),
				Rotation = 45,
				BackgroundColor3 = color,
			})
		end
		table.insert(rings, ring)
	end
	local alive = true
	task.spawn(function()
		local t = 0
		while alive and holder.Parent do
			t += task.wait()
			if not alive then
				break
			end
			for i, ring in rings do
				ring.Rotation = t * (if i % 2 == 0 then -40 else 60) * i
			end
		end
	end)
	return holder, function()
		alive = false
	end
end

local function revealCard(gui: ScreenGui, unit: any, index: number, total: number)
	local def = Characters.get(unit.id)
	local rarity = Rarities.get(unit.rarity)
	if not def or not rarity then
		return
	end
	local rank = rarity.rank
	local burst = new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = rarity.color,
		BackgroundTransparency = 0.1,
		UIKit.round(),
	})
	UIKit.tween(
		burst,
		0.6,
		{ Size = UDim2.fromOffset(900, 900), BackgroundTransparency = 1 },
		Enum.EasingStyle.Quart
	)
	task.delay(0.7, function()
		if burst.Parent then
			burst:Destroy()
		end
	end)
	if rank >= 4 then
		local flash = new("Frame", {
			Parent = gui,
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0,
			ZIndex = 20,
		})
		UIKit.tween(flash, 0.8, { BackgroundTransparency = 1 })
		task.delay(0.9, function()
			if flash.Parent then
				flash:Destroy()
			end
		end)
		shake(if rank == 5 then 1.2 else 0.7, 0.7)
	end
	registry.SoundController.play(
		if rank >= 4 then "revealLegendary" elseif rank >= 3 then "revealRare" else "reveal"
	)

	local cardScale = new("UIScale", { Scale = 0.3 })
	local card = new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromOffset(420, 520),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.05,
		cardScale,
		UIKit.corner(18),
		UIKit.stroke(rarity.color, 3, 0),
		UIKit.gradient(rarity.color:Lerp(Theme.Panel, 0.65), Theme.Panel, 90),
	})
	local uiScale = registry.UIController.panelScale
	UIKit.tween(cardScale, 0.45, { Scale = uiScale }, Enum.EasingStyle.Back)
	local viewport = UIKit.viewport(def.id, UDim2.fromOffset(300, 300), { spin = true })
	viewport.AnchorPoint = Vector2.new(0.5, 0)
	viewport.Position = UDim2.new(0.5, 0, 0, 16)
	viewport.Parent = card
	local badge = UIKit.rarityBadge(unit.rarity, 26)
	badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.Position = UDim2.new(0.5, 0, 0, 318)
	badge.Parent = card
	UIKit.text({
		Parent = card,
		Position = UDim2.fromOffset(16, 350),
		Size = UDim2.new(1, -32, 0, 40),
		Text = def.name,
		FontFace = Theme.TitleBold,
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = rarity.glow,
	})
	UIKit.text({
		Parent = card,
		Position = UDim2.fromOffset(16, 388),
		Size = UDim2.new(1, -32, 0, 22),
		Text = def.title .. "  -  " .. def.kind,
		TextColor3 = Theme.TextDim,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local unitData = { id = def.id, level = 1 }
	UIKit.text({
		Parent = card,
		Position = UDim2.fromOffset(16, 418),
		Size = UDim2.new(1, -32, 0, 26),
		Text = string.format(
			"<font color='#c89bff'>%s energy/s</font>   -   Power %d",
			Format.abbreviate(Economy.unitBaseRate(unitData)),
			Economy.unitPower(unitData)
		),
		FontFace = Theme.BodyBold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	UIKit.text({
		Parent = card,
		Position = UDim2.fromOffset(24, 448),
		Size = UDim2.new(1, -48, 0, 40),
		Text = def.description,
		TextColor3 = Theme.TextDim,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	if unit.isNew then
		new("Frame", {
			Parent = card,
			Position = UDim2.fromOffset(14, 14),
			Size = UDim2.fromOffset(64, 28),
			BackgroundColor3 = Theme.Gold,
			Rotation = -8,
			UIKit.corner(8),
			UIKit.text({
				Size = UDim2.fromScale(1, 1),
				Text = "NEW!",
				FontFace = Theme.Heavy,
				TextSize = 16,
				TextColor3 = Color3.fromRGB(40, 20, 10),
				TextXAlignment = Enum.TextXAlignment.Center,
			}),
		})
	end
	UIKit.text({
		Parent = card,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 10),
		Size = UDim2.fromOffset(400, 24),
		Text = string.format("%d / %d   -   tap to continue", index, total),
		TextColor3 = Theme.TextDim,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	waitForTap(gui, 0.6)
	UIKit.tween(cardScale, 0.18, { Scale = 0 })
	task.wait(0.18)
	card:Destroy()
end

-- Plays the reveal for a summon result ({ units = {...}, banner, ... }).
function RevealController.play(result: any, onFinished: (() -> ())?)
	if playing then
		return
	end
	playing = true
	local units = result.units or {}
	local best = 1
	for _, unit in units do
		best = math.max(best, Rarities.rank(unit.rarity))
	end
	local bestColor = Rarities.Info[Rarities.Order[best]].color
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
		BackgroundColor3 = Color3.fromRGB(8, 4, 14),
		BackgroundTransparency = 1,
	})
	UIKit.tween(backdrop, 0.4, { BackgroundTransparency = 0.15 })
	-- Charge-up: the circle hints at the best rarity in the batch.
	local circle, stop = runeCircle(gui, Theme.Violet)
	local circleScale = new("UIScale", { Parent = circle, Scale = 0.4 })
	UIKit.tween(circleScale, 1.1, { Scale = 1.15 }, Enum.EasingStyle.Quad)
	task.wait(0.6)
	for _, d in circle:GetDescendants() do
		if d:IsA("UIStroke") then
			UIKit.tween(d, 0.5, { Color = bestColor })
		elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
			UIKit.tween(d, 0.5, { BackgroundColor3 = bestColor })
		end
	end
	task.wait(0.6)
	UIKit.tween(circleScale, 0.25, { Scale = 0 })
	task.wait(0.2)
	stop()
	circle:Destroy()

	for i, unit in units do
		revealCard(gui, unit, i, #units)
	end

	-- Wrap-up: what next?
	local panelScale = registry.UIController.panelScale
	local summary = new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 190),
		BackgroundColor3 = Theme.Panel,
		new("UIScale", { Scale = panelScale }),
		UIKit.corner(16),
		UIKit.stroke(Theme.Stroke, 2, 0.2),
		UIKit.text({
			Position = UDim2.fromOffset(0, 14),
			Size = UDim2.new(1, 0, 0, 34),
			Text = "Ritual complete",
			FontFace = Theme.TitleBold,
			TextSize = 28,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
		UIKit.text({
			Position = UDim2.fromOffset(20, 50),
			Size = UDim2.new(1, -40, 0, 40),
			Text = "Place new allies on training spots in your sanctuary to earn cursed energy.",
			TextColor3 = Theme.TextDim,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
	})
	local done = false
	local function finish()
		done = true
	end
	local bestUnit = units[1]
	for _, unit in units do
		if Rarities.rank(unit.rarity) > Rarities.rank(bestUnit.rarity) then
			bestUnit = unit
		end
	end
	UIKit.button({
		parent = summary,
		text = "Place now",
		style = "gold",
		size = UDim2.fromOffset(200, 46),
		position = UDim2.new(0.5, -210, 1, -66),
		onClick = function()
			finish()
			task.defer(function()
				registry.PlacementController.begin(bestUnit.uid)
			end)
		end,
	})
	UIKit.button({
		parent = summary,
		text = "Summon more",
		style = "primary",
		size = UDim2.fromOffset(200, 46),
		position = UDim2.new(0.5, 10, 1, -66),
		onClick = function()
			finish()
			task.defer(function()
				registry.UIController.open("Summon")
			end)
		end,
	})
	while not done and gui.Parent do
		task.wait()
	end
	UIKit.tween(backdrop, 0.3, { BackgroundTransparency = 1 })
	summary:Destroy()
	task.wait(0.3)
	gui:Destroy()
	playing = false
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
