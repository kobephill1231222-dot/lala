--!nocheck
-- Client smoke test: runs the real client scripts (StarterPlayerScripts.Client) inside Lune
-- with a stubbed engine, feeds them a profile and drives every panel, placement, effects,
-- notifications and the recruitment reveal. Fails on any runtime error.
-- Usage: lune run tools/lune/client_smoke.luau build/baked.rbxl
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Sandbox = require("./lib/Sandbox")
local EngineShim = require("./lib/EngineShim")

local game = Sandbox.loadPlace(process.args[1] or "build/baked.rbxl")
local Signal = EngineShim.Signal
local errors = {}

local function fakeSignal()
	return Signal.new("fake")
end

-- Engine stubs for client-only APIs ------------------------------------------------------
EngineShim.install(game, {})
local signalCache = {}
local nextId = 0
local function instanceSignal(inst, key)
	local id = inst:GetAttribute("__clientSig")
	if not id then
		nextId += 1
		id = nextId
		inst:SetAttribute("__clientSig", id)
	end
	signalCache[id] = signalCache[id] or {}
	signalCache[id][key] = signalCache[id][key] or fakeSignal()
	return signalCache[id][key]
end
for _, pair in
	{
		{ "GuiButton", "Activated" },
		{ "GuiButton", "MouseButton1Down" },
		{ "GuiObject", "MouseEnter" },
		{ "GuiObject", "MouseLeave" },
		{ "ProximityPrompt", "Triggered" },
		{ "RemoteEvent", "OnClientEvent" },
		{ "UserInputService", "InputBegan" },
		{ "UserInputService", "InputChanged" },
		{ "UserInputService", "LastInputTypeChanged" },
		{ "Instance", "ChildAdded" },
	}
do
	roblox.implementProperty(pair[1], pair[2], function(inst)
		return instanceSignal(inst, pair[2])
	end)
end
roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(inst, prop)
	return instanceSignal(inst, "prop_" .. prop)
end)
roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(inst, attr)
	return instanceSignal(inst, "attr_" .. attr)
end)
-- A canned server: realistic shapes for every action's result.
local CANNED = {
	Summon = { units = { { uid = "7", id = "kagerou", rarity = "Epic", isNew = true } } },
	Train = { uid = "2", level = 4, cost = 100 },
	Upgrade = { id = "production", level = 1, cost = 40 },
	UnlockSpot = { spot = 3, cost = 120 },
	Release = { uid = "2", value = 80 },
	Place = { spot = 3 },
	Unplace = { spot = 2, uid = "2" },
	Collect = { amount = 60 },
	Travel = { destination = "Home" },
}
roblox.implementMethod("RemoteFunction", "InvokeServer", function(_, action, _payload)
	return { ok = true, data = CANNED[action] or {} }
end)
roblox.implementMethod("RemoteEvent", "FireServer", function() end)
roblox.implementMethod("TweenService", "Create", function(_, inst, _info, props)
	local completed = fakeSignal()
	return {
		Completed = completed,
		Play = function()
			-- Apply immediately and complete on the next tick.
			for k, v in props do
				pcall(function()
					inst[k] = v
				end)
			end
			task.delay(0.01, function()
				completed:FireSync()
			end)
		end,
		Cancel = function() end,
	}
end)
roblox.implementMethod("Debris", "AddItem", function() end)
roblox.implementMethod("ContentProvider", "PreloadAsync", function() end)
roblox.implementMethod("Sound", "Play", function() end)
roblox.implementMethod("UserInputService", "GetFocusedTextBox", function()
	return nil
end)
roblox.implementMethod("Player", "GetMouse", function()
	return { Hit = roblox.CFrame.new(0, 0, -50) }
end)
roblox.implementMethod("Camera", "ViewportPointToRay", function()
	return { Origin = roblox.Vector3.new(0, 50, 0), Direction = roblox.Vector3.new(0, -1, 0) }
end)
roblox.implementMethod("Workspace", "Raycast", function()
	return nil
end)
roblox.implementMethod("ParticleEmitter", "Emit", function() end)
roblox.implementMethod("Animator", "LoadAnimation", function()
	return { Play = function() end }
end)

-- Defaults for properties the engine would normally fill in.
local DEFAULTS = {
	Sound = { IsPlaying = false },
	Camera = { ViewportSize = roblox.Vector2.new(1280, 720) },
	Humanoid = { Health = 100, MaxHealth = 100 },
}
local function instanceNew(className, parent)
	local inst = roblox.Instance.new(className)
	local defaults = DEFAULTS[className]
	if defaults then
		for k, v in defaults do
			inst[k] = v
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local InstanceShim = setmetatable({ new = instanceNew }, { __index = roblox.Instance })

local globals = {
	Random = EngineShim.Random(),
	Instance = InstanceShim,
	TweenInfo = {
		new = function(...)
			return { ... }
		end,
	},
	RaycastParams = {
		new = function()
			return {}
		end,
	},
}

