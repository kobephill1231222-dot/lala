--!nocheck
-- Server hit-validation math.
return function(ctx)
	local kit, sb = ctx.kit, ctx.sandbox
	local describe, it, expect = kit.describe, kit.it, kit.expect
	local Vector3 = sb.globals.Vector3

	local CombatMath = sb.requirePath("ReplicatedStorage/Shared/Rules/CombatMath")
	local Abilities = sb.requirePath("ReplicatedStorage/Shared/Config/Abilities")
	local Layout = sb.requirePath("ReplicatedStorage/Shared/Config/MapLayout")

	local origin = Vector3.new(0, 0, 0)
	local north = Vector3.new(0, 0, -1)

	describe("CombatMath.sanitizeAim", function()
		it("flattens and normalises valid aims", function()
			local aim = CombatMath.sanitizeAim(Vector3.new(0, 0.5, -2))
			expect(aim.Y).toBe(0)
			expect(aim.Magnitude).toBeNear(1, 1e-5)
		end)
		it("rejects junk", function()
			expect(CombatMath.sanitizeAim("north")).toBe(nil)
			expect(CombatMath.sanitizeAim(Vector3.new(0 / 0, 0, 1))).toBe(nil)
			expect(CombatMath.sanitizeAim(Vector3.new(0, 1, 0))).toBe(nil)
			expect(CombatMath.sanitizeAim(Vector3.new(1e9, 0, 0))).toBe(nil)
		end)
	end)

	describe("CombatMath.hits", function()
		local strike = Abilities.ById.strike
		local lance = Abilities.ById.lance
		local burst = Abilities.ById.burst
		it("arc hits in front and misses behind", function()
			expect(
				CombatMath.hits("Arc", origin, north, strike.range, strike.width, Vector3.new(0, 0, -8), 2)
			).toBe(true)
			expect(CombatMath.hits("Arc", origin, north, strike.range, strike.width, Vector3.new(0, 0, 8), 2)).toBe(
				false
			)
			expect(
				CombatMath.hits("Arc", origin, north, strike.range, strike.width, Vector3.new(0, 0, -20), 2)
			).toBe(false)
		end)
		it("line hits along the aim within its width", function()
			expect(
				CombatMath.hits("Line", origin, north, lance.range, lance.width, Vector3.new(3, 0, -40), 2)
			).toBe(true)
			expect(
				CombatMath.hits("Line", origin, north, lance.range, lance.width, Vector3.new(12, 0, -20), 2)
			).toBe(false)
			expect(CombatMath.hits("Line", origin, north, lance.range, lance.width, Vector3.new(0, 0, 10), 2)).toBe(
				false
			)
		end)
		it("radius hits all around but not far away or far above", function()
			expect(CombatMath.hits("Radius", origin, north, burst.range, 0, Vector3.new(-15, 0, 5), 2)).toBe(
				true
			)
			expect(CombatMath.hits("Radius", origin, north, burst.range, 0, Vector3.new(30, 0, 0), 2)).toBe(
				false
			)
			expect(CombatMath.hits("Radius", origin, north, burst.range, 0, Vector3.new(0, 40, 0), 2)).toBe(
				false
			)
		end)
	end)

	describe("MapLayout zones", function()
		it("puts the forest gate travel point inside the combat zone", function()
			expect(Layout.inForest(Layout.TravelPoints.Forest.Position)).toBe(true)
		end)
		it("keeps sanctuaries, spawn and courtyard out of the combat zone", function()
			for i = 1, #Layout.PlotAngles do
				expect(Layout.inForest(Layout.plotCFrame(i).Position)).toBe(false)
			end
			expect(Layout.inForest(Layout.SpawnPosition)).toBe(false)
			expect(Layout.inForest(Layout.CourtyardCenter)).toBe(false)
		end)
		it("puts the dojo travel point inside the practice yard", function()
			expect(Layout.inDojo(Layout.TravelPoints.Dojo.Position)).toBe(true)
		end)
		it("places summoning travel point within ritual range", function()
			expect(
				(Layout.TravelPoints.Courtyard.Position - Layout.CourtyardCenter).Magnitude
					< Layout.SummonRadius
			).toBe(true)
		end)
		it("keeps sanctuaries apart from each other", function()
			for i = 1, #Layout.PlotAngles do
				for j = i + 1, #Layout.PlotAngles do
					local d = (Layout.plotCFrame(i).Position - Layout.plotCFrame(j).Position).Magnitude
					expect(d > Layout.PlotSize * 1.5).toBe(true)
				end
			end
		end)
	end)
end
