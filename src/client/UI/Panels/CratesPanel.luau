--!nonstrict
-- Your Crates: what's on each Crate Pad (with its Opening Time) and what's waiting in your
-- inventory. Place, Open and Pick Up from here or straight from the pads at Your Farm.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crates = require(Shared.Config.Crates)
local GameConfig = require(Shared.Config.GameConfig)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Util.Format)

local UIKit = require(script.Parent.Parent.UIKit)
local Theme = require(script.Parent.Parent.Theme)

local CratesPanel = {}

local new = UIKit.new

function CratesPanel.create(registry: any)
	local state = registry.StateController
	local ui = registry.UIController
	local root, content, scale = UIKit.panel("Crates", Vector2.new(760, 540), function()
		ui.close()
	end)
	local countLabel = UIKit.text({
		Parent = root,
		Position = UDim2.new(1, -300, 0, 14),
		Size = UDim2.fromOffset(230, 28),
		Text = "",
		TextColor3 = Theme.TextDim,
		FontFace = Theme.BodyBold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	UIKit.text({
		Parent = content,
		Size = UDim2.new(1, 0, 0, 24),
		Text = "CRATE PADS",
		FontFace = Theme.Heavy,
		TextSize = 14,
		TextColor3 = Theme.TextDim,
	})
	local padRows = new("Frame", {
		Parent = content,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 4 * 58),
		BackgroundTransparency = 1,
		UIKit.list(Enum.FillDirection.Vertical, 6),
	})
	UIKit.text({
		Parent = content,
		Position = UDim2.fromOffset(0, 26 + 4 * 58 + 8),
		Size = UDim2.new(1, 0, 0, 24),
		Text = "IN YOUR INVENTORY",
		FontFace = Theme.Heavy,
		TextSize = 14,
		TextColor3 = Theme.TextDim,
	})
	local inventory = new("ScrollingFrame", {
		Parent = content,
		Position = UDim2.fromOffset(0, 26 + 4 * 58 + 34),
		Size = UDim2.new(1, 0, 1, -(26 + 4 * 58 + 34)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		UIKit.list(Enum.FillDirection.Vertical, 6),
	})

	local pads: { any } = {}
	for pad = 1, GameConfig.PadCount do
		local row = new("Frame", {
			Parent = padRows,
			LayoutOrder = pad,
			Size = UDim2.new(1, 0, 0, 52),
			BackgroundColor3 = Theme.PanelLight,
			UIKit.corner(12),
		})
		local iconHolder = new("Frame", {
			Parent = row,
			Position = UDim2.fromOffset(10, 8),
			Size = UDim2.fromOffset(36, 36),
			BackgroundTransparency = 1,
		})
		local title = UIKit.text({
			Parent = row,
			Position = UDim2.fromOffset(56, 4),
			Size = UDim2.new(1, -330, 0, 24),
			Text = "",
			FontFace = Theme.BodyBold,
			TextSize = 17,
		})
		local sub = UIKit.text({
			Parent = row,
			Position = UDim2.fromOffset(56, 26),
			Size = UDim2.new(1, -330, 0, 20),
			Text = "",
			TextColor3 = Theme.TextDim,
			TextSize = 14,
		})
		local bar, setBar = UIKit.bar(UDim2.fromOffset(120, 8), Theme.Gold)
		bar.Position = UDim2.new(1, -394, 0, 22)
		bar.Parent = row
		local main = UIKit.button({
			parent = row,
			text = "Open",
			style = "gold",
			size = UDim2.fromOffset(120, 38),
			position = UDim2.new(1, -258, 0.5, -19),
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
			size = UDim2.fromOffset(120, 38),
			position = UDim2.new(1, -130, 0.5, -19),
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
			tier = "",
		}
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
			local cid, crate = state.crateOnPad(pad)
			local tier = if crate then crate.tier else ""
			if entry.tier ~= tier then
				entry.tier = tier
				entry.iconHolder:ClearAllChildren()
				if crate then
					UIKit.crateIcon(crate.tier, 36).Parent = entry.iconHolder
				end
			end
			if pad > unlocked then
				entry.mode = "locked"
				entry.title.Text = "Crate Pad " .. pad .. "  (locked)"
				entry.sub.Text = "Buy More Crate Pads at the Upgrade Shop"
				entry.bar.Visible = false
				UIKit.setText(entry.main, "Upgrade Shop")
				UIKit.setEnabled(entry.main, true)
				entry.pick.Visible = false
			elseif crate then
				local def = Crates.get(crate.tier)
				local remaining = crate.readyAt - now
				local total = Economy.openingTime(crate.tier, profile)
				entry.title.Text = (if def then def.name else "Crate") .. "  -  Pad " .. pad
				entry.bar.Visible = remaining > 0
				entry.setBar(1 - math.clamp(remaining / math.max(total, 1), 0, 1))
				if remaining > 0 then
					entry.mode = "wait"
					entry.sub.Text = "Opening Time: " .. Format.clock(remaining)
					UIKit.setText(entry.main, Format.clock(remaining))
					UIKit.setEnabled(entry.main, false)
				else
					entry.mode = "open"
					entry.sub.Text = "<font color='#ffc85a'>Ready to Open!</font>"
					UIKit.setText(entry.main, "Open")
					UIKit.setEnabled(entry.main, true)
				end
				entry.pick.Visible = true
				local _ = cid
			else
				entry.mode = "place"
				entry.title.Text = "Crate Pad " .. pad .. "  (empty)"
				entry.sub.Text = if unplaced > 0
					then "Place a Crate here to start its Opening Time"
					else "Buy Crates at the Crate Shop"
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
		countLabel.Text = string.format("%d / %d Crates", total, GameConfig.CrateLimit)
		for _, child in inventory:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local groups: { [string]: { string } } = {}
		for _, entry in state.unplacedCrates() do
			groups[entry.tier] = groups[entry.tier] or {}
			table.insert(groups[entry.tier], entry.cid)
		end
		local order = {}
		for tier in groups do
			table.insert(order, tier)
		end
		table.sort(order, function(a, b)
			return (Crates.get(a) :: any).order > (Crates.get(b) :: any).order
		end)
		if #order == 0 then
			new("Frame", {
				Parent = inventory,
				Size = UDim2.new(1, 0, 0, 44),
				BackgroundTransparency = 1,
				UIKit.text({
					Size = UDim2.fromScale(1, 1),
					Text = "No Crates waiting. Buy more at the Crate Shop in the plaza.",
					TextColor3 = Theme.TextDim,
					TextSize = 15,
					TextXAlignment = Enum.TextXAlignment.Center,
				}),
			})
		end
		for i, tier in order do
			local def = Crates.get(tier)
			local cids = groups[tier]
			local row = new("Frame", {
				Parent = inventory,
				LayoutOrder = i,
				Size = UDim2.new(1, -8, 0, 52),
				BackgroundColor3 = Theme.PanelLight,
				UIKit.corner(12),
			})
			local icon = UIKit.crateIcon(tier, 36)
			icon.Position = UDim2.fromOffset(10, 8)
			icon.Parent = row
			UIKit.text({
				Parent = row,
				Position = UDim2.fromOffset(56, 4),
				Size = UDim2.new(1, -220, 0, 24),
				Text = string.format("%s  x%d", if def then def.name else tier, #cids),
				FontFace = Theme.BodyBold,
				TextSize = 17,
			})
			UIKit.text({
				Parent = row,
				Position = UDim2.fromOffset(56, 26),
				Size = UDim2.new(1, -220, 0, 20),
				Text = "Opening Time: " .. Format.duration(Economy.openingTime(tier, profile)),
				TextColor3 = Theme.TextDim,
				TextSize = 14,
			})
			UIKit.button({
				parent = row,
				text = "Place",
				style = "gold",
				size = UDim2.fromOffset(130, 38),
				position = UDim2.new(1, -142, 0.5, -19),
				onClick = function()
					ui.close(true)
					registry.PlacementController.beginCrate(cids[1])
				end,
			})
		end
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
