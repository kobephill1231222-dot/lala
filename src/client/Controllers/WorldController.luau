--!nonstrict
-- The interaction layer of the world, in pixel art. Everything you can do with something in
-- the world is an "interaction": on Your Farm the 4 Crate Pads (Place / Open, Pick Up), the 10
-- production slots (Place / Upgrade, Pick Up) and the Orb Box (Collect); in the plaza the Sell
-- Stand (Sell), each Crate Shop display (Buy, Browse) and the two shops (Browse, Upgrade).
-- One pixel prompt (Pixel/Prompt) shows the nearest interaction in range of your character,
-- by it in the world's front layer (Pixel/Front: above the HUD, and placed clear of the HUD's
-- cards when there's room); E / gamepad X does its action, R / gamepad Y the second one, or tap
-- the prompt. Farm interactions only exist on the owner's client and the server validates every
-- request (ranges here match the server's).
-- Also here: the crates on the Crate Shop displays and their price tags, other players' Orb Box
-- counters, and each farm's stats board (shown by its name sign when you walk past).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crates = require(Shared.Config.Crates)
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Config.FarmLayout)
local WorldMap = require(Shared.Config.WorldMap)
local Sorcerers = require(Shared.Config.Sorcerers)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Util.Format)
local Palette = require(Shared.Pixel.Palette)
local CrateArt = require(Shared.Pixel.Art.Crates)

local Pixel = script.Parent.Parent:WaitForChild("Pixel")
local Screen = require(Pixel.Screen)
local Camera2D = require(Pixel.Camera2D)
local Actor = require(Pixel.Actor)
local Text = require(Pixel.Text)
local Front = require(Pixel.Front)
local Prompt = require(Pixel.Prompt)
local Widgets = require(Pixel.Widgets)

local WorldController = {}

local player = Players.LocalPlayer
local registry: any
local ownFarm: number? = nil

local HINT_CHARS = 24 -- wrap hint lines at this many characters

type Action = {
	action: string,
	enabled: boolean,
	run: () -> (),
}

type Interaction = {
	id: string,
	kind: string, -- "pad" | "slot" | "collect" | "sell" | "buy" | "crateShop" | "upgradeShop"
	index: number?,
	tier: string?,
	position: Vector3, -- where it is (world studs); distance is measured from here
	range: number, -- flat studs
	center: Vector3?, -- the server's range check, when it has one
	centerRange: number?,
	ownFarm: boolean?, -- only inside Your Farm's fence (the server checks that too)
	lift: number, -- art pixels from `position` (or `promptAt`) up to the prompt's tail
	promptAt: Vector3?, -- where the prompt is drawn, when not over `position`
	area: { number }?, -- what the prompt points at, art pixels { x0, y0, x1, y1 }
	object: string,
	hint: string?, -- shown when the main action can't be done
	hintOnly: boolean?, -- the hint says it all (the object is only what would be placed)
	note: string?, -- an extra line under the object
	noteColor: Color3?,
	main: Action,
	secondary: Action?,
}

local list: { Interaction } = {}
local byId: { [string]: Interaction } = {}
local current: Interaction? = nil
local prompt: any = nil
local readyAnnounced: { [string]: boolean } = {}

-- Overlay labels
local shopCrates: { { tier: string, actor: any, tag: Frame, x: number, y: number, id: string } } = {}

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local PPS = Layout.PixelsPerStud

-- A WorldMap rectangle (studs) in art pixels { x0, y0, x1, y1 }.
local function artArea(rect: WorldMap.Rect): { number }
	local x0, y0 = WorldMap.toPixels(rect.x0, rect.z0)
	local x1, y1 = WorldMap.toPixels(rect.x1, rect.z1)
	return { math.floor(x0), math.floor(y0), math.ceil(x1), math.ceil(y1) }
end

-- A square `size` studs wide around a world position, in art pixels.
local function squareArea(position: Vector3, size: number): { number }
	local x, y = Camera2D.toArt(position)
	local half = math.floor(size * PPS / 2)
	return { x - half, y - half, x + half, y + half }
end

local function rootPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.CFrame.Position
	end
	return nil
end

local function add(it: Interaction): Interaction
	if not byId[it.id] then
		table.insert(list, it)
	end
	byId[it.id] = it
	return it
end

local function bestUnplacedSorcerer(): string?
	for _, entry in registry.StateController.sortedUnits(true) do
		if not entry.slot then
			return entry.uid
		end
	end
	return nil
end

-- Actions ------------------------------------------------------------------------------

