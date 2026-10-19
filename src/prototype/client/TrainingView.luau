--!strict
-- Plays the training post. Every frame it reads the hit schedule the server wrote on the Post
-- and poses the Sorcerer from it: the wind-up starts so that contact lands exactly on each
-- beat's timestamp, the beat the server credits. On contact the dummy rocks back and flashes,
-- sparks and a ring burst from the hit point, the payout pops above the dummy and a coin
-- flies to the Reward Chest. When the chest is full the Sorcerer rests (nothing is credited).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)
local PartKit = require(Shared.Visuals.PartKit)
local Sorcerers = require(Shared.Config.Sorcerers)
local Prototype = ReplicatedStorage:WaitForChild("Prototype")
local HitSchedule = require(Prototype.HitSchedule)
local Rig = require(Prototype.Rig)
local Techniques = require(Prototype.Techniques)
local Fx = require(script.Parent.Fx)

local TrainingView = {}

local COIN_TIME = 0.5 -- seconds a coin takes to fly from the dummy to the chest
TrainingView.CoinTime = COIN_TIME
local REST_BLEND = 0.45 -- seconds to settle into (or out of) the resting pose
local ABORT_BLEND = 0.3 -- seconds to ease out of a cancelled wind-up
local GOLD = Color3.fromRGB(255, 205, 90)

type View = {
	post: Model,
	rig: Model,
	joints: { [string]: Rig.Joint },
	scale: number,
	technique: Techniques.Technique,
	color: Color3,
	dummyBody: BasePart,
	spring: Motor6D,
	springBase: CFrame,
	hitPoint: Attachment,
	popupAnchor: Attachment,
	highlight: Highlight,
	sparks: ParticleEmitter,
	ring: BasePart,
	flash: PointLight,
	chestTarget: BasePart,
	fxFolder: Folder,
	lastBeat: number?,
	placedAt: number?,
	restWeight: number,
	hitAt: number,
	hitAmp: number,
	strikeSounded: number?,
	contactAt: number?, -- timestamp of the last strike played
	lastRaw: Techniques.RawPose?,
	abortFrom: Techniques.RawPose?, -- pose a cancelled wind-up eases out of
	abortAt: number,
}

local view: View? = nil
TrainingView.strikes = 0 -- strikes played (for tests)
TrainingView.beatsShown = 0 -- credited beats those strikes showed (for tests)
TrainingView.resting = false
TrainingView.lastPose = nil :: { [string]: CFrame }?
TrainingView.lastU = nil :: number?

local function smooth(a: number): number
	return a * a * (3 - 2 * a)
end

