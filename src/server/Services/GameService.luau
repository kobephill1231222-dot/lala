--!strict
-- Handles every client request. Each handler validates its payload, applies the pure rule in
-- Shared/Rules/Actions, then triggers replication, world updates, tutorial progress and effects.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Banners = require(Shared.Config.Banners)
local Layout = require(Shared.Config.MapLayout)
local Rarities = require(Shared.Config.Rarities)
local Upgrades = require(Shared.Config.Upgrades)
local Actions = require(Shared.Rules.Actions)
local Tutorial = require(Shared.Rules.Tutorial)
local Format = require(Shared.Util.Format)
local RateLimiter = require(Shared.Util.RateLimiter)

local GameService = {}

type Result = { ok: boolean, message: string?, data: any? }

local services: any
local requestLimiter = RateLimiter.new(8, 16)
local summonLimiter = RateLimiter.new(1.2, 3)
local rng = Random.new()

-- Anywhere inside your own sanctuary counts (the well also collects on touch).
local COLLECT_RANGE = 45

local function now(): number
	return workspace:GetServerTimeNow()
end

local function fail(message: string): Result
	return { ok = false, message = message }
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
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
	services.StateService.markDirty(player)
	if render then
		services.PlotService.render(player)
	end
end

-- Validators -----------------------------------------------------------------------------

local function isUid(v: any): boolean
	return type(v) == "string" and #v > 0 and #v <= 12 and string.match(v, "^%d+$") ~= nil
end

local function isInteger(v: any, lo: number, hi: number): boolean
	return type(v) == "number" and v == v and v == math.floor(v) and v >= lo and v <= hi
end

-- Collection is shared by the well's touch sensor and the client prompt.
function GameService.collect(player: Player, source: string): Result
	local session = services.DataService.getSession(player)
	if not session or not session.plot then
		return fail("Your sanctuary isn't ready yet.")
	end
	if source ~= "touch" then
		local root = rootOf(player)
		local wellPos = services.PlotService.wellPosition(session.plot)
		if not root or (root.Position - wellPos).Magnitude > COLLECT_RANGE then
			return fail("Walk up to your Spirit Well to collect.")
		end
	end
	local ok, result = Actions.collect(session.profile, now())
	if not ok then
		return fail(result)
	end
	effectAll("Collect", { plot = session.plot, amount = result.amount, userId = player.UserId })
	tutorialEvent(player, session, "collect")
	changed(player)
	return { ok = true, data = result }
end

local handlers: { [string]: (Player, any, any) -> Result } = {}

handlers.Collect = function(player, _session, _payload)
	return GameService.collect(player, "prompt")
end

handlers.Summon = function(player, session, payload)
	if not summonLimiter:allow(player, os.clock()) then
		return fail("The ritual circle needs a moment to recover.")
	end
	local banner = Banners.get(payload.banner)
	if not banner then
		return fail("Unknown ritual.")
	end
	local root = rootOf(player)
	if not root or (root.Position - Layout.CourtyardCenter).Magnitude > Layout.SummonRadius then
		return fail("Rituals can only be performed at the Summoning Courtyard.")
	end
	local ok, result = Actions.summon(session.profile, payload.banner, payload.count, rng, now())
	if not ok then
		return fail(result)
	end
	local best = "Common"
	local bestRank = 0
	for _, unit in result.units do
		local rank = Rarities.rank(unit.rarity)
		if rank > bestRank then
			best, bestRank = unit.rarity, rank
		end
	end
	effectAll("Summon", { userId = player.UserId, rarity = best })
	if bestRank >= 4 then
		for _, other in Players:GetPlayers() do
			if other ~= player then
				notify(other, "Toast", {
					text = string.format("%s summoned a %s unit!", player.DisplayName, best),
					tone = "rare",
				})
			end
		end
	end
	tutorialEvent(player, session, "summon")
	changed(player)
	return { ok = true, data = result }
