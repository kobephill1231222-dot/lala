--!strict
-- Replicates each player's profile to their own client (throttled), and mirrors a few
-- public numbers onto the Player for the leaderboard and other players' UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Util.Format)
local ProfileSchema = require(Shared.Rules.ProfileSchema)

local StateService = {}

local FLUSH_INTERVAL = 0.12

local services: any
local dirty: { [Player]: boolean } = {}

local function findOrCreate(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

local function ensureLeaderstats(player: Player): StringValue
	local stats = findOrCreate(player, "Folder", "leaderstats")
	return findOrCreate(stats, "StringValue", "Cash") :: StringValue
end

local function send(player: Player)
	local session = services.DataService.peekSession(player)
	if not session then
		return
	end
	local profile = session.profile
	local view = ProfileSchema.publicView(profile)
	view.serverTime = workspace:GetServerTimeNow()
	view.farm = services.FarmService.farmOf(player)
	view.persistent = services.DataService.persistent
	services.Remotes.State:FireClient(player, view)

	local _, income = Economy.totals(profile)
	player:SetAttribute("Cash", profile.cash)
	player:SetAttribute("Income", income)
	ensureLeaderstats(player).Value = Format.cash(profile.cash)

	services.FarmService.sync(player)
end

function StateService.markDirty(player: Player)
	dirty[player] = true
end

function StateService.pushNow(player: Player)
	dirty[player] = nil
	send(player)
end

function StateService.init(registry: any)
	services = registry
end

function StateService.start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < FLUSH_INTERVAL then
			return
		end
		elapsed = 0
		for player in dirty do
			dirty[player] = nil
			if player.Parent then
				send(player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
	end)
end

return StateService
