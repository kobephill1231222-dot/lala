--!nocheck
-- Flattens a ScreenGui tree (as built by the real client code in Lune) into screen-space
-- rectangles and text boxes for tools/pixel/rasterize.mjs, which writes a PNG. Lune has no GUI
-- layout engine, so this resolves UDim2 positions/sizes, AnchorPoint, Visible,
-- BackgroundTransparency, ClipsDescendants and sibling ZIndex order itself. Layout objects
-- (UIListLayout etc.) are not simulated: the pixel UI positions everything with offsets.
-- UIScale is applied (it scales its parent's size and every offset below it).
local GuiExport = {}

local function safe(f, default)
	local ok, v = pcall(f)
	if ok and v ~= nil then
		return v
	end
	return default
end

local function color(c)
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

local function intersect(a, b)
	local x0, y0 = math.max(a[1], b[1]), math.max(a[2], b[2])
	local x1, y1 = math.min(a[3], b[3]), math.min(a[4], b[4])
	if x1 <= x0 or y1 <= y0 then
		return nil
	end
	return { x0, y0, x1, y1 }
end

local function uiScaleOf(node)
	for _, child in node:GetChildren() do
		if child:IsA("UIScale") then
			return child.Scale
		end
	end
	return 1
end

local function visit(node, parentAbs, clip, out, k)
	k = k or 1
	if not node:IsA("GuiObject") then
		return
	end
	if not safe(function()
		return node.Visible
	end, true) then
		return
	end
	local size, pos, anchor = node.Size, node.Position, safe(function()
		return node.AnchorPoint
	end, nil)
	local u = uiScaleOf(node)
	local w = (parentAbs[3] * size.X.Scale + size.X.Offset * k) * u
	local h = (parentAbs[4] * size.Y.Scale + size.Y.Offset * k) * u
	local x = parentAbs[1] + parentAbs[3] * pos.X.Scale + pos.X.Offset * k - (anchor and anchor.X or 0) * w
	local y = parentAbs[2] + parentAbs[4] * pos.Y.Scale + pos.Y.Offset * k - (anchor and anchor.Y or 0) * h
	local box = { x, y, x + w, y + h }
	local shown = clip and intersect(box, clip) or (clip == nil and box) or nil
	local transparency = safe(function()
		return node.BackgroundTransparency
	end, 1)
	if shown and transparency < 0.99 then
		table.insert(out.rects, {
			x = shown[1],
			y = shown[2],
			w = shown[3] - shown[1],
			h = shown[4] - shown[2],
			c = color(node.BackgroundColor3),
			a = 1 - transparency,
		})
	end
	if shown and (node:IsA("TextLabel") or node:IsA("TextButton")) and node.Text ~= "" then
		local tt = safe(function()
			return node.TextTransparency
		end, 0)
		if tt < 0.99 then
			table.insert(out.texts, {
				x = box[1],
				y = box[2],
				w = w,
				h = h,
				text = node.Text,
				c = color(node.TextColor3),
				size = if node.TextScaled then h * 0.8 else node.TextSize * k * u,
				align = safe(function()
					return node.TextXAlignment.Name
				end, "Center"),
				clip = clip,
			})
		end
	end
	local childClip = clip
	if safe(function()
		return node.ClipsDescendants
	end, false) then
		childClip = clip and intersect(clip, box) or box
		if not childClip then
			return
		end
	end
	local children = {}
	for i, child in node:GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(
				children,
				{ child = child, z = safe(function()
					return child.ZIndex
				end, 1), i = i }
			)
		end
	end
	table.sort(children, function(a, b)
		if a.z == b.z then
			return a.i < b.i
		end
		return a.z < b.z
	end)
	for _, c in children do
		visit(c.child, { x, y, w, h }, childClip, out, k * u)
	end
end

-- Exports every visible GuiObject under `screenGui` for a screen of width x height pixels.
function GuiExport.collect(screenGui, width, height, out)
	out = out or { w = width, h = height, rects = {}, texts = {} }
	local children = {}
	for i, child in screenGui:GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(children, { child = child, z = child.ZIndex, i = i })
		end
	end
	table.sort(children, function(a, b)
		if a.z == b.z then
			return a.i < b.i
		end
		return a.z < b.z
	end)
	for _, c in children do
		visit(c.child, { 0, 0, width, height }, nil, out)
	end
	return out
end

return GuiExport
