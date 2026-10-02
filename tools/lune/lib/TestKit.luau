--!nocheck
-- Tiny test framework for Lune specs.
local TestKit = {}

local results = { passed = 0, failed = 0, failures = {} }
local prefix = {}

function TestKit.describe(name: string, fn: () -> ())
	table.insert(prefix, name)
	fn()
	table.remove(prefix)
end

function TestKit.it(name: string, fn: () -> ())
	local full = table.concat(prefix, " > ") .. " > " .. name
	local ok, err = pcall(fn)
	if ok then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, full .. "\n    " .. tostring(err))
	end
end

local function fmt(v)
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

function TestKit.expect(actual)
	local e = {}
	function e.toBe(expected)
		if actual ~= expected then
			error(string.format("expected %s to be %s", fmt(actual), fmt(expected)), 2)
		end
	end
	function e.toBeNear(expected, eps)
		if math.abs(actual - expected) > (eps or 1e-6) then
			error(string.format("expected %s to be near %s", fmt(actual), fmt(expected)), 2)
		end
	end
	function e.toBeTruthy()
		if not actual then
			error(string.format("expected %s to be truthy", fmt(actual)), 2)
		end
	end
	function e.toBeFalsy()
		if actual then
			error(string.format("expected %s to be falsy", fmt(actual)), 2)
		end
	end
	function e.toBeGreaterThan(n)
		if not (actual > n) then
			error(string.format("expected %s > %s", fmt(actual), fmt(n)), 2)
		end
	end
	function e.toBeLessThan(n)
		if not (actual < n) then
			error(string.format("expected %s < %s", fmt(actual), fmt(n)), 2)
		end
	end
	return e
end

function TestKit.report(): boolean
	for _, failure in results.failures do
		print("FAIL " .. failure)
	end
	print(string.format("%d passed, %d failed", results.passed, results.failed))
	return results.failed == 0
end

return TestKit