-- Local player, character, camera, remotes ---------------------------------------------
local players = game:GetService("Players")
local player = roblox.Instance.new("Player")
player.Name = "Tester"
player.UserId = 4242
player.Parent = players
players.LocalPlayer = player
local playerGui = roblox.Instance.new("PlayerGui")
playerGui.Parent = player
local character = EngineShim.spawnCharacter(game, player, roblox.Vector3.new(0, 9, 176))
local camera = instanceNew("Camera")
camera.Parent = game:GetService("Workspace")
game:GetService("Workspace").CurrentCamera = camera
local uis = game:GetService("UserInputService")
uis.TouchEnabled = false
uis.KeyboardEnabled = true
uis.MouseEnabled = true
local curses = roblox.Instance.new("Folder")
curses.Name = "Curses"
curses.Parent = game:GetService("Workspace")

local helper = Sandbox.new(game)
local Net = helper.requirePath("ReplicatedStorage/Shared/Net")
local remotesFolder = roblox.Instance.new("Folder")
remotesFolder.Name = Net.FolderName
remotesFolder.Parent = game:GetService("ReplicatedStorage")
for name, className in
	{
		Request = "RemoteFunction",
		State = "RemoteEvent",
		Notify = "RemoteEvent",
		Effect = "RemoteEvent",
		Ability = "RemoteEvent",
	}
do
	local remote = roblox.Instance.new(className)
	remote.Name = name
	remote.Parent = remotesFolder
end

-- Client sandbox: positions via CFrame (Lune limitation), same as the server harness.
local function transform(source, name)
	if not (string.find(name, "StarterPlayer") or string.find(name, "Shared")) then
		return source
	end
	source = string.gsub(source, "([%w_]*[Rr]oot)%.Position", "%1.CFrame.Position")
	source = string.gsub(source, "(%f[%w_]marker)%.Position", "%1.CFrame.Position")
	source = string.gsub(source, "(%f[%w_]anchor)%.Position", "%1.CFrame.Position")
	source = string.gsub(source, "(%f[%w_]post)%.Position", "%1.CFrame.Position")
	return source
end
local sb = Sandbox.new(game, globals, transform)
local client = game:GetService("StarterPlayer").StarterPlayerScripts.Client

local function step(name, fn)
	local ok, err = xpcall(fn, function(e)
		return tostring(e) .. "\n" .. tostring(debug.traceback())
	end)
	if ok then
		print("  ok   " .. name)
	else
		table.insert(errors, name .. ": " .. tostring(err))
		print("  FAIL " .. name .. "\n" .. tostring(err))
	end
end

local runService = game:GetService("RunService")
local function frames(n)
	for _ = 1, n do
		runService.RenderStepped:FireSync(1 / 30)
		runService.Heartbeat:FireSync(1 / 30)
	end
	task.wait(0.05)
end

step("client boots", function()
	sb.run(client.Main)
	task.wait(0.3)
end)

local function req(path)
	return sb.requirePath("StarterPlayer/StarterPlayerScripts/Client/" .. path)
end
local Schema = sb.requirePath("ReplicatedStorage/Shared/Rules/ProfileSchema")
local UIController = req("Controllers/UIController")
local PlacementController = req("Controllers/PlacementController")
local RevealController = req("Controllers/RevealController")
local StateController = req("Controllers/StateController")
local CombatController = req("Controllers/CombatController")

local profile = Schema.publicView(Schema.new(1_700_000_000))
profile.units["2"] = { id = "suzu", level = 3 }
profile.units["3"] = { id = "yoru", level = 1 }
profile.spots["2"] = "2"
profile.discovered.suzu = true
profile.discovered.yoru = true
profile.energy = 5000
profile.seals = 20
profile.plot = 1
profile.serverTime = 1_700_000_000
profile.persistent = true
local stateRemote = remotesFolder.State
local notifyRemote = remotesFolder.Notify
local effectRemote = remotesFolder.Effect

step("receives first state snapshot", function()
	stateRemote.OnClientEvent:FireSync(profile)
	task.wait(0.3)
	frames(5)
	assert(StateController.profile ~= nil, "profile not stored")
end)
step("HUD exists", function()
	local gui = playerGui:FindFirstChild("CurseboundUI")
	assert(gui and gui:FindFirstChild("HUD", true), "HUD missing")
end)
step("own plot prompts created", function()
	task.wait(0.2)
	local count = 0
	for _, d in game:GetService("Workspace").CurseboundMap.Sanctuaries.Sanctuary1:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			count += 1
		end
	end
	assert(count >= 11, "expected well + 10 spot prompts, got " .. count)
end)
for _, panel in { "Summon", "Units", "Upgrades", "Travel", "Settings" } do
	step("open panel " .. panel, function()
		UIController.open(panel)
		task.wait(0.05)
		frames(3)
		stateRemote.OnClientEvent:FireSync(profile)
		task.wait(0.05)
		UIController.close()
	end)
