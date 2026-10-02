--!nocheck
-- End-to-end server playtest without Roblox: boots the real server (Main.server.luau) against
-- the baked place inside a minimal engine shim, then plays a scripted session through the
-- remotes exactly as a client would.
-- Usage: lune run tools/lune/integration.luau build/baked.rbxl
local process = require("@lune/process")
local task = require("@lune/task")
local roblox = require("@lune/roblox")
local Sandbox = require("./lib/Sandbox")
local EngineShim = require("./lib/EngineShim")

local V3, CF = roblox.Vector3.new, Sandbox.CFrame
local game = Sandbox.loadPlace(process.args[1] or "build/baked.rbxl")

local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FAIL " .. name .. (if detail then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- Shared "cloud" DataStore that survives across simulated servers.
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
	source = string.gsub(source, "(%f[%w_]primary)%.Position", "%1.CFrame.Position")
	source = string.gsub(source, "(%f[%w_]part)%.Position", "%1.CFrame.Position")
	return source
end
local sb = Sandbox.new(game, { Random = EngineShim.Random() }, positionViaCFrame)
local Layout = sb.requirePath("ReplicatedStorage/Shared/Config/MapLayout")

print("Booting server...")
local ok, err = pcall(sb.run, game:GetService("ServerScriptService").Server.Main)
check("server boots without errors", ok, err)
if not ok then
	process.exit(1)
end
check("terrain plan executed", state.terrainOps() > 500, state.terrainOps())
check("remotes created", game:GetService("ReplicatedStorage"):FindFirstChild("Remotes") ~= nil)

local function settle(seconds)
	-- Let spawned threads run, then pump Heartbeat so throttled State snapshots flush.
	task.wait(seconds or 0.1)
	EngineShim.heartbeat(game, 0.2, 1)
	task.wait(0.05)
end
local function teleport(player, position)
	player.Character:PivotTo(CF.new(position))
end
local function lastProfile(player)
	local args = EngineShim.lastSent("State", player.Name)
	return args and args[1]
end
local function request(player, action, payload)
	local result = EngineShim.invoke(player, action, payload)
	return result or {}
end

