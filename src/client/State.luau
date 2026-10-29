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

-- The tutorial step, with "Hatching" turned into "Open" as soon as an egg is ready
-- (the server only sends the step when something else changes).
function State.tutorialStep(data): string
	local step = data.TutorialStep
	if step == "Hatching" then
		for _, entry in data.Hatching do
			if entry.EndsAt <= State.now() then
				return "Open"
			end
		end
	end
	return step
end

function State.server(name: string): any
	return State.serverState:GetAttribute(name)
end

local refetching = false
local invHave: number? = nil -- InvVersion of the bag tables we hold

local apply: (Types.PlayerSnapshot) -> ()

-- Ask the server for everything once (the bag tables went missing or out of date).
local function refetch()
	if refetching then
		return
	end
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

apply = function(snapshot: Types.PlayerSnapshot)
	-- Inventory tables come only when they changed: keep the last copy otherwise.
	local previous = State.data
	local version = (snapshot :: any).InvVersion or 0
	if snapshot.Pets ~= nil then
		if invHave and version < invHave then
			return -- a full copy that arrived after newer news
		end
		invHave = version
	elseif previous and previous.Pets then
		snapshot.Pets = previous.Pets
		snapshot.Eggs = previous.Eggs
		snapshot.Items = previous.Items
		if version ~= invHave then
			-- The bag changed but the new tables never reached us: fetch them so counts
			-- (like the Eggs badge) never show things that aren't there.
			refetch()
		end
	else
		snapshot.Pets, snapshot.Eggs, snapshot.Items = {}, {}, {}
		refetch()
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
