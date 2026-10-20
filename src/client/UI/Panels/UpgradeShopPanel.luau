--!nonstrict
-- The Upgrade Shop: farm-wide upgrades (Orb Value, More Slots, Box Size, Opening Speed, More
-- Crate Pads, Luck, Walk Speed). Upgrading works at the shop in the plaza. Pixel window: the
-- upgrades on the left (icon, name), the picked one's level, description, next-level effect
-- and its Upgrade button on the right.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.FarmLayout)
local Upgrades = require(Shared.Config.Upgrades)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Util.Format)
local Palette = require(Shared.Pixel.Palette)
local Icons = require(Shared.Pixel.Art.Icons)

local UIKit = require(script.Parent.Parent.UIKit)

local UpgradeShopPanel = {}

local P = Palette
local fromOffset = UDim2.fromOffset
local NB = UIKit.NBSP
local W, H = 316, 164
local CW = W - 8
local LIST_W = 148
local ROW_H = 16
local DETAIL_X = LIST_W + 4
local DETAIL_W = CW - DETAIL_X
local DETAIL_H = 7 * (ROW_H + 1) - 1

-- Durations keep their parts together when wrapped ("1m 30s").
local function duration(seconds: number): string
	return (string.gsub(Format.duration(seconds), " ", NB))
end

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
			duration(Economy.openingTime("basic", profile)),
			duration(Economy.openingTime("basic", nextProfile))
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
	local root, content, scale = UIKit.panel("Upgrade Shop", Vector2.new(W, H), function()
		ui.close()
	end)

	-- Title bar: walk there (only while away from the shop).
	local goW = UIKit.textWidth("Walk me there") + 8
	local goButton = UIKit.button({
		parent = root,
		text = "Walk me there",
		style = "gold",
		size = fromOffset(goW, 14),
		position = fromOffset(W - 2 - UIKit.Window.CloseSize - 2 - goW, 2),
		onClick = function()
			ui.close(true)
			registry.TutorialController.pointAt(Layout.UpgradeShop - Vector3.new(0, 0, 10), "Upgrade Shop")
		end,
	})
	goButton.ZIndex = 3

	local defs = table.clone(Upgrades.List)
	table.sort(defs, function(a, b)
		return a.order < b.order
	end)
	local selected = defs[1] and defs[1].id
	local rows = {}

	-- Detail (right)
	local detail = UIKit.box(content, DETAIL_X, 0, DETAIL_W, DETAIL_H, "well", "Frame", "Detail")
	local inner = DETAIL_W - 8
	local bigIcon = Instance.new("Frame")
	bigIcon.Name = "BigIcon"
	bigIcon.BackgroundTransparency = 1
	bigIcon.Position = fromOffset(4, 4)
	bigIcon.Size = fromOffset(20, 20)
	bigIcon.ZIndex = UIKit.Z
	bigIcon.Parent = detail
	local nameLabel = UIKit.label(detail, "", 28, 5, { name = "Name", width = DETAIL_W - 32 })
	local levelLabel =
		UIKit.label(detail, "", 28, 15, { name = "Level", color = P.Slate, width = DETAIL_W - 32 })
	local description = UIKit.para(detail, 4, 29, inner, 3, { name = "Description", color = P.Mist })
	local effect = UIKit.para(detail, 4, 57, inner, 2, { name = "Effect", color = P.Amber })
	local upgradeButton = UIKit.button({
		parent = detail,
		text = "Upgrade",
		style = "cash",
		size = fromOffset(inner, 16),
		position = fromOffset(4, DETAIL_H - 20),
		onClick = function()
			local r = rows[selected]
			if not r then
				return
			end
			local def = r.def
			local result = state.request("BuyUpgrade", { id = def.id })
			if result.ok then
				registry.SoundController.play("upgrade")
				registry.EffectsController.upgradeFlash()
				ui.toast(string.format("%s upgraded to level %d!", def.name, result.data.level), "good")
			end
		end,
	})

	-- Footer note (full width, two lines)
	local note = UIKit.para(content, 0, DETAIL_H + 3, CW, 2, { name = "Note", color = P.Mist })

	-- Rows (left)
	local iconFor = ""
	local refresh: () -> ()
	for i, def in defs do
		local y = (i - 1) * (ROW_H + 1)
		local row = UIKit.box(content, 0, y, LIST_W, ROW_H, "row", "TextButton", def.id)
		row.LayoutOrder = i
		local face = Instance.new("Frame")
		face.Name = "Face"
		face.BackgroundTransparency = 1
		face.Size = fromOffset(LIST_W, ROW_H)
		face.ZIndex = UIKit.Z
		face.Parent = row
		local icon = UIKit.sprite(Icons.get(def.id), 1, { name = "Icon" })
		icon.Position = fromOffset(3, 3)
		icon.Parent = face
		local title = UIKit.label(face, def.name, 15, 4, { name = "Title", width = LIST_W - 22 })
		local pip = UIKit.rect(face, LIST_W - 7, 6, 4, 4, P.Leaf, "CanBuy", UIKit.Z)
		pip.Visible = false
		local press = UIKit.pressable(row, LIST_W, ROW_H, "row", face)
		row.Activated:Connect(function()
			registry.SoundController.play("click")
			selected = def.id
			refresh()
		end)
		rows[def.id] = { row = row, title = title, pip = pip, press = press, def = def }
	end

	refresh = function()
		local profile = state.profile
		if not profile then
			return
		end
		local near = ui.near(Layout.UpgradeShop, GameConfig.ShopRange)
		for id, r in rows do
			local level = Economy.upgradeLevel(profile, id)
			local cost = Economy.upgradeCost(id, level)
			r.press.setSelected(id == selected)
			UIKit.setLabel(r.title, r.def.name, if cost then P.White else P.Slate)
			r.pip.Visible = near and cost ~= nil and profile.cash >= cost
		end
		local r = rows[selected]
		if r then
			local def = r.def
			if iconFor ~= def.id then
				iconFor = def.id
				bigIcon:ClearAllChildren()
				UIKit.sprite(Icons.get(def.id), 2, { name = "Icon" }).Parent = bigIcon
			end
			local level = Economy.upgradeLevel(profile, def.id)
			local cost = Economy.upgradeCost(def.id, level)
			UIKit.setLabel(nameLabel, def.name)
			UIKit.setLabel(levelLabel, string.format("Lv %d / %d", level, def.maxLevel))
			description.set(def.description)
			if cost then
				effect.set(effectText(def.id, profile), P.Amber)
				UIKit.setText(
					upgradeButton,
					if near then "Upgrade " .. Format.cash(cost) else Format.cash(cost)
				)
				UIKit.setEnabled(upgradeButton, near and profile.cash >= cost)
			else
				effect.set("Maxed", P.Leaf)
				UIKit.setText(upgradeButton, "Max level")
				UIKit.setEnabled(upgradeButton, false)
			end
		end
		note.set(
			if near
				then string.format("You have %s.", Format.cash(profile.cash))
				else "Walk to the Upgrade Shop in the plaza to Upgrade."
		)
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
		select = function(id: string)
			if rows[id] then
				selected = id
				refresh()
			end
		end,
	}
end

return UpgradeShopPanel
