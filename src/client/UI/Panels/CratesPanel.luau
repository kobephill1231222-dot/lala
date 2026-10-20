--!nonstrict
-- Your Crates: what's on each Crate Pad (with its Opening Time) and what's waiting in your
-- inventory. Place, Open and Pick Up from here or straight from the pads at Your Farm.
-- Pixel window with two tabs, so each list shows in full: the four Crate Pads, and the Crates
-- waiting in your inventory (its tab shows how many, in yellow while you're on the other).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crates = require(Shared.Config.Crates)
local GameConfig = require(Shared.Config.GameConfig)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Util.Format)
local Palette = require(Shared.Pixel.Palette)

local UIKit = require(script.Parent.Parent.UIKit)

local CratesPanel = {}

local P = Palette
local fromOffset = UDim2.fromOffset
local W, H = 316, 164
local CW, CH = W - 8, H - 23
local TAB_H = 14
local PAGE_Y = TAB_H + 1
local PAGE_H = CH - PAGE_Y
local PAD_H = 30
local PAD_GAP = 2
local INV_W = CW - UIKit.ScrollBarWidth - 1 -- room for the scroll bar
local INV_H = 22
local MAIN_W = 48 -- "Open", "Place" and the timer
local PICK_W = 64
local WIDE_W = UIKit.textWidth("Upgrade Shop") + 8
local BUTTON_Y = PAD_H - 3 - 14 -- bottom-right of the row
local TEXT_X = 29

-- Unselected tab with something waiting in it: yellow text.
UIKit.Styles.tabAlert = { fill = P.Dusk, light = P.Steel, dark = P.Night, edge = P.Ink, text = P.Yellow }

