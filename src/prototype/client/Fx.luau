--!strict
-- Small client-side effects for the prototype: positional sounds and frame-driven effects
-- (popups, impact rings, coins) that are updated from one place every frame.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local SoundConfig =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("SoundConfig"))

local Fx = {}

-- Prototype sounds, built on the game's sound list (client-bundled audio, no uploads).
-- `volume` scales the game's volume because these play in the world, not in the UI.
local SOUNDS: { [string]: { effect: string, volume: number, speed: number? } } = {
	swing = { effect = "technique", volume = 3.2, speed = 1.15 },
	impact = { effect = "sell", volume = 3.0, speed = 1.25 },
	coin = { effect = "coin", volume = 1.6 },
	collect = { effect = "collect", volume = 1.4 },
	full = { effect = "crateReady", volume = 1.2, speed = 0.7 },
	click = { effect = "click", volume = 1 },
}
Fx.Sounds = SOUNDS

local rng = Random.new()

-- Plays a sound at `parent` (a part or attachment), or non-positionally when omitted.
function Fx.sound(name: string, parent: Instance?, pitch: number?): Sound?
	local entry = SOUNDS[name]
	local def = entry and SoundConfig.Effects[entry.effect]
	if not entry or not def then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "Fx_" .. name
	sound.SoundId = if def.id and def.id ~= "" then def.id else def.builtin or ""
	sound.Volume = math.min(def.volume * entry.volume, 2)
	local variance = def.variance or 0
	sound.PlaybackSpeed = (def.speed or 1)
		* (entry.speed or 1)
		* (pitch or 1)
		* (1 + rng:NextNumber(-variance, variance))
	sound.RollOffMinDistance = 14
	sound.RollOffMaxDistance = 120
	sound.Parent = parent or SoundService
	sound:Play()
	Debris:AddItem(sound, 4)
	return sound
end

-- Frame-driven effects ---------------------------------------------------------------------

export type Effect = {
	t0: number,
	duration: number,
	update: (alpha: number, age: number) -> (),
	finish: (() -> ())?,
}

local active: { Effect } = {}

-- Starts an effect that is updated every frame with alpha 0..1 until `duration` has passed.
function Fx.play(t0: number, duration: number, update: (number, number) -> (), finish: (() -> ())?)
	local effect: Effect = { t0 = t0, duration = duration, update = update, finish = finish }
	update(0, 0)
	table.insert(active, effect)
end

function Fx.step(now: number)
	for i = #active, 1, -1 do
		local effect = active[i]
		local age = now - effect.t0
		local alpha = math.clamp(age / effect.duration, 0, 1)
		effect.update(alpha, age)
		if alpha >= 1 then
			table.remove(active, i)
			if effect.finish then
				effect.finish()
			end
		end
	end
end

function Fx.count(): number
	return #active
end

-- Quadratic Bezier point, for coin arcs.
function Fx.arc(a: Vector3, b: Vector3, height: number, alpha: number): Vector3
	local mid = (a + b) / 2 + Vector3.new(0, height, 0)
	local p = a:Lerp(mid, alpha)
	local q = mid:Lerp(b, alpha)
	return p:Lerp(q, alpha)
end

return Fx
