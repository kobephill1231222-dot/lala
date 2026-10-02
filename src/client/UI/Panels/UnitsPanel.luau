--!nonstrict
-- Roster and collection index. Select a unit to place/remove it, train it or release it.
-- Opened with { pickSpot = n } from a spot prompt, the main action places straight there.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Characters = require(Shared.Config.Characters)
local GameConfig = require(Shared.Config.GameConfig)
local Rarities = require(Shared.Config.Rarities)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Util.Format)

local UIKit = require(script.Parent.Parent.UIKit)
local Theme = require(script.Parent.Parent.Theme)

local UnitsPanel = {}

local new = UIKit.new

local function sortedUnits(profile: any): { { uid: string, unit: any } }
	local list = {}
	for uid, unit in profile.units do
		if Characters.get(unit.id) then
			table.insert(list, { uid = uid, unit = unit })
		end
	end
	table.sort(list, function(a, b)
		local ra = Rarities.rank((Characters.get(a.unit.id) :: any).rarity)
		local rb = Rarities.rank((Characters.get(b.unit.id) :: any).rarity)
		if ra ~= rb then
			return ra > rb
		end
		local rateA, rateB = Economy.unitBaseRate(a.unit), Economy.unitBaseRate(b.unit)
		if rateA ~= rateB then
			return rateA > rateB
		end
		return (tonumber(a.uid) or 0) < (tonumber(b.uid) or 0)
	end)
	return list
end

