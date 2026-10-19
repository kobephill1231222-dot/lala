--!strict
-- Tuning for the training-post prototype (docs/NEXT_STEPS_PROPOSAL.md, Decision C).
-- Decisions taken for this build: rewards collect at the farm (A1), the chest holds about
-- 5 minutes of income and the offline vault 2 hours (B), and techniques are code-driven
-- joint animation (no uploads).

local PrototypeConfig = {}

-- The one Sorcerer on the post. Its look and technique name come from Shared.Config.Sorcerers.
PrototypeConfig.SorcererId = "kai"

-- Review presets. `hitInterval` is seconds between hits and `valuePerHit` is Cash per hit.
-- Normal matches Kai's income in the full game ($2/s). Fast is for checking combos: its hits
-- come quicker than one technique can play, so several hits share one strike.
PrototypeConfig.Presets = {
	Normal = { hitInterval = 2.0, valuePerHit = 4 },
	Fast = { hitInterval = 0.4, valuePerHit = 1 },
} :: { [string]: { hitInterval: number, valuePerHit: number } }
PrototypeConfig.DefaultPreset = "Normal"

-- One strike (anticipation + contact + recovery) needs at least this long. Faster hit rates
-- are grouped into combos so every strike the player sees is one credited payout.
PrototypeConfig.MinBeatSeconds = 1.1

-- Reward Chest storage, in seconds of the Sorcerer's income (Decision B).
PrototypeConfig.ChestStorageSeconds = 5 * 60
-- Offline vault: banks income while you're away, paid once when you return (Decision B).
-- Not used by the prototype place (it has no saving); the rule is unit-tested for the
-- full game.
PrototypeConfig.OfflineVaultSeconds = 2 * 60 * 60
PrototypeConfig.OfflineVaultMaxSeconds = 8 * 60 * 60

-- Server range check for collecting (studs from the chest).
PrototypeConfig.CollectRange = 16

return PrototypeConfig
