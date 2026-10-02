--!nonstrict
-- Visual language for every screen: dark lacquer panels that stay readable over a bright
-- world, gold for Cash, violet for Cursed Orbs, vermilion accents from the shrine gates.

local rgb = Color3.fromRGB

return {
	Panel = rgb(24, 20, 34),
	PanelLight = rgb(38, 32, 52),
	PanelLighter = rgb(54, 46, 72),
	Stroke = rgb(236, 190, 90),
	StrokeSoft = rgb(84, 70, 110),
	Text = rgb(246, 242, 252),
	TextDim = rgb(184, 176, 204),
	TextFaint = rgb(132, 124, 152),
	Violet = rgb(170, 100, 255),
	VioletDark = rgb(100, 52, 180),
	Gold = rgb(255, 200, 90),
	GoldDark = rgb(204, 128, 36),
	Cash = rgb(120, 230, 120),
	CashDark = rgb(40, 150, 70),
	Red = rgb(230, 70, 60),
	RedDark = rgb(150, 36, 34),
	Seal = rgb(255, 82, 110),
	Good = rgb(120, 230, 150),
	Bad = rgb(255, 110, 110),
	Shadow = rgb(6, 4, 10),

	Title = Font.fromEnum(Enum.Font.FredokaOne),
	TitleBold = Font.fromEnum(Enum.Font.FredokaOne),
	Body = Font.fromEnum(Enum.Font.GothamMedium),
	BodyBold = Font.fromEnum(Enum.Font.GothamBold),
	Heavy = Font.fromEnum(Enum.Font.GothamBlack),

	Corner = 12,
}
