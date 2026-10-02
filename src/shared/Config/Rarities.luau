--!strict
-- Rarity tiers. All per-rarity tuning lives here.

export type RarityInfo = {
	id: string,
	rank: number,
	color: Color3,
	glow: Color3,
	maxLevel: number,
	upgradeBase: number, -- Cash to go from level 1 -> 2
	upgradeGrowth: number, -- cost multiplier per level
	sellValue: number, -- Cash for selling a level-1 sorcerer
	auraRate: number, -- particle rate of the placed sorcerer's aura
}

local Rarities = {}

Rarities.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

Rarities.Info = {
	Common = {
		id = "Common",
		rank = 1,
		color = Color3.fromRGB(190, 190, 200),
		glow = Color3.fromRGB(230, 230, 240),
		maxLevel = 10,
		upgradeBase = 15,
		upgradeGrowth = 1.35,
		sellValue = 10,
		auraRate = 0,
	},
	Uncommon = {
		id = "Uncommon",
		rank = 2,
		color = Color3.fromRGB(90, 210, 110),
		glow = Color3.fromRGB(160, 245, 170),
		maxLevel = 15,
		upgradeBase = 60,
		upgradeGrowth = 1.33,
		sellValue = 40,
		auraRate = 2,
	},
	Rare = {
		id = "Rare",
		rank = 3,
		color = Color3.fromRGB(70, 160, 255),
		glow = Color3.fromRGB(150, 205, 255),
		maxLevel = 20,
		upgradeBase = 400,
		upgradeGrowth = 1.3,
		sellValue = 300,
		auraRate = 4,
	},
	Epic = {
		id = "Epic",
		rank = 4,
		color = Color3.fromRGB(180, 100, 255),
		glow = Color3.fromRGB(215, 170, 255),
		maxLevel = 25,
		upgradeBase = 4000,
		upgradeGrowth = 1.28,
		sellValue = 4000,
		auraRate = 8,
	},
	Legendary = {
		id = "Legendary",
		rank = 5,
		color = Color3.fromRGB(255, 190, 60),
		glow = Color3.fromRGB(255, 225, 150),
		maxLevel = 30,
		upgradeBase = 50000,
		upgradeGrowth = 1.26,
		sellValue = 60000,
		auraRate = 14,
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
