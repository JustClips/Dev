--!strict
-- Latest PlayerSnapshot from the server, plus server-wide attributes.
-- Controllers read State.data and listen to State.Changed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)

local State = {
	data = nil :: Types.PlayerSnapshot?,
	Changed = Signal.new() :: Signal.Signal<Types.PlayerSnapshot>,
	serverOffset = 0,
	serverState = ReplicatedStorage:WaitForChild("ServerState") :: Folder,
}

-- Server unix time estimate (for EndsAt timers).
function State.now(): number
	return os.time() + State.serverOffset
end

function State.server(name: string): any
	return State.serverState:GetAttribute(name)
end

local refetching = false

local function apply(snapshot: Types.PlayerSnapshot)
	-- Inventory tables come only when they changed: keep the last copy otherwise.
	local previous = State.data
	if snapshot.Pets == nil then
		if previous and previous.Pets then
			snapshot.Pets = previous.Pets
			snapshot.Eggs = previous.Eggs
			snapshot.Items = previous.Items
		else
			snapshot.Pets, snapshot.Eggs, snapshot.Items = {}, {}, {}
			if not refetching then
				-- Missed the full copy somehow: ask for everything once.
				refetching = true
				task.spawn(function()
					local ok, full = pcall(function()
						return Net.func("GetState"):InvokeServer()
					end)
					refetching = false
					if ok and full then
						apply(full)
					end
				end)
			end
		end
	end
	State.serverOffset = snapshot.ServerTime - os.time()
	State.data = snapshot
	State.Changed:Fire(snapshot)
end

function State.init()
	Net.event("PlayerState").OnClientEvent:Connect(apply)
	task.spawn(function()
		-- The profile may still be loading; ask until it's there.
		while not State.data do
			local ok, snapshot = pcall(function()
				return Net.func("GetState"):InvokeServer()
			end)
			if ok and snapshot and not State.data then
				apply(snapshot)
			end
			task.wait(1)
		end
	end)
end

-- Runs fn now (if data exists) and on every change.
function State.observe(fn: (Types.PlayerSnapshot) -> ())
	if State.data then
		task.spawn(fn, State.data)
	end
	State.Changed:Connect(fn)
end

return State
