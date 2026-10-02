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
	PlotService = require(Services.PlotService),
	GameService = require(Services.GameService),
	TravelService = require(Services.TravelService),
	CombatService = require(Services.CombatService),
}

for _, name in { "StateService", "PlotService", "GameService", "TravelService", "CombatService" } do
	registry[name].init(registry)
end

-- Order matters: everything listening to DataService.Loaded must be connected before
-- DataService starts loading players.
registry.PlotService.start()
registry.StateService.start()
registry.GameService.start()
registry.TravelService.start()
registry.CombatService.start()
registry.DataService.start()
