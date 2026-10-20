--!nonstrict
-- Pixel-art interface kit: bevelled boxes, buttons, windows, progress bars, rarity badges,
-- icons, portraits and pixel text, all drawn with plain Frames in Shared/Pixel/Palette colours
-- and Client/Pixel/Text (Arcade). Sizes are in art pixels: a container's whole-number UIScale
-- (UIController sets it) blows them up, so every art pixel covers S x S screen pixels.
--
-- Bevels: a box is its outline colour, with three rectangles inside it (light, dark, fill) so
-- the top-left edge shows light and the bottom-right edge shows dark. Bevel rectangles sit at
-- ZIndex 1 inside the box; content goes at ZIndex 2 (the default of every helper here).
--
-- The old helper names and signatures are kept (UIKit.button, panel, bar, viewport, ...) so
-- other modules keep working; the 3D/vector-only ones (corner, round, gradient) are inert now.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarities = require(Shared.Config.Rarities)
local Palette = require(Shared.Pixel.Palette)
local Sprite = require(Shared.Pixel.Sprite)
local Icons = require(Shared.Pixel.Art.Icons)
local CrateArt = require(Shared.Pixel.Art.Crates)
local Characters = require(Shared.Pixel.Art.Characters)
local Text = require(script.Parent.Parent.Pixel.Text)
local Theme = require(script.Parent.Theme)

local UIKit = {}

UIKit.Theme = Theme
UIKit.Palette = Palette
UIKit.Text = Text

-- Optional hook so every button can click without UIKit depending on the sound system.
UIKit.onClick = nil :: (() -> ())?

local P = Palette
local fromOffset = UDim2.fromOffset

UIKit.Z = 2 -- content ZIndex inside a bevelled box
UIKit.LineHeight = 9 -- one 8-pixel text line plus a pixel of leading

-- Colour sets: fill, light edge (top-left), dark edge (bottom-right), outline, text.
UIKit.Styles = {
	primary = { fill = P.Orchid, light = P.Rose, dark = P.Plum, edge = P.Ink, text = P.White },
	gold = { fill = P.Amber, light = P.Yellow, dark = P.Orange, edge = P.Brown, text = P.Ink },
	cash = { fill = P.Grass, light = P.Leaf, dark = P.Pine, edge = P.Ink, text = P.White },
	red = { fill = P.Red, light = P.Rose, dark = P.Crimson, edge = P.Ink, text = P.White },
	secondary = { fill = P.Dusk, light = P.Steel, dark = P.Night, edge = P.Ink, text = P.White },
	danger = { fill = P.Crimson, light = P.Red, dark = P.DarkBrown, edge = P.Ink, text = P.White },
	seal = { fill = P.Hot, light = P.Rose, dark = P.Crimson, edge = P.Ink, text = P.White },
	disabled = { fill = P.Night, light = P.Dusk, dark = P.Ink, edge = P.Ink, text = P.Steel },
	-- Surfaces
	window = { fill = P.Night, light = P.Dusk, dark = P.Ink, edge = P.Ink, text = P.White },
	card = { fill = P.Night, light = P.Steel, dark = P.Dusk, edge = P.Ink, text = P.White },
	well = { fill = P.Night, light = P.Ink, dark = P.Dusk, edge = P.Ink, text = P.White },
	row = { fill = P.Dusk, light = P.Steel, dark = P.Night, edge = P.Ink, text = P.White },
	rowSelected = { fill = P.Steel, light = P.Slate, dark = P.Dusk, edge = P.Amber, text = P.White },
	carry = { fill = P.Plum, light = P.Orchid, dark = P.Night, edge = P.Ink, text = P.White },
}

-- Generic plumbing ------------------------------------------------------------------------

