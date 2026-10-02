--!strict
-- Rarity tiers. Every per-rarity tuning number lives here so balance changes stay in one place.

export type RarityInfo = {
	id: string,
	rank: number,
	displayName: string,
	color: Color3,
	glow: Color3,
	maxLevel: number,
	trainBase: number, -- energy cost to go from level 1 -> 2
	trainGrowth: number, -- cost multiplier per level
	releaseValue: number, -- energy refunded per level when releasing a unit
	auraRate: number, -- particle rate used by visual auras
}

local Rarities = {}

Rarities.Order = { "Common", "Rare", "Epic", "Legendary", "Mythic" }

Rarities.Info = {
	Common = {
		id = "Common",
		rank = 1,
		displayName = "Common",
		color = Color3.fromRGB(178, 174, 190),
		glow = Color3.fromRGB(214, 210, 226),
		maxLevel = 10,
		trainBase = 20,
		trainGrowth = 1.32,
		releaseValue = 8,
		auraRate = 0,
	},
	Rare = {
		id = "Rare",
		rank = 2,
		displayName = "Rare",
		color = Color3.fromRGB(84, 168, 255),
		glow = Color3.fromRGB(140, 200, 255),
		maxLevel = 15,
		trainBase = 90,
		trainGrowth = 1.3,
		releaseValue = 40,
		auraRate = 3,
	},
	Epic = {
		id = "Epic",
		rank = 3,
		displayName = "Epic",
		color = Color3.fromRGB(176, 104, 255),
		glow = Color3.fromRGB(206, 160, 255),
		maxLevel = 20,
		trainBase = 450,
		trainGrowth = 1.28,
		releaseValue = 250,
		auraRate = 6,
	},
	Legendary = {
		id = "Legendary",
		rank = 4,
		displayName = "Legendary",
		color = Color3.fromRGB(255, 186, 64),
		glow = Color3.fromRGB(255, 220, 140),
		maxLevel = 25,
		trainBase = 2600,
		trainGrowth = 1.26,
		releaseValue = 1500,
		auraRate = 10,
	},
	Mythic = {
		id = "Mythic",
		rank = 5,
		displayName = "Mythic",
		color = Color3.fromRGB(255, 72, 126),
		glow = Color3.fromRGB(255, 150, 190),
		maxLevel = 30,
		trainBase = 12000,
		trainGrowth = 1.25,
		releaseValue = 8000,
		auraRate = 16,
	},
} :: { [string]: RarityInfo }

function Rarities.get(id: string): RarityInfo?
	return Rarities.Info[id]
end

function Rarities.rank(id: string): number
	local info = Rarities.Info[id]
	return if info then info.rank else 0
end

return Rarities
