--!strict
-- Every collectible Sorcerer. Names, looks and techniques are original.
--   ops      Orbs per Second at any level
--   orbValue Cash each Cursed Orb is worth at level 1 (Upgrade raises it)
--   style    technique animation: "Cast" | "Punch" | "Slash" | "Shoot"
--   color    colour of the technique and of the orbs it makes
-- `look` is drawn by Shared/Visuals/CharacterModels.

export type Sorcerer = {
	id: string,
	name: string,
	rarity: string,
	ops: number,
	orbValue: number,
	technique: string,
	style: string,
	color: Color3,
	look: { [string]: any },
}

local rgb = Color3.fromRGB

local function look(t: { [string]: any }): { [string]: any }
	t.template = "Sorcerer"
	return t
end

local list: { Sorcerer } = {
	-- COMMON ---------------------------------------------------------------------------
	{
		id = "kai",
		name = "Kai",
		rarity = "Common",
		ops = 1.0,
		orbValue = 2,
		technique = "Spark Palm",
		style = "Punch",
		color = rgb(255, 170, 90),
		look = look({
			skin = rgb(242, 206, 176),
			hair = rgb(230, 120, 140),
			hairStyle = "Spiky",
			outfit = rgb(30, 32, 52),
			trim = rgb(220, 70, 70),
			pants = rgb(26, 28, 42),
			eyes = rgb(170, 90, 60),
			accessories = { "Hood" },
		}),
	},
	{
		id = "mina",
		name = "Mina",
		rarity = "Common",
		ops = 0.8,
		orbValue = 3,
		technique = "Paper Seal",
		style = "Cast",
		color = rgb(240, 225, 190),
		look = look({
			skin = rgb(246, 214, 190),
			hair = rgb(70, 50, 40),
			hairStyle = "Bob",
			outfit = rgb(36, 38, 56),
			trim = rgb(214, 196, 150),
			pants = rgb(30, 30, 40),
			eyes = rgb(70, 46, 36),
			accessories = { "Talismans" },
		}),
	},
	{
		id = "toru",
		name = "Toru",
		rarity = "Common",
		ops = 1.2,
		orbValue = 2,
		technique = "Toad Call",
		style = "Cast",
		color = rgb(130, 200, 100),
		look = look({
			skin = rgb(220, 170, 130),
			hair = rgb(40, 34, 30),
			hairStyle = "Short",
			outfit = rgb(52, 60, 44),
			trim = rgb(150, 190, 90),
			pants = rgb(40, 44, 34),
			eyes = rgb(60, 50, 40),
			accessories = { "Headband" },
			companion = "Toad",
		}),
	},

	-- UNCOMMON -------------------------------------------------------------------------
	{
		id = "rei",
		name = "Rei",
		rarity = "Uncommon",
		ops = 1.0,
		orbValue = 6,
		technique = "Ice Needle",
		style = "Shoot",
		color = rgb(150, 220, 255),
		look = look({
			skin = rgb(244, 220, 204),
			hair = rgb(200, 220, 240),
			hairStyle = "Long",
			outfit = rgb(40, 50, 80),
			trim = rgb(150, 220, 255),
			pants = rgb(32, 40, 64),
			eyes = rgb(120, 200, 255),
			accessories = { "Scarf" },
		}),
	},
	{
		id = "goro",
		name = "Goro",
		rarity = "Uncommon",
		ops = 0.8,
		orbValue = 8,
		technique = "Stone Fist",
		style = "Punch",
		color = rgb(214, 150, 70),
		look = look({
			skin = rgb(204, 156, 120),
			hair = rgb(34, 30, 34),
			hairStyle = "Spiky",
			outfit = rgb(58, 52, 46),
			trim = rgb(214, 150, 70),
			pants = rgb(46, 42, 38),
			eyes = rgb(214, 150, 70),
			accessories = { "Gauntlets", "Headband" },
		}),
	},
	{
		id = "hana",
		name = "Hana",
		rarity = "Uncommon",
		ops = 1.3,
		orbValue = 5,
		technique = "Petal Storm",
		style = "Cast",
		color = rgb(255, 150, 200),
		look = look({
			skin = rgb(248, 220, 200),
			hair = rgb(250, 170, 200),
			hairStyle = "Ponytail",
			outfit = rgb(250, 244, 248),
			trim = rgb(230, 100, 150),
			pants = rgb(200, 70, 120),
			eyes = rgb(230, 90, 140),
			accessories = { "Sash" },
		}),
	},

	-- RARE -----------------------------------------------------------------------------
	{
		id = "suzu",
		name = "Suzu",
		rarity = "Rare",
		ops = 1.0,
		orbValue = 22,
		technique = "Bell Strike",
		style = "Slash",
		color = rgb(255, 120, 140),
		look = look({
			skin = rgb(246, 214, 190),
			hair = rgb(222, 224, 236),
			hairStyle = "Bob",
			outfit = rgb(246, 244, 250),
			trim = rgb(196, 54, 70),
			pants = rgb(140, 36, 52),
			eyes = rgb(196, 54, 70),
			accessories = { "BellStaff", "Sash" },
		}),
	},
	{
		id = "daiki",
		name = "Daiki",
		rarity = "Rare",
		ops = 1.4,
		orbValue = 16,
		technique = "Thunder Kick",
		style = "Punch",
		color = rgb(255, 230, 90),
		look = look({
			skin = rgb(236, 196, 160),
			hair = rgb(250, 220, 120),
			hairStyle = "Spiky",
			outfit = rgb(24, 26, 34),
			trim = rgb(255, 214, 60),
			pants = rgb(24, 26, 34),
			eyes = rgb(255, 214, 60),
			accessories = { "Scarf" },
			companion = "Wolf",
		}),
	},
	{
		id = "nao",
		name = "Nao",
		rarity = "Rare",
		ops = 1.1,
		orbValue = 20,
		technique = "Moth Lantern",
		style = "Cast",
		color = rgb(170, 220, 255),
		look = look({
			skin = rgb(246, 222, 206),
			hair = rgb(60, 70, 110),
			hairStyle = "Long",
			outfit = rgb(44, 50, 84),
			trim = rgb(170, 220, 255),
			pants = rgb(34, 38, 64),
			eyes = rgb(170, 220, 255),
			accessories = { "Orbs" },
			companion = "Moth",
		}),
	},

	-- EPIC -----------------------------------------------------------------------------
	{
		id = "ryo",
		name = "Ryo",
		rarity = "Epic",
		ops = 1.2,
		orbValue = 70,
		technique = "Tide Slash",
		style = "Slash",
		color = rgb(70, 214, 220),
		look = look({
			skin = rgb(240, 206, 178),
			hair = rgb(28, 44, 72),
			hairStyle = "Ponytail",
			outfit = rgb(24, 36, 58),
			trim = rgb(70, 214, 220),
			pants = rgb(20, 28, 44),
			eyes = rgb(70, 214, 220),
			accessories = { "KatanaBack", "Scarf" },
		}),
	},
	{
		id = "emi",
		name = "Emi",
		rarity = "Epic",
		ops = 1.0,
		orbValue = 90,
		technique = "Star Arrow",
		style = "Shoot",
		color = rgb(255, 222, 140),
		look = look({
			skin = rgb(248, 220, 200),
			hair = rgb(200, 186, 236),
			hairStyle = "Long",
			outfit = rgb(44, 40, 76),
			trim = rgb(255, 222, 140),
			pants = rgb(36, 32, 60),
			eyes = rgb(255, 222, 140),
			accessories = { "StarBow" },
		}),
	},
	{
		id = "juzo",
		name = "Juzo",
		rarity = "Epic",
		ops = 1.5,
		orbValue = 55,
		technique = "Mask Curse",
		style = "Cast",
		color = rgb(255, 80, 110),
		look = look({
			skin = rgb(230, 200, 180),
			hair = rgb(30, 24, 30),
			hairStyle = "Swept",
			hairStreak = rgb(220, 60, 80),
			outfit = rgb(30, 22, 30),
			trim = rgb(220, 60, 80),
			pants = rgb(26, 20, 26),
			eyes = rgb(255, 80, 110),
			accessories = { "Haori" },
			companion = "Mask",
		}),
	},

	-- LEGENDARY ------------------------------------------------------------------------
	{
		id = "akane",
		name = "Akane",
		rarity = "Legendary",
		ops = 1.3,
		orbValue = 260,
		technique = "Crimson Blade",
		style = "Slash",
		color = rgb(255, 110, 50),
		look = look({
			skin = rgb(244, 210, 186),
			hair = rgb(196, 36, 44),
			hairStyle = "Long",
			outfit = rgb(26, 20, 24),
			trim = rgb(255, 110, 50),
			pants = rgb(30, 22, 26),
			eyes = rgb(255, 150, 60),
			accessories = { "Haori", "KatanaHip" },
			aura = rgb(255, 110, 50),
			flameAura = true,
		}),
	},
	{
		id = "shion",
		name = "Shion",
		rarity = "Legendary",
		ops = 1.6,
		orbValue = 210,
		technique = "Moon Mirror",
		style = "Cast",
		color = rgb(170, 140, 255),
		look = look({
			skin = rgb(250, 224, 210),
			hair = rgb(176, 150, 230),
			hairStyle = "Long",
			outfit = rgb(244, 240, 252),
			trim = rgb(150, 110, 240),
			pants = rgb(120, 96, 190),
			eyes = rgb(170, 140, 255),
			accessories = { "FoxMaskSide", "Sash", "Orbs" },
			aura = rgb(170, 140, 255),
		}),
	},
	{
		id = "yoru",
		name = "Yoru",
		rarity = "Legendary",
		ops = 2.0,
		orbValue = 200,
		technique = "Void Palm",
		style = "Punch",
		color = rgb(190, 110, 255),
		look = look({
			skin = rgb(244, 224, 214),
			hair = rgb(20, 18, 28),
			hairStyle = "Swept",
			hairStreak = rgb(240, 236, 255),
			outfit = rgb(16, 14, 24),
			trim = rgb(170, 90, 255),
			pants = rgb(18, 16, 26),
			eyes = rgb(190, 110, 255),
			accessories = { "Haori", "Halo" },
			aura = rgb(170, 90, 255),
			voidAura = true,
			companion = "Serpent",
		}),
	},
}

local Sorcerers = {}
Sorcerers.List = list
Sorcerers.ById = {} :: { [string]: Sorcerer }
Sorcerers.ByRarity = {} :: { [string]: { Sorcerer } }

for _, def in list do
	assert(Sorcerers.ById[def.id] == nil, "duplicate sorcerer id " .. def.id)
	Sorcerers.ById[def.id] = def
	Sorcerers.ByRarity[def.rarity] = Sorcerers.ByRarity[def.rarity] or {}
	table.insert(Sorcerers.ByRarity[def.rarity], def)
end

Sorcerers.StarterId = "kai"

function Sorcerers.get(id: string): Sorcerer?
	return Sorcerers.ById[id]
end

return Sorcerers