-- new("Frame", { Size = ..., [child] }) : string keys are properties (functions connect to
-- the event of that name), integer keys are children.
function UIKit.new(className: string, props: any?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if type(key) == "number" then
				value.Parent = inst
			elseif key == "Parent" then
				parent = value
			elseif type(value) == "function" then
				(inst :: any)[key]:Connect(value)
			else
				(inst :: any)[key] = value
			end
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local new = UIKit.new

-- Rounded corners and gradients don't exist in pixel art: these return an inert marker so
-- old callers still work (nothing is drawn).
local function inert(name: string): Instance
	local marker = Instance.new("Folder")
	marker.Name = name
	return marker
end

function UIKit.corner(_radius: number?): Instance
	return inert("SquareCorner")
end

function UIKit.round(): Instance
	return inert("SquareCorner")
end

function UIKit.gradient(_a: Color3, _b: Color3, _rotation: number?): Instance
	return inert("FlatColour")
end

-- A border of whole-pixel edges (inside the parent's box) in the nearest palette colour.
function UIKit.stroke(color: Color3?, thickness: number?, transparency: number?): Frame
	local t = math.max(1, math.floor((thickness or 1) + 0.5))
	local c = P.nearest(color or Theme.StrokeSoft)
	local alpha = transparency or 0
	local border = new("Frame", {
		Name = "Border",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = UIKit.Z + 1,
	})
	local edges = {
		{ UDim2.new(), UDim2.new(1, 0, 0, t) },
		{ UDim2.new(0, 0, 1, -t), UDim2.new(1, 0, 0, t) },
		{ UDim2.new(0, 0, 0, t), UDim2.new(0, t, 1, -2 * t) },
		{ UDim2.new(1, -t, 0, t), UDim2.new(0, t, 1, -2 * t) },
	}
	for _, e in edges do
		new("Frame", {
			Parent = border,
			Position = e[1],
			Size = e[2],
			BackgroundColor3 = c,
			BackgroundTransparency = alpha,
			BorderSizePixel = 0,
			ZIndex = UIKit.Z + 1,
		})
	end
	return border
end

function UIKit.padding(all: number, horizontal: number?): UIPadding
	local h = UDim.new(0, horizontal or all)
	local v = UDim.new(0, all)
	return new("UIPadding", { PaddingLeft = h, PaddingRight = h, PaddingTop = v, PaddingBottom = v })
end

function UIKit.list(
	direction: Enum.FillDirection?,
	padding: number?,
	hAlign: Enum.HorizontalAlignment?,
	vAlign: Enum.VerticalAlignment?
): UIListLayout
	return new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 2),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function UIKit.tween(
	inst: Instance,
	seconds: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(
		inst,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	tween:Play()
	return tween
end

-- Pixel primitives --------------------------------------------------------------------------

-- A solid rectangle in art pixels.
function UIKit.rect(
	parent: Instance?,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3,
	name: string?,
	z: number?
): Frame
	local f = Instance.new("Frame")
	f.Name = name or "Px"
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.Position = fromOffset(x, y)
	f.Size = fromOffset(math.max(0, w), math.max(0, h))
	f.ZIndex = z or UIKit.Z
	f.Parent = parent
	return f
end
local rect = UIKit.rect

local function styleOf(style: any): any
	if type(style) == "string" then
		return UIKit.Styles[style] or UIKit.Styles.secondary
	end
	return style or UIKit.Styles.secondary
end

-- Paints a bevel into `frame` (w x h art pixels; nil sizes follow the frame's own size).
function UIKit.paint(frame: GuiObject, w: number?, h: number?, style: any)
	local s = styleOf(style)
	frame.BorderSizePixel = 0
	frame.BackgroundTransparency = 0
	if frame.BackgroundColor3 ~= s.edge then
		frame.BackgroundColor3 = s.edge
	end
	if w and h then
		local size = fromOffset(w, h)
		if frame.Size ~= size then
			frame.Size = size
		end
	end
	-- { name, top-left inset, colour, size reduction }: light covers everything inside the
	-- outline, dark starts a pixel lower-right, fill leaves one pixel of each showing.
	local parts = {
		{ "BvLight", 1, s.light, 2 },
		{ "BvDark", 2, s.dark, 3 },
		{ "BvFill", 2, s.fill, 4 },
	}
	for _, part in parts do
		local f = frame:FindFirstChild(part[1])
		if not f then
			f = rect(frame, 0, 0, 0, 0, part[3], part[1], 1)
		end
		local at, shrink = part[2], part[4]
		f.Position = fromOffset(at, at)
		if w and h then
			f.Size = fromOffset(math.max(0, w - shrink), math.max(0, h - shrink))
		else
			f.Size = UDim2.new(1, -shrink, 1, -shrink)
		end
		if f.BackgroundColor3 ~= part[3] then
			f.BackgroundColor3 = part[3]
		end
	end
end
local paint = UIKit.paint

-- A bevelled box at (x, y), w x h. `class` "TextButton" makes it clickable.
function UIKit.box(
	parent: Instance?,
	x: number,
	y: number,
	w: number,
	h: number,
	style: any,
	class: string?,
	name: string?
): any
	local f = Instance.new(class or "Frame")
	f.Name = name or "Box"
	f.Position = fromOffset(x, y)
	f.Size = fromOffset(w, h)
	f.ZIndex = UIKit.Z
	if f:IsA("TextButton") then
		f.Text = ""
		f.AutoButtonColor = false
	end
	paint(f, w, h, style)
	f.Parent = parent
	return f
end

-- Pixel text ---------------------------------------------------------------------------------

export type LabelOptions = {
	color: Color3?,
	size: number?, -- 8 or 16
	align: Enum.TextXAlignment?,
	width: number?,
	name: string?,
	z: number?,
	shadow: Color3?,
	noShadow: boolean?,
}

-- One line of pixel text with its drop shadow, top-left at (x, y). Returns the holder.
function UIKit.label(parent: Instance?, text: string, x: number, y: number, options: LabelOptions?): Frame
	local o = options or {}
	local holder = Text.new(parent, text, {
		color = o.color,
		size = o.size,
		align = o.align,
		width = o.width,
		name = o.name,
		zindex = o.z or UIKit.Z,
		shadow = o.shadow,
		noShadow = o.noShadow,
	})
	holder.Position = fromOffset(x, y)
	return holder
end

-- Changes a label's text (and colour).
function UIKit.setLabel(holder: Instance, text: string, color: Color3?)
	Text.set(holder, text, color)
end

-- Width in art pixels of `text` at size 8 (or 16).
function UIKit.textWidth(text: string, size: number?): number
	return Text.width(text, size)
end

local NBSP = utf8.char(160)

local function len(text: string): number
	return utf8.len(text) or #text
end

-- Splits text into lines of at most `maxChars` characters, on spaces where possible.
-- Explicit "\n" breaks are kept, a line that already fits keeps its own spacing, and a
-- non-breaking space (U+00A0, UIKit.NBSP) keeps two words together (it prints as a space).
UIKit.NBSP = NBSP
function UIKit.wrap(text: string, maxChars: number): { string }
	local lines: { string } = {}
	maxChars = math.max(1, maxChars)
	for _, paragraph in string.split(text, "\n") do
		if len(paragraph) <= maxChars then
			table.insert(lines, (string.gsub(paragraph, NBSP, " ")))
			continue
		end
		local line = ""
		for word in string.gmatch(paragraph, "%S+") do
			while len(word) > maxChars do
				if line ~= "" then
					table.insert(lines, line)
					line = ""
				end
				local cut = utf8.offset(word, maxChars + 1) or (#word + 1)
				table.insert(lines, string.sub(word, 1, cut - 1))
				word = string.sub(word, cut)
			end
			if line == "" then
				line = word
			elseif len(line) + 1 + len(word) <= maxChars then
				line ..= " " .. word
			else
				table.insert(lines, line)
				line = word
			end
		end
		table.insert(lines, line)
	end
	for i, line in lines do
		lines[i] = (string.gsub(line, NBSP, " "))
	end
	return lines
end

export type Para = {
	holder: Frame,
	lines: { Frame },
	set: (text: string, color: Color3?) -> number,
	count: number,
}

-- A block of up to `maxLines` wrapped lines at (x, y), `width` art pixels wide. The line
-- labels are made once; :set rewraps the text into them (returns the line count).
function UIKit.para(
	parent: Instance?,
	x: number,
	y: number,
	width: number,
	maxLines: number,
	options: LabelOptions?
): Para
	local o = options or {}
	local size = o.size or 8
	local step = size + 1
	local holder = Instance.new("Frame")
	holder.Name = o.name or "Para"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Position = fromOffset(x, y)
	holder.Size = fromOffset(width, maxLines * step)
	holder.ZIndex = o.z or UIKit.Z
	local lines = {}
	for i = 1, maxLines do
		local line = UIKit.label(holder, "", 0, (i - 1) * step, {
			color = o.color,
			size = size,
			align = o.align,
			width = width,
			name = "Line" .. i,
			z = o.z,
			shadow = o.shadow,
			noShadow = o.noShadow,
		})
		lines[i] = line
	end
	holder.Parent = parent
	local para: any = { holder = holder, lines = lines, count = 0 }
	para.set = function(text: string, color: Color3?): number
		local wrapped = UIKit.wrap(text, math.floor(width / size))
		local n = math.min(#wrapped, maxLines)
		for i, line in lines do
			Text.set(line, if i <= n then wrapped[i] else "", color)
		end
		para.count = if text == "" then 0 else n
		return para.count
	end
	return para
end

-- Legacy: a TextLabel in the pixel font (size snapped to 8 or 16 art pixels).
function UIKit.text(props: { [any]: any }): TextLabel
	local size = if (props.TextSize or 8) >= 16 then 16 else 8
	local defaults = {
		BackgroundTransparency = 1,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
		RichText = true,
	}
	for k, v in props do
		defaults[k] = v
	end
	defaults.FontFace = Text.Font
	defaults.TextSize = size
	defaults.TextScaled = false
	if typeof(defaults.TextColor3) == "Color3" then
		defaults.TextColor3 = P.nearest(defaults.TextColor3)
	end
	local label = new("TextLabel", defaults)
	new("UITextSizeConstraint", { Parent = label, MinTextSize = size, MaxTextSize = size })
	return label
end

-- Sprites, icons, portraits ---------------------------------------------------------------

-- One frame of a sprite as Frames at whole-number scale `k` (top-left at the holder's origin).
function UIKit.sprite(
	def: any,
	k: number?,
	options: { frame: number?, palette: any?, name: string?, flip: boolean?, z: number? }?
): Frame
	local o = options or {}
	return Sprite.build(def, {
		scale = math.max(1, math.floor(k or 1)),
		frame = o.frame,
		palette = o.palette,
		name = o.name,
		flip = o.flip,
		zindex = o.z or UIKit.Z,
	})
end

-- A transparent `w` x `h` holder with `def` centred in it at the largest whole scale that fits
-- (at least 1).
local function fitted(def: any, w: number, h: number, name: string, palette: any?, frame: number?): Frame
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = fromOffset(w, h)
	holder.ZIndex = UIKit.Z
	local k = math.max(1, math.floor(math.min(w / def.w, h / def.h)))
	local sprite = UIKit.sprite(def, k, { palette = palette, frame = frame, name = "Sprite" })
	sprite.Position = fromOffset(math.floor((w - def.w * k) / 2), math.floor((h - def.h * k) / 2))
	sprite.Parent = holder
	return holder
end

-- An icon from Shared/Pixel/Art/Icons (10x10 art pixels at size 10).
function UIKit.icon(name: string, size: number?): Frame
	local s = size or 10
	return fitted(Icons.get(name), s, s, "Icon")
end

-- Coin icon (Cash).
function UIKit.cashIcon(size: number): Frame
	return fitted(Icons.get("cash"), size, size, "CashIcon")
end

local orbPalettes: { [Color3]: any } = {}

-- Cursed Orb icon, optionally in another colour (snapped to the palette).
function UIKit.orbIcon(size: number, color: Color3?): Frame
	local palette = nil
	if color then
		local c = P.nearest(color)
		palette = orbPalettes[c]
		if not palette then
			palette = {
				k = P.nearest(P.shade(c, 0.5)),
				o = c,
				l = P.nearest(c:Lerp(Color3.new(1, 1, 1), 0.45)),
				w = P.White,
			}
			orbPalettes[c] = palette
		end
	end
	return fitted(Icons.get("orb"), size, size, "OrbIcon", palette)
end

-- Crate glyph in a tier's colours.
function UIKit.crateIcon(tier: string, size: number): Frame
	return fitted(CrateArt.icon(tier), size, size, "CrateIcon")
end

-- The 24x24 portrait of a Sorcerer (the idle sprite while the art has no portraits yet).
function UIKit.portraitDef(characterId: string): any
	local portrait = (Characters :: any).portrait
	if type(portrait) == "function" then
		local ok, def = pcall(portrait, characterId)
		if ok and def then
			return def
		end
	end
	return Characters.sorcerer(characterId).idle
end

local silhouettes: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any

-- Every colour of a sprite turned dark (undiscovered Sorcerers).
function UIKit.silhouette(def: any): any
	local palette = silhouettes[def]
	if not palette then
		palette = {}
		for key in def.palette do
			palette[key] = if key == "k" then P.Ink else P.Night
		end
		silhouettes[def] = palette
	end
	return palette
end

-- A Sorcerer portrait at whole-number scale `k` (top-left at the holder's origin).
function UIKit.portrait(characterId: string, k: number?, silhouette: boolean?): Frame
	local def = UIKit.portraitDef(characterId)
	return UIKit.sprite(def, k, {
		name = "Portrait",
		palette = if silhouette then UIKit.silhouette(def) else nil,
	})
end

-- (Was a 3D ViewportFrame.) A Sorcerer's pixel portrait centred in `size` at the largest
-- whole scale that fits. `silhouette` hides undiscovered units; spin/zoom are ignored.
function UIKit.viewport(
	characterId: string,
	size: UDim2,
	options: { silhouette: boolean?, spin: boolean?, zoom: number? }?
): Frame
	local opts: any = options or {}
	local def = UIKit.portraitDef(characterId)
	local w = if size.X.Offset > 0 then size.X.Offset else def.w * 2
	local h = if size.Y.Offset > 0 then size.Y.Offset else def.h * 2
	local holder = fitted(def, w, h, "Portrait", if opts.silhouette then UIKit.silhouette(def) else nil)
	if size.X.Scale ~= 0 or size.Y.Scale ~= 0 then
		holder.Size = size
	end
	return holder
end

-- (Was a 3D ViewportFrame.) A crate sprite centred in `size`.
function UIKit.crateViewport(tier: string, size: UDim2): Frame
	local def = CrateArt.sprite(tier)
	local w = if size.X.Offset > 0 then size.X.Offset else def.w * 2
	local h = if size.Y.Offset > 0 then size.Y.Offset else def.h * 2
	local holder = fitted(def, w, h, "CrateSprite")
	if size.X.Scale ~= 0 or size.Y.Scale ~= 0 then
		holder.Size = size
	end
	return holder
end

-- A keyboard key: an 11x11 cap with the letter on it (same look as the world prompts).
function UIKit.keycap(parent: Instance?, key: string, x: number?, y: number?, z: number?): Frame
	local zi = z or UIKit.Z
	local cap = rect(nil, x or 0, y or 0, 11, 11, P.Ink, "Keycap", zi)
	rect(cap, 1, 1, 9, 9, P.Mist, "Face", 1)
	rect(cap, 1, 1, 9, 1, P.White, "Light", 1)
	rect(cap, 1, 2, 1, 8, P.White, "LightSide", 1)
	rect(cap, 2, 9, 8, 1, P.Slate, "Dark", 1)
	rect(cap, 9, 2, 1, 7, P.Slate, "DarkSide", 1)
	UIKit.label(cap, string.sub(key, 1, 1), 2, 2, { color = P.Ink, noShadow = true, name = "Key", z = 2 })
	cap.Parent = parent
	return cap
end

-- Flashes a keycap's face (a hotkey was pressed).
function UIKit.flashKeycap(cap: Instance?)
	local face = cap and cap:FindFirstChild("Face")
	if face and face:IsA("Frame") then
		face.BackgroundColor3 = P.Yellow
		task.delay(0.12, function()
			face.BackgroundColor3 = P.Mist
		end)
	end
end

-- Pressable boxes -------------------------------------------------------------------------

export type Pressable = {
	setStyle: (style: any) -> (),
	setEnabled: (enabled: boolean) -> (),
	isEnabled: () -> boolean,
	setSelected: (selected: any) -> (),
	setSize: (w: number, h: number) -> (),
}

-- Wires hover/press visuals onto a bevelled GuiButton: hover lightens the fill, pressing flips
-- the bevel and drops `content` (if given) by one pixel.
function UIKit.pressable(
	button: GuiButton,
	w: number?,
	h: number?,
	style: any,
	content: GuiObject?
): Pressable
	local state = {
		style = styleOf(style),
		hover = false,
		pressed = false,
		enabled = true,
		selected = nil :: any,
		w = w,
		h = h,
	}
	local base = if content then content.Position else nil
	local function repaint()
		local s = if state.enabled then (state.selected or state.style) else UIKit.Styles.disabled
		if state.pressed and state.enabled then
			s = { fill = s.fill, light = s.dark, dark = s.light, edge = s.edge }
		elseif state.hover and state.enabled then
			s = { fill = s.light, light = s.light, dark = s.dark, edge = s.edge }
		end
		paint(button, state.w, state.h, s)
		if content and base then
			content.Position = if state.pressed and state.enabled then base + fromOffset(0, 1) else base
		end
	end
	local function connect(event: string, fn: () -> ())
		pcall(function()
			(button :: any)[event]:Connect(fn)
		end)
	end
	connect("MouseEnter", function()
		-- A tap also "enters" a button and never leaves it: no hover look for touch.
		local ok, last = pcall(function()
			return UserInputService:GetLastInputType()
		end)
		if ok and last == Enum.UserInputType.Touch then
			return
		end
		state.hover = true
		repaint()
	end)
	connect("MouseLeave", function()
		state.hover = false
		state.pressed = false
		repaint()
	end)
	connect("MouseButton1Down", function()
		state.pressed = true
		repaint()
	end)
	connect("MouseButton1Up", function()
		state.pressed = false
		repaint()
	end)
	connect("Activated", function()
		if state.pressed then
			state.pressed = false
			repaint()
		end
	end)
	repaint()
	return {
		setStyle = function(newStyle: any)
			state.style = styleOf(newStyle)
			repaint()
		end,
		setEnabled = function(enabled: boolean)
			if state.enabled ~= enabled then
				state.enabled = enabled
				button.Active = enabled
				repaint()
			end
		end,
		isEnabled = function(): boolean
			return state.enabled
		end,
		setSelected = function(selected: any)
			-- true: the "rowSelected" look; a style: that look; false/nil: the normal style.
			state.selected = if selected == true
				then UIKit.Styles.rowSelected
				elseif selected then styleOf(selected)
				else nil
			repaint()
		end,
		setSize = function(newW: number, newH: number)
			state.w, state.h = newW, newH
			repaint()
		end,
	}
end

-- Buttons -----------------------------------------------------------------------------------

local controls: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any

-- Enables/disables a button made by UIKit.button (greys it out and ignores presses).
function UIKit.setEnabled(button: Instance, value: boolean)
	local c = controls[button]
	if c then
		c.setEnabled(value)
	end
end

function UIKit.isEnabled(button: Instance): boolean
	local c = controls[button]
	return c ~= nil and c.isEnabled()
end

function UIKit.setText(button: Instance, text: string)
	local c = controls[button]
	if c then
		c.setText(text)
	end
end

-- Changes a UIKit.button's colour style ("gold", "cash", "secondary", ...).
function UIKit.setStyle(button: Instance, style: string)
	local c = controls[button]
	if c then
		c.setStyle(style)
	end
end

-- Resizes a fixed-size UIKit.button (art pixels), re-centring its label.
function UIKit.setSize(button: Instance, w: number, h: number)
	local c = controls[button]
	if c and c.setSize then
		c.setSize(w, h)
	end
end

-- A pixel button that works for mouse, touch and gamepad (Activated): a TextButton named
-- "Button" holding a "Label" TextLabel (and its "Shadow"). Sizes are in art pixels (default
-- 64 x 16); text is 8 pixels (16 when textSize >= 16). `icon` puts an Icons sprite before
-- the text.
function UIKit.button(props: {
	text: string,
	style: string?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	onClick: (() -> ())?,
	textSize: number?,
	layoutOrder: number?,
	parent: Instance?,
	icon: string?,
	name: string?,
}): any
	local styleName = props.style or "primary"
	local style = UIKit.Styles[styleName] or UIKit.Styles.primary
	local size = props.size or fromOffset(64, 16)
	local fixed = size.X.Scale == 0 and size.Y.Scale == 0
	local w, h = size.X.Offset, size.Y.Offset
	local tsize = if (props.textSize or 8) >= 16 then 16 else 8
	local enabled = true
	local current = props.text

	local button = Instance.new("TextButton")
	button.Name = props.name or "Button"
	button.AutoButtonColor = false
	button.Text = ""
	button.Size = size
	button.Position = props.position or UDim2.new()
	button.AnchorPoint = props.anchor or Vector2.zero
	button.LayoutOrder = props.layoutOrder or 0
	button.ZIndex = UIKit.Z
	button.Selectable = true
	button:SetAttribute("Text", current)

	-- Content (icon + label) lives in one frame so pressing can drop it by a pixel.
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.BackgroundTransparency = 1
	face.BorderSizePixel = 0
	face.Size = if fixed then fromOffset(w, h) else UDim2.fromScale(1, 1)
	face.ZIndex = UIKit.Z
	face.Parent = button

	local icon: Frame? = nil
	if props.icon then
		local sprite = UIKit.sprite(Icons.get(props.icon), 1, { name = "Icon" })
		sprite.Parent = face
		icon = sprite
	end
	local holder, main = Text.new(nil, current, {
		size = tsize,
		align = Enum.TextXAlignment.Center,
		zindex = UIKit.Z,
	})
	local shadow = holder:FindFirstChild("Shadow") :: TextLabel
	shadow.Parent = face
	main.Name = "Label"
	main.Parent = face
	holder:Destroy()

	local function place()
		local textW = Text.width(current, tsize)
		local iconW = if icon then 12 else 0
		main.Text = current
		shadow.Text = current
		if fixed then
			local x0 = math.floor((w - textW - iconW) / 2)
			local y0 = math.floor((h - tsize) / 2)
			main.Size = fromOffset(textW, tsize)
			main.Position = fromOffset(x0 + iconW, y0)
			shadow.Size = main.Size
			shadow.Position = fromOffset(x0 + iconW + 1, y0 + 1)
			if icon then
				icon.Position = fromOffset(x0, math.floor((h - 10) / 2))
			end
		else
			main.Size = UDim2.new(1, -iconW, 0, tsize)
			main.Position = UDim2.new(0, iconW, 0.5, -tsize // 2)
			shadow.Size = main.Size
			shadow.Position = main.Position + fromOffset(1, 1)
		end
	end

	local press = UIKit.pressable(button, if fixed then w else nil, if fixed then h else nil, style, face)
	local function recolor()
		local s = if enabled then style else UIKit.Styles.disabled
		main.TextColor3 = s.text
		shadow.Visible = s.text ~= P.Ink
	end
	place()
	recolor()

	button.Activated:Connect(function()
		if not enabled then
			return
		end
		if UIKit.onClick then
			UIKit.onClick()
		end
		if props.onClick then
			props.onClick()
		end
	end)
	controls[button] = {
		setEnabled = function(value: boolean)
			enabled = value
			press.setEnabled(value)
			recolor()
		end,
		isEnabled = function(): boolean
			return enabled
		end,
		setText = function(text: string)
			if text ~= current then
				current = text
				button:SetAttribute("Text", text)
				place()
			end
		end,
		setStyle = function(name: string)
			style = UIKit.Styles[name] or style
			press.setStyle(style)
			recolor()
		end,
		setSize = function(newW: number, newH: number)
			if fixed and (newW ~= w or newH ~= h) then
				w, h = newW, newH
				face.Size = fromOffset(w, h)
				press.setSize(w, h)
				place()
			end
		end,
	}
	button.Parent = props.parent
	return button
end

-- Bars and badges --------------------------------------------------------------------------

-- Progress bar (outline, dark well, fill with a one-pixel highlight); returns the frame and a
-- setter (0..1) that snaps the fill to whole pixels.
function UIKit.bar(size: UDim2, color: Color3): (Frame, (number) -> ())
	local c = P.nearest(color)
	local shine = P.nearest(c:Lerp(Color3.new(1, 1, 1), 0.4))
	local fixed = size.X.Scale == 0 and size.Y.Scale == 0
	local w, h = size.X.Offset, size.Y.Offset
	local frame = Instance.new("Frame")
	frame.Name = "Bar"
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = P.Ink
	frame.Size = size
	frame.ZIndex = UIKit.Z
	local well = rect(frame, 1, 1, w - 2, h - 2, P.Night, "Well", 1)
	local fill = rect(frame, 1, 1, 0, h - 2, c, "Fill", 2)
	local hi = rect(fill, 0, 0, 0, 1, shine, "Shine", 1)
	if not fixed then
		well.Size = UDim2.new(1, -2, 1, -2)
		fill.Size = UDim2.new(0, 0, 1, -2)
	end
	hi.Size = UDim2.new(1, 0, 0, 1)
	hi.Visible = (if fixed then h - 2 else 3) >= 3
	local last = -1
	return frame,
		function(alpha: number)
			local a = math.clamp(alpha, 0, 1)
			if fixed then
				local fw = math.floor(a * (w - 2) + 0.5)
				if fw ~= last then
					last = fw
					fill.Size = fromOffset(fw, h - 2)
					fill.Visible = fw > 0
				end
			else
				fill.Size = UDim2.new(a, -2 * a, 1, -2)
				fill.Visible = a > 0
			end
		end
end

-- Rarity chip: the rarity's gem and its name in the rarity colour. `height` 12 (default) or
-- 24 for the double-size chip.
function UIKit.rarityBadge(rarity: string, height: number?): Frame
	local info = Rarities.get(rarity)
	local k = if (height or 12) >= 24 then 2 else 1
	local textColor = if info then P.nearest(info.glow) else P.Mist
	local edge = if info then P.nearest(info.color) else P.Steel
	local name = string.upper(rarity)
	local tsize = 8 * k
	local w = (13 + Text.width(name) + 3) * k
	local h = 12 * k
	local badge = rect(nil, 0, 0, w, h, P.Ink, "RarityBadge", UIKit.Z)
	rect(badge, k, k, w - 2 * k, h - 2 * k, edge, "Edge", 1)
	rect(badge, 2 * k, 2 * k, w - 4 * k, h - 4 * k, P.Night, "Fill", 1)
	local gem = UIKit.sprite(Icons.get("rarity_" .. rarity), k, { name = "Gem" })
	gem.Position = fromOffset(k, k)
	gem.Parent = badge
	local label = UIKit.label(badge, name, 13 * k, 2 * k, { color = textColor, size = tsize, name = "Label" })
	badge:SetAttribute("Rarity", rarity)
	if rarity == "Legendary" or rarity == "Mythic" then
		-- A slow shimmer: the name blinks to white now and then (whole-colour steps only).
		task.defer(function()
			local bright = false
			while badge.Parent do
				bright = not bright
				Text.set(label, name, if bright then P.White else textColor)
				task.wait(if bright then 0.25 else 1.2)
			end
		end)
	end
	return badge
end

-- Windows ----------------------------------------------------------------------------------

UIKit.Window = {
	TitleHeight = 14,
	ContentX = 4,
	ContentY = 19,
	CloseSize = 14,
}

local TITLE_ICONS = {
	Sorcerers = "sorcerers",
	Crates = "crates",
	["Crate Shop"] = "crateShop",
	["Upgrade Shop"] = "upgradeShop",
	Settings = "settings",
}

-- Modal window with a title bar (icon, title, close button) in art pixels. Returns the root,
-- its content frame (at Window.ContentX/ContentY, (w - 8) x (h - 23)) and the root's UIScale
-- (UIController sets it to a whole number).
function UIKit.panel(
	title: string,
	size: Vector2,
	onClose: () -> (),
	iconName: string?
): (Frame, Frame, UIScale)
	local w, h = math.floor(size.X), math.floor(size.Y)
	local root = Instance.new("Frame")
	root.Name = "Panel"
	root.Size = fromOffset(w, h)
	root.ZIndex = UIKit.Z
	paint(root, w, h, UIKit.Styles.window)
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = root

	local bar = rect(root, 2, 2, w - 4, UIKit.Window.TitleHeight, P.Dusk, "Header", 2)
	rect(bar, 0, 0, w - 4, 1, P.Steel, "Shine", 1)
	rect(root, 2, 2 + UIKit.Window.TitleHeight, w - 4, 1, P.Ink, "HeaderLine", 2)
	local icon = iconName or TITLE_ICONS[title]
	local textX = 3
	if icon then
		local sprite = UIKit.sprite(Icons.get(icon), 1, { name = "TitleIcon" })
		sprite.Position = fromOffset(2, 2)
		sprite.Parent = bar
		textX = 15
	end
	UIKit.label(bar, string.upper(title), textX, 3, { name = "Title", color = P.White })

	local closeSize = UIKit.Window.CloseSize
	local close = UIKit.button({
		text = "X",
		style = "red",
		size = fromOffset(closeSize, closeSize),
		position = fromOffset(w - 2 - closeSize, 2),
		onClick = onClose,
		name = "Button",
	})
	close.ZIndex = 3
	close.Parent = root

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Position = fromOffset(UIKit.Window.ContentX, UIKit.Window.ContentY)
	content.Size = fromOffset(w - 2 * UIKit.Window.ContentX, h - UIKit.Window.ContentY - 4)
	content.ZIndex = 2
	content.Parent = root
	return root, content, scale
end

UIKit.ScrollBarWidth = 3 -- art pixels at the right edge of a UIKit.scroller (leave them free)

local thumbs: { [Instance]: () -> () } = setmetatable({}, { __mode = "k" }) :: any

-- A vertical list that scrolls: a ScrollingFrame in art pixels whose scroll bar is drawn in
-- pixels (a dark track and a bevelled thumb, whole art pixels) instead of the engine's
-- rounded bar images. Lay rows out with offsets, keep the right UIKit.ScrollBarWidth pixels
-- free, and set the canvas height with UIKit.setCanvas.
function UIKit.scroller(
	parent: Instance?,
	x: number,
	y: number,
	w: number,
	h: number,
	name: string?
): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.Name = name or "List"
	s.Position = fromOffset(x, y)
	s.Size = fromOffset(w, h)
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 0
	s.TopImage = ""
	s.MidImage = ""
	s.BottomImage = ""
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	s.ElasticBehavior = Enum.ElasticBehavior.Never
	s.CanvasSize = fromOffset(0, h)
	s.ZIndex = UIKit.Z

	-- The bar lives inside the canvas, so it is moved down by the scroll position to stay put.
	local bw = UIKit.ScrollBarWidth
	local track = rect(s, w - bw, 0, bw, h, P.Ink, "ScrollTrack", 50)
	track.Visible = false
	local thumb = rect(track, 0, 0, bw, h, P.Steel, "ScrollThumb", 51)
	rect(thumb, 0, 0, 1, h, P.Slate, "Light", 52).Size = UDim2.new(0, 1, 1, 0)
	local lastTop, lastSize = -1, -1
	local function update()
		local viewH = s.Size.Y.Offset
		local canvasH = s.CanvasSize.Y.Offset
		if canvasH <= viewH then
			track.Visible = false
			return
		end
		local pos = math.clamp(s.CanvasPosition.Y, 0, canvasH - viewH)
		local size = math.max(6, math.floor(viewH * viewH / canvasH + 0.5))
		local top = math.floor((viewH - size) * pos / (canvasH - viewH) + 0.5)
		track.Visible = true
		track.Position = fromOffset(s.Size.X.Offset - bw, math.floor(pos + 0.5))
		track.Size = fromOffset(bw, viewH)
		if top ~= lastTop or size ~= lastSize then
			lastTop, lastSize = top, size
			thumb.Position = fromOffset(0, top)
			thumb.Size = fromOffset(bw, size)
		end
	end
	thumbs[s] = update
	pcall(function()
		s:GetPropertyChangedSignal("CanvasPosition"):Connect(update)
		s:GetPropertyChangedSignal("CanvasSize"):Connect(update)
	end)
	update()
	s.Parent = parent
	return s
end

function UIKit.setCanvas(list: ScrollingFrame, height: number)
	local h = math.max(height, list.Size.Y.Offset)
	if list.CanvasSize.Y.Offset ~= h then
		list.CanvasSize = fromOffset(0, h)
		local update = thumbs[list]
		if update then
			update()
		end
	end
end

return UIKit
