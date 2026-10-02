--!nocheck
-- End-to-end server playtest without Roblox: boots the real server (Main.server.luau) against
-- the baked place inside a minimal engine shim, then plays the whole JJK Farm loop through
-- the remotes exactly as a client would:
--   starter Crate -> Place -> Opening Time -> Open -> Place Sorcerer -> Cursed Orbs fill the
--   Orb Box -> Collect -> carry -> Sell -> Buy a Crate -> Upgrade
-- plus validation, rate limits, a second player, persistence, offline progress (claimed once),
-- failed loads and shutdown.
-- Usage: lune run tools/lune/integration.luau dist/JJKFarm.rbxl
local process = require("@lune/process")
local task = require("@lune/task")
local roblox = require("@lune/roblox")
local Sandbox = require("./lib/Sandbox")
local EngineShim = require("./lib/EngineShim")

local V3, CF = roblox.Vector3.new, Sandbox.CFrame
local game = Sandbox.loadPlace(process.args[1] or "dist/JJKFarm.rbxl")

local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FAIL " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- Shared "cloud" DataStore that survives across simulated sessions.
local helper = Sandbox.new(game)
local MockDataStore = helper.requirePath("ServerScriptService/Server/Services/Data/MockDataStore")
local cloud = MockDataStore.new()

local state = EngineShim.install(game, { dataStore = cloud })
-- Lune can't read BasePart.Position (a derived, non-serialised property), so server modules
-- read part positions through CFrame here. This only affects the in-memory test copy.
local function positionViaCFrame(source, name)
	if not string.find(name, "ServerScriptService") then
		return source
	end
	source = string.gsub(source, "([%w_]*[Rr]oot)%.Position", "%1.CFrame.Position")
	return source
end
local sb = Sandbox.new(game, { Random = EngineShim.Random() }, positionViaCFrame)
local Layout = sb.requirePath("ReplicatedStorage/Shared/Config/FarmLayout")
local GameConfig = sb.requirePath("ReplicatedStorage/Shared/Config/GameConfig")
local Tutorial = sb.requirePath("ReplicatedStorage/Shared/Rules/Tutorial")

print("Booting server...")
local ok, err = pcall(sb.run, game:GetService("ServerScriptService").Server.Main)
check("server boots without errors", ok, err)
if not ok then
	process.exit(1)
end
local workspace = game:GetService("Workspace")
check("baked map present", workspace:FindFirstChild("JJKFarmMap") ~= nil)
check("remotes created", game:GetService("ReplicatedStorage"):FindFirstChild("Remotes") ~= nil)
local DataService = sb.requirePath("ServerScriptService/Server/Services/DataService")

local function settle(seconds)
	-- Let spawned threads run, then pump Heartbeat so throttled State snapshots flush.
	task.wait(seconds or 0.1)
	EngineShim.heartbeat(game, 0.2, 1)
	task.wait(0.05)
end
local function rootPos(player)
	return player.Character.PrimaryPart.CFrame.Position
end
local function teleport(player, position)
	player.Character:PivotTo(CF.new(position + V3(0, 3, 0)))
end
local function farmPoint(index, localPos)
	return (Layout.farmFloor(index) * CF.new(localPos)).Position
end
local function lastProfile(player)
	local args = EngineShim.lastSent("State", player.Name)
	return args and args[1]
end
local function request(player, action, payload)
	local result = EngineShim.invoke(player, action, payload)
	return result or {}
end
local function grant(player, cash)
	-- Test hook: give Cash directly in the server's session (not reachable from clients).
	DataService.getSession(player).profile.cash += cash
end

