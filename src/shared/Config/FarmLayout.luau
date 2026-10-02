--!strict
-- Where everything is. The map builder, server and client all read positions from here.
--
-- A compact plaza sits at the centre (Sell Stand, Crate Shop, Upgrade Shop). Six farms ring
-- it, each facing the plaza. Inside a farm (local space, -Z = front/entrance):
--   Crate Pads down the front-left, production slots in two rows either side of the
--   collection lane, and the Orb Box (collection point) at the front end of the lane.

local Layout = {}

-- Plaza
Layout.PlazaRadius = 82
Layout.SellStand = Vector3.new(0, 0, 0)
Layout.CrateShop = Vector3.new(0, 0, -60) -- north
Layout.UpgradeShop = Vector3.new(0, 0, 60) -- south
Layout.SpawnPosition = Vector3.new(0, 1, 26)

-- Farms
Layout.FarmCount = 6
Layout.FarmAngles = { 30, 90, 150, 210, 270, 330 } -- clockwise from north
Layout.FarmRadius = 158
Layout.FarmWidth = 100
Layout.FarmDepth = 120
Layout.FloorHeight = 0.6

function Layout.farmCFrame(index: number): CFrame
	local a = math.rad(Layout.FarmAngles[index])
	local center = Vector3.new(math.sin(a) * Layout.FarmRadius, 0, -math.cos(a) * Layout.FarmRadius)
	-- LookVector (local -Z) faces the plaza: the farm's front.
	return CFrame.lookAt(center, Vector3.new(0, 0, 0))
end

-- Floor-level frame of a farm (y = top of the farm floor)
function Layout.farmFloor(index: number): CFrame
	return Layout.farmCFrame(index) * CFrame.new(0, Layout.FloorHeight, 0)
end

-- Collection lane runs from the back (+Z) toward the Orb Box at the front.
Layout.LaneStart = Vector3.new(0, 0, 50)
Layout.LaneEnd = Vector3.new(0, 0, -30)
Layout.LaneHeight = 2.2 -- top of the lane trough above the floor
Layout.LaneWidth = 6
Layout.BoxPosition = Vector3.new(0, 0, -38)
Layout.CollectPoint = Vector3.new(0, 0, -50) -- where you stand to Collect
Layout.Entrance = Vector3.new(0, 0, -58)

-- Production slots: odd numbers on the right (+X), even on the left, front to back.
Layout.SlotX = 17
Layout.SlotZ = { -18, -4, 10, 24, 38 }
Layout.SlotSize = 12

function Layout.slotLocalCFrame(slot: number): CFrame
	local row = math.ceil(slot / 2)
	local side = if slot % 2 == 1 then 1 else -1
	local position = Vector3.new(side * Layout.SlotX, 0, Layout.SlotZ[row])
	-- Sorcerers face the lane
	return CFrame.lookAt(position, Vector3.new(0, 0, position.Z))
end

-- Where a slot's orbs drop into the lane
function Layout.laneEntry(slot: number): Vector3
	local row = math.ceil(slot / 2)
	return Vector3.new(0, Layout.LaneHeight + 0.8, Layout.SlotZ[row])
end

-- Crate Pads down the front-left
Layout.PadX = -38
Layout.PadZ = { -44, -30, -16, -2 }

function Layout.padLocalCFrame(pad: number): CFrame
	local position = Vector3.new(Layout.PadX, 0, Layout.PadZ[pad])
	return CFrame.lookAt(position, Vector3.new(0, 0, position.Z))
end

-- World helpers
function Layout.slotWorld(index: number, slot: number): CFrame
	return Layout.farmFloor(index) * Layout.slotLocalCFrame(slot)
end

function Layout.padWorld(index: number, pad: number): CFrame
	return Layout.farmFloor(index) * Layout.padLocalCFrame(pad)
end

function Layout.boxWorld(index: number): Vector3
	return (Layout.farmFloor(index) * CFrame.new(Layout.BoxPosition)).Position
end

function Layout.homeCFrame(index: number): CFrame
	local floor = Layout.farmFloor(index)
	local p = (floor * CFrame.new(Layout.CollectPoint + Vector3.new(-12, 3, -4))).Position
	local box = (floor * CFrame.new(Layout.BoxPosition)).Position
	return CFrame.lookAt(p, Vector3.new(box.X, p.Y, box.Z))
end

-- Is a world position inside farm `index`?
function Layout.inFarm(index: number, position: Vector3): boolean
	local localPos = Layout.farmCFrame(index):PointToObjectSpace(position)
	return math.abs(localPos.X) <= Layout.FarmWidth / 2 + 4
		and math.abs(localPos.Z) <= Layout.FarmDepth / 2 + 6
end

return Layout
