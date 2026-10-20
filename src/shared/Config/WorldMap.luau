--!strict
-- Everything static in the world, as data: ground areas, fences, buildings, the Sell Stand,
-- trees and props, and each farm's fixed fittings. Built from FarmLayout, in world studs
-- (X right, Z down the screen).
--
-- The server builds the invisible collision map and touch pads from it (Server/Map/MapBuilder)
-- and the client draws the same list as pixel art (Client/World), so what you see is
-- always where you collide.

local Layout = require(script.Parent.FarmLayout)

local WorldMap = {}

export type Rect = { x0: number, z0: number, x1: number, z1: number }
export type Ground = { kind: string, rect: Rect, farm: number? }
export type Object = {
	kind: string, -- "fence", "crateShop", "upgradeShop", "sellStand", "display", "tree", "lantern", "bench", ...
	rect: Rect, -- footprint in world studs
	solid: boolean, -- blocks walking (the server builds an invisible wall)
	variant: string?, -- art variant, e.g. tree "pine" / "sakura", fence "h" / "v", display tier
	farm: number?,
}
export type FarmInfo = {
	index: number,
	cframe: CFrame,
	north: boolean, -- north row (its front faces south, down the screen)
	floor: Rect,
	lane: Rect,
	box: Rect,
	collect: Rect,
	gate: Vector3, -- middle of the gate gap
	slots: { Vector3 }, -- slot centres
	pads: { Vector3 }, -- crate pad centres
	laneStart: Vector3, -- back end of the lane
	laneEnd: Vector3, -- front end (at the Orb Box)
}
export type Map = {
	bounds: Rect,
	ground: { Ground },
	objects: { Object },
	farms: { FarmInfo },
	sellPad: Rect,
}

function WorldMap.rect(cx: number, cz: number, w: number, d: number): Rect
	return { x0 = cx - w / 2, z0 = cz - d / 2, x1 = cx + w / 2, z1 = cz + d / 2 }
end
local R = WorldMap.rect

-- World rectangle of a farm-local rectangle (axis-aligned because farms are).
local function farmRect(cf: CFrame, lx: number, lz: number, w: number, d: number): Rect
	local c = cf * Vector3.new(lx, 0, lz)
	return R(c.X, c.Z, w, d)
end

local function farmInfo(index: number): FarmInfo
	local cf = Layout.farmFloor(index)
	local slots, pads = {}, {}
	for slot = 1, 10 do
		slots[slot] = Layout.slotWorld(index, slot).Position
	end
	for pad = 1, 4 do
		pads[pad] = Layout.padWorld(index, pad).Position
	end
	local laneLen = Layout.LaneStart.Z - Layout.LaneEnd.Z
	return {
		index = index,
		cframe = cf,
		north = index <= 3,
		floor = farmRect(cf, 0, 0, Layout.FarmWidth, Layout.FarmDepth),
		lane = farmRect(cf, 0, (Layout.LaneStart.Z + Layout.LaneEnd.Z) / 2, Layout.LaneWidth, laneLen),
		box = farmRect(cf, Layout.BoxPosition.X, Layout.BoxPosition.Z, Layout.BoxSize, Layout.BoxSize),
		collect = farmRect(
			cf,
			Layout.CollectPoint.X,
			Layout.CollectPoint.Z,
			Layout.CollectPadSize.X,
			Layout.CollectPadSize.Z
		),
		gate = cf * Layout.Entrance,
		slots = slots,
		pads = pads,
		laneStart = cf * Layout.LaneStart,
		laneEnd = cf * Layout.LaneEnd,
	}
end

local function fences(objects: { Object }, info: FarmInfo)
	local f = info.floor
	local t = 1 -- fence thickness (studs)
	local function add(rect: Rect, variant: string)
		table.insert(objects, { kind = "fence", rect = rect, solid = true, variant = variant, farm = info.index })
	end
	-- Back and the two sides
	local backZ = if info.north then f.z0 else f.z1 - t
	local frontZ = if info.north then f.z1 - t else f.z0
	add({ x0 = f.x0, z0 = backZ, x1 = f.x1, z1 = backZ + t }, "h")
	add({ x0 = f.x0, z0 = f.z0, x1 = f.x0 + t, z1 = f.z1 }, "v")
	add({ x0 = f.x1 - t, z0 = f.z0, x1 = f.x1, z1 = f.z1 }, "v")
	-- Front, either side of the gate
	local half = Layout.GateWidth / 2
	add({ x0 = f.x0, z0 = frontZ, x1 = info.gate.X - half, z1 = frontZ + t }, "h")
	add({ x0 = info.gate.X + half, z0 = frontZ, x1 = f.x1, z1 = frontZ + t }, "h")
end

local cache: Map? = nil

