--!nonstrict
-- First-visit flyover: the camera sweeps down from above the spirit tree to the arrival
-- plaza while the title fades in. Skippable with any click/tap/key.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Layout = require(ReplicatedStorage:WaitForChild("Shared").Config.MapLayout)

local UI = script.Parent.Parent.UI
local UIKit = require(UI.UIKit)
local Theme = require(UI.Theme)

local IntroController = {}

local player = Players.LocalPlayer
local new = UIKit.new
local registry: any
local playing = false

function IntroController.play()
	if playing then
		return
	end
	playing = true
	local camera = workspace.CurrentCamera
	if not camera then
		playing = false
		return
	end
	local gui = new("ScreenGui", {
		Name = "Intro",
		IgnoreGuiInset = true,
		DisplayOrder = 30,
		ResetOnSpawn = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local top = new("Frame", {
		Parent = gui,
		Size = UDim2.new(1, 0, 0.12, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
	})
	local bottom = new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0.12, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
	})
	local title = UIKit.text({
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(900, 90),
		Text = "CURSEBOUND FARM",
		FontFace = Theme.TitleBold,
		TextSize = 72,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		TextStrokeColor3 = Color3.fromRGB(80, 30, 140),
	})
	local subtitle = UIKit.text({
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(900, 30),
		Text = "Raise spirits. Seal curses. Tend the fractured tree.",
		TextColor3 = Theme.TextDim,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
	})
	UIKit.text({
		Parent = bottom,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(400, 24),
		Text = "tap to skip",
		TextColor3 = Theme.TextFaint,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local previousType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
	local tree = Layout.TreeBase
	local shots = {
		{
			from = CFrame.lookAt(tree + Vector3.new(-150, 150, -120), tree + Vector3.new(0, 60, 0)),
			to = CFrame.lookAt(tree + Vector3.new(-80, 110, 90), tree + Vector3.new(0, 70, 0)),
			time = 4,
		},
		{
			from = CFrame.lookAt(tree + Vector3.new(60, 40, 120), tree + Vector3.new(0, 55, 0)),
			to = CFrame.lookAt(Layout.SpawnPosition + Vector3.new(0, 18, 34), tree + Vector3.new(0, 50, 0)),
			time = 4,
		},
	}
	local skipped = false
	local connection = UserInputService.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if
			t == Enum.UserInputType.MouseButton1
			or t == Enum.UserInputType.Touch
			or t == Enum.UserInputType.Keyboard
			or t == Enum.UserInputType.Gamepad1
		then
			skipped = true
		end
	end)
	task.delay(0.8, function()
		UIKit.tween(title, 1.2, { TextTransparency = 0, TextStrokeTransparency = 0.4 })
		task.wait(0.6)
		UIKit.tween(subtitle, 1.2, { TextTransparency = 0 })
	end)
	for _, shot in shots do
		if skipped then
			break
		end
		camera.CFrame = shot.from
		local tween = TweenService:Create(
			camera,
			TweenInfo.new(shot.time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ CFrame = shot.to }
		)
		tween:Play()
		local started = os.clock()
		while os.clock() - started < shot.time and not skipped do
			task.wait()
		end
		tween:Cancel()
	end
	connection:Disconnect()
	camera.CameraType = previousType
	camera.CameraType = Enum.CameraType.Custom
	UIKit.tween(top, 0.5, { Position = UDim2.new(0, 0, -0.12, 0) })
	UIKit.tween(bottom, 0.5, { Position = UDim2.new(0, 0, 1.12, 0) })
	UIKit.tween(title, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
	UIKit.tween(subtitle, 0.4, { TextTransparency = 1 })
	task.wait(0.55)
	gui:Destroy()
	playing = false
end

function IntroController.init(reg: any)
	registry = reg
end

function IntroController.start()
	registry.StateController.Ready:Connect(function(profile)
		-- Brand-new players get the flyover once.
		if
			profile.tutorial == 1
			and (profile.stats.sessions or 0) <= 1
			and (profile.stats.collected or 0) == 0
		then
			task.wait(0.8)
			IntroController.play()
		end
	end)
end

return IntroController
