--!strict
-- Tiny helpers for building geometry from primitives. Used by the map builder, character
-- models and curse models. Only writes properties (never reads defaults), so the same code
-- runs in Roblox and in the offline Lune bake.

local PartKit = {}

export type Props = {
	Name: string?,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
	Transparency: number?,
	Reflectance: number?,
	Anchored: boolean?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	CanTouch: boolean?,
	CastShadow: boolean?,
	Massless: boolean?,
	ClassName: string?,
}

function PartKit.part(parent: Instance?, props: Props): BasePart
	local part = Instance.new(props.ClassName or "Part") :: BasePart
	part.Name = props.Name or "Part"
	if props.Shape and part:IsA("Part") then
		part.Shape = props.Shape
	end
	part.Size = props.Size
	part.CFrame = props.CFrame
	part.Color = props.Color or Color3.fromRGB(120, 116, 128)
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = if props.Anchored == nil then true else props.Anchored
	part.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	part.CanTouch = if props.CanTouch == nil then false else props.CanTouch
	part.CanQuery = if props.CanQuery == nil then part.CanCollide else props.CanQuery
	part.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	if props.Transparency then
		part.Transparency = props.Transparency
	end
	if props.Reflectance then
		part.Reflectance = props.Reflectance
	end
	if props.Massless then
		part.Massless = true
	end
	part.Parent = parent
	return part
end

-- Ellipsoid: a block with a sphere mesh stretched to its size.
function PartKit.ellipsoid(parent: Instance?, props: Props): BasePart
	local part = PartKit.part(parent, props)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Vertical cylinder centred on `cf` (Roblox cylinders run along X, so rotate onto Y).
function PartKit.cylinderY(
	parent: Instance?,
	diameter: number,
	height: number,
	cf: CFrame,
	props: { [string]: any }?
): BasePart
	local p = (props or {}) :: any
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, diameter, diameter)
	p.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	return PartKit.part(parent, p)
end

-- Cylinder whose axis runs from a to b.
function PartKit.cylinderBetween(
	parent: Instance?,
	a: Vector3,
	b: Vector3,
	diameter: number,
	props: { [string]: any }?
): BasePart
	local p = (props or {}) :: any
	local length = (b - a).Magnitude
	local mid = (a + b) / 2
	local axis = (b - a).Unit
	-- Build a frame whose X axis is the cylinder axis.
	local up = if math.abs(axis.Y) > 0.95 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	local z = axis:Cross(up).Unit
	local y = z:Cross(axis).Unit
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(length, diameter, diameter)
	p.CFrame = CFrame.fromMatrix(mid, axis, y, z)
	return PartKit.part(parent, p)
end

-- Block spanning from a to b (its Z axis follows the segment), for beams, planks and ropes.
function PartKit.blockBetween(
	parent: Instance?,
	a: Vector3,
	b: Vector3,
	width: number,
	height: number,
	props: { [string]: any }?
): BasePart
	local p = (props or {}) :: any
	local length = (b - a).Magnitude
	p.Size = Vector3.new(width, height, length)
	p.CFrame = CFrame.lookAt((a + b) / 2, b)
	return PartKit.part(parent, p)
end

function PartKit.weld(root: BasePart, part: BasePart): WeldConstraint
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	return weld
end

function PartKit.model(parent: Instance?, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

function PartKit.folder(parent: Instance?, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function PartKit.light(
	parent: Instance,
	color: Color3,
	range: number,
	brightness: number,
	shadows: boolean?
): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = shadows == true
	light.Parent = parent
	return light
end

function PartKit.sequence(points: { { number } }): NumberSequence
	local keypoints = {}
	for _, p in points do
		table.insert(keypoints, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keypoints)
end

-- Particle emitter with sensible defaults; `props` overrides any field.
function PartKit.particles(parent: Instance, props: { [string]: any }): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Rate = 4
	emitter.Lifetime = NumberRange.new(1.5, 2.5)
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(30, 30)
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = parent
	return emitter
end

function PartKit.font(enum: Enum.Font, bold: boolean?): Font
	local face = Font.fromEnum(enum)
	if bold then
		face = Font.new(face.Family, Enum.FontWeight.Bold)
	end
	return face
end

return PartKit
