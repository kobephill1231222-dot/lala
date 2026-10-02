--!nocheck
-- Preview-only staging: puts a mid-game farm on the baked map (Sorcerers on slots, Crates
-- on pads, orbs on the lane, a half-full Orb Box) plus 5.2-stud avatar stand-ins, so the
-- preview renders show scale and what a played farm looks like. Never saved to the place.
local roblox = require("@lune/roblox")
local Enum = roblox.Enum

local Stage = {}

local function avatar(parent, PartKit, cf, shirt, carrying)
	-- Proportions of a default R15 avatar: ~5.2 studs tall.
	local function add(size, offset, color)
		PartKit.part(parent, {
			Name = "Avatar",
			Size = size,
			CFrame = cf * roblox.CFrame.new(offset),
			Color = color,
			CanCollide = false,
		})
	end
	local V3 = roblox.Vector3.new
	local skin = roblox.Color3.fromRGB(245, 205, 160)
	add(V3(0.9, 2.0, 1.0), V3(-0.5, 1.0, 0), roblox.Color3.fromRGB(40, 60, 120))
	add(V3(0.9, 2.0, 1.0), V3(0.5, 1.0, 0), roblox.Color3.fromRGB(40, 60, 120))
	add(V3(2.0, 2.0, 1.0), V3(0, 3.0, 0), shirt)
	add(V3(0.9, 2.0, 1.0), V3(-1.45, 3.0, 0), skin)
	add(V3(0.9, 2.0, 1.0), V3(1.45, 3.0, 0), skin)
	add(V3(1.2, 1.2, 1.2), V3(0, 4.6, 0), skin)
	if carrying then
		add(V3(2.2, 1.8, 2.2), V3(0, 3.0, -1.9), roblox.Color3.fromRGB(110, 78, 54))
		local glow = PartKit.part(parent, {
			Name = "Carry",
			Size = V3(1.8, 0.2, 1.8),
			CFrame = cf * roblox.CFrame.new(0, 4.0, -1.9),
			Color = roblox.Color3.fromRGB(190, 110, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		local _ = glow
	end
end

function Stage.build(sb, map)
	local Layout = sb.requirePath("ReplicatedStorage/Shared/Config/FarmLayout")
	local Sorcerers = sb.requirePath("ReplicatedStorage/Shared/Config/Sorcerers")
	local CharacterModels = sb.requirePath("ReplicatedStorage/Shared/Visuals/CharacterModels")
	local CrateModels = sb.requirePath("ReplicatedStorage/Shared/Visuals/CrateModels")
	local PartKit = sb.requirePath("ReplicatedStorage/Shared/Visuals/PartKit")
	local CF, V3 = roblox.CFrame, roblox.Vector3.new

	local stage = roblox.Instance.new("Folder")
	stage.Name = "Stage"
	local function populate(index, ids, crates, fill)
		for slot, id in ids do
			local model = CharacterModels.build(
				id,
				Layout.slotWorld(index, slot) * CF.new(0, 0.5, 0),
				{ scale = CharacterModels.FarmScale }
			)
			model.Parent = stage
		end
		for pad, tier in crates do
			local model = CrateModels.build(tier, Layout.padWorld(index, pad) * CF.new(0, 0.6, 0))
			model.Parent = stage
		end
		local floor = Layout.farmFloor(index)
		-- Orbs along the lane, in each sorcerer's technique colour
		local z = Layout.LaneEnd.Z + 2
		local i = 0
		while z < Layout.LaneStart.Z - 2 do
			i += 1
			local def = Sorcerers.get(ids[(i % #ids) + 1])
			PartKit.part(stage, {
				Name = "Orb",
				Shape = Enum.PartType.Ball,
				Size = V3(1.3, 1.3, 1.3),
				CFrame = floor * CF.new(0, Layout.LaneHeight + 0.65, z),
				Color = def.color,
				Material = Enum.Material.Neon,
				CanCollide = false,
			})
			z += 5.5
		end
		-- Box fill
		local farm = map.Farms["Farm" .. index]
		local fillPart = farm.OrbBox.Fill
		local maxH = fillPart:GetAttribute("MaxHeight")
		local baseY = fillPart:GetAttribute("BaseY")
		local h = maxH * fill
		local size = fillPart.Size
		local boxCenter = floor * CF.new(Layout.BoxPosition)
		local clone = PartKit.part(stage, {
			Name = "FillStage",
			Size = V3(size.X, h, size.Z),
			CFrame = boxCenter * CF.new(0, baseY + h / 2, 0),
			Color = fillPart.Color,
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		local _ = clone
	end
	populate(1, { "kai", "rei", "hana", "daiki", "ryo", "akane" }, { "basic", "rare", "epic" }, 0.55)
	populate(2, { "toru", "mina", "goro" }, { "starter" }, 0.25)
	populate(
		6,
		{ "shion", "yoru", "juzo", "emi", "nao", "suzu", "kai", "rei" },
		{ "legendary", "epic", "rare", "basic" },
		0.85
	)

	-- Avatar stand-ins (5.2 studs) at key spots
	local function face(pos, target)
		return CF.lookAt(pos, V3(target.X, pos.Y, target.Z))
	end
	local farm1 = Layout.farmFloor(1)
	local box1 = Layout.boxWorld(1)
	avatar(
		stage,
		PartKit,
		face((farm1 * CF.new(Layout.CollectPoint)).Position, box1),
		roblox.Color3.fromRGB(220, 60, 60),
		false
	)
	avatar(
		stage,
		PartKit,
		face((farm1 * CF.new(-30, 0.6, -30)).Position, (farm1 * CF.new(-38, 0, -30)).Position),
		roblox.Color3.fromRGB(60, 160, 90),
		false
	)
	avatar(stage, PartKit, face(V3(6, 1.9, -4), V3(0, 0, 0)), roblox.Color3.fromRGB(240, 200, 60), true)
	avatar(
		stage,
		PartKit,
		face(V3(-4, 0.4, -46), Layout.CrateShop),
		roblox.Color3.fromRGB(80, 120, 230),
		false
	)
	avatar(
		stage,
		PartKit,
		face(V3(8, 0.4, 47), Layout.UpgradeShop),
		roblox.Color3.fromRGB(200, 90, 200),
		false
	)
	avatar(
		stage,
		PartKit,
		face((Layout.farmFloor(2) * CF.new(4, 0, -60)).Position, V3(0, 0, 0)),
		roblox.Color3.fromRGB(250, 140, 40),
		true
	)
	return stage
end

return Stage
