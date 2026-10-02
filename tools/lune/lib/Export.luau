--!nocheck
-- Serialises built geometry (parts, lights, recorded terrain ops) to JSON for the
-- three.js preview renderer in tools/preview.
local Export = {}

local SHAPES = { Block = "b", Ball = "s", Cylinder = "c", Wedge = "w", CornerWedge = "cw" }

local function safe(f, default)
	local ok, v = pcall(f)
	if ok then
		return v
	end
	return default
end

local function round(n)
	return math.floor(n * 1000 + 0.5) / 1000
end

function Export.collect(root, out)
	out = out or { parts = {}, lights = {} }
	local nodes = root:GetDescendants()
	table.insert(nodes, root)
	for _, inst in nodes do
		if inst:IsA("BasePart") then
			local transparency = safe(function()
				return inst.Transparency
			end, 0)
			if transparency < 0.98 and inst.Name ~= "Terrain" then
				local shape = "b"
				if inst:IsA("WedgePart") then
					shape = "w"
				elseif inst:IsA("CornerWedgePart") then
					shape = "cw"
				elseif inst:IsA("Part") then
					local s = safe(function()
						return inst.Shape.Name
					end, "Block")
					shape = SHAPES[s] or "b"
				end
				if shape == "b" then
					local mesh = inst:FindFirstChildOfClass("SpecialMesh")
					if mesh and safe(function()
						return mesh.MeshType.Name
					end, "") == "Sphere" then
						shape = "e"
					end
				end
				local cf, size, color = inst.CFrame, inst.Size, inst.Color
				local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
				table.insert(out.parts, {
					k = shape,
					p = { round(x), round(y), round(z) },
					r = {
						round(r00),
						round(r01),
						round(r02),
						round(r10),
						round(r11),
						round(r12),
						round(r20),
						round(r21),
						round(r22),
					},
					z = { round(size.X), round(size.Y), round(size.Z) },
					c = {
						math.floor(color.R * 255 + 0.5),
						math.floor(color.G * 255 + 0.5),
						math.floor(color.B * 255 + 0.5),
					},
					m = safe(function()
						return inst.Material.Name
					end, "Plastic"),
					t = round(transparency),
				})
			end
		elseif inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
			local parent = inst.Parent
			if parent and parent:IsA("BasePart") then
				local p = parent.CFrame.Position
				local c = inst.Color
				table.insert(out.lights, {
					p = { round(p.X), round(p.Y), round(p.Z) },
					c = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) },
					range = safe(function()
						return inst.Range
					end, 8),
					b = safe(function()
						return inst.Brightness
					end, 1),
				})
			end
		end
	end
	return out
end

return Export
