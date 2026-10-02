--!strict
-- Crate models, built from primitives. A crate is two anchored assemblies so clients can
-- animate the opening: the body ("Root", PrimaryPart) and the lid (child Model "Lid" with
-- its own anchored "LidRoot"). Every tier shares the silhouette (a lacquered chest bound
-- with a paper seal) and gets richer materials as it gets rarer.

local Crates = require(script.Parent.Parent.Config.Crates)
local PartKit = require(script.Parent.PartKit)

local CrateModels = {}

local V3 = Vector3.new
local rad = math.rad
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local WOOD = Enum.Material.WoodPlanks
local PAPER = Color3.fromRGB(242, 232, 204)
local INK = Color3.fromRGB(190, 40, 52)
local GOLD = Color3.fromRGB(232, 188, 92)
local IRON = Color3.fromRGB(70, 66, 74)

-- Size multiplier, corner metal, whether the trim glows.
local TIERS: { [string]: { scale: number, corner: Color3, glow: boolean, material: Enum.Material } } = {
	starter = { scale = 1.0, corner = IRON, glow = false, material = WOOD },
	basic = { scale = 1.0, corner = IRON, glow = false, material = WOOD },
	rare = {
		scale = 1.08,
		corner = Color3.fromRGB(200, 210, 230),
		glow = true,
		material = Enum.Material.SmoothPlastic,
	},
	epic = { scale = 1.16, corner = GOLD, glow = true, material = Enum.Material.SmoothPlastic },
	legendary = { scale = 1.26, corner = GOLD, glow = true, material = Enum.Material.Marble },
}

-- Footprint (studs) at scale 1.
CrateModels.Width = 5.2
CrateModels.Height = 4.6

function CrateModels.scaleOf(tier: string): number
	local info = TIERS[tier]
	return if info then info.scale else 1
end

function CrateModels.heightOf(tier: string): number
	return CrateModels.Height * CrateModels.scaleOf(tier)
end

-- Builds the crate sitting on `baseCFrame` (bottom centre), facing its LookVector.
function CrateModels.build(tier: string, baseCFrame: CFrame, extraScale: number?): Model
	local def = Crates.get(tier)
	assert(def, "unknown crate " .. tostring(tier))
	local info = TIERS[tier] or TIERS.basic
	local s = info.scale * (extraScale or 1)
	local model = Instance.new("Model")
	model.Name = def.name

	local root = PartKit.part(model, {
		Name = "Root",
		Size = V3(1, 1, 1),
		CFrame = baseCFrame,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	model.PrimaryPart = root

	local lid = Instance.new("Model")
	lid.Name = "Lid"
	lid.Parent = model
	local bodyH = 3.4
	local lidRoot = PartKit.part(lid, {
		Name = "LidRoot",
		Size = V3(1, 1, 1),
		CFrame = baseCFrame * CFrame.new(0, bodyH * s, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	lid.PrimaryPart = lidRoot

	local function add(
		parentRoot: BasePart,
		parentModel: Instance,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		material: Enum.Material?,
		extra: { [string]: any }?
	): BasePart
		local props: { [string]: any } = {
			Size = size * s,
			CFrame = baseCFrame * CFrame.new(cf.Position * s) * cf.Rotation,
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			Anchored = false,
			CanCollide = true,
			Massless = true,
		}
		if extra then
			for k, v in extra do
				props[k] = v
			end
		end
		local part = PartKit.part(parentModel, props :: any)
		PartKit.weld(parentRoot, part)
		return part
	end
	local function body(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, extra: any?)
		return add(root, model, size, cf, color, material, extra)
	end
	local function top(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, extra: any?)
		return add(lidRoot, lid, size, cf, color, material, extra)
	end

	local W = CrateModels.Width
	local trimMaterial = if info.glow then NEON else Enum.Material.SmoothPlastic
	local trim = def.color

	-- Body
	body(V3(W, bodyH - 0.3, W), CFrame.new(0, 0.3 + (bodyH - 0.3) / 2, 0), def.body, info.material)
	body(V3(W + 0.3, 0.3, W + 0.3), CFrame.new(0, 0.15, 0), info.corner, METAL)
	-- Bands
	for _, y in { 1.1, 2.6 } do
		body(V3(W + 0.12, 0.22, W + 0.12), CFrame.new(0, y, 0), trim, trimMaterial)
	end
	-- Corner posts
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			body(
				V3(0.45, bodyH, 0.45),
				CFrame.new(x * (W / 2 - 0.05), bodyH / 2, z * (W / 2 - 0.05)),
				info.corner,
				METAL
			)
		end
	end
	-- Front emblem: a round seal with the tier's colour.
	body(
		V3(0.2, 1.3, 1.3),
		CFrame.new(0, 1.85, -W / 2 - 0.08) * CFrame.Angles(0, rad(90), 0),
		info.corner,
		METAL,
		{
			Shape = Enum.PartType.Cylinder,
		}
	)
	body(
		V3(0.22, 0.85, 0.85),
		CFrame.new(0, 1.85, -W / 2 - 0.12) * CFrame.Angles(0, rad(90), 0),
		trim,
		NEON,
		{
			Shape = Enum.PartType.Cylinder,
		}
	)

	-- Lid (local to the lid's hinge height)
	top(V3(W + 0.25, 0.7, W + 0.25), CFrame.new(0, bodyH + 0.35, 0), def.body, info.material)
	top(
		V3(W - 0.6, 0.35, W - 0.6),
		CFrame.new(0, bodyH + 0.85, 0),
		def.body:Lerp(Color3.new(0, 0, 0), 0.15),
		info.material
	)
	top(V3(W + 0.35, 0.16, W + 0.35), CFrame.new(0, bodyH + 0.05, 0), trim, trimMaterial)
	-- Paper seal wrapped over the lid and down the front
	top(V3(0.9, 0.06, W + 0.5), CFrame.new(0, bodyH + 1.04, 0), PAPER)
	top(V3(0.9, 1.3, 0.06), CFrame.new(0, bodyH + 0.4, -W / 2 - 0.2), PAPER)
	top(V3(0.18, 0.08, 1.8), CFrame.new(0, bodyH + 1.08, -0.6), INK)
	top(V3(0.5, 0.08, 0.14), CFrame.new(0, bodyH + 1.08, -0.9), INK)
	top(V3(0.5, 0.08, 0.14), CFrame.new(0, bodyH + 1.08, -0.2), INK)
	if tier == "legendary" or tier == "epic" then
		-- Small roof ridge and finials for the top tiers
		top(V3(W - 1.2, 0.5, 0.6), CFrame.new(0, bodyH + 1.3, 0), info.corner, METAL)
		for _, x in { -1, 1 } do
			top(
				V3(0.5, 0.9, 0.5),
				CFrame.new(x * (W / 2 - 0.5), bodyH + 1.4, 0) * CFrame.Angles(0, 0, rad(-x * 25)),
				info.corner,
				METAL
			)
		end
	end
	if info.glow then
		local light = Instance.new("PointLight")
		light.Color = trim
		light.Range = 10 * s
		light.Brightness = 1.4
		light.Shadows = false
		light.Parent = root
	end

	model:SetAttribute("Tier", tier)
	model:SetAttribute("Height", (bodyH + 1.1) * s)
	return model
end

return CrateModels