function CratesPanel.create(registry: any)
	local state = registry.StateController
	local ui = registry.UIController
	local root, content, scale = UIKit.panel("Crates", Vector2.new(W, H), function()
		ui.close()
	end)
	local countLabel = UIKit.label(root, "", W - 2 - UIKit.Window.CloseSize - 4 - 120, 5, {
		name = "Count",
		color = P.Mist,
		width = 120,
		align = Enum.TextXAlignment.Right,
		z = 3,
	})

	-- Two pages: the Crate Pads and what's waiting in your inventory, each fully visible.
	local padsPage = Instance.new("Frame")
	padsPage.Name = "Pads"
	padsPage.BackgroundTransparency = 1
	padsPage.Position = fromOffset(0, PAGE_Y)
	padsPage.Size = fromOffset(CW, PAGE_H)
	padsPage.ZIndex = UIKit.Z
	padsPage.Parent = content
	local list = UIKit.scroller(content, 0, PAGE_Y, CW, PAGE_H, "List")
	list.Visible = false

	local page = "pads"
	local tabs: { [string]: any } = {}
	local waiting = 0
	local function paintTabs()
		UIKit.setStyle(tabs.pads, if page == "pads" then "gold" else "secondary")
		UIKit.setStyle(
			tabs.inventory,
			if page == "inventory" then "gold" elseif waiting > 0 then "tabAlert" else "secondary"
		)
	end
	local function show(name: string)
		page = name
		padsPage.Visible = name == "pads"
		list.Visible = name == "inventory"
		paintTabs()
	end
	local padsW = UIKit.textWidth("Crate Pads") + 8
	tabs.pads = UIKit.button({
		parent = content,
		text = "Crate Pads",
		style = "gold",
		size = fromOffset(padsW, TAB_H),
		position = fromOffset(0, 0),
		name = "PadsTab",
		onClick = function()
			show("pads")
		end,
	})
	local invW = UIKit.textWidth("In Your Inventory (20)") + 8
	tabs.inventory = UIKit.button({
		parent = content,
		text = "In Your Inventory",
		style = "secondary",
		size = fromOffset(invW, TAB_H),
		position = fromOffset(padsW + 2, 0),
		name = "InventoryTab",
		onClick = function()
			show("inventory")
		end,
	})

	local pads: { any } = {}
	for pad = 1, GameConfig.PadCount do
		local y = (pad - 1) * (PAD_H + PAD_GAP)
		local row = UIKit.box(padsPage, 0, y, CW, PAD_H, "row", "Frame", "Pad" .. pad)
		-- Pad number chip
		local chip = UIKit.rect(row, 3, 3, 11, 11, P.Ink, "Number", UIKit.Z)
		UIKit.rect(chip, 1, 1, 9, 9, P.Night, "Face", 1)
		UIKit.label(chip, tostring(pad), 2, 2, { name = "Digit", color = P.Mist, noShadow = true, z = 2 })
		local iconHolder = Instance.new("Frame")
		iconHolder.Name = "Icon"
		iconHolder.BackgroundTransparency = 1
		iconHolder.Position = fromOffset(16, 4)
		iconHolder.Size = fromOffset(10, 10)
		iconHolder.ZIndex = UIKit.Z
		iconHolder.Parent = row
		local title = UIKit.label(row, "", TEXT_X, 3, { name = "Title", width = CW - TEXT_X - 3 })
		local sub = UIKit.para(row, TEXT_X, 12, CW - TEXT_X - 3, 2, { name = "Sub", color = P.Mist })
		local barW = CW - 2 - PICK_W - 2 - MAIN_W - 4 - TEXT_X
		local bar, setBar = UIKit.bar(fromOffset(barW, 5), P.Amber)
		bar.Position = fromOffset(TEXT_X, 22)
		bar.Parent = row
		local main = UIKit.button({
			parent = row,
			text = "Open",
			style = "gold",
			size = fromOffset(MAIN_W, 14),
			position = fromOffset(CW - 2 - PICK_W - 2 - MAIN_W, BUTTON_Y),
			onClick = function()
				local entry = pads[pad]
				if entry.mode == "open" then
					registry.WorldController.openCrate(pad)
				elseif entry.mode == "place" then
					ui.close(true)
					registry.PlacementController.beginCrate(nil, pad)
				elseif entry.mode == "locked" then
					ui.open("UpgradeShop")
				end
			end,
		})
		local pick = UIKit.button({
			parent = row,
			text = "Pick Up",
			style = "secondary",
			size = fromOffset(PICK_W, 14),
			position = fromOffset(CW - 2 - PICK_W, BUTTON_Y),
			onClick = function()
				local result = state.request("PickUpCrate", { pad = pad })
				if result.ok then
					registry.SoundController.play("pickUp")
				end
			end,
		})
		pads[pad] = {
			iconHolder = iconHolder,
			title = title,
			sub = sub,
			bar = bar,
			setBar = setBar,
			main = main,
			pick = pick,
			mode = "",
			icon = "",
			mainW = MAIN_W,
			mainRight = false,
		}
	end

	local inventory = Instance.new("Frame")
	inventory.Name = "Inventory"
	inventory.BackgroundTransparency = 1
	inventory.Position = fromOffset(0, 0)
	inventory.Size = fromOffset(INV_W, INV_H)
	inventory.ZIndex = UIKit.Z
	inventory.Parent = list

	-- The main button: "Upgrade Shop" needs more room than the others, and it moves to the
	-- right-hand end when Pick Up isn't shown.
	local function setMain(entry: any, w: number, right: boolean)
		if entry.mainW ~= w or entry.mainRight ~= right then
			entry.mainW, entry.mainRight = w, right
			UIKit.setSize(entry.main, w, 14)
			local x = if right then CW - 2 - w else CW - 2 - PICK_W - 2 - w
			entry.main.Position = fromOffset(x, BUTTON_Y)
		end
	end

	-- Sub text wrapped to the room left of the buttons (two lines).
	local function setSub(entry: any, text: string, color: Color3)
		local left = CW - 2 - entry.mainW - (if entry.mainRight then 0 else PICK_W + 2) - 2
		local chars = math.floor((left - TEXT_X) / 8)
		entry.sub.set(table.concat(UIKit.wrap(text, chars), "\n"), color)
	end

	local function setIcon(entry: any, key: string)
		if entry.icon == key then
			return
		end
		entry.icon = key
		entry.iconHolder:ClearAllChildren()
		if key == "lock" then
			UIKit.icon("lock").Parent = entry.iconHolder
		elseif key ~= "" then
			UIKit.crateIcon(key, 10).Parent = entry.iconHolder
		end
	end

	local function refreshPads()
		local profile = state.profile
		if not profile then
			return
		end
		local now = state.now()
		local unlocked = Economy.unlockedPads(profile)
		local unplaced = #state.unplacedCrates()
		for pad, entry in pads do
			local _, crate = state.crateOnPad(pad)
			if pad > unlocked then
				entry.mode = "locked"
				setIcon(entry, "lock")
				setMain(entry, WIDE_W, true)
				UIKit.setLabel(entry.title, "Crate Pad " .. pad .. " (locked)", P.Slate)
				setSub(entry, "Buy More Crate Pads at the Upgrade Shop", P.Slate)
				entry.bar.Visible = false
				UIKit.setText(entry.main, "Upgrade Shop")
				UIKit.setStyle(entry.main, "secondary")
				UIKit.setEnabled(entry.main, true)
				entry.pick.Visible = false
			elseif crate then
				local def = Crates.get(crate.tier)
				local remaining = crate.readyAt - now
				local total = Economy.openingTime(crate.tier, profile)
				setIcon(entry, crate.tier)
				setMain(entry, MAIN_W, false)
				UIKit.setStyle(entry.main, "gold")
				UIKit.setLabel(entry.title, (if def then def.name else "Crate") .. " - Pad " .. pad, P.White)
				entry.bar.Visible = remaining > 0
				entry.setBar(1 - math.clamp(remaining / math.max(total, 1), 0, 1))
				if remaining > 0 then
					entry.mode = "wait"
					setSub(entry, "Opening Time: " .. Format.clock(remaining), P.Mist)
					UIKit.setText(entry.main, Format.clock(remaining))
					UIKit.setEnabled(entry.main, false)
				else
					entry.mode = "open"
					setSub(entry, "Ready to Open!", P.Yellow)
					UIKit.setText(entry.main, "Open")
					UIKit.setEnabled(entry.main, true)
				end
				entry.pick.Visible = true
			else
				entry.mode = "place"
				setIcon(entry, "")
				setMain(entry, MAIN_W, true)
				UIKit.setStyle(entry.main, "gold")
				UIKit.setLabel(entry.title, "Crate Pad " .. pad .. " (empty)", P.White)
				setSub(
					entry,
					if unplaced > 0
						then "Place a Crate here to start its Opening Time"
						else "Buy Crates at the Crate Shop",
					P.Mist
				)
				entry.bar.Visible = false
				UIKit.setText(entry.main, "Place")
				UIKit.setEnabled(entry.main, unplaced > 0)
				entry.pick.Visible = false
			end
		end
	end

	local function rebuildInventory()
		local profile = state.profile
		if not profile then
			return
		end
		local total = 0
		for _ in profile.crates do
			total += 1
		end
		UIKit.setLabel(countLabel, string.format("%d / %d Crates", total, GameConfig.CrateLimit))
		inventory:ClearAllChildren()
		local groups: { [string]: { string } } = {}
		local unplaced = state.unplacedCrates()
		for _, entry in unplaced do
			groups[entry.tier] = groups[entry.tier] or {}
			table.insert(groups[entry.tier], entry.cid)
		end
		waiting = #unplaced
		UIKit.setText(
			tabs.inventory,
			if waiting > 0 then string.format("In Your Inventory (%d)", waiting) else "In Your Inventory"
		)
		paintTabs()
		local order = {}
		for tier in groups do
			table.insert(order, tier)
		end
		table.sort(order, function(a, b)
			return (Crates.get(a) :: any).order > (Crates.get(b) :: any).order
		end)
		local height = INV_H
		if #order == 0 then
			local para = UIKit.para(inventory, 0, 2, INV_W, 3, { name = "Empty", color = P.Mist })
			para.set("No Crates waiting. Buy more at the Crate Shop in the plaza.")
		end
		for i, tier in order do
			local def = Crates.get(tier)
			local cids = groups[tier]
			local y = (i - 1) * (INV_H + PAD_GAP)
			local row = UIKit.box(inventory, 0, y, INV_W, INV_H, "row", "Frame", tier)
			row.LayoutOrder = i
			local icon = UIKit.crateIcon(tier, 10)
			icon.Position = fromOffset(4, 6)
			icon.Parent = row
			UIKit.label(
				row,
				string.format("%s  x%d", if def then def.name else tier, #cids),
				17,
				3,
				{ name = "Title" }
			)
			UIKit.label(
				row,
				"Opening Time: " .. Format.duration(Economy.openingTime(tier, profile)),
				17,
				12,
				{
					name = "Time",
					color = P.Mist,
				}
			)
			UIKit.button({
				parent = row,
				text = "Place",
				style = "gold",
				size = fromOffset(PICK_W, 14),
				position = fromOffset(INV_W - PICK_W - 2, 4),
				onClick = function()
					ui.close(true)
					registry.PlacementController.beginCrate(cids[1])
				end,
			})
			height = y + INV_H
		end
		inventory.Size = fromOffset(INV_W, height)
		UIKit.setCanvas(list, height)
	end

	local function refreshAll()
		rebuildInventory()
		refreshPads()
	end

	local connections: { any } = {}
	return {
		root = root,
		scale = scale,
		onOpen = function()
			show("pads")
			refreshAll()
			table.insert(connections, state.Changed:Connect(refreshAll))
			local acc = 0
			table.insert(
				connections,
				RunService.Heartbeat:Connect(function(dt)
					acc += dt
					if acc >= 0.25 then
						acc = 0
						refreshPads()
					end
				end)
			)
		end,
		onClose = function()
			for _, c in connections do
				c:Disconnect()
			end
			table.clear(connections)
		end,
	}
end

return CratesPanel
