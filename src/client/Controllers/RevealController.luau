--!nonstrict
-- Opening a Crate, in pixel art. On the pad, the crate shakes harder and harder (its shake
-- frames) inside a glow ring in the colour of what's inside; then the lid flies off in a pillar
-- of light and the Sorcerer rises out of the crate, pale and glowing. For the owner, a card
-- follows with the Sorcerer's rarity, technique, Orb Value and Orbs per Second, and Place /
-- Later buttons (E / gamepad A to Place, Esc / B for Later).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crates = require(Shared.Config.Crates)
local Layout = require(Shared.Config.FarmLayout)
local Rarities = require(Shared.Config.Rarities)
local Sorcerers = require(Shared.Config.Sorcerers)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Util.Format)
local Palette = require(Shared.Pixel.Palette)
local Sprite = require(Shared.Pixel.Sprite)
local Characters = require(Shared.Pixel.Art.Characters)
local CrateArt = require(Shared.Pixel.Art.Crates)
local Fx = require(Shared.Pixel.Art.Fx)

local Pixel = script.Parent.Parent:WaitForChild("Pixel")
local Screen = require(Pixel.Screen)
local Camera2D = require(Pixel.Camera2D)
local Actor = require(Pixel.Actor)
local Widgets = require(Pixel.Widgets)
local FxPool = require(Pixel.FxPool)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local RevealController = {}

local registry: any
local playing = false
local rng = Random.new()

-- The rarity's colours on the palette: (dark, base, light).
local function rarityColors(rarity: any): (Color3, Color3, Color3)
	local p = Fx.orb(rarity.color).palette
	return p.d, p.o, p.l
end

-- A short camera shake: the camera follows a point jittering around your character.
local function shakeCamera(intensity: number, duration: number)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local t = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		t += dt
		if t > duration or not root.Parent then
			Camera2D.setFocus(nil)
			connection:Disconnect()
			return
		end
		local falloff = 1 - t / duration
		local px = math.floor((rng:NextNumber(-1, 1)) * intensity * 3 * falloff + 0.5)
		local py = math.floor((rng:NextNumber(-1, 1)) * intensity * 3 * falloff + 0.5)
		-- Whole art pixels (4 per stud), so the world never shimmers.
		Camera2D.setFocus(
			root.CFrame.Position + Vector3.new(px / Layout.PixelsPerStud, 0, py / Layout.PixelsPerStud)
		)
	end)
end

local function heartbeat(): number
	local dt = RunService.Heartbeat:Wait()
	return if type(dt) == "number" then math.min(dt, 0.1) else 1 / 60
end

