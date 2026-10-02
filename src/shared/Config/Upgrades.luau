--!strict
-- Permanent sanctuary upgrades bought with cursed energy at the Talisman Shop.

export type UpgradeDef = {
	id: string,
	name: string,
	description: string,
	maxLevel: number,
	baseCost: number,
	growth: number,
	order: number,
	icon: string,
}

local Upgrades = {}

Upgrades.List = {
	{
		id = "production",
		name = "Focus Training",
		description = "+10% cursed energy from every unit.",
		maxLevel = 30,
		baseCost = 40,
		growth = 1.65,
		order = 1,
		icon = "focus",
	},
	{
		id = "capacity",
		name = "Deeper Well",
		description = "Your Spirit Well stores +2 minutes of output.",
		maxLevel = 12,
		baseCost = 150,
		growth = 1.75,
		order = 2,
		icon = "well",
	},
	{
		id = "combat",
		name = "Combat Mastery",
		description = "+15% damage against curses.",
		maxLevel = 25,
		baseCost = 90,
		growth = 1.6,
		order = 3,
		icon = "combat",
	},
	{
		id = "luck",
		name = "Ritual Fortune",
		description = "Raises Epic, Legendary and Mythic summon odds.",
		maxLevel = 10,
		baseCost = 600,
		growth = 2.1,
		order = 4,
		icon = "luck",
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
