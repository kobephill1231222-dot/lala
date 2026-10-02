--!strict
-- Guided introduction. The server advances steps when the matching gameplay event happens;
-- the client reads the current step to show the guide card and the world marker.

export type StepInfo = {
	title: string,
	text: string,
	event: string,
	target: string,
	reward: { energy: number?, seals: number? }?,
}

local Tutorial = {}

Tutorial.Steps = {
	{
		title = "Gather cursed energy",
		text = "Your spirits fill the Spirit Well in your sanctuary. Walk into the glowing well to collect.",
		event = "collect",
		target = "Well",
	},
	{
		title = "Summon a new ally",
		text = "Visit the Summoning Courtyard and perform a Lantern Ritual.",
		event = "summon",
		target = "Altar",
	},
	{
		title = "Put them to work",
		text = "Back home, place your new ally on an empty training spot.",
		event = "place",
		target = "Spot",
		reward = { energy = 60 },
	},
	{
		title = "Sharpen your sanctuary",
		text = "Buy Focus Training at the Talisman Shop. Every unit earns more.",
		event = "upgrade",
		target = "Shop",
		reward = { energy = 50 },
	},
	{
		title = "Cleanse the forest",
		text = "Defeat a curse in the Cursed Forest. Curses drop energy and Curse Seals.",
		event = "kill",
		target = "Forest",
		reward = { energy = 100, seals = 3 },
	},
} :: { StepInfo }

Tutorial.Done = #Tutorial.Steps + 1

function Tutorial.current(profile: any): StepInfo?
	return Tutorial.Steps[profile.tutorial]
end

-- Applies `event` to the profile. Returns the completed step and its reward when it advanced.
function Tutorial.advance(profile: any, event: string): (StepInfo?, { energy: number?, seals: number? }?)
	local step = Tutorial.Steps[profile.tutorial]
	if not step or step.event ~= event then
		return nil, nil
	end
	profile.tutorial += 1
	local reward = step.reward
	if reward then
		if reward.energy then
			profile.energy += reward.energy
			profile.lifetimeEnergy += reward.energy
		end
		if reward.seals then
			profile.seals += reward.seals
		end
	end
	return step, reward
end

function Tutorial.skip(profile: any)
	profile.tutorial = Tutorial.Done
end

return Tutorial
