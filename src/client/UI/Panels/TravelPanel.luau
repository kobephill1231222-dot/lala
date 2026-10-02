--!nonstrict
-- Fast travel between landmarks so the loop stays convenient on every device.

local UIKit = require(script.Parent.Parent.UIKit)
local Theme = require(script.Parent.Parent.Theme)

local TravelPanel = {}

local new = UIKit.new

local DESTINATIONS = {
	{ id = "Home", name = "Your Sanctuary", text = "Collect energy and place allies.", color = Theme.Violet },
	{
		id = "Courtyard",
		name = "Summoning Courtyard",
		text = "Perform rituals to recruit allies.",
		color = Color3.fromRGB(176, 104, 255),
	},
	{ id = "Shop", name = "Talisman Shop", text = "Buy permanent upgrades.", color = Theme.Gold },
	{
		id = "Dojo",
		name = "Training Dojo",
		text = "Practise techniques on dummies.",
		color = Color3.fromRGB(214, 150, 70),
	},
	{
		id = "Forest",
		name = "Cursed Forest",
		text = "Fight curses for energy and seals.",
		color = Theme.Seal,
	},
	{
		id = "Shrine",
		name = "Spirit Tree Shrine",
		text = "The arrival plaza and the great tree.",
		color = Color3.fromRGB(150, 200, 255),
	},
}

function TravelPanel.create(registry: any)
	local ui = registry.UIController
	local root, content, scale = UIKit.panel("Travel", Vector2.new(560, 520), function()
		ui.close()
	end)
	local list = new("Frame", {
		Parent = content,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		UIKit.list(Enum.FillDirection.Vertical, 8),
	})
	for i, dest in DESTINATIONS do
		local rowFrame = new("Frame", {
			Parent = list,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 62),
			BackgroundColor3 = Theme.PanelLight,
			UIKit.corner(12),
			UIKit.stroke(dest.color, 1.5, 0.4),
		})
		new("Frame", {
			Parent = rowFrame,
			Position = UDim2.fromOffset(14, 21),
			Size = UDim2.fromOffset(20, 20),
			Rotation = 45,
			BackgroundColor3 = dest.color,
			UIKit.corner(4),
		})
		UIKit.text({
			Parent = rowFrame,
			Position = UDim2.fromOffset(48, 6),
			Size = UDim2.new(1, -200, 0, 26),
			Text = dest.name,
			FontFace = Theme.TitleBold,
			TextSize = 21,
		})
		UIKit.text({
			Parent = rowFrame,
			Position = UDim2.fromOffset(48, 32),
			Size = UDim2.new(1, -200, 0, 20),
			Text = dest.text,
			TextColor3 = Theme.TextDim,
			TextSize = 13,
		})
		UIKit.button({
			parent = rowFrame,
			text = "Go",
			style = "primary",
			size = UDim2.fromOffset(120, 42),
			position = UDim2.new(1, -132, 0.5, -21),
			onClick = function()
				ui.close(true)
				registry.WorldController.travel(dest.id)
			end,
		})
	end
	return { root = root, scale = scale }
end

return TravelPanel
