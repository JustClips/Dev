--!strict
-- Starter goals after the tutorial (Config/Goals). Progress is read from the save, so no
-- other service reports anything: StateService calls Update before each snapshot, which
-- pays a finished goal (one per call) and moves to the next.
-- Save: data.Flags.Goal = index of the current goal (past the end = all done),
--       data.Flags.GoalBase = the stat value when it started (count goals).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Goals = require(Shared.Config.Goals)
local Net = require(Shared.Net)

local GoalService = {}

local S: any

local function countKeys(t: { [any]: any }?): number
	local n = 0
	for _ in t or {} do
		n += 1
	end
	return n
end

local function statValue(player: Player, data, stat: string): number
	local stats = data.Stats
	if stat == "Leaves" then
		return stats.TilesCleared or 0
	elseif stat == "EggsFound" then
		return stats.EggsFound or 0
	elseif stat == "Hatches" then
		return stats.Hatches or 0
	elseif stat == "Placed" then
		return S.AlienService:PlacedCount(player)
	elseif stat == "Power" then
		return data.Upgrades.Power or 0
	elseif stat == "Tool" then
		return data.ToolTier or 1
	elseif stat == "Zones" then
		return countKeys(data.ZonesUnlocked)
	end
	return 0
end

-- The current goal and its progress, or nil (tutorial not done / all goals done).
local function current(player: Player, data): (Goals.Goal?, number)
	if data.Flags.TutorialDone ~= true then
		return nil, 0
	end
	local index = data.Flags.Goal or 1
	local goal = Goals.List[index]
	if not goal then
		return nil, 0
	end
	local value = statValue(player, data, goal.Stat)
	if Goals.Stats[goal.Stat] == "count" then
		-- A rebirth can lower a count: restart from there instead of getting stuck.
		if type(data.Flags.GoalBase) ~= "number" or data.Flags.GoalBase > value then
			data.Flags.GoalBase = value
		end
		value -= data.Flags.GoalBase
	end
	return goal, math.clamp(value, 0, goal.Goal)
end

function GoalService:Update(player: Player)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	local goal, progress = current(player, data)
	if not goal or progress < goal.Goal then
		return
	end
	local index = data.Flags.Goal or 1
	data.Flags.Goal = index + 1
	data.Flags.GoalBase = nil
	local got = S.RewardService:Grant(player, goal.Reward, "Goal" .. index)
	Net.fire("GoalDone", player, { Text = Goals.text(goal), Reward = got })
	S.AnalyticsService:Custom(player, "GoalDone", index, nil)
	S.StateService:Mark(player)
end

-- What the card above the hotbar shows.
function GoalService:Snapshot(player: Player): any
	local data = S.DataService:GetData(player)
	if not data then
		return nil
	end
	local goal, progress = current(player, data)
	if not goal then
		return nil
	end
	return {
		Index = data.Flags.Goal or 1,
		Total = #Goals.List,
		Text = Goals.text(goal),
		Progress = progress,
		Goal = goal.Goal,
		Reward = Goals.describe(goal.Reward),
		Icon = goal.Icon,
	}
end

function GoalService:Init(services)
	S = services
end

return GoalService
