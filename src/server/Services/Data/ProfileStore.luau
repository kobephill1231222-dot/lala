--!strict
-- Session-locked profile persistence on top of a GlobalDataStore-like object.
--
-- Record layout: { data = <profile>?, lock = { job = string, t = number }?, meta = {...} }
--
-- The lock is a lease. The owning server renews it on every save (autosave runs well inside
-- the lease), and a lock is only ever taken from another server once its lease has expired
-- (`staleSeconds` without a renewal). There is no "take it anyway after N retries": a
-- server that is merely slow keeps its session, and a loading server waits or gives up.
--
-- To make the common case fast (player leaves server A and joins server B before A has
-- finished its release save), B asks A to release via `options.requestRelease` and retries.
--
-- Guarantees:
--  * A profile is only ever written by the server holding a live lease on it.
--  * A failed, corrupt, locked or newer-version load never results in a data write.
--  * The owning server can tell how long its lease is guaranteed (`leaseSeconds`).

export type Store = {
	UpdateAsync: (self: any, key: string, transform: (any) -> any) -> any,
}

export type Options = {
	jobId: string,
	staleSeconds: number, -- lease length
	retries: number,
	retryDelay: number,
	now: () -> number,
	wait: (number) -> (),
	maxVersion: number?, -- refuse data saved by a newer version of the game
	requestRelease: ((key: string, holder: string) -> ())?,
}

-- Load results:
--   "ok", data       data is nil only when the store has no profile for this key
--   "locked", reason another server holds a live lease
--   "corrupt", reason the record exists but isn't a record we understand (left untouched)
--   "newer", reason  saved by a newer game version (left untouched)
--   "error", reason  the store failed
export type LoadStatus = "ok" | "locked" | "corrupt" | "newer" | "error"

local ProfileStore = {}
ProfileStore.__index = ProfileStore

export type ProfileStore = typeof(setmetatable({} :: { store: Store, options: Options }, ProfileStore))

function ProfileStore.new(store: Store, options: Options): ProfileStore
	return setmetatable({ store = store, options = options }, ProfileStore)
end

local function leaseIsLive(lock: any, now: number, staleSeconds: number): boolean
	return type(lock) == "table" and type(lock.t) == "number" and now - lock.t < staleSeconds
end

function ProfileStore.load(self: ProfileStore, key: string): (LoadStatus, any)
	local opts = self.options
	local lastStatus: LoadStatus, lastReason: any = "error", "unknown"
	local askedRelease = false
	for attempt = 1, opts.retries do
		local status: LoadStatus, data, reason = "error", nil, "no response"
		local holder: string? = nil
		local ok, err = pcall(function()
			self.store:UpdateAsync(key, function(old: any)
				if old ~= nil and type(old) ~= "table" then
					status, reason = "corrupt", "record is not a table"
					return nil -- never overwrite something we don't understand
				end
				local record = old or {}
				local version = type(record.data) == "table" and record.data.version
				if opts.maxVersion and type(version) == "number" and version > opts.maxVersion then
					status, reason = "newer", "saved by data version " .. version
					return nil
				end
				local lock = record.lock
				local now = opts.now()
				if
					type(lock) == "table"
					and lock.job ~= opts.jobId
					and leaseIsLive(lock, now, opts.staleSeconds)
				then
					status, reason = "locked", "session leased by " .. tostring(lock.job)
					holder = tostring(lock.job)
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
		elseif status == "corrupt" or status == "newer" then
			return status, reason
		end
		lastStatus, lastReason = status, reason
		if status == "locked" and holder and not askedRelease and opts.requestRelease then
			askedRelease = true
			pcall(opts.requestRelease, key, holder)
		end
		if attempt < opts.retries then
			opts.wait(opts.retryDelay * (if status == "error" then 1 + (attempt - 1) * 0.5 else 1))
		end
	end
	return lastStatus, lastReason
end

-- Writes `data` and renews (or releases) the lease. Returns "ok", "lost" (this server no
-- longer holds the lease; nothing was written) or "error".
function ProfileStore.save(
	self: ProfileStore,
	key: string,
	data: any,
	release: boolean,
	retries: number?
): (string, string?)
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
				meta.saves = (tonumber(meta.saves) or 0) + 1
				meta.updated = now
				old.meta = meta
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

-- Drops our lock without touching data (player left before their load finished, or their
-- data was refused). With `quarantine`, also records why in the record's metadata so the
-- untouched data can be found and repaired by hand.
function ProfileStore.releaseLock(self: ProfileStore, key: string, quarantine: string?)
	local opts = self.options
	pcall(function()
		self.store:UpdateAsync(key, function(old: any)
			if type(old) ~= "table" then
				return nil
			end
			local mine = type(old.lock) == "table" and old.lock.job == opts.jobId
			if not mine and not quarantine then
				return nil
			end
			if mine then
				old.lock = nil
			end
			if quarantine then
				local meta = if type(old.meta) == "table" then old.meta else {}
				meta.quarantine = { reason = quarantine, t = opts.now(), job = opts.jobId }
				old.meta = meta
			end
			return old
		end)
	end)
end

return ProfileStore
