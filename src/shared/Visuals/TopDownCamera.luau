--!strict
-- Top-down camera: looks down on your character from high above at a steep, fixed angle, so the
-- game plays like a 2D top-down game while you walk around the world. The view never rotates
-- (screen-up is a fixed world direction, set with setYaw), so movement keys always mean the
-- same thing on screen. Mouse wheel, I / O and pinch zoom in and out.
--
-- Anything overhead (roofs, gate beams, tree canopies, lantern strings) fades out while you
-- stand under it, so it never hides you. Overhead parts are found once from where they sit,
-- not by raycasts, because most decoration isn't queryable.
--
-- `frame` and `Overhead` are pure, so offline tests can check them.

local TopDownCamera = {}

-- 90 would be straight down; a little less keeps a sliver of the sides visible and keeps
-- Roblox's camera-relative movement well defined.
TopDownCamera.Pitch = 80
-- A narrow field of view from further away keeps perspective low, so the world reads flat.
TopDownCamera.FieldOfView = 40
TopDownCamera.Distance = 90
TopDownCamera.MinDistance = 45
TopDownCamera.MaxDistance = 150
-- Parts whose lowest point is at least this high above the ground count as overhead.
TopDownCamera.OverheadHeight = 7
TopDownCamera.FadedTransparency = 0.8

local CELL = 16 -- grid cell size (studs) for finding overhead parts quickly

-- Camera CFrame looking at `target` from `distance` away, `pitch` degrees below the horizon,
-- with screen-up pointing along the ground direction given by `yaw` (0 = north, -Z).
function TopDownCamera.frame(target: Vector3, yaw: number, pitch: number, distance: number): CFrame
	local y, p = math.rad(yaw), math.rad(pitch)
	local up = Vector3.new(-math.sin(y), 0, -math.cos(y))
	local position = target - up * (distance * math.cos(p)) + Vector3.new(0, distance * math.sin(p), 0)
	return CFrame.lookAt(position, target, up)
end

-- Yaw that puts `direction` (a ground direction) at the top of the screen.
function TopDownCamera.yawFacing(direction: Vector3): number
	return math.deg(math.atan2(-direction.X, -direction.Z))
end

-- Overhead index ---------------------------------------------------------------------------

export type Overhead = {
	cells: { [string]: { BasePart } },
	count: number,
}

local function key(x: number, z: number): string
	return math.floor(x / CELL) .. ":" .. math.floor(z / CELL)
end

-- World-axis half extents of a part's box.
local function extents(cf: CFrame, size: Vector3): Vector3
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	return Vector3.new(
		math.abs(r00) * hx + math.abs(r01) * hy + math.abs(r02) * hz,
		math.abs(r10) * hx + math.abs(r11) * hy + math.abs(r12) * hz,
		math.abs(r20) * hx + math.abs(r21) * hy + math.abs(r22) * hz
	)
end

-- Indexes every part under `roots` whose bottom is at least OverheadHeight above `groundY`.
-- `keep` can exclude parts that must stay visible (gameplay objects that happen to be tall).
function TopDownCamera.indexOverhead(
	roots: { Instance },
	groundY: number?,
	keep: ((BasePart) -> boolean)?
): Overhead
	local index: Overhead = { cells = {}, count = 0 }
	local floor = (groundY or 0) + TopDownCamera.OverheadHeight
	for _, root in roots do
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and not (keep and keep(d)) then
				local cf = d.CFrame
				local e = extents(cf, d.Size)
				local p = cf.Position
				if p.Y - e.Y >= floor then
					index.count += 1
					for cx = math.floor((p.X - e.X) / CELL), math.floor((p.X + e.X) / CELL) do
						for cz = math.floor((p.Z - e.Z) / CELL), math.floor((p.Z + e.Z) / CELL) do
							local k = cx .. ":" .. cz
							local list = index.cells[k]
							if not list then
								list = {}
								index.cells[k] = list
							end
							table.insert(list, d)
						end
					end
				end
			end
		end
	end
	return index
end

