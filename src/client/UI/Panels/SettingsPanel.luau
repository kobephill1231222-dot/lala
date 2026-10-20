--!nonstrict
-- Sound toggles, tutorial controls and a reminder of the controls (pixel window).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tutorial = require(Shared.Rules.Tutorial)
local Palette = require(Shared.Pixel.Palette)
local UIKit = require(script.Parent.Parent.UIKit)

local SettingsPanel = {}

local P = Palette
local W, H = 316, 164
local CW = W - 8 -- content width
local ROW_H = 16
local BUTTON_W = 88

-- The original controls text, wrapped to the window (38 characters), plus how to walk.
local CONTROLS = {
	"Walk: WASD, or the thumbstick on touch",
	"E: Buy, Open, Place, Collect, Sell",
	"(walk up to things)",
	"R: Pick Up    G: Sorcerers",
	"C: Crates    H: Go to Your Farm",
	"Step on your Collect Pad or the Sell",
	"Stand to Collect or Sell.",
	"On touch screens, tap the on-screen",
	"prompts and buttons.",
}

function SettingsPanel.create(registry: any)
	local state = registry.StateController
	local ui = registry.UIController
	local root, content, scale = UIKit.panel("Settings", Vector2.new(W, H), function()
		ui.close()
	end)

	local function row(order: number, label: string): Frame
		local y = (order - 1) * (ROW_H + 1)
		local box = UIKit.box(content, 0, y, CW, ROW_H, "row", "Frame", "Row" .. order)
		UIKit.label(box, label, 4, 4, { name = "Label" })
		return box
	end

	local toggles = {}
	local function toggleRow(order: number, key: string, label: string)
		local box = row(order, label)
		local button = UIKit.button({
			parent = box,
			text = "",
			style = "secondary",
			size = UDim2.fromOffset(BUTTON_W, 14),
			position = UDim2.fromOffset(CW - BUTTON_W - 1, 1),
			onClick = function()
				local profile = state.profile
				if profile then
					state.request("Settings", { [key] = not profile.settings[key] })
				end
			end,
		})
		button.ZIndex = 3
		toggles[key] = button
	end
	toggleRow(1, "music", "Music & ambience")
	toggleRow(2, "sfx", "Sound effects")

	local tutorialRow = row(3, "Guided introduction")
	local skip = UIKit.button({
		parent = tutorialRow,
		text = "Skip",
		style = "secondary",
		size = UDim2.fromOffset(BUTTON_W, 14),
		position = UDim2.fromOffset(CW - BUTTON_W - 1, 1),
		onClick = function()
			state.request("SkipTutorial")
		end,
	})
	skip.ZIndex = 3

	local top = 3 * (ROW_H + 1) + 1
	UIKit.label(content, "CONTROLS", 0, top, { name = "ControlsTitle", color = P.Amber })
	local controls = UIKit.para(content, 0, top + 9, CW, #CONTROLS, { name = "Controls", color = P.Mist })
	controls.set(table.concat(CONTROLS, "\n"))

	local function refresh()
		local profile = state.profile
		if not profile then
			return
		end
		for key, button in toggles do
			local on = profile.settings[key]
			UIKit.setText(button, if on then "On" else "Off")
			UIKit.setStyle(button, if on then "cash" else "secondary")
		end
		local active = profile.tutorial < Tutorial.Done
		UIKit.setEnabled(skip, active)
		UIKit.setText(skip, if active then "Skip" else "Completed")
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

return SettingsPanel
