--!strict
-- Fast travel between village landmarks, and respawning at the player's own sanctuary.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.MapLayout)

local TravelService = {}

type Result = { ok: boolean, message: string?, data: any? }

local services: any
local spawnCount: { [Player]: number } = {}
local rng = Random.new()

local DESTINATIONS = {
	Home = true,
	Shrine = true,
	Courtyard = true,
	Shop = true,
	Dojo = true,
	Forest = true,
}

local function targetFor(player: Player, destination: string): CFrame?
	if destination == "Home" then
		return services.PlotService.homeCFrame(player)
	end
	return Layout.TravelPoints[destination]
end

local function moveCharacter(character: Model, target: CFrame)
	local jitter = Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
	character:PivotTo(target + jitter)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

function TravelService.travel(player: Player, destination: any): Result
	if type(destination) ~= "string" or not DESTINATIONS[destination] then
		return { ok = false, message = "Unknown destination." }
	end
	local session = services.DataService.getSession(player)
	if not session then
		return { ok = false, message = "Still loading..." }
	end
	local t = os.clock()
	if t - session.lastTravel < GameConfig.TravelCooldown then
		return { ok = false, message = "Catch your breath first." }
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return { ok = false, message = "You can't travel right now." }
	end
	local target = targetFor(player, destination)
	if not target then
		return { ok = false, message = "You don't have a sanctuary on this server." }
	end
	session.lastTravel = t
	moveCharacter(character, target)
	return { ok = true, data = { destination = destination } }
end

function TravelService.onLoaded(_player: Player, _session: any) end

local function onCharacterAdded(player: Player, character: Model)
	spawnCount[player] = (spawnCount[player] or 0) + 1
	-- First spawn uses the arrival plaza (the showcase view); later respawns go home.
	if spawnCount[player] <= 1 then
		return
	end
	task.defer(function()
		local root = character:WaitForChild("HumanoidRootPart", 5)
		local home = services.PlotService.homeCFrame(player)
		if root and home and character.Parent then
			moveCharacter(character, home)
		end
	end)
end

function TravelService.init(registry: any)
	services = registry
end

function TravelService.start()
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			spawnCount[player] = 1
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		spawnCount[player] = nil
	end)
end

return TravelService