function WorldController.openCrate(pad: number)
	local state = registry.StateController
	if registry.RevealController.isPlaying() then
		return
	end
	local _, crate = state.crateOnPad(pad)
	local tier = crate and crate.tier
	local result = state.request("OpenCrate", { pad = pad })
	if result.ok then
		result.data.tier = result.data.tier or tier
		registry.RevealController.play(result.data)
	end
end

function WorldController.placeCrateOnPad(pad: number, cid: string?)
	local state = registry.StateController
	local chosen = cid
	if not chosen then
		local unplaced = state.unplacedCrates()
		chosen = if unplaced[1] then unplaced[1].cid else nil
	end
	if not chosen then
		registry.UIController.toast("You have no Crates to place. Buy one at the Crate Shop!", "bad")
		return
	end
	local result = state.request("PlaceCrate", { cid = chosen, pad = pad })
	if result.ok then
		registry.SoundController.play("cratePlace")
	end
	return result
end

function WorldController.placeSorcererOnSlot(slot: number, uid: string?)
	local state = registry.StateController
	local chosen = uid or bestUnplacedSorcerer()
	if not chosen then
		registry.UIController.toast("All your Sorcerers are working. Open Crates to get more!", "info")
		return
	end
	local result = state.request("PlaceSorcerer", { uid = chosen, slot = slot })
	if result.ok then
		registry.SoundController.play("place")
	end
	return result
end

-- Own farm ------------------------------------------------------------------------------

