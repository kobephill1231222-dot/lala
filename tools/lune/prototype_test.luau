--!nocheck
-- Tests for the training-post prototype (dist/Prototype.rbxl):
--   1. unit tests (tests/prototype.spec.luau): hit schedule, chest, offline vault, technique, rig
--   2. server: the real Prototype Main script in the engine shim. Ownership, collecting at the
--      chest (prompt and pad, range-checked), the full chest, the review switches, handover
--   3. client: the real client scripts with a stubbed engine. Strikes land on the schedule's
--      timestamps, every credited beat is shown (through frame hitches), the chest display,
--      resting when full, combos, and recovery surviving a collect
-- Usage: lune run tools/lune/prototype_test.luau dist/Prototype.rbxl
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Sandbox = require("./lib/Sandbox")
local EngineShim = require("./lib/EngineShim")
local TestKit = require("./lib/TestKit")

local placePath = process.args[1] or "dist/Prototype.rbxl"
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

-- 1. Unit tests ------------------------------------------------------------------------------
do
	local game = Sandbox.loadPlace(placePath)
	require("../../tests/prototype.spec")({ sandbox = Sandbox.new(game), kit = TestKit, game = game })
end

-- Shared engine stubs ---------------------------------------------------------------------
local Signal = EngineShim.Signal
local nextSig = 0
local signals = {}
local function instanceSignal(inst, key)
	local id = inst:GetAttribute("__protoSig")
	if not id then
		nextSig += 1
		id = nextSig
		inst:SetAttribute("__protoSig", id)
	end
	signals[id] = signals[id] or {}
	signals[id][key] = signals[id][key] or Signal.new(key)
	return signals[id][key]
end
for _, pair in { { "ProximityPrompt", "Triggered" }, { "RemoteEvent", "OnClientEvent" } } do
	roblox.implementProperty(pair[1], pair[2], function(inst)
		return instanceSignal(inst, pair[2])
	end)
end
roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(inst, attr)
	return instanceSignal(inst, "attr_" .. attr)
end)
roblox.implementMethod("Debris", "AddItem", function() end)
local soundsPlayed = {}
roblox.implementMethod("Sound", "Play", function(sound)
	table.insert(soundsPlayed, { name = sound.Name, parent = sound.Parent and sound.Parent.Name })
end)
local emitted = 0
roblox.implementMethod("ParticleEmitter", "Emit", function(_, n)
	emitted += n or 1
end)

