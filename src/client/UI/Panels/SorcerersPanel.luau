--!nonstrict
-- Every Sorcerer you own. Pick one to see its stats and Place, Pick Up, Upgrade or Sell it.
-- Pixel window: a scrolling list of portraits on the left, the picked Sorcerer on the right.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.FarmLayout)
local Rarities = require(Shared.Config.Rarities)
local Sorcerers = require(Shared.Config.Sorcerers)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Util.Format)
local Palette = require(Shared.Pixel.Palette)
local Icons = require(Shared.Pixel.Art.Icons)

local UIKit = require(script.Parent.Parent.UIKit)

local SorcerersPanel = {}

local P = Palette
local fromOffset = UDim2.fromOffset
local W, H = 316, 164
local CW, CH = W - 8, H - 23
local LIST_W = 140
local ROW_W = LIST_W - 4 -- room for the scroll bar
local ROW_H = 30
local DETAIL_X = LIST_W + 4
local DETAIL_W = CW - DETAIL_X
local INNER = DETAIL_W - 8

local function glowOf(def: any): Color3
	local rarity = def and Rarities.get(def.rarity)
	return if rarity then P.nearest(rarity.glow) else P.White
end

function SorcerersPanel.create(registry: any)
	local state = registry.StateController
	local ui = registry.UIController
	local root, content, scale = UIKit.panel("Sorcerers", Vector2.new(W, H), function()
		ui.close()
	end)

	-- Title bar: back to your farm (only while you're somewhere else).
	local goW = UIKit.textWidth("Go to Your Farm") + 8
	local slotButton = UIKit.button({
		parent = root,
		text = "Go to Your Farm",
		style = "gold",
		size = fromOffset(goW, 14),
		position = fromOffset(W - 2 - UIKit.Window.CloseSize - 2 - goW, 2),
		onClick = function()
			ui.close(true)
			ui.goHome()
		end,
	})
	slotButton.ZIndex = 3

	-- Left: count and list
	local countLabel = UIKit.label(content, "", 0, 0, { name = "Count", color = P.Slate, width = LIST_W })
	local list = UIKit.scroller(content, 0, 10, LIST_W, CH - 10, "List")
	local empty = UIKit.para(content, 0, 12, LIST_W, 7, { name = "Empty", color = P.Mist })

	-- Right: details
	local detail = UIKit.box(content, DETAIL_X, 0, DETAIL_W, CH, "well", "Frame", "Detail")
	local portraitHolder = Instance.new("Frame")
	portraitHolder.Name = "PortraitHolder"
	portraitHolder.BackgroundTransparency = 1
	portraitHolder.Position = fromOffset(4, 4)
	portraitHolder.Size = fromOffset(48, 48)
	portraitHolder.ZIndex = UIKit.Z
	portraitHolder.Parent = detail
	local colX = 56
	local nameLabel = UIKit.label(detail, "", colX, 5, { name = "Name", width = DETAIL_W - colX - 4 })
	local badgeHolder = Instance.new("Frame")
	badgeHolder.Name = "BadgeHolder"
	badgeHolder.BackgroundTransparency = 1
	badgeHolder.Position = fromOffset(colX, 15)
	badgeHolder.Size = fromOffset(DETAIL_W - colX - 4, 12)
	badgeHolder.ZIndex = UIKit.Z
	badgeHolder.Parent = detail
	local levelLabel = UIKit.label(detail, "", colX, 30, { name = "Level", width = DETAIL_W - colX - 4 })
	local techniqueLabel =
		UIKit.label(detail, "", colX, 40, { name = "Technique", width = DETAIL_W - colX - 4 })
	local statusLabel = UIKit.label(detail, "", 4, 55, { name = "Status", width = INNER })
	local stats = {}
	for i, key in { "Orb Value", "Orbs per Second", "Earns" } do
		local y = 65 + (i - 1) * 9
		UIKit.label(detail, key, 4, y, { name = "Key" .. i, color = P.Slate })
		stats[key] = UIKit.label(detail, "", 4, y, {
			name = "Value" .. i,
			width = INNER,
			align = Enum.TextXAlignment.Right,
		})
	end

	local selected: string? = nil

	local upgradeButton = UIKit.button({
		parent = detail,
		text = "Upgrade",
		style = "cash",
		size = fromOffset(INNER, 16),
		position = fromOffset(4, CH - 38),
		onClick = function()
			if selected then
				local result = state.request("UpgradeSorcerer", { uid = selected })
				if result.ok then
					registry.SoundController.play("upgrade")
				end
			end
		end,
	})
	local placeW = 60
	local placeButton = UIKit.button({
		parent = detail,
		text = "Place",
		style = "gold",
		size = fromOffset(placeW, 16),
		position = fromOffset(4, CH - 20),
		onClick = function()
			if not selected then
				return
			end
			local slot = state.slotOf(selected)
			if slot then
				state.request("PickUpSorcerer", { slot = slot })
			else
				local uid = selected
				ui.close(true)
				registry.PlacementController.beginSorcerer(uid)
			end
		end,
	})
	local sellButton = UIKit.button({
		parent = detail,
		text = "Sell",
		style = "red",
		size = fromOffset(INNER - placeW - 2, 16),
		position = fromOffset(4 + placeW + 2, CH - 20),
		onClick = function()
			if selected then
				local result = state.request("SellSorcerer", { uid = selected })
				if result.ok then
					registry.SoundController.play("coin")
					ui.toast("Sold for " .. Format.cash(result.data.value), "cash")
					selected = nil
				end
			end
		end,
	})

	local portraitFor: string? = nil
	local badgeFor: string? = nil
	local function showDetail()
		local profile = state.profile
		local unit = profile and selected and profile.units[selected]
		local def = unit and Sorcerers.get(unit.id)
		detail.Visible = def ~= nil
		if not def then
			return
		end
		if portraitFor ~= def.id then
			portraitFor = def.id
			portraitHolder:ClearAllChildren()
			UIKit.viewport(def.id, fromOffset(48, 48)).Parent = portraitHolder
		end
		UIKit.setLabel(nameLabel, def.name, glowOf(def))
		if badgeFor ~= def.rarity then
			badgeFor = def.rarity
			badgeHolder:ClearAllChildren()
			UIKit.rarityBadge(def.rarity).Parent = badgeHolder
		end
		local maxLevel = Economy.maxLevel(unit)
		local slot = state.slotOf(selected :: string)
		UIKit.setLabel(levelLabel, string.format("Lv %d / %d", unit.level, maxLevel))
		UIKit.setLabel(techniqueLabel, def.technique, P.nearest(def.color))
		if slot then
			UIKit.setLabel(statusLabel, "Working on slot " .. slot, P.Amber)
		else
			UIKit.setLabel(statusLabel, "In inventory", P.Slate)
		end
		UIKit.setLabel(stats["Orb Value"], Format.cash(Economy.orbValue(unit, profile)))
		UIKit.setLabel(stats["Orbs per Second"], Format.abbreviate(def.ops))
		UIKit.setLabel(stats.Earns, Format.cash(Economy.income(unit, profile)) .. "/s", P.Leaf)
		UIKit.setText(placeButton, if slot then "Pick Up" else "Place")
		UIKit.setStyle(placeButton, if slot then "secondary" else "gold")
		local cost = Economy.unitUpgradeCost(unit)
		UIKit.setText(upgradeButton, if cost then "Upgrade " .. Format.cash(cost) else "Max level")
		UIKit.setEnabled(upgradeButton, cost ~= nil and profile.cash >= cost)
		UIKit.setText(sellButton, "Sell " .. Format.cash(Economy.sellValue(unit)))
		local count = 0
		for _ in profile.units do
			count += 1
		end
		UIKit.setEnabled(sellButton, count > 1)
		local farm = state.farm()
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local inFarm = farm ~= nil and root ~= nil and Layout.inFarm(farm, root.Position)
		slotButton.Visible = not inFarm
	end

	local cards: { [string]: any } = {}
	local function rebuild()
		local profile = state.profile
		if not profile then
			return
		end
		local entries = state.sortedUnits(true)
		UIKit.setLabel(countLabel, string.format("%d / %d Sorcerers", #entries, GameConfig.InventoryLimit))
		empty.set(
			if #entries == 0
				then "No Sorcerers yet.\nPlace a Crate on a Crate Pad at Your Farm and Open it."
				else ""
		)
		if not selected or not profile.units[selected] then
			selected = if entries[1] then entries[1].uid else nil
		end
		local seen = {}
		for order, entry in entries do
			seen[entry.uid] = true
			local def = Sorcerers.get(entry.unit.id)
			local c = cards[entry.uid]
			if not c then
				local row = UIKit.box(list, 0, 0, ROW_W, ROW_H, "row", "TextButton", "Card")
				local face = Instance.new("Frame")
				face.Name = "Face"
				face.BackgroundTransparency = 1
				face.Size = fromOffset(ROW_W, ROW_H)
				face.ZIndex = UIKit.Z
				face.Parent = row
				local portrait = UIKit.portrait(entry.unit.id, 1)
				portrait.Position = fromOffset(3, 3)
				portrait.Parent = face
				local name = UIKit.label(face, if def then def.name else "?", 30, 3, {
					name = "Name",
					color = glowOf(def),
				})
				local level = UIKit.label(face, "", 30, 3, {
					name = "Level",
					color = P.Slate,
					width = ROW_W - 33,
					align = Enum.TextXAlignment.Right,
				})
				local income =
					UIKit.label(face, "", 30, 12, { name = "Income", color = P.Leaf, width = ROW_W - 44 })
				if def then
					local gem = UIKit.sprite(Icons.get("rarity_" .. def.rarity), 1, { name = "Gem" })
					gem.Position = fromOffset(ROW_W - 13, 11)
					gem.Parent = face
				end
				local tag = UIKit.label(face, "", 30, 21, { name = "Tag", width = ROW_W - 33 })
				local press = UIKit.pressable(row, ROW_W, ROW_H, "row", face)
				row.Activated:Connect(function()
					registry.SoundController.play("click")
					selected = entry.uid
					for uid, other in cards do
						other.press.setSelected(uid == selected)
					end
					showDetail()
				end)
				c = { row = row, level = level, income = income, tag = tag, name = name, press = press }
				cards[entry.uid] = c
			end
			c.row.LayoutOrder = order
			c.row.Position = fromOffset(0, (order - 1) * (ROW_H + 1))
			c.press.setSelected(entry.uid == selected)
			UIKit.setLabel(c.level, "Lv " .. entry.unit.level)
			UIKit.setLabel(c.income, Format.cash(entry.income) .. "/s")
			if entry.slot then
				UIKit.setLabel(c.tag, "On slot " .. entry.slot, P.Amber)
			else
				UIKit.setLabel(c.tag, "Not placed", P.Slate)
			end
		end
		for uid, c in cards do
			if not seen[uid] then
				c.row:Destroy()
				cards[uid] = nil
			end
		end
		UIKit.setCanvas(list, #entries * (ROW_H + 1))
		showDetail()
	end

	local connection: any = nil
	return {
		root = root,
		scale = scale,
		onOpen = function(args)
			if args and args.uid then
				selected = args.uid
			end
			rebuild()
			connection = state.Changed:Connect(rebuild)
		end,
		onClose = function()
			if connection then
				connection:Disconnect()
				connection = nil
			end
		end,
		select = function(uid: string)
			selected = uid
			rebuild()
		end,
	}
end

return SorcerersPanel
