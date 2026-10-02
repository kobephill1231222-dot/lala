--!strict
-- Every collectible unit in Cursebound Farm. All names, designs and abilities are original.
-- `rate` is cursed energy per second at level 1, `power` feeds combat damage when the unit is placed.
-- `look` is interpreted by Shared/Visuals/CharacterModels.

export type CharacterDef = {
	id: string,
	name: string,
	title: string,
	rarity: string,
	kind: "Sorcerer" | "Spirit",
	rate: number,
	power: number,
	affinity: string,
	description: string,
	look: { [string]: any },
}

local rgb = Color3.fromRGB

local list: { CharacterDef } = {
	-- COMMON ---------------------------------------------------------------
	{
		id = "tomo",
		name = "Tomo",
		title = "Lantern Wisp",
		rarity = "Common",
		kind = "Spirit",
		rate = 1.0,
		power = 4,
		affinity = "Flame",
		description = "A paper-lantern spirit who refuses to go out. Hums while it works.",
		look = {
			template = "Lantern",
			paper = rgb(236, 196, 140),
			rib = rgb(92, 52, 34),
			glow = rgb(255, 170, 84),
			eye = rgb(40, 20, 30),
			tongue = rgb(214, 70, 82),
		},
	},
	{
		id = "ren",
		name = "Ren Asagiri",
		title = "Talisman Apprentice",
		rarity = "Common",
		kind = "Sorcerer",
		rate = 1.3,
		power = 6,
		affinity = "Paper",
		description = "First-year at the sanctuary. Writes seals faster than he can read them.",
		look = {
			template = "Sorcerer",
			skin = rgb(242, 206, 176),
			hair = rgb(84, 56, 44),
			hairStyle = "Short",
			outfit = rgb(36, 38, 56),
			trim = rgb(214, 196, 150),
			pants = rgb(30, 30, 40),
			eyes = rgb(70, 46, 36),
			accessories = { "Talismans" },
			aura = rgb(230, 220, 190),
		},
	},
	{
		id = "gama",
		name = "Gama",
		title = "Mossback Toad",
		rarity = "Common",
		kind = "Spirit",
		rate = 1.6,
		power = 5,
		affinity = "Earth",
		description = "Sat in the shrine pond for a century. Still deciding whether to move.",
		look = {
			template = "Toad",
			body = rgb(92, 116, 70),
			belly = rgb(196, 186, 140),
			moss = rgb(70, 132, 64),
			eye = rgb(250, 210, 90),
			hat = rgb(186, 150, 92),
		},
	},

	-- RARE -----------------------------------------------------------------
	{
		id = "suzu",
		name = "Suzu Amane",
		title = "Bell Warden",
		rarity = "Rare",
		kind = "Sorcerer",
		rate = 4.0,
		power = 14,
		affinity = "Sound",
		description = "Her staff rings once for every curse she has sealed. It is rarely quiet.",
		look = {
			template = "Sorcerer",
			skin = rgb(246, 214, 190),
			hair = rgb(222, 224, 236),
			hairStyle = "Bob",
			outfit = rgb(246, 244, 250),
			trim = rgb(196, 54, 70),
			pants = rgb(140, 36, 52),
			eyes = rgb(196, 54, 70),
			accessories = { "BellStaff", "Sash" },
			aura = rgb(255, 120, 140),
		},
	},
	{
		id = "hotaru",
		name = "Hotaru",
		title = "Moonlit Moth",
		rarity = "Rare",
		kind = "Spirit",
		rate = 4.5,
		power = 12,
		affinity = "Light",
		description = "Drawn to lanterns, repelled by sunrise. Leaves silver dust on everything.",
		look = {
			template = "Moth",
			body = rgb(70, 74, 104),
			wing = rgb(170, 220, 255),
			wingEdge = rgb(90, 130, 220),
			eye = rgb(220, 250, 255),
		},
	},
	{
		id = "daichi",
		name = "Daichi Ishigami",
		title = "Stonefist",
		rarity = "Rare",
		kind = "Sorcerer",
		rate = 3.6,
		power = 18,
		affinity = "Earth",
		description = "Trains by punching the mountain. The mountain is losing.",
		look = {
			template = "Sorcerer",
			skin = rgb(204, 156, 120),
			hair = rgb(34, 30, 34),
			hairStyle = "Spiky",
			outfit = rgb(58, 52, 46),
			trim = rgb(214, 150, 70),
			pants = rgb(46, 42, 38),
			eyes = rgb(214, 150, 70),
			accessories = { "Gauntlets", "Headband" },
			aura = rgb(214, 150, 70),
		},
	},

	-- EPIC -----------------------------------------------------------------
	{
		id = "kaito",
		name = "Kaito Minase",
		title = "Tidecutter",
		rarity = "Epic",
		kind = "Sorcerer",
		rate = 13,
		power = 45,
		affinity = "Water",
		description = "Draws his blade only once per fight. It is always enough.",
		look = {
			template = "Sorcerer",
			skin = rgb(240, 206, 178),
			hair = rgb(28, 44, 72),
			hairStyle = "Ponytail",
			outfit = rgb(24, 36, 58),
			trim = rgb(70, 214, 220),
			pants = rgb(20, 28, 44),
			eyes = rgb(70, 214, 220),
			accessories = { "KatanaBack", "Scarf" },
			aura = rgb(70, 214, 220),
		},
	},
	{
		id = "kagerou",
		name = "Kagerou",
		title = "The Hollow Mask",
		rarity = "Epic",
		kind = "Spirit",
		rate = 15,
		power = 40,
		affinity = "Shadow",
		description = "A festival mask that wandered off on its own. Nobody remembers its wearer.",
		look = {
			template = "Mask",
			mask = rgb(238, 232, 222),
			marking = rgb(196, 40, 60),
			cloak = rgb(22, 18, 28),
			eye = rgb(255, 80, 110),
		},
	},
	{
		id = "rin",
		name = "Rin Hoshizora",
		title = "Starbow",
		rarity = "Epic",
		kind = "Sorcerer",
		rate = 12,
		power = 50,
		affinity = "Star",
		description = "Her arrows are borrowed from constellations. She always returns them.",
		look = {
			template = "Sorcerer",
			skin = rgb(248, 220, 200),
			hair = rgb(200, 186, 236),
			hairStyle = "Long",
			outfit = rgb(44, 40, 76),
			trim = rgb(255, 222, 140),
			pants = rgb(36, 32, 60),
			eyes = rgb(255, 222, 140),
			accessories = { "StarBow" },
			aura = rgb(255, 222, 140),
		},
	},

	-- LEGENDARY ------------------------------------------------------------
	{
		id = "akane",
		name = "Akane Kurenai",
		title = "Vermilion Blade",
		rarity = "Legendary",
		kind = "Sorcerer",
		rate = 42,
		power = 150,
		affinity = "Flame",
		description = "Heir to a sealed flame technique. The seal is mostly decorative now.",
		look = {
			template = "Sorcerer",
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
		},
	},
	{
		id = "ikazuchi",
		name = "Ikazuchi",
		title = "Thunder Cub",
		rarity = "Legendary",
		kind = "Spirit",
		rate = 48,
		power = 130,
		affinity = "Thunder",
		description = "Fell from a storm cloud as a pup. Still growls at drums.",
		look = {
			template = "Wolf",
			fur = rgb(236, 232, 214),
			accent = rgb(255, 214, 60),
			eye = rgb(120, 220, 255),
		},
	},
	{
		id = "shion",
		name = "Shion Yozora",
		title = "Moonveil Oracle",
		rarity = "Legendary",
		kind = "Sorcerer",
		rate = 45,
		power = 140,
		affinity = "Moon",
		description = "Reads tomorrow in the reflection of shrine water. Rarely shares spoilers.",
		look = {
			template = "Sorcerer",
			skin = rgb(250, 224, 210),
			hair = rgb(176, 150, 230),
			hairStyle = "Long",
			outfit = rgb(244, 240, 252),
			trim = rgb(150, 110, 240),
			pants = rgb(120, 96, 190),
			eyes = rgb(170, 140, 255),
			accessories = { "FoxMaskSide", "Sash", "Orbs" },
			aura = rgb(170, 140, 255),
		},
	},

	-- MYTHIC ---------------------------------------------------------------
	{
		id = "yoru",
		name = "Yoru Mikazuki",
		title = "The Veiled Sovereign",
		rarity = "Mythic",
		kind = "Sorcerer",
		rate = 150,
		power = 480,
		affinity = "Void",
		description = "The sanctuary's oldest guardian. Where she walks, curses kneel.",
		look = {
			template = "Sorcerer",
			skin = rgb(244, 224, 214),
			hair = rgb(20, 18, 28),
			hairStyle = "Swept",
			hairStreak = rgb(240, 236, 255),
			outfit = rgb(16, 14, 24),
			trim = rgb(170, 90, 255),
			pants = rgb(18, 16, 26),
			eyes = rgb(190, 110, 255),
			accessories = { "Haori", "Halo", "Veil" },
			aura = rgb(170, 90, 255),
			voidAura = true,
		},
	},
	{
		id = "kokuyo",
		name = "Kokuyo",
		title = "The Obsidian Maw",
		rarity = "Mythic",
		kind = "Spirit",
		rate = 165,
		power = 450,
		affinity = "Void",
		description = "A sealed calamity that chose to guard rather than devour. For now.",
		look = {
			template = "Serpent",
			scale = rgb(48, 40, 62),
			crack = rgb(186, 90, 255),
			horn = rgb(220, 210, 230),
			eye = rgb(255, 70, 120),
		},
	},
}

local Characters = {}
Characters.List = list
Characters.ById = {} :: { [string]: CharacterDef }
Characters.ByRarity = {} :: { [string]: { CharacterDef } }

for _, def in list do
	assert(Characters.ById[def.id] == nil, "duplicate character id " .. def.id)
	Characters.ById[def.id] = def
	local bucket = Characters.ByRarity[def.rarity]
	if not bucket then
		bucket = {}
		Characters.ByRarity[def.rarity] = bucket
	end
	table.insert(bucket, def)
end

Characters.StarterId = "tomo"

function Characters.get(id: string): CharacterDef?
	return Characters.ById[id]
end

return Characters
