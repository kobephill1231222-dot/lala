--!strict
-- Session-locked profile persistence on top of a GlobalDataStore-like object.
--
-- Record layout: { data = <profile>, lock = { job = string, t = number }?, meta = {...} }
--
-- Guarantees:
--  * A profile is only ever written by the server holding its session lock.
--  * A failed or corrupt load never results in a write (no default data over real data).
--  * A lock left by a crashed server is taken over once it goes stale, or after retries.

export type Store = {
	UpdateAsync: (self: any, key: string, transform: (any) -> any) -> any,
}

export type Options = {
	jobId: string,
	staleSeconds: number,
	retries: number,
	retryDelay: number,
	now: () -> number,
	wait: (number) -> (),
}

local ProfileStore = {}
ProfileStore.__index = ProfileStore

export type ProfileStore = typeof(setmetatable({} :: { store: Store, options: Options }, ProfileStore))

function ProfileStore.new(store: Store, options: Options): ProfileStore
	return setmetatable({ store = store, options = options }, ProfileStore)
end

-- Returns ("ok", data | nil) on success (nil data = brand-new player), otherwise ("error", reason).
function ProfileStore.load(self: ProfileStore, key: string): (string, any)
	local opts = self.options
	local lastReason = "unknown"
	for attempt = 1, opts.retries do
		local steal = attempt == opts.retries
		local status, data, reason = "error", nil, "no response"
		local ok, err = pcall(function()
			self.store:UpdateAsync(key, function(old: any)
				if old ~= nil and type(old) ~= "table" then
					status, reason = "corrupt", "record is not a table"
					return nil -- never overwrite something we don't understand
				end
				local record = old or {}
				local lock = record.lock
				local now = opts.now()
				if
					type(lock) == "table"
					and lock.job ~= opts.jobId
					and type(lock.t) == "number"
					and now - lock.t < opts.staleSeconds
					and not steal
				then
					status, reason = "locked", "session locked by " .. tostring(lock.job)
					return nil
				end
				record.lock = { job = opts.jobId, t = now }
				status, data = "ok", record.data
				return record
			end)
		end)
		if not ok then
			status, reason = "error", tostring(err)
		end
		if status == "ok" then
			return "ok", data
		elseif status == "corrupt" then
			return "error", reason
		end
		lastReason = reason
		if attempt < opts.retries then
			opts.wait(opts.retryDelay * (if status == "error" then attempt else 1))
		end
	end
	return "error", lastReason
end

-- Writes `data`. Returns "ok", "lost" (another server owns the session) or "error".
function ProfileStore.save(self: ProfileStore, key: string, data: any, release: boolean, retries: number?): (string, string?)
	local opts = self.options
	local lastReason = "unknown"
	for attempt = 1, retries or 3 do
		local status, reason = "error", "no response"
		local ok, err = pcall(function()
			self.store:UpdateAsync(key, function(old: any)
				if type(old) ~= "table" then
					status, reason = "lost", "record missing or corrupt"
					return nil
				end
				local lock = old.lock
				if type(lock) ~= "table" or lock.job ~= opts.jobId then
					status, reason = "lost", "session lock is held elsewhere"
					return nil
				end
				local now = opts.now()
				local meta = if type(old.meta) == "table" then old.meta else {}
				old.data = data
				old.lock = if release then nil else { job = opts.jobId, t = now }
				old.meta = { saves = (tonumber(meta.saves) or 0) + 1, updated = now }
				status = "ok"
				return old
			end)
		end)
		if not ok then
			status, reason = "error", tostring(err)
		end
		if status == "ok" or status == "lost" then
			return status, reason
		end
		lastReason = reason
		if attempt < (retries or 3) then
			opts.wait(2 ^ attempt)
		end
	end
	return "error", lastReason
end

-- Drops our lock without touching data (player left before their load finished).
function ProfileStore.releaseLock(self: ProfileStore, key: string)
	local opts = self.options
	pcall(function()
		self.store:UpdateAsync(key, function(old: any)
			if type(old) ~= "table" or type(old.lock) ~= "table" or old.lock.job ~= opts.jobId then
				return nil
			end
			old.lock = nil
			return old
		end)
	end)
end

return ProfileStore
