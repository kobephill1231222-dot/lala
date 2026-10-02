--!strict
-- Handles every client request. Each handler validates its payload and the player's
-- position, applies the pure rule in Shared/Rules/Actions, then triggers replication,
-- farm updates, tutorial progress and effects. Cash only ever changes here, on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crates = require(Shared.Config.Crates)
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.FarmLayout)
local Rarities = require(Shared.Config.Rarities)
local Sorcerers = require(Shared.Config.Sorcerers)
local Upgrades = require(Shared.Config.Upgrades)
local Actions = require(Shared.Rules.Actions)
local Tutorial = require(Shared.Rules.Tutorial)
local Format = require(Shared.Util.Format)
local RateLimiter = require(Shared.Util.RateLimiter)

local GameService = {}

type Result = { ok: boolean, message: string?, data: any? }

local services: any
local requestLimiter = RateLimiter.new(8, 16)
local touchLimiter = RateLimiter.new(1, 2)
local rng = Random.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function fail(message: string): Result
	return { ok = false, message = message }
end

-- The character's root part, only while the character is alive. Every position-gated
-- action (prompts and touch pads alike) goes through this.
local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function distanceTo(player: Player, position: Vector3): number
	local root = rootOf(player)
	if not root then
		return math.huge
	end
	local delta = root.Position - position
	return Vector3.new(delta.X, 0, delta.Z).Magnitude
end

local function notify(player: Player, kind: string, payload: any)
	services.Remotes.Notify:FireClient(player, kind, payload)
end

local function effectAll(name: string, payload: any)
	services.Remotes.Effect:FireAllClients(name, payload)
end

-- Advances the tutorial if `event` matches the current step and tells the client.
local function tutorialEvent(player: Player, session: any, event: string)
	local step, reward = Tutorial.advance(session.profile, event)
	if step then
		notify(player, "TutorialStep", {
			completed = step.title,
			reward = reward,
			nextStep = session.profile.tutorial,
		})
	end
end
GameService.tutorialEvent = tutorialEvent

local function changed(player: Player, render: boolean?)
	if render then
		services.FarmService.render(player)
	end
	services.StateService.markDirty(player)
end

-- Validators -----------------------------------------------------------------------------

local function isId(v: any): boolean
	return type(v) == "string" and #v > 0 and #v <= 12 and string.match(v, "^%d+$") ~= nil
end

local function isInteger(v: any, lo: number, hi: number): boolean
	return type(v) == "number" and v == v and v == math.floor(v) and v >= lo and v <= hi
end

local function requireFarm(player: Player, session: any): (number?, string?)
	local farm = services.FarmService.farmOf(player)
	if not farm then
		return nil, "You don't have a farm on this server."
	end
	local root = rootOf(player)
	if not root or not services.FarmService.inOwnFarm(player, root.Position) then
		return nil, "Go to Your Farm first."
	end
	local _ = session
	return farm, nil
end

-- Collect and Sell are shared by the touch pads and the client's prompts. Both paths are
-- range-checked here; a touch event alone proves nothing (clients control their parts).
function GameService.collect(player: Player, source: string): Result
	local session = services.DataService.getSession(player)
	local farm = services.FarmService.farmOf(player)
	if not session or not farm then
		return fail("Your farm isn't ready yet.")
	end
	local box = Layout.boxWorld(farm)
	if distanceTo(player, box) > GameConfig.CollectRange then
		return fail("Walk up to your Orb Box to Collect.")
	end
	local _ = source
	local ok, result = Actions.collect(session.profile, now())
	if not ok then
		return fail(result)
	end
	effectAll("Collected", { farm = farm, orbs = result.orbs, userId = player.UserId })
	tutorialEvent(player, session, "collect")
	changed(player)
	return { ok = true, data = result }
end

function GameService.sell(player: Player, source: string): Result
	local session = services.DataService.getSession(player)
	if not session then
		return fail("Your farm isn't ready yet.")
	end
	if distanceTo(player, Layout.SellStand) > GameConfig.SellRange then
		return fail("Bring your orbs to the Sell Stand in the plaza.")
	end
	local _ = source
	local ok, result = Actions.sell(session.profile)
	if not ok then
		return fail(result)
	end
	effectAll("Sold", { userId = player.UserId, cash = result.cash, orbs = result.orbs })
	tutorialEvent(player, session, "sell")
	changed(player)
	return { ok = true, data = result }
end

local handlers: { [string]: (Player, any, any) -> Result } = {}

handlers.Collect = function(player, _session, _payload)
	return GameService.collect(player, "prompt")
end

handlers.Sell = function(player, _session, _payload)
	return GameService.sell(player, "prompt")
end

