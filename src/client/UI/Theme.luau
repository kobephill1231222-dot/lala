--!nonstrict
-- Visual language for every screen, in pixel art: dark Night panels with one-pixel bevels that
-- stay readable over the bright world, Yellow/Amber for Cash, Orchid for Cursed Orbs, Red from
-- the shrine gates. Every colour is an ENDESGA 32 colour from Shared/Pixel/Palette and every
-- font is Arcade (Press Start 2P), drawn at 8 or 16 art pixels by Pixel/Text.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Pixel"):WaitForChild("Palette"))

local arcade = Font.fromEnum(Enum.Font.Arcade)

return {
	Palette = Palette,

	-- Surfaces
	Panel = Palette.Night,
	PanelLight = Palette.Dusk,
	PanelLighter = Palette.Steel,
	Outline = Palette.Ink,
	Stroke = Palette.Amber,
	StrokeSoft = Palette.Steel,

	-- Text
	Text = Palette.White,
	TextDim = Palette.Mist,
	TextFaint = Palette.Slate,
	TextShadow = Palette.Ink,

	-- Accents
	Violet = Palette.Orchid,
	VioletDark = Palette.Plum,
	Gold = Palette.Yellow,
	GoldDark = Palette.Amber,
	Cash = Palette.Leaf,
	CashDark = Palette.Grass,
	Red = Palette.Red,
	RedDark = Palette.Crimson,
	Seal = Palette.Hot,
	Good = Palette.Leaf,
	Bad = Palette.Rose,
	Shadow = Palette.Ink,

	-- Fonts (one pixel font everywhere)
	Title = arcade,
	TitleBold = arcade,
	Body = arcade,
	BodyBold = arcade,
	Heavy = arcade,

	-- Pixel text sizes, in art pixels
	TextSize = 8,
	TitleSize = 16,
	LineHeight = 9,

	Corner = 0, -- pixel art has square corners
}
