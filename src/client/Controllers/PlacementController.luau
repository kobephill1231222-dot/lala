--!nonstrict
-- Placement mode: highlights the player's unlocked spots, shows a translucent preview of the
-- unit on the hovered/selected spot, and confirms with a click/tap or the on-screen button.
-- Works with mouse (hover + click), touch (tap a spot, then Confirm) and gamepad (cycle).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Characters = require(Shared.Config.Characters)
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.MapLayout)
local Rarities = require(Shared.Config.Rarities)
local CharacterModels = require(Shared.Visuals.CharacterModels)

local UI = script.Parent.Parent.UI
local UIKit = require(UI.UIKit)
local Theme = require(UI.Theme)

local PlacementController = {}

local player = Players.LocalPlayer
local new = UIKit.new
local registry: any

local active = false
local uid: string? = nil
local selectedSpot: number? = nil
local ghost: Model? = nil
local markers: { [number]: BasePart } = {}
local bar: Frame
local barTitle: TextLabel
local confirmButton: any
local connections: { RBXScriptConnection } = {}

local function clearMarkers()
	for _, marker in markers do
		marker:Destroy()
	end
	table.clear(markers)
end

local function setGhost(spot: number?)
	if spot == selectedSpot and ghost then
		return
	end
	selectedSpot = spot
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	for s, marker in markers do
		marker.Transparency = if s == spot then 0.05 else 0.45
		marker.Size = if s == spot then Vector3.new(0.3, 8.6, 8.6) else Vector3.new(0.3, 7.8, 7.8)
	end
	UIKit.setEnabled(confirmButton, spot ~= nil)
	if not spot or not uid then
		barTitle.Text = "Choose a training spot"
		return
	end
	local profile = registry.StateController.profile
	local unit = profile and profile.units[uid]
	local anchor = registry.WorldController.spotAnchor(spot)
	if not unit or not anchor then
		return
	end
	local model = CharacterModels.build(unit.id, anchor.CFrame, { ghost = true })
	local def = Characters.get(unit.id) :: any
	local rarity = Rarities.get(def.rarity) :: any
	local highlight = Instance.new("Highlight")
	highlight.FillColor = rarity.color
	highlight.OutlineColor = rarity.glow
	highlight.FillTransparency = 0.65
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	model.Parent = workspace
	ghost = model
	local occupant = profile.spots[tostring(spot)]
	if occupant and occupant ~= uid then
		local other = profile.units[occupant]
		local otherDef = other and Characters.get(other.id)
		barTitle.Text =
			string.format("Spot %d: swap with %s", spot, if otherDef then otherDef.name else "ally")
	else
		barTitle.Text = string.format("Place %s on spot %d", def.name, spot)
	end
end

function PlacementController.cancel()
	if not active then
		return
	end
	active = false
	uid = nil
	selectedSpot = nil
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	clearMarkers()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	bar.Visible = false
end

local function confirm()
	local spot = selectedSpot
	local placing = uid
	if not spot or not placing then
		return
	end
	local result = registry.StateController.request("Place", { uid = placing, spot = spot })
	if result.ok then
		registry.SoundController.play("place")
		PlacementController.cancel()
	end
end

local function spotFromScreen(position: Vector2): number?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ViewportPointToRay(position.X, position.Y)
	local params = RaycastParams.new()
	local ignore: { Instance } = {}
	if player.Character then
		table.insert(ignore, player.Character)
	end
	if ghost then
		table.insert(ignore, ghost)
	end
	params.FilterDescendantsInstances = ignore
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 400, params)
	local point = if hit then hit.Position else nil
	if not point then
		return nil
	end
	local best, bestDist = nil, 6.5
	for spot, marker in markers do
		local d = (Vector3.new(point.X, 0, point.Z) - Vector3.new(marker.Position.X, 0, marker.Position.Z)).Magnitude
		if d < bestDist then
			best, bestDist = spot, d
		end
	end
	return best
end

