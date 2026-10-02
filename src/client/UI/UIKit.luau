--!nonstrict
-- Small declarative helpers and reusable components for the interface.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sorcerers = require(Shared.Config.Sorcerers)
local Crates = require(Shared.Config.Crates)
local Rarities = require(Shared.Config.Rarities)
local CharacterModels = require(Shared.Visuals.CharacterModels)
local CrateModels = require(Shared.Visuals.CrateModels)
local Theme = require(script.Parent.Theme)

local UIKit = {}

UIKit.Theme = Theme

-- Optional hook so every button can click without UIKit depending on the sound system.
UIKit.onClick = nil :: (() -> ())?

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

function UIKit.corner(radius: number?): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Corner) })
end

function UIKit.round(): UICorner
	return new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function UIKit.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return new("UIStroke", {
		Color = color or Theme.StrokeSoft,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
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
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function UIKit.gradient(a: Color3, b: Color3, rotation: number?): UIGradient
	return new("UIGradient", { Color = ColorSequence.new(a, b), Rotation = rotation or 90 })
end

function UIKit.text(props: { [any]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		FontFace = Theme.Body,
		TextColor3 = Theme.Text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
		RichText = true,
	}
	for k, v in props do
		defaults[k] = v
	end
	return new("TextLabel", defaults)
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

local BUTTON_STYLES = {
	primary = { Theme.Violet, Theme.VioletDark, Theme.Text },
	gold = { Theme.Gold, Theme.GoldDark, Color3.fromRGB(40, 24, 10) },
	cash = { Theme.Cash, Theme.CashDark, Color3.fromRGB(10, 36, 16) },
	red = { Theme.Red, Theme.RedDark, Theme.Text },
	secondary = { Theme.PanelLighter, Theme.PanelLight, Theme.Text },
	danger = { Color3.fromRGB(220, 80, 96), Color3.fromRGB(140, 40, 56), Theme.Text },
	seal = { Theme.Seal, Color3.fromRGB(150, 30, 60), Theme.Text },
}

local controls: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any

-- Enables/disables a button made by UIKit.button (greys it out and ignores presses).
function UIKit.setEnabled(button: Instance, value: boolean)
	local c = controls[button]
	if c then
		c.setEnabled(value)
	end
end

function UIKit.setText(button: Instance, text: string)
	local c = controls[button]
	if c then
		c.setText(text)
	end
end

-- A tactile button that works for mouse, touch and gamepad (Activated).
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
}): any
	local style = BUTTON_STYLES[props.style or "primary"] or BUTTON_STYLES.primary
	local enabled = true
	local gradient = UIKit.gradient(style[1], style[2], 90)
	local scale = new("UIScale", { Scale = 1 })
	local label = UIKit.text({
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		Text = props.text,
		FontFace = Theme.BodyBold,
		TextSize = props.textSize or 17,
		TextColor3 = style[3],
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local button = new("TextButton", {
		Name = "Button",
		AutoButtonColor = false,
		Text = "",
		Size = props.size or UDim2.fromOffset(160, 44),
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = props.layoutOrder or 0,
		UIKit.corner(10),
		gradient,
		scale,
		UIKit.stroke(Color3.new(1, 1, 1), 1, 0.85),
		label,
	})
	button.MouseEnter:Connect(function()
		if enabled then
			UIKit.tween(scale, 0.12, { Scale = 1.04 })
		end
	end)
	button.MouseLeave:Connect(function()
		UIKit.tween(scale, 0.12, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		if enabled then
			UIKit.tween(scale, 0.06, { Scale = 0.95 })
		end
	end)
	button.Activated:Connect(function()
		if not enabled then
			return
		end
		UIKit.tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
		if UIKit.onClick then
			UIKit.onClick()
		end
		if props.onClick then
			props.onClick()
		end
	end)
	-- Instances can't carry custom fields, so per-button controls live in a weak side table.
	controls[button] = {
		setEnabled = function(value: boolean)
			enabled = value
			button.Active = value
			gradient.Color = if value
				then ColorSequence.new(style[1], style[2])
				else ColorSequence.new(Theme.PanelLighter, Theme.PanelLight)
			label.TextColor3 = if value then style[3] else Theme.TextFaint
		end,
		setText = function(text: string)
			label.Text = text
		end,
	}
	button.Parent = props.parent
	return button
end

-- Icons drawn from frames so they never depend on font coverage or uploaded images.
function UIKit.cashIcon(size: number): Frame
	local holder = new("Frame", { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 })
	new("Frame", {
		Parent = holder,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.86),
		BackgroundColor3 = Theme.Gold,
		UIKit.round(),
		UIKit.gradient(Color3.fromRGB(255, 236, 160), Theme.GoldDark, 45),
		UIKit.stroke(Color3.fromRGB(255, 250, 220), 1.5, 0.2),
	})
	UIKit.text({
		Parent = holder,
		Size = UDim2.fromScale(1, 1),
		Text = "$",
		FontFace = Theme.Heavy,
		TextSize = math.floor(size * 0.6),
		TextColor3 = Color3.fromRGB(110, 60, 10),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	return holder
end

function UIKit.orbIcon(size: number, color: Color3?): Frame
	local holder = new("Frame", { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 })
	local c = color or Theme.Violet
	new("Frame", {
		Parent = holder,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		BackgroundColor3 = c,
		UIKit.round(),
		UIKit.gradient(c:Lerp(Color3.new(1, 1, 1), 0.6), c, 45),
		UIKit.stroke(Color3.new(1, 1, 1), 1.2, 0.4),
	})
	new("Frame", {
		Parent = holder,
		Position = UDim2.fromScale(0.3, 0.26),
		Size = UDim2.fromScale(0.2, 0.2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.2,
		UIKit.round(),
	})
	return holder
end

-- Small chest glyph in a crate tier's colours.
function UIKit.crateIcon(tier: string, size: number): Frame
	local def = Crates.get(tier)
	local body = if def then def.body else Color3.fromRGB(110, 78, 54)
	local trim = if def then def.color else Theme.Gold
	local holder = new("Frame", { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 })
	new("Frame", {
		Parent = holder,
		Position = UDim2.fromScale(0.08, 0.36),
		Size = UDim2.fromScale(0.84, 0.56),
		BackgroundColor3 = body,
		UIKit.corner(3),
		UIKit.stroke(trim, 2, 0),
	})
	new("Frame", {
		Parent = holder,
		Position = UDim2.fromScale(0.04, 0.14),
		Size = UDim2.fromScale(0.92, 0.26),
		BackgroundColor3 = body:Lerp(Color3.new(0, 0, 0), 0.15),
		UIKit.corner(3),
		UIKit.stroke(trim, 2, 0),
	})
	new("Frame", {
		Parent = holder,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.1),
		Size = UDim2.fromScale(0.16, 0.6),
		BackgroundColor3 = Color3.fromRGB(242, 232, 204),
	})
	return holder
end

function UIKit.rarityBadge(rarity: string, height: number?): Frame
	local info = Rarities.get(rarity)
	local color = if info then info.color else Theme.TextDim
	local h = height or 22
	local badge = new("Frame", {
		Size = UDim2.fromOffset(0, h),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color,
		UIKit.corner(h // 2),
		UIKit.padding(0, 10),
		UIKit.gradient(color:Lerp(Color3.new(1, 1, 1), 0.25), color:Lerp(Color3.new(0, 0, 0), 0.25), 90),
		UIKit.text({
			Name = "Label",
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = string.upper(rarity),
			FontFace = Theme.Heavy,
			TextSize = math.floor(h * 0.55),
			TextColor3 = Color3.fromRGB(20, 14, 24),
		}),
	})
	if rarity == "Mythic" or rarity == "Legendary" then
		local shimmer = new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, color),
				ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, color),
			}),
			Offset = Vector2.new(-1, 0),
		})
		shimmer.Parent = badge
		task.defer(function()
			while badge.Parent do
				shimmer.Offset = Vector2.new(-1, 0)
				local t = UIKit.tween(shimmer, 1.6, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine)
				t.Completed:Wait()
				task.wait(1.2)
			end
		end)
		local base = badge:FindFirstChildOfClass("UIGradient")
		if base and base ~= shimmer then
			base:Destroy()
		end
	end
	return badge
