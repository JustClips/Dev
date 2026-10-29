--!strict
-- All remotes in one place. The server creates them in ReplicatedStorage.Remotes;
-- clients wait for them. Every client -> server call is rate limited here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- name = max calls per second from one client (0 = server -> client only)
local EVENTS: { [string]: number } = {
	SweepTick = 12, -- client: position while sweeping (server enforces 10/s on top)
	TilesCleared = 0, -- server -> all: buffer of u16 tile ids
	SweepResult = 0, -- server -> sweeper: dust gained, cash value, full flag
	PlayerState = 0, -- server -> owner: full PlayerSnapshot
	Notify = 0, -- server -> one: short toast
	Announce = 0, -- server -> all: server-wide message
	HatchCompleted = 0, -- server -> owner: cutscene payload
	WelcomeBack = 0, -- server -> owner: offline income payload
	CashGained = 0, -- server -> owner: { Amount, Source } for the "you got" popup
	ShowOffer = 0, -- server -> owner: contextual offer
	OfferResponse = 4, -- client: offer clicked / dismissed
	EggDrop = 0, -- server -> all: (position, rarity, fallSeconds) an Egg Rain egg falls here
	WeatherStrike = 0, -- server -> all: (position, "Lightning" | "Star", hitEgg) a strike lands here
	EggUpgraded = 0, -- server -> all: (position, mutation) the weather upgraded a growing egg
	BunnyPop = 0, -- server -> all: a dust bunny got swept at a position
	TutorialDone = 0, -- server -> owner: tutorial finished, with the reward it gave
	SetAutoSweep = 4, -- client: toggle auto sweep (gamepass)
	SetSetting = 6, -- client: ("Music" | "Sfx", 0-1) volume sliders, saved
}

local FUNCTIONS: { [string]: number } = {
	GetState = 2,
	BuyNextTool = 4,
	Rebirth = 2,
	PromptPurchase = 4, -- (productKey, giftToUserId?) -> ok, message
	ToggleVehicle = 3,
	SpawnVehicle = 3, -- (vehicleId) -> ok, message: spawn on the Garage pad
	BuyVehicle = 4, -- (vehicleId) -> ok, message
	BuyUpgrade = 6, -- (upgradeId) -> ok, message
	EquipTool = 4,
	Teleport = 2, -- ("Base" | "Rocket" | zoneId) -> ok, message
	Inventory = 10, -- (action, arg?) -> ok, message: see InventoryService ACTIONS
	Rewards = 6, -- (action, arg?) -> ok, message: see RewardService ACTIONS
}

local FOLDER_NAME = "Remotes"

local Net = {}
Net.Events = EVENTS
Net.Functions = FUNCTIONS

local folder: Folder? = nil

local function getFolder(): Folder
	if folder then
		return folder
	end
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			existing:Destroy()
		end
		local f = Instance.new("Folder")
		f.Name = FOLDER_NAME
		f.Parent = ReplicatedStorage
		folder = f
	else
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	end
	return folder :: Folder
end

-- Server: creates every remote. Call once before anything else uses Net.
function Net.setup()
	assert(RunService:IsServer(), "Net.setup is server only")
	local f = getFolder()
	for name in EVENTS do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = f
	end
	for name in FUNCTIONS do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = f
	end
end

function Net.event(name: string): RemoteEvent
	assert(EVENTS[name] ~= nil, "Unknown remote event " .. name)
	local f = getFolder()
	if RunService:IsServer() then
		return f:FindFirstChild(name) :: RemoteEvent
	end
	return f:WaitForChild(name) :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	assert(FUNCTIONS[name] ~= nil, "Unknown remote function " .. name)
	local f = getFolder()
	if RunService:IsServer() then
		return f:FindFirstChild(name) :: RemoteFunction
	end
	return f:WaitForChild(name) :: RemoteFunction
end

-- Rate limiting (server side), one token bucket per player per remote.
local buckets: { [Player]: { [string]: { tokens: number, last: number } } } = {}
local warned: { [string]: boolean } = {}

local function allow(player: Player, name: string, perSecond: number): boolean
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local now = os.clock()
	local bucket = playerBuckets[name]
	if not bucket then
		bucket = { tokens = perSecond, last = now }
		playerBuckets[name] = bucket
	end
	bucket.tokens = math.min(perSecond, bucket.tokens + (now - bucket.last) * perSecond)
	bucket.last = now
	if bucket.tokens < 1 then
		local key = player.UserId .. ":" .. name
		if not warned[key] then
			warned[key] = true
			warn(`[Net] {player.Name} is calling {name} too fast; extra calls are ignored`)
		end
		return false
	end
	bucket.tokens -= 1
	return true
end

if RunService:IsServer() then
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

function Net.onEvent(name: string, handler: (Player, ...any) -> ())
	local limit = EVENTS[name]
	assert(limit and limit > 0, name .. " is not a client -> server event")
	Net.event(name).OnServerEvent:Connect(function(player, ...)
		if allow(player, name, limit) then
			handler(player, ...)
		end
	end)
end

function Net.onInvoke(name: string, handler: (Player, ...any) -> ...any)
	local limit = FUNCTIONS[name]
	Net.func(name).OnServerInvoke = function(player, ...)
		if not allow(player, name, limit) then
			return false, "Slow down"
		end
		return handler(player, ...)
	end
end

function Net.fire(name: string, player: Player, ...: any)
	Net.event(name):FireClient(player, ...)
end

function Net.fireAll(name: string, ...: any)
	Net.event(name):FireAllClients(...)
end

return Net
