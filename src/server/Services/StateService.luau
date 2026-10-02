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

local function ensureLeaderstats(player: Player): (StringValue, StringValue)
	local stats = findOrCreate(player, "Folder", "leaderstats")
	local energy = findOrCreate(stats, "StringValue", "Energy") :: StringValue
	local rate = findOrCreate(stats, "StringValue", "Rate") :: StringValue
	return energy, rate
end

local function send(player: Player)
	local session = services.DataService.getSession(player)
	if not session then
		return
	end
	local profile = session.profile
	local view = ProfileSchema.publicView(profile)
	view.serverTime = workspace:GetServerTimeNow()
	view.plot = session.plot
	view.persistent = services.DataService.persistent
	services.Remotes.State:FireClient(player, view)

	local rate = Economy.totalRate(profile)
	player:SetAttribute("Energy", profile.energy)
	player:SetAttribute("Seals", profile.seals)
	player:SetAttribute("Rate", rate)
	local energyStat, rateStat = ensureLeaderstats(player)
	energyStat.Value = Format.abbreviate(profile.energy)
	rateStat.Value = Format.rate(rate)

	services.PlotService.updateWell(player)
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