function UnitsPanel.create(registry: any)
	local state = registry.StateController
	local ui = registry.UIController
	local root, content, scale = UIKit.panel("Your Allies", Vector2.new(840, 560), function()
		ui.close()
	end)

	local mode = "Roster"
	local selectedUid: string? = nil
	local selectedIndexId: string? = nil
	local pickSpot: number? = nil
	local confirmRelease = false

	-- Tabs
	local tabs = new("Frame", {
		Parent = content,
		Size = UDim2.new(0, 520, 0, 36),
		BackgroundTransparency = 1,
		UIKit.list(Enum.FillDirection.Horizontal, 8),
	})
	local countLabel = UIKit.text({
		Parent = content,
		Position = UDim2.new(0, 280, 0, 0),
		Size = UDim2.new(0, 220, 0, 36),
		Text = "",
		TextColor3 = Theme.TextDim,
		FontFace = Theme.BodyBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local hint = UIKit.text({
		Parent = content,
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(0, 500, 0, 22),
		Text = "",
		TextColor3 = Theme.Gold,
		FontFace = Theme.BodyBold,
		TextSize = 14,
		Visible = false,
	})

	local grid = new("ScrollingFrame", {
		Parent = content,
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(0, 510, 1, -44),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Stroke,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		new("UIGridLayout", {
			CellSize = UDim2.fromOffset(114, 146),
			CellPadding = UDim2.fromOffset(9, 9),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		UIKit.padding(4),
	})

	local detail = new("Frame", {
		Parent = content,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 280, 1, 0),
		BackgroundColor3 = Theme.PanelLight,
		UIKit.corner(14),
		UIKit.stroke(Theme.StrokeSoft, 1.5, 0.2),
	})

	local refresh: () -> ()

	local rosterTab: any, indexTab: any

	local function setTab(name: string)
		mode = name
		confirmRelease = false
		refresh()
		UIKit.setText(rosterTab, if name == "Roster" then "Roster  *" else "Roster")
		UIKit.setText(indexTab, if name == "Index" then "Index  *" else "Index")
	end
	rosterTab = UIKit.button({
		parent = tabs,
		text = "Roster  *",
		style = "primary",
		size = UDim2.fromOffset(120, 34),
		onClick = function()
			setTab("Roster")
		end,
	})
	indexTab = UIKit.button({
		parent = tabs,
		text = "Index",
		style = "secondary",
		size = UDim2.fromOffset(120, 34),
		onClick = function()
			setTab("Index")
		end,
	})

	local function clear(frame: Instance)
		for _, child in frame:GetChildren() do
			if
				not child:IsA("UIGridLayout")
				and not child:IsA("UIPadding")
				and not child:IsA("UICorner")
				and not child:IsA("UIStroke")
			then
				child:Destroy()
			end
		end
	end

	local function card(
		order: number,
		characterId: string,
		top: string,
		bottom: string,
		selected: boolean,
		discovered: boolean,
		badgeText: string?,
		onClick: () -> ()
	)
		local def = Characters.get(characterId) :: any
		local rarity = Rarities.get(def.rarity) :: any
		local button = new("TextButton", {
			Parent = grid,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = order,
			BackgroundColor3 = if selected then Theme.PanelLighter else Theme.PanelLight,
			UIKit.corner(12),
			UIKit.stroke(
				if discovered then rarity.color else Theme.StrokeSoft,
				if selected then 3 else 1.5,
				if selected then 0 else 0.3
			),
		})
		local viewport =
			UIKit.viewport(characterId, UDim2.fromOffset(96, 92), { silhouette = not discovered })
		viewport.Position = UDim2.fromOffset(9, 4)
		viewport.Parent = button
		UIKit.text({
			Parent = button,
			Position = UDim2.fromOffset(6, 96),
			Size = UDim2.new(1, -12, 0, 22),
			Text = if discovered then top else "???",
			FontFace = Theme.BodyBold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = if discovered then rarity.glow else Theme.TextFaint,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
		})
		UIKit.text({
			Parent = button,
			Position = UDim2.fromOffset(6, 118),
			Size = UDim2.new(1, -12, 0, 20),
			Text = bottom,
			TextSize = 13,
			TextColor3 = Theme.TextDim,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		if badgeText then
			new("Frame", {
				Parent = button,
				Position = UDim2.fromOffset(6, 6),
				Size = UDim2.fromOffset(0, 20),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = Color3.fromRGB(40, 110, 70),
				UIKit.corner(10),
				UIKit.padding(0, 6),
				UIKit.text({
					Size = UDim2.new(0, 0, 1, 0),
					AutomaticSize = Enum.AutomaticSize.X,
					Text = badgeText,
					FontFace = Theme.Heavy,
					TextSize = 11,
				}),
			})
		end
		button.Activated:Connect(function()
			registry.SoundController.play("click")
			onClick()
		end)
	end

	local function statLine(
		parent: Instance,
		order: number,
		label: string,
		value: string,
		valueColor: Color3?
	)
		local line = new("Frame", {
			Parent = parent,
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		})
		UIKit.text({
			Parent = line,
			Size = UDim2.new(0.5, 0, 1, 0),
			Text = label,
			TextColor3 = Theme.TextDim,
			TextSize = 14,
		})
		UIKit.text({
			Parent = line,
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.new(0.5, 0, 1, 0),
			Text = value,
			FontFace = Theme.BodyBold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = valueColor or Theme.Text,
		})
	end

	local function showDetail(characterId: string?, uid: string?)
		clear(detail)
		local profile = state.profile
		if not characterId or not profile then
			UIKit.text({
				Parent = detail,
				Position = UDim2.fromOffset(16, 0),
				Size = UDim2.new(1, -32, 1, 0),
				Text = "Select a unit to see its details.",
				TextColor3 = Theme.TextDim,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			return
		end
		local def = Characters.get(characterId) :: any
		local rarity = Rarities.get(def.rarity) :: any
		local discovered = profile.discovered[characterId] == true
		local unit = uid and profile.units[uid]
		local viewport = UIKit.viewport(
			characterId,
			UDim2.fromOffset(180, 170),
			{ spin = discovered, silhouette = not discovered }
		)
		viewport.AnchorPoint = Vector2.new(0.5, 0)
		viewport.Position = UDim2.new(0.5, 0, 0, 4)
		viewport.Parent = detail
		local body = new("Frame", {
			Parent = detail,
			Position = UDim2.fromOffset(14, 172),
			Size = UDim2.new(1, -28, 1, -176),
			BackgroundTransparency = 1,
			UIKit.list(Enum.FillDirection.Vertical, 3, Enum.HorizontalAlignment.Center),
		})
		UIKit.text({
			Parent = body,
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 28),
			Text = if discovered then def.name else "Undiscovered",
			FontFace = Theme.TitleBold,
			TextSize = 25,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = rarity.glow,
		})
		local badge = UIKit.rarityBadge(def.rarity, 20)
		badge.LayoutOrder = 2
		badge.Parent = body
		UIKit.text({
			Parent = body,
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, 18),
			Text = def.title .. "  -  " .. def.kind .. "  -  " .. def.affinity,
			TextColor3 = Theme.TextDim,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local stats = new("Frame", {
			Parent = body,
			LayoutOrder = 4,
			Size = UDim2.new(1, 0, 0, 92),
			BackgroundTransparency = 1,
			UIKit.list(Enum.FillDirection.Vertical, 1),
		})
		local level = if unit then unit.level else 1
		local data = { id = characterId, level = level }
		local maxLevel = Economy.maxLevel(data)
		statLine(stats, 1, "Level", string.format("%d / %d", level, maxLevel))
		statLine(stats, 2, "Output", Format.rate(Economy.unitRate(data, profile)), Theme.Violet)
		statLine(stats, 3, "Power", tostring(Economy.unitPower(data)))
		local spot = uid and state.placedSpot(uid)
		statLine(
			stats,
			4,
			"Status",
			if spot
				then "Training on spot " .. spot
				elseif unit then "Resting"
				else (if discovered then "Not owned" else "?"),
			if spot then Theme.Good else Theme.TextDim
		)

		if not unit then
			UIKit.text({
				Parent = body,
				LayoutOrder = 5,
				Size = UDim2.new(1, 0, 0, 60),
				Text = if discovered then def.description else "Perform rituals to discover this unit.",
				TextColor3 = Theme.TextDim,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			return
		end

		local actions = new("Frame", {
			Parent = body,
			LayoutOrder = 6,
			Size = UDim2.new(1, 0, 0, 140),
			BackgroundTransparency = 1,
			UIKit.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center),
		})
		local unitUid = uid :: string
		if pickSpot then
			UIKit.button({
				parent = actions,
				layoutOrder = 1,
				text = "Place on spot " .. pickSpot,
				style = "gold",
				size = UDim2.new(1, 0, 0, 40),
				onClick = function()
					local result = state.request("Place", { uid = unitUid, spot = pickSpot })
					if result.ok then
						registry.SoundController.play("place")
						ui.close(true)
					end
				end,
			})
		elseif spot then
			UIKit.button({
				parent = actions,
				layoutOrder = 1,
				text = "Remove from spot",
				style = "secondary",
				size = UDim2.new(1, 0, 0, 40),
				onClick = function()
					state.request("Unplace", { spot = spot })
				end,
			})
		else
			UIKit.button({
				parent = actions,
				layoutOrder = 1,
				text = "Place in sanctuary",
				style = "gold",
				size = UDim2.new(1, 0, 0, 40),
				onClick = function()
					ui.close(true)
					registry.PlacementController.begin(unitUid)
				end,
			})
		end
		local trainCost = Economy.trainCost(unit)
		local train = UIKit.button({
			parent = actions,
			layoutOrder = 2,
			text = if trainCost
				then string.format("Train  (%s)", Format.abbreviate(trainCost))
				else "Max level",
			style = "primary",
			size = UDim2.new(1, 0, 0, 40),
			onClick = function()
				local result = state.request("Train", { uid = unitUid })
				if result.ok then
					registry.SoundController.play("upgrade")
					ui.toast(string.format("%s reached level %d!", def.name, result.data.level), "good", 2)
				end
			end,
		})
		UIKit.setEnabled(train, trainCost ~= nil and profile.energy >= trainCost)
		local value = Economy.releaseValue(unit)
		UIKit.button({
			parent = actions,
			layoutOrder = 3,
			text = if confirmRelease
				then string.format("Confirm release (+%s)", Format.abbreviate(value))
				else "Release",
			style = if confirmRelease then "danger" else "secondary",
			size = UDim2.new(1, 0, 0, if confirmRelease then 36 else 30),
			textSize = 14,
			onClick = function()
				if not confirmRelease then
					confirmRelease = true
					showDetail(characterId, uid)
					return
				end
				confirmRelease = false
				local result = state.request("Release", { uid = unitUid })
				if result.ok then
					selectedUid = nil
					ui.toast(
						string.format(
							"%s returned to the spirit world (+%s energy).",
							def.name,
							Format.abbreviate(result.data.value)
						),
						"info"
					)
				end
			end,
		})
	end

	local lastSignature = ""

	-- Grid rebuilds (viewports are costly) only when the roster, selection or mode changed.
	local function signature(profile: any): string
		local parts = { mode, tostring(selectedUid), tostring(selectedIndexId), tostring(pickSpot) }
		for uid, unit in profile.units do
			table.insert(parts, uid .. ":" .. unit.id .. ":" .. unit.level)
		end
		for spot, uid in profile.spots do
			table.insert(parts, "s" .. spot .. "=" .. uid)
		end
		for id in profile.discovered do
			table.insert(parts, "d" .. id)
		end
		table.sort(parts)
		return table.concat(parts, "|")
	end

	refresh = function()
		local profile = state.profile
		if not profile then
			return
		end
		local sig = signature(profile)
		if sig == lastSignature then
			if mode == "Roster" then
				local selected = selectedUid and profile.units[selectedUid]
				showDetail(selected and selected.id, selectedUid)
			end
			return
		end
		lastSignature = sig
		clear(grid)
		hint.Visible = pickSpot ~= nil
		grid.Position = if pickSpot then UDim2.fromOffset(0, 66) else UDim2.fromOffset(0, 44)
		grid.Size = if pickSpot then UDim2.new(0, 510, 1, -66) else UDim2.new(0, 510, 1, -44)
		if pickSpot then
			hint.Text = "Choose an ally to train on spot " .. pickSpot
		end
		if mode == "Roster" then
			local list = sortedUnits(profile)
			countLabel.Text = string.format("%d / %d allies", #list, GameConfig.InventoryLimit)
			if selectedUid and not profile.units[selectedUid] then
				selectedUid = nil
			end
			if not selectedUid and list[1] then
				-- Prefer an unplaced unit when choosing for a spot
				for _, entry in list do
					if not pickSpot or not state.placedSpot(entry.uid) then
						selectedUid = entry.uid
						break
					end
				end
				selectedUid = selectedUid or list[1].uid
			end
			for i, entry in list do
				local def = Characters.get(entry.unit.id) :: any
				local spot = state.placedSpot(entry.uid)
				card(
					i,
					entry.unit.id,
					def.name,
					string.format(
						"Lv %d  -  %s",
						entry.unit.level,
						Format.rate(Economy.unitBaseRate(entry.unit))
					),
					entry.uid == selectedUid,
					true,
					if spot then "SPOT " .. spot else nil,
					function()
						selectedUid = entry.uid
						confirmRelease = false
						refresh()
					end
				)
			end
			local selected = selectedUid and profile.units[selectedUid]
			showDetail(selected and selected.id, selectedUid)
		else
			local discoveredCount = 0
			for i, def in Characters.List do
				local discovered = profile.discovered[def.id] == true
				if discovered then
					discoveredCount += 1
				end
				card(i, def.id, def.name, def.rarity, def.id == selectedIndexId, discovered, nil, function()
					selectedIndexId = def.id
					refresh()
				end)
			end
			countLabel.Text = string.format("%d / %d discovered", discoveredCount, #Characters.List)
			showDetail(selectedIndexId or Characters.List[1].id, nil)
		end
	end

	local connection: any = nil
	return {
		root = root,
		scale = scale,
		onOpen = function(args: any)
			pickSpot = args and args.pickSpot
			if args and args.uid then
				selectedUid = args.uid
				mode = "Roster"
			end
			if pickSpot then
				mode = "Roster"
				selectedUid = nil
			end
			confirmRelease = false
			refresh()
			connection = state.Changed:Connect(function()
				refresh()
			end)
		end,
		onClose = function()
			if connection then
				connection:Disconnect()
				connection = nil
			end
			pickSpot = nil
			lastSignature = ""
			clear(grid)
		end,
	}
end

return UnitsPanel
