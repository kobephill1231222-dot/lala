--!strict
-- Sanctuary ownership and world representation: which plot belongs to whom, the units
-- standing on training spots, seals on locked spots, and the Spirit Well's live numbers.
-- Interaction prompts are created client-side for the owner only; the server validates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Characters = require(Shared.Config.Characters)
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.MapLayout)
local Rarities = require(Shared.Config.Rarities)
local Economy = require(Shared.Rules.Economy)
local CharacterModels = require(Shared.Visuals.CharacterModels)

type SpotState = {
	index: number,
	model: Model,
	state: string,
	uid: string?,
	id: string?,
	level: number?,
	unit: Model?,
	seal: Instance?,
	ring: BasePart?,
	anchor: BasePart,
}

type Plot = {
	index: number,
	model: Model,
	owner: Player?,
	spots: { SpotState },
	unitsFolder: Folder,
	wellCore: BasePart?,
	wellAttachment: Attachment?,
}

local PlotService = {}

local services: any
local plots: { Plot } = {}

local RING_COLORS = {
	Locked = Color3.fromRGB(60, 56, 66),
	Next = Color3.fromRGB(255, 186, 96),
	Empty = Color3.fromRGB(150, 110, 230),
}

local function setRing(spot: SpotState, state: string, rarityColor: Color3?)
	local ring = spot.ring
	if not ring then
		return
	end
	if state == "Locked" then
		ring.Material = Enum.Material.Slate
		ring.Color = RING_COLORS.Locked
		ring.Transparency = 0
	elseif state == "Occupied" then
		ring.Material = Enum.Material.Neon
		ring.Color = rarityColor or RING_COLORS.Empty
		ring.Transparency = 0
	else
		ring.Material = Enum.Material.Neon
		ring.Color = RING_COLORS[state] or RING_COLORS.Empty
		ring.Transparency = 0.35
	end
end

local function setSealVisible(spot: SpotState, visible: boolean)
	if not spot.seal then
		return
	end
	spot.seal.Parent = if visible then spot.model else nil
end

local function clearUnit(spot: SpotState)
	if spot.unit then
		spot.unit:Destroy()
		spot.unit = nil
	end
	spot.uid, spot.id, spot.level = nil, nil, nil
end

local function makeUnitLabel(def: Characters.CharacterDef, level: number, parent: BasePart, height: number)
	local rarity = Rarities.get(def.rarity)
	local gui = Instance.new("BillboardGui")
	gui.Name = "UnitLabel"
	gui.Size = UDim2.fromOffset(160, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height + 1.4, 0)
	gui.MaxDistance = 55
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false

	local name = Instance.new("TextLabel")
	name.Name = "UnitName"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0.55, 0)
	name.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	name.TextScaled = true
	name.Text = def.name
	name.TextColor3 = if rarity then rarity.glow else Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.4
	name.Parent = gui

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "Level"
	levelLabel.BackgroundTransparency = 1
	levelLabel.Position = UDim2.fromScale(0, 0.55)
	levelLabel.Size = UDim2.new(1, 0, 0.45, 0)
	levelLabel.FontFace = Font.fromEnum(Enum.Font.GothamMedium)
	levelLabel.TextScaled = true
	levelLabel.Text = string.format("Lv %d  -  %s", level, def.rarity)
	levelLabel.TextColor3 = Color3.fromRGB(230, 222, 240)
	levelLabel.TextStrokeTransparency = 0.5
	levelLabel.Parent = gui

	gui.Parent = parent
end

local function attachBeam(plot: Plot, spot: SpotState, unit: Model, color: Color3)
	local root = unit.PrimaryPart
	if not root or not plot.wellAttachment then
		return
	end
	local source = Instance.new("Attachment")
	source.Name = "BeamSource"
	source.Position = Vector3.new(0, 2.6, 0)
	source.Parent = root

	local beam = Instance.new("Beam")
	beam.Name = "EnergyBeam"
	beam.Attachment0 = source
	beam.Attachment1 = plot.wellAttachment
	beam.Color = ColorSequence.new(color, Color3.fromRGB(170, 100, 255))
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85),
		NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	beam.Width0 = 0.5
	beam.Width1 = 0.25
	beam.CurveSize0 = 3
	beam.CurveSize1 = -2
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 3
	beam.TextureSpeed = 1.2
	beam.Segments = 12
	beam.Parent = root
	local _ = spot
