--!strict
-- Guided first loop. The server advances a step when the matching action succeeds; the
-- client shows the card and points at the target.

export type StepInfo = {
	title: string,
	text: string,
	event: string,
	target: string,
	reward: { cash: number? }?,
}

local Tutorial = {}

Tutorial.Steps = {
	{
		title = "Place your Starter Crate",
		text = "Walk to a Crate Pad on your farm and press Place.",
		event = "placeCrate",
		target = "Pad",
	},
	{
		title = "Open the crate",
		text = "Wait for the Opening Time to finish, then press Open.",
		event = "openCrate",
		target = "Pad",
	},
	{
		title = "Place your Sorcerer",
		text = "Put your new Sorcerer on a production slot. It will start making Cursed Orbs.",
		event = "placeSorcerer",
		target = "Slot",
	},
	{
		title = "Collect the Orb Box",
		text = "Cursed Orbs roll down the lane into your Orb Box. Walk up to it and Collect.",
		event = "collect",
		target = "Box",
	},
	{
		title = "Sell your orbs",
		text = "Carry the box to the Sell Stand in the plaza and Sell it for Cash.",
		event = "sell",
		target = "Sell",
		reward = { cash = 50 },
	},
	{
		title = "Buy a crate",
		text = "Visit the Crate Shop and Buy a Basic Crate.",
		event = "buyCrate",
		target = "CrateShop",
		reward = { cash = 25 },
	},
	{
		title = "Upgrade your farm",
		text = "Visit the Upgrade Shop and Upgrade Orb Value.",
		event = "upgrade",
		target = "UpgradeShop",
		reward = { cash = 50 },
	},
} :: { StepInfo }

Tutorial.Done = #Tutorial.Steps + 1

function Tutorial.current(profile: any): StepInfo?
	return Tutorial.Steps[profile.tutorial]
end

function Tutorial.advance(profile: any, event: string): (StepInfo?, { cash: number? }?)
	local step = Tutorial.Steps[profile.tutorial]
	if not step or step.event ~= event then
		return nil, nil
	end
	profile.tutorial += 1
	local reward = step.reward
	if reward and reward.cash then
		profile.cash += reward.cash
		profile.stats.cashEarned += reward.cash
	end
	return step, reward
end

function Tutorial.skip(profile: any)
	profile.tutorial = Tutorial.Done
end

return Tutorial
