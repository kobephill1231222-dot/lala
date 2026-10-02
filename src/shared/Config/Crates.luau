--!strict
-- Crates hold one Sorcerer. Buy them at the Crate Shop, place them on a Crate Pad at your
-- farm, wait out the Opening Time (it keeps counting while you're offline), then Open.

export type CrateDef = {
	id: string,
	name: string,
	price: number, -- Cash; 0 = not sold (starter)
	openingTime: number, -- seconds, before Opening Speed upgrades
	odds: { [string]: number }, -- relative weights per rarity
	color: Color3, -- trim / glow colour
	body: Color3, -- wood colour
	order: number,
	guaranteed: string?, -- always gives this sorcerer (starter crate)
}

local rgb = Color3.fromRGB

local Crates = {}

Crates.List = {
	{
		id = "starter",
		name = "Starter Crate",
		price = 0,
		openingTime = 10,
		odds = { Common = 1 },
		color = rgb(220, 220, 230),
		body = rgb(120, 90, 66),
		order = 0,
		guaranteed = "kai",
	},
	{
		id = "basic",
		name = "Basic Crate",
		price = 60,
		openingTime = 30,
		odds = { Common = 75, Uncommon = 22, Rare = 3 },
		color = rgb(200, 160, 110),
		body = rgb(110, 78, 54),
		order = 1,
	},
	{
		id = "rare",
		name = "Rare Crate",
		price = 2000,
		openingTime = 120,
		odds = { Common = 20, Uncommon = 50, Rare = 27, Epic = 3 },
		color = rgb(70, 160, 255),
		body = rgb(52, 60, 90),
		order = 2,
	},
	{
		id = "epic",
		name = "Epic Crate",
		price = 75000,
		openingTime = 300,
		odds = { Uncommon = 25, Rare = 50, Epic = 24, Legendary = 1 },
		color = rgb(180, 100, 255),
		body = rgb(60, 40, 84),
		order = 3,
	},
	{
		id = "legendary",
		name = "Legendary Crate",
		price = 2500000,
		openingTime = 600,
		odds = { Rare = 35, Epic = 55, Legendary = 10 },
		color = rgb(255, 190, 60),
		body = rgb(70, 50, 30),
		order = 4,
	},
} :: { CrateDef }

Crates.ById = {} :: { [string]: CrateDef }
for _, def in Crates.List do
	Crates.ById[def.id] = def
end

-- Luck upgrade: per level, rarer weights grow by this fraction.
Crates.LuckPerLevel = { Uncommon = 0.03, Rare = 0.06, Epic = 0.1, Legendary = 0.12 }

function Crates.get(id: string): CrateDef?
	return Crates.ById[id]
end

return Crates