local function setupOwnFarm(index: number)
	if ownFarm == index then
		return
	end
	-- (A new farm index replaces the old farm's interactions.)
	for i = #list, 1, -1 do
		local it = list[i]
		if it.kind == "pad" or it.kind == "slot" or it.kind == "collect" then
			byId[it.id] = nil
			table.remove(list, i)
		end
	end
	ownFarm = index

	for pad = 1, GameConfig.PadCount do
		add({
			id = "pad" .. pad,
			kind = "pad",
			index = pad,
			ownFarm = true,
			position = Layout.padWorld(index, pad).Position,
			area = squareArea(Layout.padWorld(index, pad).Position, Layout.PadSize),
			range = 12,
			lift = 10,
			object = "Crate",
			main = {
				action = "Place",
				enabled = false,
				run = function()
					local state = registry.StateController
					local profile = state.profile
					if not profile then
						return
					end
					if pad > Economy.unlockedPads(profile) then
						registry.UIController.open("UpgradeShop")
						return
					end
					local _, crate = state.crateOnPad(pad)
					if crate then
						WorldController.openCrate(pad)
					else
						WorldController.placeCrateOnPad(pad)
					end
				end,
			},
			secondary = {
				action = "Pick Up",
				enabled = false,
				run = function()
					local result = registry.StateController.request("PickUpCrate", { pad = pad })
					if result.ok then
						registry.SoundController.play("pickUp")
					end
				end,
			},
		})
	end

	for slot = 1, GameConfig.SlotCount do
		add({
			id = "slot" .. slot,
			kind = "slot",
			index = slot,
			ownFarm = true,
			position = Layout.slotWorld(index, slot).Position,
			area = squareArea(Layout.slotWorld(index, slot).Position, Layout.SlotSize),
			range = 13,
			lift = 20,
			object = "Sorcerer",
			main = {
				action = "Place",
				enabled = false,
				run = function()
					local state = registry.StateController
					local profile = state.profile
					if not profile then
						return
					end
					if slot > Economy.unlockedSlots(profile) then
						registry.UIController.open("UpgradeShop")
						return
					end
					local uid = profile.slots[tostring(slot)]
					if uid then
						local result = state.request("UpgradeSorcerer", { uid = uid })
						if result.ok then
							registry.SoundController.play("upgrade")
						end
					else
						WorldController.placeSorcererOnSlot(slot)
					end
				end,
			},
			secondary = {
				action = "Pick Up",
				enabled = false,
				run = function()
					local result = registry.StateController.request("PickUpSorcerer", { slot = slot })
					if result.ok then
						registry.SoundController.play("pickUp")
						registry.UIController.toast(
							"Picked up. Place it again from Sorcerers (G) or an empty slot.",
							"info"
						)
					end
				end,
			},
		})
	end

	-- The prompt goes over whichever of the Orb Box and the Collect Pad is higher on screen,
	-- so it never covers you standing on the pad.
	local box = Layout.boxWorld(index)
	local pad = (Layout.farmFloor(index) * CFrame.new(Layout.CollectPoint)).Position
	local boxHigher = box.Z < pad.Z
	local info = WorldMap.get().farms[index]
	local boxArea, padArea = artArea(info.box), artArea(info.collect)
	add({
		id = "collect",
		kind = "collect",
		position = box,
		-- (the Orb Box and the Collect Pad in front of it)
		area = {
			math.min(boxArea[1], padArea[1]),
			math.min(boxArea[2], padArea[2]),
			math.max(boxArea[3], padArea[3]),
			math.max(boxArea[4], padArea[4]),
		},
		range = GameConfig.CollectRange,
		promptAt = if boxHigher then nil else pad,
		lift = if boxHigher then 20 else 22,
		object = "Orb Box",
		main = {
			action = "Collect",
			enabled = false,
			run = function()
				registry.StateController.request("Collect")
			end,
		},
	})
end

-- Same rules as ever: what each pad, slot and the Orb Box offers right now.
local function refreshOwnFarm()
	local state = registry.StateController
	local profile = state.profile
	if not profile or not ownFarm then
		return
	end
	local now = state.now()
	local unlockedPads = Economy.unlockedPads(profile)
	local unplacedCrates = state.unplacedCrates()
	for pad = 1, GameConfig.PadCount do
		local it = byId["pad" .. pad]
		local _, crate = state.crateOnPad(pad)
		local locked = pad > unlockedPads
		it.secondary.enabled = crate ~= nil
		it.note = nil
		it.hintOnly = nil
		if locked then
			it.main.enabled = true
			it.main.action = "Upgrade"
			it.object = "More Crate Pads"
			it.hint = "Locked - More Crate Pads"
			it.lift = 10
		elseif crate then
			local def = Crates.get(crate.tier)
			local remaining = crate.readyAt - now
			it.main.enabled = remaining <= 0
			it.main.action = "Open"
			it.object = if def then def.name else "Crate"
			it.hint = if remaining > 0 then "Opening Time " .. Format.clock(remaining) else nil
			it.lift = 24
		else
			local nextCrate = unplacedCrates[1]
			local def = nextCrate and Crates.get(nextCrate.tier)
			it.main.enabled = nextCrate ~= nil
			it.main.action = "Place"
			it.object = if def then def.name else "Crate"
			it.hintOnly = true
			it.hint = if nextCrate
				then "Crate Pad - Place a Crate"
				else "Crate Pad - Buy Crates at the Crate Shop"
			it.lift = 10
		end
	end
	-- "READY!" chime for your own crates
	for cid, crate in profile.crates do
		if crate.pad and crate.readyAt and now >= crate.readyAt and not readyAnnounced[cid] then
			readyAnnounced[cid] = true
			registry.SoundController.play("crateReady")
		end
	end

	local unlockedSlots = Economy.unlockedSlots(profile)
	local spare = bestUnplacedSorcerer()
	for slot = 1, GameConfig.SlotCount do
		local it = byId["slot" .. slot]
		local uid = profile.slots[tostring(slot)]
		local unit = uid and profile.units[uid]
		it.secondary.enabled = unit ~= nil
		it.note = nil
		it.hintOnly = nil
		if slot > unlockedSlots then
			it.main.enabled = true
			it.main.action = "Upgrade"
			it.object = "More Slots"
			it.hint = "Locked slot - More Slots"
			it.lift = 18
		elseif unit then
			local def = Sorcerers.get(unit.id)
			local cost = Economy.unitUpgradeCost(unit)
			it.main.enabled = cost ~= nil
			it.main.action = "Upgrade"
			it.object = string.format(
				"%s Lv %d  %s",
				if def then def.name else "?",
				unit.level,
				if cost then Format.cash(cost) else "MAX"
			)
			it.hint = nil
			it.lift = 20
		else
			local spareUnit = spare and profile.units[spare]
			local def = spareUnit and Sorcerers.get(spareUnit.id)
			it.main.enabled = spare ~= nil
			it.main.action = "Place"
			it.object = if def then def.name else "Sorcerer"
			it.hintOnly = true
			it.hint = if spare then "Empty slot - Place a Sorcerer" else "Empty slot"
			it.lift = 18
		end
	end

	local collect = byId.collect
	local orbs, _, cap = state.box()
	collect.main.enabled = orbs >= 1
	collect.object = if orbs >= 1 then Format.commas(math.floor(orbs)) .. " Cursed Orbs" else "Orb Box"
	collect.hint = string.format("%s / %s", Format.commas(math.floor(orbs)), Format.commas(cap))
	local full = cap > 0 and orbs >= cap - 0.01
	collect.note = if full then "FULL!  Collect it" else nil
	collect.noteColor = Palette.Yellow
end

-- Plaza ---------------------------------------------------------------------------------

local function displays(): { WorldMap.Object }
	local out = {}
	for _, object in WorldMap.get().objects do
		if object.kind == "display" and object.variant then
			table.insert(out, object)
		end
	end
	return out
end

local function rectCenter(rect: WorldMap.Rect): Vector3
	return Vector3.new((rect.x0 + rect.x1) / 2, 0, (rect.z0 + rect.z1) / 2)
end

local function objectArea(kind: string): { number }?
	for _, object in WorldMap.get().objects do
		if object.kind == kind then
			return artArea(object.rect)
		end
	end
	return nil
end

local function setupPlaza()
	add({
		id = "sell",
		kind = "sell",
		position = Layout.SellStand,
		area = objectArea("sellStand"),
		range = GameConfig.SellRange,
		lift = 22,
		object = "Cursed Orbs",
		main = {
			action = "Sell",
			enabled = false,
			run = function()
				registry.StateController.request("Sell")
			end,
		},
	})

	for _, object in displays() do
		local def = Crates.get(object.variant :: string)
		if def then
			add({
				id = "buy_" .. def.id,
				kind = "buy",
				tier = def.id,
				position = rectCenter(object.rect),
				area = artArea(object.rect),
				range = 10,
				center = Layout.CrateShop,
				centerRange = GameConfig.ShopRange,
				lift = 26,
				object = def.name .. "  " .. Format.cash(def.price),
				note = "Opening Time " .. Format.duration(def.openingTime),
				noteColor = Palette.Slate,
				main = {
					action = "Buy",
					enabled = true,
					run = function()
						local result = registry.StateController.request("BuyCrate", { tier = def.id })
						if result.ok then
							registry.SoundController.play("buy")
							registry.EffectsController.boughtCrate(def.id)
							registry.UIController.toast(
								def.name .. " bought! Place it on a Crate Pad at Your Farm.",
								"good"
							)
						end
					end,
				},
				secondary = {
					action = "Browse",
					enabled = true,
					run = function()
						registry.UIController.open("CrateShop")
					end,
				},
			})
		end
	end

	local shop = Layout.CrateShop
	add({
		id = "crateShop",
		kind = "crateShop",
		position = Vector3.new(shop.X, 0, shop.Z - 10),
		range = 14,
		center = Layout.CrateShop,
		centerRange = GameConfig.ShopRange,
		lift = 16,
		object = "Crate Shop",
		main = {
			action = "Browse",
			enabled = true,
			run = function()
				registry.UIController.open("CrateShop")
			end,
		},
	})

	local upgrades = Layout.UpgradeShop
	add({
		id = "upgradeShop",
		kind = "upgradeShop",
		position = Vector3.new(upgrades.X, 0, upgrades.Z - 8),
		range = 16,
		center = Layout.UpgradeShop,
		centerRange = GameConfig.ShopRange,
		lift = 22,
		object = "Upgrade Shop",
		main = {
			action = "Upgrade",
			enabled = true,
			run = function()
				registry.UIController.open("UpgradeShop")
			end,
		},
	})
end

local function refreshPlaza()
	local profile = registry.StateController.profile
	local sell = byId.sell
	if not profile or not sell then
		return
	end
	local carried = profile.carried
	sell.main.enabled = carried.orbs >= 1
	if carried.orbs >= 1 then
		sell.object = string.format(
			"%s Cursed Orbs (%s)",
			Format.commas(carried.orbs),
			Format.cash(math.floor(carried.value + 0.5))
		)
		sell.hint = nil
		sell.lift = 22
	else
		sell.object = "Sell Stand"
		sell.hint = "Bring your Orb Box here and Sell"
		sell.lift = 36 -- over the stand's beam, clear of the coins and "+$" when you've sold
	end
end

-- Prompt ------------------------------------------------------------------------------------

local function inRange(it: Interaction, at: Vector3): (boolean, number)
	local d = flat(at, it.position)
	if d > it.range then
		return false, d
	end
	if it.center and it.centerRange and flat(at, it.center) > it.centerRange then
		return false, d
	end
	if it.ownFarm and not (ownFarm and Layout.inFarm(ownFarm, at)) then
		return false, d
	end
	return true, d
end

local function actionable(it: Interaction): boolean
	return it.main.enabled or (it.secondary ~= nil and it.secondary.enabled)
end

-- The interaction the prompt should show: the nearest one in range, preferring ones with
-- something to do over ones with only a hint.
local function pick(at: Vector3?): Interaction?
	if not at or not registry.StateController.profile then
		return nil
	end
	local best, bestScore = nil, math.huge
	for _, it in list do
		local ok, d = inRange(it, at)
		if ok and (actionable(it) or it.hint) then
			local score = d + (if actionable(it) then 0 else 1000)
			if score < bestScore then
				best, bestScore = it, score
			end
		end
	end
	return best
end

local function run(action: Action?)
	if action and action.enabled then
		task.spawn(action.run)
	end
end

local function placing(): boolean
	local placement = registry.PlacementController
	return placement ~= nil and placement.isActive()
end

local function activate(secondary: boolean)
	local it = current
	if not it or registry.RevealController.isPlaying() or placing() then
		return
	end
	local action = if secondary then it.secondary else it.main
	if action and action.enabled then
		prompt:flash(if secondary then "secondary" else "main")
		run(action)
	end
end

-- How the player is playing right now: keys on keycaps for keyboards and gamepads (E / R or
-- X / Y), buttons to tap on touch screens.
local function inputMode(): string
	local ok, last = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	if ok and typeof(last) == "EnumItem" then
		if string.find(last.Name, "^Gamepad") then
			return "gamepad"
		elseif last == Enum.UserInputType.Touch then
			return "touch"
		elseif string.find(last.Name, "^Mouse") or last == Enum.UserInputType.Keyboard then
			return "keyboard"
		end
	end
	local function enabled(name: string): boolean
		local okRead, value = pcall(function()
			return (UserInputService :: any)[name]
		end)
		return okRead and value == true
	end
	if enabled("TouchEnabled") and not enabled("KeyboardEnabled") then
		return if enabled("GamepadEnabled") then "gamepad" else "touch"
	end
	return "keyboard"
end

local KEYS = {
	keyboard = { main = "E", secondary = "R" },
	gamepad = { main = "X", secondary = "Y" },
}

local function rowsFor(it: Interaction): { Prompt.Row }
	local mode = inputMode()
	local keys = KEYS[mode]
	local rows: { Prompt.Row } = {}
	if it.main.enabled then
		table.insert(rows, {
			key = keys and keys.main,
			tap = keys == nil,
			id = "main",
			text = it.main.action,
			color = Palette.White,
			onClick = function()
				activate(false)
			end,
		})
		table.insert(rows, { text = it.object, color = Palette.Mist })
	else
		if not (it.hintOnly and it.hint) then
			table.insert(rows, { text = it.object, color = Palette.Mist })
		end
		if it.hint then
			for _, line in Widgets.wrap(it.hint, HINT_CHARS) do
				table.insert(rows, { text = line, color = Palette.Cream })
			end
		end
	end
	if it.note then
		table.insert(rows, { text = it.note, color = it.noteColor or Palette.Slate })
	end
	if it.secondary and it.secondary.enabled then
		table.insert(rows, {
			key = keys and keys.secondary,
			tap = keys == nil,
			id = "secondary",
			text = it.secondary.action,
			color = Palette.White,
			onClick = function()
				activate(true)
			end,
		})
	end
	return rows
end

-- Your character's sprite (art pixels), which the prompt avoids covering when it can.
local function characterArea(at: Vector3?): { Front.Rect }
	if not at then
		return {}
	end
	local x, y = Camera2D.toArt(at)
	return { { x0 = x - 8, y0 = y - 20, x1 = x + 8, y1 = y + 5 } }
end

local function updatePrompt()
	local at = rootPosition()
	local it = if registry.RevealController.isPlaying() or placing() then nil else pick(at)
	current = it
	if not it then
		prompt:setVisible(false)
		return
	end
	prompt:set(rowsFor(it))
	local px, py = Camera2D.toArt(it.promptAt or it.position)
	local area = it.area
	local x0, y0, x1, y1 = Camera2D.view()
	prompt:place({
		cx = px,
		top = py - it.lift,
		bottom = (if area then area[4] else py + 6) + 1,
		left = if area then area[1] else px - 8,
		right = if area then area[3] else px + 8,
	}, x0, y0, x1, y1, Front.blockers(), characterArea(at))
	prompt:setVisible(true)
end

-- World labels ------------------------------------------------------------------------------

local LABEL_W = 64
local OWNER_CHARS = 9 -- names are cut to this many characters (as on the farm signs)

-- "$60", "$2K", "$75K", "$2.5M": short enough for tags 40 pixels apart.
local function shortPrice(value: number): string
	local function fmt(n: number, suffix: string): string
		local rounded = math.floor(n * 10 + 0.5) / 10
		local text = if rounded == math.floor(rounded)
			then string.format("%d", rounded)
			else string.format("%.1f", rounded)
		return "$" .. text .. suffix
	end
	if value >= 1e9 then
		return fmt(value / 1e9, "B")
	elseif value >= 1e6 then
		return fmt(value / 1e6, "M")
	elseif value >= 1e3 then
		return fmt(value / 1e3, "K")
	end
	return "$" .. tostring(math.floor(value))
end

local function ownerName(model: Instance): string?
	local owner = model:GetAttribute("OwnerName")
	return if type(owner) == "string" then string.sub(owner, 1, OWNER_CHARS) else nil
end

-- Other players' Orb Boxes: "12 / 60" and "<OWNER>'S ORB BOX" over the box (yours is on the
-- HUD and in the Collect prompt).
type BoxLabel = { count: Frame, owner: Frame }
local boxLabels: { [number]: BoxLabel } = {}