end

-- A ViewportFrame showing a unit, framed by its height. `silhouette` hides undiscovered units.
function UIKit.viewport(
	characterId: string,
	size: UDim2,
	options: { silhouette: boolean?, spin: boolean?, zoom: number? }?
): ViewportFrame
	local opts: any = options or {}
	local viewport = new("ViewportFrame", {
		Size = size,
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 140, 170),
		LightColor = Color3.fromRGB(255, 236, 220),
		LightDirection = Vector3.new(-0.6, -1, -0.8),
		ImageColor3 = if opts.silhouette then Color3.new(0, 0, 0) else Color3.new(1, 1, 1),
	})
	local world = new("WorldModel", { Parent = viewport })
	local def = Sorcerers.get(characterId)
	if not def then
		return viewport
	end
	local model = CharacterModels.build(
		characterId,
		CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(180), 0),
		{ aura = false }
	)
	model.Parent = world
	local height = CharacterModels.heightOf(characterId)
	local camera = new("Camera", { FieldOfView = 30, Parent = viewport })
	local distance = (height * 1.25 + 3) / (opts.zoom or 1)
	local focus = Vector3.new(0, height * 0.5, 0)
	camera.CFrame = CFrame.lookAt(focus + Vector3.new(distance * 0.35, height * 0.18, distance), focus)
	viewport.CurrentCamera = camera
	if opts.spin then
		-- Orbit the camera (moving welded parts inside a viewport isn't reliable).
		task.defer(function()
			local angle = 0
			local function alive(): boolean
				local ok, parent = pcall(function()
					return viewport.Parent
				end)
				return ok and parent ~= nil
			end
			while alive() do
				angle += task.wait() * 0.5
				local offset = Vector3.new(math.sin(angle * 0.8) * distance * 0.6, height * 0.18, distance)
				camera.CFrame = CFrame.lookAt(focus + offset, focus)
			end
		end)
	end
	return viewport
end

-- A ViewportFrame showing a crate model.
function UIKit.crateViewport(tier: string, size: UDim2): ViewportFrame
	local viewport = new("ViewportFrame", {
		Size = size,
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(160, 150, 170),
		LightColor = Color3.fromRGB(255, 240, 220),
		LightDirection = Vector3.new(-0.6, -1, -0.8),
	})
	if not Crates.get(tier) then
		return viewport
	end
	local world = new("WorldModel", { Parent = viewport })
	local model = CrateModels.build(tier, CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(180 + 25), 0))
	model.Parent = world
	local h = CrateModels.heightOf(tier)
	local camera = new("Camera", { FieldOfView = 30, Parent = viewport })
	local focus = Vector3.new(0, h * 0.5, 0)
	camera.CFrame = CFrame.lookAt(focus + Vector3.new(4, h * 0.9, 13.5), focus)
	viewport.CurrentCamera = camera
	return viewport
