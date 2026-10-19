--!nocheck
-- Unit tests for the top-down camera: the view's geometry, Your Farm upright on screen, and
-- which parts fade overhead (checked on the real map).
return function(ctx)
	local kit, sb = ctx.kit, ctx.sandbox
	local describe, it, expect = kit.describe, kit.it, kit.expect

	local Cam = sb.requirePath("ReplicatedStorage/Shared/Visuals/TopDownCamera")
	local Layout = sb.requirePath("ReplicatedStorage/Shared/Config/FarmLayout")
	local CameraController =
		sb.requirePath("StarterPlayer/StarterPlayerScripts/Client/Controllers/CameraController")
	local Instance, CFrame, Vector3 = sb.globals.Instance, sb.globals.CFrame, sb.globals.Vector3

	local function flat(v)
		return Vector3.new(v.X, 0, v.Z).Unit
	end

	describe("TopDownCamera", function()
		it("looks steeply down on the target from the set distance", function()
			local target = Vector3.new(10, 3, -20)
			for _, yaw in { 0, 90, -150, 210 } do
				local cf = Cam.frame(target, yaw, Cam.Pitch, 90)
				expect((cf.Position - target).Magnitude).toBeNear(90, 1e-3)
				expect(cf.LookVector.Y).toBeNear(-math.sin(math.rad(Cam.Pitch)), 1e-3)
				-- The target is dead centre.
				local toTarget = (target - cf.Position).Unit
				expect(cf.LookVector:Dot(toTarget)).toBeNear(1, 1e-6)
			end
		end)

		it("keeps screen-up on the chosen ground direction", function()
			for _, dir in { Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), Vector3.new(-0.6, 0, 0.8) } do
				local cf = Cam.frame(Vector3.zero, Cam.yawFacing(dir), Cam.Pitch, 90)
				expect(flat(cf.UpVector):Dot(dir)).toBeNear(1, 1e-4)
				-- Screen-right is the ground direction to the right of it.
				expect(math.abs(cf.RightVector.Y)).toBeLessThan(1e-4)
			end
		end)

		it("shows each farm upright: its back at the top, the plaza below", function()
			for farm = 1, Layout.FarmCount do
				local floor = Layout.farmFloor(farm)
				local cf = Cam.frame(floor.Position, CameraController.yawFor(farm), Cam.Pitch, 90)
				local back = (floor * CFrame.new(0, 0, Layout.FarmDepth / 2)).Position
				local plaza = Vector3.new(0, 0, 0)
				local up = flat(cf.UpVector)
				expect(up:Dot(flat(back - floor.Position))).toBeNear(1, 1e-4)
				expect(up:Dot(plaza - floor.Position) < 0).toBeTruthy()
			end
		end)

		it("indexes only parts high enough to hide you, and finds those above you", function()
			local folder = Instance.new("Folder")
			local function part(size, cf)
				local p = Instance.new("Part")
				p.Size, p.CFrame, p.Parent = size, cf, folder
				return p
			end
			local roof =
				part(Vector3.new(20, 1, 12), CFrame.new(0, 12, 0) * CFrame.Angles(math.rad(25), 0, 0))
			part(Vector3.new(40, 1, 40), CFrame.new(0, -0.5, 0)) -- ground
			part(Vector3.new(1, 12, 1), CFrame.new(9, 6, 5)) -- pillar from the ground up
			local index = Cam.indexOverhead({ folder })
			expect(index.count).toBe(1)
			local under = Cam.over(index, Vector3.new(4, 3, 2))
			expect(#under).toBe(1)
			expect(under[1].Name).toBe(roof.Name)
			expect(#Cam.over(index, Vector3.new(30, 3, 0))).toBe(0) -- outside its footprint
			expect(#Cam.over(index, Vector3.new(0, 15, 0))).toBe(0) -- standing on top of it
			local kept = Cam.indexOverhead({ folder }, 0, function()
				return true
			end)
			expect(kept.count).toBe(0)
		end)

		it("fades what's over you and restores it when you leave", function()
			local folder = Instance.new("Folder")
			local roof = Instance.new("Part")
			roof.Size, roof.CFrame, roof.Parent = Vector3.new(10, 1, 10), CFrame.new(0, 14, 0), folder
			Cam.state.overhead = Cam.indexOverhead({ folder })
			Cam.updateFades(Vector3.new(1, 3, 1))
			expect(roof.LocalTransparencyModifier).toBeNear(Cam.FadedTransparency, 1e-6)
			Cam.updateFades(Vector3.new(40, 3, 1))
			expect(roof.LocalTransparencyModifier).toBe(0)
			Cam.state.overhead = nil
			Cam.state.faded = {}
		end)

		it("on the real map, roofs and gates fade but the Orb Box and display crates stay", function()
			local MapBuilder = sb.requirePath("ServerScriptService/Server/Map/MapBuilder")
			local map = MapBuilder.buildStructures(Instance.new("Folder"))
			local index = Cam.indexOverhead({ map }, 0, CameraController.keep)
			expect(index.count > 1000).toBeTruthy()
			local function names(pos)
				local out = {}
				for _, p in Cam.over(index, pos + Vector3.new(0, 3, 0)) do
					table.insert(out, p:GetFullName())
				end
				return table.concat(out, " ")
			end
			-- Walking under the Sell Stand's roof and a farm's gate fades them.
			expect(string.find(names(Layout.SellStand), "SellStand") ~= nil).toBeTruthy()
			expect(string.find(names(Layout.homeCFrame(1).Position - Vector3.new(0, 3, 0)), "Gate") ~= nil).toBeTruthy()
			for farm = 1, Layout.FarmCount do
				-- Nothing overhead hides a production slot or crate pad, and the box never fades.
				for slot = 1, 10 do
					expect(names(Layout.slotWorld(farm, slot).Position)).toBe("")
				end
				for pad = 1, 4 do
					expect(names(Layout.padWorld(farm, pad).Position)).toBe("")
				end
				expect(string.find(names(Layout.boxWorld(farm)), "OrbBox")).toBe(nil)
			end
			expect(string.find(names(Layout.CrateShop), "Displays")).toBe(nil)
		end)
	end)
end
