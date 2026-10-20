--!strict
-- A sprite that lives in the world: Sorcerers, Crates, players. It holds every animation
-- (each built once with Sprite.frames, optionally mirrored), sits on its anchor point in art
-- pixels, and keeps itself y-sorted against other actors (lower on screen draws in front).
--
--   local a = Actor.new(Screen.layers.Actors, { idle = def, walk = def2 }, { flip = true })
--   a:moveTo(px, py); a:play("idle", 2); a:attach("Label", label, 0, -22)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sprite = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Pixel"):WaitForChild("Sprite"))

local Actor = {}
Actor.__index = Actor

export type Actor = typeof(setmetatable(
	{} :: {
		frame: Frame, -- the actor's anchor point; everything it shows is inside
		defs: { [string]: any },
		containers: { [string]: Frame },
		state: string?,
		frame: number,
		flip: boolean,
		x: number,
		y: number,
		zBias: number,
		attachments: { [string]: { gui: GuiObject, dx: number, dy: number } },
	},
	Actor
))

export type Options = {
	flip: boolean?, -- mirror every animation (faces left instead of right)
	mirrors: { [string]: string }?, -- extra mirrored copies: { newState = "sourceState" }
	name: string?,
	zBias: number?, -- breaks ties when two actors stand on the same row
	palette: { [string]: Color3 }?,
}

function Actor.new(layer: Instance, defs: { [string]: any }, options: Options?): Actor
	local o = options or {}
	local holder = Instance.new("Frame")
	holder.Name = o.name or "Actor"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromOffset(0, 0)
	local self = setmetatable({
		frame = holder,
		defs = table.clone(defs),
		containers = {},
		state = nil,
		frame = 1,
		flip = o.flip == true,
		x = 0,
		y = 0,
		zBias = o.zBias or 0,
		attachments = {},
	}, Actor)
	local function add(name: string, def: any, flip: boolean)
		local container = Sprite.frames(def, { scale = 1, flip = flip, palette = o.palette, name = name })
		container.Visible = false
		-- Anchor pixel at the actor's origin.
		local ax = if flip then def.w - def.anchor[1] else def.anchor[1]
		container.Position = UDim2.fromOffset(-ax, -def.anchor[2])
		container.Parent = holder
		self.containers[name] = container
	end
	for name, def in defs do
		add(name, def, self.flip)
	end
	for name, source in o.mirrors or {} do
		local def = defs[source]
		if def then
			add(name, def, not self.flip)
			self.defs[name] = def
		end
	end
	holder.Parent = layer
	return self
end

-- Shows animation `state` at frame `frame` (cheap if nothing changes).
function Actor.play(self: Actor, state: string, frame: number?)
	local f = frame or 1
	if self.state ~= state then
		if self.state and self.containers[self.state] then
			self.containers[self.state].Visible = false
		end
		local container = self.containers[state]
		if not container then
			return
		end
		container.Visible = true
		self.state = state
	end
	local def = self.defs[state]
	local n = if def then #def.frames else 1
	local wrapped = ((f - 1) % n) + 1
	Sprite.show(self.containers[state], wrapped)
	self.frame = wrapped
end

-- Puts the actor's anchor on art pixel (x, y) and re-sorts it by y.
function Actor.moveTo(self: Actor, x: number, y: number)
	x, y = math.floor(x + 0.5), math.floor(y + 0.5)
	if x == self.x and y == self.y and self.frame.Parent ~= nil and self.frame:GetAttribute("Placed") then
		return
	end
	self.frame:SetAttribute("Placed", true)
	self.x, self.y = x, y
	self.frame.Position = UDim2.fromOffset(x, y)
	local z = y * 4 + self.zBias
	if self.frame.ZIndex ~= z then
		self.frame.ZIndex = z
	end
end

-- Keeps a GuiObject (label, bar, prompt) at an offset from the actor's anchor.
function Actor.attach(self: Actor, name: string, gui: GuiObject, dx: number, dy: number)
	gui.Position = UDim2.fromOffset(dx, dy)
	gui.Parent = self.frame
	self.attachments[name] = { gui = gui, dx = dx, dy = dy }
end

function Actor.attachment(self: Actor, name: string): GuiObject?
	local a = self.attachments[name]
	return a and a.gui
end

function Actor.setVisible(self: Actor, visible: boolean)
	self.frame.Visible = visible
end

function Actor.destroy(self: Actor)
	self.frame:Destroy()
end

return Actor