handlers.BuyCrate = function(player, session, payload)
	if type(payload.tier) ~= "string" or not Crates.get(payload.tier) then
		return fail("Unknown crate.")
	end
	if distanceTo(player, Layout.CrateShop) > GameConfig.ShopRange then
		return fail("Visit the Crate Shop to Buy crates.")
	end
	local ok, result = Actions.buyCrate(session.profile, payload.tier)
	if not ok then
		return fail(result)
	end
	effectAll("Bought", { userId = player.UserId, tier = result.tier })
	tutorialEvent(player, session, "buyCrate")
	changed(player)
	return { ok = true, data = result }
end

handlers.PlaceCrate = function(player, session, payload)
	if not isId(payload.cid) or not isInteger(payload.pad, 1, GameConfig.PadCount) then
		return fail("Invalid placement.")
	end
	local farm, why = requireFarm(player, session)
	if not farm then
		return fail(why :: string)
	end
	local ok, result = Actions.placeCrate(session.profile, payload.cid, payload.pad, now())
	if not ok then
		return fail(result)
	end
	effectAll("CratePlaced", { farm = farm, pad = payload.pad })
	tutorialEvent(player, session, "placeCrate")
	changed(player, true)
	return { ok = true, data = result }
end

handlers.PickUpCrate = function(player, session, payload)
	if not isInteger(payload.pad, 1, GameConfig.PadCount) then
		return fail("Invalid Crate Pad.")
	end
	local farm, why = requireFarm(player, session)
	if not farm then
		return fail(why :: string)
	end
	local ok, result = Actions.pickUpCrate(session.profile, payload.pad, now())
	if not ok then
		return fail(result)
	end
	changed(player, true)
	return { ok = true, data = result }
end

handlers.OpenCrate = function(player, session, payload)
	if not isInteger(payload.pad, 1, GameConfig.PadCount) then
		return fail("Invalid Crate Pad.")
	end
	local farm, why = requireFarm(player, session)
	if not farm then
		return fail(why :: string)
	end
	local ok, result = Actions.openCrate(session.profile, payload.pad, rng, now())
	if not ok then
		return fail(result)
	end
	effectAll("CrateOpened", {
		farm = farm,
		pad = payload.pad,
		tier = result.tier,
		id = result.id,
		rarity = result.rarity,
		userId = player.UserId,
	})
	if Rarities.rank(result.rarity) >= 4 then
		local def = Sorcerers.get(result.id)
		for _, other in Players:GetPlayers() do
			if other ~= player then
				notify(other, "Toast", {
					text = string.format(
						"%s opened a %s Sorcerer: %s!",
						player.DisplayName,
						result.rarity,
						if def then def.name else "?"
					),
					tone = "rare",
				})
			end
		end
	end
	tutorialEvent(player, session, "openCrate")
	changed(player, true)
	return { ok = true, data = result }
end

handlers.PlaceSorcerer = function(player, session, payload)
	if not isId(payload.uid) or not isInteger(payload.slot, 1, GameConfig.SlotCount) then
		return fail("Invalid placement.")
	end
	local farm, why = requireFarm(player, session)
	if not farm then
		return fail(why :: string)
	end
	local ok, result = Actions.placeSorcerer(session.profile, payload.uid, payload.slot, now())
	if not ok then
		return fail(result)
	end
	if not result.unchanged then
		effectAll("Placed", { farm = farm, slot = payload.slot })
		tutorialEvent(player, session, "placeSorcerer")
	end
	changed(player, true)
	return { ok = true, data = result }
end

handlers.PickUpSorcerer = function(player, session, payload)
	if not isInteger(payload.slot, 1, GameConfig.SlotCount) then
		return fail("Invalid slot.")
	end
	local farm, why = requireFarm(player, session)
	if not farm then
		return fail(why :: string)
	end
	local ok, result = Actions.pickUpSorcerer(session.profile, payload.slot, now())
	if not ok then
		return fail(result)
	end
	changed(player, true)
	return { ok = true, data = result }
end

handlers.UpgradeSorcerer = function(player, session, payload)
	if not isId(payload.uid) then
		return fail("Invalid Sorcerer.")
	end
	local ok, result = Actions.upgradeSorcerer(session.profile, payload.uid, now())
	if not ok then
		return fail(result)
	end
	local slot = Actions.slotOf(session.profile, payload.uid)
	local farm = services.FarmService.farmOf(player)
	if slot and farm then
		effectAll("Upgraded", { farm = farm, slot = slot })
	end
	changed(player, true)
	return { ok = true, data = result }
end

handlers.SellSorcerer = function(player, session, payload)
	if not isId(payload.uid) then
		return fail("Invalid Sorcerer.")
	end
	local ok, result = Actions.sellSorcerer(session.profile, payload.uid, now())
	if not ok then
		return fail(result)
	end
	changed(player, true)
	return { ok = true, data = result }
end

