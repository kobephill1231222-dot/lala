--!strict
-- Restrained art-direction palette: dark wood, weathered stone, warm lantern light and
-- violet cursed energy. Everything in the map pulls from here so the world stays cohesive.

local rgb = Color3.fromRGB

return {
	-- Wood
	DarkWood = rgb(46, 34, 30),
	Wood = rgb(78, 56, 44),
	AgedWood = rgb(104, 80, 62),
	Lacquer = rgb(98, 34, 30), -- deep, dusky vermilion for torii and bridges
	LacquerDark = rgb(62, 24, 24),
	Black = rgb(22, 20, 24),

	-- Stone
	Stone = rgb(112, 108, 112),
	StoneDark = rgb(78, 76, 82),
	StoneLight = rgb(150, 146, 146),
	Moss = rgb(70, 88, 56),
	Gravel = rgb(132, 126, 124),
	RoofTile = rgb(50, 50, 60),
	Plaster = rgb(206, 196, 178),

	-- Light & energy
	Lantern = rgb(255, 176, 96),
	LanternPaper = rgb(255, 178, 110),
	LanternLight = rgb(255, 168, 92),
	Violet = rgb(170, 90, 255),
	VioletDeep = rgb(96, 40, 170),
	VioletLight = rgb(214, 170, 255),
	Ember = rgb(255, 120, 60),

	-- Plants
	Foliage = rgb(48, 62, 44),
	FoliageDark = rgb(34, 44, 34),
	Pine = rgb(48, 70, 52),
	Bamboo = rgb(96, 118, 66),
	BambooDark = rgb(66, 84, 50),
	BambooLeaf = rgb(70, 96, 52),
	Maple = rgb(150, 52, 40),
	SpiritLeaf = rgb(82, 50, 128),
	SpiritLeafLight = rgb(132, 86, 190),
	CursedBark = rgb(34, 28, 36),
	Lily = rgb(214, 36, 48),

	-- Fabric & paper
	Paper = rgb(238, 232, 216),
	Rope = rgb(170, 148, 108),
	Noren = rgb(40, 44, 70),
	NorenAccent = rgb(130, 60, 170),
}
