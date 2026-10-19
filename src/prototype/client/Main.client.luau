--!strict
-- Prototype client: wires the training post, the Reward Chest and the HUD to one frame loop
-- driven by server time, so every client sees each strike land on the same timestamp.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ChestView = require(script.Parent:WaitForChild("ChestView"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local Hud = require(script.Parent:WaitForChild("Hud"))
local TrainingView = require(script.Parent:WaitForChild("TrainingView"))

local yard = workspace:WaitForChild("TrainingCourtyard")
Hud.start(yard)
TrainingView.start(yard)
ChestView.start(yard)

local notify = ReplicatedStorage:WaitForChild("PrototypeNotify") :: RemoteEvent
notify.OnClientEvent:Connect(function(kind: string, payload: { [string]: any })
	local now = workspace:GetServerTimeNow()
	if kind == "Collected" then
		ChestView.burst(now)
		if payload.userId == Players.LocalPlayer.UserId then
			Hud.toast("Banked %s", now, "collect", payload.cash)
		end
	elseif kind == "Empty" then
		Hud.toast("Nothing in the chest yet", now)
	elseif kind == "Error" then
		Hud.toast(tostring(payload.message), now)
		Fx.sound("click")
	elseif kind == "Preset" then
		Hud.toast(
			if payload.preset == "Fast"
				then "Fast Sorcerer: hits now land in combos"
				else "Back to normal speed",
			now
		)
	elseif kind == "Filled" then
		Hud.toast("Chest filled for testing", now)
	end
end)

RunService.RenderStepped:Connect(function(dt: number)
	local now = workspace:GetServerTimeNow()
	TrainingView.step(now, dt)
	ChestView.step(now, dt)
	Fx.step(now)
	Hud.step(now, TrainingView.resting, ChestView.full)
end)
