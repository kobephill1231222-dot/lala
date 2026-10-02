--!strict
-- Reusable architecture and nature pieces for the village. Every builder takes a parent and
-- a CFrame placed on the ground at the piece's base centre, facing its LookVector.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartKit = require(ReplicatedStorage.Shared.Visuals.PartKit)
local Palette = require(script.Parent.Palette)

local Kit = {}

local rad = math.rad
local V3 = Vector3.new
local M = Enum.Material

export type Rng = { NextNumber: (any, number?, number?) -> number, NextInteger: (any, number, number) -> number }

-- Generic part with map defaults (anchored, collidable, smooth).
function Kit.part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, extra: { [string]: any }?): BasePart
	local props: { [string]: any } = { Name = name, Size = size, CFrame = cf, Color = color, Material = material or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return PartKit.part(parent, props :: any)
end

-- Decorative part: no collision, no queries, no shadow unless large.
function Kit.deco(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, extra: { [string]: any }?): BasePart
	local props: { [string]: any } = {
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material or M.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		CastShadow = size.Magnitude > 4,
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return PartKit.part(parent, props :: any)
end

function Kit.wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, collide: boolean?): BasePart
	return PartKit.part(parent, {
		ClassName = "WedgePart",
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material or M.SmoothPlastic,
		CanCollide = collide ~= false,
		CanQuery = collide ~= false,
	})
end

function Kit.cylinder(parent: Instance, name: string, diameter: number, height: number, cf: CFrame, color: Color3, material: Enum.Material?, extra: { [string]: any }?): BasePart
	local props: { [string]: any } = { Name = name, Color = color, Material = material or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return PartKit.cylinderY(parent, diameter, height, cf, props)
end

function Kit.ball(parent: Instance, name: string, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?, extra: { [string]: any }?): BasePart
	local props: { [string]: any } = {
		Name = name,
		Shape = Enum.PartType.Ball,
		Size = V3(diameter, diameter, diameter),
		CFrame = cf,
		Color = color,
		Material = material or M.SmoothPlastic,
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return PartKit.part(parent, props :: any)
end

function Kit.ellipsoid(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, extra: { [string]: any }?): BasePart
	local props: { [string]: any } = { Name = name, Size = size, CFrame = cf, Color = color, Material = material or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return PartKit.ellipsoid(parent, props :: any)
end

function Kit.light(part: BasePart, color: Color3?, range: number?, brightness: number?): PointLight
	return PartKit.light(part, color or Palette.LanternLight, range or 16, brightness or 1.4, false)
end

-- Text on a board face (Front = -Z of the part).
function Kit.label(part: BasePart, text: string, options: { [string]: any }?): TextLabel
	local opts = options or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = opts.guiName or "SignGui"
	gui.Face = opts.face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = opts.pps or 40
	gui.LightInfluence = opts.lightInfluence or 0.6
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = opts.labelName or "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.TextWrapped = true
	label.FontFace = Font.fromEnum(opts.font or Enum.Font.Sarpanch)
	label.TextColor3 = opts.color or Palette.Paper
	label.TextStrokeTransparency = opts.stroke or 0.7
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	local pad = UDim.new(opts.padding or 0.08, 0)
	padding.PaddingLeft, padding.PaddingRight, padding.PaddingTop, padding.PaddingBottom = pad, pad, pad, pad
	padding.Parent = label
	return label
end

-- TORII -----------------------------------------------------------------------------------

function Kit.torii(parent: Instance, cf: CFrame, height: number, width: number, options: { [string]: any }?): Model
	local opts = options or {}
	local color = opts.color or Palette.Lacquer
	local model = PartKit.model(parent, opts.name or "Torii")
	local pillarD = math.max(0.8, width * 0.085)
	for _, side in { -1, 1 } do
		local base = cf * CFrame.new(side * width / 2, 0, 0)
		Kit.cylinder(model, "Pillar", pillarD, height, base * CFrame.new(0, height / 2, 0), color, M.Wood)
		Kit.cylinder(model, "Base", pillarD * 1.25, height * 0.08, base * CFrame.new(0, height * 0.04, 0), Palette.Black, M.Slate)
	end
	-- Nuki: tie beam that passes through both pillars
	Kit.part(model, "Nuki", V3(width * 1.18, height * 0.06, pillarD * 0.6), cf * CFrame.new(0, height * 0.74, 0), color, M.Wood)
	-- Kasagi: the top lintel, gently swept upward at the tips
	local beamY = height * 0.93
	local thick = height * 0.065
	local span = width * 1.5
	Kit.part(model, "Kasagi", V3(span * 0.6, thick, pillarD * 1.25), cf * CFrame.new(0, beamY, 0), color, M.Wood)
	Kit.part(model, "Shimaki", V3(span * 0.6, thick * 0.6, pillarD * 1.35), cf * CFrame.new(0, beamY + thick * 0.8, 0), Palette.Black, M.Slate)
	for _, side in { -1, 1 } do
		local tip = cf * CFrame.new(side * span * 0.39, beamY + thick * 0.25, 0) * CFrame.Angles(0, 0, rad(side * 7))
		Kit.part(model, "KasagiTip", V3(span * 0.22, thick, pillarD * 1.25), tip, color, M.Wood)
		Kit.part(model, "ShimakiTip", V3(span * 0.22, thick * 0.6, pillarD * 1.35), tip * CFrame.new(0, thick * 0.8, 0), Palette.Black, M.Slate)
	end
	-- Gakuzuka strut and a small plaque
	Kit.part(model, "Strut", V3(pillarD * 0.7, height * 0.13, pillarD * 0.5), cf * CFrame.new(0, height * 0.835, 0), color, M.Wood)
	if opts.plaque then
		local plaque = Kit.part(model, "Plaque", V3(width * 0.16, height * 0.14, 0.3), cf * CFrame.new(0, height * 0.835, -pillarD * 0.3), Palette.Black, M.Wood)
		Kit.label(plaque, opts.plaque, { color = Color3.fromRGB(230, 200, 140), font = Enum.Font.Sarpanch })
	end
	if opts.rope then
		Kit.rope(model, (cf * CFrame.new(-width / 2, height * 0.68, 0)).Position, (cf * CFrame.new(width / 2, height * 0.68, 0)).Position, height * 0.06, pillarD * 0.45, 10)
	end
	return model
end

-- ROPES & PAPER -----------------------------------------------------------------------------

-- Shimenawa: a sagging twisted rope with paper shide streamers.
function Kit.rope(parent: Instance, a: Vector3, b: Vector3, sag: number, thickness: number, segments: number, color: Color3?): ()
	local previous = a
	for i = 1, segments do
		local t = i / segments
		local p = a:Lerp(b, t) - V3(0, sag * 4 * t * (1 - t), 0)
		PartKit.cylinderBetween(parent, previous, p, thickness, {
			Name = "Rope",
			Color = color or Palette.Rope,
			Material = M.Fabric,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
		if i % 3 == 0 and i < segments then
			Kit.shide(parent, CFrame.lookAt(p, p + (b - a):Cross(V3(0, 1, 0))) * CFrame.new(0, -thickness * 0.5, 0), math.min(thickness * 1.6, 1.8))
		end
		previous = p
	end
end

function Kit.shide(parent: Instance, cf: CFrame, scale: number)
	for i = 0, 2 do
		Kit.deco(parent, "Shide", V3(scale * 0.6, scale * 0.55, 0.06), cf * CFrame.new((i % 2) * scale * 0.18, -scale * (0.3 + i * 0.5), 0), Palette.Paper)
	end
end

-- LANTERNS ---------------------------------------------------------------------------------

-- Stone tōrō. Returns the glowing fire-box part.
function Kit.stoneLantern(parent: Instance, cf: CFrame, scale: number?, lit: boolean?): BasePart
	local s = scale or 1
	local model = PartKit.model(parent, "StoneLantern")
	local stone = Palette.Stone
	Kit.part(model, "Base", V3(2.2, 0.5, 2.2) * s, cf * CFrame.new(0, 0.25 * s, 0), Palette.StoneDark, M.Slate)
	Kit.cylinder(model, "Post", 0.9 * s, 2.6 * s, cf * CFrame.new(0, 1.8 * s, 0), stone, M.Slate)
	Kit.part(model, "Platform", V3(1.9, 0.45, 1.9) * s, cf * CFrame.new(0, 3.3 * s, 0), stone, M.Slate)
	local box = Kit.part(model, "FireBox", V3(1.2, 1.1, 1.2) * s, cf * CFrame.new(0, 4.05 * s, 0), if lit ~= false then Palette.Lantern else Palette.StoneDark, if lit ~= false then M.Neon else M.Slate, { CanCollide = false })
	for _, offset in { V3(0.55, 0, 0.55), V3(-0.55, 0, 0.55), V3(0.55, 0, -0.55), V3(-0.55, 0, -0.55) } do
		Kit.deco(model, "Frame", V3(0.25, 1.15, 0.25) * s, cf * CFrame.new(offset * s + V3(0, 4.05 * s, 0)), stone, M.Slate)
	end
	-- Roof: a squat pyramid with a jewel on top
	for i = 0, 3 do
		local rot = CFrame.Angles(0, rad(i * 90), 0)
		Kit.wedge(model, "Roof", V3(2.6, 0.7, 1.3) * s, cf * CFrame.new(0, 4.95 * s, 0) * rot * CFrame.new(0, 0, -0.65 * s), stone, M.Slate, false)
	end
	Kit.ball(model, "Jewel", 0.55 * s, cf * CFrame.new(0, 5.55 * s, 0), stone, M.Slate, { CanCollide = false })
	if lit ~= false then
		Kit.light(box, Palette.LanternLight, 14 * s, 1.3)
	end
	return box
end

-- Paper chōchin lantern hanging from `cf` (the hook point).
function Kit.paperLantern(parent: Instance, cf: CFrame, size: number?, color: Color3?, withLight: boolean?): BasePart
	local s = size or 1
	local body = Kit.ellipsoid(parent, "PaperLantern", V3(1.3, 1.7, 1.3) * s, cf * CFrame.new(0, -1.25 * s, 0), color or Palette.LanternPaper, M.Neon, { CanCollide = false, CanQuery = false, CastShadow = false })
	Kit.cylinder(parent, "Cap", 0.8 * s, 0.22 * s, cf * CFrame.new(0, -0.38 * s, 0), Palette.Black, M.Wood, { CanCollide = false, CanQuery = false, CastShadow = false })
	Kit.cylinder(parent, "Cap", 0.8 * s, 0.22 * s, cf * CFrame.new(0, -2.12 * s, 0), Palette.Black, M.Wood, { CanCollide = false, CanQuery = false, CastShadow = false })
	Kit.deco(parent, "Cord", V3(0.08, 0.3, 0.08) * s, cf * CFrame.new(0, -0.12 * s, 0), Palette.Black)
	if withLight then
		Kit.light(body, Palette.LanternLight, 12 * s, 1.1)
	end
	return body
end

-- A string of paper lanterns between two points.
function Kit.lanternString(parent: Instance, a: Vector3, b: Vector3, count: number, sag: number, lightEvery: number?)
	local previous = a
	local steps = count + 1
	for i = 1, steps do
		local t = i / steps
		local p = a:Lerp(b, t) - V3(0, sag * 4 * t * (1 - t), 0)
		PartKit.cylinderBetween(parent, previous, p, 0.12, { Name = "Cord", Color = Palette.Black, Material = M.Fabric, CanCollide = false, CanQuery = false, CastShadow = false })
		if i <= count then
			Kit.paperLantern(parent, CFrame.new(p), 0.7, nil, lightEvery ~= nil and i % lightEvery == 0)
		end
		previous = p
	end
end

-- ROOFS & BUILDINGS -------------------------------------------------------------------------

-- Curved Japanese roof: steep upper slopes, shallow flared eaves, ridge cap.
-- `cf` is the centre of the eave line (bottom of the roof); width along X, depth along Z.
function Kit.roof(parent: Instance, cf: CFrame, width: number, depth: number, height: number, color: Color3?, hip: boolean?)
	local c = color or Palette.RoofTile
	local M_ROOF = M.Slate
	local upperH = height * 0.75
	local eaveH = height * 0.25
	local halfD = depth / 2
	for _, side in { -1, 1 } do
		local rot = if side == 1 then CFrame.Angles(0, rad(180), 0) else CFrame.new()
		-- Flared eave (shallow)
		Kit.wedge(parent, "Eave", V3(width, eaveH, halfD * 0.42), cf * rot * CFrame.new(0, eaveH / 2, -halfD + halfD * 0.21), c, M_ROOF, false)
		-- Upper slope (steep)
		Kit.wedge(parent, "Slope", V3(width * 0.94, upperH, halfD * 0.62), cf * rot * CFrame.new(0, eaveH + upperH / 2, -halfD * 0.58 + halfD * 0.31 - 0.05), c, M_ROOF, false)
		-- Fill under the eave
		Kit.deco(parent, "RoofCore", V3(width * 0.94, eaveH, halfD * 0.62), cf * rot * CFrame.new(0, eaveH / 2, -halfD * 0.27), c, M_ROOF)
		if hip then
			-- Hip ends: wedges facing the side
			local sideRot = CFrame.Angles(0, rad(side * 90), 0)
			Kit.wedge(parent, "HipEave", V3(depth * 0.95, eaveH, width * 0.12), cf * sideRot * CFrame.new(0, eaveH / 2, -width / 2 + width * 0.06), c, M_ROOF, false)
		end
	end
	-- Ridge
	Kit.deco(parent, "Ridge", V3(width * 0.98, height * 0.16, depth * 0.08), cf * CFrame.new(0, height + height * 0.02, 0), Palette.Black, M_ROOF)
	for _, side in { -1, 1 } do
		Kit.deco(parent, "Onigawara", V3(height * 0.12, height * 0.32, depth * 0.1), cf * CFrame.new(side * width * 0.49, height + height * 0.1, 0), Palette.Black, M_ROOF)
	end
	-- Gable ends: close the triangle so the roof reads solid from the side
	if not hip then
		for _, side in { -1, 1 } do
			local gable = cf * CFrame.new(side * width * 0.46, 0, 0)
			for _, half in { -1, 1 } do
				local rot = if half == 1 then CFrame.Angles(0, rad(180), 0) else CFrame.new()
				Kit.wedge(parent, "Gable", V3(0.4, height, halfD * 0.95), gable * rot * CFrame.new(0, height / 2, -halfD * 0.475), Palette.DarkWood, M.Wood, false)
			end
		end
	end
end

-- A timber building on a stone plinth. Returns the model and the floor height.
function Kit.building(parent: Instance, cf: CFrame, width: number, depth: number, wallHeight: number, options: { [string]: any }?): (Model, number)
	local opts = options or {}
	local model = PartKit.model(parent, opts.name or "Building")
	local plinth = opts.plinth or 1.2
	local wood = opts.wood or Palette.DarkWood
	Kit.part(model, "Plinth", V3(width + 1.4, plinth, depth + 1.4), cf * CFrame.new(0, plinth / 2, 0), Palette.StoneDark, M.Slate)
	Kit.part(model, "Floor", V3(width, 0.4, depth), cf * CFrame.new(0, plinth + 0.2, 0), Palette.Wood, M.WoodPlanks)
	local floorY = plinth + 0.4
	-- Pillars on a grid
	local nx = math.max(2, math.floor(width / 7) + 1)
	local nz = math.max(2, math.floor(depth / 7) + 1)
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			if i == 0 or j == 0 or i == nx - 1 or j == nz - 1 then
				local x = -width / 2 + 0.5 + i * (width - 1) / (nx - 1)
				local z = -depth / 2 + 0.5 + j * (depth - 1) / (nz - 1)
				Kit.part(model, "Pillar", V3(0.9, wallHeight, 0.9), cf * CFrame.new(x, floorY + wallHeight / 2, z), wood, M.Wood)
			end
		end
	end
	-- Walls: plaster panels with a dark timber band, leaving the front open if requested
	local walls = {
		{ side = "back", cf = CFrame.new(0, 0, depth / 2 - 0.3), len = width, rot = 0 },
		{ side = "left", cf = CFrame.new(-width / 2 + 0.3, 0, 0), len = depth, rot = 90 },
		{ side = "right", cf = CFrame.new(width / 2 - 0.3, 0, 0), len = depth, rot = 90 },
		{ side = "front", cf = CFrame.new(0, 0, -depth / 2 + 0.3), len = width, rot = 0 },
	}
	for _, wall in walls do
		local open = opts.open and opts.open[wall.side]
		local base = cf * wall.cf * CFrame.Angles(0, rad(wall.rot), 0)
		if not open then
			Kit.part(model, "Wall", V3(wall.len - 1, wallHeight * 0.62, 0.35), base * CFrame.new(0, floorY + wallHeight * 0.31, 0), opts.plaster or Palette.Plaster, M.Plaster)
			Kit.part(model, "Wainscot", V3(wall.len - 0.9, wallHeight * 0.18, 0.45), base * CFrame.new(0, floorY + wallHeight * 0.09, 0), wood, M.WoodPlanks)
			Kit.part(model, "Transom", V3(wall.len - 1, wallHeight * 0.38, 0.3), base * CFrame.new(0, floorY + wallHeight * 0.81, 0), Palette.Wood, M.WoodPlanks)
		else
			Kit.part(model, "Lintel", V3(wall.len, wallHeight * 0.14, 0.6), base * CFrame.new(0, floorY + wallHeight * 0.93, 0), wood, M.Wood)
		end
	end
	-- Roof
	local overhang = opts.overhang or 3
	Kit.roof(model, cf * CFrame.new(0, floorY + wallHeight, 0), width + overhang * 2, depth + overhang * 2, opts.roofHeight or (depth * 0.45), opts.roofColor, opts.hip)
	return model, floorY
end

-- STEPS, FENCES, BRIDGES -------------------------------------------------------------------

-- Stairs climbing along the LookVector of `cf` (which sits at the bottom-front edge).
function Kit.steps(parent: Instance, cf: CFrame, width: number, totalRise: number, count: number, run: number?, color: Color3?)
	local r = run or 1.4
	local rise = totalRise / count
	for i = 1, count do
		local h = rise * i
		Kit.part(parent, "Step", V3(width, h, r), cf * CFrame.new(0, h / 2, -(i - 0.5) * r), color or Palette.Stone, M.Slate)
	end
end

function Kit.fence(parent: Instance, points: { Vector3 }, height: number, color: Color3?, spacing: number?)
	local c = color or Palette.DarkWood
	local gap = spacing or 3
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local length = (b - a).Magnitude
		local n = math.max(1, math.floor(length / gap))
		for k = 0, n do
			local p = a:Lerp(b, k / n)
			Kit.part(parent, "Post", V3(0.45, height, 0.45), CFrame.new(p + V3(0, height / 2, 0)), c, M.Wood)
		end
		for _, h in { height * 0.4, height * 0.85 } do
			PartKit.blockBetween(parent, a + V3(0, h, 0), b + V3(0, h, 0), 0.25, 0.3, { Name = "Rail", Color = c, Material = M.Wood })
		end
	end
end

-- Arched bridge from a to b (deck top heights taken from the points), rising by `arch`.
function Kit.bridge(parent: Instance, a: Vector3, b: Vector3, width: number, arch: number, options: { [string]: any }?): Model
	local opts = options or {}
	local model = PartKit.model(parent, opts.name or "Bridge")
	local color = opts.color or Palette.Lacquer
	local segments = opts.segments or 12
	local dir = (b - a) * V3(1, 0, 1)
	local right = dir.Unit:Cross(V3(0, 1, 0))
	local function pointAt(t: number): Vector3
		return a:Lerp(b, t) + V3(0, arch * math.sin(math.pi * t), 0)
	end
	for i = 1, segments do
		local p0, p1 = pointAt((i - 1) / segments), pointAt(i / segments)
		local mid = (p0 + p1) / 2
		local frame = CFrame.lookAt(mid, p1)
		local len = (p1 - p0).Magnitude + 0.15
		Kit.part(model, "Deck", V3(width, 0.6, len), frame * CFrame.new(0, -0.3, 0), Palette.AgedWood, M.WoodPlanks)
		Kit.deco(model, "Beam", V3(width + 0.6, 0.8, len), frame * CFrame.new(0, -0.95, 0), Palette.DarkWood, M.Wood)
		for _, side in { -1, 1 } do
			local rail = frame * CFrame.new(side * (width / 2 + 0.1), 2.6, 0)
			Kit.part(model, "Rail", V3(0.35, 0.3, len), rail, color, M.Wood)
			Kit.deco(model, "LowRail", V3(0.25, 0.25, len), frame * CFrame.new(side * (width / 2 + 0.1), 1.3, 0), color, M.Wood)
			-- Invisible guard so players don't tumble off the arch
			Kit.part(model, "Guard", V3(0.3, 4, len), frame * CFrame.new(side * (width / 2 + 0.2), 2, 0), color, M.Wood, { Transparency = 1, CastShadow = false })
		end
		if i == 1 or i == segments or i % 3 == 0 then
			local p = if i == segments then p1 else p0
			for _, side in { -1, 1 } do
				local post = p + right * side * (width / 2 + 0.1)
				Kit.part(model, "Post", V3(0.55, 3.3, 0.55), CFrame.new(post + V3(0, 1.35, 0)), color, M.Wood)
				-- Giboshi: the onion-shaped bronze post caps
				Kit.ball(model, "Giboshi", 0.75, CFrame.new(post + V3(0, 3.2, 0)), Color3.fromRGB(150, 120, 70), M.Metal, { CanCollide = false })
			end
		end
	end
	-- Supports down into the water
	if opts.supports ~= false then
		for _, t in { 0.3, 0.7 } do
			local p = pointAt(t)
			for _, side in { -1, 1 } do
				local base = p + right * side * (width / 2 - 0.4)
				local depthBelow = (opts.supportBottom or (math.min(a.Y, b.Y) - 6))
				local h = base.Y - depthBelow
				Kit.part(model, "Support", V3(0.8, h, 0.8), CFrame.new(base.X, depthBelow + h / 2, base.Z), Palette.DarkWood, M.Wood)
			end
		end
	end
	return model
end

-- NATURE ------------------------------------------------------------------------------------

function Kit.rock(parent: Instance, pos: Vector3, size: number, rng: Rng, color: Color3?): BasePart
	local s = V3(size * rng:NextNumber(0.9, 1.4), size * rng:NextNumber(0.55, 0.9), size * rng:NextNumber(0.8, 1.2))
	local cf = CFrame.new(pos + V3(0, s.Y * 0.25, 0)) * CFrame.Angles(rad(rng:NextNumber(-12, 12)), rad(rng:NextNumber(0, 360)), rad(rng:NextNumber(-12, 12)))
	return Kit.part(parent, "Rock", s, cf, color or Palette.StoneDark, M.Slate)
end

function Kit.bamboo(parent: Instance, center: Vector3, rng: Rng, count: number, radius: number, minH: number, maxH: number)
	local grove = PartKit.model(parent, "Bamboo")
	for _ = 1, count do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = radius * math.sqrt(rng:NextNumber())
		local base = center + V3(math.cos(a) * r, -0.5, math.sin(a) * r)
		local h = rng:NextNumber(minH, maxH)
		local d = rng:NextNumber(0.55, 0.9)
		local lean = CFrame.Angles(rad(rng:NextNumber(-5, 5)), 0, rad(rng:NextNumber(-5, 5)))
		local frame = CFrame.new(base) * lean
		local color = if rng:NextNumber() < 0.3 then Palette.BambooDark else Palette.Bamboo
		Kit.cylinder(grove, "Stalk", d, h, frame * CFrame.new(0, h / 2, 0), color, M.SmoothPlastic, { CanCollide = r < radius * 0.8, CastShadow = true })
		for k = 1, 2 do
			Kit.cylinder(grove, "Node", d * 1.12, 0.18, frame * CFrame.new(0, h * k / 3, 0), Palette.BambooDark, M.SmoothPlastic, { CanCollide = false, CanQuery = false, CastShadow = false })
		end
		for k = 1, (if rng:NextNumber() < 0.5 then 1 else 2) do
			local leafY = h * (0.78 + k * 0.08)
			local ang = rng:NextNumber(0, 360)
			Kit.ellipsoid(grove, "Leaves", V3(rng:NextNumber(3, 5), 0.6, rng:NextNumber(1.2, 2)), frame * CFrame.new(0, leafY, 0) * CFrame.Angles(0, rad(ang), rad(-12)) * CFrame.new(1.6, 0, 0), Palette.BambooLeaf, M.Grass, { CanCollide = false, CanQuery = false, CastShadow = false })
		end
	end
	return grove
end

-- Japanese black pine: a leaning trunk with flat, layered foliage pads.
function Kit.pine(parent: Instance, base: Vector3, scale: number, rng: Rng)
	local tree = PartKit.model(parent, "Pine")
	local h = 18 * scale
	local lean = rng:NextNumber(-14, 14)
	local yaw = rng:NextNumber(0, 360)
	local frame = CFrame.new(base) * CFrame.Angles(0, rad(yaw), 0) * CFrame.Angles(0, 0, rad(lean))
	local segs = 3
	for i = 1, segs do
		local d = (1.8 - i * 0.35) * scale
		local seg = frame * CFrame.new(0, h * (i - 0.5) / segs, 0) * CFrame.Angles(0, 0, rad((i - 2) * 6))
		Kit.cylinder(tree, "Trunk", d, h / segs + 0.4, seg, Palette.Wood, M.Wood)
	end
	for i = 1, 5 do
		local y = h * (0.45 + i * 0.11)
		local ang = rad(i * 137)
		local off = V3(math.cos(ang), 0, math.sin(ang)) * (3.2 - i * 0.35) * scale
		local pad = frame * CFrame.new(off.X, y, off.Z)
		local w = (9 - i * 1.1) * scale
		local padColor = if i % 2 == 0 then Palette.Pine else Palette.FoliageDark
		Kit.ellipsoid(tree, "Pad", V3(w, 2.8 * scale, w * 0.8), pad, padColor, M.Grass, { CanCollide = false, CanQuery = false })
		Kit.ellipsoid(tree, "Pad", V3(w * 0.6, 2.4 * scale, w * 0.55), pad * CFrame.new(w * 0.15, 1.2 * scale, -w * 0.1), padColor:Lerp(Palette.Moss, 0.25), M.Grass, { CanCollide = false, CanQuery = false })
		PartKit.cylinderBetween(tree, (frame * CFrame.new(0, y - 1.5 * scale, 0)).Position, pad.Position, 0.5 * scale, { Name = "Branch", Color = Palette.Wood, Material = M.Wood, CanCollide = false, CanQuery = false })
	end
	return tree
end

function Kit.maple(parent: Instance, base: Vector3, scale: number, rng: Rng, color: Color3?)
	local tree = PartKit.model(parent, "Maple")
	local h = 11 * scale
	Kit.cylinder(tree, "Trunk", 1.3 * scale, h, CFrame.new(base + V3(0, h / 2, 0)), Palette.DarkWood, M.Wood)
	for i = 1, 6 do
		local a = rad(i * 60 + rng:NextNumber(-20, 20))
		local r = rng:NextNumber(2, 4.5) * scale
		local p = base + V3(math.cos(a) * r, h + rng:NextNumber(-1.5, 2.5) * scale, math.sin(a) * r)
		Kit.ball(tree, "Leaves", rng:NextNumber(5, 7.5) * scale, CFrame.new(p), (color or Palette.Maple):Lerp(Palette.FoliageDark, rng:NextNumber(0, 0.35)), M.Grass, { CanCollide = false, CanQuery = false })
	end
	Kit.ball(tree, "Crown", 7 * scale, CFrame.new(base + V3(0, h + 3 * scale, 0)), color or Palette.Maple, M.Grass, { CanCollide = false, CanQuery = false })
	return tree
end

-- Twisted, leafless cursed tree with a few violet-black tufts.
function Kit.cursedTree(parent: Instance, base: Vector3, scale: number, rng: Rng)
	local tree = PartKit.model(parent, "CursedTree")
	local yaw = rng:NextNumber(0, 360)
	local p = base - V3(0, 0.5, 0)
	local dir = V3(0, 1, 0)
	local d = 2.6 * scale
	for i = 1, 5 do
		local len = rng:NextNumber(4.5, 6.5) * scale
		dir = (dir + V3(rng:NextNumber(-0.35, 0.35), 0, rng:NextNumber(-0.35, 0.35))).Unit
		local nextP = p + dir * len
		PartKit.cylinderBetween(tree, p, nextP, d, { Name = "Trunk", Color = Palette.CursedBark, Material = M.Wood, CanCollide = i <= 2 })
		if i >= 3 then
			for _ = 1, 2 do
				local bdir = (dir + V3(rng:NextNumber(-1, 1), rng:NextNumber(-0.2, 0.5), rng:NextNumber(-1, 1))).Unit
				local tip = nextP + bdir * rng:NextNumber(4, 8) * scale
				PartKit.cylinderBetween(tree, nextP, tip, d * 0.45, { Name = "Branch", Color = Palette.CursedBark, Material = M.Wood, CanCollide = false, CanQuery = false })
				if rng:NextNumber() < 0.6 then
					Kit.ball(tree, "Tuft", rng:NextNumber(3.5, 6) * scale, CFrame.new(tip), Color3.fromRGB(38, 26, 52), M.Grass, { CanCollide = false, CanQuery = false })
				end
			end
		end
		p = nextP
		d *= 0.78
	end
	local _ = yaw
	return tree
end

function Kit.lilies(parent: Instance, center: Vector3, radius: number, count: number, rng: Rng)
	for _ = 1, count do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = radius * math.sqrt(rng:NextNumber())
		local base = center + V3(math.cos(a) * r, 0, math.sin(a) * r)
		local h = rng:NextNumber(1.4, 2.2)
		Kit.deco(parent, "Stem", V3(0.12, h, 0.12), CFrame.new(base + V3(0, h / 2, 0)), Color3.fromRGB(60, 90, 50))
		for k = 0, 4 do
			local cf = CFrame.new(base + V3(0, h, 0)) * CFrame.Angles(0, rad(k * 72), 0) * CFrame.Angles(rad(-40), 0, 0) * CFrame.new(0, 0.35, 0)
			Kit.deco(parent, "Petal", V3(0.12, 0.8, 0.12), cf, Palette.Lily, M.Neon, { Transparency = 0.15 })
		end
	end
end

function Kit.grassTufts(parent: Instance, center: Vector3, radius: number, count: number, rng: Rng, color: Color3?)
	for _ = 1, count do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = radius * math.sqrt(rng:NextNumber())
		local base = center + V3(math.cos(a) * r, 0, math.sin(a) * r)
		local h = rng:NextNumber(0.8, 1.6)
		Kit.wedge(parent, "Tuft", V3(0.2, h, rng:NextNumber(0.6, 1.2)), CFrame.new(base + V3(0, h / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), color or Palette.Moss, M.Grass, false)
	end
end

-- STATUES & PROPS ---------------------------------------------------------------------------

function Kit.komainu(parent: Instance, cf: CFrame)
	local model = PartKit.model(parent, "Komainu")
	local stone = Palette.StoneLight
	Kit.part(model, "Pedestal", V3(3, 2.4, 3.6), cf * CFrame.new(0, 1.2, 0), Palette.StoneDark, M.Slate)
	Kit.ellipsoid(model, "Body", V3(2, 2.2, 3), cf * CFrame.new(0, 3.4, 0.3), stone, M.Slate)
	Kit.ball(model, "Head", 2, cf * CFrame.new(0, 5.0, -0.7), stone, M.Slate)
	Kit.ellipsoid(model, "Mane", V3(2.5, 2.2, 1.2), cf * CFrame.new(0, 4.7, -0.2), Palette.Stone, M.Slate)
	Kit.part(model, "Snout", V3(1, 0.7, 0.8), cf * CFrame.new(0, 4.75, -1.65), stone, M.Slate)
	for _, side in { -1, 1 } do
		Kit.part(model, "Leg", V3(0.6, 1.6, 0.6), cf * CFrame.new(side * 0.6, 3.0, -1.0), stone, M.Slate)
		Kit.deco(model, "Eye", V3(0.25, 0.2, 0.1), cf * CFrame.new(side * 0.42, 5.25, -1.62), Palette.Lantern, M.Neon)
	end
	return model
end

function Kit.jizo(parent: Instance, cf: CFrame)
	local model = PartKit.model(parent, "Jizo")
	Kit.ellipsoid(model, "Body", V3(1.4, 2, 1.2), cf * CFrame.new(0, 1, 0), Palette.StoneLight, M.Slate)
	Kit.ball(model, "Head", 1.1, cf * CFrame.new(0, 2.35, 0), Palette.StoneLight, M.Slate)
	Kit.wedge(model, "Bib", V3(1.3, 0.8, 0.5), cf * CFrame.new(0, 1.55, -0.45) * CFrame.Angles(0, 0, rad(180)), Color3.fromRGB(170, 40, 40), M.Fabric, false)
	return model
end

function Kit.sign(parent: Instance, cf: CFrame, width: number, height: number, text: string, options: { [string]: any }?): BasePart
	local opts = options or {}
	local board = Kit.part(parent, opts.name or "Sign", V3(width, height, 0.35), cf, opts.board or Palette.DarkWood, M.Wood)
	Kit.label(board, text, opts)
	if opts.back then
		local o = table.clone(opts)
		o.face = Enum.NormalId.Back
		Kit.label(board, opts.backText or text, o)
	end
	return board
end

return Kit