handlers.BuyUpgrade = function(player, session, payload)
	if type(payload.id) ~= "string" or not Upgrades.get(payload.id) then
		return fail("Unknown upgrade.")
	end
	if distanceTo(player, Layout.UpgradeShop) > GameConfig.ShopRange then
		return fail("Visit the Upgrade Shop to buy upgrades.")
	end
	local ok, result = Actions.buyUpgrade(session.profile, payload.id, now())
	if not ok then
		return fail(result)
	end
	if payload.id == "walkSpeed" then
		services.FarmService.applyWalkSpeed(player)
	end
	tutorialEvent(player, session, "upgrade")
	changed(player, true)
	return { ok = true, data = result }
end

handlers.GoHome = function(player, _session, _payload)
	services.FarmService.spawnAtFarm(player)
	return { ok = true }
end

handlers.SkipTutorial = function(player, session, _payload)
	Tutorial.skip(session.profile)
	changed(player)
	return { ok = true }
end

handlers.Settings = function(player, session, payload)
	for key, value in payload do
		if session.profile.settings[key] ~= nil and type(value) == "boolean" then
			session.profile.settings[key] = value
		end
	end
	changed(player)
	return { ok = true }
end

handlers.GetState = function(player, _session, _payload)
	services.StateService.pushNow(player)
	return { ok = true }
end

local function onRequest(player: Player, action: any, payload: any): Result
	if type(action) ~= "string" or handlers[action] == nil then
		return fail("Unknown action.")
	end
	if payload == nil then
		payload = {}
	elseif type(payload) ~= "table" then
		return fail("Malformed request.")
	end
	if not requestLimiter:allow(player, os.clock()) then
		return fail("Slow down a little!")
	end
	local session = services.DataService.getSession(player)
	if not session then
		if services.DataService.isPaused(player) then
			return fail("Saving is delayed, so changes are paused for a moment.")
		end
		return fail("Your farm is still loading...")
	end
	local ok, result = pcall(handlers[action], player, session, payload)
	if not ok then
		warn("[JJK Farm] Request", action, "failed:", result)
		return fail("Something went wrong. Please try again.")
	end
	return result
end

-- Touch pads: stepping onto your Collect Pad or the Sell Stand's pad does the action.
local function playerFromHit(hit: BasePart): Player?
	local model = hit:FindFirstAncestorOfClass("Model")
	return if model then Players:GetPlayerFromCharacter(model) else nil
end

local function connectTouchPads()
	local map = workspace:FindFirstChild("JJKFarmMap")
	if not map then
		return
	end
	for _, part in map:GetDescendants() do
		local kind = part:GetAttribute("TouchAction")
		if part:IsA("BasePart") and kind then
			part.Touched:Connect(function(hit)
				local player = playerFromHit(hit)
				if not player or not touchLimiter:allow(player, os.clock()) then
					return
				end
				if kind == "Sell" then
					local session = services.DataService.getSession(player)
					if session and session.profile.carried.orbs >= 1 then
						GameService.sell(player, "touch")
					end
				elseif kind == "Collect" then
					local farmIndex = part:GetAttribute("Farm")
					if farmIndex == services.FarmService.farmOf(player) then
						local result = GameService.collect(player, "touch")
						local _ = result
					end
				end
			end)
		end
	end
end

function GameService.init(registry: any)
	services = registry
end

function GameService.start()
	services.Remotes.Request.OnServerInvoke = onRequest
	connectTouchPads()

	services.DataService.Loaded:Connect(function(player: Player, session: any)
		local farm = services.FarmService.assign(player)
		if not farm then
			notify(
				player,
				"Toast",
				{ text = "Every farm on this server is taken. Try another server!", tone = "bad" }
			)
		end
		services.FarmService.render(player)
		services.StateService.pushNow(player)
		services.FarmService.spawnAtFarm(player)
		if not services.DataService.persistent then
			notify(player, "StudioMode", {})
		end
		local report = session.offline
		if report and report.seconds >= 60 and (report.orbs >= 1 or report.cratesReady > 0) then
			local parts = {}
			if report.orbs >= 1 then
				table.insert(
					parts,
					string.format(
						"your Sorcerers made %s Cursed Orbs (%s)",
						Format.commas(report.orbs),
						Format.cash(report.value)
					)
				)
			end
			if report.cratesReady > 0 then
				table.insert(
					parts,
					string.format(
						"%d Crate%s finished opening",
						report.cratesReady,
						if report.cratesReady == 1 then "" else "s"
					)
				)
			end
			notify(player, "Offline", {
				seconds = report.seconds,
				counted = report.counted,
				capped = report.capped,
				boxFull = report.boxFull,
				orbs = math.floor(report.orbs),
				value = report.value,
				cratesReady = report.cratesReady,
				text = string.format(
					"While you were away (%s), %s.",
					Format.duration(report.seconds),
					table.concat(parts, " and ")
				),
			})
		end
	end)

	services.DataService.Removing:Connect(function(player: Player)
		services.FarmService.release(player)
		requestLimiter:remove(player)
		touchLimiter:remove(player)
	end)
end

return GameService