end

local function placeUnit(plot: Plot, spot: SpotState, uid: string, unitData: any)
	local def = Characters.get(unitData.id)
	if not def then
		return
	end
	local model = CharacterModels.build(def.id, spot.anchor.CFrame, { aura = true })
	model.Name = "Unit" .. spot.index
	model:SetAttribute("Uid", uid)
	model:SetAttribute("CharacterId", def.id)
	model:SetAttribute("Level", unitData.level)
	model:SetAttribute("Spot", spot.index)
	model:SetAttribute("Plot", plot.index)
	local rarity = Rarities.get(def.rarity)
	local color = if rarity then rarity.color else Color3.new(1, 1, 1)
	if model.PrimaryPart then
		makeUnitLabel(def, unitData.level, model.PrimaryPart, CharacterModels.heightOf(def.id))
	end
	model.Parent = plot.unitsFolder
	attachBeam(plot, spot, model, color)
	spot.unit = model
	spot.uid, spot.id, spot.level = uid, unitData.id, unitData.level
end

local function applySpot(plot: Plot, spot: SpotState, state: string, uid: string?, unitData: any?)
	if state ~= "Occupied" then
		clearUnit(spot)
	end
	if state == "Occupied" and uid and unitData then
		local sameUnit = spot.uid == uid and spot.id == unitData.id
		if not sameUnit then
			clearUnit(spot)
			placeUnit(plot, spot, uid, unitData)
		elseif spot.level ~= unitData.level and spot.unit then
			spot.level = unitData.level
			spot.unit:SetAttribute("Level", unitData.level)
			local root = spot.unit.PrimaryPart
			local label = root and root:FindFirstChild("UnitLabel")
			local levelText = label and label:FindFirstChild("Level")
			if levelText and levelText:IsA("TextLabel") then
				levelText.Text = string.format("Lv %d  -  %s", unitData.level, (Characters.get(unitData.id) :: any).rarity)
			end
		end
	end
	local def = unitData and Characters.get(unitData.id)
	local rarity = def and Rarities.get(def.rarity)
	setRing(spot, state, rarity and rarity.color)
	setSealVisible(spot, state == "Locked" or state == "Next")
	spot.state = state
	spot.model:SetAttribute("State", state)
	spot.model:SetAttribute("Uid", uid)
	spot.model:SetAttribute("Cost", if state == "Next" then Economy.spotUnlockCost(spot.index) else nil)
end

local function resetPlot(plot: Plot)
	for _, spot in plot.spots do
		local state = if spot.index <= GameConfig.StartingSpots then "Empty" else "Locked"
		applySpot(plot, spot, state, nil, nil)
	end
	plot.model:SetAttribute("OwnerUserId", nil)
	plot.model:SetAttribute("OwnerName", nil)
	local sign = plot.model:FindFirstChild("Sign", true)
	local label = sign and sign:FindFirstChild("OwnerLabel", true)
	if label and label:IsA("TextLabel") then
		label.Text = "Vacant Sanctuary"
	end
	local ward = plot.model:FindFirstChild("Ward", true)
	if ward and ward:IsA("BasePart") then
		ward.Transparency = 1
	end
	local well = plot.model:FindFirstChild("Well")
	if well then
		well:SetAttribute("Stored", 0)
		well:SetAttribute("Capacity", 0)
		well:SetAttribute("Rate", 0)
		well:SetAttribute("Updated", workspace:GetServerTimeNow())
	end
end

local function onWellTouched(plot: Plot, hit: BasePart)
	local owner = plot.owner
	if not owner then
		return
	end
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character or Players:GetPlayerFromCharacter(character) ~= owner then
		return
	end
	local session = services.DataService.getSession(owner)
	if not session then
		return
	end
	local t = os.clock()
	if t - session.lastCollectTouch < 1.2 then
		return
	end
	session.lastCollectTouch = t
	services.GameService.collect(owner, "touch")
end

