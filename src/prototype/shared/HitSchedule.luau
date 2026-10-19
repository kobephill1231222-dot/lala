--!strict
-- The one production schedule a placed Sorcerer runs on. Shared by the server (which credits
-- Cash from it) and the client (which plays a strike on exactly the same timestamps), so a
-- hit the player sees is always a hit that was paid, and the reverse.
--
-- Time is cut into beats. Beat k lands at `placedAt + k * beat` (k = 1, 2, ...). Normally a
-- beat is one hit. When hits come faster than a strike can be drawn (MinBeatSeconds), a beat
-- groups `hitsPerBeat` hits into one combo strike worth all of them.
--
-- The Reward Chest stores beats after `fromBeat`, up to `capBeats` of them. While it's full the
-- Sorcerer rests and nothing more is credited. Collecting pays what's stored and moves
-- `fromBeat` to the current beat.

export type Post = {
	placedAt: number,
	beat: number, -- seconds between strikes
	hitsPerBeat: number,
	valuePerBeat: number,
	fromBeat: number, -- beats up to and including this one are collected (or were lost while full)
	capBeats: number,
}

local HitSchedule = {}

-- Tiny slack so a timestamp computed as placedAt + k * beat counts as beat k, not k - 1.
local EPS = 1e-6

-- How many hits share one strike, so strikes are at least `minBeat` seconds apart.
function HitSchedule.combo(hitInterval: number, minBeat: number): number
	if hitInterval <= 0 then
		return 1
	end
	return math.max(1, math.ceil(minBeat / hitInterval - EPS))
end

function HitSchedule.capacityBeats(beat: number, storageSeconds: number): number
	return math.max(1, math.floor(storageSeconds / beat + EPS))
end

function HitSchedule.new(
	placedAt: number,
	hitInterval: number,
	valuePerHit: number,
	minBeat: number,
	storageSeconds: number
): Post
	local hits = HitSchedule.combo(hitInterval, minBeat)
	local beat = hitInterval * hits
	return {
		placedAt = placedAt,
		beat = beat,
		hitsPerBeat = hits,
		valuePerBeat = valuePerHit * hits,
		fromBeat = 0,
		capBeats = HitSchedule.capacityBeats(beat, storageSeconds),
	}
end

-- Beats that have landed by time t (0 before the first).
function HitSchedule.beatsAt(post: Post, t: number): number
	if t <= post.placedAt then
		return 0
	end
	return math.floor((t - post.placedAt) / post.beat + EPS)
end

function HitSchedule.beatTime(post: Post, k: number): number
	return post.placedAt + k * post.beat
end

-- Whether beat k pays into the chest (false once the chest would already be full).
function HitSchedule.isCredited(post: Post, k: number): boolean
	return k > post.fromBeat and k <= post.fromBeat + post.capBeats
end

-- Beats waiting in the chest at time t.
function HitSchedule.stored(post: Post, t: number): number
	return math.clamp(HitSchedule.beatsAt(post, t) - post.fromBeat, 0, post.capBeats)
end

function HitSchedule.storedValue(post: Post, t: number): number
	return HitSchedule.stored(post, t) * post.valuePerBeat
end

function HitSchedule.isFull(post: Post, t: number): boolean
	return HitSchedule.stored(post, t) >= post.capBeats
end

-- Time the chest fills, if nobody collects.
function HitSchedule.fullAt(post: Post): number
	return HitSchedule.beatTime(post, post.fromBeat + post.capBeats)
end

-- Pays out the chest at time t. Returns (beats, Cash) and updates the post.
function HitSchedule.collect(post: Post, t: number): (number, number)
	local beats = HitSchedule.stored(post, t)
	post.fromBeat = math.max(post.fromBeat, HitSchedule.beatsAt(post, t))
	return beats, beats * post.valuePerBeat
end

-- Cash per second while working.
function HitSchedule.income(post: Post): number
	return post.valuePerBeat / post.beat
end

-- Offline vault: what one absence pays, given income per second. Capped at the vault size and
-- paid once per absence (the caller moves its "last seen" timestamp forward afterwards).
function HitSchedule.offlinePayout(incomePerSecond: number, awaySeconds: number, vaultSeconds: number): number
	if incomePerSecond <= 0 or awaySeconds <= 0 then
		return 0
	end
	return math.floor(incomePerSecond * math.min(awaySeconds, vaultSeconds))
end

-- Post fields as instance attributes, so clients can follow the same schedule.
local FIELDS = { "placedAt", "beat", "hitsPerBeat", "valuePerBeat", "fromBeat", "capBeats" }
local ATTRIBUTES = {
	placedAt = "PlacedAt",
	beat = "Beat",
	hitsPerBeat = "HitsPerBeat",
	valuePerBeat = "ValuePerBeat",
	fromBeat = "FromBeat",
	capBeats = "CapBeats",
}
HitSchedule.Attributes = ATTRIBUTES

function HitSchedule.write(post: Post, inst: Instance)
	for _, field in FIELDS do
		inst:SetAttribute(ATTRIBUTES[field], (post :: any)[field])
	end
end

function HitSchedule.read(inst: Instance): Post?
	local post: { [string]: number } = {}
	for _, field in FIELDS do
		local value = inst:GetAttribute(ATTRIBUTES[field])
		if type(value) ~= "number" then
			return nil
		end
		post[field] = value
	end
	if post.beat <= 0 then
		return nil
	end
	return post :: any
end

return HitSchedule
