--!nonstrict
-- Turns server notifications into toasts and reward popups.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Tutorial = require(Shared.Rules.Tutorial)
local Format = require(Shared.Util.Format)

local NotificationController = {}

local registry: any

local function rewardText(reward: any): string
	if reward and reward.cash then
		return "+" .. Format.cash(reward.cash)
	end
	return ""
end

function NotificationController.init(reg: any)
	registry = reg
end

function NotificationController.start()
	local ui = registry.UIController
	registry.StateController.Notified:Connect(function(kind: string, payload: any)
		payload = payload or {}
		if kind == "Toast" then
			ui.toast(payload.text or "", payload.tone)
			if payload.tone == "bad" then
				registry.SoundController.play("error")
			end
		elseif kind == "TutorialStep" then
			local reward = rewardText(payload.reward)
			ui.toast(
				"Done: " .. (payload.completed or "") .. (if reward ~= "" then "   " .. reward else ""),
				"good",
				3.5
			)
			registry.SoundController.play("upgrade")
			if reward ~= "" then
				ui.pulseCash()
			end
			if payload.nextStep and payload.nextStep >= Tutorial.Done then
				task.delay(1.2, function()
					ui.toast(
						"Tutorial complete! Keep opening Crates, placing Sorcerers and upgrading Your Farm.",
						"reward",
						5
					)
				end)
			end
		elseif kind == "Offline" then
			local text = payload.text or "Welcome back!"
			if payload.capped then
				text ..= string.format(
					" (Offline progress counts up to %d hours.)",
					GameConfig.MaxOfflineSeconds // 3600
				)
			elseif payload.boxFull then
				text ..= " Your Orb Box is full - Collect it!"
			end
			ui.toast(text, "reward", 8)
		elseif kind == "StudioMode" then
			ui.toast(
				"Studio test session: DataStores are unavailable, so progress won't be saved.",
				"rare",
				8
			)
		end
	end)
end

return NotificationController
