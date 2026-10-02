--!strict
-- Client entry point: creates controllers and panels, then starts them in order.

local Players = game:GetService("Players")
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
	"EffectsController",
	"ProductionController",
	"WorldController",
	"RevealController",
	"PlacementController",
	"TutorialController",
	"NotificationController",
}

for _, name in order do
	registry[name] = (require :: any)(Controllers:WaitForChild(name))
end
for _, name in order do
	registry[name].init(registry)
end

local ui = registry.UIController
ui.register("Sorcerers", require(Panels.SorcerersPanel).create(registry))
ui.register("Crates", require(Panels.CratesPanel).create(registry))
ui.register("CrateShop", require(Panels.CrateShopPanel).create(registry))
ui.register("UpgradeShop", require(Panels.UpgradeShopPanel).create(registry))
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

local _ = Players
