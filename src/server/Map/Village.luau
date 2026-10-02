--!strict
-- Everything that ties the districts into one village: winding roads, the ring road around the
-- moat with its lanterns and signposts, villagers' houses, a teahouse, bamboo groves, trees,
-- the koi pond, the stream with its spring and bridges, an old graveyard by the forest,
-- fireflies, ambient sound emitters and the world boundary.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Config.MapLayout)
local PartKit = require(ReplicatedStorage.Shared.Visuals.PartKit)
local Prng = require(ReplicatedStorage.Shared.Util.Prng)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local TerrainPlan = require(script.Parent.TerrainPlan)

local Village = {}

local rad = math.rad
local V3 = Vector3.new
local M = Enum.Material

local function onGround(x: number, z: number): Vector3
	return V3(x, TerrainPlan.heightAt(x, z), z)
end

local function polar(angleDeg: number, radius: number): Vector3
	local a = rad(angleDeg)
	return V3(math.sin(a) * radius, 0, -math.cos(a) * radius)
end

-- Road network as control points (also used to keep props off the roads).
function Village.roads(): { { points: { Vector3 }, width: number, material: Enum.Material } }
	local roads = {}
	local ring = {}
	for i = 0, 72 do
		table.insert(ring, polar(i * 5, Layout.RingRoadRadius))
	end
	table.insert(roads, { points = ring, width = 10, material = M.Cobblestone })
	table.insert(roads, { points = { polar(90, 70), V3(Layout.CourtyardCenter.X - 34, 0, Layout.CourtyardCenter.Z) }, width = 12, material = M.Cobblestone })
	table.insert(roads, { points = { polar(270, 70), Layout.WestPlaza }, width = 11, material = M.Cobblestone })
	table.insert(roads, { points = { Layout.WestPlaza, Layout.DojoYardCenter + V3(14, 0, 4) }, width = 8, material = M.Ground })
	table.insert(roads, { points = { Layout.WestPlaza, Layout.ShopPosition + V3(18, 0, 0) }, width = 8, material = M.Ground })
	table.insert(roads, { points = { Layout.WestPlaza + V3(-10, 0, 0), Layout.PagodaPosition + V3(14, 0, 0) }, width = 7, material = M.Ground })
	table.insert(roads, { points = { polar(0, 70), Layout.ForestGate + V3(0, 0, 4) }, width = 11, material = M.Cobblestone })
	-- Winding spokes out to every sanctuary's stairs
	for i, angle in Layout.PlotAngles do
		local stairs = (Layout.plotCFrame(i) * CFrame.new(0, -Layout.PlotY, -Layout.PlotSize / 2 - 8)).Position
		local wiggle = if i % 2 == 0 then 9 else -9
		local start = polar(angle + (if i % 2 == 0 then -6 else 6), Layout.RingRoadRadius)
		local mid = polar(angle + wiggle * 0.5, 118) + polar(angle + 90, wiggle)
		table.insert(roads, { points = { start, mid, V3(stairs.X, 0, stairs.Z) }, width = 8, material = M.Ground })
	end
	return roads
end

local function nearRoad(roads: any, x: number, z: number, margin: number): boolean
	for _, road in roads do
		local pts = road.points
		for k = 1, #pts - 1 do
			local a, b = pts[k], pts[k + 1]
			local abx, abz = b.X - a.X, b.Z - a.Z
			local len2 = abx * abx + abz * abz
			local t = if len2 > 0 then math.clamp(((x - a.X) * abx + (z - a.Z) * abz) / len2, 0, 1) else 0
			local dx, dz = x - (a.X + abx * t), z - (a.Z + abz * t)
			if dx * dx + dz * dz < (road.width / 2 + margin) ^ 2 then
				return true
			end
		end
	end
	return false
end

local function freeSpot(roads: any, x: number, z: number, margin: number): boolean
	return not TerrainPlan.isReserved(x, z, margin) and not nearRoad(roads, x, z, margin) and TerrainPlan.distanceToStream(x, z) > margin + 6
end

