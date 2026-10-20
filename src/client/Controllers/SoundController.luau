--!nonstrict
-- Plays UI and world sounds from SoundConfig and handles the music/SFX toggles stored in the
-- profile settings. The world is flat pixel art, so there are no 3D sounds: a world sound
-- (playAt) is an ordinary sound whose volume falls off with the flat distance from your
-- character, and the ambient beds (Plaza, Farm) fade with how close you are to each area.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundConfig = require(Shared.Config.SoundConfig)
local Layout = require(Shared.Config.FarmLayout)

local SoundController = {}

-- World sounds: full volume within NEAR studs, silent beyond FAR (as the old roll-off).
SoundController.Near = 12
SoundController.Far = 140

local folder: Folder
local sfxEnabled = true
local musicEnabled = true
local musicSound: Sound? = nil
local ambient: { [string]: Sound } = {}
local rng = Random.new()
local pool: { [string]: { Sound } } = {}

local function sourceOf(def: any): string?
	if def.id and def.id ~= "" then
		return def.id
	end
	return def.builtin
end

local function getSound(name: string): Sound?
	local def = SoundConfig.Effects[name]
	if not def then
		return nil
	end
	local list = pool[name]
	if not list then
		list = {}
		pool[name] = list
	end
	for _, sound in list do
		if not sound.IsPlaying then
			return sound
		end
	end
	if #list >= 4 then
		return list[1]
	end
	local source = sourceOf(def)
	if not source then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = source
	sound.Volume = def.volume
	sound.Parent = folder
	table.insert(list, sound)
	return sound
end

local function playScaled(name: string, pitch: number?, gain: number)
	if not sfxEnabled or gain <= 0 then
		return
	end
	local def = SoundConfig.Effects[name]
	local sound = getSound(name)
	if not sound or not def then
		return
	end
	local variance = def.variance or 0
	sound.Volume = def.volume * gain
	sound.PlaybackSpeed = (def.speed or 1) * (pitch or 1) * (1 + rng:NextNumber(-variance, variance))
	sound.TimePosition = 0
	sound:Play()
end

function SoundController.play(name: string, pitch: number?)
	playScaled(name, pitch, 1)
end

local function characterPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.CFrame.Position
	end
	return nil
end

-- 0..1: how loud something `distance` studs away is.
function SoundController.falloff(distance: number): number
	local near, far = SoundController.Near, SoundController.Far
	if distance <= near then
		return 1
	end
	return math.clamp(1 - (distance - near) / (far - near), 0, 1)
end

-- A one-shot at a world position: louder the closer it is to your character.
function SoundController.playAt(name: string, position: Vector3, pitch: number?)
	local at = characterPosition()
	local gain = 1
	if at then
		local d = Vector3.new(at.X - position.X, 0, at.Z - position.Z).Magnitude
		gain = SoundController.falloff(d)
	end
	playScaled(name, pitch, gain * 1.4)
end

function SoundController.setEnabled(sfx: boolean, music: boolean)
	sfxEnabled = sfx
	musicEnabled = music
	if musicSound then
		musicSound.Volume = if musicEnabled then SoundConfig.Music.volume else 0
	end
	if not sfx then
		for _, sound in ambient do
			sound.Volume = 0
		end
	end
end

-- Ambient beds: the plaza's near the plaza band, the farm's inside any farm.
local function ambientLevels(at: Vector3): { [string]: number }
	local plazaD = math.max(0, math.abs(at.Z) - Layout.PlazaHalfDepth)
	local farmD = math.huge
	for index = 1, Layout.FarmCount do
		local c = Layout.farmCFrame(index).Position
		local dx = math.max(0, math.abs(at.X - c.X) - Layout.FarmWidth / 2)
		local dz = math.max(0, math.abs(at.Z - c.Z) - Layout.FarmDepth / 2)
		farmD = math.min(farmD, math.sqrt(dx * dx + dz * dz))
	end
	local out = {}
	for kind, def in SoundConfig.Ambient do
		local d = if kind == "Plaza" then plazaD else farmD
		out[kind] = math.clamp(1 - d / def.rolloff, 0, 1)
	end
	return out
end

local function startAmbient()
	for kind, def in SoundConfig.Ambient do
		if def.id and def.id ~= "" then
			local sound = Instance.new("Sound")
			sound.Name = "Ambient" .. kind
			sound.SoundId = def.id
			sound.Looped = true
			sound.Volume = 0
			sound.Parent = folder
			sound:Play()
			ambient[kind] = sound
		end
	end
	if next(ambient) == nil then
		return
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		local at = characterPosition()
		if not at then
			return
		end
		local levels = ambientLevels(at)
		for kind, sound in ambient do
			local def = SoundConfig.Ambient[kind]
			sound.Volume = if sfxEnabled then def.volume * (levels[kind] or 0) else 0
		end
	end)
end

function SoundController.init(_registry: any)
	folder = Instance.new("Folder")
	folder.Name = "JJKFarmSfx"
	folder.Parent = SoundService
end

function SoundController.start()
	local preload = {}
	for name in SoundConfig.Effects do
		local sound = getSound(name)
		if sound then
			table.insert(preload, sound)
		end
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(preload)
		end)
	end)
	if SoundConfig.Music.id ~= "" then
		local music = Instance.new("Sound")
		music.Name = "Music"
		music.SoundId = SoundConfig.Music.id
		music.Looped = true
		music.Volume = SoundConfig.Music.volume
		music.Parent = folder
		music:Play()
		musicSound = music
	end
	startAmbient()
end

return SoundController
