--!strict
-- Replicates each player's state to their own client as one snapshot.
-- Services call Mark(player) after changing something; the snapshot is sent at most
-- every StateFlushInterval seconds.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)
local Rewards = require(Shared.Config.Rewards)
local Types = require(Shared.Types)
local Upgrades = require(Shared.Config.Upgrades)

local StateService = {}

local S: any
local dirty: { [Player]: boolean } = {}
local sentInventory: { [Player]: number } = {}
local serverState: Folder

-- Server-wide values (Moon %, event state, server luck) live as attributes on
-- ReplicatedStorage.ServerState so every client gets them without extra remotes.
function StateService:GetServerState(): Folder
	return serverState
end

-- Server-confirmed tutorial step (GAME_PLAN §4).
-- One-time reward for finishing the tutorial (Config/Rewards.Tutorial).
local function rewardTutorial(player: Player)
	local reward = Rewards.Tutorial
	S.BackpackService:GiveCash(player, reward.Cash, "TutorialReward")
	for itemId, amount in reward.Items do
		S.InventoryService:AddItem(player, itemId, amount)
	end
	Net.fire("TutorialDone", player, reward)
	S.StateService:Mark(player)
end

local function tutorialStep(player: Player, session: any): string
	local data = session.Data
	if data.Flags.TutorialDone then
		return "Done"
	end
	local runtime = session.Runtime
	-- The egg steps only matter until the first hatch: picking up an egg later mustn't
	-- send you back to "carry it home".
	if data.Stats.Hatches == 0 then
		-- The furthest egg step wins: an egg growing, then one in the bag, then one on your
		-- head, then one on the ground. A second egg found later never sends you back.
		if #data.Hatching > 0 then
			for _, entry in data.Hatching do
				if entry.EndsAt <= os.time() then
					return "Open"
				end
			end
			return "Hatching"
		end
		if next(data.Eggs) ~= nil then
			return "Place"
		end
		if runtime.Carried and #runtime.Carried > 0 then
			return "Base"
		end
		if runtime.TutorialEggPosition then
			return "Egg"
		end
		return "Sweep"
	end
	local anyPlaced = false
	for _, pet in data.Pets do
		if pet.Placed then
			anyPlaced = true
			break
		end
	end
	if not anyPlaced and next(data.Pets) ~= nil then
		return "PlacePet"
	end
	if data.Stats.Sells == 0 then
		return "Sell"
	end
	if data.ToolTier < 2 then
		return "Shop"
	end
	if (data.Upgrades.Power or 0) < 1 then
		return "Upgrade"
	end
	data.Flags.TutorialDone = true
	if not data.Flags.TutorialRewarded then
		data.Flags.TutorialRewarded = true
		task.defer(rewardTutorial, player)
	end
	return "Done"
end

function StateService:Build(player: Player, full: boolean?): Types.PlayerSnapshot?
	local session = S.DataService:GetSession(player)
	if not session then
		return nil
	end
	local data = session.Data
	local runtime = session.Runtime
	local bestCar = S.ToolService:GetBestVehicle(player)
	-- Inventory tables only go out when they changed since the last snapshot (or when the
	-- client asks for everything with GetState).
	local invVersion = S.InventoryService:GetVersion(player)
	local sendInventory = full == true or sentInventory[player] ~= invVersion
	sentInventory[player] = invVersion
	local carried = {}
	for _, entry in runtime.Carried or {} do
		table.insert(carried, entry.Rarity)
	end
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
		WalkSpeed = Upgrades.walkSpeed(data.Upgrades) + S.BoostService:GetSpeedBonus(player),
		Rebirths = data.Rebirths,
		RebirthCost = S.RebirthService:GetCost(data),
		ZonesUnlocked = data.ZonesUnlocked,
		InvVersion = invVersion,
		Pets = if sendInventory then data.Pets else nil,
		Eggs = if sendInventory then data.Eggs else nil,
		Items = if sendInventory then data.Items else nil,
		Hatching = data.Hatching,
		Incubators = S.HatchService:GetIncubatorCount(player),
		PetBagSize = Economy.PetBagSize,
		EggBagSize = Economy.EggBagSize,
		PlacedCount = S.AlienService:PlacedCount(player),
		Daily = data.Daily,
		Rewards = S.RewardService:Snapshot(player),
		Index = data.Index,
		BaseSkins = data.BaseSkins,
		Boosts = data.Boosts,
		Gamepasses = data.Gamepasses,
		Flags = data.Flags,
		Stats = data.Stats,
		Slots = S.AlienService:GetSlotCount(player),
		SlotCashPrice = Economy.SlotCashPrices[(data.Flags.CashSlots or 0) + 1],
		IncomePerSec = S.AlienService:GetIncomePerSec(player),
		CashPacks = S.ShopService:GetCashPackAmounts(player),
		CashMultiplier = S.BoostService:GetCashMultiplier(player),
		CarriedEggs = carried,
		CarryLimit = S.EggService:GetCarryLimit(player),
		BaseIndex = runtime.BaseIndex or 0,
		TutorialStep = tutorialStep(player, session),
		TutorialTarget = runtime.TutorialEggPosition,
		AutoSweep = data.Settings.AutoSweep == true,
		AutoSell = data.Settings.AutoSell ~= false,
		Settings = { Music = data.Settings.Music, Sfx = data.Settings.Sfx, Hotbar = data.Settings.Hotbar },
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
		return StateService:Build(player, true)
	end)
	S.DataService.ProfileLoaded:Connect(function(player)
		StateService:Mark(player)
	end)
	S.DataService.ProfileReleasing:Connect(function(player)
		dirty[player] = nil
		sentInventory[player] = nil
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
