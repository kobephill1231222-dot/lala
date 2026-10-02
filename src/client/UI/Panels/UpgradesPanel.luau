--!nonstrict
-- Talisman Shop: permanent sanctuary upgrades plus breaking the next spot seal.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Upgrades = require(Shared.Config.Upgrades)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Util.Format)

local UIKit = require(script.Parent.Parent.UIKit)
local Theme = require(script.Parent.Parent.Theme)

local UpgradesPanel = {}

local new = UIKit.new

local function effectText(id: string, level: number, profile: any): string
	if id == "production" then
		return string.format("+%d%% output", math.floor(level * GameConfig.ProductionPerUpgrade * 100 + 0.5))
	elseif id == "capacity" then
		return string.format(
			"%s of output",
			Format.duration(GameConfig.WellBaseSeconds + GameConfig.WellSecondsPerLevel * level)
		)
	elseif id == "combat" then
		return string.format("+%d%% damage", math.floor(level * GameConfig.CombatPerUpgrade * 100 + 0.5))
	elseif id == "luck" then
		local chances = Economy.rarityChances("lantern", level)
		return string.format(
			"Epic+ %s (Lantern)",
			Format.percent((chances.Epic or 0) + (chances.Legendary or 0) + (chances.Mythic or 0))
		)
	end
	local _ = profile
	return ""
end

local function iconFor(id: string): Frame
	local colors = {
		production = Theme.Violet,
		capacity = Color3.fromRGB(110, 170, 255),
		combat = Theme.Seal,
		luck = Theme.Gold,
		seal = Color3.fromRGB(230, 220, 200),
	}
	local color = colors[id] or Theme.Violet
	local icon = new("Frame", {
		Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = color:Lerp(Theme.Panel, 0.6),
		UIKit.corner(12),
		UIKit.stroke(color, 2, 0.1),
	})
	new("Frame", {
		Parent = icon,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.42, 0.42),
		Rotation = 45,
		BackgroundColor3 = color,
		UIKit.corner(3),
	})
	return icon
end

function UpgradesPanel.create(registry: any)
	local state = registry.StateController
	local ui = registry.UIController
	local root, content, scale = UIKit.panel("Talisman Shop", Vector2.new(720, 540), function()
		ui.close()
	end)
	local list = new("ScrollingFrame", {
		Parent = content,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		UIKit.list(Enum.FillDirection.Vertical, 10),
		UIKit.padding(2, 4),
	})

	local rows = {}
	local function row(order: number, id: string, name: string, description: string, onBuy: () -> ())
		local frame = new("Frame", {
			Parent = list,
			LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, 78),
			BackgroundColor3 = Theme.PanelLight,
			UIKit.corner(12),
			UIKit.stroke(Theme.StrokeSoft, 1.5, 0.25),
		})
		local icon = iconFor(id)
		icon.Position = UDim2.fromOffset(12, 13)
		icon.Parent = frame
		UIKit.text({
			Parent = frame,
			Position = UDim2.fromOffset(76, 8),
			Size = UDim2.new(1, -300, 0, 24),
			Text = name,
			FontFace = Theme.TitleBold,
			TextSize = 22,
		})
		local levelLabel = UIKit.text({
			Parent = frame,
			Position = UDim2.fromOffset(76, 8),
			Size = UDim2.new(1, -300, 0, 24),
			Text = "",
			FontFace = Theme.BodyBold,
			TextSize = 14,
			TextColor3 = Theme.TextDim,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		UIKit.text({
			Parent = frame,
			Position = UDim2.fromOffset(76, 32),
			Size = UDim2.new(1, -300, 0, 18),
			Text = description,
			TextColor3 = Theme.TextDim,
			TextSize = 13,
		})
		local effect = UIKit.text({
			Parent = frame,
			Position = UDim2.fromOffset(76, 52),
			Size = UDim2.new(1, -300, 0, 18),
			Text = "",
			FontFace = Theme.BodyBold,
			TextColor3 = Theme.Violet,
			TextSize = 14,
		})
		local buy = UIKit.button({
			parent = frame,
			text = "",
			style = "gold",
			size = UDim2.fromOffset(200, 48),
			position = UDim2.new(1, -212, 0.5, -24),
			onClick = onBuy,
		})
		rows[id] = { level = levelLabel, effect = effect, buy = buy }
	end

	for _, def in Upgrades.List do
		row(def.order, def.id, def.name, def.description, function()
			local result = state.request("Upgrade", { id = def.id })
			if result.ok then
				registry.SoundController.play("upgrade")
				registry.EffectsController.upgradeFlash()
				ui.toast(string.format("%s upgraded to level %d!", def.name, result.data.level), "good", 2)
			end
		end)
	end
	row(10, "seal", "Expand Sanctuary", "Break the seal on your next training spot.", function()
		local result = state.request("UnlockSpot")
		if result.ok then
			registry.SoundController.play("unlock")
			ui.toast(string.format("Spot %d unsealed! Place an ally there.", result.data.spot), "good", 2.5)
		end
	end)

	local function refresh()
		local profile = state.profile
		if not profile then
			return
		end
		for _, def in Upgrades.List do
			local r = rows[def.id]
			local level = profile.upgrades[def.id] or 0
			local cost = Economy.upgradeCost(def.id, level)
			r.level.Text = string.format("Lv %d / %d", level, def.maxLevel)
			r.effect.Text = if cost
				then effectText(def.id, level, profile) .. "  >  " .. effectText(def.id, level + 1, profile)
				else effectText(def.id, level, profile) .. "  (max)"
			UIKit.setText(r.buy, if cost then Format.abbreviate(cost) .. " energy" else "Maxed")
			UIKit.setEnabled(r.buy, cost ~= nil and profile.energy >= cost)
		end
		local r = rows.seal
		local nextSpot = profile.unlockedSpots + 1
		local cost = Economy.spotUnlockCost(nextSpot)
		r.level.Text = string.format("Spots %d / %d", profile.unlockedSpots, GameConfig.SpotCount)
		r.effect.Text = if cost then "Unlocks training spot " .. nextSpot else "Every spot is open"
		UIKit.setText(r.buy, if cost then Format.abbreviate(cost) .. " energy" else "Complete")
		UIKit.setEnabled(r.buy, cost ~= nil and profile.energy >= cost)
	end

	local connection: any = nil
	return {
		root = root,
		scale = scale,
		onOpen = function()
			refresh()
			connection = state.Changed:Connect(refresh)
		end,
		onClose = function()
			if connection then
				connection:Disconnect()
				connection = nil
			end
		end,
	}
end

return UpgradesPanel