-- Each farm's stats board (the old notice board by the entrance): shown over the farm's name
-- sign while you walk past it outside the farm.
type Board = {
	frame: Frame,
	lines: { Frame },
	signature: string,
	x: number,
	y: number,
	signX: number,
	signY: number,
	north: boolean,
	w: number,
	h: number,
}
local boards: { [number]: Board } = {}
local BOARD_RANGE = 26 -- studs from the sign
local BOARD_LINES = 4

local function setupBoxLabels()
	local overlay = Screen.layers.Overlay
	for _, info in WorldMap.get().farms do
		local count = Text.centered(overlay, "", LABEL_W * 2, { color = Palette.Mist, zindex = 20 })
		count.Name = "BoxCount" .. info.index
		count.Visible = false
		local owner = Text.centered(overlay, "", LABEL_W * 3, { color = Palette.Slate, zindex = 20 })
		owner.Name = "BoxOwner" .. info.index
		owner.Visible = false
		boxLabels[info.index] = { count = count, owner = owner }
	end
end

local function setupBoards()
	local overlay = Screen.layers.Overlay
	for _, info in WorldMap.get().farms do
		local frame = Widgets.panel(overlay, 40, 20, Widgets.Styles.board, 18)
		frame.Name = "StatsBoard" .. info.index
		frame.Visible = false
		local lines = {}
		for i = 1, BOARD_LINES do
			lines[i] = Widgets.label(frame, "", 4, 4 + (i - 1) * 9, Palette.Cream, 18 + Widgets.ContentZ)
		end
		-- Over the name sign (WorldView draws it beside the gate, on the road side), toward the
		-- plaza: below it for the north row, above it for the south row.
		local gx, gy = Camera2D.toArt(info.gate)
		local signX = gx + 12 + 36
		local f = info.floor
		local _, fy0 = WorldMap.toPixels(f.x0, f.z0)
		local _, fy1 = WorldMap.toPixels(f.x1, f.z1)
		local signY = if info.north then math.floor(fy1) + 8 else math.floor(fy0) - 8
		boards[info.index] = {
			frame = frame,
			lines = lines,
			signature = "",
			x = 0,
			y = 0,
			signX = signX,
			signY = signY,
			north = info.north,
			w = 40,
			h = 20,
		}
		local _ = gy
	end
