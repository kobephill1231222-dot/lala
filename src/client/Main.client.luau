--!strict
-- Client entry point: creates controllers and panels, then starts them in order.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Controllers = script.Parent:WaitForChild("Controllers")
local Panels = script.Parent:WaitForChild("UI"):WaitForChild("Panels")

local registry: { [string]: any } = {
	Remotes = Net.waitClient(),
}

local order = {
	"StateController",
	"SoundController",
	"UIController",
	"WorldController",
	"EffectsController",
	"RevealController",
	"PlacementController",
	"CombatController",
	"TutorialController",
	"IntroController",
	"NotificationController",
}

for _, name in order do
	registry[name] = (require :: any)(Controllers:WaitForChild(name))
end
for _, name in order do
	registry[name].init(registry)
end

local ui = registry.UIController
ui.register("Summon", require(Panels.SummonPanel).create(registry))
ui.register("Units", require(Panels.UnitsPanel).create(registry))
ui.register("Upgrades", require(Panels.UpgradesPanel).create(registry))
ui.register("Travel", require(Panels.TravelPanel).create(registry))
ui.register("Settings", require(Panels.SettingsPanel).create(registry))

for _, name in order do
	task.spawn(registry[name].start)
end

-- Keep audio settings in sync with the saved profile.
registry.StateController.Changed:Connect(function(profile)
	if profile and profile.settings then
		registry.SoundController.setEnabled(profile.settings.sfx ~= false, profile.settings.music ~= false)
	end
end)
