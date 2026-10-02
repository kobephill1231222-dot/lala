--!strict
-- Server entry point: builds the world, wires services together and starts them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Services = script.Parent:WaitForChild("Services")

local MapService = require(Services.MapService)
MapService.ensure()

local registry = {
	Remotes = Net.createServer(),
	DataService = require(Services.DataService),
	StateService = require(Services.StateService),
	FarmService = require(Services.FarmService),
	GameService = require(Services.GameService),
}

for _, name in { "StateService", "FarmService", "GameService" } do
	registry[name].init(registry)
end

-- Order matters: everything listening to DataService.Loaded must be connected before
-- DataService starts loading players.
registry.FarmService.start()
registry.StateService.start()
registry.GameService.start()
registry.DataService.start()
