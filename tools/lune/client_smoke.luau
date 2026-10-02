--!nocheck
-- Client smoke test: runs the real client scripts (StarterPlayerScripts.Client) inside Lune
-- with a stubbed engine, feeds them a profile and drives every panel, prompt, placement,
-- production animation, effect, notification, tutorial step and the crate reveal.
-- Fails on any runtime error.
-- Usage: lune run tools/lune/client_smoke.luau dist/JJKFarm.rbxl
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Sandbox = require("./lib/Sandbox")
local EngineShim = require("./lib/EngineShim")

local game = Sandbox.loadPlace(process.args[1] or "dist/JJKFarm.rbxl")
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
		{ "Instance", "ChildRemoved" },
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
local NOW = 1_700_000_000
local CANNED = {
	OpenCrate = { uid = "9", id = "ryo", rarity = "Epic", isNew = true, tier = "rare", pad = 1 },
	BuyCrate = { cid = "8", tier = "basic", cost = 60 },
	PlaceCrate = { cid = "5", pad = 2, readyAt = NOW + 90, duration = 90 },
	PickUpCrate = { cid = "4", tier = "basic", pad = 1 },
	PlaceSorcerer = { slot = 2, uid = "3" },
	PickUpSorcerer = { slot = 1, uid = "2" },
	UpgradeSorcerer = { uid = "2", level = 4, cost = 100 },
	SellSorcerer = { uid = "3", id = "yoru", value = 60000 },
	BuyUpgrade = { id = "orbValue", level = 2, cost = 36 },
	Collect = { orbs = 20, value = 40, carried = 20 },
	Sell = { orbs = 20, cash = 40 },
}
local invoked = {}
roblox.implementMethod("RemoteFunction", "InvokeServer", function(_, action, _payload)
	invoked[action] = (invoked[action] or 0) + 1
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
roblox.implementMethod("Camera", "ScreenPointToRay", function()
	return { Origin = roblox.Vector3.new(0, 50, 0), Direction = roblox.Vector3.new(0, -1, 0) }
end)
roblox.implementMethod("UserInputService", "GetMouseLocation", function()
	return roblox.Vector2.new(640, 360)
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
local helper = Sandbox.new(game)
local Layout = helper.requirePath("ReplicatedStorage/Shared/Config/FarmLayout")
local character = EngineShim.spawnCharacter(game, player, Layout.homeCFrame(1).Position)
local camera = instanceNew("Camera")
camera.Parent = game:GetService("Workspace")
game:GetService("Workspace").CurrentCamera = camera
local uis = game:GetService("UserInputService")
uis.TouchEnabled = false
uis.KeyboardEnabled = true
uis.MouseEnabled = true
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

-- Simulate what the server puts on the map: runtime folders on every farm, Farm 1 owned by
-- the tester with two Sorcerers working and a crate opening, and its Orb Box numbers.
local CharacterModels = helper.requirePath("ReplicatedStorage/Shared/Visuals/CharacterModels")
local CrateModels = helper.requirePath("ReplicatedStorage/Shared/Visuals/CrateModels")
local farmsFolder = game:GetService("Workspace").JJKFarmMap.Farms
for index = 1, Layout.FarmCount do
	local farm = farmsFolder["Farm" .. index]
	local runtime = roblox.Instance.new("Folder")
	runtime.Name = "Runtime"
	runtime.Parent = farm
	for _, name in { "Sorcerers", "Crates" } do
		local f = roblox.Instance.new("Folder")
		f.Name = name
		f.Parent = runtime
	end
end
local farm1 = farmsFolder.Farm1
farm1:SetAttribute("OwnerId", 4242)
farm1:SetAttribute("OwnerName", "Tester")
farm1:SetAttribute("Ops", 2.4)
farm1:SetAttribute("CashRate", 40)
farm1:SetAttribute("BoxOrbs", 12)
farm1:SetAttribute("BoxValue", 30)
farm1:SetAttribute("BoxT", NOW)
farm1:SetAttribute("BoxCap", 60)
for slot, id in { [1] = "suzu", [2] = "yoru" } do
	local model = CharacterModels.build(
		id,
		Layout.slotWorld(1, slot) * roblox.CFrame.new(0, 0.5, 0),
		{ aura = true, scale = CharacterModels.FarmScale }
	)
	model.Name = "Sorcerer" .. slot
	model:SetAttribute("SorcererId", id)
	model:SetAttribute("Slot", slot)
	model:SetAttribute("Farm", 1)
	model:SetAttribute("Level", 3)
	model.Parent = farm1.Runtime.Sorcerers
end
local crateModel = CrateModels.build("basic", Layout.padWorld(1, 1) * roblox.CFrame.new(0, 0.6, 0))
crateModel.Name = "Crate1"
crateModel:SetAttribute("ReadyAt", NOW + 20)
crateModel:SetAttribute("Farm", 1)
crateModel:SetAttribute("Pad", 1)
crateModel.Parent = farm1.Runtime.Crates

step("client boots", function()
	sb.run(client.Main)
	task.wait(0.3)
end)

local function req(path)
	return sb.requirePath("StarterPlayer/StarterPlayerScripts/Client/" .. path)
end
local Schema = sb.requirePath("ReplicatedStorage/Shared/Rules/ProfileSchema")
local Tutorial = sb.requirePath("ReplicatedStorage/Shared/Rules/Tutorial")
local UIController = req("Controllers/UIController")
local PlacementController = req("Controllers/PlacementController")
local RevealController = req("Controllers/RevealController")
local StateController = req("Controllers/StateController")
local ProductionController = req("Controllers/ProductionController")
local WorldController = req("Controllers/WorldController")

local raw = Schema.new(NOW)
raw.units["2"] = { id = "suzu", level = 3 }
raw.units["3"] = { id = "yoru", level = 1 }
raw.units["6"] = { id = "kai", level = 1 }
raw.slots["1"] = "2"
raw.crates["1"] = nil
raw.crates["4"] = { tier = "basic", pad = 1, readyAt = NOW + 20 }
raw.crates["5"] = { tier = "rare" }
raw.discovered.suzu = true
raw.discovered.yoru = true
raw.cash = 1e6
raw.box = { orbs = 12, value = 30, t = NOW }
local profile = Schema.publicView(raw)
profile.farm = 1
profile.serverTime = NOW
profile.persistent = true
local stateRemote = remotesFolder.State
local notifyRemote = remotesFolder.Notify
local effectRemote = remotesFolder.Effect

local function push()
	stateRemote.OnClientEvent:FireSync(profile)
	task.wait(0.05)
end

step("receives first state snapshot", function()
	push()
	task.wait(0.3)
	frames(5)
	assert(StateController.profile ~= nil, "profile not stored")
	assert(StateController.farm() == 1, "farm not known")
end)
step("HUD shows Cash, income and the Orb Box", function()
	local gui = playerGui:FindFirstChild("JJKFarmUI")
	assert(gui and gui:FindFirstChild("HUD", true), "HUD missing")
	frames(30)
	local cash = gui:FindFirstChild("Cash", true)
	assert(cash and string.find(cash.Text, "%$"), "cash label: " .. tostring(cash and cash.Text))
	local count = gui:FindFirstChild("OrbBoxCard", true):FindFirstChild("Count")
	assert(count and string.find(count.Text, "/ 60"), "box label: " .. tostring(count and count.Text))
end)
step("HUD navigation stays on screen at every size", function()
	local gui = playerGui.JJKFarmUI
	local hud = gui.HUD
	assert(hud:FindFirstChildOfClass("UIScale") == nil, "the full-screen HUD container must not be scaled")
	local menu = hud.Menu
	assert(menu.AnchorPoint == roblox.Vector2.new(1, 0.5), "menu must anchor to the right edge")
	assert(menu.Position.X.Scale == 1 and menu.Position.X.Offset < 0, "menu must sit inside the right edge")
	local sizes = {
		{ 1558, 717 }, -- the reviewer's Studio viewport (minus top bar)
		{ 1920, 1044 },
		{ 1280, 684 },
		{ 1024, 600 },
		{ 812, 339 }, -- landscape phone, safe area
		{ 390, 760 }, -- portrait phone
		{ 2560, 1404 },
	}
	for _, wh in sizes do
		local w, h = wh[1], wh[2]
		local s = UIController._hudScaleFor(roblox.Vector2.new(w, h), false)
		local st = UIController._hudScaleFor(roblox.Vector2.new(w, h), true)
		for _, scale in { s, st } do
			local menuW, menuH = menu.Size.X.Offset * scale, menu.Size.Y.Offset * scale
			local statsW = hud.Stats.Size.X.Offset * scale
			local left = w - 12 - menuW
			assert(left >= 0 and w - 12 <= w, string.format("%dx%d: menu leaves the screen", w, h))
			assert(
				menuH <= h - 24 + 1e-6,
				string.format("%dx%d: menu taller than the screen (%.0f)", w, h, menuH)
			)
			assert(12 + statsW <= left + 1e-6, string.format("%dx%d: stats overlap the menu", w, h))
		end
	end
	-- The menu's children add up to the height the layout reserves.
	local total = 0
	local count = 0
	for _, child in menu:GetChildren() do
		if child:IsA("GuiObject") then
			total += child.Size.Y.Offset
			count += 1
		end
	end
	total += (count - 1) * 8
	assert(
		total <= menu.Size.Y.Offset,
		"menu buttons need " .. total .. "px, frame has " .. menu.Size.Y.Offset
	)
end)
step("Your Farm prompts created (pads, slots, Orb Box)", function()
	task.wait(0.2)
	frames(3)
	local count = 0
	for _, d in farm1:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			count += 1
		end
	end
	assert(count == 4 * 2 + 10 * 2 + 1, "prompts on Farm 1: " .. count)
	assert(farm1.Sign.SignGui.Title.Text == "Your Farm", "sign: " .. farm1.Sign.SignGui.Title.Text)
end)
step("plaza prompts created (Sell, Buy, shops)", function()
	local count = 0
	for _, d in game:GetService("Workspace").JJKFarmMap.Plaza:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			count += 1
		end
	end
	assert(count == 1 + 4 * 2 + 1 + 2, "plaza prompts: " .. count)
end)
step("prompt texts use the game's words", function()
	local pad1 = WorldController.padPrompt(1)
	local pad2 = WorldController.padPrompt(2)
	local pad3 = WorldController.padPrompt(3)
	local slot1 = WorldController.slotPrompt(1)
	local slot2 = WorldController.slotPrompt(2)
	local slot5 = WorldController.slotPrompt(5)
	assert(pad1.ActionText == "Open" and pad1.Enabled == false, "pad1 " .. pad1.ActionText)
	assert(
		pad2.ActionText == "Place" and pad2.ObjectText == "Rare Crate",
		"pad2 " .. pad2.ActionText .. " " .. pad2.ObjectText
	)
	assert(pad3.ActionText == "Upgrade" and pad3.ObjectText == "More Crate Pads", "pad3 " .. pad3.ObjectText)
	assert(slot1.ActionText == "Upgrade", "slot1 " .. slot1.ActionText)
	assert(slot2.ActionText == "Place" and slot2.ObjectText == "Yoru", "slot2 " .. slot2.ObjectText)
	assert(slot5.ActionText == "Upgrade" and slot5.ObjectText == "More Slots", "slot5 " .. slot5.ObjectText)
end)
step("production: techniques fire and Cursed Orbs travel the lane into the Orb Box", function()
	local fx = ProductionController.farmFx(1)
	assert(fx, "farm 1 not tracked")
	local workers = 0
	for _ in fx.workers do
		workers += 1
	end
	assert(workers == 2, "workers: " .. workers)
	local maxOrbs = 0
	for _ = 1, 150 do
		frames(1)
		maxOrbs = math.max(maxOrbs, ProductionController.orbCount())
	end
	assert(maxOrbs > 0, "no orbs were produced")
	local fill = farm1.OrbBox.Fill
	assert(fill.Size.Y > 0.5, "box fill didn't rise: " .. fill.Size.Y)
end)
step("crate timer label counts down", function()
	local found = false
	for _, d in playerGui.WorldLabels:GetDescendants() do
		if d:IsA("TextLabel") and string.find(d.Text, "Opening Time") then
			found = true
		end
	end
	assert(found, "no Opening Time label")
end)
for _, panel in { "Sorcerers", "Crates", "CrateShop", "UpgradeShop", "Settings" } do
	step("open panel " .. panel, function()
		UIController.open(panel)
		task.wait(0.05)
		frames(3)
		push()
		UIController.close()
	end)
end
step("all panel buttons can be activated", function()
	for _, panel in { "Sorcerers", "Crates", "CrateShop", "UpgradeShop", "Settings" } do
		UIController.open(panel)
		task.wait(0.05)
		local buttons, last = {}, {}
		for _, root in playerGui.JJKFarmUI.Panels.PanelScroller:GetChildren() do
			if root.Name == "Panel" and root.Visible then
				for _, d in root:GetDescendants() do
					if d:IsA("TextButton") and d.Name == "Button" then
						local label = d:FindFirstChild("Label")
						local text = label and label.Text or ""
						-- Skip close, placement and travel buttons (they leave the panel or yield);
						-- press Sell last since it removes the selected Sorcerer.
						if string.find(text, "^Sell") then
							table.insert(last, d)
						elseif
							text ~= "X"
							and text ~= "Place"
							and not string.find(text, "Walk")
							and not string.find(text, "Your Farm")
						then
							table.insert(buttons, d)
						end
					end
				end
			end
		end
		for _, d in last do
			table.insert(buttons, d)
		end
		for _, button in buttons do
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
	assert((invoked.UpgradeSorcerer or 0) > 0, "Upgrade never requested")
	assert((invoked.SellSorcerer or 0) > 0, "Sell never requested")
end)
step("world prompts send the right requests", function()
	for _, pair in { { "slot", 2 }, { "slot", 1 }, { "pad", 2 } } do
		local prompt = if pair[1] == "slot"
			then WorldController.slotPrompt(pair[2])
			else WorldController.padPrompt(pair[2])
		prompt.Triggered:FireSync()
	end
	assert(invoked.PlaceSorcerer and invoked.PlaceCrate, "place requests missing")
	for _, d in farm1:GetDescendants() do
		if d:IsA("ProximityPrompt") and (d.Name == "PickUpPrompt" or d.Name == "CollectPrompt") then
			d.Triggered:FireSync()
		end
	end
	assert(
		invoked.PickUpSorcerer and invoked.PickUpCrate and invoked.Collect,
		"pick up / collect requests missing"
	)
	for _, d in game:GetService("Workspace").JJKFarmMap.Plaza:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			d.Triggered:FireSync()
			UIController.close(true)
		end
	end
	assert(invoked.BuyCrate and invoked.Sell, "buy / sell requests missing")
end)
step("placement: Sorcerer preview on a slot, Place", function()
	PlacementController.beginSorcerer("3")
	task.wait(0.4)
	frames(3)
	assert(PlacementController.isActive(), "placement not active")
	assert(
		PlacementController.selected() == 2,
		"expected first empty slot preselected, got " .. tostring(PlacementController.selected())
	)
	local ghost = false
	for _, child in game:GetService("Workspace"):GetChildren() do
		if child.Name == "yoru" then
			ghost = true
		end
	end
	assert(ghost, "no ghost preview")
	PlacementController.confirm()
	assert(not PlacementController.isActive(), "placement didn't finish")
end)
step("placement: Crate preview on a pad, cancel", function()
	PlacementController.beginCrate("5")
	task.wait(0.4)
	frames(3)
	assert(
		PlacementController.isActive() and PlacementController.mode() == "crate",
		"crate placement not active"
	)
	PlacementController.cancel()
end)
step("server effects render", function()
	local V3 = roblox.Vector3.new
	effectRemote.OnClientEvent:FireSync("Collected", { farm = 1, orbs = 20, userId = 4242 })
	effectRemote.OnClientEvent:FireSync("Sold", { userId = 4242, cash = 40, orbs = 20 })
	effectRemote.OnClientEvent:FireSync("Placed", { farm = 1, slot = 2 })
	effectRemote.OnClientEvent:FireSync("Upgraded", { farm = 1, slot = 1 })
	effectRemote.OnClientEvent:FireSync("CratePlaced", { farm = 1, pad = 2 })
	effectRemote.OnClientEvent:FireSync("Bought", { userId = 1, tier = "rare" })
	effectRemote.OnClientEvent:FireSync(
		"CrateOpened",
		{ farm = 1, pad = 1, tier = "epic", id = "shion", rarity = "Legendary", userId = 1 }
	)
	for _ = 1, 90 do
		frames(1)
	end
	local _ = V3
end)
step("notifications become toasts", function()
	for _, n in
		{
			{ "Toast", { text = "Hello", tone = "bad" } },
			{ "TutorialStep", { completed = "Sell your orbs", reward = { cash = 50 }, nextStep = 6 } },
			{
				"TutorialStep",
				{ completed = "Upgrade your farm", reward = { cash = 50 }, nextStep = Tutorial.Done },
			},
			{
				"Offline",
				{
					seconds = 3600,
					orbs = 60,
					value = 120,
					cratesReady = 1,
					capped = false,
					boxFull = true,
					text = "While you were away (1h 00m), ...",
				},
			},
			{ "StudioMode", {} },
		}
	do
		notifyRemote.OnClientEvent:FireSync(n[1], n[2])
	end
	task.wait(0.1)
end)
step("tutorial guidance follows every step", function()
	for stepIndex = 1, Tutorial.Done do
		profile.tutorial = stepIndex
		profile.cash = if stepIndex % 2 == 0 then 0 else 1e6
		push()
		frames(2)
	end
	profile.carried = { orbs = 20, value = 40 }
	push()
	frames(20)
	profile.carried = { orbs = 0, value = 0 }
	profile.cash = 1e6
	push()
end)
step("crate reveal plays through to Place", function()
	profile.units["9"] = { id = "ryo", level = 1 }
	push()
	local done = false
	task.spawn(function()
		RevealController.play(
			{ uid = "9", id = "ryo", rarity = "Epic", isNew = true, tier = "rare", pad = 1 },
			function()
				done = true
			end
		)
	end)
	for _ = 1, 200 do
		frames(1)
		local reveal = playerGui:FindFirstChild("Reveal")
		if reveal and reveal:FindFirstChild("RevealCard", true) then
			for _, d in reveal:GetDescendants() do
				if d:IsA("TextButton") and d.Name == "Button" then
					local label = d:FindFirstChild("Label")
					if label and label.Text == "Place" then
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
	task.wait(0.4)
	frames(3)
	assert(PlacementController.isActive(), "Place on the reveal card should start placement")
	PlacementController.cancel()
end)
step("menu hotkeys and Home", function()
	for _, key in { "G", "C", "B", "U", "H" } do
		uis.InputBegan:FireSync(
			{ KeyCode = roblox.Enum.KeyCode[key], UserInputType = roblox.Enum.UserInputType.Keyboard },
			false
		)
		task.wait(0.02)
	end
	UIController.close(true)
	assert(invoked.GoHome, "Home not requested")
end)

print(string.format("\nClient smoke: %d failure(s)", #errors))
process.exit(if #errors == 0 then 0 else 1)
