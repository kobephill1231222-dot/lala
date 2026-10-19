--!nocheck
-- Unit tests for the training-post prototype: the hit schedule (one schedule for credit and
-- visuals, chest storage, offline vault), the technique timing and the jointed rig.
return function(ctx)
	local kit, sb, game = ctx.kit, ctx.sandbox, ctx.game
	local describe, it, expect = kit.describe, kit.it, kit.expect

	local HitSchedule = sb.requirePath("ReplicatedStorage/Prototype/HitSchedule")
	local Config = sb.requirePath("ReplicatedStorage/Prototype/PrototypeConfig")
	local Rig = sb.requirePath("ReplicatedStorage/Prototype/Rig")
	local Techniques = sb.requirePath("ReplicatedStorage/Prototype/Techniques")
	local Sorcerers = sb.requirePath("ReplicatedStorage/Shared/Config/Sorcerers")
	local Instance = sb.globals.Instance
	local CFrame = sb.globals.CFrame
	local Vector3 = sb.globals.Vector3

	local T0 = 1_700_000_000.37

	local function preset(name, t)
		local p = Config.Presets[name]
		return HitSchedule.new(
			t or T0,
			p.hitInterval,
			p.valuePerHit,
			Config.MinBeatSeconds,
			Config.ChestStorageSeconds
		)
	end

	describe("HitSchedule", function()
		it("groups hits faster than one strike into combos", function()
			expect(HitSchedule.combo(2.0, 1.1)).toBe(1)
			expect(HitSchedule.combo(0.4, 1.1)).toBe(3)
			expect(HitSchedule.combo(0.55, 1.1)).toBe(2) -- exact multiple doesn't round up
			expect(HitSchedule.combo(1.1, 1.1)).toBe(1)
		end)

		it("keeps income the same with or without combos", function()
			local normal, fast = preset("Normal"), preset("Fast")
			expect(normal.beat).toBe(2)
			expect(normal.valuePerBeat).toBe(4)
			expect(HitSchedule.income(normal)).toBeNear(2)
			expect(fast.hitsPerBeat).toBe(3)
			expect(fast.beat).toBeNear(1.2)
			expect(fast.valuePerBeat).toBe(3)
			expect(HitSchedule.income(fast)).toBeNear(2.5)
		end)

		it("sizes the chest in minutes of income", function()
			expect(preset("Normal").capBeats).toBe(150) -- 5 minutes of 2-second beats
			expect(preset("Fast").capBeats).toBe(250)
			expect(HitSchedule.storedValue(preset("Normal"), T0 + 10_000)).toBe(600) -- 5 min of $2/s
		end)

		it("counts beat k from exactly its timestamp, even at large server times", function()
			for _, name in { "Normal", "Fast" } do
				local post = preset(name)
				for k = 1, 2000 do
					local t = HitSchedule.beatTime(post, k)
					assert(HitSchedule.beatsAt(post, t) == k, name .. " beat " .. k .. " at its own time")
					assert(
						HitSchedule.beatsAt(post, t - 0.001) == k - 1,
						name .. " beat " .. k .. " just before"
					)
				end
			end
			expect(HitSchedule.beatsAt(preset("Normal"), T0 - 5)).toBe(0)
		end)

		it("credits exactly the beats a frame-by-frame viewer sees, through hitches", function()
			local post = preset("Normal")
			local rng = sb.requirePath("ReplicatedStorage/Shared/Util/Prng").new(9)
			local t, last, seen = T0, 0, 0
			while t < T0 + 250 do
				-- 60 fps with the odd long stall
				t += if rng:NextNumber() < 0.02 then rng:NextNumber(0.5, 6) else 1 / 60
				local k = HitSchedule.beatsAt(post, t)
				for b = last + 1, k do
					if HitSchedule.isCredited(post, b) then
						seen += 1
					end
				end
				last = k
			end
			local beats, cash = HitSchedule.collect(post, t)
			expect(beats).toBe(seen)
			expect(cash).toBe(seen * post.valuePerBeat)
		end)

		it("stops crediting when the chest is full and resumes after collecting", function()
			local post = preset("Normal")
			local full = HitSchedule.fullAt(post)
			expect(full).toBeNear(T0 + 300, 1e-6)
			expect(HitSchedule.isFull(post, full - 0.01)).toBeFalsy()
			expect(HitSchedule.isFull(post, full)).toBeTruthy()
			expect(HitSchedule.isCredited(post, 150)).toBeTruthy()
			expect(HitSchedule.isCredited(post, 151)).toBeFalsy()
			local t = T0 + 900
			expect(HitSchedule.stored(post, t)).toBe(150)
			local beats, cash = HitSchedule.collect(post, t)
			expect(beats).toBe(150)
			expect(cash).toBe(600)
			-- Beats that fell while full are gone, not owed.
			expect(HitSchedule.stored(post, t)).toBe(0)
			expect(HitSchedule.isCredited(post, HitSchedule.beatsAt(post, t) + 1)).toBeTruthy()
			expect(HitSchedule.stored(post, t + 2)).toBe(1)
		end)

		it("never pays a beat twice", function()
			local post = preset("Normal")
			local _, first = HitSchedule.collect(post, T0 + 21)
			local _, again = HitSchedule.collect(post, T0 + 21.5)
			local _, later = HitSchedule.collect(post, T0 + 23)
			expect(first).toBe(40)
			expect(again).toBe(0)
			expect(later).toBe(4)
			-- An earlier timestamp (clock skew) can't rewind fromBeat.
			local _, skew = HitSchedule.collect(post, T0 + 5)
			expect(skew).toBe(0)
			expect(post.fromBeat).toBe(11)
		end)

		it("offline vault pays income for the absence, capped by the vault", function()
			expect(HitSchedule.offlinePayout(2, 3600, Config.OfflineVaultSeconds)).toBe(7200)
			expect(HitSchedule.offlinePayout(2, 10 * 3600, Config.OfflineVaultSeconds)).toBe(14400)
			expect(HitSchedule.offlinePayout(2, 10 * 3600, Config.OfflineVaultMaxSeconds)).toBe(57600)
			expect(HitSchedule.offlinePayout(2, 0, Config.OfflineVaultSeconds)).toBe(0)
			expect(HitSchedule.offlinePayout(0, 3600, Config.OfflineVaultSeconds)).toBe(0)
		end)

		it("round-trips through instance attributes and rejects incomplete ones", function()
			local post = preset("Fast")
			post.fromBeat = 7
			local folder = Instance.new("Folder")
			HitSchedule.write(post, folder)
			local back = HitSchedule.read(folder)
			for key, value in post do
				expect(back[key]).toBe(value)
			end
			folder:SetAttribute("Beat", 0)
			expect(HitSchedule.read(folder)).toBe(nil)
			expect(HitSchedule.read(Instance.new("Folder"))).toBe(nil)
		end)
	end)

	describe("Spark Palm", function()
		local tech = Techniques.SparkPalm
		local look = Sorcerers.get(Config.SorcererId).look
		local model = Rig.build(nil, CFrame.new(), look, Rig.PostScale)
		local joints = Rig.joints(model)
		local function at(u)
			local raw = if u == nil
				then Techniques.Stance
				elseif u == "rest" then Techniques.Rest
				else Techniques.sample(tech, u)
			Rig.apply(joints, Techniques.resolve(raw, Rig.PostScale))
			return Rig.solve(model)
		end

		it("builds every R15 joint", function()
			local names = {}
			for _, def in Rig.Joints do
				assert(joints[def.name], "missing joint " .. def.name)
				names[def.name] = true
			end
			for _, n in
				{
					"Root",
					"Waist",
					"Neck",
					"RightShoulder",
					"LeftElbow",
					"RightWrist",
					"LeftHip",
					"RightKnee",
					"LeftAnkle",
				}
			do
				assert(names[n], n)
			end
			expect(model.PrimaryPart.Name).toBe("HumanoidRootPart")
		end)

		it("fits one strike inside the shortest beat", function()
			expect(tech.anticipation + tech.recovery <= Config.MinBeatSeconds).toBeTruthy()
			expect(tech.keys[1].t).toBe(-tech.anticipation)
			expect(tech.keys[#tech.keys].t).toBe(tech.recovery)
		end)

		it("starts and ends in the stance, without a jump", function()
			for _, u in { -tech.anticipation, tech.recovery } do
				local a = Techniques.sample(tech, u - 0.001)
				local b = Techniques.sample(tech, u + 0.001)
				for name, v in a.joints do
					for i = 1, 3 do
						expect(v[i]).toBeNear(b.joints[name][i], 0.5)
					end
				end
			end
		end)

		it("reaches furthest exactly at contact, into the dummy's target", function()
			local forward = function(u)
				return -at(u).RightHand.Position.Z
			end
			local reach = forward(0)
			for _, u in { -0.4, -0.3, -0.2, -0.1, -0.05, -0.02, 0.15, 0.3, 0.5 } do
				assert(forward(u) < reach, string.format("hand further at %.2f than at contact", u))
			end
			-- In the courtyard, the palm meets the dummy's hit point at contact.
			local yard = game:GetService("Workspace"):FindFirstChild("TrainingCourtyard")
			if yard then
				local Courtyard = sb.requirePath("ServerScriptService/Prototype/Courtyard")
				local body = yard.Dummy.Body
				local hitWorld = (body.CFrame * body.HitPoint.CFrame).Position
				local palmLocal = at(0).RightHand.Position
				local palmWorld = Courtyard.SorcererCFrame * palmLocal
				expect((palmWorld - hitWorld).Magnitude).toBeLessThan(0.7)
			end
		end)

		it("keeps both feet on the ground through the whole strike", function()
			local rest = at(nil)
			local floorY = rest.LeftFoot.Position.Y
			local u = -tech.anticipation
			while u <= tech.recovery do
				local cf = at(u)
				for _, foot in { "LeftFoot", "RightFoot" } do
					local p = cf[foot]
					assert(
						math.abs(p.Position.Y - floorY) < 0.03,
						string.format("%s off the floor at %.2f", foot, u)
					)
					-- Sole stays level
					assert(p.UpVector.Y > 0.995, string.format("%s tilted at %.2f", foot, u))
				end
				u += 0.02
			end
			local resting = at("rest")
			expect(math.abs(resting.RightFoot.Position.Y - floorY)).toBeLessThan(0.03)
		end)

		it("plants the back foot while the body lunges", function()
			local before, during = at(-0.3).RightFoot.Position, at(0).RightFoot.Position
			expect((before - during).Magnitude).toBeLessThan(0.03)
			expect(at(0).LowerTorso.Position.Z).toBeLessThan(at(-0.3).LowerTorso.Position.Z - 0.5)
		end)

		it("blends into the resting pose", function()
			local half = Techniques.blend(Techniques.Stance, Techniques.Rest, 0.5)
			expect(half.joints.Neck[1]).toBeNear(
				(Techniques.Stance.joints.Neck[1] + Techniques.Rest.joints.Neck[1]) / 2
			)
			local _ = Vector3
		end)
	end)
end
