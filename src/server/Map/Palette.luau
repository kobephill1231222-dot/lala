--!strict
-- Art-direction palette: bright afternoon light on vermilion lacquer, pale stone, warm wood
-- and fresh greens, with violet cursed energy as the accent. Everything in the map pulls
-- from here so the world stays cohesive.

local rgb = Color3.fromRGB

return {
	-- Wood
	DarkWood = rgb(78, 56, 44),
	Wood = rgb(128, 92, 64),
	AgedWood = rgb(160, 122, 88),
	Lacquer = rgb(204, 58, 42), -- vermilion for torii, rails and pillars
	LacquerDark = rgb(150, 40, 34),
	Black = rgb(34, 30, 34),
	Gold = rgb(236, 190, 90),

	-- Stone
	Stone = rgb(170, 166, 160),
	StoneDark = rgb(126, 122, 120),
	StoneLight = rgb(206, 202, 194),
	Moss = rgb(96, 130, 70),
	Gravel = rgb(200, 186, 156),
	Paving = rgb(186, 180, 170),
	PavingLight = rgb(222, 216, 204),
	RoofTile = rgb(62, 70, 88),
	Plaster = rgb(240, 234, 220),

	-- Light & energy
	Lantern = rgb(255, 186, 104),
	LanternPaper = rgb(255, 196, 128),
	LanternLight = rgb(255, 184, 110),
	Violet = rgb(170, 90, 255),
	VioletDeep = rgb(110, 50, 190),
	VioletLight = rgb(214, 170, 255),
	Ember = rgb(255, 130, 70),

	-- Plants
	Grass = rgb(112, 164, 82),
	GrassDark = rgb(86, 136, 66),
	Hedge = rgb(70, 122, 64),
	Foliage = rgb(84, 140, 70),
	FoliageDark = rgb(56, 104, 62),
	Pine = rgb(62, 118, 74),
	Bamboo = rgb(132, 168, 86),
	BambooDark = rgb(96, 128, 64),
	BambooLeaf = rgb(104, 152, 76),
	Maple = rgb(222, 96, 60),
	Sakura = rgb(255, 184, 208),
	SakuraDeep = rgb(244, 150, 186),
	SpiritLeaf = rgb(150, 110, 210),
	SpiritLeafLight = rgb(190, 150, 240),
	CursedBark = rgb(60, 48, 58),
	Lily = rgb(224, 50, 60),
	Mountain = rgb(150, 166, 192),

	-- Fabric & paper
	Paper = rgb(246, 240, 224),
	Rope = rgb(196, 170, 120),
	Noren = rgb(40, 50, 90),
	NorenAccent = rgb(150, 80, 200),
	Tatami = rgb(204, 196, 140),
}
