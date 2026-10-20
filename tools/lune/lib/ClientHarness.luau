--!nocheck
-- Runs the real client (StarterPlayerScripts.Client) inside Lune with a stubbed engine, a canned
-- server, a local player standing on Farm 1 and a mid-game profile, and renders whatever is on
-- screen to a PNG (through GuiExport + tools/pixel/rasterize.mjs).
--
--   local H = ClientHarness.new("dist/JJKFarm.rbxl", { width = 1280, height = 720 })
--   H:boot()                       -- runs Client/Main and pushes the first profile
--   H:frames(30)                   -- RenderStepped + Heartbeat, server clock advances
--   H:key("E")                     -- a key press (InputBegan)
--   H:moveTo(Layout.homeCFrame(1).Position)
--   H:render("build/shot.png")     -- every ScreenGui in PlayerGui, by DisplayOrder
--   H.invoked, H.canned, H.profile, H.sb, H.player, H.character, H.playerGui
--   H:finish(0)                    -- always end with this (client loops keep Lune alive)
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Sandbox = require("./Sandbox")
local EngineShim = require("./EngineShim")
local GuiExport = require("./GuiExport")

local ClientHarness = {}
ClientHarness.__index = ClientHarness

local installed = false
local shimState = nil
local signalCache, nextId = {}, 0

local function instanceSignal(inst, key)
	local id = inst:GetAttribute("__clientSig")
	if not id then
		nextId += 1
		id = nextId
		inst:SetAttribute("__clientSig", id)
	end
	signalCache[id] = signalCache[id] or {}
	signalCache[id][key] = signalCache[id][key] or EngineShim.Signal.new(key)
	return signalCache[id][key]
end
ClientHarness.signal = instanceSignal

local NOW = 1_700_000_000.5
ClientHarness.NOW = NOW

