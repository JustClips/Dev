--!strict
-- In-memory stand-in for a GlobalDataStore, used in Studio when the place is unpublished
-- or "Enable Studio Access to API Services" is off. Data is lost when the test stops.
local MockDataStore = {}
MockDataStore.__index = MockDataStore

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

function MockDataStore.new()
	return setmetatable({ _data = {} :: { [string]: any } }, MockDataStore)
end

function MockDataStore:GetAsync(key: string): any
	task.wait() -- behave asynchronously like the real thing
	return deepCopy(self._data[key])
end

function MockDataStore:SetAsync(key: string, value: any)
	task.wait()
	self._data[key] = deepCopy(value)
end

function MockDataStore:UpdateAsync(key: string, transform: (any) -> any): any
	task.wait()
	local result = transform(deepCopy(self._data[key]))
	if result ~= nil then
		self._data[key] = deepCopy(result)
	end
	return deepCopy(result)
end

return MockDataStore
