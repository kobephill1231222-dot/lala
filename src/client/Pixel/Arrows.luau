--!strict
-- Pixel arrows pointing in the 8 compass directions (for guidance at the screen's edge),
-- generated from two drawn shapes (straight and diagonal) by mirroring and transposing, in the
-- same gold-and-brown colours as the arrow icon.
--
--   Arrows.get("ne")  -- Sprite.Def, 9x9, anchor at the centre
--   Arrows.direction(dx, dy)  -- "e", "se", "s", ... for a screen-space vector

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared.Pixel.Palette)
local Sprite = require(Shared.Pixel.Sprite)

local Arrows = {}

local SIZE = 9
local PALETTE = { k = Palette.Brown, y = Palette.Yellow, a = Palette.Amber, w = Palette.White }

type Grid = { string }

-- Rasterises `inside(x, y)` into rows: outline where a neighbour is outside, light above the
-- arrow's axis, shade below it.
local function draw(inside: (number, number) -> boolean, below: (number, number) -> boolean): Grid
	local rows: Grid = {}
	for y = 0, SIZE - 1 do
		local row = table.create(SIZE, ".")
		for x = 0, SIZE - 1 do
			if inside(x, y) then
				local edge = false
				for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
					local nx, ny = x + d[1], y + d[2]
					if nx < 0 or ny < 0 or nx >= SIZE or ny >= SIZE or not inside(nx, ny) then
						edge = true
					end
				end
				row[x + 1] = if edge then "k" elseif below(x, y) then "a" else "y"
			end
		end
		rows[y + 1] = table.concat(row)
	end
	return rows
end

-- Pointing right: a shaft and a triangular head with its tip at (8, 4).
local EAST = draw(function(x, y)
	local shaft = x <= 4 and y >= 3 and y <= 5
	local head = x >= 4 and math.abs(y - 4) <= 8 - x
	return shaft or head
end, function(_, y)
	return y > 4
end)

-- Pointing down-right: a diagonal shaft and a head in the bottom-right corner.
local SOUTHEAST = draw(function(x, y)
	local shaft = math.abs(x - y) <= 1 and x + y < 11
	local head = x + y >= 10
	return shaft or head
end, function(x, y)
	return y > x
end)

local function mirrorX(rows: Grid): Grid
	local out = table.create(#rows)
	for i, row in rows do
		out[i] = string.reverse(row)
	end
	return out
end

local function mirrorY(rows: Grid): Grid
	local out = table.create(#rows)
	for i = #rows, 1, -1 do
		table.insert(out, rows[i])
	end
	return out
end

local function transpose(rows: Grid): Grid
	local out = table.create(#rows)
	for x = 1, #rows[1] do
		local chars = table.create(#rows)
		for y = 1, #rows do
			chars[y] = string.sub(rows[y], x, x)
		end
		out[x] = table.concat(chars)
	end
	return out
end

-- Transposing swaps the light/shade sides too; recolour so light stays on top.
local function relight(rows: Grid): Grid
	local out = table.create(#rows)
	for i, row in rows do
		out[i] = (string.gsub(row, "[ya]", if i <= math.ceil(#rows / 2) then "y" else "a"))
	end
	return out
end

local GRIDS: { [string]: Grid } = {
	e = EAST,
	w = mirrorX(EAST),
	s = relight(transpose(EAST)),
	n = relight(mirrorY(transpose(EAST))),
	se = SOUTHEAST,
	sw = mirrorX(SOUTHEAST),
	ne = mirrorY(SOUTHEAST),
	nw = mirrorX(mirrorY(SOUTHEAST)),
}

local cache: { [string]: Sprite.Def } = {}

function Arrows.get(direction: string): Sprite.Def
	local def = cache[direction]
	if not def then
		def = Sprite.define({
			name = "Arrow_" .. direction,
			palette = PALETTE,
			frames = { GRIDS[direction] or GRIDS.s },
			anchor = { 4, 4 },
		})
		cache[direction] = def
	end
	return def
end

Arrows.Directions = { "e", "se", "s", "sw", "w", "nw", "n", "ne" }

-- The nearest of the 8 directions for a screen-space vector (y down).
function Arrows.direction(dx: number, dy: number): string
	local angle = math.atan2(dy, dx)
	local index = math.floor(angle / (math.pi / 4) + 0.5) % 8
	return Arrows.Directions[index + 1]
end

return Arrows