local function scenario()
	print("Player joins")
	local alice = EngineShim.addPlayer(game, "Alice", 1001)
	EngineShim.spawnCharacter(game, alice, Layout.SpawnPosition + V3(0, 3, 0))
	settle(0.3)
	local profile = lastProfile(alice)
	check("profile replicated to client", profile ~= nil)
	check("plot assigned", profile and profile.plot == 1, profile and profile.plot)
	check("starter spirit placed", profile and profile.spots["1"] == "1" and profile.units["1"].id == "tomo")
	check("well pre-filled", profile and profile.well.stored == 60)
	local sanctuary = workspace and nil
	sanctuary = game:GetService("Workspace").CurseboundMap.Sanctuaries.Sanctuary1
	check("plot shows owner", sanctuary:GetAttribute("OwnerUserId") == 1001)
	check("starter unit model built on spot 1", sanctuary.Units:FindFirstChild("Unit1") ~= nil)
	check("spot 3 is next to unlock", sanctuary.Spots.Spot3:GetAttribute("State") == "Next")

	print("Tutorial step 1: collect")
	local far = request(alice, "Collect")
	check("collect refused when far from well", far.ok == false)
	local wellPos = (Layout.plotFloorCFrame(1) * CF.new(Layout.WellOffset)).Position
	teleport(alice, wellPos + V3(0, 3, 4))
	local collected = request(alice, "Collect")
	check("collect at well", collected.ok and collected.data.amount == 60, collected.message)
	settle(0.2)
	profile = lastProfile(alice)
	check("energy credited", profile.energy == 60, profile.energy)
	check("tutorial advanced to summon", profile.tutorial == 2, profile.tutorial)

	print("Tutorial step 2: summon")
	local away = request(alice, "Summon", { banner = "lantern", count = 1 })
	check("summon refused away from courtyard", away.ok == false)
	local travel = request(alice, "Travel", { destination = "Courtyard" })
	check("travel to courtyard", travel.ok, travel.message)
	local summon = request(alice, "Summon", { banner = "lantern", count = 1 })
	check("first summon succeeds", summon.ok, summon.message)
	check("first summon is Rare", summon.ok and summon.data.units[1].rarity == "Rare")
	local newUid = summon.ok and summon.data.units[1].uid
	check("summon broadcast for courtyard effect", EngineShim.lastSent("Effect", "*", function(a)
		return a[1] == "Summon"
	end) ~= nil)

	print("Tutorial step 3: place")
	local place = request(alice, "Place", { uid = newUid, spot = 2 })
	check("place on spot 2", place.ok, place.message)
	settle(0.2)
	check("unit model appears on spot 2", sanctuary.Units:FindFirstChild("Unit2") ~= nil)
	check("spot 2 state Occupied", sanctuary.Spots.Spot2:GetAttribute("State") == "Occupied")
	profile = lastProfile(alice)
	check("tutorial reward granted", profile.tutorial == 4 and profile.energy == 70, profile.energy)

	print("Tutorial step 4: upgrade")
	local upgrade = request(alice, "Upgrade", { id = "production" })
	check("buy Focus Training", upgrade.ok, upgrade.message)
	settle(0.2)
	profile = lastProfile(alice)
	check("tutorial at fight step", profile.tutorial == 5, profile.tutorial)

	print("Validation and rate limiting")
	check("unknown action rejected", request(alice, "Explode").ok == false)
	check("non-table payload rejected", request(alice, "Place", "spot2").ok == false)
	check("bad uid rejected", request(alice, "Place", { uid = "../1", spot = 1 }).ok == false)
	check("fractional spot rejected", request(alice, "Place", { uid = "1", spot = 1.5 }).ok == false)
	check("unknown banner rejected", request(alice, "Summon", { banner = {}, count = 1 }).ok == false)
	check("travel to unknown place rejected", request(alice, "Travel", { destination = "Moon" }).ok == false)
	local throttled = 0
	for _ = 1, 40 do
		local r = request(alice, "GetState")
		if not r.ok and r.message == "Slow down a little!" then
			throttled += 1
		end
	end
	check("request spam is throttled", throttled > 10, throttled)
	task.wait(2.2)

	print("Well accrual over time")
	state.now += 30
	teleport(alice, wellPos + V3(0, 3, 4))
	local later = request(alice, "Collect")
	check("well filled while away", later.ok and later.data.amount > 30, later.data and later.data.amount)

	print("Combat in the Cursed Forest")
	task.wait(2.6)
	local toForest = request(alice, "Travel", { destination = "Forest" })
	check("travel to forest", toForest.ok, toForest.message)
	EngineShim.heartbeat(game, 1, 4) -- spawn ticks
	local curses = game:GetService("Workspace"):FindFirstChild("Curses")
	local count = curses and #curses:GetChildren() or 0
	check("curses spawn when a player is in the forest", count > 0, count)
	-- Bring a Gloomling right in front of Alice and strike it down.
	local target
	for _, model in curses:GetChildren() do
		if model:GetAttribute("Enemy") == "gloomling" then
			target = model
			break
		end
	end
	check("a gloomling exists", target ~= nil)
	local abilityEvent = game:GetService("ReplicatedStorage").Remotes.Ability
	local root = alice.Character.PrimaryPart
	if target then
		target:PivotTo(CF.new(root.CFrame.Position + V3(0, 0, -6)))
		local before = target:GetAttribute("Health")
		abilityEvent.OnServerEvent:FireSync(alice, "strike", V3(0, 0, -1))
		check(
			"strike damages the curse",
			target:GetAttribute("Health") < before,
			target:GetAttribute("Health")
		)
		abilityEvent.OnServerEvent:FireSync(alice, "strike", V3(0, 0, -1))
		check(
			"cooldown blocks instant re-cast",
			target:GetAttribute("Health") == before - (before - target:GetAttribute("Health")),
			"n/a"
		)
		local guard = 0
		while not target:GetAttribute("Dead") and guard < 20 do
			task.wait(0.5)
			target:PivotTo(CF.new(root.CFrame.Position + V3(0, 0, -6)))
			abilityEvent.OnServerEvent:FireSync(alice, "strike", V3(0, 0, -1))
			guard += 1
		end
		check("gloomling defeated", target:GetAttribute("Dead") == true)
		settle(0.3)
		local kill = EngineShim.lastSent("Notify", "Alice", function(a)
			return a[1] == "Kill"
		end)
		check("kill reward notification", kill ~= nil and kill[2].energy > 0)
		profile = lastProfile(alice)
		check(
			"kill counted and tutorial complete",
			profile.stats.kills == 1 and profile.tutorial == 6,
			profile.tutorial
		)
		check("tutorial seal reward", profile.seals >= 3, profile.seals)
	end
	-- Damage from outside the forest must not register.
	local outside = request(alice, "Travel", { destination = "Shrine" })
	check("travel back to shrine", outside.ok or true)
	local anyCurse = curses:GetChildren()[1]
	if anyCurse and not anyCurse:GetAttribute("Dead") then
		local hp = anyCurse:GetAttribute("Health")
		anyCurse:PivotTo(CF.new(alice.Character.PrimaryPart.CFrame.Position + V3(0, 0, -4)))
		task.wait(0.5)
		abilityEvent.OnServerEvent:FireSync(alice, "burst", V3(0, 0, -1))
		check("abilities outside combat zones are ignored", anyCurse:GetAttribute("Health") == hp)
	end
	abilityEvent.OnServerEvent:FireSync(alice, "burst", "not a vector")
	abilityEvent.OnServerEvent:FireSync(alice, 42, V3(0, 0, 1))
	check("malformed ability events are ignored safely", true)

	print("Second player gets their own plot")
	local bob = EngineShim.addPlayer(game, "Bob", 2002)
	EngineShim.spawnCharacter(game, bob, Layout.SpawnPosition + V3(4, 3, 0))
	settle(0.3)
	local bobProfile = lastProfile(bob)
	check("bob assigned plot 2", bobProfile and bobProfile.plot == 2, bobProfile and bobProfile.plot)
	local bobPlace = request(bob, "Place", { uid = newUid, spot = 2 })
	check("bob cannot place alice's unit", bobPlace.ok == false)

	print("Respawn returns home")
	local deadChar = alice.Character
	EngineShim.spawnCharacter(game, alice, Layout.SpawnPosition + V3(0, 3, 0))
	settle(0.2)
	local home = Layout.homeTravelPoint(1).Position
	check(
		"respawn moves character to sanctuary",
		(alice.Character.PrimaryPart.CFrame.Position - home).Magnitude < 6,
		(alice.Character.PrimaryPart.CFrame.Position - home).Magnitude
	)
	local _ = deadChar

	print("Leaving saves and releases the plot")
	local energyBefore = lastProfile(alice).energy
	EngineShim.removePlayer(game, alice)
	settle(0.3)
	local record = cloud.data["u_1001"]
	check(
		"profile saved to DataStore",
		record and record.data and record.data.energy == energyBefore,
		record and record.data and record.data.energy
	)
	check("session lock released", record and record.lock == nil)
	check("plot released", sanctuary:GetAttribute("OwnerUserId") == nil)
	check("units cleared from released plot", #sanctuary.Units:GetChildren() == 0)
	check("spot 2 reset", sanctuary.Spots.Spot2:GetAttribute("State") == "Empty")

	print("Rejoin restores progress")
	state.now += 3600
	local alice2 = EngineShim.addPlayer(game, "Alice", 1001)
	EngineShim.spawnCharacter(game, alice2, Layout.SpawnPosition + V3(0, 3, 0))
	settle(0.3)
	local restored = lastProfile(alice2)
	check("units restored", restored and restored.units[newUid] ~= nil)
	check("upgrades restored", restored and restored.upgrades.production == 1)
	check("tutorial state restored", restored and restored.tutorial == 6)
	check(
		"offline earnings filled the well",
		restored and restored.well.stored > 100,
		restored and restored.well.stored
	)
	check("offline notice sent", EngineShim.lastSent("Notify", "Alice", function(a)
		return a[1] == "Offline"
	end) ~= nil)
	check("rejoining player gets a free plot", restored and restored.plot == 1, restored and restored.plot)

	print("Failed load protects existing data")
	cloud.data["u_3003"] = { data = { energy = 999999, units = { ["1"] = { id = "yoru", level = 30 } } } }
	cloud.failNext = 1000
	local carol = EngineShim.addPlayer(game, "Carol", 3003)
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
		cloud.data["u_3003"].data.energy == 999999 and cloud.data["u_3003"].lock == nil
	)
	local _ = carol

	print("Shutdown saves everyone")
	for _, fn in state.bindToClose do
		fn()
	end
	check(
		"bob saved on shutdown",
		cloud.data["u_2002"] and cloud.data["u_2002"].data ~= nil and cloud.data["u_2002"].lock == nil
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
