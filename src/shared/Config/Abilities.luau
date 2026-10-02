--!strict
-- Player techniques usable in the Cursed Forest (and on the Dojo practice dummies).
-- Hit detection runs on the server using these numbers; clients only play effects.

export type AbilityDef = {
	id: string,
	name: string,
	keyLabel: string,
	cooldown: number,
	damageScale: number,
	shape: "Arc" | "Radius" | "Line",
	range: number,
	width: number, -- arc: minimum facing dot product; line: half-width in studs
	color: Color3,
	order: number,
}

local Abilities = {}

Abilities.List = {
	{
		id = "strike",
		name = "Cursed Strike",
		keyLabel = "1",
		cooldown = 0.45,
		damageScale = 1,
		shape = "Arc",
		range = 12,
		width = 0.1,
		color = Color3.fromRGB(190, 120, 255),
		order = 1,
	},
	{
		id = "lance",
		name = "Spirit Lance",
		keyLabel = "2",
		cooldown = 3,
		damageScale = 1.7,
		shape = "Line",
		range = 46,
		width = 4.5,
		color = Color3.fromRGB(120, 220, 255),
		order = 2,
	},
	{
		id = "burst",
		name = "Violet Burst",
		keyLabel = "3",
		cooldown = 6,
		damageScale = 2.4,
		shape = "Radius",
		range = 17,
		width = 0,
		color = Color3.fromRGB(220, 90, 255),
		order = 3,
	},
} :: { AbilityDef }

Abilities.ById = {} :: { [string]: AbilityDef }
for _, def in Abilities.List do
	Abilities.ById[def.id] = def
end

Abilities.BaseDamage = 10
-- Small allowance for latency when the server checks cooldowns.
Abilities.CooldownTolerance = 0.12

return Abilities