local function loadPlot(index: number, model: Model): Plot
	local units = model:FindFirstChild("Units") :: Folder?
	if not units then
		units = Instance.new("Folder")
		units.Name = "Units"
		units.Parent = model
	end
	local plot: Plot = {
		index = index,
		model = model,
		owner = nil,
		spots = {},
		unitsFolder = units :: Folder,
		wellCore = nil,
		wellAttachment = nil,
	}
	local well = model:WaitForChild("Well")
	local core = well:WaitForChild("Core") :: BasePart
	plot.wellCore = core
	local attachment = core:FindFirstChild("BeamTarget") :: Attachment?
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "BeamTarget"
		attachment.Parent = core
	end
	plot.wellAttachment = attachment

	local spotsFolder = model:WaitForChild("Spots")
	for i = 1, GameConfig.SpotCount do
		local spotModel = spotsFolder:WaitForChild("Spot" .. i) :: Model
		local spot: SpotState = {
			index = i,
			model = spotModel,
			state = "",
			anchor = spotModel:WaitForChild("Anchor") :: BasePart,
			ring = spotModel:FindFirstChild("Ring") :: BasePart?,
			seal = spotModel:FindFirstChild("Seal"),
		}
		table.insert(plot.spots, spot)
	end

	local sensor = well:WaitForChild("Sensor") :: BasePart
	sensor.Touched:Connect(function(hit)
		onWellTouched(plot, hit)
	end)
	resetPlot(plot)
	return plot
end

function PlotService.init(registry: any)
	services = registry
end

function PlotService.start()
	local map = workspace:WaitForChild("CurseboundMap")
	local folder = map:WaitForChild("Sanctuaries")
	for i = 1, #Layout.PlotAngles do
		plots[i] = loadPlot(i, folder:WaitForChild("Sanctuary" .. i) :: Model)
	end
end

function PlotService.assign(player: Player): number?
	for _, plot in plots do
		if plot.owner == nil then
			plot.owner = player
			plot.model:SetAttribute("OwnerUserId", player.UserId)
			plot.model:SetAttribute("OwnerName", player.DisplayName)
			local sign = plot.model:FindFirstChild("Sign", true)
			local label = sign and sign:FindFirstChild("OwnerLabel", true)
			if label and label:IsA("TextLabel") then
				label.Text = player.DisplayName .. "'s Sanctuary"
			end
			local ward = plot.model:FindFirstChild("Ward", true)
			if ward and ward:IsA("BasePart") then
				ward.Transparency = 0.2
			end
			return plot.index
		end
	end
	return nil
end

function PlotService.release(player: Player)
	for _, plot in plots do
		if plot.owner == player then
			plot.owner = nil
			resetPlot(plot)
		end
	end
end

function PlotService.getPlot(index: number): Plot?
	return plots[index]
end

-- Synchronises spot visuals with the owner's profile (only touches what changed).
function PlotService.render(player: Player)
	local session = services.DataService.getSession(player)
	if not session or not session.plot then
		return
	end
	local plot = plots[session.plot]
	local profile = session.profile
	for _, spot in plot.spots do
		local state, uid, unitData = "Locked", nil, nil
		if spot.index <= profile.unlockedSpots then
			uid = profile.spots[tostring(spot.index)]
			unitData = uid and profile.units[uid]
			state = if unitData then "Occupied" else "Empty"
		elseif spot.index == profile.unlockedSpots + 1 then
			state = "Next"
		end
		applySpot(plot, spot, state, uid, unitData)
	end
	PlotService.updateWell(player)
end

function PlotService.updateWell(player: Player)
	local session = services.DataService.getSession(player)
	if not session or not session.plot then
		return
	end
	local plot = plots[session.plot]
	local well = plot.model:FindFirstChild("Well")
	if not well then
		return
	end
	local profile = session.profile
	local rate = Economy.totalRate(profile)
	well:SetAttribute("Stored", profile.well.stored)
	well:SetAttribute("Updated", profile.well.t)
	well:SetAttribute("Rate", rate)
	well:SetAttribute("Capacity", Economy.wellCapacity(profile, rate))
end

function PlotService.wellPosition(index: number): Vector3
	return (Layout.plotFloorCFrame(index) * CFrame.new(Layout.WellOffset)).Position
end

function PlotService.homeCFrame(player: Player): CFrame?
	local session = services.DataService.getSession(player)
	if not session or not session.plot then
		return nil
	end
	return Layout.homeTravelPoint(session.plot)
end

return PlotService
