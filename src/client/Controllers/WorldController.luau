--!nonstrict
-- Interaction layer for the world: proximity prompts on the player's own well and spots
-- (prompts exist only on the owner's client), the courtyard altar, the shop counter and the
-- dojo, the live Spirit Well display, and fast travel with a screen fade.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.MapLayout)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent.UI
local UIKit = require(UI.UIKit)
local Theme = require(UI.Theme)
local SummonPanel = require(UI.Panels.SummonPanel)

local WorldController = {}

local player = Players.LocalPlayer
local new = UIKit.new
local registry: any
local map: Instance
local ownPlot: number? = nil
local spotPrompts: { [number]: ProximityPrompt } = {}
local spotLabels: { [number]: BillboardGui } = {}
local fade: Frame
local traveling = false

local function makePrompt(
	parent: Instance,
	action: string,
	object: string,
	hold: number?,
	distance: number?
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = hold or 0
	prompt.MaxActivationDistance = distance or 11
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = parent
	return prompt
end

-- Travel ---------------------------------------------------------------------------------

function WorldController.travel(destination: string, onArrived: (() -> ())?)
	if traveling then
		return
	end
	traveling = true
	registry.SoundController.play("travel")
	fade.Visible = true
	fade.BackgroundTransparency = 1
	UIKit.tween(fade, 0.25, { BackgroundTransparency = 0 })
	task.wait(0.27)
	local result = registry.StateController.request("Travel", { destination = destination })
	task.wait(0.2)
	UIKit.tween(fade, 0.35, { BackgroundTransparency = 1 })
	task.wait(0.36)
	fade.Visible = false
	traveling = false
	if result.ok and onArrived then
		onArrived()
	end
end

function WorldController.openSummon()
	registry.UIController.open("Summon")
end

function WorldController.distanceTo(position: Vector3): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return math.huge
	end
	return (root.Position - position).Magnitude
end

-- Own sanctuary --------------------------------------------------------------------------

local function spotLabel(spot: number, adornee: BasePart): BillboardGui
	local gui = new("BillboardGui", {
		Name = "SpotLabel" .. spot,
		Adornee = adornee,
		Size = UDim2.fromOffset(170, 52),
		StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0),
		MaxDistance = 70,
		AlwaysOnTop = false,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	new("Frame", {
		Name = "Box",
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.25,
		UIKit.corner(12),
		UIKit.stroke(Theme.Gold, 1.5, 0.2),
		UIKit.text({
			Name = "Title",
			Position = UDim2.fromOffset(0, 3),
			Size = UDim2.new(1, 0, 0.5, 0),
			Text = "",
			FontFace = Theme.BodyBold,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
		UIKit.text({
			Name = "Sub",
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0.45, 0),
			Text = "",
			TextSize = 13,
			TextColor3 = Theme.TextDim,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
	})
	return gui
end

local function updateSpot(spotModel: Model, spot: number)
	local state = spotModel:GetAttribute("State")
	local prompt = spotPrompts[spot]
	local label = spotLabels[spot]
	if not prompt or not label then
		return
	end
	local box = label:FindFirstChild("Box") :: Frame
	local title = box:FindFirstChild("Title") :: TextLabel
	local sub = box:FindFirstChild("Sub") :: TextLabel
	local stroke = box:FindFirstChildOfClass("UIStroke") :: UIStroke
	prompt.Enabled = state ~= "Locked"
	label.Enabled = state == "Next" or state == "Empty"
	if state == "Next" then
		local cost = tonumber(spotModel:GetAttribute("Cost")) or GameConfig.SpotUnlockCosts[spot] or 0
		prompt.ActionText = "Break Seal"
		prompt.ObjectText = string.format("Spot %d  -  %s energy", spot, Format.abbreviate(cost))
		prompt.HoldDuration = 0.4
		title.Text = "Sealed spot"
		sub.Text = Format.abbreviate(cost) .. " energy to unseal"
		stroke.Color = Theme.Gold
	elseif state == "Empty" then
		prompt.ActionText = "Place Ally"
		prompt.ObjectText = "Training spot " .. spot
		prompt.HoldDuration = 0
		title.Text = "Empty spot"
		sub.Text = "Place an ally here"
		stroke.Color = Theme.Violet
	elseif state == "Occupied" then
		prompt.ActionText = "Manage Ally"
		prompt.ObjectText = "Training spot " .. spot
		prompt.HoldDuration = 0
	end
end

local function buildWellDisplay(well: Instance)
	local display = well:FindFirstChild("Display") :: BasePart?
	if not display then
		return
	end
	local gui = new("BillboardGui", {
		Name = "WellDisplay",
		Adornee = display,
		Size = UDim2.fromOffset(230, 86),
		MaxDistance = 120,
		LightInfluence = 0,
		AlwaysOnTop = false,
		ResetOnSpawn = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local box = new("Frame", {
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.2,
		UIKit.corner(14),
		UIKit.stroke(Theme.Violet, 2, 0.1),
	})
	local icon = UIKit.energyIcon(32)
	icon.Position = UDim2.fromOffset(10, 8)
	icon.Parent = box
	local amount = UIKit.text({
		Name = "Amount",
		Parent = box,
		Position = UDim2.fromOffset(48, 4),
		Size = UDim2.new(1, -56, 0, 30),
		Text = "0",
		FontFace = Theme.Heavy,
		TextSize = 24,
	})
	local bar, setter = UIKit.bar(UDim2.new(1, -20, 0, 9), Theme.Violet)
	bar.Position = UDim2.fromOffset(10, 44)
	bar.Parent = box
	local sub = UIKit.text({
		Name = "Sub",
		Parent = box,
		Position = UDim2.fromOffset(10, 58),
		Size = UDim2.new(1, -20, 0, 20),
		Text = "",
		TextSize = 13,
		TextColor3 = Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	RunService.RenderStepped:Connect(function()
		if not gui.Parent then
			return
		end
		local state = registry.StateController
		local stored, cap = state.wellStored(), state.wellCapacity()
		amount.Text = Format.abbreviate(stored)
			.. "  <font size='15' color='#a99cc0'>/ "
			.. Format.abbreviate(cap)
			.. "</font>"
		setter(if cap > 0 then stored / cap else 0)
		local full = cap > 0 and stored >= cap
		sub.Text = if full
			then "FULL - walk in to collect!"
			else "+" .. Format.rate(state.rate()) .. "  -  walk in to collect"
		sub.TextColor3 = if full then Theme.Gold else Theme.TextDim
	end)
end

local function setupOwnPlot(plotIndex: number)
	if ownPlot == plotIndex then
		return
	end
	ownPlot = plotIndex
	local sanctuary = map:WaitForChild("Sanctuaries"):WaitForChild("Sanctuary" .. plotIndex)
	local well = sanctuary:WaitForChild("Well")
	local core = well:WaitForChild("Core") :: BasePart
	local wellPrompt = makePrompt(core, "Collect", "Spirit Well", 0, 14)
	wellPrompt.Triggered:Connect(function()
		registry.StateController.request("Collect")
	end)
	buildWellDisplay(well)

	local spots = sanctuary:WaitForChild("Spots")
	for spot = 1, GameConfig.SpotCount do
		local spotModel = spots:WaitForChild("Spot" .. spot) :: Model
		local anchor = spotModel:WaitForChild("Anchor") :: BasePart
		local prompt = makePrompt(anchor, "", "", 0, 9)
		spotPrompts[spot] = prompt
		spotLabels[spot] = spotLabel(spot, anchor)
		prompt.Triggered:Connect(function()
			local state = spotModel:GetAttribute("State")
			if state == "Next" then
				local result = registry.StateController.request("UnlockSpot")
				if result.ok then
					registry.SoundController.play("unlock")
					registry.UIController.toast(
						string.format("Spot %d unsealed!", result.data.spot),
						"good",
						2
					)
				end
			elseif state == "Empty" then
				registry.UIController.open("Units", { pickSpot = spot })
			elseif state == "Occupied" then
				registry.UIController.open("Units", { uid = tostring(spotModel:GetAttribute("Uid")) })
			end
		end)
		spotModel:GetAttributeChangedSignal("State"):Connect(function()
			updateSpot(spotModel, spot)
		end)
		spotModel:GetAttributeChangedSignal("Cost"):Connect(function()
			updateSpot(spotModel, spot)
		end)
		updateSpot(spotModel, spot)
	end
end

function WorldController.ownPlot(): number?
	return ownPlot
end

function WorldController.spotAnchor(spot: number): BasePart?
	if not ownPlot then
		return nil
	end
	local folder = map:FindFirstChild("Sanctuaries")
	local sanctuary = folder and folder:FindFirstChild("Sanctuary" .. ownPlot)
	local spots = sanctuary and sanctuary:FindFirstChild("Spots")
	local spotModel = spots and spots:FindFirstChild("Spot" .. spot)
	return spotModel and spotModel:FindFirstChild("Anchor") :: BasePart?
end

function WorldController.spotState(spot: number): string?
	local anchor = WorldController.spotAnchor(spot)
	local parent = anchor and anchor.Parent
	local state = parent and parent:GetAttribute("State")
	return if type(state) == "string" then state else nil
end

-- Shared landmarks -----------------------------------------------------------------------

local function setupLandmarks()
	local altar = map:WaitForChild("Courtyard"):WaitForChild("Altar"):WaitForChild("PromptAnchor")
	local altarPrompt = makePrompt(altar, "Perform Ritual", "Summoning Altar", 0, 14)
	altarPrompt.Triggered:Connect(function()
		registry.UIController.open("Summon")
	end)
	local counter = map:WaitForChild("Shop"):WaitForChild("Counter")
	local shopPrompt = makePrompt(counter, "Browse Upgrades", "Talisman Shop", 0, 12)
	shopPrompt.Triggered:Connect(function()
		registry.UIController.open("Upgrades")
	end)
	local dojo = map:WaitForChild("Dojo")
	local yard = dojo:FindFirstChild("Yard")
	if yard then
		local dojoPrompt = makePrompt(yard, "Train Allies", "Training Dojo", 0, 16)
		dojoPrompt.Triggered:Connect(function()
			registry.UIController.open("Units")
		end)
	end
end

function WorldController.init(reg: any)
	registry = reg
	fade = new("Frame", {
		Name = "TravelFade",
		Parent = registry.UIController.getGui(),
		Size = UDim2.new(1, 0, 1, 60),
		Position = UDim2.fromOffset(0, -60),
		BackgroundColor3 = Color3.fromRGB(10, 6, 16),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 40,
	})
end

function WorldController.start()
	map = workspace:WaitForChild("CurseboundMap")
	task.spawn(setupLandmarks)
	local function onState(profile: any)
		if profile and profile.plot then
			task.spawn(setupOwnPlot, profile.plot)
		end
	end
	registry.StateController.Changed:Connect(onState)
	if registry.StateController.profile then
		onState(registry.StateController.profile)
	end
	local _ = SummonPanel
	local _ = Layout
end

return WorldController
