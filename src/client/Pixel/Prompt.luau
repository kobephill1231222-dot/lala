--!strict
-- The world prompt: one small pixel panel by whatever you can interact with, like
--
--   [E] COLLECT
--       12 CURSED ORBS
--   [R] PICK UP
--
-- It lives in the front layer (Pixel/Front: the world's art pixels, drawn above the HUD) and is
-- redrawn only when its text changes. Rows are pooled. Each action row has a transparent
-- TextButton over it, so it can be tapped or clicked; keys (E / R, gamepad X / Y) are handled by
-- WorldController. On touch screens action rows have no keycap and look like buttons instead.
-- It goes above its target when that's clear of the HUD, else below it, else beside it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Pixel"):WaitForChild("Palette"))
local Text = require(script.Parent.Text)
local Widgets = require(script.Parent.Widgets)
local Front = require(script.Parent.Front)

local Prompt = {}
Prompt.__index = Prompt

export type Row = {
	key: string?, -- keycap glyph ("E", "R", "X", "Y"); nil for no keycap
	tap: boolean?, -- an action row drawn as a button (touch screens: no keycap)
	id: string?, -- which action the row is ("main", "secondary"), for flash()
	text: string,
	color: Color3?,
	onClick: (() -> ())?,
}

-- Where the target is, in art pixels: the prompt's tail points at (cx, top) from above or at
-- (cx, bottom) from below; beside it, it's centred on the rows between.
export type Target = { cx: number, top: number, bottom: number, left: number, right: number }

export type Placement = "above" | "below" | "right" | "left"

type RowUi = {
	frame: Frame,
	cap: Frame,
	label: Frame,
	back: Frame,
	button: TextButton,
	id: string?,
	onClick: (() -> ())?,
}

export type Prompt = typeof(setmetatable(
	{} :: {
		frame: Frame,
		tail: Frame,
		tailUp: Frame,
		rows: { RowUi },
		signature: string,
		w: number,
		h: number,
		z: number,
		visible: boolean,
		x: number,
		y: number,
		placement: Placement,
		placeKey: string,
	},
	Prompt
))

local PAD = 3
local KEY_ROW = 12
local TEXT_ROW = 9
local KEY_INDENT = 12 -- text after a keycap

-- A 7x4 tail (pointing down, or up when `up`).
local function makeTail(parent: Frame, name: string, z: number, up: boolean): Frame
	local tail = Instance.new("Frame")
	tail.Name = name
	tail.BackgroundTransparency = 1
	tail.BorderSizePixel = 0
	tail.Size = UDim2.fromOffset(7, 4)
	tail.ZIndex = z + 2
	local function row(n: string, x: number, y: number, w: number, color: Color3, zi: number)
		Widgets.rect(tail, n, x, if up then 3 - y else y, w, 1, color, zi)
	end
	row("Edge", 0, 0, 7, Palette.Night, z + 1)
	row("Row1", 0, 0, 1, Palette.Ink, z + 2)
	row("Row1R", 6, 0, 1, Palette.Ink, z + 2)
	row("Row2", 1, 1, 5, Palette.Ink, z + 1)
	row("Row2F", 2, 1, 3, Palette.Night, z + 2)
	row("Row3", 2, 2, 3, Palette.Ink, z + 1)
	row("Row3F", 3, 2, 1, Palette.Night, z + 2)
	row("Row4", 3, 3, 1, Palette.Ink, z + 1)
	tail.Parent = parent
	return tail
end

function Prompt.new(layer: Instance, z: number?): Prompt
	local zi = z or 50
	local frame = Widgets.panel(nil, 20, 16, Widgets.Styles.prompt, zi)
	frame.Name = "Prompt"
	frame.Visible = false
	local tail = makeTail(frame, "Tail", zi, false)
	local tailUp = makeTail(frame, "TailUp", zi, true)
	tailUp.Visible = false
	frame.Parent = layer
	local self = setmetatable({
		frame = frame,
		tail = tail,
		tailUp = tailUp,
		rows = {},
		signature = "",
		w = 20,
		h = 16,
		z = zi,
		visible = false,
		x = 0,
		y = 0,
		placement = "above" :: Placement,
		placeKey = "",
	}, Prompt)
	return self
end

local function newRow(self: Prompt): RowUi
	local z = self.z + 3
	local frame = Instance.new("Frame")
	frame.Name = "Row"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ZIndex = z
	frame.Parent = self.frame
	local back = Widgets.panel(frame, 8, 8, Widgets.Styles.tap, z)
	back.Name = "TapBack"
	back.Visible = false
	local cap = Widgets.keycap(frame, "E", z)
	local label = Widgets.label(frame, "", KEY_INDENT, 2, Palette.White, z + 2)
	local button = Instance.new("TextButton")
	button.Name = "Tap"
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Active = true
	button.Selectable = false -- (keys and gamepad X / Y do the actions, not UI navigation)
	button.ZIndex = z + 5
	button.Parent = frame
	local row: RowUi = {
		frame = frame,
		cap = cap,
		label = label,
		back = back,
		button = button,
		id = nil,
		onClick = nil,
	}
	button.Activated:Connect(function()
		if row.onClick then
			row.onClick()
		end
	end)
	return row
end

-- Shows these rows (rebuilt only when the text changes).
function Prompt.set(self: Prompt, rows: { Row })
	local parts = {}
	for _, row in rows do
		table.insert(
			parts,
			(row.key or "")
				.. "|"
				.. (if row.tap then "T" else "")
				.. "|"
				.. row.text
				.. "|"
				.. tostring(row.color)
		)
	end
	local signature = table.concat(parts, "\n")
	-- Callbacks can change without the text changing.
	for i, row in rows do
		local ui = self.rows[i]
		if ui then
			ui.onClick = row.onClick
			ui.id = row.id
		end
	end
	if signature == self.signature then
		return
	end
	self.signature = signature
	-- Text lines up after the keycaps when there are any.
	local anyKey, anyTap = false, false
	for _, row in rows do
		anyKey = anyKey or row.key ~= nil
		anyTap = anyTap or row.tap == true
	end
	local indent = if anyKey then KEY_INDENT elseif anyTap then 3 else 0
	local y = PAD
	local width = 0
	for i, row in rows do
		local ui = self.rows[i]
		if not ui then
			ui = newRow(self)
			self.rows[i] = ui
		end
		ui.onClick = row.onClick
		ui.id = row.id
		ui.frame.Visible = true
		local text = string.upper(row.text)
		local action = row.key ~= nil or row.tap == true
		local h = if action then KEY_ROW else TEXT_ROW
		ui.frame.Position = UDim2.fromOffset(PAD, y)
		ui.cap.Visible = row.key ~= nil
		if row.key then
			local letter = ui.cap:FindFirstChild("Key")
			if letter then
				Text.set(letter, row.key)
			end
		end
		Widgets.setLabel(ui.label, text, row.color or Palette.White)
		ui.label.Position = UDim2.fromOffset(indent, if action then 2 else 0)
		local rowW = indent + Text.width(text) + 1 + (if row.tap then 3 else 0)
		ui.frame.Size = UDim2.fromOffset(rowW, h)
		ui.back.Visible = row.tap == true
		ui.button.Visible = row.onClick ~= nil
		width = math.max(width, rowW)
		y += h
	end
	for i = #rows + 1, #self.rows do
		self.rows[i].frame.Visible = false
		self.rows[i].onClick = nil
		self.rows[i].id = nil
	end
	local w = width + PAD * 2
	local h = y + PAD - 1
	for i = 1, #rows do
		local ui = self.rows[i]
		local rh = if rows[i].key or rows[i].tap then KEY_ROW else TEXT_ROW
		ui.button.Size = UDim2.fromOffset(w - PAD, rh)
		ui.button.Position = UDim2.fromOffset(-PAD + 1, 0)
		if rows[i].tap then
			Widgets.resize(ui.back, width, rh - 1, Widgets.Styles.tap)
			ui.back.Position = UDim2.fromOffset(0, 0)
		end
	end
	self.w, self.h = w, h
	Widgets.resize(self.frame, w, h, Widgets.Styles.prompt)
end

local ORDER: { Placement } = { "above", "below", "right", "left" }
local SLIDE_STEP = 4 -- art pixels between the sideways positions tried
local PUSH_STEP = 6 -- ... and the positions further from the target
local MAX_PUSH = 48
local KIND_COST: { [string]: number } = { above = 0, below = 24, right = 48, left = 48 }

-- Puts the prompt by `target`, inside the view rectangle (x0, y0, x1, y1), in the first place
-- that's clear of `blockers` (the HUD, in the same art pixels): above, below, right, left.
-- `soft` rectangles (your character) are avoided when it costs little. Returns where it went.
function Prompt.place(
	self: Prompt,
	target: Target,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	blockers: { Front.Rect }?,
	soft: { Front.Rect }?
): Placement
	local w, h = self.w, self.h
	local hard = blockers or {}
	local light = soft or {}
	-- Nothing changed since last frame (standing still): nothing to do.
	local parts = { target.cx, target.top, target.bottom, target.left, target.right, x0, y0, x1, y1, w, h }
	for _, list in { hard, light } do
		for _, r in list do
			table.insert(parts, r.x0)
			table.insert(parts, r.y0)
			table.insert(parts, r.x1)
			table.insert(parts, r.y1)
		end
		table.insert(parts, -1)
	end
	local key = table.concat(parts, ",")
	if key == self.placeKey then
		return self.placement
	end
	self.placeKey = key
	local function clampX(x: number): number
		return math.clamp(x, x0 + 2, math.max(x0 + 2, x1 - w - 2))
	end
	local function clampY(y: number): number
		return math.clamp(y, y0 + 2, math.max(y0 + 2, y1 - h - 2))
	end
	local best: Placement, bestScore, bestX, bestY = "above", math.huge, 0, 0
	local scores: { [string]: { number } } = {}
	local function try(kind: Placement, ux: number, uy: number, slide: number, push: number)
		local x, y = clampX(ux + slide), clampY(uy + push)
		-- Clamping can push the panel off its target; sliding it sideways keeps the tail on it,
		-- and moving it further up (or down) keeps it pointing the right way.
		local moved = math.abs(x - ux - slide) + math.abs(y - uy - push)
		-- (the tail's 4 pixels count as part of the panel)
		local ty0 = if kind == "below" then y - 4 else y
		local ty1 = if kind == "above" then y + h + 4 else y + h
		local score = Front.overlap(hard, x, ty0, x + w, ty1) * 8
			+ Front.overlap(light, x, ty0, x + w, ty1)
			+ moved * 3
			+ math.abs(slide) // 2
			+ math.abs(push) * 2
			+ KIND_COST[kind]
		local seen = scores[kind]
		if not seen or score < seen[1] then
			scores[kind] = { score, x, y }
		end
		if score < bestScore then
			best, bestScore, bestX, bestY = kind, score, x, y
		end
	end
	local maxSlide = math.max(0, math.floor(w / 2) - 6)
	for _, kind in ORDER do
		if kind == "above" or kind == "below" then
			local ux = math.floor(target.cx - w / 2 + 0.5)
			local uy = if kind == "above" then target.top - h - 3 else target.bottom + 4
			local dir = if kind == "above" then -1 else 1
			for push = 0, MAX_PUSH, PUSH_STEP do
				try(kind, ux, uy, 0, push * dir)
				for slide = SLIDE_STEP, maxSlide, SLIDE_STEP do
					try(kind, ux, uy, -slide, push * dir)
					try(kind, ux, uy, slide, push * dir)
				end
			end
		else
			local mid = math.floor((target.top + target.bottom) / 2)
			local ux = if kind == "right" then target.right + 4 else target.left - w - 4
			try(kind, ux, math.floor(mid - h / 2 + 0.5), 0, 0)
		end
	end
	-- Stay put unless somewhere else is clearly better (no flicker while you walk).
	local keep = scores[self.placement]
	if keep and keep[1] <= bestScore + 16 then
		best, bestX, bestY = self.placement, keep[2], keep[3]
	end
	self.placement = best
	if bestX ~= self.x or bestY ~= self.y then
		self.x, self.y = bestX, bestY
		self.frame.Position = UDim2.fromOffset(bestX, bestY)
	end
	-- The tail points at the target, even when the panel is pushed sideways.
	local tx = math.clamp(math.floor(target.cx - bestX) - 3, 1, w - 8)
	self.tail.Visible = best == "above"
	self.tailUp.Visible = best == "below"
	if best == "above" then
		self.tail.Position = UDim2.fromOffset(tx, h - 1)
	elseif best == "below" then
		self.tailUp.Position = UDim2.fromOffset(tx, -3)
	end
	return best
end

function Prompt.setVisible(self: Prompt, visible: boolean)
	if self.visible ~= visible then
		self.visible = visible
		self.frame.Visible = visible
	end
end

-- Briefly lights the row of action `id` ("main" / "secondary") as feedback when pressed.
function Prompt.flash(self: Prompt, id: string)
	for _, ui in self.rows do
		if ui.id == id and ui.frame.Visible then
			Widgets.pressKeycap(ui.cap, true)
			task.delay(0.12, function()
				Widgets.pressKeycap(ui.cap, false)
			end)
		end
	end
end

-- The tap buttons (for tests): row index -> TextButton.
function Prompt.button(self: Prompt, index: number): TextButton?
	local ui = self.rows[index]
	return ui and ui.button
end

-- The art rectangle the prompt covers (x0, y0, x1, y1), for tests.
function Prompt.rect(self: Prompt): (number, number, number, number)
	return self.x, self.y, self.x + self.w, self.y + self.h
end

function Prompt.destroy(self: Prompt)
	self.frame:Destroy()
end

return Prompt
