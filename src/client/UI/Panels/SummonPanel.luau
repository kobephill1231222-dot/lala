--!nonstrict
-- Ritual selection at the Summoning Courtyard: odds, costs, pity progress, x1 / x3 rituals.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Banners = require(Shared.Config.Banners)
local Layout = require(Shared.Config.MapLayout)
local Rarities = require(Shared.Config.Rarities)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Util.Format)

local UIKit = require(script.Parent.Parent.UIKit)
local Theme = require(script.Parent.Parent.Theme)

local SummonPanel = {}

local new = UIKit.new

local function atCourtyard(): boolean
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and (root.Position - Layout.CourtyardCenter).Magnitude < Layout.SummonRadius - 3
end
SummonPanel.atCourtyard = atCourtyard

function SummonPanel.create(registry: any)
	local state = registry.StateController
	local ui = registry.UIController
	local root, content, scale = UIKit.panel("Summoning Circle", Vector2.new(820, 540), function()
		ui.close()
	end)

	local away = new("Frame", {
		Parent = content,
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundColor3 = Color3.fromRGB(90, 40, 60),
		BackgroundTransparency = 0.2,
		Visible = false,
		UIKit.corner(10),
		UIKit.text({
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -230, 1, 0),
			Text = "Rituals can only be performed at the Summoning Courtyard.",
			FontFace = Theme.BodyBold,
			TextSize = 15,
		}),
	})
	UIKit.button({
		parent = away,
		text = "Travel there",
		style = "gold",
		size = UDim2.fromOffset(190, 36),
		position = UDim2.new(1, -200, 0.5, -18),
		onClick = function()
			ui.close(true)
			registry.WorldController.travel("Courtyard", function()
				ui.open("Summon")
			end)
		end,
	})

	local row = new("Frame", {
		Parent = content,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 1, -36),
		BackgroundTransparency = 1,
		UIKit.list(Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Center),
	})
	local pityLabel = UIKit.text({
		Parent = content,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 28),
		Text = "",
		TextColor3 = Theme.TextDim,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local cards = {}
	for _, banner in Banners.List do
		local card = new("Frame", {
			Parent = row,
			Size = UDim2.fromOffset(245, 410),
			BackgroundColor3 = Theme.PanelLight,
			LayoutOrder = banner.order,
			UIKit.corner(14),
			UIKit.stroke(banner.accent, 2, 0.15),
			UIKit.gradient(Theme.PanelLighter, Theme.Panel, 90),
		})
		-- Ritual sigil
		local sigil = new("Frame", {
			Parent = card,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 14),
			Size = UDim2.fromOffset(70, 70),
			BackgroundTransparency = 1,
			UIKit.round(),
			UIKit.stroke(banner.accent, 3),
		})
		new("Frame", {
			Parent = sigil,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.5, 0.5),
			Rotation = 45,
			BackgroundTransparency = 1,
			UIKit.stroke(banner.accent, 2),
		})
		new("Frame", {
			Parent = sigil,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.2, 0.2),
			Rotation = 45,
			BackgroundColor3 = banner.accent,
		})
		UIKit.text({
			Parent = card,
			Position = UDim2.fromOffset(12, 90),
			Size = UDim2.new(1, -24, 0, 30),
			Text = banner.name,
			FontFace = Theme.TitleBold,
			TextSize = 25,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		UIKit.text({
			Parent = card,
			Position = UDim2.fromOffset(14, 120),
			Size = UDim2.new(1, -28, 0, 36),
			Text = banner.subtitle,
			TextColor3 = Theme.TextDim,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		local odds = new("Frame", {
			Parent = card,
			Position = UDim2.fromOffset(18, 162),
			Size = UDim2.new(1, -36, 0, 130),
			BackgroundTransparency = 1,
			UIKit.list(Enum.FillDirection.Vertical, 2),
		})
		local oddsLabels = {}
		for i, rarity in Rarities.Order do
			local info = Rarities.Info[rarity]
			local line = new(
				"Frame",
				{ Parent = odds, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = i }
			)
			new("Frame", {
				Parent = line,
				Position = UDim2.fromOffset(0, 6),
				Size = UDim2.fromOffset(10, 10),
				BackgroundColor3 = info.color,
				UIKit.round(),
			})
			UIKit.text({
				Parent = line,
				Position = UDim2.fromOffset(18, 0),
				Size = UDim2.new(0.6, 0, 1, 0),
				Text = rarity,
				TextSize = 14,
				TextColor3 = info.glow,
			})
			oddsLabels[rarity] = UIKit.text({
				Parent = line,
				Position = UDim2.new(0.5, 0, 0, 0),
				Size = UDim2.new(0.5, 0, 1, 0),
				Text = "",
				FontFace = Theme.BodyBold,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Right,
			})
		end
		local costRow = new("Frame", {
			Parent = card,
			Position = UDim2.fromOffset(14, 296),
			Size = UDim2.new(1, -28, 0, 30),
			BackgroundTransparency = 1,
		})
		local icon = UIKit.currencyIcon(banner.currency, 24)
		icon.Position = UDim2.fromOffset(40, 3)
		icon.Parent = costRow
		UIKit.text({
			Parent = costRow,
			Position = UDim2.fromOffset(70, 0),
			Size = UDim2.new(1, -70, 1, 0),
			Text = Format.commas(banner.cost) .. " each",
			FontFace = Theme.BodyBold,
			TextSize = 17,
		})
		local style = if banner.currency == "seals"
			then "seal"
			elseif banner.id == "greater" then "primary"
			else "gold"
		local one = UIKit.button({
			parent = card,
			text = "Summon x1",
			style = style,
			size = UDim2.new(1, -28, 0, 40),
			position = UDim2.fromOffset(14, 330),
		})
		local three = UIKit.button({
			parent = card,
			text = "x3",
			style = "secondary",
			size = UDim2.new(1, -28, 0, 30),
			position = UDim2.fromOffset(14, 374),
			textSize = 15,
		})
		local function perform(count: number)
			if not atCourtyard() then
				registry.UIController.toast("Head to the Summoning Courtyard to perform rituals.", "bad")
				return
			end
			registry.SoundController.play("summonCharge")
			local result = state.request("Summon", { banner = banner.id, count = count })
			if result.ok then
				ui.close(true)
				registry.RevealController.play(result.data, function()
					SummonPanel.lastBanner = banner.id
					SummonPanel.lastCount = count
				end)
			end
		end
		one.Activated:Connect(function()
			perform(1)
		end)
		three.Activated:Connect(function()
			perform(3)
		end)
		cards[banner.id] = { one = one, three = three, odds = oddsLabels, banner = banner }
	end

	local function refresh()
		local profile = state.profile
		if not profile then
			return
		end
		local here = atCourtyard()
		away.Visible = not here
		row.Position = if here then UDim2.fromOffset(0, 0) else UDim2.fromOffset(0, 56)
		row.Size = if here then UDim2.new(1, 0, 1, -36) else UDim2.new(1, 0, 1, -92)
		for id, card in cards do
			local chances = Economy.rarityChances(id, profile.upgrades.luck or 0)
			for rarity, label in card.odds do
				local c = chances[rarity] or 0
				label.Text = if c > 0 then Format.percent(c) else "-"
				label.TextColor3 = if c > 0 then Theme.Text else Theme.TextFaint
			end
			local balance = if card.banner.currency == "seals" then profile.seals else profile.energy
			UIKit.setEnabled(card.one, here and balance >= card.banner.cost)
			UIKit.setEnabled(card.three, here and balance >= card.banner.cost * 3)
			UIKit.setText(card.three, "x3  (" .. Format.abbreviate(card.banner.cost * 3) .. ")")
		end
		local remaining = Banners.PityThreshold - profile.pity
		pityLabel.Text = string.format(
			"Legendary or better guaranteed within <b>%d</b> rituals  -  Ritual Fortune Lv %d",
			math.max(1, remaining),
			profile.upgrades.luck or 0
		)
	end

	local connection: RBXScriptConnection? = nil
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

return SummonPanel
