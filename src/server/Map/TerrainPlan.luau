--!strict
-- Declarative terrain: hills, mounds, the moat, the stream and painted paths are described as
-- primitive fill operations. The same plan drives Terrain generation and `heightAt`, which
-- props use to sit correctly on slopes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Config.MapLayout)
local Prng = require(ReplicatedStorage.Shared.Util.Prng)

local TerrainPlan = {}

export type Op = {
	kind: "block" | "ball" | "cyl" | "wedge",
	cframe: CFrame?,
	center: Vector3?,
	size: Vector3?,
	radius: number?,
	height: number?,
	material: Enum.Material,
	paint: boolean?,
}

local M = Enum.Material
local V3 = Vector3.new

TerrainPlan.MaterialColors = {
	[M.Grass] = Color3.fromRGB(66, 80, 50),
	[M.LeafyGrass] = Color3.fromRGB(52, 46, 60),
	[M.Ground] = Color3.fromRGB(86, 72, 60),
	[M.Cobblestone] = Color3.fromRGB(100, 96, 100),
	[M.Rock] = Color3.fromRGB(88, 86, 96),
	[M.Slate] = Color3.fromRGB(70, 68, 78),
	[M.Mud] = Color3.fromRGB(58, 46, 48),
	[M.Sand] = Color3.fromRGB(104, 96, 86),
	[M.Basalt] = Color3.fromRGB(52, 48, 58),
	[M.Pavement] = Color3.fromRGB(110, 106, 108),
}
TerrainPlan.WaterColor = Color3.fromRGB(30, 46, 62)

-- Ground surface ignoring water (used to seat props). Filled in by `create`.
local hills: { { c: Vector3, r: number } } = {}

-- The stream's centre line, from a spring in the north-west hills to the moat.
TerrainPlan.StreamPoints = {
	V3(-236, 0, -112),
	V3(-196, 0, -94),
	V3(-156, 0, -86),
	V3(-118, 0, -68),
	V3(-86, 0, -50),
	V3(-58, 0, -33),
}
TerrainPlan.StreamWidth = 9
TerrainPlan.StreamWaterY = -1.3

TerrainPlan.SpawnMound = { center = V3(0, 0, 182), radius = 26, top = Layout.SpawnY }
TerrainPlan.Ponds = {
	{ center = V3(-42, 0, 138), radius = 11 },
}

local function catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2, t3 = t * t, t * t * t
	return (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3)
		* 0.5
end