end
step("units panel in pick-spot mode", function()
	UIController.open("Units", { pickSpot = 3 })
	task.wait(0.05)
	UIController.close()
	UIController.open("Units", { uid = "3" })
	task.wait(0.05)
	UIController.close()
end)
step("all panel buttons can be activated", function()
	for _, panel in { "Units", "Upgrades", "Settings", "Summon" } do
		UIController.open(panel)
		task.wait(0.05)
		local buttons = {}
		for _, d in playerGui.CurseboundUI.Panels:GetDescendants() do
			if d:IsA("TextButton") and d.Name == "Button" then
				local label = d:FindFirstChild("Label")
				local text = label and label.Text or ""
				-- Skip travel/close/placement/summon buttons (they yield or leave the panel)
				if
					not string.find(text, "Travel")
					and text ~= "X"
					and not string.find(text, "Place")
					and not string.find(text, "Summon")
				then
					table.insert(buttons, d)
				end
			end
		end
		for _, button in buttons do
			-- Earlier clicks may rebuild the panel; destroyed buttons are skipped.
			local ok, parent = pcall(function()
				return button.Parent
			end)
			if ok and parent ~= nil then
				button.Activated:FireSync()
			end
		end
		task.wait(0.05)
		UIController.close()
	end
end)
step("placement mode begins and cancels", function()
	PlacementController.begin("3")
	task.wait(0.1)
	frames(3)
	assert(PlacementController.isActive(), "placement not active")
	PlacementController.cancel()
end)
step("server effects render", function()
	effectRemote.OnClientEvent:FireSync("Collect", { plot = 1, amount = 120, userId = 4242 })
	effectRemote.OnClientEvent:FireSync("Summon", { userId = 1, rarity = "Legendary" })
	effectRemote.OnClientEvent:FireSync("Place", { plot = 1, spot = 2 })
	effectRemote.OnClientEvent:FireSync("Unlock", { plot = 1, spot = 3 })
	effectRemote.OnClientEvent:FireSync("Train", { plot = 1, spot = 2 })
	effectRemote.OnClientEvent:FireSync("Cast", {
		userId = 9,
		ability = "burst",
		origin = roblox.Vector3.new(0, 3, -150),
		direction = roblox.Vector3.new(0, 0, -1),
	})
	effectRemote.OnClientEvent:FireSync(
		"Hits",
		{ ability = "strike", hits = { { position = roblox.Vector3.new(0, 3, -150), damage = 15 } } }
	)
	effectRemote.OnClientEvent:FireSync(
		"CurseDeath",
		{ position = roblox.Vector3.new(0, 3, -150), enemy = "gloomling" }
	)
	effectRemote.OnClientEvent:FireSync(
		"CurseStrike",
		{ position = roblox.Vector3.new(0, 3, -150), radius = 6, enemy = "brute" }
	)
	task.wait(0.2)
	frames(10)
end)
step("notifications become toasts", function()
	for _, n in
		{
			{ "Toast", { text = "Hello", tone = "bad" } },
			{ "Kill", { name = "Gloomling", energy = 50, seals = 1 } },
			{ "TutorialStep", { completed = "Gather", reward = { energy = 60 }, nextStep = 6 } },
			{ "Offline", { amount = 100, text = "Welcome back" } },
			{ "StudioMode", {} },
		}
	do
		notifyRemote.OnClientEvent:FireSync(n[1], n[2])
	end
	task.wait(0.1)
end)
step("tutorial guidance follows steps", function()
	for stepIndex = 1, 6 do
		profile.tutorial = stepIndex
		stateRemote.OnClientEvent:FireSync(profile)
		task.wait(0.05)
		frames(2)
	end
end)
step("combat bar in the forest", function()
	character:PivotTo(roblox.CFrame.new(0, 3, -150))
	frames(12)
	CombatController.use("strike")
	CombatController.use("lance")
	CombatController.use("burst")
	frames(3)
end)
step("recruitment reveal plays through", function()
	local done = false
	task.spawn(function()
		RevealController.play({
			units = {
				{ uid = "7", id = "kagerou", rarity = "Epic", isNew = true },
				{ uid = "8", id = "kokuyo", rarity = "Mythic", isNew = true },
			},
		}, function()
			done = true
		end)
	end)
	local input =
		{ UserInputType = roblox.Enum.UserInputType.MouseButton1, KeyCode = roblox.Enum.KeyCode.Unknown }
	for _ = 1, 40 do
		task.wait(0.15)
		uis.InputBegan:FireSync(input, false)
		frames(1)
		-- Press "Summon more" on the wrap-up card when it appears
		local reveal = playerGui:FindFirstChild("Reveal")
		if reveal then
			for _, d in reveal:GetDescendants() do
				if d:IsA("TextButton") and d.Name == "Button" then
					local label = d:FindFirstChild("Label")
					if label and label.Text == "Summon more" then
						d.Activated:FireSync()
					end
				end
			end
		end
		if done then
			break
		end
	end
	assert(done, "reveal did not finish")
	UIController.close(true)
end)

print(string.format("\nClient smoke: %d failure(s)", #errors))
process.exit(if #errors == 0 then 0 else 1)
