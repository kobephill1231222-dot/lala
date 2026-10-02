--!nonstrict
-- Sound toggles, tutorial controls and a reminder of the controls.

local UIKit = require(script.Parent.Parent.UIKit)
local Theme = require(script.Parent.Parent.Theme)

local SettingsPanel = {}

local new = UIKit.new

function SettingsPanel.create(registry: any)
	local state = registry.StateController
	local ui = registry.UIController
	local root, content, scale = UIKit.panel("Settings", Vector2.new(520, 470), function()
		ui.close()
	end)
	local list = new("Frame", {
		Parent = content,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		UIKit.list(Enum.FillDirection.Vertical, 10),
	})

	local toggles = {}
	local function toggleRow(order: number, key: string, label: string)
		local row = new("Frame", {
			Parent = list,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 50),
			BackgroundColor3 = Theme.PanelLight,
			UIKit.corner(12),
		})
		UIKit.text({
			Parent = row,
			Position = UDim2.fromOffset(16, 0),
			Size = UDim2.new(1, -160, 1, 0),
			Text = label,
			FontFace = Theme.BodyBold,
			TextSize = 17,
		})
		local button = UIKit.button({
			parent = row,
			text = "",
			style = "secondary",
			size = UDim2.fromOffset(110, 36),
			position = UDim2.new(1, -122, 0.5, -18),
			onClick = function()
				local profile = state.profile
				if profile then
					state.request("Settings", { [key] = not profile.settings[key] })
				end
			end,
		})
		toggles[key] = button
	end
	toggleRow(1, "music", "Music & ambience")
	toggleRow(2, "sfx", "Sound effects")

	local tutorialRow = new("Frame", {
		Parent = list,
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = Theme.PanelLight,
		UIKit.corner(12),
	})
	UIKit.text({
		Parent = tutorialRow,
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -180, 1, 0),
		Text = "Guided introduction",
		FontFace = Theme.BodyBold,
		TextSize = 17,
	})
	local skip = UIKit.button({
		parent = tutorialRow,
		text = "Skip",
		style = "secondary",
		size = UDim2.fromOffset(130, 36),
		position = UDim2.new(1, -142, 0.5, -18),
		onClick = function()
			state.request("SkipTutorial")
		end,
	})

	local introRow = new("Frame", {
		Parent = list,
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = Theme.PanelLight,
		UIKit.corner(12),
	})
	UIKit.text({
		Parent = introRow,
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -180, 1, 0),
		Text = "Village flyover",
		FontFace = Theme.BodyBold,
		TextSize = 17,
	})
	UIKit.button({
		parent = introRow,
		text = "Replay",
		style = "secondary",
		size = UDim2.fromOffset(130, 36),
		position = UDim2.new(1, -142, 0.5, -18),
		onClick = function()
			ui.close(true)
			registry.IntroController.play()
		end,
	})

	UIKit.text({
		Parent = list,
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 130),
		Text = "<b>Controls</b>\nWalk into your Spirit Well to collect.  E: interact\nF Summon  -  G Allies  -  U Upgrades  -  T Travel\nIn the forest: click or 1 Strike, 2 Lance, 3 Burst\nOn touch screens use the on-screen buttons.",
		TextColor3 = Theme.TextDim,
		TextSize = 14,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	local function refresh()
		local profile = state.profile
		if not profile then
			return
		end
		for key, button in toggles do
			local on = profile.settings[key]
			UIKit.setText(button, if on then "On" else "Off")
		end
		local active = profile.tutorial <= 5
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
