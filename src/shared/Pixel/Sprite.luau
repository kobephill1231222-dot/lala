--!strict
-- Pixel-art sprites drawn with plain UI Frames, so the game needs no uploaded images.
--
-- A sprite is written as text: one string per row, one character per pixel, and a palette that
-- maps characters to colours ("." and " " are transparent). Several frames make an animation.
--
--   Sprite.define({
--       palette = { k = Color3.fromRGB(20, 18, 26), s = Color3.fromRGB(240, 200, 170) },
--       frames = { { "..kk..", ".kssk.", ... } },
--       anchor = { 3, 6 },  -- pixel that sits on the sprite's position (default: bottom middle)
--   })
--
-- Building a sprite merges same-coloured pixels into as few rectangles as it can (runs along
-- each row, then identical runs stacked down the rows), so a 16x16 character is usually a few
-- dozen Frames, not 256. Every Frame sits on whole screen pixels at an integer scale, so the
-- art stays crisp.

local Sprite = {}

export type Palette = { [string]: Color3 }
export type Rect = { x: number, y: number, w: number, h: number, key: string }
export type Def = {
	w: number,
	h: number,
	palette: Palette,
	frames: { { string } },
	rects: { { Rect } }, -- merged rectangles per frame (computed once)
	anchor: { number },
	name: string?,
}
export type Spec = {
	palette: Palette,
	frames: { { string } },
	anchor: { number }?,
	name: string?,
}

local TRANSPARENT = { ["."] = true, [" "] = true }

-- Merges one frame's pixels into rectangles: horizontal runs first, then runs with the same
-- columns and colour on consecutive rows join into one taller rectangle.
function Sprite.merge(rows: { string }): { Rect }
	local out: { Rect } = {}
	local open: { [string]: Rect } = {} -- run key "x:w:c" -> rectangle still growing downward
	for y, row in rows do
		local nextOpen: { [string]: Rect } = {}
		local x = 1
		local width = #row
		while x <= width do
			local c = string.sub(row, x, x)
			local stop = x
			while stop < width and string.sub(row, stop + 1, stop + 1) == c do
				stop += 1
			end
			if not TRANSPARENT[c] then
				local key = x .. ":" .. (stop - x + 1) .. ":" .. c
				local grow = open[key]
				if grow then
					grow.h += 1
					nextOpen[key] = grow
				else
					local rect: Rect = { x = x - 1, y = y - 1, w = stop - x + 1, h = 1, key = c }
					table.insert(out, rect)
					nextOpen[key] = rect
				end
			end
			x = stop + 1
		end
		open = nextOpen
	end
	return out
end