function TrainingView.start(yard: Instance)
	local post = yard:WaitForChild("Post") :: Model
	local rig = post:WaitForChild("Sorcerer") :: Model
	local dummy = yard:WaitForChild("Dummy") :: Model
	local body = dummy:WaitForChild("Body") :: BasePart
	local spring = body:WaitForChild("Spring") :: Motor6D
	local id = rig:GetAttribute("SorcererId")
	local def = Sorcerers.get(if type(id) == "string" then id else "kai")
	local color = if def then def.color else Color3.fromRGB(255, 170, 90)

	local fxFolder = Instance.new("Folder")
	fxFolder.Name = "PrototypeFx"
	fxFolder.Parent = workspace

	local highlight = Instance.new("Highlight")
	highlight.Name = "HitFlash"
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.OutlineColor = color
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Adornee = dummy
	highlight.Parent = dummy

	local hitPoint = body:WaitForChild("HitPoint") :: Attachment
	local sparks = PartKit.particles(hitPoint, {
		Name = "Sparks",
		Rate = 0,
		Color = ColorSequence.new(color, Color3.new(1, 1, 1)),
		Lifetime = NumberRange.new(0.18, 0.4),
		Speed = NumberRange.new(14, 26),
		SpreadAngle = Vector2.new(70, 70),
		Drag = 6,
		EmissionDirection = Enum.NormalId.Front,
		Size = PartKit.sequence({ { 0, 0.55 }, { 1, 0 } }),
		Transparency = PartKit.sequence({ { 0, 0 }, { 1, 1 } }),
	})

	local ring = PartKit.part(fxFolder, {
		Name = "ImpactRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 1, 1),
		CFrame = body.CFrame * hitPoint.CFrame,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	local flash = PartKit.light(ring, color, 14, 0)

	local chest = yard:WaitForChild("Chest")
	local scale = rig:GetAttribute("RigScale")
	view = {
		post = post,
		rig = rig,
		joints = Rig.joints(rig),
		scale = if type(scale) == "number" then scale else Rig.PostScale,
		technique = Techniques.SparkPalm,
		color = color,
		dummyBody = body,
		spring = spring,
		springBase = spring.C0,
		hitPoint = hitPoint,
		popupAnchor = body:WaitForChild("PopupAnchor") :: Attachment,
		highlight = highlight,
		sparks = sparks,
		ring = ring,
		flash = flash,
		chestTarget = chest:WaitForChild("Gold") :: BasePart,
		fxFolder = fxFolder,
		lastBeat = nil,
		placedAt = nil,
		restWeight = 0,
		hitAt = -math.huge,
		hitAmp = 0,
		strikeSounded = nil,
		contactAt = nil,
		lastRaw = nil,
		abortFrom = nil,
		abortAt = -math.huge,
	}
end

local function popup(v: View, now: number, text: string, big: boolean)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Payout"
	gui.Size = UDim2.fromOffset(if big then 220 else 150, if big then 64 else 46)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	gui.Adornee = v.popupAnchor
	gui.Parent = v.popupAnchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = GOLD
	label.TextStrokeColor3 = Color3.fromRGB(60, 30, 10)
	label.TextStrokeTransparency = 0.1
	label.FontFace = PartKit.font(Enum.Font.GothamBlack, true)
	label.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = label
	local drift = (math.random() - 0.5) * 1.2
	Fx.play(now, 0.9, function(alpha)
		-- Pop in, hang, then rise and fade.
		local pop = if alpha < 0.12
			then 0.6 + 0.6 * (alpha / 0.12)
			else 1.2 - 0.2 * math.min(1, (alpha - 0.12) / 0.15)
		scale.Scale = pop
		gui.StudsOffsetWorldSpace = Vector3.new(drift * alpha, 2.2 * smooth(alpha), 0)
		local fade = math.clamp((alpha - 0.6) / 0.4, 0, 1)
		label.TextTransparency = fade
		label.TextStrokeTransparency = 0.1 + 0.9 * fade
	end, function()
		gui:Destroy()
	end)
end

local function coin(v: View, now: number, from: Vector3)
	local part = PartKit.part(v.fxFolder, {
		Name = "Coin",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.18, 0.8, 0.8),
		CFrame = CFrame.new(from),
		Color = GOLD,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	local target = v.chestTarget.CFrame.Position + Vector3.new(0, 0.6, 0)
	Fx.play(now, COIN_TIME, function(alpha, age)
		local p = Fx.arc(from, target, 5, smooth(alpha))
		part.CFrame = CFrame.new(p) * CFrame.Angles(0, age * 14, math.rad(90))
		part.Transparency = if alpha > 0.9 then (alpha - 0.9) * 10 else 0
	end, function()
		part:Destroy()
	end)
end

local function onContact(v: View, post: HitSchedule.Post, now: number, beats: number)
	local hits = beats * post.hitsPerBeat
	local value = beats * post.valuePerBeat
	TrainingView.strikes += 1
	TrainingView.beatsShown += beats
	v.hitAt = now
	v.hitAmp = 15 + 4 * math.min(hits - 1, 5)
	local hitCF = v.dummyBody.CFrame * v.hitPoint.CFrame
	v.sparks:Emit(10 + 3 * math.min(hits, 6))
	v.highlight.OutlineColor = v.color
	Fx.play(now, 0.28, function(alpha)
		v.highlight.FillTransparency = 0.35 + 0.65 * alpha
		v.highlight.OutlineTransparency = alpha
	end)
	-- Ring faces the Sorcerer (cylinder axis along the hit point's Z).
	local ringCF = hitCF * CFrame.Angles(0, math.rad(90), 0)
	Fx.play(now, 0.24, function(alpha)
		local d = 0.8 + 4.2 * (1 - (1 - alpha) * (1 - alpha))
		v.ring.Size = Vector3.new(0.12, d, d)
		v.ring.CFrame = ringCF
		v.ring.Transparency = 0.05 + 0.95 * alpha
		v.flash.Brightness = 4 * (1 - alpha)
	end)
	local text = if post.hitsPerBeat > 1 or beats > 1
		then string.format("x%d  +%s", hits, Format.cash(value))
		else "+" .. Format.cash(value)
	popup(v, now, text, hits > 1)
	coin(v, now, hitCF.Position)
	Fx.sound("impact", v.hitPoint, if hits > 1 then 0.85 else 1)
	task.delay(0.08, function()
		Fx.sound("coin", v.popupAnchor)
	end)
end

-- Advances the view to server time `now`. Called every frame.
function TrainingView.step(now: number, dt: number)
	local v = view
	if not v then
		return
	end
	local post = HitSchedule.read(v.post)
	local tech = v.technique
	local u: number? = nil
	local working = false
	if post then
		-- A new placement (or preset switch) restarts the beat count.
		if v.placedAt ~= post.placedAt then
			v.placedAt = post.placedAt
			v.lastBeat = HitSchedule.beatsAt(post, now)
			v.contactAt = nil
		end
		local k = HitSchedule.beatsAt(post, now)
		local last = v.lastBeat or k
		if k > last then
			local credited = 0
			for b = last + 1, k do
				if HitSchedule.isCredited(post, b) then
					credited += 1
				end
			end
			if credited > 0 then
				v.contactAt = HitSchedule.beatTime(post, k)
				onContact(v, post, now, credited)
			end
		end
		-- Never step back: a small server-clock correction mustn't replay a hit.
		v.lastBeat = math.max(last, k)
		-- Which strike are we in? Recovery of the last one played, or wind-up of the next.
		local untilNext = HitSchedule.beatTime(post, k + 1) - now
		local contactAt = v.contactAt
		if contactAt and now - contactAt < tech.recovery then
			u = now - contactAt
		elseif HitSchedule.isCredited(post, k + 1) and untilNext < tech.anticipation then
			u = -untilNext
			if v.strikeSounded ~= k + 1 then
				v.strikeSounded = k + 1
				Fx.sound("swing", v.rig.PrimaryPart)
			end
		end
		working = HitSchedule.isCredited(post, k + 1) or u ~= nil
	end
	TrainingView.resting = not working
	local target = if working then 0 else 1
	local step = dt / REST_BLEND
	v.restWeight = if target > v.restWeight
		then math.min(target, v.restWeight + step)
		else math.max(target, v.restWeight - step)

	-- A wind-up whose hit won't be paid any more (chest filled, Sorcerer re-placed) is dropped,
	-- easing out of where it was rather than snapping.
	local wasWindingUp = TrainingView.lastU ~= nil and (TrainingView.lastU :: number) < 0
	if wasWindingUp and u == nil and v.lastRaw then
		v.abortFrom, v.abortAt = v.lastRaw, now
	end
	TrainingView.lastU = u
	local raw = if u then Techniques.sample(tech, u) else Techniques.Stance
	raw = Techniques.blend(raw, Techniques.Rest, smooth(v.restWeight))
	local abortAge = now - v.abortAt
	if v.abortFrom and abortAge >= 0 and abortAge < ABORT_BLEND then
		raw = Techniques.blend(v.abortFrom, raw, smooth(abortAge / ABORT_BLEND))
	end
	v.lastRaw = raw
	raw = Techniques.breathe(raw, now, if u then 0.2 else 1)
	local pose = Techniques.resolve(raw, v.scale)
	Rig.apply(v.joints, pose)
	TrainingView.lastPose = pose

	-- Dummy: a damped rock away from the Sorcerer after each hit.
	local age = now - v.hitAt
	local angle = if age >= 0 and age < 2 then v.hitAmp * math.exp(-5.5 * age) * math.sin(15 * age) else 0
	v.spring.C0 = v.springBase * CFrame.Angles(math.rad(angle), 0, 0)
end

return TrainingView
