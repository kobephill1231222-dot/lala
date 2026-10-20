--!strict
-- Small pixel pieces for the world-interaction layer: the bevelled panel and keycap of the
-- world prompt (1-art-pixel Frames in Palette colours, the same look as UI/UIKit's boxes and
-- keycaps), self-fitting text labels, wrapped text, tinted sprite palettes ("translucent"
-- previews), and a HUD root: a ScreenGui whose content is built at art-pixel size under a
-- whole-number UIScale (Screen.scale), so HUD-level cards sit on the world's pixel grid.
--
--   local hud = Widgets.screen("JJKGuide", -1)          -- hud.root is in art pixels
--   local panel = Widgets.panel(hud.root, 120, 40)
--   hud.destroy()                                       -- when it's no longer needed

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared.Pixel.Palette)
local Sprite = require(Shared.Pixel.Sprite)
local Signal = require(Shared.Util.Signal)
local Screen = require(script.Parent.Screen)
local Text = require(script.Parent.Text)

local Widgets = {}

-- Content inside a panel or button goes at this ZIndex or above (the bevel is below it).
Widgets.ContentZ = 3

-- Colour sets: fill, light edge (top-left), dark edge (bottom-right), outline, text.
export type Style = { fill: Color3, light: Color3, dark: Color3, edge: Color3, text: Color3 }

Widgets.Styles = {
	panel = {
		fill = Palette.Night,
		light = Palette.Dusk,
		dark = Palette.Ink,
		edge = Palette.Ink,
		text = Palette.White,
	},
	prompt = {
		fill = Palette.Night,
		light = Palette.Steel,
		dark = Palette.Dusk,
		edge = Palette.Ink,
		text = Palette.White,
	},
	-- An action row of the world prompt on touch screens (a button instead of a keycap).
	tap = {
		fill = Palette.Dusk,
		light = Palette.Slate,
		dark = Palette.Night,
		edge = Palette.Amber,
		text = Palette.White,
	},
	-- A farm's stats board.
	board = {
		fill = Palette.Brown,
		light = Palette.Bark,
		dark = Palette.DarkBrown,
		edge = Palette.Ink,
		text = Palette.Cream,
	},
} :: { [string]: Style }

local function rect(
	parent: Instance,
	name: string,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3,
	z: number
): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(math.max(0, w), math.max(0, h))
	f.ZIndex = z
	f.Parent = parent
	return f
end
Widgets.rect = rect

-- Lays out a bevel (outline, fill, light top-left, dark bottom-right) inside `frame`: five
-- 1-pixel-edged Frames ("BvFill", "BvLight", ...) one ZIndex above the frame's own.
local BEVEL = { "BvFill", "BvLight", "BvLightSide", "BvDark", "BvDarkSide" }

local function bevel(frame: GuiObject, w: number, h: number, style: Style)
	local z = frame.ZIndex
	if not frame:FindFirstChild("BvFill") then
		for _, name in BEVEL do
			rect(frame, name, 0, 0, 0, 0, style.fill, z + 1)
		end
	end
	local function set(name: string, x: number, y: number, rw: number, rh: number, color: Color3)
		local f = frame:FindFirstChild(name) :: Frame
		f.Position = UDim2.fromOffset(x, y)
		f.Size = UDim2.fromOffset(math.max(0, rw), math.max(0, rh))
		if f.BackgroundColor3 ~= color then
			f.BackgroundColor3 = color
		end
	end
	frame.BackgroundColor3 = style.edge
	frame.BackgroundTransparency = 0
	frame.Size = UDim2.fromOffset(w, h)
	set("BvFill", 1, 1, w - 2, h - 2, style.fill)
	set("BvLight", 1, 1, w - 2, 1, style.light)
	set("BvLightSide", 1, 2, 1, h - 3, style.light)
	set("BvDark", 2, h - 2, w - 3, 1, style.dark)
	set("BvDarkSide", w - 2, 2, 1, h - 4, style.dark)
end
Widgets.bevel = bevel