-- Smooth polyline through control points, sampled every `spacing` studs (approximately).
function TerrainPlan.smoothPath(points: { Vector3 }, spacing: number): { Vector3 }
	local out = {}
	for i = 1, #points - 1 do
		local p0 = points[math.max(1, i - 1)]
		local p1, p2 = points[i], points[i + 1]
		local p3 = points[math.min(#points, i + 2)]
		local steps = math.max(1, math.ceil((p2 - p1).Magnitude / spacing))
		for s = 0, steps - 1 do
			table.insert(out, catmull(p0, p1, p2, p3, s / steps))
		end
	end
	table.insert(out, points[#points])
	return out
end

local function distanceToSegment2D(px: number, pz: number, a: Vector3, b: Vector3): number
	local abx, abz = b.X - a.X, b.Z - a.Z
	local len2 = abx * abx + abz * abz
	local t = if len2 > 0 then math.clamp(((px - a.X) * abx + (pz - a.Z) * abz) / len2, 0, 1) else 0
	local dx, dz = px - (a.X + abx * t), pz - (a.Z + abz * t)
	return math.sqrt(dx * dx + dz * dz)
end

function TerrainPlan.distanceToStream(x: number, z: number): number
	local best = math.huge
	local pts = TerrainPlan.StreamPoints
	for i = 1, #pts - 1 do
		best = math.min(best, distanceToSegment2D(x, z, pts[i], pts[i + 1]))
	end
	return best
end

function TerrainPlan.heightAt(x: number, z: number): number
	local r = math.sqrt(x * x + z * z)
	local h = 0
	if r < Layout.TerraceRadius then
		return Layout.TerraceY
	elseif r < Layout.MoatOuterRadius then
		return -6
	end
	local mound = TerrainPlan.SpawnMound
	local dm = math.sqrt((x - mound.center.X) ^ 2 + (z - mound.center.Z) ^ 2)
	if dm < mound.radius then
		h = mound.top
	end
	for _, ball in hills do
		local dx, dz = x - ball.c.X, z - ball.c.Z
		local d2 = dx * dx + dz * dz
		if d2 < ball.r * ball.r then
			local top = ball.c.Y + math.sqrt(ball.r * ball.r - d2)
			if top > h then
				h = top
			end
		end
	end
	if TerrainPlan.distanceToStream(x, z) < TerrainPlan.StreamWidth / 2 then
		h = math.min(h, -4)
	end
	for _, pond in TerrainPlan.Ponds do
		if math.sqrt((x - pond.center.X) ^ 2 + (z - pond.center.Z) ^ 2) < pond.radius then
			h = math.min(h, -3.5)
		end
	end
	return h
end

-- Is (x, z) kept clear for gameplay spaces (plots, plaza, districts, roads)?
function TerrainPlan.isReserved(x: number, z: number, margin: number): boolean
	local r = math.sqrt(x * x + z * z)
	if r < Layout.RingRoadRadius + 10 + margin then
		return true
	end
	for i = 1, #Layout.PlotAngles do
		local c = Layout.plotCFrame(i).Position
		if math.sqrt((x - c.X) ^ 2 + (z - c.Z) ^ 2) < Layout.PlotSize * 0.75 + margin then
			return true
		end
	end
	local function near(p: Vector3, radius: number): boolean
		return math.sqrt((x - p.X) ^ 2 + (z - p.Z) ^ 2) < radius + margin
	end
	if
		near(Layout.CourtyardCenter, 42)
		or near(Layout.SpawnPosition, 34)
		or near(Layout.DojoPosition, 34)
	then
		return true
	end
	if near(Layout.ShopPosition, 26) or near(Layout.WestPlaza, 22) or near(Layout.PagodaPosition, 16) then
		return true
	end
	local fz = Layout.ForestZoneCenter
	local fs = Layout.ForestZoneSize
	if math.abs(x - fz.X) < fs.X / 2 + margin and math.abs(z - fz.Z) < fs.Z / 2 + margin then
		return true
	end
	-- Approach from the plaza to the south bridge
	if math.abs(x) < 14 + margin and z > 40 and z < 200 then
		return true
	end
	return false
end

local function addHill(ops: { Op }, center: Vector3, radius: number, material: Enum.Material)
	table.insert(ops, { kind = "ball", center = center, radius = radius, material = material })
	table.insert(hills, { c = center, r = radius })
end

-- Builds the ordered operation list.
function TerrainPlan.create(): { Op }
	table.clear(hills)
	local ops: { Op } = {}
	local rng = Prng.new(1337)

	-- 1. Base plain, top at y = 0.
	table.insert(
		ops,
		{ kind = "block", cframe = CFrame.new(0, -10, 0), size = V3(1400, 20, 1400), material = M.Grass }
	)

	-- 2. Distant mountains: big rocky shapes for the skyline, half-lost in haze.
	for i = 0, 17 do
		local angle = math.rad(i * 20 + rng:NextNumber(-7, 7))
		local dist = rng:NextNumber(520, 640)
		local radius = rng:NextNumber(130, 200)
		local peak = rng:NextNumber(70, 150)
		local c = V3(math.sin(angle) * dist, peak - radius, -math.cos(angle) * dist)
		addHill(ops, c, radius, M.Grass)
		addHill(
			ops,
			c + V3(rng:NextNumber(-20, 20), radius * 0.35, rng:NextNumber(-20, 20)),
			radius * 0.68,
			M.Rock
		)
	end

	-- 3. Inner hills that cradle the village. Their ground footprint stays outside r = 272.
	for i = 0, 39 do
		local angle = math.rad(i * 9 + rng:NextNumber(-3, 3))
		local radius = rng:NextNumber(38, 64)
		local h = rng:NextNumber(14, 34)
		local footprint = math.sqrt(math.max(0, 2 * radius * h - h * h))
		local dist = 276 + footprint + rng:NextNumber(0, 30)
		local c = V3(math.sin(angle) * dist, h - radius, -math.cos(angle) * dist)
		addHill(ops, c, radius, if rng:NextNumber() < 0.25 then M.Ground else M.Grass)
		if rng:NextNumber() < 0.4 then
			addHill(
				ops,
				c + V3(rng:NextNumber(-12, 12), radius * 0.55, rng:NextNumber(-12, 12)),
				radius * 0.45,
				M.Rock
			)
		end
	end

	-- 4. Gentle mounds between sanctuaries for layered depth (kept off reserved ground).
	local placed = 0
	for _ = 1, 400 do
		if placed >= 22 then
			break
		end
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(150, 268)
		local x, z = math.sin(angle) * dist, -math.cos(angle) * dist
		local radius = rng:NextNumber(14, 26)
		local h = rng:NextNumber(2.5, 6)
		local footprint = math.sqrt(2 * radius * h - h * h)
		if
			not TerrainPlan.isReserved(x, z, footprint + 4)
			and TerrainPlan.distanceToStream(x, z) > footprint + 8
		then
			addHill(ops, V3(x, h - radius, z), radius, M.Grass)
			placed += 1
		end
	end

	-- 5. Spawn plaza mound (the stone plaza sits on top of it).
	local mound = TerrainPlan.SpawnMound
	table.insert(ops, {
		kind = "cyl",
		cframe = CFrame.new(mound.center.X, mound.top / 2 - 2, mound.center.Z),
		height = mound.top + 4,
		radius = mound.radius,
		material = M.Ground,
	})

	-- 6. Moat around the shrine terrace.
	table.insert(ops, {
		kind = "cyl",
		cframe = CFrame.new(0, 2, 0),
		height = 20,
		radius = Layout.MoatOuterRadius,
		material = M.Air,
	})
	table.insert(ops, {
		kind = "cyl",
		cframe = CFrame.new(0, -8, 0),
		height = 4,
		radius = Layout.MoatOuterRadius,
		material = M.Sand,
	})
	table.insert(ops, {
		kind = "cyl",
		cframe = CFrame.new(0, (-6 + Layout.WaterY) / 2, 0),
		height = Layout.WaterY + 6,
		radius = Layout.MoatOuterRadius,
		material = M.Water,
	})
	table.insert(ops, {
		kind = "cyl",
		cframe = CFrame.new(0, (Layout.TerraceY - 8) / 2, 0),
		height = Layout.TerraceY + 8,
		radius = Layout.TerraceRadius + 0.5,
		material = M.Grass,
	})

	-- 7. Stream: carve a channel, then fill it with water.
	local stream = TerrainPlan.smoothPath(TerrainPlan.StreamPoints, 3)
	for i = 1, #stream - 1 do
		local a, b = stream[i], stream[i + 1]
		local mid = (a + b) / 2
		local frame = CFrame.lookAt(V3(mid.X, 0, mid.Z), V3(b.X, 0, b.Z))
		local len = (b - a).Magnitude + 2
		table.insert(ops, {
			kind = "block",
			cframe = frame * CFrame.new(0, 2, 0),
			size = V3(TerrainPlan.StreamWidth, 12, len),
			material = M.Air,
		})
		table.insert(ops, {
			kind = "block",
			cframe = frame * CFrame.new(0, -5, 0),
			size = V3(TerrainPlan.StreamWidth + 2, 2, len),
			material = M.Mud,
		})
		table.insert(ops, {
			kind = "block",
			cframe = frame * CFrame.new(0, (TerrainPlan.StreamWaterY - 4) / 2, 0),
			size = V3(TerrainPlan.StreamWidth, TerrainPlan.StreamWaterY + 4, len),
			material = M.Water,
		})
	end
	-- Spring pool at the source
	local spring = TerrainPlan.StreamPoints[1]
	table.insert(ops, {
		kind = "cyl",
		cframe = CFrame.new(spring.X, 2, spring.Z),
		height = 12,
		radius = 11,
		material = M.Air,
	})
	table.insert(ops, {
		kind = "cyl",
		cframe = CFrame.new(spring.X, -6, spring.Z),
		height = 2,
		radius = 11,
		material = M.Mud,
	})
	table.insert(ops, {
		kind = "cyl",
		cframe = CFrame.new(spring.X, (TerrainPlan.StreamWaterY - 5) / 2, spring.Z),
		height = TerrainPlan.StreamWaterY + 5,
		radius = 11,
		material = M.Water,
	})

	-- 8. Koi pond(s) near the arrival plaza.
	for _, pond in TerrainPlan.Ponds do
		local c = pond.center
		table.insert(ops, {
			kind = "cyl",
			cframe = CFrame.new(c.X, 2, c.Z),
			height = 10,
			radius = pond.radius,
			material = M.Air,
		})
		table.insert(ops, {
			kind = "cyl",
			cframe = CFrame.new(c.X, -4.5, c.Z),
			height = 2,
			radius = pond.radius,
			material = M.Mud,
		})
		table.insert(ops, {
			kind = "cyl",
			cframe = CFrame.new(c.X, -2.2, c.Z),
			height = 2.6,
			radius = pond.radius,
			material = M.Water,
		})
	end

	-- 9. Cursed forest floor: darker ground with soft undulations.
	local fz, fs = Layout.ForestZoneCenter, Layout.ForestZoneSize
	table.insert(ops, {
		kind = "block",
		cframe = CFrame.new(fz.X, -2, fz.Z - 6),
		size = V3(fs.X + 24, 4, fs.Z + 24),
		material = M.LeafyGrass,
		paint = true,
	})
	for _ = 1, 26 do
		local x = fz.X + rng:NextNumber(-fs.X / 2, fs.X / 2)
		local z = fz.Z + rng:NextNumber(-fs.Z / 2, fs.Z / 2)
		local radius = rng:NextNumber(8, 14)
		local h = rng:NextNumber(0.8, 1.8)
		table.insert(ops, {
			kind = "ball",
			center = V3(x, h - radius, z),
			radius = radius,
			material = if rng:NextNumber() < 0.3 then M.Mud else M.LeafyGrass,
		})
		table.insert(hills, { c = V3(x, h - radius, z), r = radius })
	end

	return ops
end

-- Painted path discs (material change only; surface height is untouched).
function TerrainPlan.paintPath(ops: { Op }, points: { Vector3 }, width: number, material: Enum.Material)
	for _, p in TerrainPlan.smoothPath(points, 3) do
		local top = TerrainPlan.heightAt(p.X, p.Z)
		table.insert(ops, {
			kind = "cyl",
			cframe = CFrame.new(p.X, top - 2, p.Z),
			height = 4,
			radius = width / 2,
			material = material,
			paint = true,
		})
	end
end

-- Executes the plan against a Terrain-like object (Roblox Terrain or the offline recorder).
function TerrainPlan.apply(terrain: any, ops: { Op })
	for material, color in TerrainPlan.MaterialColors do
		terrain:SetMaterialColor(material, color)
	end
	for _, op in ops do
		if op.kind == "block" then
			terrain:FillBlock(op.cframe, op.size, op.material)
		elseif op.kind == "ball" then
			terrain:FillBall(op.center, op.radius, op.material)
		elseif op.kind == "cyl" then
			terrain:FillCylinder(op.cframe, op.height, op.radius, op.material)
		elseif op.kind == "wedge" then
			terrain:FillWedge(op.cframe, op.size, op.material)
		end
	end
end

return TerrainPlan