end

local function setupShopCrates()
	local overlay = Screen.layers.Overlay
	for _, object in displays() do
		local tier = object.variant :: string
		local def = Crates.get(tier)
		local center = rectCenter(object.rect)
		local px, py = Camera2D.toArt(center)
		local tag = Text.centered(
			overlay,
			if def then shortPrice(def.price) else "",
			LABEL_W,
			{ color = Palette.Yellow, zindex = 20 }
		)
		tag.Name = "PriceTag_" .. tier
		-- Under the pedestal, so the Buy prompt above never hides it.
		tag.Position = UDim2.fromOffset(px - LABEL_W / 2, py + 10)
		local entry = { tier = tier, actor = nil :: any, tag = tag, x = px, y = py, id = "buy_" .. tier }
		table.insert(shopCrates, entry)
		-- The crate stands on the pedestal's top.
		local ok, err = pcall(function()
			local actor = Actor.new(
				Screen.layers.Actors,
				{ crate = CrateArt.sprite(tier) },
				{ name = "ShopCrate_" .. tier }
			)
			entry.actor = actor
			actor:moveTo(px, py + 1)
			actor:play("crate", 1)
		end)
		if not ok then
			warn("[JJK Farm] shop crate", tier, err)
		end
	end
end

local clock = 0
local labelWarned: number? = nil