-- Starts placing `unitUid`. Travels home first when the player is far from their sanctuary
-- (only once: after travelling we start regardless, in case replication is still catching up).
function PlacementController.begin(unitUid: string, arrived: boolean?)
	local profile = registry.StateController.profile
	if not profile or not profile.plot or not profile.units[unitUid] then
		return
	end
	PlacementController.cancel()
	local plotCenter = Layout.plotCFrame(profile.plot).Position
	if not arrived and registry.WorldController.distanceTo(plotCenter) > 70 then
		registry.UIController.toast("Heading home to place your ally...", "info", 2)
		registry.WorldController.travel("Home", function()
			PlacementController.begin(unitUid, true)
		end)
		return
	end
	active = true
	uid = unitUid
	bar.Visible = true
	-- Markers on every unlocked spot (occupied spots can be swapped).
	for spot = 1, math.min(profile.unlockedSpots, GameConfig.SpotCount) do
		local anchor = registry.WorldController.spotAnchor(spot)
		if anchor then
			local occupied = profile.spots[tostring(spot)] ~= nil
			local marker = Instance.new("Part")
			marker.Name = "PlacementMarker"
			marker.Shape = Enum.PartType.Cylinder
			marker.Anchored = true
			marker.CanCollide = false
			marker.CanQuery = false
			marker.CanTouch = false
			marker.CastShadow = false
			marker.Material = Enum.Material.Neon
			marker.Color = if occupied then Theme.Gold else Theme.Violet
			marker.Transparency = 0.45
			marker.Size = Vector3.new(0.3, 7.8, 7.8)
			marker.CFrame = CFrame.new(anchor.Position + Vector3.new(0, 0.1, 0))
				* CFrame.Angles(0, 0, math.rad(90))
			marker.Parent = workspace
			markers[spot] = marker
		end
	end
	-- Preselect the first empty spot so touch players can confirm immediately.
	local firstEmpty = nil
	for spot = 1, profile.unlockedSpots do
		if not profile.spots[tostring(spot)] then
			firstEmpty = spot
			break
		end
	end
	setGhost(firstEmpty)

	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input, processed)
			if processed or input.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end
			local spot = spotFromScreen(Vector2.new(input.Position.X, input.Position.Y))
			if spot then
				setGhost(spot)
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				local spot = spotFromScreen(Vector2.new(input.Position.X, input.Position.Y))
				if spot then
					setGhost(spot)
					confirm()
				end
			elseif input.UserInputType == Enum.UserInputType.Touch then
				local spot = spotFromScreen(Vector2.new(input.Position.X, input.Position.Y))
				if spot then
					setGhost(spot)
				end
			elseif input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
				PlacementController.cancel()
			elseif input.KeyCode == Enum.KeyCode.ButtonR1 or input.KeyCode == Enum.KeyCode.Tab then
				local current = selectedSpot or 0
				setGhost((current % profile.unlockedSpots) + 1)
			elseif input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.Return then
				confirm()
			end
		end)
	)
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function()
			local t = os.clock()
			for spot, marker in markers do
				if spot ~= selectedSpot then
					marker.Transparency = 0.45 + math.sin(t * 4 + spot) * 0.15
				end
			end
		end)
	)
end

function PlacementController.isActive(): boolean
	return active
end

function PlacementController.init(reg: any)
	registry = reg
	bar = new("Frame", {
		Name = "PlacementBar",
		Parent = registry.UIController.getGui(),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(560, 74),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 5,
		UIKit.corner(16),
		UIKit.stroke(Theme.Violet, 2, 0.1),
		new("UIScale", { Name = "Scale" }),
	})
	barTitle = UIKit.text({
		Parent = bar,
		Position = UDim2.fromOffset(18, 6),
		Size = UDim2.new(1, -300, 0, 32),
		Text = "Choose a training spot",
		FontFace = Theme.BodyBold,
		TextSize = 18,
	})
	UIKit.text({
		Parent = bar,
		Position = UDim2.fromOffset(18, 38),
		Size = UDim2.new(1, -300, 0, 26),
		Text = "Click a glowing spot, or tap one then Confirm.",
		TextColor3 = Theme.TextDim,
		TextSize = 13,
	})
	confirmButton = UIKit.button({
		parent = bar,
		text = "Confirm",
		style = "gold",
		size = UDim2.fromOffset(130, 48),
		position = UDim2.new(1, -278, 0.5, -24),
		onClick = confirm,
	})
	UIKit.button({
		parent = bar,
		text = "Cancel",
		style = "secondary",
		size = UDim2.fromOffset(120, 48),
		position = UDim2.new(1, -136, 0.5, -24),
		onClick = PlacementController.cancel,
	})
end

function PlacementController.start()
	local scale = bar:FindFirstChild("Scale") :: UIScale
	RunService.RenderStepped:Connect(function()
		if bar.Visible then
			scale.Scale = math.clamp(registry.UIController.panelScale * 1.05, 0.6, 1.2)
		end
	end)
	player.CharacterRemoving:Connect(function()
		PlacementController.cancel()
	end)
end

return PlacementController