local function buildRingDressing(parent: Instance, rng: any)
	local folder = PartKit.folder(parent, "RingRoad")
	local spokes = { 0, 90, 180, 270 }
	for _, a in Layout.PlotAngles do
		table.insert(spokes, a)
	end
	local count = 0
	for i = 0, 23 do
		local angle = i * 15 + 7.5
		local blocked = false
		for _, s in spokes do
			local d = math.abs(((angle - s + 180) % 360) - 180)
			if d < 6 then
				blocked = true
			end
		end
		if not blocked then
			count += 1
			local p = polar(angle, Layout.RingRoadRadius + 7)
			Kit.stoneLantern(folder, CFrame.lookAt(p, V3(0, 0, 0)), 0.95, count % 2 == 0)
		end
	end
	-- Signposts at the four main junctions
	local signs = {
		{ angle = 84, text = "Summoning Courtyard  >" },
		{ angle = 276, text = "<  Dojo & Talisman Shop" },
		{ angle = 6, text = "Cursed Forest  ^" },
		{ angle = 186, text = "Arrival Plaza  v" },
	}
	for _, info in signs do
		local p = polar(info.angle, Layout.RingRoadRadius + 7)
		local cf = CFrame.lookAt(p, V3(0, 0, 0)) * CFrame.Angles(0, rad(180), 0)
		Kit.part(folder, "SignPost", V3(0.5, 6, 0.5), cf * CFrame.new(0, 3, 0), Palette.DarkWood, M.Wood)
		Kit.sign(folder, cf * CFrame.new(0, 5, -0.3), 6.6, 1.2, info.text, { font = Enum.Font.GothamBold, board = Palette.AgedWood, color = Color3.fromRGB(44, 30, 26), stroke = 1, lightInfluence = 1, back = true })
	end
	local _ = rng
end

local function buildHouses(parent: Instance, roads: any, rng: any)
	local folder = PartKit.folder(parent, "Houses")
	local placed = 0
	local spots = {}
	for _ = 1, 600 do
		if placed >= 9 then
			break
		end
		local angle = rng:NextNumber(0, 360)
		local radius = rng:NextNumber(112, 190)
		local p = polar(angle, radius)
		local ok = freeSpot(roads, p.X, p.Z, 9)
		for _, other in spots do
			if (other - p).Magnitude < 30 then
				ok = false
			end
		end
		if ok and math.abs(TerrainPlan.heightAt(p.X, p.Z)) < 0.5 then
			placed += 1
			table.insert(spots, p)
			local cf = CFrame.lookAt(p, V3(0, 0, 0)) * CFrame.Angles(0, rad(rng:NextNumber(-20, 20)), 0)
			local w, d = rng:NextNumber(9, 12), rng:NextNumber(7, 9)
			local house = Kit.building(folder, cf, w, d, 5.5, {
				name = "House",
				open = { front = rng:NextNumber() < 0.3 },
				plinth = 0.8,
				roofHeight = d * 0.5,
				overhang = 1.8,
				hip = rng:NextNumber() < 0.4,
			})
			-- Little stories: lantern by the door, barrels, a laundry line or a bench
			Kit.paperLantern(house, cf * CFrame.new(w / 2 - 1, 7.4, -d / 2 - 1.6), 0.9, nil, placed % 2 == 0)
			local roll = rng:NextNumber()
			if roll < 0.35 then
				for k = 0, 1 do
					Kit.cylinder(house, "Barrel", 1.6, 2, cf * CFrame.new(-w / 2 - 1.6, 1, -d / 2 + 1 + k * 1.9), Palette.Wood, M.WoodPlanks)
				end
			elseif roll < 0.7 then
				local a = (cf * CFrame.new(-w / 2 - 2, 5, -d / 2 - 3)).Position
				local b = (cf * CFrame.new(-w / 2 - 2, 5, d / 2)).Position
				for _, q in { a, b } do
					Kit.part(house, "Pole", V3(0.4, 5, 0.4), CFrame.new(q - V3(0, 2.5, 0)), Palette.DarkWood, M.Wood)
				end
				PartKit.cylinderBetween(house, a, b, 0.1, { Name = "Line", Color = Palette.Rope, Material = M.Fabric, CanCollide = false, CanQuery = false })
				for k = 1, 3 do
					local q = a:Lerp(b, k / 4)
					Kit.deco(house, "Cloth", V3(0.1, 1.8, 1.6), CFrame.lookAt(q - V3(0, 1, 0), q - V3(0, 1, 0) + (b - a):Cross(V3(0, 1, 0))), (if k % 2 == 0 then Palette.Noren else Palette.Paper), M.Fabric)
				end
			else
				local bench = cf * CFrame.new(0, 0, -d / 2 - 2.6)
				Kit.part(house, "Bench", V3(5, 0.4, 1.4), bench * CFrame.new(0, 1.5, 0), Palette.Wood, M.WoodPlanks)
				for _, x in { -2, 2 } do
					Kit.part(house, "BenchLeg", V3(0.4, 1.3, 1.2), bench * CFrame.new(x, 0.65, 0), Palette.DarkWood, M.Wood)
				end
			end
		end
	end
	-- Teahouse with a red parasol near the plaza
	local tea = CFrame.lookAt(V3(36, 0, 150), V3(0, 0, 150))
	Kit.building(folder, tea, 12, 9, 6, { name = "Teahouse", open = { front = true }, plinth = 0.8, roofHeight = 4.2, overhang = 2.2 })
	Kit.sign(folder, tea * CFrame.new(0, 8.2, -6.7), 5, 1.5, "TEA", { font = Enum.Font.Sarpanch, board = Palette.Black, color = Palette.LanternPaper })
	local parasol = tea * CFrame.new(-2, 0, -10)
	Kit.part(folder, "ParasolPole", V3(0.3, 7, 0.3), parasol * CFrame.new(0, 3.5, 0), Palette.AgedWood, M.Wood)
	Kit.cylinder(folder, "Parasol", 8, 0.3, parasol * CFrame.new(0, 7, 0), Color3.fromRGB(150, 40, 40), M.Fabric, { CanCollide = false })
	Kit.part(folder, "TeaBench", V3(6, 0.5, 2), parasol * CFrame.new(0, 1.4, 1.5), Color3.fromRGB(130, 36, 36), M.Fabric)
