--!nonstrict
-- Every Sorcerer you own. Pick one to see its stats and Place, Pick Up, Upgrade or Sell it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.FarmLayout)
local Rarities = require(Shared.Config.Rarities)
local Sorcerers = require(Shared.Config.Sorcerers)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Util.Format)

local UIKit = require(script.Parent.Parent.UIKit)
local Theme = require(script.Parent.Parent.Theme)

local SorcerersPanel = {}

local new = UIKit.new

function SorcerersPanel.create(registry: any)
	local state = registry.StateController
	local ui = registry.UIController
	local root, content, scale = UIKit.panel("Sorcerers", Vector2.new(860, 560), function()
		ui.close()
	end)
	local countLabel = UIKit.text({
		Parent = root,
		Position = UDim2.new(1, -330, 0, 14),
		Size = UDim2.fromOffset(260, 28),
		Text = "",
		TextColor3 = Theme.TextDim,
		FontFace = Theme.BodyBold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	-- Left: grid of cards
	local grid = new("ScrollingFrame", {
		Name = "Grid",
		Parent = content,
		Size = UDim2.new(0, 470, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.StrokeSoft,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		new("UIGridLayout", {
			CellSize = UDim2.fromOffset(146, 92),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		UIKit.padding(4),
	})
	local empty = UIKit.text({
		Parent = content,
		Size = UDim2.new(0, 470, 0, 120),
		Text = "No Sorcerers yet.\nPlace a Crate on a Crate Pad at Your Farm and Open it.",
		TextColor3 = Theme.TextDim,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	})

	-- Right: details
	local detail = new("Frame", {
		Name = "Detail",
		Parent = content,
		Position = UDim2.new(0, 486, 0, 0),
		Size = UDim2.new(1, -486, 1, 0),
		BackgroundColor3 = Theme.PanelLight,
		UIKit.corner(14),
	})
	local portraitHolder = new("Frame", {
		Parent = detail,
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 0, 170),
		BackgroundTransparency = 1,
	})
	local nameLabel = UIKit.text({
		Parent = detail,
		Position = UDim2.fromOffset(14, 172),
		Size = UDim2.new(1, -28, 0, 34),
		Text = "",
		FontFace = Theme.TitleBold,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local badgeHolder = new("Frame", {
		Parent = detail,
		Position = UDim2.fromOffset(0, 208),
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		UIKit.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center),
	})
	local statsLabel = UIKit.text({
		Name = "Stats",
		Parent = detail,
		Position = UDim2.fromOffset(18, 238),
		Size = UDim2.new(1, -36, 0, 120),
		Text = "",
		TextSize = 16,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local actions = new("Frame", {
		Parent = detail,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -12),
		Size = UDim2.new(1, -28, 0, 100),
		BackgroundTransparency = 1,
		new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -5, 0, 46),
			CellPadding = UDim2.fromOffset(10, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local selected: string? = nil

	local placeButton = UIKit.button({
		parent = actions,
		text = "Place",
		style = "gold",
		layoutOrder = 1,
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
	local upgradeButton = UIKit.button({
		parent = actions,
		text = "Upgrade",
		style = "cash",
		layoutOrder = 2,
		onClick = function()
			if selected then
				local result = state.request("UpgradeSorcerer", { uid = selected })
				if result.ok then
					registry.SoundController.play("upgrade")
				end
			end
		end,
	})
	local sellButton = UIKit.button({
		parent = actions,
		text = "Sell",
		style = "red",
		layoutOrder = 3,
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
	local slotButton = UIKit.button({
		parent = actions,
		text = "Go to Your Farm",
		style = "secondary",
		layoutOrder = 4,
		onClick = function()
			ui.close(true)
			ui.goHome()
		end,
	})

	local portraitFor: string? = nil
	local function showDetail()
		local profile = state.profile
		local unit = profile and selected and profile.units[selected]
		local def = unit and Sorcerers.get(unit.id)
		detail.Visible = def ~= nil
		if not def then
			return
		end
		local rarity = Rarities.get(def.rarity)
		if portraitFor ~= def.id then
			portraitFor = def.id
			portraitHolder:ClearAllChildren()
			local viewport = UIKit.viewport(def.id, UDim2.fromOffset(170, 170), { spin = true })
			viewport.AnchorPoint = Vector2.new(0.5, 0)
			viewport.Position = UDim2.fromScale(0.5, 0)
			viewport.Parent = portraitHolder
		end
		nameLabel.Text = def.name
		nameLabel.TextColor3 = if rarity then rarity.glow else Theme.Text
		badgeHolder:ClearAllChildren()
		UIKit.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center).Parent = badgeHolder
		UIKit.rarityBadge(def.rarity, 24).Parent = badgeHolder
		local maxLevel = Economy.maxLevel(unit)
		local slot = state.slotOf(selected :: string)
		local hex = function(c: Color3)
			return string.format("#%02x%02x%02x", c.R * 255, c.G * 255, c.B * 255)
		end
		statsLabel.Text = string.format(
			"Technique: <font color='%s'><b>%s</b></font>\nLevel <b>%d</b> / %d\nOrb Value: <b>%s</b>\nOrbs per Second: <b>%s</b>\nEarns <font color='#78e678'><b>%s/s</b></font>\n%s",
			hex(def.color),
			def.technique,
			unit.level,
			maxLevel,
			Format.cash(Economy.orbValue(unit, profile)),
			Format.abbreviate(def.ops),
			Format.cash(Economy.income(unit, profile)),
			if slot
				then "<font color='#ffc85a'>Working on slot " .. slot .. "</font>"
				else "<font color='#a8a0bc'>In inventory</font>"
		)
		UIKit.setText(placeButton, if slot then "Pick Up" else "Place")
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
		local list = state.sortedUnits(true)
		countLabel.Text = string.format("%d / %d Sorcerers", #list, GameConfig.InventoryLimit)
		empty.Visible = #list == 0
		if not selected or not profile.units[selected] then
			selected = if list[1] then list[1].uid else nil
		end
		local seen = {}
		for order, entry in list do
			seen[entry.uid] = true
			local def = Sorcerers.get(entry.unit.id)
			local rarity = def and Rarities.get(def.rarity)
			local c = cards[entry.uid]
			if not c then
				local button = new("TextButton", {
					Parent = grid,
					Text = "",
					AutoButtonColor = false,
					BackgroundColor3 = Theme.PanelLight,
					UIKit.corner(12),
				})
				local stroke = UIKit.stroke(if rarity then rarity.color else Theme.StrokeSoft, 2, 0.2)
				stroke.Parent = button
				local icon = UIKit.orbIcon(30, if def then def.color else Theme.Violet)
				icon.Position = UDim2.fromOffset(8, 8)
				icon.Parent = button
				local name = UIKit.text({
					Parent = button,
					Position = UDim2.fromOffset(44, 6),
					Size = UDim2.new(1, -50, 0, 22),
					Text = if def then def.name else "?",
					FontFace = Theme.TitleBold,
					TextSize = 20,
					TextColor3 = if rarity then rarity.glow else Theme.Text,
				})
				local level = UIKit.text({
					Parent = button,
					Position = UDim2.fromOffset(44, 28),
					Size = UDim2.new(1, -50, 0, 16),
					Text = "",
					TextColor3 = Theme.TextDim,
					TextSize = 13,
				})
				local income = UIKit.text({
					Parent = button,
					Position = UDim2.fromOffset(10, 48),
					Size = UDim2.new(1, -20, 0, 18),
					Text = "",
					TextColor3 = Theme.Cash,
					FontFace = Theme.BodyBold,
					TextSize = 14,
				})
				local tag = UIKit.text({
					Parent = button,
					Position = UDim2.fromOffset(10, 68),
					Size = UDim2.new(1, -20, 0, 16),
					Text = "",
					TextSize = 12,
				})
				button.Activated:Connect(function()
					registry.SoundController.play("click")
					selected = entry.uid
					for uid, other in cards do
						other.button.BackgroundColor3 = if uid == selected
							then Theme.PanelLighter
							else Theme.PanelLight
					end
					showDetail()
				end)
				c = { button = button, level = level, income = income, tag = tag, name = name }
				cards[entry.uid] = c
			end
			c.button.LayoutOrder = order
			c.button.BackgroundColor3 = if entry.uid == selected then Theme.PanelLighter else Theme.PanelLight
			c.level.Text = string.format("Lv %d  -  %s", entry.unit.level, if def then def.rarity else "")
			c.income.Text = Format.cash(entry.income) .. "/s"
			c.tag.Text = if entry.slot then "On slot " .. entry.slot else "Not placed"
			c.tag.TextColor3 = if entry.slot then Theme.Gold else Theme.TextFaint
		end
		for uid, c in cards do
			if not seen[uid] then
				c.button:Destroy()
				cards[uid] = nil
			end
		end
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
