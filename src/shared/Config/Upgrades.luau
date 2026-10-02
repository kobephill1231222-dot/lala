--!strict
-- Farm-wide upgrades sold at the Upgrade Shop.

export type UpgradeDef = {
	id: string,
	name: string,
	description: string,
	maxLevel: number,
	baseCost: number,
	growth: number,
	order: number,
	costs: { number }?, -- explicit per-level costs (overrides baseCost/growth)
}

local Upgrades = {}

Upgrades.List = {
	{
		id = "orbValue",
		name = "Orb Value",
		description = "+10% Cash from every Cursed Orb.",
		maxLevel = 50,
		baseCost = 25,
		growth = 1.45,
		order = 1,
	},
	{
		id = "slots",
		name = "More Slots",
		description = "Unlock another production slot.",
		maxLevel = 7, -- 3 free slots + 7 = 10
		baseCost = 0,
		growth = 1,
		order = 2,
		costs = { 150, 1000, 6000, 30000, 150000, 750000, 3000000 },
	},
	{
		id = "boxSize",
		name = "Box Size",
		description = "Your Orb Box holds 35% more Cursed Orbs.",
		maxLevel = 25,
		baseCost = 40,
		growth = 1.6,
		order = 3,
	},
	{
		id = "openSpeed",
		name = "Opening Speed",
		description = "Crates open 6% faster.",
		maxLevel = 10,
		baseCost = 150,
		growth = 1.9,
		order = 4,
	},
	{
		id = "pads",
		name = "More Crate Pads",
		description = "Open another crate at the same time.",
		maxLevel = 2, -- 2 free pads + 2 = 4
		baseCost = 0,
		growth = 1,
		order = 5,
		costs = { 500, 25000 },
	},
	{
		id = "luck",
		name = "Luck",
		description = "Better odds for rare Sorcerers from crates.",
		maxLevel = 10,
		baseCost = 500,
		growth = 2,
		order = 6,
	},
	{
		id = "walkSpeed",
		name = "Walk Speed",
		description = "Move 2 studs/s faster.",
		maxLevel = 5,
		baseCost = 100,
		growth = 2.2,
		order = 7,
	},
} :: { UpgradeDef }

Upgrades.ById = {} :: { [string]: UpgradeDef }
for _, def in Upgrades.List do
	Upgrades.ById[def.id] = def
end

function Upgrades.get(id: string): UpgradeDef?
	return Upgrades.ById[id]
end

return Upgrades