-- The world (computed once).
function WorldMap.get(): Map
	if cache then
		return cache
	end
	local hw, hd = Layout.WorldHalfWidth, Layout.WorldHalfDepth
	local ground: { Ground } = {
		{ kind = "grass", rect = { x0 = -hw, z0 = -hd, x1 = hw, z1 = hd } },
		{
			kind = "plaza",
			rect = {
				x0 = -Layout.PlazaHalfWidth,
				z0 = -Layout.PlazaHalfDepth,
				x1 = Layout.PlazaHalfWidth,
				z1 = Layout.PlazaHalfDepth,
			},
		},
	}
	local objects: { Object } = {}
	local farms: { FarmInfo } = {}
	for index = 1, Layout.FarmCount do
		local info = farmInfo(index)
		farms[index] = info
		table.insert(ground, { kind = "farmFloor", rect = info.floor, farm = index })
		-- Path from the gate to the plaza
		local g = info.gate
		local plazaEdge = if info.north then -Layout.PlazaHalfDepth else Layout.PlazaHalfDepth
		table.insert(ground, {
			kind = "road",
			rect = {
				x0 = g.X - Layout.GateWidth / 2,
				x1 = g.X + Layout.GateWidth / 2,
				z0 = math.min(g.Z, plazaEdge),
				z1 = math.max(g.Z, plazaEdge),
			},
			farm = index,
		})
		fences(objects, info)
		-- The Orb Box blocks walking; the Collect Pad and lane don't.
		table.insert(objects, { kind = "orbBox", rect = info.box, solid = true, farm = index })
		-- Stone lanterns either side of the gate, on the road side
		local lz = g.Z + (if info.north then 3 else -3)
		for _, side in { -1, 1 } do
			table.insert(objects, {
				kind = "lantern",
				rect = R(g.X + side * 7, lz, 2, 2),
				solid = true,
				farm = index,
			})
		end
	end

	-- Plaza: Sell Stand in the middle, Crate Shop west, Upgrade Shop east
	local s = Layout.SellStand
	table.insert(objects, { kind = "sellStand", rect = R(s.X, s.Z, 14, 14), solid = false })
	for _, dx in { -6, 6 } do
		for _, dz in { -6, 6 } do
			table.insert(objects, { kind = "pillar", rect = R(s.X + dx, s.Z + dz, 1.5, 1.5), solid = true })
		end
	end
	local c = Layout.CrateShop
	table.insert(objects, { kind = "crateShop", rect = R(c.X, c.Z - 17, 28, 10), solid = true })
	for i, tier in { "basic", "rare", "epic", "legendary" } do
		table.insert(objects, {
			kind = "display",
			rect = R(c.X - 15 + (i - 1) * 10, c.Z - 8, 6, 4),
			solid = true,
			variant = tier,
		})
	end
	local u = Layout.UpgradeShop
	table.insert(objects, { kind = "upgradeShop", rect = R(u.X, u.Z - 17, 28, 10), solid = true })
	table.insert(objects, { kind = "upgradeBoard", rect = R(u.X, u.Z - 8, 16, 2), solid = true })
	-- Benches and sakura in the plaza
	for _, x in { -20, 20 } do
		table.insert(objects, { kind = "bench", rect = R(x, 14, 8, 2), solid = false })
	end
	for _, x in { -84, 84 } do
		table.insert(objects, { kind = "tree", rect = R(x, 0, 3, 3), solid = true, variant = "sakura" })
	end
	-- Trees along the edges of the world (outside the farms)
	local edge = {}
	for x = -96, 96, 12 do
		table.insert(edge, { x, -hd + 5, "pine" })
		table.insert(edge, { x, hd - 5, "pine" })
	end
	for z = -84, 84, 14 do
		if math.abs(z) > Layout.PlazaHalfDepth + 2 then
			table.insert(edge, { -hw + 5, z, if z % 28 == 0 then "sakura" else "pine" })
			table.insert(edge, { hw - 5, z, if z % 28 == 0 then "maple" else "pine" })
		end
	end
	for _, e in edge do
		table.insert(objects, {
			kind = "tree",
			rect = R(e[1] :: number, e[2] :: number, 3, 3),
			solid = true,
			variant = e[3] :: string,
		})
	end

	cache = {
		bounds = { x0 = -hw, z0 = -hd, x1 = hw, z1 = hd },
		ground = ground,
		objects = objects,
		farms = farms,
		sellPad = R(s.X, s.Z, 6, 6),
	}
	return cache :: Map
end

-- Pixel helpers: world studs -> art pixels, with the world's top-left corner at (0, 0).
function WorldMap.toPixels(x: number, z: number): (number, number)
	return (x + Layout.WorldHalfWidth) * Layout.PixelsPerStud, (z + Layout.WorldHalfDepth) * Layout.PixelsPerStud
end

function WorldMap.pixelSize(): (number, number)
	return Layout.WorldHalfWidth * 2 * Layout.PixelsPerStud, Layout.WorldHalfDepth * 2 * Layout.PixelsPerStud
end

return WorldMap
