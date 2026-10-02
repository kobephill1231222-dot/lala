--!strict
-- Curses that roam the Cursed Forest. Rewards scale with the defeating player's income so
-- combat stays worthwhile at every stage of progression.

export type EnemyDef = {
	id: string,
	name: string,
	maxHealth: number,
	walkSpeed: number,
	hipHeight: number,
	damage: number,
	attackRange: number,
	attackWindup: number,
	attackCooldown: number,
	aggroRange: number,
	rewardEnergy: number,
	rewardIncomeSeconds: number,
	sealChance: number,
	sealAmount: number,
	maxAlive: number,
	respawnDelay: number,
	scale: number,
}

local Enemies = {}

Enemies.List = {
	{
		id = "gloomling",
		name = "Gloomling",
		maxHealth = 60,
		walkSpeed = 10,
		hipHeight = 2.2,
		damage = 7,
		attackRange = 5.5,
		attackWindup = 0.55,
		attackCooldown = 1.6,
		aggroRange = 38,
		rewardEnergy = 18,
		rewardIncomeSeconds = 10,
		sealChance = 0.1,
		sealAmount = 1,
		maxAlive = 6,
		respawnDelay = 4,
		scale = 1,
	},
	{
		id = "wailer",
		name = "Wailing Mask",
		maxHealth = 240,
		walkSpeed = 12,
		hipHeight = 3.4,
		damage = 13,
		attackRange = 7,
		attackWindup = 0.7,
		attackCooldown = 2.0,
		aggroRange = 46,
		rewardEnergy = 70,
		rewardIncomeSeconds = 30,
		sealChance = 0.3,
		sealAmount = 1,
		maxAlive = 3,
		respawnDelay = 10,
		scale = 1.2,
	},
	{
		id = "brute",
		name = "Hollow Brute",
		maxHealth = 1500,
		walkSpeed = 8,
		hipHeight = 4.2,
		damage = 26,
		attackRange = 10,
		attackWindup = 1.0,
		attackCooldown = 2.8,
		aggroRange = 50,
		rewardEnergy = 350,
		rewardIncomeSeconds = 120,
		sealChance = 1,
		sealAmount = 3,
		maxAlive = 1,
		respawnDelay = 45,
		scale = 1.9,
	},
} :: { EnemyDef }

Enemies.ById = {} :: { [string]: EnemyDef }
for _, def in Enemies.List do
	Enemies.ById[def.id] = def
end

-- A player must deal at least this share of a curse's health to receive its reward.
Enemies.MinContributionShare = 0.12

return Enemies
