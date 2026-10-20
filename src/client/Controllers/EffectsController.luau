--!nonstrict
-- One-shot visual effects in pixel art, and the effect primitives the other controllers use
-- (bursts, rings, slash arcs, streaks, light pillars, floating text). Driven by server Effect
-- events for things everyone should see: Collect, Sell, Place, Upgrade, crate purchases and
-- placements. Everything here is cosmetic; nothing affects gameplay state.
--
-- Positions are world positions in studs (Vector3 / CFrame), as before. They become art pixels
-- with Camera2D.toArt (4 art px per stud); height (Y) lifts things up the screen by the same
-- 4 px per stud, the way the world is drawn. Effects draw in the world's Overlay layer from
-- pooled pieces (Pixel/FxPool), move in whole art pixels, and are skipped when off screen.
-- Floating text goes in the front layer (Pixel/Front, above the HUD), moved clear of the HUD's
-- cards. Rings grow through a fixed ladder of radii so their pooled drawings are shared.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared.Config.FarmLayout)
local WorldMap = require(Shared.Config.WorldMap)
local Format = require(Shared.Util.Format)
local Palette = require(Shared.Pixel.Palette)
local Sprite = require(Shared.Pixel.Sprite)
local Fx = require(Shared.Pixel.Art.Fx)

local Pixel = script.Parent.Parent:WaitForChild("Pixel")
local Screen = require(Pixel.Screen)
local Camera2D = require(Pixel.Camera2D)
local Front = require(Pixel.Front)
local FxPool = require(Pixel.FxPool)
local Text = require(Pixel.Text)

local EffectsController = {}

local player = Players.LocalPlayer
local registry: any

local PPS = Layout.PixelsPerStud
local VIOLET = Color3.fromRGB(170, 90, 255)
local GOLD = Color3.fromRGB(255, 205, 90)
local CASH = Color3.fromRGB(120, 230, 120)

local Z_GROUND = 2 -- rings and pillars' feet
local Z_FX = 4 -- sparks, coins, orbs
local Z_TEXT = 70 -- floating text (over the world prompt)

-- Live effects: each steps once per frame and returns false when finished.
type Live = (dt: number) -> boolean
local live: { Live } = {}
local MAX_LIVE = 160

local rng = Random.new()

local function colorKey(c: Color3): string
	return string.format(
		"%02x%02x%02x",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5)
	)
end

