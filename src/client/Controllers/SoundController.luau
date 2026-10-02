--!nonstrict
-- Plays UI and world sounds from SoundConfig, attaches ambient beds to map emitters and
-- handles the music/SFX toggles stored in the profile settings.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local SoundConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.SoundConfig)

local SoundController = {}

local folder: Folder
local sfxEnabled = true
local musicEnabled = true
local musicSound: Sound? = nil
local ambient: { Sound } = {}
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

function SoundController.play(name: string, pitch: number?)
	if not sfxEnabled then
		return
	end
	local def = SoundConfig.Effects[name]
	local sound = getSound(name)
	if not sound or not def then
		return
	end
	local variance = def.variance or 0
	sound.PlaybackSpeed = (def.speed or 1) * (pitch or 1) * (1 + rng:NextNumber(-variance, variance))
	sound.TimePosition = 0
	sound:Play()
end

-- Positional one-shot at a world position.
function SoundController.playAt(name: string, position: Vector3, pitch: number?)
	if not sfxEnabled then
		return
	end
	local def = SoundConfig.Effects[name]
	local source = def and sourceOf(def)
	if not def or not source then
		return
	end
	local holder = Instance.new("Attachment")
	holder.WorldPosition = position
	holder.Parent = workspace.Terrain
	local sound = Instance.new("Sound")
	sound.SoundId = source
	sound.Volume = def.volume * 1.4
	sound.RollOffMaxDistance = 140
	sound.RollOffMinDistance = 12
	sound.PlaybackSpeed = (def.speed or 1)
		* (pitch or 1)
		* (1 + rng:NextNumber(-(def.variance or 0), def.variance or 0))
	sound.Parent = holder
	sound:Play()
	task.delay(4, function()
		holder:Destroy()
	end)
end

function SoundController.setEnabled(sfx: boolean, music: boolean)
	sfxEnabled = sfx
	musicEnabled = music
	if musicSound then
		musicSound.Volume = if musicEnabled then SoundConfig.Music.volume else 0
	end
	for _, sound in ambient do
		sound.Volume = if sfx then (sound:GetAttribute("BaseVolume") :: number? or 0.3) else 0
	end
end

local function attachAmbient()
	local map = workspace:WaitForChild("JJKFarmMap", 30)
	if not map then
		return
	end
	for _, emitter in map:GetDescendants() do
		local kind = emitter:GetAttribute("AmbientKind")
		local def = kind and SoundConfig.Ambient[kind]
		if def and def.id ~= "" and emitter:IsA("BasePart") then
			local sound = Instance.new("Sound")
			sound.Name = "Ambient"
			sound.SoundId = def.id
			sound.Looped = true
			sound.Volume = def.volume
			sound:SetAttribute("BaseVolume", def.volume)
			sound.RollOffMaxDistance = def.rolloff
			sound.RollOffMinDistance = def.rolloff * 0.25
			sound.Parent = emitter
			sound:Play()
			table.insert(ambient, sound)
		end
	end
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
	task.spawn(attachAmbient)
end

return SoundController