-- Overhead parts that cover `position` (a character's root, within `margin` studs) and are
-- above its head.
function TopDownCamera.over(index: Overhead, position: Vector3, margin: number?): { BasePart }
	local m = margin or 2
	local head = position.Y + 2
	local found: { BasePart } = {}
	local list = index.cells[key(position.X, position.Z)]
	if not list then
		return found
	end
	for _, part in list do
		local cf = part.CFrame
		local e = extents(cf, part.Size)
		local p = cf.Position
		if
			math.abs(position.X - p.X) <= e.X + m
			and math.abs(position.Z - p.Z) <= e.Z + m
			and p.Y - e.Y > head
		then
			table.insert(found, part)
		end
	end
	return found
end

-- Controller ---------------------------------------------------------------------------------

type State = {
	yaw: number,
	targetYaw: number,
	distance: number,
	zoomTo: number,
	focus: Vector3?,
	overhead: Overhead?,
	faded: { [BasePart]: boolean },
	fadeClock: number,
}

local state: State = {
	yaw = 0,
	targetYaw = 0,
	distance = TopDownCamera.Distance,
	zoomTo = TopDownCamera.Distance,
	focus = nil,
	overhead = nil,
	faded = {},
	fadeClock = 0,
}
TopDownCamera.state = state

-- Turns the view so `yaw` is screen-up (eased over a moment unless `instant`).
function TopDownCamera.setYaw(yaw: number, instant: boolean?)
	state.targetYaw = yaw
	if instant then
		state.yaw = yaw
	end
end

function TopDownCamera.zoom(factor: number)
	state.zoomTo = math.clamp(state.zoomTo * factor, TopDownCamera.MinDistance, TopDownCamera.MaxDistance)
end

-- Fades what's above `position` and restores what no longer is.
local function updateFades(position: Vector3)
	local index = state.overhead
	if not index then
		return
	end
	local now: { [BasePart]: boolean } = {}
	for _, part in TopDownCamera.over(index, position) do
		now[part] = true
		if not state.faded[part] then
			part.LocalTransparencyModifier = TopDownCamera.FadedTransparency
		end
	end
	for part in state.faded do
		if not now[part] then
			part.LocalTransparencyModifier = 0
		end
	end
	state.faded = now
end
TopDownCamera.updateFades = updateFades

-- Shortest signed angle from a to b, in degrees.
local function angleDelta(a: number, b: number): number
	return (b - a + 180) % 360 - 180
end

-- One camera update (called every frame by the controller; exposed for tests).
function TopDownCamera.step(camera: Camera, focus: Vector3?, dt: number)
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	local k = 1 - math.exp(-12 * dt)
	if focus then
		state.focus = if state.focus then (state.focus :: Vector3):Lerp(focus, k) else focus
	end
	state.distance += (state.zoomTo - state.distance) * k
	state.yaw += angleDelta(state.yaw, state.targetYaw) * (1 - math.exp(-5 * dt))
	local target = state.focus
	if not target then
		return
	end
	camera.CFrame = TopDownCamera.frame(target, state.yaw, TopDownCamera.Pitch, state.distance)
	-- Roblox renders detail and places the listener around the focus.
	camera.Focus = CFrame.new(target)
	state.fadeClock += dt
	if focus and state.fadeClock >= 0.1 then
		state.fadeClock = 0
		updateFades(focus)
	end
end

-- Takes over the camera for the local player. `overheadRoots` are the map folders whose
-- overhead parts should fade (e.g. { workspace.JJKFarmMap }); `keep` excludes some of them.
function TopDownCamera.start(overheadRoots: { Instance }?, keep: ((BasePart) -> boolean)?)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")
	local player = Players.LocalPlayer
	if overheadRoots then
		-- Index once everything has replicated, so no roof is missed. The camera works meanwhile.
		task.spawn(function()
			if not game:IsLoaded() then
				game.Loaded:Wait()
			end
			state.overhead = TopDownCamera.indexOverhead(overheadRoots, 0, keep)
		end)
	end
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = TopDownCamera.FieldOfView

	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.UserInputType == Enum.UserInputType.MouseWheel then
			TopDownCamera.zoom(if input.Position.Z > 0 then 0.88 else 1 / 0.88)
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.I then
			TopDownCamera.zoom(0.8)
		elseif input.KeyCode == Enum.KeyCode.O then
			TopDownCamera.zoom(1.25)
		end
	end)
	local pinchStart = state.zoomTo
	UserInputService.TouchPinch:Connect(
		function(
			_touches: { any },
			scale: number,
			_velocity: number,
			inputState: Enum.UserInputState,
			processed: boolean
		)
			if processed then
				return
			end
			if inputState == Enum.UserInputState.Begin then
				pinchStart = state.zoomTo
			elseif scale > 0 then
				state.zoomTo =
					math.clamp(pinchStart / scale, TopDownCamera.MinDistance, TopDownCamera.MaxDistance)
			end
		end
	)

	RunService:BindToRenderStep("TopDownCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		local cam = workspace.CurrentCamera
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		TopDownCamera.step(cam, if root then root.CFrame.Position else nil, dt)
	end)
end

return TopDownCamera
