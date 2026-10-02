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

-- What the player should do right now for the current step, judged from the farm's actual
-- state rather than the step alone, so detours (picking the crate back up, removing the only
-- Sorcerer, running out of Cash) always get an instruction the player can follow.
-- Returns (text, target) or nil when the tutorial is finished.
function Tutorial.guidance(profile: any, now: number): (string?, string?)
	local step = Tutorial.current(profile)
	if not step then
		return nil, nil
	end
	local Economy = require(script.Parent.Economy)
	local Crates = require(script.Parent.Parent.Config.Crates)

	local onPad, unplaced = nil, 0
	for _, crate in profile.crates do
		if crate.pad then
			onPad = onPad or crate
		else
			unplaced += 1
		end
	end
	local placed = next(profile.slots) ~= nil
	local boxOrbs = Economy.boxAt(profile, now)
	local carried = profile.carried.orbs

	-- How to get Cash when a shop step can't be afforded yet.
	local function earn(goal: string): (string, string)
		if carried >= 1 then
			return "Sell your Cursed Orbs at the Sell Stand to afford " .. goal .. ".", "Sell"
		elseif boxOrbs >= 1 then
			return "Collect your Orb Box, then Sell it, to afford " .. goal .. ".", "Box"
		elseif not placed then
			return "Place a Sorcerer on a slot so it makes Cursed Orbs.", "Slot"
		end
		return "Your Sorcerers are filling the Orb Box. Collect and Sell it to afford " .. goal .. ".", "Box"
	end

	if step.event == "placeCrate" then
		if onPad then
			return "Your crate is opening. Wait for its Opening Time, then press Open.", "Pad"
		elseif unplaced == 0 then
			return earn("a Basic Crate at the Crate Shop")
		end
		return step.text, step.target
	elseif step.event == "openCrate" then
		if onPad then
			local remaining = onPad.readyAt - now
			if remaining > 0 then
				return string.format(
					"Opening Time: %d:%02d. When it's ready, press Open on the crate.",
					math.ceil(remaining) // 60,
					math.ceil(remaining) % 60
				),
					"Pad"
			end
			return "Your crate is ready! Walk up to it and press Open.", "Pad"
		elseif unplaced > 0 then
			return "Your crate is back in your inventory. Place it on a Crate Pad again; its Opening Time carries on.",
				"Pad"
		end
		return step.text, step.target
	elseif step.event == "placeSorcerer" then
		return step.text, step.target
	elseif step.event == "collect" then
		if boxOrbs >= 1 then
			return step.text, "Box"
		elseif not placed then
			return "Place a Sorcerer on a slot so it can make Cursed Orbs.", "Slot"
		end
		return "Watch your Sorcerer make Cursed Orbs. They roll down the lane into your Orb Box.", "Box"
	elseif step.event == "sell" then
		if carried >= 1 then
			return step.text, "Sell"
		elseif boxOrbs >= 1 then
			return "Collect your Orb Box first, then carry it to the Sell Stand.", "Box"
		elseif not placed then
			return "Place a Sorcerer on a slot so it can make Cursed Orbs.", "Slot"
		end
		return "Wait for your Orb Box to fill a little, then Collect it.", "Box"
	elseif step.event == "buyCrate" then
		local price = (Crates.get("basic") :: any).price
		if profile.cash < price then
			return earn("a Basic Crate (" .. price .. " Cash)")
		end
		return step.text, step.target
	elseif step.event == "upgrade" then
		local cost = Economy.upgradeCost("orbValue", Economy.upgradeLevel(profile, "orbValue")) or 0
		if profile.cash < cost then
			return earn("Orb Value (" .. cost .. " Cash)")
		end
		return step.text, step.target
	end
	return step.text, step.target
end

return Tutorial