-- 2. Server -------------------------------------------------------------------------------
-- The shim patches engine classes globally, so it's installed once and its clock is shared.
local shim
do
	local game = Sandbox.loadPlace(placePath)
	-- Fractional, like real server time (Lune stores whole-number attributes as 32-bit floats).
	local T0 = 1_700_000_000.125
	shim = EngineShim.install(game, { startTime = T0 })
	local sb = Sandbox.new(game, { Random = EngineShim.Random() })
	local HitSchedule = sb.requirePath("ReplicatedStorage/Prototype/HitSchedule")
	local Courtyard = sb.requirePath("ServerScriptService/Prototype/Courtyard")
	local workspace = game:GetService("Workspace")
	local yard = workspace.TrainingCourtyard
	local post = yard.Post
	local chestBody = yard.Chest.Body
	local pad = yard.CollectPad
	local board = yard.ReviewBoard.Board

	local function at(t)
		shim.now = T0 + t
	end
	local function trigger(prompt, player)
		prompt.Triggered:FireSync(player)
	end
	local function lastNotify(target, kind)
		return EngineShim.lastSent("PrototypeNotify", target, function(args)
			return args[1] == kind
		end)
	end
	local function outboxSize()
		return #shim.outbox
	end
	local function moveTo(player, cf)
		player.Character.HumanoidRootPart.CFrame = cf
	end
	local nearChest = Courtyard.ChestCFrame * roblox.CFrame.new(0, 3, -4)

	describe("Prototype server", function()
		it("boots against the baked place without errors", function()
			sb.run(game:GetService("ServerScriptService").Prototype.Main)
			expect(game:GetService("ReplicatedStorage"):FindFirstChild("PrototypeNotify") ~= nil).toBeTruthy()
		end)

		local alice
		it("gives the post to the first player and starts the Sorcerer working", function()
			at(0)
			alice = EngineShim.addPlayer(game, "Alice", 101)
			EngineShim.spawnCharacter(
				game,
				alice,
				Courtyard.SpawnCFrame.Position + roblox.Vector3.new(0, 3, 0)
			)
			task.wait(0.01)
			expect(post:GetAttribute("OwnerId")).toBe(101)
			expect(post:GetAttribute("PlacedAt")).toBe(T0)
			expect(post:GetAttribute("Beat")).toBe(2)
			expect(post:GetAttribute("CapBeats")).toBe(150)
			expect(alice:GetAttribute("Cash")).toBe(0)
		end)

		it("refuses to collect from out of range", function()
			at(21)
			trigger(chestBody.Prompt, alice)
			local msg = lastNotify("Alice", "Error")
			expect(msg ~= nil and string.find(msg[2].message, "Walk up") ~= nil).toBeTruthy()
			expect(alice:GetAttribute("Cash")).toBe(0)
		end)

		it("pays exactly the credited hits at the chest", function()
			moveTo(alice, nearChest)
			trigger(chestBody.Prompt, alice)
			expect(alice:GetAttribute("Cash")).toBe(40) -- 10 hits x $4
			local msg = lastNotify("*", "Collected")
			expect(msg[2].cash).toBe(40)
			expect(msg[2].hits).toBe(10)
			expect(post:GetAttribute("FromBeat")).toBe(10)
		end)

		it("tells you when the chest is empty and pays nothing twice", function()
			at(21.6)
			trigger(chestBody.Prompt, alice)
			expect(lastNotify("Alice", "Empty") ~= nil).toBeTruthy()
			expect(alice:GetAttribute("Cash")).toBe(40)
		end)

		it("caps the chest at 5 minutes of income", function()
			at(21.6 + 1000)
			trigger(chestBody.Prompt, alice)
			expect(alice:GetAttribute("Cash")).toBe(40 + 600)
			local fresh = HitSchedule.read(post)
			expect(HitSchedule.stored(fresh, T0 + 1021.6)).toBe(0)
		end)

		it("collects from the pad quietly, and only for the owner", function()
			at(1041.6) -- 10 more beats
			local before = outboxSize()
			pad.Touched:FireSync(alice.Character.HumanoidRootPart)
			expect(alice:GetAttribute("Cash")).toBe(680)
			-- A pad touch with nothing stored sends nothing.
			at(1041.9)
			before = outboxSize()
			pad.Touched:FireSync(alice.Character.HumanoidRootPart)
			expect(outboxSize()).toBe(before)
		end)

		local bob
		it("doesn't let other players take the chest", function()
			at(1060)
			bob = EngineShim.addPlayer(game, "Bob", 202)
			EngineShim.spawnCharacter(game, bob, nearChest.Position)
			task.wait(0.01)
			pad.Touched:FireSync(bob.Character.HumanoidRootPart)
			trigger(chestBody.Prompt, bob)
			expect(bob:GetAttribute("Cash")).toBe(0)
			local msg = lastNotify("Bob", "Error")
			expect(string.find(msg[2].message, "isn't your chest") ~= nil).toBeTruthy()
			expect(post:GetAttribute("OwnerId")).toBe(101)
		end)

		it("won't pay a player who is dead", function()
			at(1064)
			alice.Character.Humanoid.Health = 0
			local cash = alice:GetAttribute("Cash")
			trigger(chestBody.Prompt, alice)
			expect(alice:GetAttribute("Cash")).toBe(cash)
			alice.Character.Humanoid.Health = 100
		end)

		it("Fast switch banks the chest and re-places the Sorcerer with combos", function()
			at(1070)
			local cash = alice:GetAttribute("Cash")
			local stored = HitSchedule.storedValue(HitSchedule.read(post), shim.now)
			expect(stored > 0).toBeTruthy()
			trigger(board.FastPromptAnchor.FastPrompt, alice)
			expect(alice:GetAttribute("Cash")).toBe(cash + stored)
			expect(post:GetAttribute("Preset")).toBe("Fast")
			expect(post:GetAttribute("PlacedAt")).toBe(shim.now)
			expect(post:GetAttribute("HitsPerBeat")).toBe(3)
			expect(post:GetAttribute("ValuePerBeat")).toBe(3)
			expect(board.FastPromptAnchor.FastPrompt.ActionText).toBe("Normal Sorcerer")
		end)

		it("Fill switch fills the chest right away", function()
			at(1080)
			trigger(board.FillPromptAnchor.FillPrompt, alice)
			local p = HitSchedule.read(post)
			expect(HitSchedule.isFull(p, shim.now)).toBeTruthy()
			expect(HitSchedule.isCredited(p, HitSchedule.beatsAt(p, shim.now) + 1)).toBeFalsy()
			expect(lastNotify("*", "Filled") ~= nil).toBeTruthy()
		end)

		it("ignores the review switches from anyone but the owner", function()
			at(1090)
			trigger(board.FastPromptAnchor.FastPrompt, bob)
			expect(post:GetAttribute("Preset")).toBe("Fast")
		end)

		it("hands the post to the next player when the owner leaves", function()
			at(1100)
			EngineShim.removePlayer(game, alice)
			expect(post:GetAttribute("OwnerId")).toBe(202)
			expect(post:GetAttribute("PlacedAt")).toBe(shim.now)
			expect(post:GetAttribute("FromBeat")).toBe(0)
		end)
	end)
