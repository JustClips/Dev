--!strict
-- Story and daily quests (Config/Quests). Progress is read from the save (Stats and where
-- you are), so no other service has to report anything: StateService calls Update before
-- each snapshot, which pays finished quests and moves on.
-- Save: data.Quests = {
--   Story = index of the current story quest (past the end = all done),
--   StoryBase = the stat value when it started (count quests),
--   Day = UTC day of the dailies, Daily = { { Id, Base, Done } }, Chest = claimed today,
--   Streak = days in a row with the chest, LastChestDay = UTC day of the last chest }
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Quests = require(Shared.Config.Quests)

local QuestService = {}

local S: any

local function today(): number
	return math.floor(os.time() / 86400)
end

local function countKeys(t: { [any]: any }?): number
	local n = 0
	for _ in t or {} do
		n += 1
	end
	return n
end

local function upgradeLevels(data): number
	local n = 0
	for _, level in data.Upgrades do
		if type(level) == "number" then
			n += level
		end
	end
	return n
end

-- The raw number a stat reads right now.
local function statValue(player: Player, data, stat: string): number
	local stats = data.Stats
	if stat == "Leaves" then
		return stats.TilesCleared or 0
	elseif stat == "EggsFound" then
		return stats.EggsFound or 0
	elseif stat == "Hatches" then
		return stats.Hatches or 0
	elseif stat == "Sells" then
		return stats.Sells or 0
	elseif stat == "Upgrades" then
		return upgradeLevels(data)
	elseif stat == "Placed" then
		return S.AlienService:PlacedCount(player)
	elseif stat == "Power" then
		return data.Upgrades.Power or 0
	elseif stat == "Tool" then
		return data.ToolTier or 1
	elseif stat == "Zones" then
		return countKeys(data.ZonesUnlocked)
	elseif stat == "Index" then
		return countKeys(data.Index)
	elseif stat == "Rebirths" then
		return data.Rebirths or 0
	end
	return 0
end

local function progress(player: Player, data, quest: Quests.Quest, base: number?): number
	local value = statValue(player, data, quest.Stat)
	if Quests.Stats[quest.Stat] == "count" then
		value -= base or value
	end
	return math.clamp(value, 0, quest.Goal)
end

-- Quests start once the tutorial is done (or for anyone who has rebirthed).
local function active(data): boolean
	return data.Flags.TutorialDone == true or (data.Rebirths or 0) > 0
end

