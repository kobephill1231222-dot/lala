--!strict
-- Everything around the farms: the grass ground, rolling hills and distant mountains on the
-- horizon, and trees in the gaps between farms. Built from parts (no Terrain) so the place
-- looks the same in Studio's edit mode as it does in play.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Config.FarmLayout)
local PartKit = require(ReplicatedStorage.Shared.Visuals.PartKit)
local Prng = require(ReplicatedStorage.Shared.Util.Prng)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)

local Scenery = {}

local V3 = Vector3.new
local rad = math.rad
local M = Enum.Material

local function polar(angleDeg: number, radius: number, y: number?): Vector3
	local a = rad(angleDeg)
	return V3(math.sin(a) * radius, y or 0, -math.cos(a) * radius)
end

function Scenery.build(parent: Instance): Model
	local model = PartKit.model(parent, "Scenery")
	local rng: any = Prng.new(2024)

	Kit.part(model, "Ground", V3(2048, 4, 2048), CFrame.new(0, -2, 0), Palette.Grass, M.Grass)

	-- Rolling hills ring the valley; mountains beyond them.
	local hills = PartKit.model(model, "Hills")
	for i = 0, 23 do
		local angle = i * 15 + rng:NextNumber(-5, 5)
		local r = rng:NextNumber(330, 380)
		local w = rng:NextNumber(140, 210)
		local h = rng:NextNumber(50, 90)
		Kit.ellipsoid(
			hills,
			"Hill",
			V3(w, h, w * rng:NextNumber(0.7, 1)),
			CFrame.new(polar(angle, r, -h * 0.18)) * CFrame.Angles(0, rad(angle), 0),
			if i % 2 == 0 then Palette.Grass else Palette.GrassDark,
			M.Grass,
			{
				CastShadow = false,
			}
		)
	end
	for i = 0, 15 do
		local angle = i * 22.5 + rng:NextNumber(-6, 6)
		local r = rng:NextNumber(620, 720)
		local w = rng:NextNumber(260, 380)
		local h = rng:NextNumber(150, 260)
		Kit.ellipsoid(
			hills,
			"Mountain",
			V3(w, h * 2, w * 0.8),
			CFrame.new(polar(angle, r, -h * 0.25)) * CFrame.Angles(0, rad(angle), 0),
			Palette.Mountain,
			M.Rock,
			{
				CanCollide = false,
				CanQuery = false,
				CastShadow = false,
			}
		)
	end

	-- Trees between the farms and behind them.
	local trees = PartKit.model(model, "Trees")
	for _, gap in { 0, 60, 120, 180, 240, 300 } do
		-- A sakura and pines in each gap between neighbouring farms
		Kit.maple(trees, polar(gap, 122, 0), 1.5, rng, Palette.Sakura)
		for k = 1, 3 do
			Kit.pine(
				trees,
				polar(gap + rng:NextNumber(-6, 6), 150 + k * 24, 0),
				rng:NextNumber(1.1, 1.5),
				rng
			)
		end
		Kit.stoneLantern(trees, CFrame.new(polar(gap - 5, 104, 0)), 1.4, true)
		Kit.stoneLantern(trees, CFrame.new(polar(gap + 5, 104, 0)), 1.4, true)
	end
	for i = 0, 35 do
		local angle = i * 10 + rng:NextNumber(-3, 3)
		local r = Layout.FarmRadius + Layout.FarmDepth / 2 + rng:NextNumber(18, 50)
		if rng:NextNumber() < 0.7 then
			Kit.pine(trees, polar(angle, r, 0), rng:NextNumber(1.1, 1.6), rng)
		else
			Kit.maple(
				trees,
				polar(angle, r, 0),
				rng:NextNumber(1.2, 1.6),
				rng,
				if rng:NextNumber() < 0.5 then Palette.Maple else Palette.SakuraDeep
			)
		end
	end
	for i = 0, 11 do
		local angle = i * 30 + 15
		Kit.bamboo(trees, polar(angle, 300, 0), rng, 14, 10, 18, 30)
	end
	return model
end

return Scenery
