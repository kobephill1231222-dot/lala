--!strict
-- The game's pixel palette: ENDESGA 32 (a free, widely used 32-colour pixel-art palette), named
-- for how the game uses each colour. Sprites, tiles and UI all pull from here so the whole
-- screen reads as one piece of pixel art. Sorcerer looks keep their own colours from
-- Config/Sorcerers, snapped to the nearest palette colour by Palette.nearest.

local hex = Color3.fromHex

local Palette = {
	-- Reds, oranges, skin
	Rust = hex("be4a2f"),
	Clay = hex("d77643"),
	Cream = hex("ead4aa"),
	Tan = hex("e4a672"),
	Bark = hex("b86f50"),
	Brown = hex("733e39"),
	DarkBrown = hex("3e2731"),
	Crimson = hex("a22633"),
	Red = hex("e43b44"),
	Orange = hex("f77622"),
	Amber = hex("feae34"),
	Yellow = hex("fee761"),
	-- Greens
	Leaf = hex("63c74d"),
	Grass = hex("3e8948"),
	Pine = hex("265c42"),
	DeepTeal = hex("193c3e"),
	-- Blues
	Navy = hex("124e89"),
	Sky = hex("0099db"),
	Cyan = hex("2ce8f5"),
	-- Greys
	White = hex("ffffff"),
	Mist = hex("c0cbdc"),
	Slate = hex("8b9bb4"),
	Steel = hex("5a6988"),
	Dusk = hex("3a4466"),
	Night = hex("262b44"),
	Ink = hex("181425"),
	-- Accents
	Hot = hex("ff0044"),
	Plum = hex("68386c"),
	Orchid = hex("b55088"),
	Rose = hex("f6757a"),
	Peach = hex("e8b796"),
	Sand = hex("c28569"),
}

Palette.All = {} :: { Color3 }
for name, c in Palette :: any do
	if typeof(c) == "Color3" then
		table.insert(Palette.All, c)
	end
end

-- Nearest palette colour (weighted RGB distance), for snapping config colours.
function Palette.nearest(color: Color3): Color3
	local best, bestD = color, math.huge
	for _, c in Palette.All do
		local dr, dg, db = (c.R - color.R) * 255, (c.G - color.G) * 255, (c.B - color.B) * 255
		local d = 2 * dr * dr + 4 * dg * dg + 3 * db * db
		if d < bestD then
			best, bestD = c, d
		end
	end
	return best
end

-- A darker shade for outlines and shadows (not snapped).
function Palette.shade(color: Color3, amount: number?): Color3
	local k = 1 - (amount or 0.35)
	return Color3.new(color.R * k, color.G * k, color.B * k)
end

return Palette
