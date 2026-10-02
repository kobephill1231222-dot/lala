--!nocheck
-- Persistence safety tests: session locking, retries, corrupt records, lock theft.
return function(ctx)
	local kit, sb = ctx.kit, ctx.sandbox
	local describe, it, expect = kit.describe, kit.it, kit.expect

	local ProfileStore = sb.requirePath("ServerScriptService/Server/Services/Data/ProfileStore")
	local MockDataStore = sb.requirePath("ServerScriptService/Server/Services/Data/MockDataStore")
	local Schema = sb.requirePath("ReplicatedStorage/Shared/Rules/ProfileSchema")

	local clock = 1000
	local waits = 0
	local function options(job)
		return {
			jobId = job,
			staleSeconds = 300,
			retries = 4,
			retryDelay = 1,
			now = function()
				return clock
			end,
			wait = function(seconds)
				waits += 1
				clock += seconds
			end,
		}
	end

	describe("ProfileStore", function()
		it("loads a new player as nil data and takes the session lock", function()
			local mock = MockDataStore.new()
			local store = ProfileStore.new(mock, options("A"))
			local status, data = store:load("p1")
			expect(status).toBe("ok")
			expect(data).toBe(nil)
			expect(mock.data.p1.lock.job).toBe("A")
		end)

		it("saves, releases, and lets the next server load the same data", function()
			local mock = MockDataStore.new()
			local a = ProfileStore.new(mock, options("A"))
			a:load("p1")
			local profile = Schema.new(clock)
			profile.cash = 1234
			expect((a:save("p1", profile, true))).toBe("ok")
			expect(mock.data.p1.lock).toBe(nil)
			local b = ProfileStore.new(mock, options("B"))
			local status, data = b:load("p1")
			expect(status).toBe("ok")
			expect(data.cash).toBe(1234)
			expect(mock.data.p1.lock.job).toBe("B")
		end)

		it("never takes a live lease, however many retries it makes", function()
			-- The reviewer's case: A holds the lease from t=1000; B retries for 12 s.
			local mock = MockDataStore.new()
			local a = ProfileStore.new(mock, options("A"))
			a:load("p1")
			a:save("p1", { cash = 5 }, false)
			waits = 0
			local opts = options("B")
			opts.retries = 5
			opts.retryDelay = 3
			local b = ProfileStore.new(mock, opts)
			local status = b:load("p1")
			expect(status).toBe("locked")
			expect(waits).toBe(4)
			expect(mock.data.p1.lock.job).toBe("A")
			-- A still owns the session and can keep saving.
			expect((a:save("p1", { cash = 6 }, false))).toBe("ok")
			expect(mock.data.p1.data.cash).toBe(6)
		end)

		it("takes over only once the lease has expired, and the old server can't write after", function()
			local mock = MockDataStore.new()
			local a = ProfileStore.new(mock, options("A"))
			a:load("p1")
			a:save("p1", { cash = 7 }, false)
			clock += 290
			local b = ProfileStore.new(mock, options("B"))
			expect((b:load("p1"))).toBe("locked") -- its retries take it to +293 s
			clock += 8 -- A hasn't renewed for 301 s: the lease is gone
			local status, data = b:load("p1")
			expect(status).toBe("ok")
			expect(data.cash).toBe(7)
			expect((a:save("p1", { cash = 0 }, false))).toBe("lost")
			expect(mock.data.p1.data.cash).toBe(7)
		end)

		it("asks the holder to release, then loads its latest data", function()
			local mock = MockDataStore.new()
			local a = ProfileStore.new(mock, options("A"))
			a:load("p1")
			a:save("p1", { cash = 1 }, false)
			local requests = 0
			local opts = options("B")
			opts.requestRelease = function(key, holder)
				requests += 1
				expect(key).toBe("p1")
				expect(holder).toBe("A")
				-- Server A's handler: final save with release.
				a:save("p1", { cash = 42 }, true)
			end
			local b = ProfileStore.new(mock, opts)
			local status, data = b:load("p1")
			expect(status).toBe("ok")
			expect(data.cash).toBe(42)
			expect(requests).toBe(1)
			expect(mock.data.p1.lock.job).toBe("B")
		end)

		it("renewing the lease on save keeps it alive past the stale window", function()
			local mock = MockDataStore.new()
			local a = ProfileStore.new(mock, options("A"))
			a:load("p1")
			for _ = 1, 5 do
				clock += 90 -- autosave interval
				expect((a:save("p1", { cash = 1 }, false))).toBe("ok")
			end
			local b = ProfileStore.new(mock, options("B"))
			expect((b:load("p1"))).toBe("locked")
		end)

		it("refuses data saved by a newer version without writing", function()
			local mock = MockDataStore.new()
			mock.data.p1 = { data = { version = 99, cash = 5 } }
			local opts = options("A")
			opts.maxVersion = 1
			local store = ProfileStore.new(mock, opts)
			expect((store:load("p1"))).toBe("newer")
			expect(mock.data.p1.lock).toBe(nil)
			expect(mock.data.p1.data.version).toBe(99)
		end)

		it("quarantine marks the record but leaves its data alone", function()
			local mock = MockDataStore.new()
			mock.data.p1 = { data = "not a profile" }
			local store = ProfileStore.new(mock, options("A"))
			expect((store:load("p1"))).toBe("ok")
			store:releaseLock("p1", "profile is a string")
			expect(mock.data.p1.data).toBe("not a profile")
			expect(mock.data.p1.lock).toBe(nil)
			expect(mock.data.p1.meta.quarantine.reason).toBe("profile is a string")
		end)

		it("takes over a stale lock immediately", function()
			local mock = MockDataStore.new()
			mock.data.p1 = { data = { cash = 9 }, lock = { job = "Crashed", t = clock - 10_000 } }
			waits = 0
			local b = ProfileStore.new(mock, options("B"))
			local status, data = b:load("p1")
			expect(status).toBe("ok")
			expect(data.cash).toBe(9)
			expect(waits).toBe(0)
		end)

		it("retries transient failures and succeeds", function()
			local mock = MockDataStore.new()
			mock.data.p1 = { data = { cash = 77 } }
			mock.failNext = 2
			local store = ProfileStore.new(mock, options("A"))
			local status, data = store:load("p1")
			expect(status).toBe("ok")
			expect(data.cash).toBe(77)
		end)

		it("reports an error after repeated failures and never writes", function()
			local mock = MockDataStore.new()
			mock.data.p1 = { data = { cash = 77 } }
			mock.failNext = 100
			local store = ProfileStore.new(mock, options("A"))
			local status = store:load("p1")
			expect(status).toBe("error")
			expect(mock.data.p1.data.cash).toBe(77)
			expect(mock.data.p1.lock).toBe(nil)
		end)

		it("refuses to touch a corrupt record", function()
			local mock = MockDataStore.new()
			mock.data.p1 = "garbage"
			local store = ProfileStore.new(mock, options("A"))
			local status = store:load("p1")
			expect(status).toBe("corrupt")
			expect(mock.data.p1).toBe("garbage")
		end)

		it("does not save over a record whose lock it never held", function()
			local mock = MockDataStore.new()
			mock.data.p1 = { data = { cash = 50 } }
			local store = ProfileStore.new(mock, options("A"))
			expect((store:save("p1", { cash = 0 }, true))).toBe("lost")
			expect(mock.data.p1.data.cash).toBe(50)
		end)

		it("releases a lock without modifying data", function()
			local mock = MockDataStore.new()
			mock.data.p1 = { data = { cash = 50 } }
			local store = ProfileStore.new(mock, options("A"))
			store:load("p1")
			store:releaseLock("p1")
			expect(mock.data.p1.lock).toBe(nil)
			expect(mock.data.p1.data.cash).toBe(50)
		end)
	end)

	describe("ProfileSchema.validate", function()
		it("refuses data that isn't shaped like a profile instead of resetting it", function()
			for _, bad in
				{
					"malformed-saved-profile",
					42,
					{ units = "abc" },
					{ crates = 7 },
					{ cash = "500" },
					{ box = true },
					{ upgrades = "x" },
				}
			do
				local ok, _, kind = Schema.validate(bad)
				expect(ok).toBe(false)
				expect(kind).toBe("corrupt")
			end
		end)

		it("refuses a newer data version", function()
			local ok, _, kind = Schema.validate({ version = 999 })
			expect(ok).toBe(false)
			expect(kind).toBe("newer")
		end)

		it("accepts current and partial profiles", function()
			expect((Schema.validate(Schema.new(clock)))).toBe(true)
			expect((Schema.validate({}))).toBe(true)
			expect((Schema.validate({ cash = 10 }))).toBe(true)
		end)
	end)
end