-- World animation at the pad. Returns after the lid has burst (about 1.7 s).
function RevealController.playWorld(payload: any, mine: boolean)
	local farm, pad = payload.farm, payload.pad
	if not farm or not pad then
		return
	end
	local base = Layout.padWorld(farm, pad).Position
	local effects = registry.EffectsController
	if not mine and not effects.visible(base, 96) then
		return
	end
	local tier = payload.tier or "basic"
	if not Crates.get(tier) then
		tier = "basic"
	end
	local rarity = Rarities.get(payload.rarity) or Rarities.Info.Common
	local color = rarity.color
	local dark, mid, light = rarityColors(rarity)
	local px, py = Camera2D.toArt(base)
	local footY = py + 6 -- where crates stand on a pad

	-- Our own crate on the pad (the real one goes when the server removes it).
	local WorldView = registry.WorldView
	local real = WorldView and WorldView.crate(farm, pad)
	local view = WorldView and WorldView.farm(farm)
	local realCid = view and view.crateInfo[pad] and view.crateInfo[pad].cid
	if real then
		pcall(function()
			real:setVisible(false)
		end)
	end
	local crate = Actor.new(
		Screen.layers.Actors,
		{ crate = CrateArt.sprite(tier) },
		{ name = "RevealCrate", zBias = 2 }
	)
	crate:moveTo(px, footY)
	crate:play("crate", 1)

	-- Shake: frames 2 / 3 alternate faster and the crate jumps further as it builds.
	local duration = 1.5 + rarity.rank * 0.12
	local elapsed = 0 -- game time (Heartbeat), so the stage never skips when a frame is slow
	local nextThud = 0
	local glow: Frame? = nil
	local glowKey = ""
	while true do
		local t = elapsed / duration
		if t >= 1 then
			break
		end
		local amp = 1 + t * t * 3 -- 1..4 px
		local rate = 6 + t * 18 -- shakes per second
		local phase = math.floor(elapsed * rate)
		local side = if phase % 2 == 0 then -1 else 1
		crate:play("crate", if side < 0 then 2 else 3)
		local hop = if phase % 3 == 0 then math.floor(amp * 0.5 + 0.5) else 0
		crate:moveTo(px + math.floor(side * amp * 0.5 + 0.5), footY - hop)
		-- Glow ring in the rarity's colour, growing in 2-pixel steps (six pooled sizes) and
		-- pulsing as it builds.
		local r = 6 + 2 * math.min(5, math.floor(t * 6))
		local c = if t < 0.5 then dark elseif t < 0.85 then mid else light
		local key = r .. tostring(c)
		if key ~= glowKey then
			FxPool.release(glow)
			glow = FxPool.canvas("revealRing:" .. r .. ":" .. tostring(c), function(canvas)
				Fx.ring(canvas, 0, 0, r, c)
				Fx.ring(canvas, 0, 0, math.max(1, r - 2), c)
			end, 2)
			glowKey = key
			FxPool.place(glow :: Frame, px, footY - 6)
		end
		local ring = glow :: Frame
		ring.Visible = t < 0.4 or phase % 3 ~= 0
		if mine and t >= nextThud then
			nextThud = t + 0.22 - t * 0.12
			registry.SoundController.play("crateShake")
		end
		elapsed += heartbeat()
	end
	FxPool.release(glow)
	crate:moveTo(px, footY)
	crate:play("crate", 4) -- open, light pouring out

	-- Burst: lid flies off, pillar of rarity light
	effects.pillar(base, color, 40 + rarity.rank * 12, 1.3)
	effects.ring(base + Vector3.new(0, 1, 0), color, 4, 26, 0.8)
	effects.burst(base + Vector3.new(0, 4, 0), color, 30 + rarity.rank * 12, 22, 1)
	registry.SoundController.playAt(
		if rarity.rank >= 4 then "revealLegendary" elseif rarity.rank >= 3 then "revealRare" else "reveal",
		base
	)
	if mine and rarity.rank >= 4 then
		shakeCamera(if rarity.rank == 5 then 1.2 else 0.7, 0.7)
	end
	task.spawn(function()
		local lid = FxPool.sprite(CrateArt.lid(tier), "lid:" .. tier, false, nil, 5)
		local spin = if rng:NextNumber() < 0.5 then -1 else 1
		local lx, ly = px, footY - 12
		local spent = 0
		while spent < 0.9 do
			local t = spent / 0.9
			FxPool.place(lid, lx + spin * t * 24, ly - 48 * t + 40 * t * t)
			Sprite.show(lid, math.floor(t * 10) % 4 + 1)
			lid.Visible = t < 0.7 or math.floor(t * 30) % 2 == 0
			spent += heartbeat()
		end
		FxPool.release(lid)
		task.wait(0.5)
		crate:destroy()
		-- The server normally removes the opened crate long before this; if that same crate is
		-- somehow still on the pad, show it again.
		local info = view and view.crateInfo[pad]
		if real and info and info.cid == realCid and WorldView.crate(farm, pad) == real then
			pcall(function()
				real:setVisible(true)
			end)
		end
	end)
	-- The Sorcerer rises from the crate, pale and glowing in the rarity's colour.
	local def = Sorcerers.get(payload.id or "")
	if def then
		task.spawn(function()
			local art = Characters.sorcerer(def.id)
			local palette = {}
			for k, c in art.idle.palette do
				palette[k] = Palette.nearest(c:Lerp(light, 0.45):Lerp(Palette.White, 0.25))
			end
			local ghost =
				FxPool.sprite(art.idle, "revealGhost:" .. def.id .. ":" .. rarity.rank, false, palette, 6)
			local spent = 0
			while spent < 1.4 do
				local t = spent / 1.4
				Sprite.show(ghost, if math.floor(t * 6) % 2 == 0 then 1 else 2)
				FxPool.place(ghost, px, footY - 6 - math.floor(t * 22 + 0.5))
				ghost.Visible = t < 0.65 or math.floor(t * 30) % 2 == 0
				spent += heartbeat()
			end
			FxPool.release(ghost)
		end)
	end
