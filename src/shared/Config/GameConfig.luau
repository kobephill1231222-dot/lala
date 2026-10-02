--!strict
-- General tuning constants.

local GameConfig = {}

GameConfig.GameName = "JJK Farm"
GameConfig.DataStoreName = "JJKFarm_Profiles_v1"
GameConfig.DataVersion = 1

-- Farm
GameConfig.SlotCount = 10
GameConfig.StartingSlots = 3
GameConfig.PadCount = 4
GameConfig.StartingPads = 2
GameConfig.InventoryLimit = 60
GameConfig.CrateLimit = 20

-- Orb Box
GameConfig.BoxBaseCapacity = 60 -- Cursed Orbs
GameConfig.BoxGrowthPerLevel = 1.35
-- Offline production is computed once when you return, for at most this long, and still
-- can't exceed the Orb Box capacity.
GameConfig.MaxOfflineSeconds = 8 * 60 * 60

-- Growth
GameConfig.OrbValuePerLevel = 0.2 -- sorcerer level: +20% Orb Value per level above 1
GameConfig.OrbValuePerUpgrade = 0.1 -- farm upgrade: +10% per level
GameConfig.OpenSpeedPerLevel = 0.06
GameConfig.BaseWalkSpeed = 20
GameConfig.WalkSpeedPerLevel = 2

-- Interaction ranges (studs), checked on the server
GameConfig.CollectRange = 22
GameConfig.SellRange = 26
GameConfig.ShopRange = 40

-- Persistence
GameConfig.AutosaveInterval = 90
GameConfig.SessionLockStaleSeconds = 300
GameConfig.LoadRetries = 5
GameConfig.LoadRetryDelay = 3
GameConfig.SaveRetries = 4

return GameConfig