-- Canned results for every request the client can send.
ClientHarness.CANNED = {
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

local function install(game, invoked)
	if installed then
		return
	end
	installed = true
	shimState = EngineShim.install(game, { startTime = NOW })
	for _, pair in
		{
			{ "GuiButton", "Activated" },
			{ "GuiButton", "MouseButton1Down" },
			{ "GuiButton", "MouseButton1Click" },
			{ "GuiObject", "MouseEnter" },
			{ "GuiObject", "MouseLeave" },
			{ "GuiObject", "InputBegan" },
			{ "ProximityPrompt", "Triggered" },
			{ "RemoteEvent", "OnClientEvent" },
			{ "UserInputService", "InputBegan" },
			{ "UserInputService", "InputEnded" },
			{ "UserInputService", "InputChanged" },
			{ "UserInputService", "LastInputTypeChanged" },
			{ "UserInputService", "TouchPinch" },
			{ "UserInputService", "TouchTap" },
			{ "Instance", "ChildAdded" },
			{ "Instance", "ChildRemoved" },
			{ "Instance", "DescendantAdded" },
			{ "DataModel", "Loaded" },
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
	roblox.implementMethod("RemoteFunction", "InvokeServer", function(_, action, payload)
		invoked[action] = (invoked[action] or 0) + 1
		table.insert(invoked, { action = action, payload = payload })
		return { ok = true, data = ClientHarness.CANNED[action] or {} }
	end)
	roblox.implementMethod("RemoteEvent", "FireServer", function() end)
	roblox.implementMethod("TweenService", "Create", function(_, inst, _info, props)
		local completed = EngineShim.Signal.new("Completed")
		return {
			Completed = completed,
			Play = function()
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
	roblox.implementMethod("Sound", "Stop", function() end)
	roblox.implementMethod("UserInputService", "GetFocusedTextBox", function()
		return nil
	end)
	roblox.implementMethod("UserInputService", "GetMouseLocation", function()
		return roblox.Vector2.new(640, 360)
	end)
	roblox.implementMethod("UserInputService", "IsKeyDown", function()
		return false
	end)
	roblox.implementMethod("Player", "GetMouse", function()
		return { Hit = roblox.CFrame.new(0, 0, -50), X = 640, Y = 360 }
	end)
	roblox.implementMethod("Camera", "ScreenPointToRay", function()
		return { Origin = roblox.Vector3.new(0, 50, 0), Direction = roblox.Vector3.new(0, -1, 0) }
	end)
	roblox.implementMethod("Camera", "ViewportPointToRay", function()
		return { Origin = roblox.Vector3.new(0, 50, 0), Direction = roblox.Vector3.new(0, -1, 0) }
	end)
	roblox.implementMethod("Workspace", "Raycast", function()
		return nil
	end)
	roblox.implementMethod("ParticleEmitter", "Emit", function() end)
	roblox.implementMethod("RunService", "BindToRenderStep", function(rs, _name, _priority, fn)
		rs.RenderStepped:Connect(fn)
	end)
	roblox.implementMethod("RunService", "UnbindFromRenderStep", function() end)
	roblox.implementMethod("DataModel", "IsLoaded", function()
		return true
	end)
	roblox.implementMethod("ContextActionService", "BindAction", function() end)
	roblox.implementMethod("ContextActionService", "BindActionAtPriority", function() end)
	roblox.implementMethod("ContextActionService", "UnbindAction", function() end)
end

local DEFAULTS = {
	Sound = { IsPlaying = false },
	Camera = { ViewportSize = roblox.Vector2.new(1280, 720) },
	Humanoid = { Health = 100, MaxHealth = 100 },
}

function ClientHarness.new(placePath, options)
	options = options or {}
	local self = setmetatable({}, ClientHarness)
	self.width = options.width or 1280
	self.height = options.height or 720
	self.invoked = {}
	self.canned = ClientHarness.CANNED
	self.errors = {}
	local game = Sandbox.loadPlace(placePath)
	self.game = game
	-- Optional stand-in art (options.stubArt = a folder of <Name>.luau) for any Art module the
	-- place doesn't have.
	local stubDir = options.stubArt
	local pixel = game:GetService("ReplicatedStorage").Shared:FindFirstChild("Pixel")
	if pixel and stubDir and fs.isDir(stubDir) then
		local art = pixel:FindFirstChild("Art")
		if not art then
			art = roblox.Instance.new("Folder")
			art.Name = "Art"
			art.Parent = pixel
		end
		self.stubbed = {}
		for _, name in { "World", "Characters", "Crates", "Icons", "Fx" } do
			if not art:FindFirstChild(name) and fs.isFile(stubDir .. name .. ".luau") then
				local m = roblox.Instance.new("ModuleScript")
				m.Name = name
				m.Source = fs.readFile(stubDir .. name .. ".luau")
				m.Parent = art
				table.insert(self.stubbed, name)
			end
		end
	end
	install(game, self.invoked)
	self.shim = shimState
	shimState.now = NOW

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
	local globals = {
		Random = EngineShim.Random(),
		Instance = setmetatable({ new = instanceNew }, { __index = roblox.Instance }),
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

	-- Local player, character, camera, remotes
	local players = game:GetService("Players")
	local player = roblox.Instance.new("Player")
	player.Name = "Tester"
	player.DisplayName = "Tester"
	player.UserId = 4242
	player.Parent = players
	players.LocalPlayer = player
	self.player = player
	local playerGui = roblox.Instance.new("PlayerGui")
	playerGui.Parent = player
	self.playerGui = playerGui
	local helper = Sandbox.new(game)
	local Layout = helper.requirePath("ReplicatedStorage/Shared/Config/FarmLayout")
	self.Layout = Layout
	self.character = EngineShim.spawnCharacter(game, player, Layout.homeCFrame(1).Position)
	EngineShim.state.players[4242] = player
	local camera = instanceNew("Camera")
	camera.Parent = game:GetService("Workspace")
	game:GetService("Workspace").CurrentCamera = camera
	self.camera = camera
	local uis = game:GetService("UserInputService")
	uis.TouchEnabled = options.touch == true
	uis.KeyboardEnabled = options.touch ~= true
	uis.MouseEnabled = options.touch ~= true
	self.uis = uis
	local Net = helper.requirePath("ReplicatedStorage/Shared/Net")
	local remotesFolder = roblox.Instance.new("Folder")
	remotesFolder.Name = Net.FolderName
	remotesFolder.Parent = game:GetService("ReplicatedStorage")
	for name, className in
		{ Request = "RemoteFunction", State = "RemoteEvent", Notify = "RemoteEvent", Effect = "RemoteEvent" }
	do
		local remote = roblox.Instance.new(className)
		remote.Name = name
		remote.Parent = remotesFolder
	end
	self.remotes = remotesFolder

	-- What the server publishes: Farm 1 owned by the tester with Sorcerers and a crate.
	local farms = game:GetService("Workspace").JJKFarmMap.Farms
	for index = 1, Layout.FarmCount do
		local farm = farms["Farm" .. index]
		local runtime = roblox.Instance.new("Folder")
		runtime.Name = "Runtime"
		runtime.Parent = farm
		for _, name in { "Sorcerers", "Crates" } do
			local f = roblox.Instance.new("Folder")
			f.Name = name
			f.Parent = runtime
		end
	end
	local farm1 = farms.Farm1
	farm1:SetAttribute("OwnerId", 4242)
	farm1:SetAttribute("OwnerName", "Tester")
	farm1:SetAttribute("Ops", 2.4)
	farm1:SetAttribute("CashRate", 40)
	farm1:SetAttribute("BoxOrbs", 12)
	farm1:SetAttribute("BoxValue", 30)
	farm1:SetAttribute("BoxT", NOW)
	farm1:SetAttribute("BoxCap", 60)
	farm1:SetAttribute("UnlockedSlots", 4)
	farm1:SetAttribute("UnlockedPads", 2)
	self.farm1 = farm1
	for slot, id in { [1] = "suzu", [2] = "yoru", [3] = "kai" } do
		self:addSorcerer(1, slot, id, 3)
	end
	self:addCrate(1, 1, "basic", NOW + 20, "4")
	local farm2 = farms.Farm2
	farm2:SetAttribute("OwnerId", 5151)
	farm2:SetAttribute("OwnerName", "Neighbour")
	farm2:SetAttribute("UnlockedSlots", 3)
	farm2:SetAttribute("UnlockedPads", 2)
	self:addSorcerer(2, 1, "rei", 1)

	-- Client sandbox: Lune can't read BasePart.Position; rewrite the common spellings.
	local function transform(source, name)
		if not (string.find(name, "StarterPlayer") or string.find(name, "Shared")) then
			return source
		end
		source = string.gsub(source, "([%w_]*[Rr]oot)%.Position", "%1.CFrame.Position")
		return source
	end
	self.sb = Sandbox.new(game, globals, transform)

	local Schema = self.sb.requirePath("ReplicatedStorage/Shared/Rules/ProfileSchema")
	local raw = Schema.new(NOW)
	raw.units["2"] = { id = "suzu", level = 3 }
	raw.units["3"] = { id = "yoru", level = 1 }
	raw.units["6"] = { id = "kai", level = 1 }
	raw.slots["1"] = "2"
	raw.slots["2"] = "3"
	raw.slots["3"] = "6"
	raw.crates["1"] = nil
	raw.crates["4"] = { tier = "basic", pad = 1, readyAt = NOW + 20 }
	raw.crates["5"] = { tier = "rare" }
	raw.discovered.suzu = true
	raw.discovered.yoru = true
	raw.discovered.kai = true
	raw.cash = 12450
	raw.box = { orbs = 12, value = 30, t = NOW }
	raw.upgrades.slots = 1
	local profile = Schema.publicView(raw)
	profile.farm = 1
	profile.serverTime = NOW
	profile.persistent = true
	self.profile = profile
	return self
end

function ClientHarness:addSorcerer(farm, slot, id, level)
	local folder = self.game:GetService("Workspace").JJKFarmMap.Farms["Farm" .. farm].Runtime.Sorcerers
	local item = roblox.Instance.new("Folder")
	item.Name = "Sorcerer" .. slot
	item:SetAttribute("Slot", slot)
	item:SetAttribute("SorcererId", id)
	item:SetAttribute("Level", level or 1)
	item:SetAttribute("Farm", farm)
	item:SetAttribute("Uid", tostring(slot + 1))
	item:SetAttribute("Ops", 1)
	item:SetAttribute("OrbValue", 2)
	item.Parent = folder
	return item
end

function ClientHarness:addCrate(farm, pad, tier, readyAt, cid)
	local folder = self.game:GetService("Workspace").JJKFarmMap.Farms["Farm" .. farm].Runtime.Crates
	local item = roblox.Instance.new("Folder")
	item.Name = "Crate" .. pad
	item:SetAttribute("Pad", pad)
	item:SetAttribute("Tier", tier)
	item:SetAttribute("ReadyAt", readyAt)
	item:SetAttribute("Cid", cid or "4")
	item:SetAttribute("Farm", farm)
	item.Parent = folder
	return item
end

function ClientHarness:require(path)
	return self.sb.requirePath("StarterPlayer/StarterPlayerScripts/Client/" .. path)
end

-- Advances `n` frames of `dt` seconds (server clock too).
function ClientHarness:frames(n, dt)
	dt = dt or 1 / 30
	local rs = self.game:GetService("RunService")
	for _ = 1, n or 1 do
		self.shim.now += dt
		rs.RenderStepped:FireSync(dt)
		rs.Heartbeat:FireSync(dt)
	end
	task.wait(0.02)
end

function ClientHarness:push(profile)
	self.remotes.State.OnClientEvent:FireSync(profile or self.profile)
	task.wait(0.03)
end

function ClientHarness:notify(kind, payload)
	self.remotes.Notify.OnClientEvent:FireSync(kind, payload)
	task.wait(0.02)
end

function ClientHarness:effect(name, payload)
	self.remotes.Effect.OnClientEvent:FireSync(name, payload)
	task.wait(0.02)
end

-- Boots Client/Main, pushes the profile and lets a few frames run. Errors are collected.
function ClientHarness:boot()
	local client = self.game:GetService("StarterPlayer").StarterPlayerScripts.Client
	self.sb.run(client.Main)
	task.wait(0.2)
	self:push()
	self:frames(10)
end

function ClientHarness:key(name, ended)
	local input = {
		KeyCode = roblox.Enum.KeyCode[name],
		UserInputType = roblox.Enum.UserInputType.Keyboard,
		UserInputState = roblox.Enum.UserInputState.Begin,
	}
	self.uis.InputBegan:FireSync(input, false)
	if ended ~= false then
		self.uis.InputEnded:FireSync(input, false)
	end
	task.wait(0.02)
end

-- Clicks a GuiButton (fires Activated and MouseButton1Click).
function ClientHarness:click(button)
	instanceSignal(button, "Activated"):FireSync()
	instanceSignal(button, "MouseButton1Click"):FireSync()
	task.wait(0.02)
end

function ClientHarness:moveTo(position)
	self.character.HumanoidRootPart.CFrame = roblox.CFrame.new(position.X, 3, position.Z)
end

-- Every ScreenGui in PlayerGui, lowest DisplayOrder first, flattened into one export.
function ClientHarness:export()
	local out = { w = self.width, h = self.height, rects = {}, texts = {} }
	local guis = {}
	for _, gui in self.playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui.Enabled ~= false then
			table.insert(guis, gui)
		end
	end
	table.sort(guis, function(a, b)
		return a.DisplayOrder < b.DisplayOrder
	end)
	for _, gui in guis do
		GuiExport.collect(gui, self.width, self.height, out)
	end
	return out
end

-- Ends the run. The client starts background loops (state polling, timers) that would keep
-- Lune alive forever, so every script using the harness must finish with this.
function ClientHarness:finish(code)
	process.exit(code or 0)
end

-- Renders the screen to a PNG (needs node). Returns the PNG path.
function ClientHarness:render(pngPath, scale)
	local json = string.gsub(pngPath, "%.png$", ".json")
	local dir = string.match(pngPath, "^(.*)/[^/]+$")
	if dir then
		fs.writeDir(dir)
	end
	fs.writeFile(json, serde.encode("json", self:export()))
	local result = process.exec("node", { "tools/pixel/rasterize.mjs", json, pngPath, tostring(scale or 1) })
	if not result.ok then
		error("rasterize failed: " .. result.stderr)
	end
	return pngPath
end

return ClientHarness
