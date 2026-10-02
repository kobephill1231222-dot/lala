--!strict
-- The Cursed Forest: spawns curses while players are nearby, runs their AI, validates player
-- techniques (cooldowns, zone, hit shapes all computed here) and pays out rewards to every
-- player who contributed meaningfully to a kill. Dojo dummies reuse the same hit path.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Abilities = require(Shared.Config.Abilities)
local Enemies = require(Shared.Config.Enemies)
local Layout = require(Shared.Config.MapLayout)
local Actions = require(Shared.Rules.Actions)
local CombatMath = require(Shared.Rules.CombatMath)
local Economy = require(Shared.Rules.Economy)
local RateLimiter = require(Shared.Util.RateLimiter)
local CurseModels = require(Shared.Visuals.CurseModels)

type Enemy = {
	def: Enemies.EnemyDef,
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	health: number,
	home: Vector3,
	contributions: { [Player]: number },
	state: "idle" | "windup" | "dead",
	attackAt: number,
	nextAttack: number,
	nextWander: number,
	attackTarget: Humanoid?,
	leashUntil: number,
}

local CombatService = {}

local services: any
local enemies: { [Model]: Enemy } = {}
local nextSpawn: { [string]: number } = {}
local spawnPoints: { Vector3 } = {}
local dummies: { Model } = {}
local folder: Folder
local abilityLimiter = RateLimiter.new(12, 12)
local rng = Random.new()
local lastActive = -math.huge

local AI_INTERVAL = 0.15
local IDLE_DESPAWN = 30
local ZONE_MARGIN = 10
local LEASH_RANGE = 75

local function aliveCount(defId: string): number
	local n = 0
	for _, enemy in enemies do
		if enemy.def.id == defId and enemy.state ~= "dead" then
			n += 1
		end
	end
	return n
end

local function inZoneWithMargin(position: Vector3): boolean
	local d = position - Layout.ForestZoneCenter
	local size = Layout.ForestZoneSize
	return math.abs(d.X) <= size.X / 2 + ZONE_MARGIN and math.abs(d.Z) <= size.Z / 2 + ZONE_MARGIN
end

type Fighter = { player: Player, root: BasePart, humanoid: Humanoid }

local function fightersInForest(): { Fighter }
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if
			root
			and root:IsA("BasePart")
			and humanoid
			and humanoid.Health > 0
			and inZoneWithMargin(root.Position)
		then
			table.insert(list, { player = player, root = root, humanoid = humanoid })
		end
	end
	return list
end

