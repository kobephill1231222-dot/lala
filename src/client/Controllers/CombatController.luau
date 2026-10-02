--!nonstrict
-- Techniques in the Cursed Forest (and on the Dojo dummies). Shows an ability bar inside
-- combat zones, reads keyboard/mouse/touch/gamepad input, aims (mouse direction, or the
-- nearest curse on touch), plays local effects instantly and lets the server decide hits.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Abilities = require(Shared.Config.Abilities)
local Layout = require(Shared.Config.MapLayout)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent.UI
local UIKit = require(UI.UIKit)
local Theme = require(UI.Theme)

local CombatController = {}

local player = Players.LocalPlayer
local new = UIKit.new
local registry: any
local barFrame: Frame
local barScale: UIScale
local zoneLabel: TextLabel
local slots: { [string]: { button: TextButton, cooldown: Frame, label: TextLabel } } = {}
local readyAt: { [string]: number } = {}
local inZone: string? = nil

local KEYS = {
	[Enum.KeyCode.One] = "strike",
	[Enum.KeyCode.Two] = "lance",
	[Enum.KeyCode.Three] = "burst",
	[Enum.KeyCode.ButtonX] = "strike",
	[Enum.KeyCode.ButtonY] = "lance",
	[Enum.KeyCode.ButtonR2] = "burst",
}

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function nearestCurse(origin: Vector3, range: number): Vector3?
	local curses = workspace:FindFirstChild("Curses")
	if not curses then
		return nil
	end
	local best, bestDist = nil, range
	for _, model in curses:GetChildren() do
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and not model:GetAttribute("Dead") then
			local d = (root.Position - origin).Magnitude
			if d < bestDist then
				best, bestDist = root.Position, d
			end
		end
	end
	return best
end

local function aimDirection(root: BasePart, range: number): Vector3
	local origin = root.Position
	local target = nearestCurse(origin, range + 6)
	if UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
		local mouse = player:GetMouse()
		local hit = mouse.Hit.Position
		local dir = Vector3.new(hit.X - origin.X, 0, hit.Z - origin.Z)
		if dir.Magnitude > 1 then
			return dir.Unit
		end
	end
	if target then
		local dir = Vector3.new(target.X - origin.X, 0, target.Z - origin.Z)
		if dir.Magnitude > 0.5 then
			return dir.Unit
		end
	end
	local look = root.CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

function CombatController.use(abilityId: string)
	if not inZone then
		return
	end
	local ability = Abilities.ById[abilityId]
	local root = rootPart()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not ability or not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	if now < (readyAt[abilityId] or 0) then
		return
	end
	readyAt[abilityId] = now + ability.cooldown
	local direction = aimDirection(root, ability.range)
	-- Turn the character to face the technique
	root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
	registry.EffectsController.abilityVfx(abilityId, root.Position, direction)
	registry.Remotes.Ability:FireServer(abilityId, direction)
end

local function buildBar()
	barFrame = new("Frame", {
		Name = "AbilityBar",
		Parent = registry.UIController.getGui(),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(360, 130),
		BackgroundTransparency = 1,
		Visible = false,
	})
	barScale = new("UIScale", { Parent = barFrame })
	zoneLabel = UIKit.text({
		Parent = barFrame,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 22),
		Text = "",
		FontFace = Theme.BodyBold,
		TextSize = 15,
		TextColor3 = Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
	})
	local row = new("Frame", {
		Parent = barFrame,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 100),
		BackgroundTransparency = 1,
		UIKit.list(Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Center),
	})
	for _, ability in Abilities.List do
		local size = if ability.id == "strike" then 100 else 86
		local button = new("TextButton", {
			Parent = row,
			Name = ability.id,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = ability.order,
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.1,
			UIKit.round(),
			UIKit.stroke(ability.color, 3, 0.05),
		})
		new("Frame", {
			Parent = button,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.42),
			Size = UDim2.fromScale(0.3, 0.3),
			Rotation = 45,
			BackgroundColor3 = ability.color,
			UIKit.corner(4),
		})
		local label = UIKit.text({
			Parent = button,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Size = UDim2.new(1, -8, 0, 16),
			Text = ability.name,
			FontFace = Theme.BodyBold,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		UIKit.text({
			Parent = button,
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.new(1, 0, 0, 14),
			Text = ability.keyLabel,
			FontFace = Theme.Heavy,
			TextSize = 12,
			TextColor3 = Theme.TextFaint,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local cooldown = new("Frame", {
			Parent = button,
			Size = UDim2.fromScale(1, 0),
			Position = UDim2.fromScale(0, 1),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35,
			UIKit.round(),
		})
		button.Activated:Connect(function()
			CombatController.use(ability.id)
		end)
		slots[ability.id] = { button = button, cooldown = cooldown, label = label }
	end
end

local function updateZone()
	local root = rootPart()
	local zone: string? = nil
	if root then
		if Layout.inForest(root.Position) then
			zone = "Forest"
		elseif Layout.inDojo(root.Position) then
			zone = "Dojo"
		end
	end
	if zone ~= inZone then
		inZone = zone
		barFrame.Visible = zone ~= nil
		if zone == "Forest" then
			registry.UIController.toast(
				"You entered the Cursed Forest. Defeat curses for energy and seals!",
				"rare",
				3
			)
		elseif zone == "Dojo" then
			registry.UIController.toast("Practice yard: try your techniques on the dummies.", "info", 2.5)
		end
	end
	if zone then
		local profile = registry.StateController.profile
		local damage = if profile then Economy.abilityDamage(profile, "strike") else 0
		zoneLabel.Text = string.format(
			"%s  -  Strike damage %s",
			if zone == "Forest" then "Cursed Forest" else "Practice Yard",
			Format.abbreviate(damage)
		)
	end
end

function CombatController.init(reg: any)
	registry = reg
	buildBar()
end

function CombatController.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not inZone then
			return
		end
		local ability = KEYS[input.KeyCode]
		if ability then
			CombatController.use(ability)
		elseif
			input.UserInputType == Enum.UserInputType.MouseButton1
			and not registry.PlacementController.isActive()
		then
			CombatController.use("strike")
		end
	end)
	local elapsed = 0
	RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		if elapsed > 0.25 then
			elapsed = 0
			updateZone()
		end
		if barFrame.Visible then
			barScale.Scale = math.clamp(
				registry.UIController.panelScale * (if registry.UIController.isTouch then 1.1 else 0.95),
				0.6,
				1.2
			)
			local now = os.clock()
			for id, slot in slots do
				local ability = Abilities.ById[id]
				local remaining = math.max(0, (readyAt[id] or 0) - now)
				slot.cooldown.Size = UDim2.fromScale(1, remaining / ability.cooldown)
			end
		end
	end)
end

return CombatController
