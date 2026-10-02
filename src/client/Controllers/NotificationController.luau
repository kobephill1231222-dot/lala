--!nonstrict
-- Turns server notifications into toasts and reward popups.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage:WaitForChild("Shared").Util.Format)

local NotificationController = {}

local registry: any

local function rewardText(reward: any): string
	local parts = {}
	if reward and reward.energy then
		table.insert(parts, "+" .. Format.abbreviate(reward.energy) .. " energy")
	end
	if reward and reward.seals then
		table.insert(parts, "+" .. reward.seals .. " Curse Seals")
	end
	return table.concat(parts, "  ")
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
		elseif kind == "Kill" then
			local text = string.format(
				"%s defeated!  +%s energy",
				payload.name or "Curse",
				Format.abbreviate(payload.energy or 0)
			)
			if (payload.seals or 0) > 0 then
				text ..= string.format("  +%d Seal%s", payload.seals, if payload.seals > 1 then "s" else "")
			end
			ui.toast(text, if (payload.seals or 0) > 0 then "rare" else "good", 2.6)
			registry.SoundController.play("reward")
		elseif kind == "TutorialStep" then
			local reward = rewardText(payload.reward)
			ui.toast(
				"Done: " .. (payload.completed or "") .. (if reward ~= "" then "   " .. reward else ""),
				"good",
				3.5
			)
			registry.SoundController.play("upgrade")
			if payload.nextStep and payload.nextStep > 5 then
				task.delay(1.2, function()
					ui.toast("Tutorial complete! Keep collecting, summoning and upgrading.", "reward", 5)
				end)
			end
		elseif kind == "Offline" then
			ui.toast(payload.text or "Welcome back!", "reward", 6)
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