local function pickSpawnPoint(fighters: { Fighter }): Vector3?
	for _ = 1, 8 do
		local point = spawnPoints[rng:NextInteger(1, #spawnPoints)]
		local clear = true
		for _, fighter in fighters do
			if (fighter.root.Position - point).Magnitude < 22 then
				clear = false
				break
			end
		end
		if clear then
			return point
		end
	end
	return nil
end

local function spawnEnemy(def: Enemies.EnemyDef, point: Vector3)
	local model = CurseModels.build(def.id, point)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	model:SetAttribute("Enemy", def.id)
	model:SetAttribute("Health", def.maxHealth)
	model:SetAttribute("MaxHealth", def.maxHealth)
	model:SetAttribute("Telegraph", false)
	model.Parent = folder
	root:SetNetworkOwner(nil)
	humanoid.WalkSpeed = def.walkSpeed
	enemies[model] = {
		def = def,
		model = model,
		root = root,
		humanoid = humanoid,
		health = def.maxHealth,
		home = point,
		contributions = {},
		state = "idle",
		attackAt = 0,
		nextAttack = 0,
		nextWander = 0,
		attackTarget = nil,
		leashUntil = 0,
	}
end

local function despawnAll()
	for model in enemies do
		model:Destroy()
	end
	table.clear(enemies)
	table.clear(nextSpawn)
end

local function spawnTick()
	local t = os.clock()
	local fighters = fightersInForest()
	if #fighters > 0 then
		lastActive = t
	elseif t - lastActive > IDLE_DESPAWN then
		if next(enemies) then
			despawnAll()
		end
		return
	end
	if #spawnPoints == 0 then
		return
	end
	for _, def in Enemies.List do
		if aliveCount(def.id) < def.maxAlive and t >= (nextSpawn[def.id] or 0) then
			local point = pickSpawnPoint(fighters)
			if point then
				spawnEnemy(def, point)
				-- Stagger arrivals so a fresh forest fills up over a few seconds.
				nextSpawn[def.id] = t + 1.5
			end
		end
	end
end

local function nearestFighter(enemy: Enemy, fighters: { Fighter }): (Fighter?, number)
	local best, bestDist = nil, math.huge
	for _, fighter in fighters do
		local dist = (fighter.root.Position - enemy.root.Position).Magnitude
		if dist < bestDist and dist <= enemy.def.aggroRange then
			best, bestDist = fighter, dist
		end
	end
	return best, bestDist
end

local function think(enemy: Enemy, fighters: { Fighter }, t: number)
	if enemy.state == "dead" then
		return
	end
	local def = enemy.def
	local position = enemy.root.Position
	if enemy.state == "windup" then
		if t >= enemy.attackAt then
			enemy.state = "idle"
			enemy.model:SetAttribute("Telegraph", false)
			enemy.nextAttack = t + def.attackCooldown
			local target = enemy.attackTarget
			local targetRoot = target and target.Parent and target.Parent:FindFirstChild("HumanoidRootPart")
			services.Remotes.Effect:FireAllClients(
				"CurseStrike",
				{ position = position, radius = def.attackRange, enemy = def.id }
			)
			if target and targetRoot and targetRoot:IsA("BasePart") and target.Health > 0 then
				if (targetRoot.Position - position).Magnitude <= def.attackRange + 3 then
					target:TakeDamage(def.damage)
				end
			end
		end
		return
	end

	-- Stay near home; drop aggro briefly if dragged too far.
	if (position - enemy.home).Magnitude > LEASH_RANGE or not inZoneWithMargin(position) then
		enemy.leashUntil = t + 3
		enemy.humanoid:MoveTo(enemy.home)
		return
	end

	local fighter, distance = nil, math.huge
	if t >= enemy.leashUntil then
		fighter, distance = nearestFighter(enemy, fighters)
	end
	if fighter then
		if distance <= def.attackRange and t >= enemy.nextAttack then
			enemy.state = "windup"
			enemy.attackAt = t + def.attackWindup
			enemy.attackTarget = fighter.humanoid
			enemy.model:SetAttribute("Telegraph", true)
			enemy.humanoid:MoveTo(position)
		elseif distance > def.attackRange * 0.7 then
			local toward = (fighter.root.Position - position)
			local stop = fighter.root.Position - toward.Unit * def.attackRange * 0.55
			enemy.humanoid:MoveTo(stop)
		end
	elseif t >= enemy.nextWander then
		enemy.nextWander = t + rng:NextNumber(3, 6)
		local offset = Vector3.new(rng:NextNumber(-18, 18), 0, rng:NextNumber(-18, 18))
		enemy.humanoid:MoveTo(enemy.home + offset)
	end
end

local function rewardContributors(enemy: Enemy, killer: Player)
	local def = enemy.def
	local threshold = def.maxHealth * Enemies.MinContributionShare
	for player, damage in enemy.contributions do
		if player.Parent and (damage >= threshold or player == killer) then
			local session = services.DataService.getSession(player)
			if session then
				local energy = Economy.combatReward(def.id, session.profile)
				local seals = if rng:NextNumber() < def.sealChance then def.sealAmount else 0
				Actions.grantReward(session.profile, energy, seals)
				session.profile.stats.kills += 1
				services.Remotes.Notify:FireClient(
					player,
					"Kill",
					{ name = def.name, energy = energy, seals = seals }
				)
				services.GameService.tutorialEvent(player, session, "kill")
				services.StateService.markDirty(player)
			end
		end
	end
end

local function killEnemy(enemy: Enemy, killer: Player)
	enemy.state = "dead"
	enemy.model:SetAttribute("Dead", true)
	enemy.model:SetAttribute("Telegraph", false)
	enemy.humanoid:MoveTo(enemy.root.Position)
	services.Remotes.Effect:FireAllClients(
		"CurseDeath",
		{ position = enemy.root.Position, enemy = enemy.def.id }
	)
	rewardContributors(enemy, killer)
	nextSpawn[enemy.def.id] = math.max(nextSpawn[enemy.def.id] or 0, os.clock() + enemy.def.respawnDelay)
	local model = enemy.model
	task.delay(1.1, function()
		enemies[model] = nil
		model:Destroy()
	end)
end

local function onAbility(player: Player, abilityId: any, aimInput: any)
	if not abilityLimiter:allow(player, os.clock()) then
		return
	end
	if type(abilityId) ~= "string" then
		return
	end
	local ability = Abilities.ById[abilityId]
	local aim = CombatMath.sanitizeAim(aimInput)
	if not ability or not aim then
		return
	end
	local session = services.DataService.getSession(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not session or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return
	end
	local origin = root.Position
	local inForest = Layout.inForest(origin)
	local inDojo = not inForest and Layout.inDojo(origin)
	if not inForest and not inDojo then
		return
	end
	local t = os.clock()
	local ready = session.cooldowns[abilityId]
	if ready and t < ready - Abilities.CooldownTolerance then
		return
	end
	session.cooldowns[abilityId] = t + ability.cooldown

	services.Remotes.Effect:FireAllClients("Cast", {
		userId = player.UserId,
		ability = abilityId,
		origin = origin,
		direction = aim,
	})

	local damage = Economy.abilityDamage(session.profile, abilityId)
	local hits = {}
	if inForest then
		for _, enemy in enemies do
			if enemy.state ~= "dead" then
				local radius = 2 * enemy.def.scale
				if
					CombatMath.hits(
						ability.shape,
						origin,
						aim,
						ability.range,
						ability.width,
						enemy.root.Position,
						radius
					)
				then
					local dealt = math.min(damage, enemy.health)
					enemy.health -= dealt
					enemy.contributions[player] = (enemy.contributions[player] or 0) + dealt
					enemy.model:SetAttribute("Health", enemy.health)
					table.insert(hits, { position = enemy.root.Position, damage = damage })
					if enemy.health <= 0 then
						killEnemy(enemy, player)
					end
				end
			end
		end
	else
		for _, dummy in dummies do
			local primary = dummy.PrimaryPart
			if
				primary
				and CombatMath.hits(
					ability.shape,
					origin,
					aim,
					ability.range,
					ability.width,
					primary.Position,
					2
				)
			then
				table.insert(hits, { position = primary.Position, damage = damage, dummy = dummy.Name })
			end
		end
	end
	if #hits > 0 then
		services.Remotes.Effect:FireClient(player, "Hits", { hits = hits, ability = abilityId })
	end
end

function CombatService.init(registry: any)
	services = registry
end

function CombatService.start()
	folder = Instance.new("Folder")
	folder.Name = "Curses"
	folder.Parent = workspace

	local map = workspace:WaitForChild("CurseboundMap")
	local forest = map:WaitForChild("Forest")
	local spawnFolder = forest:FindFirstChild("Spawns")
	if spawnFolder then
		for _, part in spawnFolder:GetChildren() do
			if part:IsA("BasePart") then
				table.insert(spawnPoints, part.Position)
			end
		end
	end
	if #spawnPoints == 0 then
		for x = -2, 2 do
			for z = -2, 2 do
				table.insert(spawnPoints, Layout.ForestZoneCenter + Vector3.new(x * 28, 0, z * 22))
			end
		end
	end
	local dojo = map:FindFirstChild("Dojo")
	local dummyFolder = dojo and dojo:FindFirstChild("Dummies")
	if dummyFolder then
		for _, dummy in dummyFolder:GetChildren() do
			if dummy:IsA("Model") then
				table.insert(dummies, dummy)
			end
		end
	end

	services.Remotes.Ability.OnServerEvent:Connect(onAbility)
	Players.PlayerRemoving:Connect(function(player)
		abilityLimiter:remove(player)
		for _, enemy in enemies do
			enemy.contributions[player] = nil
		end
	end)

	local aiElapsed, spawnElapsed = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		aiElapsed += dt
		spawnElapsed += dt
		if spawnElapsed >= 1 then
			spawnElapsed = 0
			spawnTick()
		end
		if aiElapsed >= AI_INTERVAL then
			aiElapsed = 0
			if next(enemies) then
				local fighters = fightersInForest()
				local t = os.clock()
				for _, enemy in enemies do
					think(enemy, fighters, t)
				end
			end
		end
	end)
end

return CombatService
