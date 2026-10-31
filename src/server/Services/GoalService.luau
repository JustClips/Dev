--!strict
-- The three goals after the tutorial (Config/Goals). Progress is read from the save, so no
-- other service reports anything: StateService calls Update before each snapshot. Each goal
-- ticks off on its own; all three = a free wheel spin and the next round.
-- Save (Flags): GoalRound = round number, GoalBase = { Leaves, Cash, Hatches } at the
-- round's start, GoalDone = { [1..3] = true } for goals already ticked this round.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Aliens = require(Shared.Config.Aliens)
local BigNum = require(Shared.BigNum)
local Eggs = require(Shared.Config.Eggs)
local Goals = require(Shared.Config.Goals)
local Net = require(Shared.Net)

local GoalService = {}

local S: any

local function counters(data): { [string]: number }
	return {
		Leaves = data.Stats.TilesCleared or 0,
		Cash = BigNum.toNumber(data.Stats.CashEarned or 0),
		Hatches = data.Stats.Hatches or 0,
	}
end

local function hasPet(data, rarity: string): boolean
	local want = Eggs.order(rarity)
	for _, pet in data.Pets do
		local def = Aliens.ById[pet.Id]
		if def and Eggs.order(def.Rarity) >= want then
			return true
		end
	end
	return false
end

-- Starts tracking once the tutorial is done. Returns the round's goals and progress.
local function current(data): (Goals.Round?, { number })
	if data.Flags.TutorialDone ~= true then
		return nil, {}
	end
	local flags = data.Flags
	local now = counters(data)
	if type(flags.GoalRound) ~= "number" or type(flags.GoalBase) ~= "table" then
		flags.GoalRound = 1
		flags.GoalBase = now
		flags.GoalDone = {}
	end
	local base = flags.GoalBase
	local round = Goals.round(flags.GoalRound)
	local progress = {}
	for i, goal in round do
		local value = 0
		if goal.Kind == "Pet" then
			value = if hasPet(data, goal.Rarity or "Rare") then 1 else 0
		else
			-- A rebirth can lower a count: restart from there instead of getting stuck.
			if (base[goal.Kind] or 0) > now[goal.Kind] then
				base[goal.Kind] = now[goal.Kind]
			end
			value = now[goal.Kind] - (base[goal.Kind] or 0)
		end
		local target = if goal.Kind == "Pet" then 1 else goal.Goal or 1
		progress[i] = if flags.GoalDone[i] then target else math.clamp(value, 0, target)
	end
	return round, progress
end

function GoalService:Update(player: Player)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	local round, progress = current(data)
	if not round then
		return
	end
	local flags = data.Flags
	local all = true
	for i, goal in round do
		local target = if goal.Kind == "Pet" then 1 else goal.Goal or 1
		if progress[i] >= target then
			if not flags.GoalDone[i] then
				flags.GoalDone[i] = true
				Net.fire("GoalDone", player, { Text = Goals.text(goal), Index = i })
			end
		else
			all = false
		end
	end
	if all then
		local n = flags.GoalRound
		S.RewardService:Grant(player, Goals.Reward, "Goals" .. n)
		Net.fire("GoalDone", player, { Text = "All 3 goals", Reward = Goals.RewardText, Round = n })
		S.AnalyticsService:Custom(player, "GoalsRound", n, nil)
		flags.GoalRound = n + 1
		flags.GoalBase = counters(data)
		flags.GoalDone = {}
		S.StateService:Mark(player)
	end
end

-- What the goals panel shows. nil before the tutorial is done.
function GoalService:Snapshot(player: Player): any
	local data = S.DataService:GetData(player)
	if not data then
		return nil
	end
	local round, progress = current(data)
	if not round then
		return nil
	end
	local out = { Round = data.Flags.GoalRound, Reward = Goals.RewardText, List = {} }
	for i, goal in round do
		local target = if goal.Kind == "Pet" then 1 else goal.Goal or 1
		table.insert(out.List, {
			Text = Goals.text(goal),
			Progress = Goals.progressText(goal, progress[i]),
			Fraction = progress[i] / target,
			Done = progress[i] >= target,
		})
	end
	return out
end

function GoalService:Init(services)
	S = services
end

return GoalService
