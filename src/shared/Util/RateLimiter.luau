--!strict
-- Token-bucket rate limiter keyed by player (or any key).

local RateLimiter = {}
RateLimiter.__index = RateLimiter

type Bucket = { tokens: number, last: number }

export type RateLimiter = typeof(setmetatable(
	{} :: { rate: number, burst: number, buckets: { [any]: Bucket } },
	RateLimiter
))

-- rate: tokens refilled per second; burst: bucket size.
function RateLimiter.new(rate: number, burst: number): RateLimiter
	return setmetatable({ rate = rate, burst = burst, buckets = {} }, RateLimiter)
end

function RateLimiter.allow(self: RateLimiter, key: any, now: number, cost: number?): boolean
	local price = cost or 1
	local bucket = self.buckets[key]
	if not bucket then
		bucket = { tokens = self.burst, last = now }
		self.buckets[key] = bucket
	end
	local elapsed = math.max(0, now - bucket.last)
	bucket.tokens = math.min(self.burst, bucket.tokens + elapsed * self.rate)
	bucket.last = now
	if bucket.tokens >= price then
		bucket.tokens -= price
		return true
	end
	return false
end

function RateLimiter.remove(self: RateLimiter, key: any)
	self.buckets[key] = nil
end

return RateLimiter
