--!nonstrict
-- Visual language for every screen: ink-dark lacquer panels, violet cursed energy accents,
-- warm lantern gold for rewards.

local rgb = Color3.fromRGB

return {
	Panel = rgb(20, 16, 30),
	PanelLight = rgb(34, 28, 48),
	PanelLighter = rgb(48, 40, 66),
	Stroke = rgb(120, 76, 200),
	StrokeSoft = rgb(70, 54, 104),
	Text = rgb(240, 234, 250),
	TextDim = rgb(170, 160, 190),
	TextFaint = rgb(120, 110, 140),
	Violet = rgb(170, 100, 255),
	VioletDark = rgb(96, 46, 176),
	Gold = rgb(255, 196, 92),
	GoldDark = rgb(196, 120, 40),
	Seal = rgb(255, 82, 110),
	Good = rgb(120, 230, 150),
	Bad = rgb(255, 110, 110),
	Shadow = rgb(6, 4, 10),

	Title = Font.fromEnum(Enum.Font.Sarpanch),
	TitleBold = Font.new("rbxasset://fonts/families/Sarpanch.json", Enum.FontWeight.Bold),
	Body = Font.fromEnum(Enum.Font.GothamMedium),
	BodyBold = Font.fromEnum(Enum.Font.GothamBold),
	Heavy = Font.fromEnum(Enum.Font.GothamBlack),

	Corner = 12,
}
