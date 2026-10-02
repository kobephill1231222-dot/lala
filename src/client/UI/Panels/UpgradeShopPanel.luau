--!nonstrict
-- The Upgrade Shop: farm-wide upgrades (Orb Value, More Slots, Box Size, Opening Speed, More
-- Crate Pads, Luck, Walk Speed). Upgrading works at the shop in the plaza.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.FarmLayout)
local Upgrades = require(Shared.Config.Upgrades)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Util.Format)

local UIKit = require(script.Parent.Parent.UIKit)
local Theme = require(script.Parent.Parent.Theme)

local UpgradeShopPanel = {}

local new = UIKit.new

-- What the upgrade does now -> after the next level.
local function effectText(id: string, profile: any): string
	local level = Economy.upgradeLevel(profile, id)
	local nextProfile = table.clone(profile)
	nextProfile.upgrades = table.clone(profile.upgrades)
	nextProfile.upgrades[id] = level + 1
	if id == "orbValue" then
		return string.format("+%d%% -> +%d%% Orb Value", level * 10, (level + 1) * 10)
	elseif id == "slots" then
		return string.format(
			"%d -> %d production slots",
			Economy.unlockedSlots(profile),
			Economy.unlockedSlots(nextProfile)
		)
	elseif id == "boxSize" then
		return string.format(
			"%s -> %s Cursed Orbs",
			Format.commas(Economy.boxCapacity(profile)),
			Format.commas(Economy.boxCapacity(nextProfile))
		)
	elseif id == "openSpeed" then
		return string.format(
			"Basic Crate: %s -> %s",
			Format.duration(Economy.openingTime("basic", profile)),
			Format.duration(Economy.openingTime("basic", nextProfile))
		)
	elseif id == "pads" then
		return string.format(
			"%d -> %d Crate Pads",
			Economy.unlockedPads(profile),
			Economy.unlockedPads(nextProfile)
		)
	elseif id == "luck" then
		local now = Economy.crateChances("rare", level)
		local after = Economy.crateChances("rare", level + 1)
		return string.format(
			"Rare Crate Epic: %s -> %s",
			Format.percent(now.Epic or 0),
			Format.percent(after.Epic or 0)
		)
	elseif id == "walkSpeed" then
		return string.format(
			"%d -> %d walk speed",
			Economy.walkSpeed(profile),
			Economy.walkSpeed(nextProfile)
		)
	end
	return ""
end

function UpgradeShopPanel.create(registry: any)
	local state = registry.StateController
	local ui = registry.UIController
	local root, content, scale = UIKit.panel("Upgrade Shop", Vector2.new(780, 560), function()
		ui.close()
	end)
	local note = UIKit.text({
		Parent = content,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, -230, 0, 40),
		Text = "",
		TextColor3 = Theme.TextDim,
		TextSize = 15,
	})
	local goButton = UIKit.button({
		parent = content,
		text = "Walk me there",
		style = "secondary",
		size = UDim2.fromOffset(210, 40),
		position = UDim2.new(1, -210, 1, -40),
		onClick = function()
			ui.close(true)
			registry.TutorialController.pointAt(Layout.UpgradeShop - Vector3.new(0, 0, 10), "Upgrade Shop")
		end,
	})
	local list = new("ScrollingFrame", {
		Parent = content,
		Size = UDim2.new(1, 0, 1, -52),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		UIKit.list(Enum.FillDirection.Vertical, 6),
	})
	local rows = {}
	local defs = table.clone(Upgrades.List)
	table.sort(defs, function(a, b)
		return a.order < b.order
	end)
	for i, def in defs do
		local row = new("Frame", {
			Parent = list,
			Name = def.id,
			LayoutOrder = i,
			Size = UDim2.new(1, -8, 0, 58),
			BackgroundColor3 = Theme.PanelLight,
			UIKit.corner(12),
		})
		local title = UIKit.text({
			Parent = row,
			Position = UDim2.fromOffset(14, 4),
			Size = UDim2.new(1, -230, 0, 26),
			Text = def.name,
			FontFace = Theme.BodyBold,
			TextSize = 18,
		})
		local effect = UIKit.text({
			Parent = row,
			Position = UDim2.fromOffset(14, 30),
			Size = UDim2.new(1, -230, 0, 22),
			Text = def.description,
			TextColor3 = Theme.TextDim,
			TextSize = 14,
		})
		local button = UIKit.button({
			parent = row,
			text = "Upgrade",
			style = "cash",
			size = UDim2.fromOffset(190, 42),
			position = UDim2.new(1, -202, 0.5, -21),
			onClick = function()
				local result = state.request("BuyUpgrade", { id = def.id })
				if result.ok then
					registry.SoundController.play("upgrade")
					registry.EffectsController.upgradeFlash()
					ui.toast(string.format("%s upgraded to level %d!", def.name, result.data.level), "good")
				end
			end,
		})
		rows[def.id] = { title = title, effect = effect, button = button, def = def }
	end

	local function refresh()
		local profile = state.profile
		if not profile then
			return
		end
		local near = ui.near(Layout.UpgradeShop, GameConfig.ShopRange)
		for id, r in rows do
			local level = Economy.upgradeLevel(profile, id)
			local cost = Economy.upgradeCost(id, level)
			r.title.Text = string.format(
				"%s  <font color='#a8a0bc'>Lv %d / %d</font>",
				r.def.name,
				level,
				r.def.maxLevel
			)
			if cost then
				r.effect.Text = r.def.description
					.. "   <font color='#ffc85a'>"
					.. effectText(id, profile)
					.. "</font>"
				UIKit.setText(r.button, if near then "Upgrade " .. Format.cash(cost) else Format.cash(cost))
				UIKit.setEnabled(r.button, near and profile.cash >= cost)
			else
				r.effect.Text = r.def.description .. "   <font color='#78e678'>Maxed</font>"
				UIKit.setText(r.button, "Max level")
				UIKit.setEnabled(r.button, false)
			end
		end
		note.Text = if near
			then string.format("You have %s.", Format.cash(profile.cash))
			else "Walk to the Upgrade Shop in the plaza to Upgrade."
		goButton.Visible = not near
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

return UpgradeShopPanel