local function scenario()
	local map = workspace.JJKFarmMap
	local farm1 = map.Farms.Farm1

	print("Player joins")
	local alice = EngineShim.addPlayer(game, "Alice", 1001)
	EngineShim.spawnCharacter(game, alice, Layout.SpawnPosition + V3(0, 3, 0))
	settle(0.3)
	local profile = lastProfile(alice)
	check("profile replicated to client", profile ~= nil)
	check("assigned Farm 1", profile and profile.farm == 1, profile and profile.farm)
	check(
		"starts with one unplaced Starter Crate",
		profile
			and profile.crates["1"]
			and profile.crates["1"].tier == "starter"
			and profile.crates["1"].pad == nil
	)
	check(
		"starts with no Sorcerers and no Cash",
		profile and next(profile.units) == nil and profile.cash == 0
	)
	check("farm shows its owner", farm1:GetAttribute("OwnerId") == 1001)
	check(
		"sign reads Alice's Farm",
		farm1.Sign.SignGui.Title.Text == "Alice's Farm",
		farm1.Sign.SignGui.Title.Text
	)
	check(
		"spawned at Your Farm",
		(rootPos(alice) - Layout.homeCFrame(1).Position).Magnitude < 1,
		(rootPos(alice) - Layout.homeCFrame(1).Position).Magnitude
	)
	check(
		"slot 3 open, slot 4 locked",
		farm1.Slots.Slot3:GetAttribute("Locked") == false and farm1.Slots.Slot4:GetAttribute("Locked") == true
	)
	check(
		"pad 2 open, pad 3 locked",
		farm1.Pads.Pad2:GetAttribute("Locked") == false and farm1.Pads.Pad3:GetAttribute("Locked") == true
	)
	check(
		"leaderstats show Cash",
		alice:FindFirstChild("leaderstats") and alice.leaderstats.Cash.Value == "$0"
	)

	print("Step 1: place the Starter Crate")
	teleport(alice, Layout.SellStand)
	local away = request(alice, "PlaceCrate", { cid = "1", pad = 1 })
	check(
		"placing from the plaza is refused",
		away.ok == false and away.message == "Go to Your Farm first.",
		away.message
	)
	teleport(alice, farmPoint(1, V3(-30, 0, -40)))
	check("locked pad refused", request(alice, "PlaceCrate", { cid = "1", pad = 3 }).ok == false)
	check("bad pad refused", request(alice, "PlaceCrate", { cid = "1", pad = "1" }).ok == false)
	local placed = request(alice, "PlaceCrate", { cid = "1", pad = 1 })
	check("Starter Crate placed on pad 1", placed.ok, placed.message)
	check(
		"Opening Time is 10 s",
		placed.ok and placed.data.readyAt - state.now == 10,
		placed.data and placed.data.readyAt - state.now
	)
	settle(0.2)
	local crateModel = farm1.Runtime.Crates:FindFirstChild("Crate1")
	-- (Lune stores attribute numbers as 32-bit floats; Roblox uses doubles.)
	check(
		"crate model on the pad with its finish time",
		crateModel ~= nil and math.abs(crateModel:GetAttribute("ReadyAt") - (state.now + 10)) <= 128
	)
	check("tutorial at step 2", lastProfile(alice).tutorial == 2, lastProfile(alice).tutorial)

	print("Step 2: open it")
	local early = request(alice, "OpenCrate", { pad = 1 })
	check(
		"can't open before the Opening Time is over",
		early.ok == false and early.message == "This Crate is still opening.",
		early.message
	)
	state.now += 10
	local opened = request(alice, "OpenCrate", { pad = 1 })
	check("crate opens", opened.ok, opened.message)
	check(
		"starter gives Kai (Common)",
		opened.ok and opened.data.id == "kai" and opened.data.rarity == "Common"
	)
	check("reveal broadcast to everyone", EngineShim.lastSent("Effect", "*", function(a)
		return a[1] == "CrateOpened" and a[2].farm == 1 and a[2].pad == 1
	end) ~= nil)
	settle(0.2)
	check("crate model removed", farm1.Runtime.Crates:FindFirstChild("Crate1") == nil)
	local kai = opened.data.uid
	check("tutorial at step 3", lastProfile(alice).tutorial == 3)

	print("Step 3: place the Sorcerer")
	check("locked slot refused", request(alice, "PlaceSorcerer", { uid = kai, slot = 4 }).ok == false)
	check("fractional slot refused", request(alice, "PlaceSorcerer", { uid = kai, slot = 1.5 }).ok == false)
	local put = request(alice, "PlaceSorcerer", { uid = kai, slot = 1 })
	check("Kai placed on slot 1", put.ok, put.message)
	settle(0.2)
	local kaiModel = farm1.Runtime.Sorcerers:FindFirstChild("Sorcerer1")
	check("Sorcerer model stands on slot 1", kaiModel ~= nil and kaiModel:GetAttribute("SorcererId") == "kai")
	check(
		"model is avatar-plus sized",
		kaiModel and kaiModel:GetAttribute("Height") > 6,
		kaiModel and kaiModel:GetAttribute("Height")
	)
	check("farm reports 1 Orb per Second", farm1:GetAttribute("Ops") == 1, farm1:GetAttribute("Ops"))
	check("tutorial at step 4", lastProfile(alice).tutorial == 4)

	print("Step 4: Cursed Orbs fill the Orb Box; Collect")
	state.now += 20
	teleport(alice, Layout.SellStand)
	local far = request(alice, "Collect")
	check("collect refused away from the Orb Box", far.ok == false, far.message)
	teleport(alice, farmPoint(1, Layout.CollectPoint))
	local collected = request(alice, "Collect")
	check(
		"collect 20 Cursed Orbs",
		collected.ok and collected.data.orbs == 20,
		collected.data and collected.data.orbs
	)
	settle(0.2)
	profile = lastProfile(alice)
	check(
		"carrying 20 orbs worth $40",
		profile.carried.orbs == 20 and math.abs(profile.carried.value - 40) < 1e-6
	)
	check("carried Orb Box visible on the character", alice.Character:FindFirstChild("CarriedOrbBox") ~= nil)
	check("Orb Box emptied", profile.box.orbs < 1)
	check("tutorial at step 5", profile.tutorial == 5)

	print("Step 5: Sell at the Sell Stand")
	local farSell = request(alice, "Sell")
	check("sell refused away from the Sell Stand", farSell.ok == false, farSell.message)
	teleport(alice, Layout.SellStand)
	local sold = request(alice, "Sell")
	check("sold for $40", sold.ok and sold.data.cash == 40, sold.data and sold.data.cash)
	settle(0.2)
	profile = lastProfile(alice)
	check("Cash = 40 + $50 tutorial reward", profile.cash == 90, profile.cash)
	check("carried box gone", alice.Character:FindFirstChild("CarriedOrbBox") == nil)
	check("leaderstats updated", alice.leaderstats.Cash.Value == "$90", alice.leaderstats.Cash.Value)
	check("tutorial at step 6", profile.tutorial == 6)

	print("Touch pads collect and sell too")
	state.now += 15
	local collectPad = farm1.CollectPad
	teleport(alice, farmPoint(1, Layout.CollectPoint))
	collectPad.Touched:FireSync(alice.Character.PrimaryPart)
	settle(0.1)
	check(
		"stepping on the Collect Pad collects",
		lastProfile(alice).carried.orbs == 15,
		lastProfile(alice).carried.orbs
	)
	task.wait(1.1) -- touch cooldown
	local sellPad = map.Plaza.SellStand.SellPad
	teleport(alice, Layout.SellStand)
	sellPad.Touched:FireSync(alice.Character.PrimaryPart)
	settle(0.1)
	check(
		"stepping on the Sell Stand sells",
		lastProfile(alice).cash == 120 and lastProfile(alice).carried.orbs == 0,
		lastProfile(alice).cash
	)

	print("Step 6: Buy a crate")
	local farBuy = request(alice, "BuyCrate", { tier = "basic" })
	check("buying away from the Crate Shop refused", farBuy.ok == false, farBuy.message)
	teleport(alice, Layout.CrateShop + V3(0, 0, 12))
	check("starter crate isn't for sale", request(alice, "BuyCrate", { tier = "starter" }).ok == false)
	check("unknown crate refused", request(alice, "BuyCrate", { tier = {} }).ok == false)
	check("can't afford a Rare Crate", request(alice, "BuyCrate", { tier = "rare" }).ok == false)
	local bought = request(alice, "BuyCrate", { tier = "basic" })
	check("Basic Crate bought", bought.ok, bought.message)
	settle(0.2)
	profile = lastProfile(alice)
	check("charged $60 (+$25 tutorial reward)", profile.cash == 120 - 60 + 25, profile.cash)
	local basicCid = bought.data and bought.data.cid
	check("crate in inventory", basicCid and profile.crates[basicCid] and profile.crates[basicCid].pad == nil)

	print("Step 7: Upgrade")
	local farUp = request(alice, "BuyUpgrade", { id = "orbValue" })
	check("upgrading away from the Upgrade Shop refused", farUp.ok == false, farUp.message)
	teleport(alice, Layout.UpgradeShop - V3(0, 0, 12))
	local up = request(alice, "BuyUpgrade", { id = "orbValue" })
	check("Orb Value upgraded", up.ok and up.data.level == 1, up.message)
	settle(0.2)
	profile = lastProfile(alice)
	check(
		"tutorial complete with reward",
		profile.tutorial == Tutorial.Done and profile.cash == 85 - 25 + 50,
		profile.cash
	)
	local kaiModelNow = farm1.Runtime.Sorcerers:FindFirstChild("Sorcerer1")
	check(
		"Orb Value shown on the Sorcerer",
		kaiModelNow and math.abs(kaiModelNow:GetAttribute("OrbValue") - 2.2) < 1e-6
	)

	print("Reinvest: more slots, pads, a second sorcerer")
	grant(alice, 10000)
	check("buy More Slots", request(alice, "BuyUpgrade", { id = "slots" }).ok)
	check("buy More Crate Pads", request(alice, "BuyUpgrade", { id = "pads" }).ok)
	check("buy Walk Speed", request(alice, "BuyUpgrade", { id = "walkSpeed" }).ok)
	check(
		"walk speed applied",
		alice.Character.Humanoid.WalkSpeed == GameConfig.BaseWalkSpeed + GameConfig.WalkSpeedPerLevel
	)
	check("unknown upgrade refused", request(alice, "BuyUpgrade", { id = "teleport" }).ok == false)
	settle(0.2)
	check("slot 4 unlocked", farm1.Slots.Slot4:GetAttribute("Locked") == false)
	check("pad 3 unlocked", farm1.Pads.Pad3:GetAttribute("Locked") == false)
	teleport(alice, farmPoint(1, V3(-30, 0, -20)))
	local p2 = request(alice, "PlaceCrate", { cid = basicCid, pad = 3 })
	check("Basic Crate placed on pad 3", p2.ok, p2.message)
	state.now += 5
	local pick = request(alice, "PickUpCrate", { pad = 3 })
	check("Pick Up a crate", pick.ok, pick.message)
	check(
		"pick up keeps the remaining Opening Time",
		DataService.getSession(alice).profile.crates[basicCid].remaining == 25
	)
	request(alice, "PlaceCrate", { cid = basicCid, pad = 2 })
	state.now += 25
	local second = request(alice, "OpenCrate", { pad = 2 })
	check("Basic Crate opens after 30 s total", second.ok, second.message)
	local secondUid = second.data and second.data.uid
	local put2 = request(alice, "PlaceSorcerer", { uid = secondUid, slot = 1 })
	check("placing on an occupied slot swaps", put2.ok and put2.data.replaced == kai, put2.message)
	check("move Kai to slot 2", request(alice, "PlaceSorcerer", { uid = kai, slot = 2 }).ok)
	settle(0.2)
	check(
		"two Sorcerers working",
		farm1.Runtime.Sorcerers:FindFirstChild("Sorcerer1")
			and farm1.Runtime.Sorcerers:FindFirstChild("Sorcerer2")
	)
	local lvl = request(alice, "UpgradeSorcerer", { uid = kai })
	check("Upgrade Kai to level 2", lvl.ok and lvl.data.level == 2, lvl.message)
	settle(0.2)
	check("model shows level 2", farm1.Runtime.Sorcerers.Sorcerer2:GetAttribute("Level") == 2)
	local pickS = request(alice, "PickUpSorcerer", { slot = 2 })
	check("Pick Up a Sorcerer", pickS.ok, pickS.message)
	settle(0.2)
	check("slot 2 cleared", farm1.Runtime.Sorcerers:FindFirstChild("Sorcerer2") == nil)
	check("Kai back on slot 2", request(alice, "PlaceSorcerer", { uid = kai, slot = 2 }).ok)

	print("Validation and rate limiting")
	check("unknown action rejected", request(alice, "Explode").ok == false)
	check("non-table payload rejected", request(alice, "PlaceSorcerer", "slot2").ok == false)
	check("bad uid rejected", request(alice, "PlaceSorcerer", { uid = "../1", slot = 1 }).ok == false)
	check("huge slot rejected", request(alice, "PlaceSorcerer", { uid = kai, slot = 999 }).ok == false)
	check("NaN pad rejected", request(alice, "OpenCrate", { pad = 0 / 0 }).ok == false)
	local throttled = 0
	for _ = 1, 40 do
		local r = request(alice, "GetState")
		if not r.ok and r.message == "Slow down a little!" then
			throttled += 1
		end
	end
	check("request spam is throttled", throttled > 10, throttled)
	task.wait(2.2)

	print("Second player gets their own farm")
	local bob = EngineShim.addPlayer(game, "Bob", 2002)
	EngineShim.spawnCharacter(game, bob, Layout.SpawnPosition + V3(4, 3, 0))
	settle(0.3)
	local bobProfile = lastProfile(bob)
	check("Bob assigned Farm 2", bobProfile and bobProfile.farm == 2, bobProfile and bobProfile.farm)
	check(
		"Bob can't place Alice's Sorcerer",
		request(bob, "PlaceSorcerer", { uid = kai, slot = 1 }).ok == false
	)
	teleport(bob, farmPoint(1, Layout.CollectPoint))
	check("Bob can't collect Alice's Orb Box", request(bob, "Collect").ok == false)
	collectPad.Touched:FireSync(bob.Character.PrimaryPart)
	check("Alice's Collect Pad ignores Bob", lastProfile(bob).carried.orbs == 0)
	check(
		"Bob can't place on Alice's farm",
		request(bob, "PlaceCrate", { cid = "1", pad = 1 }).message == "Go to Your Farm first."
	)

	print("Respawn returns home")
	EngineShim.spawnCharacter(game, alice, Layout.SpawnPosition + V3(0, 3, 0))
	settle(0.2)
	check(
		"respawn moves character to Your Farm",
		(rootPos(alice) - Layout.homeCFrame(1).Position).Magnitude < 1
	)

	print("Leaving saves and releases the farm")
	state.now += 30
	local cashBefore = DataService.getSession(alice).profile.cash
	-- Leave a crate opening on a pad so its timestamp has to survive the trip.
	teleport(alice, farmPoint(1, V3(-30, 0, -40)))
	grant(alice, 60)
	teleport(alice, Layout.CrateShop + V3(0, 0, 12))
	local third = request(alice, "BuyCrate", { tier = "basic" })
	teleport(alice, farmPoint(1, V3(-30, 0, -40)))
	request(alice, "PlaceCrate", { cid = third.data.cid, pad = 1 })
	local readyAt = DataService.getSession(alice).profile.crates[third.data.cid].readyAt
	EngineShim.removePlayer(game, alice)
	settle(0.3)
	local record = cloud.data["u_1001"]
	check(
		"profile saved to DataStore",
		record and record.data and record.data.cash == cashBefore,
		record and record.data and record.data.cash
	)
	check("session lock released", record and record.lock == nil)
	check("placements saved", record.data.slots["1"] == secondUid and record.data.slots["2"] == kai)
	check(
		"crate on pad saved with its finish time",
		record.data.crates[third.data.cid].pad == 1 and record.data.crates[third.data.cid].readyAt == readyAt
	)
	check("Orb Box settled at save time", record.data.box.t == state.now, record.data.box.t)
	check(
		"farm released",
		farm1:GetAttribute("OwnerId") == nil and farm1.Sign.SignGui.Title.Text == "Empty Farm"
	)
	check("sorcerers cleared from the released farm", #farm1.Runtime.Sorcerers:GetChildren() == 0)
	check("crates cleared from the released farm", #farm1.Runtime.Crates:GetChildren() == 0)

	print("Offline progress: once per absence")
	local savedOrbs = record.data.box.orbs
	state.now += 3600
	local alice2 = EngineShim.addPlayer(game, "Alice", 1001)
	EngineShim.spawnCharacter(game, alice2, Layout.SpawnPosition + V3(0, 3, 0))
	settle(0.3)
	local restored = lastProfile(alice2)
	check("sorcerers restored", restored and restored.units[kai] ~= nil and restored.units[kai].level == 2)
	check("upgrades restored", restored and restored.upgrades.orbValue == 1 and restored.upgrades.slots == 1)
	check("placements restored", restored and restored.slots["2"] == kai)
	local cap = 60
	check(
		"Orb Box filled while away (up to capacity)",
		restored and restored.box.orbs == cap,
		restored and restored.box.orbs
	)
	local offline = EngineShim.lastSent("Notify", "Alice", function(a)
		return a[1] == "Offline"
	end)
	check("offline notice sent", offline ~= nil and offline[2].cratesReady == 1, offline and offline[2].text)
	check(
		"offline orbs reported",
		offline and offline[2].orbs == cap - math.floor(savedOrbs) or offline and offline[2].orbs > 0,
		offline and offline[2].orbs
	)
	check(
		"crate that finished offline can be opened",
		(function()
			teleport(alice2, farmPoint(1, V3(-30, 0, -40)))
			return request(alice2, "OpenCrate", { pad = 1 }).ok
		end)()
	)
	-- Duplicate-claim protection: leave and rejoin immediately. The box timestamp was moved
	-- to the load time and saved, so the same hour is not paid out again.
	teleport(alice2, farmPoint(1, Layout.CollectPoint))
	local c1 = request(alice2, "Collect")
	check("collect the offline orbs", c1.ok and c1.data.orbs == cap, c1.data and c1.data.orbs)
	state.outbox = {}
	EngineShim.state.outbox = state.outbox
	EngineShim.removePlayer(game, alice2)
	settle(0.3)
	local alice3 = EngineShim.addPlayer(game, "Alice", 1001)
	EngineShim.spawnCharacter(game, alice3, Layout.SpawnPosition + V3(0, 3, 0))
	settle(0.3)
	local again = lastProfile(alice3)
	check("no second payout for the same absence", again and again.box.orbs < 1, again and again.box.orbs)
	check("no offline notice on an instant rejoin", EngineShim.lastSent("Notify", "Alice", function(a)
		return a[1] == "Offline"
	end) == nil)
	check("carried orbs survive a rejoin", again and again.carried.orbs == cap, again and again.carried.orbs)

	print("Failed load protects existing data")
	cloud.data["u_3003"] = { data = { cash = 999999, units = { ["1"] = { id = "yoru", level = 30 } } } }
	cloud.failNext = 1000
	EngineShim.addPlayer(game, "Carol", 3003)
	task.wait(24) -- retries with backoff (~21s)
	cloud.failNext = 0
	local kicked = false
	for _, k in state.kicked do
		if k.player == "Carol" then
			kicked = true
		end
	end
	check("player kicked after repeated load failures", kicked)
	check(
		"stored data untouched",
		cloud.data["u_3003"].data.cash == 999999 and cloud.data["u_3003"].lock == nil
	)

	print("Shutdown saves everyone")
	for _, fn in state.bindToClose do
		fn()
	end
	check(
		"Bob saved on shutdown",
		cloud.data["u_2002"] and cloud.data["u_2002"].data ~= nil and cloud.data["u_2002"].lock == nil
	)
	check(
		"Alice saved on shutdown",
		cloud.data["u_1001"].lock == nil and cloud.data["u_1001"].data.carried.orbs == cap
	)
end

local okScenario, scenarioError = xpcall(scenario, function(e)
	return tostring(e) .. "\n" .. tostring(debug.traceback())
end)
if not okScenario then
	failed += 1
	print("  FAIL scenario crashed: " .. tostring(scenarioError))
end
print(string.format("\nIntegration: %d passed, %d failed", passed, failed))
process.exit(if failed == 0 then 0 else 1)