local function state(player: Player, data)
	local q = data.Quests
	if type(q) ~= "table" then
		q = { Story = 1 }
		data.Quests = q
	end
	-- New day: 3 fresh daily quests, picked the same way for the whole day.
	local day = today()
	if q.Day ~= day then
		q.Day = day
		q.Chest = nil
		q.Daily = {}
		local rng = Random.new(day * 7919 + player.UserId % 100000)
		local pool = table.clone(Quests.Daily)
		for _ = 1, math.min(Quests.DailyCount, #pool) do
			local quest = table.remove(pool, rng:NextInteger(1, #pool))
			table.insert(q.Daily, { Id = quest.Id, Base = statValue(player, data, quest.Stat) })
		end
	end
	local story = Quests.Story[q.Story or 1]
	if story and q.StoryBase == nil then
		q.StoryBase = statValue(player, data, story.Stat)
	end
	return q
end

local function pay(player: Player, reward: Quests.Reward, sku: string): string
	return S.RewardService:Grant(player, reward, sku)
end

-- Pays finished quests (one story quest per call, so a chain of already-met ones goes one
-- by one with its own popup). Returns true when something changed.
function QuestService:Update(player: Player): boolean
	local data = S.DataService:GetData(player)
	if not data or not active(data) then
		return false
	end
	local q = state(player, data)
	local changed = false
	-- A rebirth resets upgrades: a count that went down restarts from there instead of
	-- getting stuck below its start.
	local function rebase(quest: Quests.Quest?, base: number?): number?
		if quest and base and Quests.Stats[quest.Stat] == "count" then
			return math.min(base, statValue(player, data, quest.Stat))
		end
		return base
	end
	q.StoryBase = rebase(Quests.Story[q.Story or 1], q.StoryBase)
	for _, entry in q.Daily or {} do
		entry.Base = rebase(Quests.ById[entry.Id], entry.Base)
	end
	local story = Quests.Story[q.Story or 1]
	if story and progress(player, data, story, q.StoryBase) >= story.Goal then
		local got = pay(player, story.Reward, "Quest_" .. story.Id)
		q.Story = (q.Story or 1) + 1
		q.StoryBase = nil
		local nextQuest = Quests.Story[q.Story]
		if nextQuest then
			q.StoryBase = statValue(player, data, nextQuest.Stat)
		end
		Net.fire("QuestDone", player, { Text = Quests.text(story), Reward = got, Kind = "Story" })
		S.AnalyticsService:Custom(player, "QuestDone", q.Story - 1, { Quest = story.Id })
		changed = true
	end
	local allDone = true
	for _, entry in q.Daily or {} do
		local quest = Quests.ById[entry.Id]
		if quest and not entry.Done then
			if progress(player, data, quest, entry.Base) >= quest.Goal then
				entry.Done = true
				local got = pay(player, quest.Reward, "Quest_" .. quest.Id)
				Net.fire("QuestDone", player, { Text = Quests.text(quest), Reward = got, Kind = "Daily" })
				S.AnalyticsService:Custom(player, "QuestDone", 0, { Quest = quest.Id })
				changed = true
			else
				allDone = false
			end
		end
	end
	if allDone and #(q.Daily or {}) > 0 and not q.Chest then
		q.Chest = true
		local day = today()
		q.Streak = if q.LastChestDay == day - 1 then (q.Streak or 0) + 1 else 1
		q.LastChestDay = day
		local reward = if q.Streak % 7 == 0 then Quests.WeekChest else Quests.DailyChest
		local got = pay(player, reward, "Quest_DailyChest")
		Net.fire("QuestDone", player, { Text = "All daily quests done!", Reward = got, Kind = "Chest" })
		S.AnalyticsService:Custom(player, "DailyChest", q.Streak, nil)
		changed = true
	end
	return changed
end

-- What the client shows (tracker + Quests window). nil before the tutorial is done.
function QuestService:Snapshot(player: Player): any
	local data = S.DataService:GetData(player)
	if not data or not active(data) then
		return nil
	end
	local q = state(player, data)
	local out: any = {
		StoryIndex = q.Story or 1,
		StoryTotal = #Quests.Story,
		Daily = {},
		Chest = q.Chest == true,
		Streak = if q.LastChestDay and q.LastChestDay >= today() - 1 then q.Streak or 0 else 0,
		ResetsAt = (today() + 1) * 86400,
	}
	local story = Quests.Story[q.Story or 1]
	if story then
		out.Story = {
			Id = story.Id,
			Text = Quests.text(story),
			Progress = progress(player, data, story, q.StoryBase),
			Goal = story.Goal,
			Reward = Quests.describe(story.Reward),
			RewardIcon = Quests.rewardIcon(story.Reward),
			Icon = story.Icon,
		}
	end
	for _, entry in q.Daily or {} do
		local quest = Quests.ById[entry.Id]
		if quest then
			table.insert(out.Daily, {
				Id = quest.Id,
				Text = Quests.text(quest),
				Progress = if entry.Done then quest.Goal else progress(player, data, quest, entry.Base),
				Goal = quest.Goal,
				Done = entry.Done == true,
				Reward = Quests.describe(quest.Reward),
				RewardIcon = Quests.rewardIcon(quest.Reward),
				Icon = quest.Icon,
			})
		end
	end
	local week = ((out.Streak or 0) + (if q.Chest then 0 else 1)) % 7 == 0
	out.ChestReward = Quests.describe(if week then Quests.WeekChest else Quests.DailyChest)
	return out
end

function QuestService:Init(services)
	S = services
end

return QuestService