end

local function buildNature(parent: Instance, roads: any, rng: any)
	local folder = PartKit.folder(parent, "Nature")
	-- Bamboo groves in the band between sanctuaries and the hills
	local groves = 0
	for _ = 1, 500 do
		if groves >= 20 then
			break
		end
		local angle = rng:NextNumber(0, 360)
		local radius = rng:NextNumber(232, 292)
		local p = polar(angle, radius)
		if freeSpot(roads, p.X, p.Z, 9) then
			groves += 1
			Kit.bamboo(folder, onGround(p.X, p.Z), rng, rng:NextInteger(12, 18), rng:NextNumber(6, 9), 20, 32)
		end
	end
	-- Bamboo behind the arrival plaza frames the first view
	Kit.bamboo(folder, V3(-22, 0, 206), rng, 16, 8, 22, 30)
	Kit.bamboo(folder, V3(24, 0, 208), rng, 16, 8, 22, 30)
	-- Pines and maples through the village
	local trees = 0
	for _ = 1, 600 do
		if trees >= 26 then
			break
		end
		local angle = rng:NextNumber(0, 360)
		local radius = rng:NextNumber(88, 250)
		local p = polar(angle, radius)
		if freeSpot(roads, p.X, p.Z, 5) then
			trees += 1
			local g = onGround(p.X, p.Z)
			if rng:NextNumber() < 0.6 then
				Kit.pine(folder, g, rng:NextNumber(0.8, 1.2), rng)
			else
				Kit.maple(folder, g, rng:NextNumber(0.75, 1.05), rng, if rng:NextNumber() < 0.5 then Palette.Maple else Color3.fromRGB(176, 90, 46))
			end
		end
	end
	-- Pines along the moat's outer bank
	for _, angle in { 30, 62, 118, 150, 210, 242, 300, 330 } do
		local p = polar(angle, 67.5)
		Kit.pine(folder, V3(p.X, 0, p.Z), 0.8, rng)
	end
	-- Rocks and grass tufts
	local rocks = 0
	for _ = 1, 400 do
		if rocks >= 40 then
			break
		end
		local angle = rng:NextNumber(0, 360)
		local radius = rng:NextNumber(85, 280)
		local p = polar(angle, radius)
		if freeSpot(roads, p.X, p.Z, 3) then
			rocks += 1
			Kit.rock(folder, onGround(p.X, p.Z), rng:NextNumber(2, 6), rng)
			if rng:NextNumber() < 0.5 then
				Kit.grassTufts(folder, onGround(p.X + 2, p.Z), 3, 4, rng)
			end
		end
	end
end

