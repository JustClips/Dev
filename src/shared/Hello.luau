-- Shared module, synced from GitHub by LiveSync.
local Hello = {}

function Hello.greet(name: string): string
	return "Hello, " .. name .. "!"
end

return Hello
