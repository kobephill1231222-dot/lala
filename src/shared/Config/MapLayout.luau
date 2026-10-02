--!strict
-- Single source of truth for where things are in the village. The map builder places
-- geometry from these values and the server/client use them for travel, validation and
-- tutorial guidance, so they can never drift apart.
--
-- Orientation: -Z is north. The arrival plaza is south of the shrine and looks north
-- toward the spirit tree.

local Layout = {}

Layout.VillageCenter = Vector3.new(0, 0, 0)
Layout.GroundY = 0

-- Central shrine terrace and moat
Layout.TerraceY = 5
Layout.TerraceRadius = 44
Layout.MoatOuterRadius = 62
Layout.RingRoadRadius = 75
Layout.WaterY = -1.6

-- Spirit tree
Layout.TreeBase = Vector3.new(0, Layout.TerraceY, -8)
Layout.TreeHeight = 112

-- Arrival plaza (first spawn)
Layout.SpawnY = 6
Layout.SpawnPosition = Vector3.new(0, Layout.SpawnY, 176)
Layout.SpawnCFrame = CFrame.lookAt(Layout.SpawnPosition, Vector3.new(0, Layout.SpawnY, 0))

-- Summoning courtyard (east)
Layout.CourtyardCenter = Vector3.new(126, 1, -4)
Layout.CircleRadius = 15
Layout.AltarPosition = Layout.CourtyardCenter + Vector3.new(21, 0, 0)
Layout.SummonRadius = 48 -- server-side: how close a player must be to perform a ritual

-- Village west: Talisman Shop (upgrades) and Training Dojo
Layout.ShopPosition = Vector3.new(-120, 1, 34)
Layout.ShopCounter = Layout.ShopPosition + Vector3.new(8, 0, 0)
Layout.WestPlaza = Vector3.new(-92, 0, 0)
Layout.PagodaPosition = Vector3.new(-168, 0, -2)
Layout.DojoPosition = Vector3.new(-128, 1, -38)
Layout.DojoYardCenter = Vector3.new(-100, 1, -38)
Layout.DojoZoneSize = Vector3.new(30, 30, 30)

-- Cursed Forest (north)
Layout.ForestGate = Vector3.new(0, 0, -104)
Layout.ForestZoneCenter = Vector3.new(0, 0, -182)
Layout.ForestZoneSize = Vector3.new(176, 90, 148)

-- Sanctuaries ring the village. Angles are clockwise from north.
Layout.PlotSize = 72
Layout.PlotY = 2
Layout.PlotRadius = 214
Layout.PlotAngles = { 45, 115, 150, 210, 245, 315 }

function Layout.plotCFrame(index: number): CFrame
	local angle = math.rad(Layout.PlotAngles[index])
	local center =
		Vector3.new(Layout.PlotRadius * math.sin(angle), Layout.PlotY, -Layout.PlotRadius * math.cos(angle))
	-- Local -Z (LookVector) faces the village centre: that's the sanctuary's front gate.
	return CFrame.lookAt(center, Vector3.new(0, Layout.PlotY, 0))
end

-- Inside a sanctuary (local space, relative to plotCFrame, y = 0 at the gravel floor).
Layout.PlotFloorHeight = 1.4
Layout.WellOffset = Vector3.new(0, 0, -4)
Layout.SpotRingRadius = 19
Layout.SpotAngles = { 40, -40, 70, -70, 100, -100, 130, -130, 160, -160 }
Layout.EntranceOffset = Vector3.new(0, 0, -30)

function Layout.spotLocalCFrame(spot: number): CFrame
	local angle = math.rad(Layout.SpotAngles[spot])
	local offset = Vector3.new(math.sin(angle), 0, -math.cos(angle)) * Layout.SpotRingRadius
	local position = Layout.WellOffset + offset
	return CFrame.lookAt(position, Layout.WellOffset)
end

function Layout.plotFloorCFrame(index: number): CFrame
	return Layout.plotCFrame(index) * CFrame.new(0, Layout.PlotFloorHeight, 0)
end

-- Travel destinations (character root CFrames).
local function facing(position: Vector3, target: Vector3): CFrame
	return CFrame.lookAt(position, Vector3.new(target.X, position.Y, target.Z))
end

Layout.TravelPoints = {
	Shrine = facing(Vector3.new(0, Layout.SpawnY + 3, 166), Vector3.new(0, 0, 0)),
	Courtyard = facing(Vector3.new(94, 4, -4), Layout.CourtyardCenter),
	Shop = facing(Layout.ShopPosition + Vector3.new(26, 3, 0), Layout.ShopPosition),
	Dojo = facing(Layout.DojoYardCenter + Vector3.new(12, 3, 0), Layout.DojoPosition),
	Forest = facing(Layout.ForestGate + Vector3.new(0, 3, -14), Layout.ForestZoneCenter),
}

function Layout.homeTravelPoint(index: number): CFrame
	local floor = Layout.plotFloorCFrame(index)
	local entrance = floor * CFrame.new(Layout.EntranceOffset + Vector3.new(0, 3, 0))
	return CFrame.lookAt(entrance.Position, (floor * CFrame.new(Layout.WellOffset)).Position)
end

local function insideBox(position: Vector3, center: Vector3, size: Vector3): boolean
	local d = position - center
	return math.abs(d.X) <= size.X / 2 and math.abs(d.Y) <= size.Y / 2 and math.abs(d.Z) <= size.Z / 2
end

function Layout.inForest(position: Vector3): boolean
	return insideBox(position, Layout.ForestZoneCenter, Layout.ForestZoneSize)
end

function Layout.inDojo(position: Vector3): boolean
	return insideBox(position, Layout.DojoYardCenter, Layout.DojoZoneSize)
end

return Layout
