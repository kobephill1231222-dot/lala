--!strict
-- The Reward Chest. Shows what's stored from the same schedule the server credits (lagging
-- by the coin's flight so the number ticks up as each coin lands): the label's amount and
-- bar, a gold heap that rises and a lid that lifts as it fills. When it's full the label says
-- so. Collecting throws the lid open with a burst of gold.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)
local PartKit = require(Shared.Visuals.PartKit)
local HitSchedule = require(ReplicatedStorage:WaitForChild("Prototype"):WaitForChild("HitSchedule"))
local Fx = require(script.Parent.Fx)
local TrainingView = require(script.Parent.TrainingView)

local ChestView = {}

local GOLD = Color3.fromRGB(255, 205, 90)
local PAPER = Color3.fromRGB(246, 240, 224)
local FULL = Color3.fromRGB(255, 120, 90)

type View = {
	post: Model,
	body: BasePart,
	hinge: Motor6D,
	hingeBase: CFrame,
	gold: BasePart,
	goldBottom: CFrame,
	goldWidth: Vector3,
	maxHeight: number,
	light: PointLight?,
	title: TextLabel,
	amount: TextLabel,
	fill: Frame,
	burstAt: number,
	sparkle: ParticleEmitter,
	wasFull: boolean,
}

local view: View? = nil
ChestView.stored = 0
ChestView.full = false

function ChestView.start(yard: Instance)
	local chest = yard:WaitForChild("Chest")
	local body = chest:WaitForChild("Body") :: BasePart
	local lid = chest:WaitForChild("Lid") :: BasePart
	local hinge = lid:WaitForChild("Hinge") :: Motor6D
	local gold = chest:WaitForChild("Gold") :: BasePart
	local label = body:WaitForChild("Label") :: BillboardGui
	local size = gold.Size
	local maxHeight = gold:GetAttribute("MaxHeight")
	view = {
		post = yard:WaitForChild("Post") :: Model,
		body = body,
		hinge = hinge,
		hingeBase = hinge.C0,
		gold = gold,
		goldBottom = gold.CFrame * CFrame.new(0, -size.Y / 2, 0),
		goldWidth = Vector3.new(size.X, 0, size.Z),
		maxHeight = if type(maxHeight) == "number" then maxHeight else 0.9,
		light = gold:FindFirstChildOfClass("PointLight"),
		title = label:WaitForChild("Title") :: TextLabel,
		amount = label:WaitForChild("Amount") :: TextLabel,
		fill = label:WaitForChild("Bar"):WaitForChild("Fill") :: Frame,
		burstAt = -math.huge,
		sparkle = PartKit.particles(gold, {
			Name = "Burst",
			Rate = 0,
			Color = ColorSequence.new(GOLD),
			Lifetime = NumberRange.new(0.5, 0.9),
			Speed = NumberRange.new(10, 18),
			SpreadAngle = Vector2.new(35, 35),
			Acceleration = Vector3.new(0, -30, 0),
			EmissionDirection = Enum.NormalId.Top,
			Size = PartKit.sequence({ { 0, 0.5 }, { 1, 0.1 } }),
		}),
		wasFull = false,
	}
end

-- Lid throw and gold burst when the chest is collected.
function ChestView.burst(now: number)
	local v = view
	if not v then
		return
	end
	v.burstAt = now
	v.sparkle:Emit(36)
	Fx.sound("collect", v.body)
end

function ChestView.step(now: number, _dt: number)
	local v = view
	if not v then
		return
	end
	local post = HitSchedule.read(v.post)
	local fraction, full = 0, false
	if post then
		-- Count a beat once its coin has landed.
		local stored = HitSchedule.stored(post, now - TrainingView.CoinTime)
		fraction = stored / post.capBeats
		full = stored >= post.capBeats
		ChestView.stored = stored
		v.amount.Text = Format.cash(stored * post.valuePerBeat)
			.. " / "
			.. Format.cash(post.capBeats * post.valuePerBeat)
	else
		ChestView.stored = 0
		v.amount.Text = "—"
	end
	ChestView.full = full
	if full and not v.wasFull then
		Fx.sound("full", v.body)
	end
	v.wasFull = full
	v.fill.Size = UDim2.fromScale(fraction, 1)
	if full then
		local pulse = 0.5 + 0.5 * math.sin(now * 6)
		v.title.Text = "FULL · COLLECT!"
		v.title.TextColor3 = FULL:Lerp(PAPER, pulse * 0.5)
		v.fill.BackgroundColor3 = FULL
	else
		v.title.Text = "REWARD CHEST"
		v.title.TextColor3 = PAPER
		v.fill.BackgroundColor3 = GOLD
	end
	-- Lid: lifts with the fill, thrown open on collect.
	local age = now - v.burstAt
	local burst = if age >= 0 and age < 1.2 then 75 * math.exp(-3.2 * age) else 0
	local angle = 4 + 34 * fraction + burst
	v.hinge.C0 = v.hingeBase * CFrame.Angles(math.rad(angle), 0, 0)
	-- Gold heap
	local h = 0.15 + v.maxHeight * fraction
	v.gold.Size = v.goldWidth + Vector3.new(0, h, 0)
	v.gold.CFrame = v.goldBottom * CFrame.new(0, h / 2, 0)
	if v.light then
		v.light.Brightness = 0.3 + 1.7 * fraction
	end
end

return ChestView