local function farmOwned(index: number): Instance?
	local WorldView = registry.WorldView
	local farm = WorldView and WorldView.farm(index)
	local model = farm and farm.model
	if model and model:GetAttribute("OwnerId") ~= nil then
		return model
	end
	return nil
end

local function drawBoard(index: number, board: Board, model: Instance)
	local ops = model:GetAttribute("Ops") or 0
	local cash = model:GetAttribute("CashRate") or 0
	local orbs, _, cap = registry.ProductionController.boxOf(model)
	local owner = ownerName(model)
	local title = if index == ownFarm
		then "YOUR FARM"
		elseif owner then string.upper(owner) .. "'S FARM"
		else "EMPTY FARM"
	local texts = {
		title,
		"Orbs per Second: " .. Format.abbreviate(ops),
		"Cash: " .. Format.cash(cash) .. "/s",
		string.format("Orb Box: %s / %s", Format.commas(math.floor(orbs)), Format.commas(cap)),
	}
	local signature = table.concat(texts, "|")
	if signature == board.signature then
		return
	end
	board.signature = signature
	local width = 0
	for i, text in texts do
		local upper = string.upper(text)
		Widgets.setLabel(board.lines[i], upper, if i == 1 then Palette.Yellow else Palette.Cream)
		width = math.max(width, Text.width(upper))
	end
	local w, h = width + 9, 4 + BOARD_LINES * 9 + 2
	if w ~= board.w or h ~= board.h then
		board.w, board.h = w, h
		Widgets.resize(board.frame, w, h, Widgets.Styles.board)
	end
	-- (title centred over the stats)
	board.lines[1].Position = UDim2.fromOffset(math.floor((w - Text.width(texts[1])) / 2), 4)
	local x = board.signX - math.floor(w / 2)
	local y = if board.north then board.signY + 8 else board.signY - 8 - h
	if x ~= board.x or y ~= board.y then
		board.x, board.y = x, y
		board.frame.Position = UDim2.fromOffset(x, y)
	end