end

-- 3. Client -------------------------------------------------------------------------------
do
	local game = Sandbox.loadPlace(placePath)
	local T0 = 1_700_000_000.25
	shim.now = T0
	local players = game:GetService("Players")
	local player = roblox.Instance.new("Player")
	player.Name = "Tester"
	player.UserId = 4242
	player.Parent = players
	players.LocalPlayer = player
	local playerGui = roblox.Instance.new("PlayerGui")
	playerGui.Parent = player
	local notify = roblox.Instance.new("RemoteEvent")
	notify.Name = "PrototypeNotify"
	notify.Parent = game:GetService("ReplicatedStorage")

	local sb = Sandbox.new(game, { Random = EngineShim.Random() })
	local HitSchedule = sb.requirePath("ReplicatedStorage/Prototype/HitSchedule")
	local Config = sb.requirePath("ReplicatedStorage/Prototype/PrototypeConfig")
	local yard = game:GetService("Workspace").TrainingCourtyard
	local postModel = yard.Post

	local function place(name, t)
		local p = Config.Presets[name]
		local post = HitSchedule.new(
			t,
			p.hitInterval,
			p.valuePerHit,
			Config.MinBeatSeconds,
			Config.ChestStorageSeconds
		)
		HitSchedule.write(post, postModel)
		postModel:SetAttribute("HitInterval", p.hitInterval)
		postModel:SetAttribute("ValuePerHit", p.valuePerHit)
		return post
	end
	local post = place("Normal", T0)

	local runService = game:GetService("RunService")
	local function frame(dt)
		shim.now += dt
		runService.RenderStepped:FireSync(dt)
	end
	local function runUntil(t, dt)
		while shim.now < t - 1e-9 do
			frame(math.min(dt or 1 / 60, t - shim.now))
		end
	end
	local function req(name)
		return sb.requirePath("StarterPlayer/StarterPlayerScripts/Prototype/" .. name)
	end

	describe("Prototype client", function()
		local TrainingView, ChestView, Hud
		it("boots", function()
			sb.run(game:GetService("StarterPlayer").StarterPlayerScripts.Prototype.Main)
			TrainingView, ChestView, Hud = req("TrainingView"), req("ChestView"), req("Hud")
			frame(1 / 60)
			expect(playerGui:FindFirstChild("PrototypeHud") ~= nil).toBeTruthy()
		end)

		local rig = postModel.Sorcerer
		local shoulder = rig.RightUpperArm.RightShoulder
		local rest = nil
		it("stands in stance before the first wind-up", function()
			runUntil(T0 + 1.2)
			expect(TrainingView.lastU).toBe(nil)
			expect(TrainingView.strikes).toBe(0)
			rest = shoulder.C0
		end)

		it("winds up so that contact lands on the beat's timestamp", function()
			runUntil(T0 + 2 - 0.2)
			expect(TrainingView.lastU).toBeNear(-0.2, 1e-6)
			expect(TrainingView.strikes).toBe(0)
			local moved = (shoulder.C0.Position - rest.Position).Magnitude
				+ (shoulder.C0.LookVector - rest.LookVector).Magnitude
			expect(moved > 0.1).toBeTruthy()
			runUntil(T0 + 2 - 1e-4)
			expect(TrainingView.strikes).toBe(0)
			frame(1e-4)
			expect(TrainingView.strikes).toBe(1)
			expect(TrainingView.lastU).toBeNear(0, 1e-3)
		end)

		it("doesn't replay a hit when the server clock steps back slightly", function()
			shim.now -= 0.004
			frame(0)
			shim.now += 0.004
			frame(0)
			expect(TrainingView.strikes).toBe(1)
		end)

		it("pops the payout, flashes the dummy and plays the impact", function()
			local anchor = yard.Dummy.Body.PopupAnchor
			local gui = anchor:FindFirstChild("Payout")
			expect(gui ~= nil).toBeTruthy()
			expect(gui:FindFirstChildOfClass("TextLabel").Text).toBe("+$4")
			expect(emitted > 0).toBeTruthy()
			local impact = false
			for _, s in soundsPlayed do
				impact = impact or s.name == "Fx_impact"
			end
			expect(impact).toBeTruthy()
			local springRest = yard.Dummy.Body.Spring.C0
			frame(0.1)
			expect((yard.Dummy.Body.Spring.C0.LookVector - springRest.LookVector).Magnitude > 0.05).toBeTruthy()
		end)

		it("cleans up its effects", function()
			runUntil(shim.now + 1.5)
			expect(yard.Dummy.Body.PopupAnchor:FindFirstChild("Payout")).toBe(nil)
			local fx = game:GetService("Workspace").PrototypeFx
			expect(#fx:GetChildren()).toBe(1) -- only the reusable impact ring
		end)

		it("shows every credited beat, through frame hitches", function()
			-- 4 minutes at 30 fps with a 0.9 s and a 5 s stall.
			local t1 = T0 + 240
			local stalls = { [T0 + 60] = 0.9, [T0 + 120] = 5 }
			while shim.now < t1 do
				local dt = 1 / 30
				for at, len in stalls do
					if shim.now < at and shim.now + dt >= at then
						dt = len
						stalls[at] = nil
					end
				end
				frame(dt)
			end
			expect(TrainingView.beatsShown).toBe(HitSchedule.beatsAt(post, shim.now))
			expect(TrainingView.strikes < TrainingView.beatsShown).toBeTruthy() -- stalls merged beats
		end)

		it("fills the chest display as coins land", function()
			local landed = HitSchedule.stored(post, shim.now - TrainingView.CoinTime)
			expect(ChestView.stored).toBe(landed)
			local amount = yard.Chest.Body.Label.Amount.Text
			expect(amount).toBe("$" .. landed * 4 .. " / $600")
		end)

		it("rests while the chest is full and stops striking", function()
			runUntil(HitSchedule.fullAt(post) + 3, 1 / 20)
			expect(ChestView.full).toBeTruthy()
			expect(TrainingView.resting).toBeTruthy()
			expect(TrainingView.beatsShown).toBe(150)
			runUntil(shim.now + 20, 1 / 20)
			expect(TrainingView.beatsShown).toBe(150)
			expect(yard.Chest.Body.Label.Title.Text).toBe("FULL · COLLECT!")
			expect(string.find(playerGui.PrototypeHud.Hint.Text, "resting") ~= nil).toBeTruthy()
		end)

		it("resumes after the chest is collected, and toasts the banked Cash", function()
			HitSchedule.collect(post, shim.now)
			HitSchedule.write(post, postModel)
			notify.OnClientEvent:FireSync("Collected", { userId = 4242, cash = 600, hits = 150 })
			expect(Hud.lastToast).toBe("Banked $600")
			local before = TrainingView.beatsShown
			runUntil(shim.now + 2.05, 1 / 30)
			expect(TrainingView.beatsShown).toBe(before + 1)
			expect(TrainingView.resting).toBeFalsy()
		end)

		it("lets a strike finish its recovery when the chest is collected mid-strike", function()
			local nextBeat = HitSchedule.beatsAt(post, shim.now) + 1
			runUntil(HitSchedule.beatTime(post, nextBeat) + 0.1, 1 / 60)
			HitSchedule.collect(post, shim.now)
			HitSchedule.write(post, postModel)
			frame(1 / 60)
			expect(TrainingView.lastU ~= nil and TrainingView.lastU > 0.1).toBeTruthy()
		end)

		it("eases out of a wind-up whose hit is cancelled instead of snapping", function()
			local nextBeat = HitSchedule.beatsAt(post, shim.now) + 1
			runUntil(HitSchedule.beatTime(post, nextBeat) - 0.15, 1 / 60)
			expect(TrainingView.lastU < 0).toBeTruthy()
			local windup = shoulder.C0
			-- The Fill switch: chest full now, so the coming hit won't be paid.
			post.fromBeat = HitSchedule.beatsAt(post, shim.now) - post.capBeats
			HitSchedule.write(post, postModel)
			frame(1 / 60)
			expect(TrainingView.lastU).toBe(nil)
			local justAfter = shoulder.C0
			expect((justAfter.LookVector - windup.LookVector).Magnitude < 0.1).toBeTruthy()
			local shown = TrainingView.beatsShown
			runUntil(shim.now + 1, 1 / 60)
			expect(TrainingView.beatsShown).toBe(shown) -- the cancelled hit never lands
			expect((shoulder.C0.LookVector - windup.LookVector).Magnitude > 0.1).toBeTruthy()
			HitSchedule.collect(post, shim.now)
			HitSchedule.write(post, postModel)
		end)

		it("plays combos on the Fast preset, one strike per beat of three hits", function()
			post = place("Fast", shim.now)
			local before = TrainingView.strikes
			runUntil(shim.now + 1.2 + 1e-3, 1 / 60)
			expect(TrainingView.strikes).toBe(before + 1)
			local gui = yard.Dummy.Body.PopupAnchor:FindFirstChild("Payout")
			expect(gui:FindFirstChildOfClass("TextLabel").Text).toBe("x3  +$3")
			expect(string.find(playerGui.PrototypeHud.Info.Text, "x3 combos") ~= nil).toBeTruthy()
		end)
	end)
end

if not TestKit.report() then
	process.exit(1)
end
