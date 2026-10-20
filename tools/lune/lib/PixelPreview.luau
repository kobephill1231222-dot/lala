--!nocheck
-- Offline previews of pixel art: lays out sprites and canvases on a sheet, builds them as real
-- UI Frames (the same code the game uses), flattens the UI with GuiExport and writes JSON for
-- tools/pixel/rasterize.mjs, which turns it into a PNG.
--
--   local sheet = PixelPreview.new(sb, { width = 640, scale = 3, background = Color3.fromRGB(40, 44, 68) })
--   sheet:sprite("Kai idle", def, 1)          -- one frame of a Sprite def
--   sheet:frames("Kai attack", def)            -- every frame side by side
--   sheet:canvas("Fence", canvas)              -- a Canvas (procedural art)
--   sheet:write("build/art/sheet.json")        -- then: node tools/pixel/rasterize.mjs build/art/sheet.json out.png 2
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local GuiExport = require("./GuiExport")

local PixelPreview = {}
PixelPreview.__index = PixelPreview

function PixelPreview.new(sb, options)
	options = options or {}
	local self = setmetatable({}, PixelPreview)
	self.sb = sb
	self.Sprite = sb.requirePath("ReplicatedStorage/Shared/Pixel/Sprite")
	self.scale = options.scale or 3
	self.width = options.width or 720
	self.gap = options.gap or 10
	self.gui = roblox.Instance.new("ScreenGui")
	self.bg = roblox.Instance.new("Frame")
	self.bg.BackgroundColor3 = options.background or roblox.Color3.fromRGB(40, 44, 68)
	self.bg.BorderSizePixel = 0
	self.bg.Parent = self.gui
	self.x, self.y, self.rowH = self.gap, self.gap, 0
	return self
end

local function label(parent, text, x, y, w)
	local l = roblox.Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = 8
	l.TextColor3 = roblox.Color3.fromRGB(230, 230, 240)
	l.TextXAlignment = roblox.Enum.TextXAlignment.Left
	l.Position = roblox.UDim2.fromOffset(x, y)
	l.Size = roblox.UDim2.fromOffset(w, 10)
	l.Parent = parent
end

-- Reserves a w x h box (screen pixels) plus a label line; returns its top-left.
function PixelPreview:place(text, w, h)
	local cellW = math.max(w, #text * 6)
	if self.x + cellW > self.width - self.gap and self.x > self.gap then
		self.x = self.gap
		self.y += self.rowH + self.gap
		self.rowH = 0
	end
	local x, y = self.x, self.y
	label(self.bg, text, x, y, cellW)
	self.x += cellW + self.gap
	self.rowH = math.max(self.rowH, h + 12)
	return x, y + 12
end

function PixelPreview:sprite(text, def, frame, options)
	local s = self.scale
	local x, y = self:place(text, def.w * s, def.h * s)
	local o = { scale = s, frame = frame or 1 }
	if options then
		for k, v in options do
			o[k] = v
		end
	end
	local holder = self.Sprite.build(def, o)
	holder.Position = roblox.UDim2.fromOffset(x, y)
	holder.Parent = self.bg
end

function PixelPreview:frames(text, def, options)
	local s = self.scale
	local n = #def.frames
	local x, y = self:place(text, n * (def.w + 2) * s, def.h * s)
	for i = 1, n do
		local o = { scale = s, frame = i }
		if options then
			for k, v in options do
				o[k] = v
			end
		end
		local holder = self.Sprite.build(def, o)
		holder.Position = roblox.UDim2.fromOffset(x + (i - 1) * (def.w + 2) * s, y)
		holder.Parent = self.bg
	end
end

function PixelPreview:canvas(text, canvas, scale)
	local s = scale or self.scale
	local x0, y0, x1, y1 = canvas:bounds()
	if not x0 then
		return
	end
	local x, y = self:place(text, (x1 - x0) * s, (y1 - y0) * s)
	local holder = roblox.Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = roblox.UDim2.fromOffset(x, y)
	holder.Size = roblox.UDim2.fromOffset((x1 - x0) * s, (y1 - y0) * s)
	holder.Parent = self.bg
	canvas:build(holder, s, x0, y0)
end

function PixelPreview:newRow()
	self.x = self.gap
	self.y += self.rowH + self.gap
	self.rowH = 0
end

-- Writes the sheet as GuiExport JSON; returns (width, height).
function PixelPreview:write(path)
	local h = self.y + self.rowH + self.gap
	self.bg.Size = roblox.UDim2.fromOffset(self.width, h)
	local dir = string.match(path, "^(.*)/[^/]+$")
	if dir then
		fs.writeDir(dir)
	end
	fs.writeFile(path, serde.encode("json", GuiExport.collect(self.gui, self.width, h)))
	return self.width, h
end

return PixelPreview
