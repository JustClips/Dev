--!strict
-- Player profiles: session-locked load, autosave, release on leave, BindToClose flush.
-- Holds the per-player Session table that other services read and write.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)
local ProfileStore = require(script.Parent.Parent.Lib.ProfileStore)
local MockDataStore = require(script.Parent.Parent.Lib.MockDataStore)

local STORE_NAME = "PlayerData_v1"
local CURRENT_VERSION = 3
local RECEIPTS_KEPT = 100

local TEMPLATE: Types.ProfileData = {
	Version = CURRENT_VERSION,
	Cash = { m = 0, e = 0 },
	TotalDust = { m = 0, e = 0 },
	Rebirths = 0,
	Backpack = 0,
	BackpackValue = 0,
	ToolTier = 1,
	OwnedTools = { true },
	Vehicles = {},
	Upgrades = { Backpack = 0, Power = 0, Speed = 0, Luck = 0 },
	ZonesUnlocked = { Landing = true },
	Pets = {},
	Eggs = {},
	Items = {},
	NextUid = 1,
	Hatching = {},
	Index = {},
	Boosts = {},
	Gamepasses = {},
	Daily = { Streak = 0, LastDay = 0 },
	ReceiptsGranted = {},
	ReceiptOrder = {},
	LastOnline = 0,
	Flags = {
		StarterPackBought = false,
		TutorialDone = false,
		Funnel = {},
		OffersShown = {},
		FreeSkips = 0,
		GroupRewardClaimed = false,
		EventSignups = {},
	},
	Stats = { EggsFound = 0, Hatches = 0, Playtime = 0, TilesCleared = 0, Sells = 0 },
	Settings = { AutoSweep = true },
}

export type Session = {
	Player: Player,
	Profile: ProfileStore.Profile,
	Data: Types.ProfileData,
	JoinedAt: number,
	IsNewPlayer: boolean,
	-- Runtime only (not saved). Services add their own fields here.
	Runtime: { [string]: any },
}

local DataService = {
	ProfileLoaded = Signal.new() :: Signal.Signal<Player, Session>,
	ProfileReleasing = Signal.new() :: Signal.Signal<Player, Session>,
	UsingMock = false,
}

local sessions: { [Player]: Session } = {}
local store: any = nil

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