end

local function updateLabels()
	local at = rootPosition()
	local x0, y0, x1, y1 = Camera2D.view()
	local function onScreen(x: number, y: number, margin: number): boolean
		return x >= x0 - margin and x <= x1 + margin and y >= y0 - margin and y <= y1 + margin
	end
	-- Price tags and crates on the Crate Shop displays
	local nearShop = at ~= nil and flat(at, Layout.CrateShop) <= GameConfig.ShopRange + 16
	for _, entry in shopCrates do
		local visible = onScreen(entry.x, entry.y, 32)
		if entry.actor then
			entry.actor:setVisible(visible)
		end
		entry.tag.Visible = visible and nearShop
	end
	-- Other players' Orb Boxes on screen
	local half = Layout.BoxSize * PPS / 2
	for index, label in boxLabels do
		local model = if index ~= ownFarm then farmOwned(index) else nil
		local bx, by = Camera2D.toArt(Layout.boxWorld(index))
		local show = model ~= nil and onScreen(bx, by, 16)
		if show and model then
			local orbs, _, cap = registry.ProductionController.boxOf(model)
			local full = cap > 0 and orbs >= cap - 0.01
			local top = by - half - 20
			label.count.Position = UDim2.fromOffset(bx - LABEL_W, top)
			label.owner.Position = UDim2.fromOffset(bx - math.floor(LABEL_W * 1.5), top + 9)
			if full then
				Text.set(label.count, if math.floor(clock * 3) % 2 == 0 then "FULL!" else "", Palette.Yellow)
			else
				Text.set(
					label.count,
					string.format("%s / %s", Format.commas(math.floor(orbs)), Format.commas(cap)),
					Palette.Mist
				)
			end
			Text.set(label.owner, string.upper((ownerName(model) or "?") .. "'s Orb Box"), Palette.Slate)
		end
		label.count.Visible = show
		label.owner.Visible = show
	end
	-- The stats board of the farm whose sign you're walking past (outside its fence).
	local nearest, nearestD = nil, BOARD_RANGE
	if at then
		local ax, ay = Camera2D.toArt(at)
		for index, board in boards do
			local d = math.sqrt((ax - board.signX) ^ 2 + (ay - board.signY) ^ 2) / PPS
			if d < nearestD and not Layout.inFarm(index, at) and farmOwned(index) then
				nearest, nearestD = index, d
			end
		end
	end
	for index, board in boards do
		local show = index == nearest
		if show then
			drawBoard(index, board, farmOwned(index) :: Instance)
		end
		if board.frame.Visible ~= show then
			board.frame.Visible = show
		end
	end
