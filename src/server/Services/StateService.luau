--!strict
-- Replicates each player's state to their own client as one snapshot.
-- Services call Mark(player) after changing something; the snapshot is sent at most
-- every StateFlushInterval seconds.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Upgrades = require(Shared.Config.Upgrades)

local StateService = {}

local S: any
local dirty: { [Player]: boolean } = {}
local serverState: Folder

-- Server-wide values (Moon %, event state, server luck) live as attributes on
-- ReplicatedStorage.ServerState so every client gets them without extra remotes.
function StateService:GetServerState(): Folder
	return serverState
end

-- Server-confirmed tutorial step (GAME_PLAN §4).
local function tutorialStep(session: any): string
	local data = session.Data
	if data.Flags.TutorialDone then
		return "Done"
	end
	local runtime = session.Runtime
	if runtime.Carried and #runtime.Carried > 0 then
		return "Base"
	end
	if data.Stats.Hatches == 0 then
		if runtime.TutorialEggPosition then
			return "Egg"
		end
		if #data.Hatching > 0 then
			return "Hatching"
		end
		return "Sweep"
	end
	if data.Stats.Sells == 0 then
		return "Sell"
	end
	if data.ToolTier < 2 then
		return "Shop"
	end
	data.Flags.TutorialDone = true
	return "Done"
end

function StateService:Build(player: Player): Types.PlayerSnapshot?
	local session = S.DataService:GetSession(player)
	if not session then
		return nil
	end
	local data = session.Data
	local runtime = session.Runtime
	local bestCar = S.ToolService:GetBestVehicle(player)
	return {
		Cash = data.Cash,
		Backpack = data.Backpack,
		Capacity = S.ToolService:GetCapacity(player),
		ToolTier = data.ToolTier,
		EffectiveTier = S.ToolService:GetEffectiveTier(player),
		Vehicles = data.Vehicles,
		RentedVehicle = runtime.RentedVehicle,
		BestVehicle = if bestCar then bestCar.Id else nil,
		InVehicle = S.ToolService:IsInVehicle(player),
		Upgrades = data.Upgrades,
		WalkSpeed = Upgrades.walkSpeed(data.Upgrades),
		Rebirths = data.Rebirths,
		RebirthCost = S.RebirthService:GetCost(data),
		ZonesUnlocked = data.ZonesUnlocked,
		Aliens = data.Aliens,
		Hatching = data.Hatching,
		Index = data.Index,
		Boosts = data.Boosts,
		Gamepasses = data.Gamepasses,
		Flags = data.Flags,
		Stats = data.Stats,
		Slots = S.AlienService:GetSlotCount(player),
		IncomePerSec = S.AlienService:GetIncomePerSec(player),
		CashPacks = S.ShopService:GetCashPackAmounts(player),
		CashMultiplier = S.BoostService:GetCashMultiplier(player),
		CarriedEggs = runtime.Carried or {},
		CarryLimit = S.EggService:GetCarryLimit(player),
		BaseIndex = runtime.BaseIndex or 0,
		TutorialStep = tutorialStep(session),
		TutorialTarget = runtime.TutorialEggPosition,
		AutoSweep = data.Settings.AutoSweep == true,
		ServerTime = os.time(),
	} :: any
end

function StateService:Mark(player: Player)
	dirty[player] = true
end

function StateService:Init(services)
	S = services
	local existing = ReplicatedStorage:FindFirstChild("ServerState")
	if existing then
		existing:Destroy()
	end
	serverState = Instance.new("Folder")
	serverState.Name = "ServerState"
	serverState.Parent = ReplicatedStorage
	Net.onInvoke("GetState", function(player)
		return StateService:Build(player)
	end)
	S.DataService.ProfileLoaded:Connect(function(player)
		StateService:Mark(player)
	end)
	S.DataService.ProfileReleasing:Connect(function(player)
		dirty[player] = nil
	end)
end

function StateService:Start()
	task.spawn(function()
		while true do
			task.wait(Economy.StateFlushInterval)
			for player in dirty do
				dirty[player] = nil
				local ok, snapshot = pcall(StateService.Build, StateService, player)
				if ok and snapshot then
					Net.fire("PlayerState", player, snapshot)
				elseif not ok then
					warn("[StateService] snapshot failed: " .. tostring(snapshot))
				end
			end
		end
	end)
end

return StateService
