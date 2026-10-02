--!strict
-- In-memory stand-in for a GlobalDataStore. Used for Studio sessions without API access
-- (progress is not persisted and the player is told so) and by the offline test-suite,
-- which can inject failures to exercise the retry and locking paths.

local MockDataStore = {}
MockDataStore.__index = MockDataStore

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

function MockDataStore.new()
	return setmetatable({
		data = {} :: { [string]: any },
		failNext = 0, -- number of upcoming calls that should error
		calls = 0,
	}, MockDataStore)
end

function MockDataStore:_maybeFail()
	self.calls += 1
	if self.failNext > 0 then
		self.failNext -= 1
		error("MockDataStore: simulated request failure")
	end
end

function MockDataStore:GetAsync(key: string): any
	self:_maybeFail()
	return deepCopy(self.data[key])
end

function MockDataStore:UpdateAsync(key: string, transform: (any) -> any): any
	self:_maybeFail()
	local result = transform(deepCopy(self.data[key]))
	if result ~= nil then
		-- Real DataStores serialise to JSON; a deep copy catches accidental shared references.
		self.data[key] = deepCopy(result)
	end
	return deepCopy(result)
end

function MockDataStore:SetAsync(key: string, value: any)
	self:_maybeFail()
	self.data[key] = deepCopy(value)
end

return MockDataStore