-- A bevelled box. Children go at ZIndex >= Widgets.ContentZ (relative to the panel's own).
function Widgets.panel(parent: Instance?, w: number, h: number, style: Style?, z: number?): Frame
	local f = Instance.new("Frame")
	f.Name = "Panel"
	f.BorderSizePixel = 0
	f.ZIndex = z or 1
	bevel(f, w, h, style or Widgets.Styles.panel)
	f.Parent = parent
	return f
end

function Widgets.resize(panel: GuiObject, w: number, h: number, style: Style?)
	bevel(panel, w, h, style or Widgets.Styles.panel)
end

-- One line of pixel text at (x, y); returns the Text holder.
function Widgets.label(
	parent: Instance?,
	text: string,
	x: number,
	y: number,
	color: Color3?,
	z: number?,
	size: number?
): Frame
	local holder = Text.new(parent, text, { color = color, zindex = z or Widgets.ContentZ, size = size })
	holder.Position = UDim2.fromOffset(x, y)
	return holder
end

-- Changes a label's text and colour and refits its box to the text.
function Widgets.setLabel(holder: Frame, text: string, color: Color3?)
	Text.set(holder, text, color)
	local main = holder:FindFirstChild("Main") :: TextLabel?
	local size = if main then main.TextSize else 8
	local w = Text.width(text, size)
	holder.Size = UDim2.fromOffset(w + 1, size + 1)
	for _, child in holder:GetChildren() do
		if child:IsA("TextLabel") then
			child.Size = UDim2.fromOffset(w, size)
		end
	end
end

-- Splits text into lines of at most `maxChars` characters (on spaces where possible).
function Widgets.wrap(text: string, maxChars: number): { string }
	local lines: { string } = {}
	local line = ""
	for word in string.gmatch(text, "%S+") do
		while #word > maxChars do
			if line ~= "" then
				table.insert(lines, line)
				line = ""
			end
			table.insert(lines, string.sub(word, 1, maxChars))
			word = string.sub(word, maxChars + 1)
		end
		if line == "" then
			line = word
		elseif #line + 1 + #word <= maxChars then
			line ..= " " .. word
		else
			table.insert(lines, line)
			line = word
		end
	end
	if line ~= "" then
		table.insert(lines, line)
	end
	return lines
end

-- A keyboard key: an 11x11 cap with the letter on it.
function Widgets.keycap(parent: Instance?, key: string, z: number?): Frame
	local zi = z or Widgets.ContentZ
	local cap = Instance.new("Frame")
	cap.Name = "Keycap"
	cap.BorderSizePixel = 0
	cap.BackgroundColor3 = Palette.Ink
	cap.Size = UDim2.fromOffset(11, 11)
	cap.ZIndex = zi
	rect(cap, "Face", 1, 1, 9, 9, Palette.Mist, zi + 1)
	rect(cap, "Light", 1, 1, 9, 1, Palette.White, zi + 1)
	rect(cap, "LightSide", 1, 2, 1, 8, Palette.White, zi + 1)
	rect(cap, "Dark", 2, 9, 8, 1, Palette.Slate, zi + 1)
	rect(cap, "DarkSide", 9, 2, 1, 7, Palette.Slate, zi + 1)
	local letter = Text.new(cap, key, { color = Palette.Ink, noShadow = true, zindex = zi + 2, name = "Key" })
	letter.Position = UDim2.fromOffset(2, 2)
	cap.Parent = parent
	return cap
end

-- Shows a keycap pressed (face darker) or released.
function Widgets.pressKeycap(cap: Frame, pressed: boolean)
	local face = cap:FindFirstChild("Face") :: Frame?
	if face then
		face.BackgroundColor3 = if pressed then Palette.Yellow else Palette.Mist
	end
end

-- A sprite's palette pulled toward `toward` by `amount` (0..1), snapped back onto the palette:
-- ghosts and previews ("translucent" without real transparency).
function Widgets.tint(def: Sprite.Def, toward: Color3, amount: number): Sprite.Palette
	local out: Sprite.Palette = {}
	for key, color in def.palette do
		out[key] = Palette.nearest(color:Lerp(toward, amount))
	end
	return out
end

-- HUD root ------------------------------------------------------------------------------

export type Hud = {
	gui: ScreenGui,
	root: Frame, -- art-pixel space (w x h), blown up by a UIScale of Screen.scale
	w: number,
	h: number,
	Changed: any, -- Signal (w, h): fired when the art size changes
	destroy: () -> (), -- disconnects it from Screen.Changed and destroys the gui
}

-- A ScreenGui for HUD-level pixel screens. Its root is in art pixels.
function Widgets.screen(name: string, displayOrder: number, ignoreInset: boolean?): Hud
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = ignoreInset == true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = root
	local connections: { any } = {}
	local hud: Hud
	hud = {
		gui = gui,
		root = root,
		w = 0,
		h = 0,
		Changed = Signal.new(),
		destroy = function()
			for _, c in connections do
				c:Disconnect()
			end
			table.clear(connections)
			hud.Changed:DisconnectAll()
			gui:Destroy()
		end,
	}
	local function fit()
		local s = math.max(1, Screen.scale)
		local ok, measured = pcall(function()
			return gui.AbsoluteSize
		end)
		local size = if ok and measured.X >= 1 and measured.Y >= 1 then measured else Screen.size
		if not gui.IgnoreGuiInset then
			local insetOk, inset = pcall(function()
				return GuiService:GetGuiInset()
			end)
			if (not ok or measured.Y < 1) and insetOk then
				size = Vector2.new(size.X, size.Y - inset.Y)
			end
		end
		local w, h = math.floor(size.X / s), math.floor(size.Y / s)
		scale.Scale = s
		root.Size = UDim2.fromOffset(w, h)
		if w ~= hud.w or h ~= hud.h then
			hud.w, hud.h = w, h
			hud.Changed:Fire(w, h)
		end
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	table.insert(connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit))
	local screenChanged: any = Screen.Changed
	table.insert(connections, screenChanged:Connect(fit))
	fit()
	return hud
end

return Widgets