end

handlers.Place = function(player, session, payload)
	if not isUid(payload.uid) or not isInteger(payload.spot, 1, 10) then
		return fail("Invalid placement.")
	end
	local ok, result = Actions.place(session.profile, payload.uid, payload.spot, now())
	if not ok then
		return fail(result)
	end
	if not result.unchanged then
		effectAll("Place", { plot = session.plot, spot = payload.spot })
		tutorialEvent(player, session, "place")
	end
	changed(player, true)
	return { ok = true, data = result }
end

handlers.Unplace = function(player, session, payload)
	if not isInteger(payload.spot, 1, 10) then
		return fail("Invalid spot.")
	end
	local ok, result = Actions.unplace(session.profile, payload.spot, now())
	if not ok then
		return fail(result)
	end
	changed(player, true)
	return { ok = true, data = result }
end

handlers.Train = function(player, session, payload)
	if not isUid(payload.uid) then
		return fail("Invalid unit.")
	end
	local ok, result = Actions.train(session.profile, payload.uid, now())
	if not ok then
		return fail(result)
	end
	local spot = Actions.spotOf(session.profile, payload.uid)
	if spot then
		effectAll("Train", { plot = session.plot, spot = spot })
	end
	changed(player, true)
	return { ok = true, data = result }
end

handlers.Release = function(player, session, payload)
	if not isUid(payload.uid) then
		return fail("Invalid unit.")
	end
	local ok, result = Actions.release(session.profile, payload.uid, now())
	if not ok then
		return fail(result)
	end
	changed(player, true)
	return { ok = true, data = result }
end

handlers.Upgrade = function(player, session, payload)
	if type(payload.id) ~= "string" or not Upgrades.get(payload.id) then
		return fail("Unknown upgrade.")
	end
	local ok, result = Actions.buyUpgrade(session.profile, payload.id, now())
	if not ok then
		return fail(result)
	end
	tutorialEvent(player, session, "upgrade")
	changed(player)
	return { ok = true, data = result }
end

handlers.UnlockSpot = function(player, session, _payload)
	local ok, result = Actions.unlockSpot(session.profile, now())
	if not ok then
		return fail(result)
	end
	effectAll("Unlock", { plot = session.plot, spot = result.spot })
	changed(player, true)
	return { ok = true, data = result }
end

handlers.Travel = function(player, _session, payload)
	return services.TravelService.travel(player, payload.destination)
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
		return fail("Your sanctuary is still loading...")
	end
	local ok, result = pcall(handlers[action], player, session, payload)
	if not ok then
		warn("[Cursebound] Request", action, "failed:", result)
		return fail("Something went wrong. Please try again.")
	end
	return result
end

function GameService.init(registry: any)
	services = registry
end

function GameService.start()
	services.Remotes.Request.OnServerInvoke = onRequest

	services.DataService.Loaded:Connect(function(player: Player, session: any)
		local plot = services.PlotService.assign(player)
		session.plot = plot
		if not plot then
			notify(
				player,
				"Toast",
				{ text = "All sanctuaries are taken on this server. Try another server!", tone = "bad" }
			)
		end
		services.PlotService.render(player)
		services.StateService.pushNow(player)
		if not services.DataService.persistent then
			notify(player, "StudioMode", {})
		end
		if session.offlineGain >= 1 and session.offlineSeconds > 60 then
			notify(player, "Offline", {
				amount = math.floor(session.offlineGain),
				text = string.format(
					"While you were away (%s), your spirits gathered %s energy into the well.",
					Format.duration(session.offlineSeconds),
					Format.abbreviate(session.offlineGain)
				),
			})
		end
		services.TravelService.onLoaded(player, session)
	end)

	services.DataService.Removing:Connect(function(player: Player)
		services.PlotService.release(player)
		requestLimiter:remove(player)
		summonLimiter:remove(player)
	end)
end

return GameService
