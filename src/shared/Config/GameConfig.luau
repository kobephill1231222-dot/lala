--!strict
-- General tuning constants that don't belong to a specific catalogue.

local GameConfig = {}

GameConfig.GameName = "Cursebound Farm"
GameConfig.DataStoreName = "CurseboundFarm_Profiles_v1"
GameConfig.DataVersion = 1

-- Sanctuary layout
GameConfig.SpotCount = 10
GameConfig.StartingSpots = 2
-- Energy cost to break the seal on each spot (index = spot number).
GameConfig.SpotUnlockCosts = {
	[3] = 120,
	[4] = 500,
	[5] = 1800,
	[6] = 6000,
	[7] = 25000,
	[8] = 90000,
	[9] = 300000,
	[10] = 1000000,
}

GameConfig.InventoryLimit = 50

-- Spirit Well (where placed units deposit energy until collected)
GameConfig.WellMinCapacity = 200
GameConfig.WellBaseSeconds = 240
GameConfig.WellSecondsPerLevel = 120
GameConfig.WellStartingEnergy = 60
GameConfig.MaxOfflineSeconds = 8 * 60 * 60

-- Unit growth
GameConfig.RatePerLevel = 0.25 -- +25% of base rate per level above 1
GameConfig.PowerPerLevel = 0.2
GameConfig.ProductionPerUpgrade = 0.1
GameConfig.CombatPerUpgrade = 0.15
GameConfig.TeamPowerDivisor = 40 -- damage multiplier = 1 + teamPower / divisor

-- Persistence
GameConfig.AutosaveInterval = 90
GameConfig.SessionLockStaleSeconds = 300
GameConfig.LoadRetries = 6
GameConfig.LoadRetryDelay = 4
GameConfig.SaveRetries = 4

-- Travel
GameConfig.TravelCooldown = 2.5

return GameConfig
