--!strict
-- Where everything is. The server, the invisible collision map and the pixel renderer all read
-- positions from here, in studs (X right, Z down the screen: north = -Z).
--
-- The world is drawn as top-down pixel art, so everything is on an axis-aligned grid of 4-stud
-- tiles (one tile = 16 art pixels). A plaza band runs across the middle (Crate Shop on the
-- west, Sell Stand in the centre, Upgrade Shop on the east). Three farms sit above it facing
-- south and three below it facing north, each with its gate toward the plaza.
--
-- Inside a farm (local space, -Z = front, toward the plaza and the gate):
--   the collection lane runs down the middle from the back to the Orb Box near the front,
--   production slots stand in two columns either side of the lane, Crate Pads run down one
--   side, and the Collect Pad sits in front of the Orb Box.

local Layout = {}

-- Pixel scale
Layout.TileStuds = 4
Layout.PixelsPerStud = 4 -- art pixels per stud (a 16-pixel tile is 4 studs)

-- Plaza (a band between the two rows of farms)
Layout.PlazaHalfDepth = 20 -- plaza runs from z = -20 to z = 20
Layout.PlazaHalfWidth = 100
Layout.SellStand = Vector3.new(0, 0, 0)
Layout.CrateShop = Vector3.new(-40, 0, 4) -- where you stand to shop (in front of its displays)
Layout.UpgradeShop = Vector3.new(40, 0, 4)
Layout.SpawnPosition = Vector3.new(0, 1, 12)

-- Farms
Layout.FarmCount = 6
Layout.FarmWidth = 56
Layout.FarmDepth = 64
Layout.FarmColumns = { -64, 0, 64 } -- farm centre X for each column
Layout.FarmRowZ = 56 -- farm centre distance from the plaza's middle line
Layout.FloorHeight = 0 -- farms sit on the ground (the world is flat)

-- Farms 1-3 are the north row (west to east), 4-6 the south row (west to east).
function Layout.farmCFrame(index: number): CFrame
	local column = (index - 1) % 3 + 1
	local north = index <= 3
	local center = Vector3.new(Layout.FarmColumns[column], 0, if north then -Layout.FarmRowZ else Layout.FarmRowZ)
	-- LookVector (local -Z) faces the plaza: the farm's front. Axis-aligned, so pixel art
	-- never has to be drawn at an angle.
	return if north then CFrame.new(center) * CFrame.Angles(0, math.pi, 0) else CFrame.new(center)
end

-- Floor-level frame of a farm (y = top of the farm floor)
function Layout.farmFloor(index: number): CFrame
	return Layout.farmCFrame(index) * CFrame.new(0, Layout.FloorHeight, 0)
end

-- Collection lane runs from the back (+Z) toward the Orb Box at the front.
Layout.LaneStart = Vector3.new(0, 0, 28)
Layout.LaneEnd = Vector3.new(0, 0, -12)
Layout.LaneHeight = 0.4
Layout.LaneWidth = 8
Layout.BoxPosition = Vector3.new(0, 0, -16) -- 8 x 8
Layout.BoxSize = 8
Layout.CollectPoint = Vector3.new(0, 0, -22) -- the Collect Pad, where you stand to Collect
Layout.CollectPadSize = Vector3.new(8, 0, 4)
Layout.Entrance = Vector3.new(0, 0, -30) -- the gate in the front fence
Layout.GateWidth = 8

-- Production slots: odd numbers on one side (+X), even on the other, front to back.
Layout.SlotX = 12
Layout.SlotZ = { -8, 0, 8, 16, 24 }
Layout.SlotSize = 8

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

-- Crate Pads down one side (front to back)
Layout.PadX = 22
Layout.PadZ = { -20, -8, 4, 16 }
Layout.PadSize = 4

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

-- Where you appear on your farm: beside the Collect Pad, facing the Orb Box.
function Layout.homeCFrame(index: number): CFrame
	local floor = Layout.farmFloor(index)
	local p = (floor * CFrame.new(Layout.CollectPoint + Vector3.new(-8, 3, -2))).Position
	local box = (floor * CFrame.new(Layout.BoxPosition)).Position
	return CFrame.lookAt(p, Vector3.new(box.X, p.Y, box.Z))
end

-- Is a world position inside farm `index`?
function Layout.inFarm(index: number, position: Vector3): boolean
	local localPos = Layout.farmCFrame(index):PointToObjectSpace(position)
	return math.abs(localPos.X) <= Layout.FarmWidth / 2 + 2
		and math.abs(localPos.Z) <= Layout.FarmDepth / 2 + 3
end

-- World bounds (walls keep everyone inside)
Layout.WorldHalfWidth = 104
Layout.WorldHalfDepth = 100

return Layout
