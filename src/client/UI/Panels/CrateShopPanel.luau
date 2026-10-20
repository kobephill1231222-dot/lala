--!nonstrict
-- The Crate Shop: every crate for sale with its price, Opening Time and the chance of each
-- rarity. Buying works at the shop in the plaza; elsewhere this is a catalogue. Pixel window:
-- the crates on the left (icon, name, price), the picked crate's sprite, Opening Time, odds
-- and Buy button on the right.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crates = require(Shared.Config.Crates)
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.FarmLayout)
local Rarities = require(Shared.Config.Rarities)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Util.Format)
local Palette = require(Shared.Pixel.Palette)
local Icons = require(Shared.Pixel.Art.Icons)
local CrateArt = require(Shared.Pixel.Art.Crates)

local UIKit = require(script.Parent.Parent.UIKit)

local CrateShopPanel = {}

local P = Palette
local fromOffset = UDim2.fromOffset
local W, H = 316, 164
local CW, CH = W - 8, H - 23
local LIST_W = 148
local ROW_H = 22
local DETAIL_X = LIST_W + 4
local DETAIL_W = CW - DETAIL_X

function CrateShopPanel.create(registry: any)
	local state = registry.StateController
	local ui = registry.UIController
	local root, content, scale = UIKit.panel("Crate Shop", Vector2.new(W, H), function()
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
			registry.TutorialController.pointAt(Layout.CrateShop + Vector3.new(0, 0, 10), "Crate Shop")
		end,
	})
	goButton.ZIndex = 3

	local sold = {}
	for _, def in Crates.List do
		if def.price > 0 then
			table.insert(sold, def)
		end
	end
	table.sort(sold, function(a, b)
		return a.order < b.order
	end)
	local selected = sold[1] and sold[1].id
	local rows = {}

	-- Detail (right)
	local detail = UIKit.box(content, DETAIL_X, 0, DETAIL_W, CH, "well", "Frame", "Detail")
	local inner = DETAIL_W - 8
	local spriteHolder = Instance.new("Frame")
	spriteHolder.Name = "Crate"
	spriteHolder.BackgroundTransparency = 1
	spriteHolder.Position = fromOffset(4, 4)
	spriteHolder.Size = fromOffset(32, 32)
	spriteHolder.ZIndex = UIKit.Z
	spriteHolder.Parent = detail
	local nameText = UIKit.para(detail, 40, 5, DETAIL_W - 44, 2, { name = "Name" })
	local priceLabel =
		UIKit.label(detail, "", 40, 25, { name = "Price", color = P.Yellow, width = DETAIL_W - 44 })
	UIKit.label(detail, "Opening Time:", 4, 40, { name = "OpeningTitle", color = P.Slate })
	local timeLabel = UIKit.label(detail, "", 4, 49, { name = "OpeningTime", width = inner })
	local odds = {}
	for i, rarity in Rarities.Order do
		local y = 60 + (i - 1) * 10
		local gem = UIKit.sprite(Icons.get("rarity_" .. rarity), 1, { name = "Gem" .. rarity })
		gem.Position = fromOffset(4, y)
		gem.Parent = detail
		local info = Rarities.get(rarity)
		local label = UIKit.label(detail, "", 16, y + 1, {
			name = "Odds" .. rarity,
			color = if info then P.nearest(info.glow) else P.Mist,
			width = inner - 12,
		})
		odds[rarity] = { gem = gem, label = label }
	end
	local buyButton = UIKit.button({
		parent = detail,
		text = "Buy",
		style = "cash",
		size = fromOffset(inner, 16),
		position = fromOffset(4, CH - 20),
		onClick = function()
			local r = rows[selected]
			if not r then
				return
			end
			local def = r.def
			local result = state.request("BuyCrate", { tier = def.id })
			if result.ok then
				registry.SoundController.play("buy")
				registry.EffectsController.boughtCrate(def.id)
				ui.toast(def.name .. " bought! Place it on a Crate Pad at Your Farm.", "good")
			end
		end,
	})

	-- Crate rows (left) and the note under them
	local refresh: () -> ()
	for i, def in sold do
		local row = UIKit.box(content, 0, (i - 1) * (ROW_H + 1), LIST_W, ROW_H, "row", "TextButton", def.id)
		row.LayoutOrder = i
		local face = Instance.new("Frame")
		face.Name = "Face"
		face.BackgroundTransparency = 1
		face.Size = fromOffset(LIST_W, ROW_H)
		face.ZIndex = UIKit.Z
		face.Parent = row
		local icon = UIKit.crateIcon(def.id, 10)
		icon.Position = fromOffset(3, 6)
		icon.Parent = face
		UIKit.label(face, def.name, 15, 3, { name = "Title", width = LIST_W - 18 })
		local price = UIKit.label(
			face,
			Format.cash(def.price),
			15,
			12,
			{ name = "Price", color = P.Yellow, width = LIST_W - 18 }
		)
		local press = UIKit.pressable(row, LIST_W, ROW_H, "row", face)
		row.Activated:Connect(function()
			registry.SoundController.play("click")
			selected = def.id
			refresh()
		end)
		rows[def.id] = { row = row, price = price, press = press, def = def }
	end
	local noteY = #sold * (ROW_H + 1) + 2
	local note = UIKit.para(content, 0, noteY, LIST_W, math.max(1, (CH - noteY) // UIKit.LineHeight), {
		name = "Note",
		color = P.Mist,
	})

	local spriteFor = ""
	refresh = function()
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
		for id, r in rows do
			r.press.setSelected(id == selected)
			UIKit.setLabel(
				r.price,
				Format.cash(r.def.price),
				if profile.cash >= r.def.price then P.Yellow else P.Rose
			)
		end
		local r = rows[selected]
		if r then
			local def = r.def
			if spriteFor ~= def.id then
				spriteFor = def.id
				spriteHolder:ClearAllChildren()
				UIKit.sprite(CrateArt.sprite(def.id), 2, { name = "Sprite" }).Parent = spriteHolder
			end
			nameText.set(def.name, P.nearest(def.color:Lerp(Color3.new(1, 1, 1), 0.35)))
			local affordable = profile.cash >= def.price
			UIKit.setLabel(priceLabel, Format.cash(def.price), if affordable then P.Yellow else P.Rose)
			UIKit.setLabel(timeLabel, Format.duration(Economy.openingTime(def.id, profile)))
			local chances = Economy.crateChances(def.id, Economy.upgradeLevel(profile, "luck"))
			local line = 0
			for _, rarity in Rarities.Order do
				local o = odds[rarity]
				local chance = chances[rarity] or 0
				o.gem.Visible = chance > 0
				o.label.Visible = chance > 0
				if chance > 0 then
					-- Shown rarities stack from the top.
					local y = 60 + line * 10
					o.gem.Position = fromOffset(4, y)
					o.label.Position = fromOffset(16, y + 1)
					UIKit.setLabel(o.label, rarity .. "  " .. Format.percent(chance))
					line += 1
				end
			end
			UIKit.setEnabled(buyButton, near and affordable and not full)
			UIKit.setText(
				buyButton,
				if not near then "Buy at the shop" elseif full then "Crates full" else "Buy"
			)
		end
		note.set(
			if near
				then string.format(
					"You have %s.  Crates: %d / %d",
					Format.cash(profile.cash),
					total,
					GameConfig.CrateLimit
				)
				else "Walk to the Crate Shop in the plaza to Buy. Luck upgrades improve these odds."
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
		select = function(tier: string)
			if rows[tier] then
				selected = tier
				refresh()
			end
		end,
	}
end

return CrateShopPanel
