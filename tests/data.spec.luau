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
			profile.energy = 1234
			expect((a:save("p1", profile, true))).toBe("ok")
			expect(mock.data.p1.lock).toBe(nil)
			local b = ProfileStore.new(mock, options("B"))
			local status, data = b:load("p1")
			expect(status).toBe("ok")
			expect(data.energy).toBe(1234)
			expect(mock.data.p1.lock.job).toBe("B")
		end)

		it("waits for a live lock, then takes it over on the final attempt", function()
			local mock = MockDataStore.new()
			local a = ProfileStore.new(mock, options("A"))
			a:load("p1")
			a:save("p1", { energy = 5 }, false)
			waits = 0
			local b = ProfileStore.new(mock, options("B"))
			local status, data = b:load("p1")
			expect(status).toBe("ok")
			expect(data.energy).toBe(5)
			expect(waits).toBe(3)
			-- The old server can no longer write over the new session.
			local saveStatus = a:save("p1", { energy = 0 }, true)
			expect(saveStatus).toBe("lost")
			expect(mock.data.p1.data.energy).toBe(5)
		end)

		it("takes over a stale lock immediately", function()
			local mock = MockDataStore.new()
			mock.data.p1 = { data = { energy = 9 }, lock = { job = "Crashed", t = clock - 10_000 } }
			waits = 0
			local b = ProfileStore.new(mock, options("B"))
			local status, data = b:load("p1")
			expect(status).toBe("ok")
			expect(data.energy).toBe(9)
			expect(waits).toBe(0)
		end)

		it("retries transient failures and succeeds", function()
			local mock = MockDataStore.new()
			mock.data.p1 = { data = { energy = 77 } }
			mock.failNext = 2
			local store = ProfileStore.new(mock, options("A"))
			local status, data = store:load("p1")
			expect(status).toBe("ok")
			expect(data.energy).toBe(77)
		end)

		it("reports an error after repeated failures and never writes", function()
			local mock = MockDataStore.new()
			mock.data.p1 = { data = { energy = 77 } }
			mock.failNext = 100
			local store = ProfileStore.new(mock, options("A"))
			local status = store:load("p1")
			expect(status).toBe("error")
			expect(mock.data.p1.data.energy).toBe(77)
			expect(mock.data.p1.lock).toBe(nil)
		end)

		it("refuses to touch a corrupt record", function()
			local mock = MockDataStore.new()
			mock.data.p1 = "garbage"
			local store = ProfileStore.new(mock, options("A"))
			local status = store:load("p1")
			expect(status).toBe("error")
			expect(mock.data.p1).toBe("garbage")
		end)

		it("does not save over a record whose lock it never held", function()
			local mock = MockDataStore.new()
			mock.data.p1 = { data = { energy = 50 } }
			local store = ProfileStore.new(mock, options("A"))
			expect((store:save("p1", { energy = 0 }, true))).toBe("lost")
			expect(mock.data.p1.data.energy).toBe(50)
		end)

		it("releases a lock without modifying data", function()
			local mock = MockDataStore.new()
			mock.data.p1 = { data = { energy = 50 } }
			local store = ProfileStore.new(mock, options("A"))
			store:load("p1")
			store:releaseLock("p1")
			expect(mock.data.p1.lock).toBe(nil)
			expect(mock.data.p1.data.energy).toBe(50)
		end)
	end)
end