end

-- Rounded progress bar; returns frame and a setter (0..1).
function UIKit.bar(size: UDim2, color: Color3): (Frame, (number) -> ())
	local fill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = color,
		UIKit.round(),
		UIKit.gradient(color:Lerp(Color3.new(1, 1, 1), 0.3), color, 90),
	})
	local frame = new("Frame", {
		Size = size,
		BackgroundColor3 = Theme.Shadow,
		BackgroundTransparency = 0.2,
		UIKit.round(),
		fill,
	})
	return frame, function(alpha: number)
		fill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
	end
end

-- Modal panel with title bar and close button. Returns the root and its content frame.
function UIKit.panel(title: string, size: Vector2, onClose: () -> ()): (Frame, Frame, UIScale)
	local scale = new("UIScale", { Scale = 1 })
	local content = new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 1, -56),
		BackgroundTransparency = 1,
		UIKit.padding(14, 18),
	})
	local close = UIKit.button({
		text = "X",
		style = "secondary",
		size = UDim2.fromOffset(40, 40),
		position = UDim2.new(1, -50, 0, 8),
		onClick = onClose,
		textSize = 18,
	})
	local root = new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.04,
		scale,
		UIKit.corner(16),
		UIKit.stroke(Theme.Stroke, 2, 0.2),
		new("Frame", {
			Name = "Header",
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundColor3 = Theme.PanelLight,
			UIKit.corner(16),
			UIKit.gradient(Theme.PanelLighter, Theme.Panel, 90),
			UIKit.text({
				Name = "Title",
				Position = UDim2.fromOffset(22, 0),
				Size = UDim2.new(1, -90, 1, 0),
				Text = title,
				FontFace = Theme.TitleBold,
				TextSize = 28,
				TextColor3 = Theme.Text,
			}),
			new("Frame", {
				Name = "Accent",
				Position = UDim2.new(0, 22, 1, -3),
				Size = UDim2.new(0, 120, 0, 3),
				BackgroundColor3 = Theme.Violet,
				BorderSizePixel = 0,
				UIKit.gradient(Theme.Violet, Theme.Panel, 0),
			}),
			close,
		}),
		content,
	})
	return root, content, scale
end

return UIKit
