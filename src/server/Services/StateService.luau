--!strict
-- Replicates each player's state to their own client as one snapshot.
-- Services call Mark(player) after changing something; the snapshot is sent at most
-- every StateFlushInterval seconds.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)
local Rewards = require(Shared.Config.Rewards)
local Tools = require(Shared.Config.Tools)
local Types = require(Shared.Types)
local Upgrades = require(Shared.Config.Upgrades)

local StateService = {}

local S: any
local dirty: { [Player]: boolean } = {}
local sentInventory: { [Player]: number } = {}
-- Last tutorial step sent to each player (analytics logs each new one).
local lastStep: { [Player]: string } = {}
local lastLesson: { [Player]: string } = {}
local TUTORIAL_STEP_CASH = 25
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

-- The tutorial (Dev, 2026-11-01): it answers "why am I here, what do I do?" and nothing
-- else. Sweep leaves until your bag has some, sell them, upgrade your tool (free Broom),
-- then buy your first upgrade in the upgrade tree (free Sweep Power). Eggs come after,
-- taught by the egg lesson the first time you find one (eggLesson below).
local SWEEP_GOAL = 30 -- leaves in the bag before the Sell step

local function tutorialStep(player: Player, session: any): string
	local data = session.Data
	if data.Flags.TutorialDone then
		return "Done"
	end
	if data.Stats.Sells == 0 then
		-- Once Sell shows it stays until you've sold (Dev, 2026-11-01: the tutorial went back
		-- a step when the bag dipped under the goal, e.g. capacity changed in a car).
		if session.Runtime.TutorialSell then
			return "Sell"
		end
		local goal = math.min(SWEEP_GOAL, S.ToolService:GetCapacity(player))
		if data.Backpack >= goal then
			session.Runtime.TutorialSell = true
			return "Sell"
		end
		return "Sweep"
	end
	if data.ToolTier < Tools.FreeTier then
		return "Upgrade"
	end
	-- Last (Dev, 2026-11-01): buy your first upgrade in the upgrade tree (Sweep Power
	-- level 1 is free, Tools.tutorialPrice).
	if (data.Upgrades.Power or 0) < 1 then
		return "Tree"
	end
	data.Flags.TutorialDone = true
	-- The guaranteed first egg comes a few leaves after the tutorial (EggService).
	data.Flags.EggLessonFrom = data.Stats.TilesCleared
	if not data.Flags.TutorialRewarded then
		data.Flags.TutorialRewarded = true
		task.defer(rewardTutorial, player)
	end
	return "Done"
end

-- The egg lesson: after the tutorial, until the first hatch. The furthest egg step wins:
-- an egg growing, then one in the bag, then one in your hands, then one on the ground.
-- nil when there's nothing to teach right now (no egg found yet, or already hatched one).
local LESSON_ORDER = { Egg = 1, Base = 2, Place = 3, Hatching = 4, Open = 5 }

local function lessonNow(session: any): string?
	local data = session.Data
	if not data.Flags.TutorialDone or data.Stats.Hatches > 0 then
		return nil
	end
	local runtime = session.Runtime
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
	return nil
end

-- Never steps back (Dev, 2026-11-01: "it can go down a step"): picking an egg back out of
-- the bag or dropping it would show an earlier step. The furthest step reached this
-- session stays until the lesson ends (the first hatch).
local function eggLesson(session: any): string?
	local lesson = lessonNow(session)
	local runtime = session.Runtime
	if not lesson then
		if session.Data.Stats.Hatches > 0 then
			runtime.LessonMax = nil
		end
		return if session.Data.Stats.Hatches > 0 then nil else runtime.LessonMax
	end
	if runtime.LessonMax and LESSON_ORDER[runtime.LessonMax] > LESSON_ORDER[lesson] then
		return runtime.LessonMax
	end
	runtime.LessonMax = lesson
	return lesson
end

-- The tutorial step this player was last shown ("Done" once finished).
function StateService:GetTutorialStep(player: Player): string?
	return lastStep[player]
end

function StateService:Build(player: Player, full: boolean?): Types.PlayerSnapshot?
	local session = S.DataService:GetSession(player)
	if not session then
		return nil
	end
	local data = session.Data
	local runtime = session.Runtime
	local bestCar = S.ToolService:GetEquippedVehicle(player)
	-- Inventory tables only go out when they changed since the last snapshot (or when the
	-- client asks for everything with GetState).
	local invVersion = S.InventoryService:GetVersion(player)
	local sendInventory = full == true or sentInventory[player] ~= invVersion
	sentInventory[player] = invVersion
	local step = tutorialStep(player, session)
	S.QuestService:Update(player)
	if lastStep[player] ~= step then
		-- Every finished tutorial step pays a little cash with the "you got" popup (kids
		-- stay for small, frequent rewards). Not on the first snapshot after joining.
		if lastStep[player] ~= nil and lastStep[player] ~= "Done" and step ~= "Done" then
			task.defer(function()
				S.BackpackService:GiveCash(player, TUTORIAL_STEP_CASH, "TutorialStep")
			end)
		end
		lastStep[player] = step
		S.AnalyticsService:TutorialStep(player, step)
	end
	local lesson = eggLesson(session)
	if (lastLesson[player] or "") ~= (lesson or "") then
		if lesson then
			S.AnalyticsService:TutorialStep(player, "Lesson" .. lesson)
		elseif lastLesson[player] and data.Stats.Hatches > 0 then
			S.AnalyticsService:TutorialStep(player, "LessonDone")
		end
		lastLesson[player] = lesson
	end
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
		FriendsHere = S.BoostService:GetFriendCount(player),
		Index = data.Index,
		BaseSkins = data.BaseSkins,
		Boosts = data.Boosts,
		Gamepasses = data.Gamepasses,
		Flags = data.Flags,
		Stats = data.Stats,
		Slots = S.AlienService:GetSlotCount(player),
		SlotCashPrice = Economy.SlotCashPrices[(data.Flags.CashSlots or 0) + 1],
		IncomePerSec = S.AlienService:GetIncomePerSec(player),
		OfflinePerDay = S.AlienService:GetOfflinePerDay(player),
		CashPacks = S.ShopService:GetCashPackAmounts(player),
		CashMultiplier = S.BoostService:GetCashMultiplier(player),
		CarriedEggs = carried,
		CarryLimit = S.EggService:GetCarryLimit(player),
		BaseIndex = runtime.BaseIndex or 0,
		TutorialStep = step,
		EggLesson = lesson,
		Quests = S.QuestService:Snapshot(player),
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
		-- After AnalyticsService has read it for the "left during step" event.
		task.defer(function()
			lastStep[player] = nil
			lastLesson[player] = nil
		end)
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
