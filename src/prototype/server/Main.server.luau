--!strict
-- Prototype server. Builds the courtyard if the place doesn't have it, then runs the one
-- training post: it owns the hit schedule (written to the Post's attributes for clients),
-- credits Cash only from that schedule, and pays the Reward Chest out at the farm (A1).
-- No saving: this place is for reviewing the look and feel, not the economy.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RateLimiter = require(Shared.Util.RateLimiter)
local Prototype = ReplicatedStorage:WaitForChild("Prototype")
local HitSchedule = require(Prototype.HitSchedule)
local PrototypeConfig = require(Prototype.PrototypeConfig)
local Atmosphere = require(ServerScriptService:WaitForChild("Map"):WaitForChild("Atmosphere"))
local Courtyard = require(script.Parent:WaitForChild("Courtyard"))

if not workspace:FindFirstChild(Courtyard.Name) then
	Courtyard.build(workspace)
end
Atmosphere.apply(Lighting)

local yard = workspace:WaitForChild(Courtyard.Name)
local postModel = yard:WaitForChild("Post") :: Model
local chestBody = yard:WaitForChild("Chest"):WaitForChild("Body") :: BasePart
local pad = yard:WaitForChild("CollectPad") :: BasePart
local board = yard:WaitForChild("ReviewBoard"):WaitForChild("Board") :: BasePart

local notify = ReplicatedStorage:FindFirstChild("PrototypeNotify") :: RemoteEvent?
if not notify then
	local remote = Instance.new("RemoteEvent")
	remote.Name = "PrototypeNotify"
	remote.Parent = ReplicatedStorage
	notify = remote
end
local Notify = notify :: RemoteEvent

local state = {
	preset = PrototypeConfig.DefaultPreset,
	post = nil :: HitSchedule.Post?,
	ownerId = nil :: number?,
}
local cash: { [number]: number } = {}
local limiter = RateLimiter.new(2, 3)

local function now(): number
	return workspace:GetServerTimeNow()
end

local function place(t: number)
	local preset = PrototypeConfig.Presets[state.preset]
	local post = HitSchedule.new(
		t,
		preset.hitInterval,
		preset.valuePerHit,
		PrototypeConfig.MinBeatSeconds,
		PrototypeConfig.ChestStorageSeconds
	)
	state.post = post
	HitSchedule.write(post, postModel)
	postModel:SetAttribute("Preset", state.preset)
	postModel:SetAttribute("HitInterval", preset.hitInterval)
	postModel:SetAttribute("ValuePerHit", preset.valuePerHit)
end

local function owner(): Player?
	for _, player in Players:GetPlayers() do
		if player.UserId == state.ownerId then
			return player
		end
	end
	return nil
end

local function setOwner(player: Player?)
	state.ownerId = if player then player.UserId else nil
	postModel:SetAttribute("OwnerId", if player then player.UserId else 0)
	postModel:SetAttribute("OwnerName", if player then player.DisplayName else "")
	if player then
		-- The Sorcerer starts working when its owner arrives.
		place(now())
	end
end

local function inRange(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	return (root.CFrame.Position - chestBody.CFrame.Position).Magnitude <= PrototypeConfig.CollectRange
end

-- Pays the chest to `player`. Quiet when it's a pad touch with nothing stored.
local function collect(player: Player, quiet: boolean?): (boolean, string?)
	local post = state.post
	if not post or player.UserId ~= state.ownerId then
		return false, "This isn't your chest."
	end
	if not inRange(player) then
		return false, "Walk up to the Reward Chest to collect."
	end
	local t = now()
	if not limiter:allow(player.UserId, t) then
		return false, nil
	end
	local beats, value = HitSchedule.collect(post, t)
	HitSchedule.write(post, postModel)
	if beats <= 0 then
		if not quiet then
			Notify:FireClient(player, "Empty", {})
		end
		return true, nil
	end
	cash[player.UserId] = (cash[player.UserId] or 0) + value
	player:SetAttribute("Cash", cash[player.UserId])
	Notify:FireAllClients("Collected", {
		userId = player.UserId,
		cash = value,
		hits = beats * post.hitsPerBeat,
	})
	return true, nil
end

local function onPrompt(player: Player)
	local ok, message = collect(player)
	if not ok and message then
		Notify:FireClient(player, "Error", { message = message })
	end
end

(chestBody:WaitForChild("Prompt") :: ProximityPrompt).Triggered:Connect(onPrompt)

pad.Touched:Connect(function(hit: BasePart)
	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if player and player.UserId == state.ownerId then
		collect(player, true)
	end
end)

-- Review switches ------------------------------------------------------------------------

local function reviewer(player: Player): boolean
	return player.UserId == state.ownerId and limiter:allow(player.UserId, now())
end

local fast = board:WaitForChild("FastPromptAnchor"):WaitForChild("FastPrompt") :: ProximityPrompt
fast.Triggered:Connect(function(player: Player)
	if not reviewer(player) then
		return
	end
	-- Bank what's stored first so switching never loses Cash, then re-place the Sorcerer.
	local post = state.post
	if post then
		local beats, value = HitSchedule.collect(post, now())
		if beats > 0 then
			cash[player.UserId] = (cash[player.UserId] or 0) + value
			player:SetAttribute("Cash", cash[player.UserId])
		end
	end
	state.preset = if state.preset == "Fast" then "Normal" else "Fast"
	place(now())
	fast.ActionText = if state.preset == "Fast" then "Normal Sorcerer" else "Fast Sorcerer"
	Notify:FireAllClients("Preset", { preset = state.preset })
end)

local fill = board:WaitForChild("FillPromptAnchor"):WaitForChild("FillPrompt") :: ProximityPrompt
fill.Triggered:Connect(function(player: Player)
	local post = state.post
	if not post or not reviewer(player) then
		return
	end
	-- Count the chest as full right now: the Sorcerer rests until it's collected.
	post.fromBeat = HitSchedule.beatsAt(post, now()) - post.capBeats
	HitSchedule.write(post, postModel)
	Notify:FireAllClients("Filled", {})
end)

-- Players ---------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	cash[player.UserId] = cash[player.UserId] or 0
	player:SetAttribute("Cash", cash[player.UserId])
	if not owner() then
		setOwner(player)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	limiter:remove(player.UserId)
	if player.UserId == state.ownerId then
		local nextOwner: Player? = nil
		for _, other in Players:GetPlayers() do
			if other.UserId ~= player.UserId then
				nextOwner = other
				break
			end
		end
		setOwner(nextOwner)
	end
end)

print("[JJK Farm prototype] Training post ready")