function Sprite.define(spec: Spec): Def
	local first = spec.frames[1]
	assert(first and #first > 0, "sprite needs at least one frame")
	local h = #first
	local w = 0
	for _, row in first do
		w = math.max(w, #row)
	end
	local rects = {}
	for i, frame in spec.frames do
		assert(
			#frame == h,
			string.format("%s frame %d has %d rows, expected %d", spec.name or "sprite", i, #frame, h)
		)
		for r, row in frame do
			assert(
				#row == w,
				string.format(
					"%s frame %d row %d is %d wide, expected %d",
					spec.name or "sprite",
					i,
					r,
					#row,
					w
				)
			)
			for c = 1, #row do
				local ch = string.sub(row, c, c)
				assert(
					TRANSPARENT[ch] or spec.palette[ch],
					string.format("%s: colour '%s' not in palette", spec.name or "sprite", ch)
				)
			end
		end
		rects[i] = Sprite.merge(frame)
	end
	return {
		w = w,
		h = h,
		palette = spec.palette,
		frames = spec.frames,
		rects = rects,
		anchor = spec.anchor or { math.floor(w / 2), h },
		name = spec.name,
	}
end

-- Number of Frames one frame of the sprite costs.
function Sprite.cost(def: Def, frame: number?): number
	return #def.rects[frame or 1]
end

export type Options = {
	scale: number, -- screen pixels per art pixel (a whole number)
	frame: number?,
	flip: boolean?, -- mirror left-right
	palette: Palette?, -- colour overrides (e.g. a player's shirt colour)
	zindex: number?,
	name: string?,
}

-- Builds one frame of a sprite as a Frame holding its rectangles. The holder is sized to the
-- sprite; position it by its anchor with Sprite.place.
function Sprite.build(def: Def, options: Options): Frame
	local scale = options.scale
	local holder = Instance.new("Frame")
	holder.Name = options.name or def.name or "Sprite"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromOffset(def.w * scale, def.h * scale)
	holder.ZIndex = options.zindex or 1
	Sprite.paint(holder, def, options)
	return holder
end

-- Replaces a holder's rectangles with another frame (or palette) of the same sprite.
function Sprite.paint(holder: Frame, def: Def, options: Options)
	for _, child in holder:GetChildren() do
		if child:IsA("Frame") and child.Name == "Px" then
			child:Destroy()
		end
	end
	local scale = options.scale
	local palette = options.palette
	local rects = def.rects[options.frame or 1] or def.rects[1]
	for _, r in rects do
		local px = Instance.new("Frame")
		px.Name = "Px"
		px.BorderSizePixel = 0
		px.BackgroundColor3 = (palette and palette[r.key]) or def.palette[r.key]
		local x = if options.flip then def.w - r.x - r.w else r.x
		px.Position = UDim2.fromOffset(x * scale, r.y * scale)
		px.Size = UDim2.fromOffset(r.w * scale, r.h * scale)
		px.ZIndex = options.zindex or 1
		px.Parent = holder
	end
end

-- Puts a built sprite so its anchor pixel lands on screen point (x, y) (whole pixels).
function Sprite.place(holder: Frame, def: Def, x: number, y: number, scale: number, flip: boolean?)
	local ax = if flip then def.w - def.anchor[1] else def.anchor[1]
	holder.Position =
		UDim2.fromOffset(math.floor(x - ax * scale + 0.5), math.floor(y - def.anchor[2] * scale + 0.5))
end

-- Builds every animation frame of a sprite once, as sibling holders ("F1", "F2", ...) inside
-- one container, so animating is just switching Visible (no Frames created or destroyed while
-- playing). Show a frame with Sprite.show.
function Sprite.frames(def: Def, options: Options): Frame
	local container = Instance.new("Frame")
	container.Name = options.name or def.name or "Sprite"
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Size = UDim2.fromOffset(def.w * options.scale, def.h * options.scale)
	container.ZIndex = options.zindex or 1
	for i = 1, #def.frames do
		local frameOptions = table.clone(options)
		frameOptions.frame = i
		frameOptions.name = "F" .. i
		local holder = Sprite.build(def, frameOptions)
		holder.Visible = i == 1
		holder.Parent = container
	end
	container:SetAttribute("Frame", 1)
	return container
end

-- Shows frame `n` of a container made by Sprite.frames (cheap when it's already showing).
function Sprite.show(container: Frame, n: number)
	local current = container:GetAttribute("Frame")
	if current == n then
		return
	end
	local old = container:FindFirstChild("F" .. tostring(current))
	local new = container:FindFirstChild("F" .. n)
	if new and new:IsA("GuiObject") then
		if old and old:IsA("GuiObject") then
			old.Visible = false
		end
		new.Visible = true
		container:SetAttribute("Frame", n)
	end
end

-- Turns a frame's rows 180 degrees (for things drawn facing the other way).
function Sprite.rotate180(rows: { string }): { string }
	local out = table.create(#rows)
	for i = #rows, 1, -1 do
		table.insert(out, string.reverse(rows[i]))
	end
	return out
end

-- Mirrors a frame's rows left-right.
function Sprite.mirror(rows: { string }): { string }
	local out = table.create(#rows)
	for _, row in rows do
		table.insert(out, string.reverse(row))
	end
	return out
end

return Sprite
