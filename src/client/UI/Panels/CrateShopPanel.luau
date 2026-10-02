--!nonstrict
-- The Crate Shop: every crate for sale with its price, Opening Time and the chance of each
-- rarity. Buying works at the shop in the plaza; elsewhere this is a catalogue.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crates = require(Shared.Config.Crates)
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.FarmLayout)
local Rarities = require(Shared.Config.Rarities)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Util.Format)

local UIKit = require(script.Parent.Parent.UIKit)
local Theme = require(script.Parent.Parent.Theme)

local CrateShopPanel = {}

local new = UIKit.new

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", c.R * 255, c.G * 255, c.B * 255)
end

function CrateShopPanel.create(registry: any)
	local state = registry.StateController
	local ui = registry.UIController
	local root, content, scale = UIKit.panel("Crate Shop", Vector2.new(860, 560), function()
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
			registry.TutorialController.pointAt(Layout.CrateShop + Vector3.new(0, 0, 10), "Crate Shop")
		end,
	})
	local row = new("Frame", {
		Parent = content,
		Size = UDim2.new(1, 0, 1, -52),
		BackgroundTransparency = 1,
		UIKit.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center),
	})

	local sold = {}
	for _, def in Crates.List do
		if def.price > 0 then
			table.insert(sold, def)
		end
	end
	table.sort(sold, function(a, b)
		return a.order < b.order
	end)

	local cards = {}
	for i, def in sold do
		local cardFrame = new("Frame", {
			Parent = row,
			LayoutOrder = i,
			Size = UDim2.new(0.25, -8, 1, 0),
			BackgroundColor3 = Theme.PanelLight,
			UIKit.corner(14),
			UIKit.stroke(def.color, 2, 0.3),
		})
		local viewport = UIKit.crateViewport(def.id, UDim2.new(1, 0, 0, 130))
		viewport.Parent = cardFrame
		UIKit.text({
			Parent = cardFrame,
			Position = UDim2.fromOffset(8, 128),
			Size = UDim2.new(1, -16, 0, 28),
			Text = def.name,
			FontFace = Theme.TitleBold,
			TextSize = 22,
			TextColor3 = def.color:Lerp(Color3.new(1, 1, 1), 0.35),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local price = UIKit.text({
			Parent = cardFrame,
			Position = UDim2.fromOffset(8, 156),
			Size = UDim2.new(1, -16, 0, 26),
			Text = Format.cash(def.price),
			FontFace = Theme.Heavy,
			TextSize = 22,
			TextColor3 = Theme.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local timeLabel = UIKit.text({
			Parent = cardFrame,
			Position = UDim2.fromOffset(8, 184),
			Size = UDim2.new(1, -16, 0, 20),
			Text = "",
			TextColor3 = Theme.TextDim,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local odds = UIKit.text({
			Name = "Odds",
			Parent = cardFrame,
			Position = UDim2.fromOffset(12, 208),
			Size = UDim2.new(1, -24, 0, 120),
			Text = "",
			TextSize = 14,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		local buy = UIKit.button({
			parent = cardFrame,
			text = "Buy",
			style = "cash",
			size = UDim2.new(1, -20, 0, 44),
			position = UDim2.new(0, 10, 1, -54),
			onClick = function()
				local result = state.request("BuyCrate", { tier = def.id })
				if result.ok then
					registry.SoundController.play("buy")
					registry.EffectsController.boughtCrate(def.id)
					ui.toast(def.name .. " bought! Place it on a Crate Pad at Your Farm.", "good")
				end
			end,
		})
		cards[def.id] = { price = price, time = timeLabel, odds = odds, buy = buy, def = def }
	end

	local function refresh()
		local profile = state.profile
		if not profile then
			return
		end
		local near = ui.near(Layout.CrateShop, GameConfig.ShopRange)
		local total = 0
		for _ in profile.crates do
			total += 1
		end
		local full = total >= GameConfig.CrateLimit
		for _, c in cards do
			local def = c.def
			c.time.Text = "Opening Time: " .. Format.duration(Economy.openingTime(def.id, profile))
			local chances = Economy.crateChances(def.id, Economy.upgradeLevel(profile, "luck"))
			local lines = {}
			for _, rarity in Rarities.Order do
				local chance = chances[rarity] or 0
				if chance > 0 then
					local info = Rarities.get(rarity) :: any
					table.insert(
						lines,
						string.format(
							"<font color='%s'>%s</font>  %s",
							hex(info.color),
							rarity,
							Format.percent(chance)
						)
					)
				end
			end
			c.odds.Text = table.concat(lines, "\n")
			local affordable = profile.cash >= def.price
			c.price.TextColor3 = if affordable then Theme.Gold else Theme.Bad
			UIKit.setEnabled(c.buy, near and affordable and not full)
			UIKit.setText(c.buy, if not near then "Buy at the shop" elseif full then "Crates full" else "Buy")
		end
		note.Text = if near
			then string.format(
				"You have %s.  Crates: %d / %d",
				Format.cash(profile.cash),
				total,
				GameConfig.CrateLimit
			)
			else "Walk to the Crate Shop in the plaza to Buy. Luck upgrades improve these odds."
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

return CrateShopPanel
