--!strict
-- Minimal prototype HUD: Cash, what the post is doing, a hint line and toasts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)
local PartKit = require(Shared.Visuals.PartKit)
local Sorcerers = require(Shared.Config.Sorcerers)
local Prototype = ReplicatedStorage:WaitForChild("Prototype")
local HitSchedule = require(Prototype.HitSchedule)
local PrototypeConfig = require(Prototype.PrototypeConfig)

local Hud = {}

local GOLD = Color3.fromRGB(255, 205, 90)
local PAPER = Color3.fromRGB(246, 240, 224)
local INK = Color3.fromRGB(24, 20, 30)

type Toast = { frame: Frame, label: TextLabel, t0: number, key: string?, amount: number }

local gui: ScreenGui
local cashLabel: TextLabel
local infoLabel: TextLabel
local hintLabel: TextLabel
local toastHolder: Frame
local toasts: { Toast } = {}
local postModel: Model?
local sorcerer = Sorcerers.get(PrototypeConfig.SorcererId) :: Sorcerers.Sorcerer
Hud.lastToast = nil :: string?

local function text(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.TextColor3 = PAPER
	label.TextStrokeColor3 = INK
	label.TextStrokeTransparency = 0.35
	label.FontFace = PartKit.font(Enum.Font.GothamBold, true)
	for k, v in props do
		(label :: any)[k] = v
	end
	label.Parent = parent
	return label
end

function Hud.start(yard: Instance)
	local player = Players.LocalPlayer
	postModel = yard:WaitForChild("Post") :: Model
	gui = Instance.new("ScreenGui")
	gui.Name = "PrototypeHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = player:WaitForChild("PlayerGui")

	cashLabel = text(gui, "Cash", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(260, 44),
		TextScaled = true,
		TextColor3 = GOLD,
		FontFace = PartKit.font(Enum.Font.GothamBlack, true),
		Text = "$0",
	})
	infoLabel = text(gui, "Info", {
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.fromOffset(330, 92),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = 15,
		TextWrapped = true,
		RichText = true,
		Text = "",
	})
	hintLabel = text(gui, "Hint", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(0.9, 0, 0, 22),
		TextSize = 16,
		TextWrapped = true,
		Text = "",
	})
	toastHolder = Instance.new("Frame")
	toastHolder.Name = "Toasts"
	toastHolder.BackgroundTransparency = 1
	toastHolder.AnchorPoint = Vector2.new(0.5, 0)
	toastHolder.Position = UDim2.new(0.5, 0, 0, 58)
	toastHolder.Size = UDim2.fromOffset(360, 140)
	toastHolder.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = toastHolder

	local function refreshCash()
		cashLabel.Text = Format.cash(player:GetAttribute("Cash") or 0)
	end
	player:GetAttributeChangedSignal("Cash"):Connect(refreshCash)
	refreshCash()
end

-- Shows a toast. Toasts with the same `key` within a moment add their amounts together.
function Hud.toast(message: string, now: number, key: string?, amount: number?)
	Hud.lastToast = message
	if key then
		for _, t in toasts do
			if t.key == key and now - t.t0 < 1.6 then
				t.amount += amount or 0
				t.t0 = now
				t.label.Text = string.format(message, Format.cash(t.amount))
				Hud.lastToast = t.label.Text
				return
			end
		end
	end
	local frame = Instance.new("Frame")
	frame.Name = "Toast"
	frame.BackgroundColor3 = INK
	frame.BackgroundTransparency = 0.25
	frame.Size = UDim2.fromOffset(340, 30)
	frame.LayoutOrder = math.floor(now * 100)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	local shown = if key then string.format(message, Format.cash(amount or 0)) else message
	local label = text(frame, "Text", {
		Size = UDim2.fromScale(1, 1),
		TextSize = 16,
		Text = shown,
	})
	Hud.lastToast = shown
	frame.Parent = toastHolder
	table.insert(toasts, { frame = frame, label = label, t0 = now, key = key, amount = amount or 0 })
	while #toasts > 4 do
		local oldest = table.remove(toasts, 1)
		if oldest then
			oldest.frame:Destroy()
		end
	end
end

function Hud.step(now: number, resting: boolean, chestFull: boolean)
	for i = #toasts, 1, -1 do
		local t = toasts[i]
		local age = now - t.t0
		if age > 3 then
			t.frame:Destroy()
			table.remove(toasts, i)
		elseif age > 2.4 then
			local fade = (age - 2.4) / 0.6
			t.frame.BackgroundTransparency = 0.25 + 0.75 * fade
			t.label.TextTransparency = fade
			t.label.TextStrokeTransparency = 0.35 + 0.65 * fade
		end
	end
	local post = postModel and HitSchedule.read(postModel)
	if post then
		local intervalAttr = (postModel :: Model):GetAttribute("HitInterval")
		local perHitAttr = (postModel :: Model):GetAttribute("ValuePerHit")
		local interval: number = if type(intervalAttr) == "number"
			then intervalAttr
			else post.beat / post.hitsPerBeat
		local perHit: number = if type(perHitAttr) == "number"
			then perHitAttr
			else post.valuePerBeat / post.hitsPerBeat
		local combo = if post.hitsPerBeat > 1
			then string.format(' · <font color="#ffcd5a">x%d combos</font>', post.hitsPerBeat)
			else ""
		infoLabel.Text = string.format(
			"<b>TRAINING POST</b> (prototype)\n%s · %s\n1 hit / %.1fs · %s per hit · %s/s%s\nChest holds %s of income",
			sorcerer.name,
			sorcerer.technique,
			interval,
			Format.cash(perHit),
			Format.cash(HitSchedule.income(post)),
			combo,
			Format.clock(PrototypeConfig.ChestStorageSeconds)
		)
	end
	if chestFull then
		hintLabel.Text = sorcerer.name
			.. " is resting: the Reward Chest is full. Collect it (E at the chest, or step on its pad)."
		hintLabel.TextColor3 = Color3.fromRGB(255, 160, 120)
	elseif resting then
		hintLabel.Text = sorcerer.name .. " is resting."
		hintLabel.TextColor3 = PAPER
	else
		hintLabel.Text = "Every hit pays into the Reward Chest. Collect at the chest (E) or step on its pad."
		hintLabel.TextColor3 = PAPER
	end
end

return Hud
