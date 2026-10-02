--!strict
-- Every sound the game plays. Defaults use audio that ships with the Roblox client
-- (rbxasset://sounds/...), so they always load with no uploads or permissions.
--
-- To upgrade the soundscape, put a Creator Store audio id in `id` (e.g. "rbxassetid://123")
-- and it will be used instead of the built-in fallback. Ambient beds and music have no
-- built-in equivalent, so they stay silent until you add ids. See docs/INSTALL.md.

export type SoundDef = {
	id: string?, -- optional custom asset; takes priority when set
	builtin: string?, -- client-bundled fallback
	volume: number,
	speed: number?,
	variance: number?, -- random +/- playback speed variation
}

local BUILTIN = {
	tick = "rbxasset://sounds/volume_slider.ogg",
	splash = "rbxasset://sounds/impact_water.mp3",
	boom = "rbxasset://sounds/impact_explosion_03.mp3",
	whoosh = "rbxasset://sounds/action_swim.mp3",
	thud = "rbxasset://sounds/action_jump_land.mp3",
	hop = "rbxasset://sounds/action_jump.mp3",
	rise = "rbxasset://sounds/action_get_up.mp3",
}

local SoundConfig = {}

SoundConfig.Effects = {
	click = { builtin = BUILTIN.tick, volume = 0.45, speed = 1.35, variance = 0.05 },
	open = { builtin = BUILTIN.whoosh, volume = 0.18, speed = 2.2 },
	close = { builtin = BUILTIN.whoosh, volume = 0.14, speed = 2.6 },
	error = { builtin = BUILTIN.tick, volume = 0.5, speed = 0.55 },
	collect = { builtin = BUILTIN.splash, volume = 0.38, speed = 1.7, variance = 0.08 },
	coin = { builtin = BUILTIN.tick, volume = 0.35, speed = 2.1, variance = 0.15 },
	summonCharge = { builtin = BUILTIN.whoosh, volume = 0.35, speed = 0.55 },
	reveal = { builtin = BUILTIN.boom, volume = 0.3, speed = 1.4 },
	revealRare = { builtin = BUILTIN.boom, volume = 0.4, speed = 1.1 },
	revealLegendary = { builtin = BUILTIN.boom, volume = 0.55, speed = 0.75 },
	place = { builtin = BUILTIN.rise, volume = 0.5, speed = 1.2 },
	unlock = { builtin = BUILTIN.boom, volume = 0.3, speed = 1.8 },
	upgrade = { builtin = BUILTIN.rise, volume = 0.5, speed = 1.5 },
	strike = { builtin = BUILTIN.whoosh, volume = 0.35, speed = 2.4, variance = 0.15 },
	lance = { builtin = BUILTIN.whoosh, volume = 0.45, speed = 1.6 },
	burst = { builtin = BUILTIN.boom, volume = 0.35, speed = 1.6 },
	hit = { builtin = BUILTIN.thud, volume = 0.5, speed = 1.5, variance = 0.15 },
	curseDeath = { builtin = BUILTIN.boom, volume = 0.35, speed = 2.2 },
	curseStrike = { builtin = BUILTIN.thud, volume = 0.6, speed = 0.7 },
	reward = { builtin = BUILTIN.tick, volume = 0.45, speed = 1.8 },
	travel = { builtin = BUILTIN.whoosh, volume = 0.3, speed = 1.2 },
} :: { [string]: SoundDef }

-- Looping beds attached to the map's AmbientEmitters (by AmbientKind attribute).
-- Leave `id` empty to keep them silent.
SoundConfig.Ambient = {
	Water = { id = "", volume = 0.35, rolloff = 70 },
	Forest = { id = "", volume = 0.45, rolloff = 120 },
	Shrine = { id = "", volume = 0.3, rolloff = 110 },
	Courtyard = { id = "", volume = 0.25, rolloff = 70 },
	Village = { id = "", volume = 0.25, rolloff = 90 },
}

-- Background music (looped, non-positional). Empty = no music.
SoundConfig.Music = { id = "", volume = 0.22 }

return SoundConfig