end

-- Card ------------------------------------------------------------------------------------------

local CARD_W = 184

-- The card, built from UIKit's pixel helpers in art pixels (`root` is blown up by a whole-number
-- UIScale). Returns "place" or "close".
local function revealCard(gui: ScreenGui, root: Frame, rootW: number, rootH: number, payload: any): string
	local def = Sorcerers.get(payload.id)
	local rarity = Rarities.get(payload.rarity)
	if not def or not rarity then
		return "close"
	end
	local profile = registry.StateController.profile
	local unit = { id = def.id, level = 1 }
	local dark, mid, light = rarityColors(rarity)

	-- Flash of the rarity's colour
	local flash = UIKit.rect(root, 0, 0, rootW, rootH, mid, "Flash", 1)
	flash.BackgroundTransparency = 0.4
	task.delay(0.08, function()
		flash.BackgroundTransparency = 0.7
	end)
	task.delay(0.16, function()
		flash:Destroy()
	end)

	-- Text lines under the name
	local lines = {}
	local maxChars = math.floor((CARD_W - 12) / 8)
	for _, line in UIKit.wrap(string.upper("Technique: " .. def.technique), maxChars) do
		table.insert(lines, { text = line, color = Palette.nearest(def.color) })
	end
	table.insert(
		lines,
		{ text = "ORB VALUE " .. Format.cash(Economy.orbValue(unit, profile)), color = Palette.White }
	)
	table.insert(lines, { text = "ORBS PER SECOND " .. Format.abbreviate(def.ops), color = Palette.White })
	for _, line in
		UIKit.wrap(
			string.upper("Earns " .. Format.cash(Economy.income(unit, profile)) .. "/s on a slot"),
			maxChars
		)
	do
		table.insert(lines, { text = line, color = Palette.Leaf })
	end
	local nameText = string.upper(def.name)
	local nameSize = if UIKit.textWidth(nameText, 16) <= CARD_W - 12 then 16 else 8
	local portrait = UIKit.portraitDef(def.id)
	local pscale = 2
	local boxW = portrait.w * pscale + 8
	local boxH = portrait.h * pscale + 8
	local y = 6
	local rarityY = y
	y += 14
	local boxY = y
	y += boxH + 4
	local nameY = y
	y += nameSize + 4
	local linesY = y
	y += #lines * UIKit.LineHeight + 4
	local buttonsY = y
	local cardH = y + 16 + 6

	-- The card unrolls from the middle inside a clipping holder (whole pixels).
	local holder = Instance.new("Frame")
	holder.Name = "RevealCard"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.ClipsDescendants = true
	holder.ZIndex = 2
	holder.Parent = root
	local cx = math.floor((rootW - CARD_W) / 2)
	local cy = math.max(0, math.floor((rootH - cardH) / 2))
	local style = { fill = Palette.Night, light = mid, dark = dark, edge = Palette.Ink, text = Palette.White }
	local card = UIKit.box(holder, 0, 0, CARD_W, cardH, style, nil, "Card")

	-- Rarity chip
	local badge = UIKit.rarityBadge(payload.rarity)
	badge.Position = UDim2.fromOffset(math.floor((CARD_W - badge.Size.X.Offset) / 2), rarityY)
	badge.Parent = card
	-- Portrait in a dark box edged with the rarity's colour
	local box = UIKit.box(card, math.floor((CARD_W - boxW) / 2), boxY, boxW, boxH, {
		fill = Palette.Ink,
		light = dark,
		dark = dark,
		edge = mid,
	}, nil, "PortraitBox")
	local picture = UIKit.portrait(def.id, pscale)
	picture.Position = UDim2.fromOffset(4, 4)
	picture.Parent = box
	-- Name, technique and numbers
	UIKit.label(card, nameText, math.floor((CARD_W - UIKit.textWidth(nameText, nameSize)) / 2), nameY, {
		color = light,
		size = nameSize,
		name = "SorcererName",
	})
	for i, line in lines do
		local w = UIKit.textWidth(line.text)
		UIKit.label(card, line.text, math.floor((CARD_W - w) / 2), linesY + (i - 1) * UIKit.LineHeight, {
			color = line.color,
			name = "Stats",
		})
	end
	if payload.isNew then
		local tag = UIKit.box(card, 5, 5, UIKit.textWidth("NEW!") + 8, 12, "gold", nil, "New")
		UIKit.label(tag, "NEW!", 4, 2, { color = Palette.Ink, noShadow = true })
	end
	local choice: string? = nil
	UIKit.button({
		parent = card,
		text = "Place",
		style = "gold",
		size = UDim2.fromOffset(72, 16),
		position = UDim2.fromOffset(math.floor(CARD_W / 2) - 76, buttonsY),
		onClick = function()
			choice = "place"
		end,
	})
	UIKit.button({
		parent = card,
		text = "Later",
		style = "secondary",
		size = UDim2.fromOffset(72, 16),
		position = UDim2.fromOffset(math.floor(CARD_W / 2) + 4, buttonsY),
		onClick = function()
			choice = "close"
		end,
	})
	local function unroll(t: number)
		local h = math.floor(cardH * t + 0.5)
		local top = cy + math.floor((cardH - h) / 2)
		holder.Position = UDim2.fromOffset(cx, top)
		holder.Size = UDim2.fromOffset(CARD_W, h)
		card.Position = UDim2.fromOffset(0, cy - top)
	end
	unroll(0)
	task.spawn(function()
		local spent = 0
		while holder.Parent do
			local t = math.min(1, spent / 0.25)
			unroll(1 - (1 - t) ^ 3)
			if t >= 1 then
				break
			end
			spent += heartbeat()
		end
	end)
	local keyConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonA then
			choice = "place"
		elseif input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			choice = "close"
		end
	end)
	while not choice and holder.Parent and gui.Parent do
		task.wait()
	end
	keyConnection:Disconnect()
	-- Roll back up.
	local closing = 0
	while holder.Parent do
		local t = math.min(1, closing / 0.15)
		unroll(1 - t)
		if t >= 1 then
			break
		end
		closing += heartbeat()
	end
	holder:Destroy()
	return choice or "close"
