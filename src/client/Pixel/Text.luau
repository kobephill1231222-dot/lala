--!strict
-- Pixel text: Press Start 2P (Enum.Font.Arcade) at multiples of 8, with a one-pixel drop
-- shadow made from an offset copy (TextStroke would blur it). Sizes are in art pixels; the
-- world and the HUD are blown up by a whole-number UIScale, so the glyphs stay on the grid.
-- A UITextSizeConstraint pins the size so the player's Text Size setting can't push it off the
-- 8-pixel grid.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Pixel"):WaitForChild("Palette"))

local Text = {}

Text.Font = Font.fromEnum(Enum.Font.Arcade)
Text.Size = 8 -- one line of text is 8 art pixels tall

export type Options = {
	color: Color3?,
	shadow: Color3?, -- false-y to omit
	noShadow: boolean?,
	size: number?, -- 8 or 16
	align: Enum.TextXAlignment?,
	width: number?, -- box width in art pixels (default: fits the text)
	name: string?,
	zindex: number?,
}

-- Width in art pixels of `text` at size 8 (every glyph is 8 wide).
function Text.width(text: string, size: number?): number
	return (utf8.len(text) or #text) * (size or 8)
end

local function label(parent: Instance?, text: string, color: Color3, size: number, align: Enum.TextXAlignment, width: number, z: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.FontFace = Text.Font
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = align
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextWrapped = false
	l.Size = UDim2.fromOffset(width, size)
	l.ZIndex = z
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = size
	constraint.MaxTextSize = size
	constraint.Parent = l
	l.Parent = parent
	return l
end

-- A text line with a shadow. Returns the holder Frame (position it) and the main label.
function Text.new(parent: Instance?, text: string, options: Options?): (Frame, TextLabel)
	local o = options or {}
	local size = o.size or Text.Size
	local width = o.width or ((utf8.len(text) or #text) * size)
	local align = o.align or Enum.TextXAlignment.Left
	local z = o.zindex or 1
	local holder = Instance.new("Frame")
	holder.Name = o.name or "Text"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromOffset(width + 1, size + 1)
	holder.ZIndex = z
	if not o.noShadow then
		local shadow = label(holder, text, o.shadow or Palette.Ink, size, align, width, z)
		shadow.Name = "Shadow"
		shadow.Position = UDim2.fromOffset(1, 1)
	end
	local main = label(holder, text, o.color or Palette.White, size, align, width, z)
	main.Name = "Main"
	holder.Parent = parent
	return holder, main
end

-- Changes a Text.new holder's text (and its shadow).
function Text.set(holder: Instance, text: string, color: Color3?)
	local main = holder:FindFirstChild("Main")
	local shadow = holder:FindFirstChild("Shadow")
	if main and main:IsA("TextLabel") then
		if main.Text ~= text then
			main.Text = text
		end
		if color and main.TextColor3 ~= color then
			main.TextColor3 = color
		end
	end
	if shadow and shadow:IsA("TextLabel") and shadow.Text ~= text then
		shadow.Text = text
	end
end

-- A label centred on (0, 0): for names and counters over actors.
function Text.centered(parent: Instance?, text: string, width: number, options: Options?): Frame
	local o = table.clone(options or {}) :: Options
	o.width = width
	o.align = Enum.TextXAlignment.Center
	local holder = Text.new(parent, text, o)
	return holder
end

return Text