-- Fill keys that are missing (new fields added after a player's last save).
local function reconcile(data: any, template: any)
	for key, value in template do
		if data[key] == nil then
			data[key] = deepCopy(value)
		elseif type(value) == "table" and type(data[key]) == "table" and next(value) ~= nil and #value == 0 then
			-- Dictionary sub-tables (Flags, Stats, Settings): fill nested defaults too.
			reconcile(data[key], value)
		end
	end
end

-- Version upgrades: MIGRATIONS[n] turns a version-n profile into version n+1.
local MIGRATIONS: { [number]: (any) -> () } = {
	-- v2: cars left the tool ladder (tiers 7-9) and became owned vehicles.
	[1] = function(data)
		local carTiers = { [7] = "SweeperCart", [8] = "DustTruck", [9] = "MoonCrawler" }
		data.Vehicles = data.Vehicles or {}
		local tier = data.ToolTier or 1
		for t, id in carTiers do
			if tier >= t then
				data.Vehicles[id] = true
			end
		end
		if tier > 6 then
			data.ToolTier = 6
			data.OwnedTools = { true, true, true, true, true, true }
		end
	end,
	-- v3: inventory (Steal an Egg style). Aliens became Pets keyed by uid (all placed),
	-- hatching eggs got uids and a zone.
	[2] = function(data)
		local nextUid = 1
		data.Pets = {}
		for _, alien in data.Aliens or {} do
			data.Pets["p" .. nextUid] = { Id = alien.Id, Mutation = alien.Mutation, Placed = true }
			nextUid += 1
		end
		data.Aliens = nil
		local hatching = {}
		for i, entry in data.Hatching or {} do
			table.insert(hatching, {
				Uid = "e" .. nextUid,
				Rarity = entry.EggRarity or entry.Rarity or "Common",
				Zone = "Landing",
				Spot = i,
				EndsAt = entry.EndsAt or 0,
			})
			nextUid += 1
		end
		data.Hatching = hatching
		data.NextUid = nextUid
	end,
}

local function migrate(data: any)
	data.Version = data.Version or 1
	while data.Version < CURRENT_VERSION do
		local step = MIGRATIONS[data.Version]
		if step then
			step(data)
		end
		data.Version += 1
	end
end

local function pickStore(): any
	if game.GameId == 0 then
		warn("[DataService] Place isn't published: using an in-memory mock DataStore (nothing is saved).")
		DataService.UsingMock = true
		return MockDataStore.new()
	end
	local ok, result = pcall(function()
		local ds = DataStoreService:GetDataStore(STORE_NAME)
		ds:GetAsync("__probe")
		return ds
	end)
	if ok then
		return result
	end
	if RunService:IsStudio() then
		warn("[DataService] DataStores unavailable in Studio (" .. tostring(result) .. "). Using an in-memory mock. Turn on Game Settings > Security > Enable Studio Access to API Services to test saving.")
		DataService.UsingMock = true
		return MockDataStore.new()
	end
	-- Live server: keep the real store; loads will retry and kick on failure.
	return DataStoreService:GetDataStore(STORE_NAME)
end

local function kick(player: Player, message: string)
	if player.Parent then
		player:Kick(message)
	end
end

local function onPlayerAdded(player: Player)
	local profile, reason = store:LoadAsync("Player_" .. player.UserId, function()
		return player.Parent ~= nil
	end)
	if not profile then
		if reason == "locked" then
			kick(player, "Your save is still closing on another server. Please rejoin in a minute!")
		elseif reason ~= "left" then
			kick(player, "We couldn't load your save (Roblox data servers are busy). Please rejoin!")
		end
		return
	end
	if player.Parent == nil then
		profile:ReleaseAsync()
		return
	end

	local isNew = profile.Data == nil
	local data = profile.Data or deepCopy(TEMPLATE)
	migrate(data)
	reconcile(data, TEMPLATE)
	profile.Data = data

	local session: Session = {
		Player = player,
		Profile = profile,
		Data = data,
		JoinedAt = os.time(),
		IsNewPlayer = isNew,
		Runtime = {},
	}
	sessions[player] = session
	DataService.ProfileLoaded:Fire(player, session)
end

local function finalize(session: Session)
	session.Data.LastOnline = os.time()
	session.Data.Stats.Playtime += os.time() - session.JoinedAt
	session.JoinedAt = os.time()
end

local function release(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	-- Handlers run before the session is removed, so GetSession still works inside them.
	DataService.ProfileReleasing:Fire(player, session)
	sessions[player] = nil
	finalize(session)
	session.Profile:ReleaseAsync()
end

function DataService:GetSession(player: Player): Session?
	return sessions[player]
end

function DataService:GetData(player: Player): Types.ProfileData?
	local session = sessions[player]
	return if session then session.Data else nil
end

function DataService:GetSessions(): { [Player]: Session }
	return sessions
end

-- Saves right away (used after purchases). Returns true if the write went through.
function DataService:SaveNow(player: Player): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	finalize(session)
	local ok = session.Profile:SaveAsync()
	if session.Profile.Lost then
		sessions[player] = nil
		kick(player, "Your save was opened on another server.")
	end
	return ok
end

-- A new unique id for a pet ("p") or egg ("e").
function DataService:NewUid(data: Types.ProfileData, prefix: string): string
	local uid = prefix .. data.NextUid
	data.NextUid += 1
	return uid
end

-- Records a granted purchase id, keeping only the newest RECEIPTS_KEPT.
function DataService:RecordReceipt(data: Types.ProfileData, purchaseId: string, grantedTo: string)
	data.ReceiptsGranted[purchaseId] = grantedTo
	table.insert(data.ReceiptOrder, purchaseId)
	while #data.ReceiptOrder > RECEIPTS_KEPT do
		local oldest = table.remove(data.ReceiptOrder, 1)
		if oldest then
			data.ReceiptsGranted[oldest] = nil
		end
	end
end

function DataService:Init()
	store = ProfileStore.new(pickStore(), Economy.SessionStaleSeconds)
	-- Characters spawn only once the profile is loaded (see BaseService).
	Players.CharacterAutoLoads = false
end

function DataService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(release)

	task.spawn(function()
		while true do
			task.wait(Economy.AutosaveSeconds)
			for player in sessions do
				task.spawn(function()
					DataService:SaveNow(player)
				end)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in sessions do
			pending += 1
			task.spawn(function()
				release(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