end

-- Full reveal for the local player's own crate (result of OpenCrate).
function RevealController.play(result: any, onFinished: (() -> ())?)
	if playing then
		return
	end
	playing = true
	local farm = registry.StateController.farm()
	local payload = table.clone(result)
	payload.farm = payload.farm or farm
	local ok, err = pcall(RevealController.playWorld, payload, true)
	if not ok then
		warn("[JJK Farm] reveal", err)
	end
	local hud = Widgets.screen("Reveal", 20, true)
	local backdrop = UIKit.rect(hud.root, 0, 0, hud.w, hud.h, Palette.Ink, "Backdrop", 0)
	backdrop.BackgroundTransparency = 0.35
	local cardOk, choice = pcall(revealCard, hud.gui, hud.root, hud.w, hud.h, payload)
	if not cardOk then
		warn("[JJK Farm] reveal card", choice)
		choice = "close"
	end
	hud.destroy()
	playing = false
	if choice == "place" and payload.uid then
		task.defer(function()
			registry.PlacementController.beginSorcerer(payload.uid)
		end)
	end
	if onFinished then
		onFinished()
	end
end

function RevealController.isPlaying(): boolean
	return playing
end

function RevealController.init(reg: any)
	registry = reg
end

function RevealController.start() end

return RevealController
