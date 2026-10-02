--!strict
-- Summoning rituals offered at the Summoning Courtyard.
-- Weights are relative; Ritual Fortune (luck upgrade) boosts Epic+ weights at roll time.

export type Banner = {
	id: string,
	name: string,
	subtitle: string,
	currency: "energy" | "seals",
	cost: number,
	weights: { [string]: number },
	accent: Color3,
	order: number,
}

local Banners = {}

Banners.List = {
	{
		id = "lantern",
		name = "Lantern Ritual",
		subtitle = "A humble offering of cursed energy.",
		currency = "energy",
		cost = 50,
		weights = { Common = 72, Rare = 24, Epic = 3.7, Legendary = 0.3, Mythic = 0 },
		accent = Color3.fromRGB(255, 176, 92),
		order = 1,
	},
	{
		id = "greater",
		name = "Greater Ritual",
		subtitle = "Rare or better. Echoes reach the Mythic.",
		currency = "energy",
		cost = 3000,
		weights = { Common = 0, Rare = 60, Epic = 33, Legendary = 6.5, Mythic = 0.5 },
		accent = Color3.fromRGB(176, 104, 255),
		order = 2,
	},
	{
		id = "sealed",
		name = "Sealed Ritual",
		subtitle = "Break curse seals won in the forest. Epic or better.",
		currency = "seals",
		cost = 12,
		weights = { Common = 0, Rare = 0, Epic = 72, Legendary = 25, Mythic = 3 },
		accent = Color3.fromRGB(255, 72, 126),
		order = 3,
	},
} :: { Banner }

Banners.ById = {} :: { [string]: Banner }
for _, banner in Banners.List do
	Banners.ById[banner.id] = banner
end

-- Allowed multi-summon sizes.
Banners.AllowedCounts = { [1] = true, [3] = true }

-- A Legendary-or-better unit is guaranteed after this many summons without one.
Banners.PityThreshold = 80

-- Luck bonus per Ritual Fortune level, as a fraction of the base weight.
Banners.LuckPerLevel = {
	Epic = 0.06,
	Legendary = 0.1,
	Mythic = 0.1,
}

function Banners.get(id: string): Banner?
	return Banners.ById[id]
end

return Banners
