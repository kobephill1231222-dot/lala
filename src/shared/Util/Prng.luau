--!strict
-- Small deterministic PRNG (LCG) with the same method names as Roblox's Random.
-- Used for map generation (identical results in Studio and in the offline Lune bake) and tests.

local Prng = {}
Prng.__index = Prng

export type Prng = typeof(setmetatable({} :: { state: number }, Prng))

local MOD = 4294967296 -- 2^32

function Prng.new(seed: number?): Prng
	local s = math.floor(math.abs(seed or 1)) % MOD
	local self = setmetatable({ state = s }, Prng)
	-- Warm up so nearby seeds diverge quickly.
	for _ = 1, 4 do
		self:NextNumber()
	end
	return self
end

function Prng.NextNumber(self: Prng, min: number?, max: number?): number
	self.state = (self.state * 1664525 + 1013904223) % MOD
	local unit = self.state / MOD
	if min and max then
		return min + (max - min) * unit
	end
	return unit
end

function Prng.NextInteger(self: Prng, min: number, max: number): number
	return min + math.floor(self:NextNumber() * (max - min + 1))
end

function Prng.Pick<T>(self: Prng, list: { T }): T
	return list[self:NextInteger(1, #list)]
end

return Prng