-- (dark, base, light) palette colours for any colour (the effects' own ramp).
local function ramp(color: Color3): (Color3, Color3, Color3)
	local p = Fx.orb(color).palette
	return p.d, p.o, p.l
end
EffectsController.ramp = ramp

-- World studs -> art pixels, height lifting things up the screen.
local function art(position: Vector3): (number, number)
	local x, y = Camera2D.toArt(position)
	return x, y - math.floor(position.Y * PPS + 0.5)
end
EffectsController.art = art

-- Is art pixel (x, y) on screen (with a margin in art pixels)?
local function onScreen(x: number, y: number, margin: number?): boolean
	local x0, y0, x1, y1 = Camera2D.view()
	local m = margin or 32
	return x >= x0 - m and x <= x1 + m and y >= y0 - m and y <= y1 + m
end

local function visible(position: Vector3, margin: number?): boolean
	local x, y = art(position)
	return onScreen(x, y, margin)
end
EffectsController.visible = visible

local function spawn(step: Live)
	if #live >= MAX_LIVE then
		-- Over budget: finish the oldest effect early.
		local oldest = table.remove(live, 1)
		if oldest then
			oldest(math.huge)
		end
	end
	table.insert(live, step)
end
EffectsController.spawn = spawn

local function stepAll(dt: number)
	local i = 1
	while i <= #live do
		local ok, alive = pcall(live[i], dt)
		if ok and alive then
			i += 1
		else
			if not ok then
				warn("[JJK Farm] effect step", alive)
			end
			table.remove(live, i)
		end
	end
end
EffectsController.step = stepAll

-- Primitives ---------------------------------------------------------------------------------

-- Sparkles flying out of `position` (count, speed in studs/s, size ~0.4-1).
function EffectsController.burst(
	position: Vector3,
	color: Color3,
	count: number,
	speed: number?,
	size: number?
)
	local cx, cy = art(position)
	if not onScreen(cx, cy, 24) then
		return
	end
	local dark, base, light = ramp(color)
	local n = math.clamp(math.floor(count * 0.6 + 0.5), 2, 24)
	local big = (size or 0.6) >= 0.6
	local v = (speed or 14) * PPS * 0.9
	local motes = {}
	for _ = 1, n do
		local angle = rng:NextNumber(0, math.pi * 2)
		local s = rng:NextNumber(0.4, 1) * v
		local m = FxPool.mote(light, if big then 2 else 1, if big then 2 else 1, Z_FX)
		table.insert(motes, {
			f = m,
			x = cx,
			y = cy,
			vx = math.cos(angle) * s,
			vy = math.sin(angle) * s * 0.75,
			life = rng:NextNumber(0.35, 0.8),
			t = 0,
			stage = 0,
		})
		FxPool.place(m, cx, cy)
	end
	-- A few twinkles in the middle
	local twinkles = {}
	for _ = 1, math.max(1, math.floor(n / 8)) do
		local f = FxPool.sprite(
			Fx.spark,
			"spark:" .. colorKey(light),
			false,
			{ y = light, w = Palette.White, a = base },
			Z_FX + 1
		)
		local tx, ty = cx + rng:NextInteger(-5, 5), cy + rng:NextInteger(-5, 5)
		FxPool.place(f, tx, ty)
		local delay = rng:NextNumber(0, 0.25)
		f.Visible = delay <= 0
		table.insert(twinkles, { f = f, delay = delay, t = 0 })
	end
	spawn(function(dt)
		local alive = false
		for _, m in motes do
			if m.f then
				m.t += dt
				if m.t >= m.life then
					FxPool.release(m.f)
					m.f = nil
				else
					local drag = math.exp(-4 * dt)
					m.vx *= drag
					m.vy *= drag
					m.x += m.vx * dt
					m.y += m.vy * dt
					FxPool.place(m.f, m.x, m.y)
					local k = m.t / m.life
					local stage = if k < 0.3 then 0 elseif k < 0.65 then 1 else 2
					if stage ~= m.stage then
						m.stage = stage
						m.f.BackgroundColor3 = if stage == 1 then base else dark
					end
					alive = true
				end
			end
		end
		for _, tw in twinkles do
			if tw.f then
				tw.t += dt
				local k = (tw.t - tw.delay) / 0.3
				if k >= 1 then
					FxPool.release(tw.f)
					tw.f = nil
				else
					tw.f.Visible = k >= 0
					Sprite.show(tw.f, math.clamp(math.floor(k * 3) + 1, 1, 3))
					alive = true
				end
			end
		end
		return alive
	end)
end

local function ringPiece(r: number, color: Color3): Frame
	return FxPool.canvas("ring:" .. r .. ":" .. colorKey(color), function(canvas)
		Fx.ring(canvas, 0, 0, r, color)
	end, Z_GROUND)
end

-- The radii a ring grows through (about a third bigger each step): every ring effect shares
-- these drawings, so a few hundred pooled Frames cover them all.
local RADII = { 1, 2, 3, 4, 5, 7, 9, 12, 16, 21, 28, 37, 49, 64, 72 }
EffectsController.RingRadii = RADII

-- The ladder's radii from r0 to r1 (r1 snapped down onto it).
local function ladder(r0: number, r1: number): { number }
	local out = {}
	for _, r in RADII do
		if r >= r0 and r <= r1 then
			table.insert(out, r)
		end
	end
	if #out == 0 then
		local nearest = RADII[1]
		for _, r in RADII do
			if r <= r1 then
				nearest = r
			end
		end
		table.insert(out, nearest)
	end
	return out
end
EffectsController.ladder = ladder

-- Expanding ring: sizes are diameters in studs, as before (`normal` is ignored: everything is
-- seen from above).
function EffectsController.ring(
	position: Vector3,
	color: Color3,
	fromSize: number,
	toSize: number,
	seconds: number,
	_normal: Vector3?
)
	local cx, cy = art(position)
	local r1 = math.clamp(math.floor(toSize * PPS / 2 + 0.5), 1, 72)
	if not onScreen(cx, cy, r1) then
		return
	end
	local r0 = math.clamp(math.floor(fromSize * PPS / 2 + 0.5), 1, r1)
	local steps = ladder(r0, r1)
	local _, base, light = ramp(color)
	local t = 0
	local shown: Frame? = nil
	local shownKey = ""
	spawn(function(dt)
		t += dt
		local k = t / math.max(seconds, 0.05)
		if k >= 1 then
			FxPool.release(shown)
			return false
		end
		local eased = 1 - (1 - k) * (1 - k)
		local r = steps[math.clamp(math.floor(eased * #steps) + 1, 1, #steps)]
		local c = if k < 0.5 then light else base
		local key = r .. colorKey(c)
		if key ~= shownKey then
			FxPool.release(shown)
			shown = ringPiece(r, c)
			shownKey = key
			FxPool.place(shown :: Frame, cx, cy)
		end
		-- Flicker out over the last third.
		local piece = shown :: Frame
		piece.Visible = k < 0.66 or math.floor(t * 30) % 2 == 0
		return true
	end)
end

-- A crescent blade swing in front of `cf` (Slash techniques).
function EffectsController.slashArc(cf: CFrame, color: Color3)
	local cx, cy = art(cf.Position)
	if not onScreen(cx, cy, 16) then
		return
	end
	local flip = cf.LookVector.X < 0
	local f = FxPool.sprite(Fx.slash(color), "slash:" .. colorKey(color), flip, nil, Z_FX)
	FxPool.place(f, cx, cy)
	local t = 0
	spawn(function(dt)
		t += dt
		if t >= 0.3 then
			FxPool.release(f)
			return false
		end
		Sprite.show(f, math.clamp(math.floor(t / 0.1) + 1, 1, 3))
		return true
	end)
end

-- A quick bolt flying from a to b (Shoot techniques).
function EffectsController.streak(a: Vector3, b: Vector3, color: Color3)
	local ax, ay = art(a)
	local bx, by = art(b)
	if not onScreen(ax, ay, 16) and not onScreen(bx, by, 16) then
		return
	end
	local flip = bx < ax
	local f = FxPool.sprite(Fx.bolt(color), "bolt:" .. colorKey(color), flip, nil, Z_FX)
	FxPool.place(f, ax, ay)
	local t = 0
	spawn(function(dt)
		t += dt
		local k = t / 0.25
		if k >= 1 then
			FxPool.release(f)
			return false
		end
		FxPool.place(f, ax + (bx - ax) * k, ay + (by - ay) * k)
		Sprite.show(f, if math.floor(t * 20) % 2 == 0 then 1 else 2)
		return true
	end)
end

-- A beam of light rising from `position` (height in studs), narrowing as it fades.
function EffectsController.pillar(position: Vector3, color: Color3, height: number, seconds: number)
	local cx, cy = art(position)
	local h = math.clamp(math.floor(height * 2 + 0.5), 24, 128)
	if not onScreen(cx, cy - h / 2, h) then
		return
	end
	local _, base = ramp(color)
	local widths = { 14, 12, 10, 8, 6, 4, 2 }
	local t = 0
	local shown: Frame? = nil
	local shownW = 0
	spawn(function(dt)
		t += dt
		local k = t / math.max(seconds, 0.05)
		if k >= 1 then
			FxPool.release(shown)
			return false
		end
		local w = widths[math.clamp(math.floor(k * #widths) + 1, 1, #widths)]
		if w ~= shownW then
			FxPool.release(shown)
			shown = FxPool.canvas("pillar:" .. w .. ":" .. h .. ":" .. colorKey(base), function(canvas)
				Fx.pillar(canvas, 0, 0, w, h, base)
			end, Z_GROUND)
			shownW = w
			FxPool.place(shown :: Frame, cx, cy)
		end
		return true
	end)
end

-- Floating "+$123" style text at a world position (size: the old point size; big sizes use
-- the 16 px font when the text is short enough). It rises above the HUD, moved out from under
-- the HUD's cards when it would start behind one.
function EffectsController.floatText(position: Vector3, text: string, color: Color3, size: number?)
	local x, y = art(position)
	if not onScreen(x, y, 48) then
		return
	end
	local upper = string.upper(text)
	local px = if (size or 30) >= 30 and #upper <= 6 then 16 else 8
	local snapped = Palette.nearest(color)
	local RISE = 24
	-- The whole path it rises through; slide it the shortest way out of any card it touches.
	local half = math.floor(Text.width(upper, px) / 2) + 1
	local blockers = Front.blockers()
	local x0, y0, x1, y1 = Camera2D.view()
	for _ = 1, 3 do
		local hit: Front.Rect? = nil
		for _, r in blockers do
			if x + half > r.x0 and x - half < r.x1 and y + px > r.y0 and y - RISE - px < r.y1 then
				hit = r
				break
			end
		end
		if not hit then
			break
		end
		local b = hit :: Front.Rect
		local options = {
			{ dx = 0, dy = b.y1 + RISE + px - y }, -- below the card
			{ dx = b.x1 + half + 1 - x, dy = 0 }, -- right of it
			{ dx = b.x0 - half - 1 - x, dy = 0 }, -- left of it
		}
		local best, bestCost = nil, math.huge
		for _, o in options do
			local nx, ny = x + o.dx, y + o.dy
			local inside = nx - half >= x0 and nx + half <= x1 and ny - RISE - px >= y0 and ny + px <= y1
			local cost = math.abs(o.dx) + math.abs(o.dy) + (if inside then 0 else 10000)
			if cost < bestCost then
				best, bestCost = o, cost
			end
		end
		if not best then
			break
		end
		x += best.dx
		y += best.dy
	end
	local f = FxPool.text(upper, snapped, px, Z_TEXT, Front.world)
	FxPool.place(f, x, y)
	local t = 0
	spawn(function(dt)
		t += dt
		if t >= 1.2 then
			FxPool.release(f)
			return false
		end
		local rise = RISE * (1 - (1 - t / 1.2) ^ 2)
		FxPool.place(f, x, y - rise)
		f.Visible = t < 0.75 or math.floor(t * 16) % 2 == 0
		return true
	end)
end

-- Where your character is drawn (art pixels, chest height).
local function playerArt(): (number?, number?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local x, y = Camera2D.toArt(root.CFrame.Position)
		return x, y - 8
	end
	return nil, nil
end

-- A stream of Cursed Orbs flying from `from` to your character (Collect).
local function orbStream(from: Vector3, count: number, color: Color3)
	local fx, fy = art(from)
	local def = Fx.orb(color)
	local key = "orb:" .. colorKey(color)
	for i = 1, math.min(count, 14) do
		local delay = i * 0.04
		local sx, sy = fx + rng:NextInteger(-8, 8), fy + rng:NextInteger(-6, 2)
		local f: Frame? = nil
		local t = 0
		spawn(function(dt)
			t += dt
			local k = (t - delay) / 0.45
			if k < 0 then
				return true
			end
			local tx, ty = playerArt()
			if k >= 1 or not tx then
				FxPool.release(f)
				return false
			end
			if not f then
				f = FxPool.sprite(def, key, false, nil, Z_FX)
			end
			local x = sx + ((tx :: number) - sx) * k
			local y = sy + ((ty :: number) - sy) * k - 20 * 4 * k * (1 - k)
			FxPool.place(f :: Frame, x, y)
			Sprite.show(f :: Frame, if math.floor(t * 12) % 2 == 0 then 1 else 2)
			return true
		end)
	end
end

-- A fountain of spinning coins (Sell): a few pooled coin sprites (each starting on its own
-- spin phase) among gold glints.
local function coinFountain(position: Vector3, count: number)
	local cx, cy = art(position)
	local n = math.min(count, 18)
	local coins = math.min(n, math.max(2, math.floor(n / 3)))
	for i = 1, n do
		local isCoin = i <= coins
		local f = if isCoin
			then FxPool.sprite(Fx.coin, "coin", false, nil, Z_FX)
			else FxPool.mote(if i % 2 == 0 then Palette.Yellow else Palette.Amber, 2, 2, Z_FX)
		local x, ground = cx + rng:NextInteger(-3, 3), cy + rng:NextInteger(-2, 6)
		local vx = rng:NextNumber(-48, 48)
		local vh = rng:NextNumber(80, 125)
		local h = 0
		local t = 0
		local phase = i % 4
		local bounced = false
		FxPool.place(f, x, ground)
		spawn(function(dt)
			t += dt
			if t >= 1.1 then
				FxPool.release(f)
				return false
			end
			vh -= 260 * dt
			h += vh * dt
			x += vx * dt
			if h <= 0 then
				h = 0
				if bounced then
					vh, vx = 0, vx * 0.5
				else
					bounced = true
					vh, vx = -vh * 0.4, vx * 0.6
				end
			end
			FxPool.place(f, x, ground - h)
			if isCoin then
				Sprite.show(f, (math.floor(t * 12) + phase) % 4 + 1)
			end
			f.Visible = t < 0.85 or math.floor(t * 20) % 2 == 0
			return true
		end)
	end
end

-- Server effects -----------------------------------------------------------------------------

local handlers: { [string]: (any) -> () } = {}

handlers.Collected = function(payload)
	local box = Layout.boxWorld(payload.farm) + Vector3.new(0, 6, 0)
	local mine = payload.userId == player.UserId
	if mine or visible(box, 64) then
		EffectsController.burst(box, VIOLET, if mine then 36 else 14, 16)
		EffectsController.ring(box - Vector3.new(0, 5, 0), VIOLET, 4, 18, 0.6)
	end
	if mine then
		orbStream(box, payload.orbs, VIOLET)
		EffectsController.floatText(
			box + Vector3.new(0, 3, 0),
			"+" .. Format.commas(payload.orbs) .. " Cursed Orbs",
			Color3.fromRGB(220, 180, 255),
			30
		)
		registry.SoundController.play("collect")
	end
end

handlers.Sold = function(payload)
	local stand = Layout.SellStand + Vector3.new(0, 3, 0)
	local mine = payload.userId == player.UserId
	if mine or visible(stand, 64) then
		coinFountain(stand, if mine then 18 else 8)
		EffectsController.ring(stand - Vector3.new(0, 1, 0), GOLD, 6, 30, 0.7)
		EffectsController.burst(stand, GOLD, if mine then 40 else 16, 18, 0.8)
	end
	if mine then
		EffectsController.floatText(stand + Vector3.new(0, 5, 0), "+" .. Format.cash(payload.cash), CASH, 40)
		registry.SoundController.play("sell")
		task.delay(0.1, function()
			registry.SoundController.play("coin")
		end)
		registry.UIController.pulseCash()
	end
end

handlers.Placed = function(payload)
	local position = Layout.slotWorld(payload.farm, payload.slot).Position
	if not visible(position, 64) then
		return
	end
	EffectsController.pillar(position, VIOLET, 24, 0.8)
	EffectsController.ring(position + Vector3.new(0, 0.8, 0), Color3.fromRGB(220, 180, 255), 3, 16, 0.6)
	EffectsController.burst(position + Vector3.new(0, 3, 0), VIOLET, 24, 12)
	registry.SoundController.playAt("place", position)
end

handlers.Upgraded = function(payload)
	local position = Layout.slotWorld(payload.farm, payload.slot).Position
	if visible(position, 64) then
		EffectsController.burst(position + Vector3.new(0, 4, 0), GOLD, 26, 12)
		EffectsController.ring(position + Vector3.new(0, 0.8, 0), GOLD, 3, 14, 0.5)
		EffectsController.floatText(position + Vector3.new(0, 9, 0), "LEVEL UP!", GOLD, 28)
	end
end

handlers.CratePlaced = function(payload)
	local position = Layout.padWorld(payload.farm, payload.pad).Position
	if visible(position, 64) then
		EffectsController.ring(position + Vector3.new(0, 0.8, 0), Color3.fromRGB(240, 220, 190), 4, 16, 0.5)
		EffectsController.burst(position + Vector3.new(0, 1.5, 0), Color3.fromRGB(240, 220, 190), 18, 10, 0.7)
		registry.SoundController.playAt("cratePlace", position)
	end
end

handlers.Bought = function(payload)
	if payload.userId == player.UserId then
		return -- played locally on purchase
	end
	local position = Layout.CrateShop + Vector3.new(0, 4, -4)
	if visible(position, 32) then
		EffectsController.burst(position, GOLD, 12, 10)
	end
end

handlers.CrateOpened = function(payload)
	if payload.userId == player.UserId then
		return -- the local reveal plays the full animation
	end
	registry.RevealController.playWorld(payload, false)
end

-- Local feedback ---------------------------------------------------------------------------

function EffectsController.upgradeFlash()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local position = root.CFrame.Position
		EffectsController.burst(position, GOLD, 30, 12)
		EffectsController.ring(Vector3.new(position.X, 0.2, position.Z), GOLD, 3, 14, 0.6)
	end
end

-- Sparkle over the bought crate's display in the Crate Shop.
function EffectsController.boughtCrate(tier: string)
	local position = Layout.CrateShop
	for _, object in WorldMap.get().objects do
		if object.kind == "display" and object.variant == tier then
			local r = object.rect
			position = Vector3.new((r.x0 + r.x1) / 2, 5, (r.z0 + r.z1) / 2)
		end
	end
	EffectsController.burst(position, GOLD, 30, 14, 0.8)
	EffectsController.ring(position - Vector3.new(0, 2, 0), GOLD, 3, 12, 0.5)
end

-- How many effects are running (for tests and budgets).
function EffectsController.count(): number
	return #live
end

function EffectsController.init(reg: any)
	registry = reg
end

function EffectsController.start()
	Screen.start()
	Front.start()
	registry.StateController.Effect:Connect(function(name: string, payload: any)
		local handler = handlers[name]
		if handler and type(payload) == "table" then
			-- Own thread per effect: some (crate reveals) animate over several frames.
			task.spawn(function()
				local ok, err = pcall(handler, payload)
				if not ok then
					warn("[JJK Farm] effect", name, err)
				end
			end)
		end
	end)
	RunService.RenderStepped:Connect(stepAll)
	-- The Sell Stand's coin turns slowly above the stand.
	local coin = FxPool.sprite(Fx.coin, "standCoin", false, nil, Z_FX)
	coin.Name = "SellStandCoin"
	local sx, sy = Camera2D.toArt(Layout.SellStand)
	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		local shown = onScreen(sx, sy, 48)
		coin.Visible = shown
		if shown then
			FxPool.place(coin, sx, sy - 34 - (if math.floor(t * 1.5) % 2 == 0 then 0 else 1))
			Sprite.show(coin, math.floor(t * 5) % 4 + 1)
		end
	end)
end

return EffectsController