end

local function setupLabels()
	for _, setup in { setupBoxLabels, setupBoards, setupShopCrates } do
		local ok, err = pcall(setup)
		if not ok then
			warn("[JJK Farm] world labels", err)
		end
	end
end

-- Public ------------------------------------------------------------------------------------

function WorldController.ownFarm(): number?
	return ownFarm
end

-- Every interaction and what it offers right now (for tests and tools).
function WorldController.interactions(): { any }
	local at = rootPosition()
	local out = {}
	for _, it in list do
		local ok = if at then (inRange(it, at)) else false
		table.insert(out, {
			id = it.id,
			kind = it.kind,
			index = it.index,
			tier = it.tier,
			position = it.position,
			action = it.main.action,
			object = it.object,
			enabled = it.main.enabled,
			hint = it.hint,
			note = it.note,
			secondary = if it.secondary
				then { action = it.secondary.action, enabled = it.secondary.enabled }
				else nil,
			inRange = ok,
			current = current == it,
		})
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

-- Runs an interaction's action (the main one, or the secondary with `secondary`), as if its
-- key were pressed in range. Returns false when there is no such action. (Test hook: runs
-- synchronously and doesn't check range or Enabled, like firing a prompt's Triggered.)
function WorldController.trigger(id: string, secondary: boolean?): boolean
	local it = byId[id]
	local action = it and (if secondary then it.secondary else it.main)
	if not action then
		return false
	end
	action.run()
	return true
end

-- The interaction the prompt is showing (id), if any.
function WorldController.current(): string?
	return current and current.id
end

-- The world prompt (Pixel/Prompt), for tests.
function WorldController.prompt(): any
	return prompt
end

-- Old test hooks (the world had a ProximityPrompt per pad and slot): what that prompt would
-- say now, with the same field names, and Triggered:Fire() runs its action.
local function legacyPrompt(id: string): any
	local it = byId[id]
	if not it then
		return nil
	end
	local fire = function()
		WorldController.trigger(id)
	end
	return {
		Name = id,
		ActionText = it.main.action,
		ObjectText = it.object,
		Enabled = it.main.enabled,
		Triggered = { Fire = fire, FireSync = fire },
	}
end

function WorldController.padPrompt(pad: number): any
	return legacyPrompt("pad" .. pad)
end

function WorldController.slotPrompt(slot: number): any
	return legacyPrompt("slot" .. slot)
end

function WorldController.refresh()
	refreshOwnFarm()
	refreshPlaza()
end

function WorldController.init(reg: any)
	registry = reg
end

function WorldController.start()
	Screen.start()
	Front.start()
	prompt = Prompt.new(Front.world, 60)
	-- The HUD's cards (and the front layer goes away while a panel covers the screen).
	local ui = registry.UIController
	Front.addBlocker("hud", function()
		return ui.getGui()
	end, function()
		return if ui.hudRects then ui.hudRects() else {}
	end, function()
		return ui.pixelScale or Screen.scale
	end)
	Front.hideWhen("panel", function()
		return ui.currentPanel() ~= nil
	end)
	-- Input and the frame loop first, so a problem drawing a label can never take the
	-- interactions with it.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.E or key == Enum.KeyCode.ButtonX then
			activate(false)
		elseif key == Enum.KeyCode.R or key == Enum.KeyCode.ButtonY then
			activate(true)
		end
	end)
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		acc += dt
		if acc >= 0.2 then
			acc = 0
			refreshOwnFarm()
			refreshPlaza()
		end
		updatePrompt()
		local ok, err = pcall(updateLabels)
		if not ok and clock - (labelWarned or -10) > 10 then
			labelWarned = clock
			warn("[JJK Farm] world labels", err)
		end
	end)
	setupPlaza()
	local state = registry.StateController
	local function onState(profile)
		if profile and profile.farm and profile.farm ~= ownFarm then
			setupOwnFarm(profile.farm)
		end
		refreshOwnFarm()
		refreshPlaza()
	end
	state.Changed:Connect(onState)
	if state.profile then
		onState(state.profile)
	end
	setupLabels()
end

return WorldController