local function buildWater(parent: Instance, roads: any, rng: any)
	local folder = PartKit.folder(parent, "Water")
	-- Bridge where the ring road crosses the stream
	local stream = TerrainPlan.smoothPath(TerrainPlan.StreamPoints, 2)
	local crossing: Vector3? = nil
	local crossingDir = V3(1, 0, 0)
	for k = 1, #stream - 1 do
		local r0 = V3(stream[k].X, 0, stream[k].Z).Magnitude
		local r1 = V3(stream[k + 1].X, 0, stream[k + 1].Z).Magnitude
		if (r0 - Layout.RingRoadRadius) * (r1 - Layout.RingRoadRadius) <= 0 then
			crossing = stream[k]
			crossingDir = (stream[k + 1] - stream[k]).Unit
		end
	end
	if crossing then
		local across = crossingDir:Cross(V3(0, 1, 0))
		local a = crossing - across * 9 + V3(0, 0.4, 0)
		local b = crossing + across * 9 + V3(0, 0.4, 0)
		Kit.bridge(folder, a, b, 10, 1.4, { name = "StreamBridge", color = Palette.DarkWood, segments = 6, supportBottom = -4 })
	end
	-- Rocks along the banks
	for k = 4, #stream - 4, 4 do
		local p = stream[k]
		local dir = (stream[k + 1] - p).Unit
		local side = dir:Cross(V3(0, 1, 0)) * (if k % 8 == 0 then 1 else -1)
		local q = p + side * (TerrainPlan.StreamWidth / 2 + rng:NextNumber(0.5, 2))
		if not nearRoad(roads, q.X, q.Z, 2) then
			Kit.rock(folder, V3(q.X, -0.6, q.Z), rng:NextNumber(1.8, 3.6), rng, Palette.StoneDark:Lerp(Palette.Moss, rng:NextNumber(0, 0.6)))
		end
	end
	-- The spring: a mossy ledge and a small waterfall feeding the stream
	local spring = TerrainPlan.StreamPoints[1]
	local ledge = CFrame.lookAt(spring + V3(-13, 0, -7), spring)
	for k = 0, 5 do
		local off = V3(rng:NextNumber(-7, 7), rng:NextNumber(0, 4), rng:NextNumber(-3, 3))
		Kit.part(folder, "LedgeRock", V3(rng:NextNumber(6, 10), rng:NextNumber(6, 12), rng:NextNumber(5, 8)), ledge * CFrame.new(off + V3(0, 3, 2)) * CFrame.Angles(rad(rng:NextNumber(-10, 10)), rad(rng:NextNumber(0, 360)), 0), Palette.StoneDark:Lerp(Palette.Moss, k / 8), M.Slate)
	end
	local fall = Kit.deco(folder, "Waterfall", V3(4, 11, 0.6), ledge * CFrame.new(0, 4.5, -2.2), Color3.fromRGB(150, 190, 220), M.Glass, { Transparency = 0.35 })
	PartKit.particles(fall, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(210, 230, 255)),
		LightEmission = 0.3,
		Size = PartKit.sequence({ { 0, 2 }, { 1, 5 } }),
		Transparency = PartKit.sequence({ { 0, 0.7 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.5, 2.5),
		Rate = 8,
		Speed = NumberRange.new(1, 2),
		EmissionDirection = Enum.NormalId.Bottom,
	})
	fall:SetAttribute("AmbientKind", "Water")
	-- Koi pond: stepping stones, a snow-viewing lantern and koi glints
	for _, pond in TerrainPlan.Ponds do
		local c = pond.center
		for k = 0, 4 do
			local a = rad(140 + k * 22)
			Kit.part(folder, "SteppingStone", V3(2.6, 0.8, 2.2), CFrame.new(c.X + math.sin(a) * (pond.radius - 3), -1.2, c.Z - math.cos(a) * (pond.radius - 3)) * CFrame.Angles(0, a, 0), Palette.StoneLight, M.Slate)
		end
		Kit.stoneLantern(folder, CFrame.new(c.X + pond.radius + 2, 0, c.Z - 3), 0.8, true)
		for k = 0, 4 do
			local a = rad(k * 72 + 20)
			Kit.ellipsoid(folder, "Koi", V3(0.6, 0.3, 1.6), CFrame.new(c.X + math.sin(a) * 4, -1.7, c.Z + math.cos(a) * 4) * CFrame.Angles(0, a, 0), if k % 2 == 0 then Color3.fromRGB(240, 120, 60) else Color3.fromRGB(240, 236, 226), M.SmoothPlastic, { CanCollide = false, CanQuery = false, CastShadow = false })
		end
		Kit.maple(folder, V3(c.X - pond.radius - 3, 0, c.Z + 4), 0.8, rng, Palette.Maple)
	end
	-- Fireflies over the water
	local fireflyPoints = { polar(30, 53), polar(150, 53), polar(240, 53), polar(330, 53), stream[math.floor(#stream / 2)], spring }
	for _, pond in TerrainPlan.Ponds do
		table.insert(fireflyPoints, pond.center)
	end
	for _, p in fireflyPoints do
		local emitter = Kit.deco(folder, "Fireflies", V3(18, 4, 18), CFrame.new(V3(p.X, 3, p.Z)), Palette.Lantern, M.SmoothPlastic, { Transparency = 1 })
		emitter:SetAttribute("AmbientKind", "Water")
		PartKit.particles(emitter, {
			Color = ColorSequence.new(Color3.fromRGB(220, 255, 140)),
			Size = PartKit.sequence({ { 0, 0 }, { 0.2, 0.22 }, { 0.8, 0.22 }, { 1, 0 } }),
			Lifetime = NumberRange.new(4, 7),
			Rate = 3,
			Speed = NumberRange.new(0.3, 1),
			SpreadAngle = Vector2.new(180, 180),
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			Acceleration = V3(0, 0.1, 0),
		})
	end
end

local function buildGraveyard(parent: Instance, rng: any)
	local folder = PartKit.folder(parent, "OldGraves")
	local c = V3(-112, 0, -98)
	for k = 0, 9 do
		local p = c + V3((k % 5) * 3.4 - 6.8, 0, math.floor(k / 5) * 4.5 - 2)
		local h = rng:NextNumber(2.2, 3.6)
		Kit.part(folder, "Gravestone", V3(1.2, h, 1.2), CFrame.new(p + V3(0, h / 2, 0)) * CFrame.Angles(0, rad(rng:NextNumber(-8, 8)), rad(rng:NextNumber(-6, 6))), Palette.StoneDark:Lerp(Palette.Moss, rng:NextNumber(0, 0.6)), M.Slate)
		if k % 3 == 0 then
			Kit.deco(folder, "Sotoba", V3(0.5, 4.6, 0.1), CFrame.new(p + V3(0.9, 2.3, 0.6)) * CFrame.Angles(0, 0, rad(rng:NextNumber(-10, 10))), Palette.AgedWood, M.Wood)
		end
	end
	Kit.stoneLantern(folder, CFrame.new(c + V3(10, 0, 0)), 0.8, false)
	Kit.lilies(folder, c + V3(0, 0, 6), 4, 8, rng)
	Kit.jizo(folder, CFrame.lookAt(c + V3(-10, 0, 2), V3(0, 0, 0)))
end

local function buildBoundary(parent: Instance)
	local folder = PartKit.folder(parent, "Boundary")
	local n = 40
	local r = 305
	for k = 0, n - 1 do
		local a = (k + 0.5) / n * math.pi * 2
		local len = 2 * math.pi * r / n + 2
		Kit.part(folder, "Edge", V3(len, 200, 2), CFrame.new(math.sin(a) * r, 80, -math.cos(a) * r) * CFrame.Angles(0, -a, 0), Palette.StoneDark, M.SmoothPlastic, { Transparency = 1, CastShadow = false })
	end
end

local function buildAmbience(parent: Instance)
	local folder = PartKit.folder(parent, "AmbientEmitters")
	local spots = {
		{ kind = "Shrine", p = Layout.TreeBase + V3(0, 10, 0) },
		{ kind = "Forest", p = Layout.ForestZoneCenter + V3(0, 6, 0) },
		{ kind = "Water", p = polar(300, 60) },
		{ kind = "Water", p = polar(120, 60) },
		{ kind = "Courtyard", p = Layout.CourtyardCenter + V3(0, 4, 0) },
		{ kind = "Village", p = Layout.WestPlaza + V3(0, 4, 0) },
	}
	for _, info in spots do
		local emitter = Kit.deco(folder, info.kind, V3(1, 1, 1), CFrame.new(info.p), Palette.Violet, M.SmoothPlastic, { Transparency = 1 })
		emitter:SetAttribute("AmbientKind", info.kind)
	end
end

function Village.build(map: Instance)
	local rng = Prng.new(2024)
	local folder = PartKit.folder(map, "Village")
	local roads = Village.roads()
	buildRingDressing(folder, rng)
	buildHouses(folder, roads, rng)
	buildNature(folder, roads, rng)
	buildWater(folder, roads, rng)
	buildGraveyard(folder, rng)
	buildBoundary(folder)
	buildAmbience(folder)
end

return Village
