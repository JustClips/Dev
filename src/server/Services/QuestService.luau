--!strict
-- Quests (Config/Quests): the Quest Master's jobs and 3 daily quests. Replaced the 3-goal
-- strip (GoalService) on 2026-10-31. Progress is read from the save (Stats counters and
-- what you own), so other services only bump their Stats counter; StateService calls
-- Update before each snapshot.
--
-- Save (Flags):
--   QuestJob    the job you're on (1-based)
--   QuestBase   counters when that job started
--   QuestDaily  { Day, List = { { Kind, Goal, Base, Claimed } }, Bonus = claimed? }
--
-- Remote "Quests"(action, arg) -> ok, message
--   "ClaimJob"        the finished job's reward; you must be at a Quest Master
--   "ClaimDaily", i   daily quest i's reward (anywhere)
--   "ClaimBonus"      all daily quests claimed -> the bonus (anywhere)
--
-- The Quest Masters themselves stand on the left of every base (Lib/Npc, stall: MapBuilder).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Aliens = require(Shared.Config.Aliens)
local BigNum = require(Shared.BigNum)
local Eggs = require(Shared.Config.Eggs)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Quests = require(Shared.Config.Quests)
local Rewards = require(Shared.Config.Rewards)
local World = require(Shared.Config.World)
local Npc = require(script.Parent.Parent.Lib.Npc)

local QuestService = {}

local S: any
local folder: Folder
local roots: { BasePart } = {}
local CLAIM_DISTANCE = 18 -- a little looser than the Talk prompt

local function now(): number
	return os.time()
end

-------------------------------------------------------------------------- progress

-- Every counted kind's value right now.
local function counters(player: Player, data): { [string]: number }
	local out = {}
	for kind, stat in Quests.Counters do
		if type(stat) == "string" then
			out[kind] = data.Stats[stat] or 0
		end
	end
	out.Cash = BigNum.toNumber(data.Stats.CashEarned or 0)
	local session = S.DataService:GetSession(player)
	local live = if session then now() - session.JoinedAt else 0
	out.Minutes = math.floor(((data.Stats.Playtime or 0) + live) / 60)
	return out
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

local function count(t: { [any]: any }, test: ((any) -> boolean)?): number
	local n = 0
	for _, v in t do
		if not test or test(v) then
			n += 1
		end
	end
	return n
end

-- Progress on q: counted kinds from base, the rest from what you have now.
local function progressOf(q: Quests.Quest, data, now_: { [string]: number }, base: { [string]: number }?): number
	local k = q.Kind
	local value = 0
	if Quests.Counters[k] then
		local from = base and base[k] or 0
		-- A rebirth or old save can make a counter lower than its start: restart from there.
		if base and from > (now_[k] or 0) then
			base[k] = now_[k] or 0
			from = base[k]
		end
		value = (now_[k] or 0) - from
	elseif k == "Pet" then
		value = if hasPet(data, q.Rarity or "Rare") then 1 else 0
	elseif k == "Tool" then
		value = if (data.ToolTier or 1) >= (q.Goal or 1) or data.OwnedTools[q.Goal or 1] then 1 else 0
	elseif k == "Zones" then
		value = count(data.ZonesUnlocked, function(v)
			return v == true
		end)
	elseif k == "Placed" then
		value = count(data.Pets, function(p)
			return p.Placed == true
		end)
	elseif k == "Index" then
		value = count(data.Index)
	elseif k == "Rebirths" then
		value = data.Rebirths or 0
	end
	return math.clamp(value, 0, Quests.target(q))
end

-------------------------------------------------------------------------- jobs

local function jobState(player: Player, data, now_: { [string]: number }): (Quests.Quest?, number)
	if data.Flags.TutorialDone ~= true then
		return nil, 0
	end
	local flags = data.Flags
	if type(flags.QuestJob) ~= "number" or type(flags.QuestBase) ~= "table" then
		flags.QuestJob = 1
		flags.QuestBase = table.clone(now_)
	end
	local q = Quests.job(flags.QuestJob)
	return q, progressOf(q, data, now_, flags.QuestBase)
end

-------------------------------------------------------------------------- daily

local function niceRound(n: number): number
	if n < 100 then
		return math.max(1, math.floor(n))
	end
	local p = 10 ^ math.floor(math.log10(n))
	local step = if n / p >= 5 then p else p / 2
	return math.floor(n / step + 0.5) * step
end

local function rollDaily(player: Player, data, day: number, now_: { [string]: number })
	local rng = Random.new(day * 7919 + player.UserId % 1_000_003)
	local tier = Quests.tier((data.Flags.QuestJob or 1) - 1, data.Rebirths or 0)
	local pool = table.clone(Quests.DailyPool)
	local list = {}
	for _ = 1, math.min(Quests.DailyCount, #pool) do
		local pick = table.remove(pool, rng:NextInteger(1, #pool)) :: any
		local goal = pick.Size(tier)
		if pick.Kind == "Cash" then
			-- About 10 minutes of your best pet income (at least $2K).
			goal = niceRound(math.max(2_000, (data.Stats.BestPerSec or 0) * 600))
		else
			goal = niceRound(goal)
		end
		table.insert(list, { Kind = pick.Kind, Goal = goal, Base = now_[pick.Kind] or 0, Claimed = false })
	end
	data.Flags.QuestDaily = { Day = day, List = list, Bonus = false }
end

local function dailyState(player: Player, data, now_: { [string]: number })
	if data.Flags.TutorialDone ~= true then
		return nil
	end
	local day = Rewards.day(now())
	local daily = data.Flags.QuestDaily
	if type(daily) ~= "table" or daily.Day ~= day or type(daily.List) ~= "table" then
		rollDaily(player, data, day, now_)
		daily = data.Flags.QuestDaily
	end
	return daily
end

local function dailyProgress(q, data, now_): number
	local base = { [q.Kind] = q.Base or 0 }
	local value = progressOf(q, data, now_, base)
	q.Base = base[q.Kind]
	return value
end

local function rewardOfDaily(kind: string): Quests.Reward
	for _, t in Quests.DailyPool do
		if t.Kind == kind then
			return t.Reward
		end
	end
	return { Kind = "Cash", Seconds = 300, Floor = 0.3 }
end

-------------------------------------------------------------------------- update + notify

-- Fires QuestReady once per finished quest (not for ones already done when you joined).
local function notifyReady(player: Player, key: string, text: string, isJob: boolean)
	local session = S.DataService:GetSession(player)
	if not session then
		return
	end
	local rt = session.Runtime
	local seen = rt.QuestSeen
	if seen == nil then
		seen = {}
		rt.QuestSeen = seen
	end
	if seen[key] then
		return
	end
	seen[key] = true
	if not rt.QuestPrimed then
		return
	end
	Net.fire("QuestReady", player, { Text = text, Job = isJob })
end

function QuestService:Update(player: Player)
	local data = S.DataService:GetData(player)
	if not data or data.Flags.TutorialDone ~= true then
		return
	end
	local now_ = counters(player, data)
	local job, jp = jobState(player, data, now_)
	if job and jp >= Quests.target(job) then
		notifyReady(player, "J" .. data.Flags.QuestJob, Quests.text(job), true)
	end
	local daily = dailyState(player, data, now_)
	if daily then
		for i, q in daily.List do
			if not q.Claimed and dailyProgress(q, data, now_) >= Quests.target(q) then
				notifyReady(player, `D{daily.Day}_{i}`, Quests.text(q), false)
			end
		end
	end
	local session = S.DataService:GetSession(player)
	if session then
		session.Runtime.QuestPrimed = true
	end
end

-------------------------------------------------------------------------- claims

local function claimJob(player: Player): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return false, "Still loading"
	end
	if not Npc.isNear(player, roots, CLAIM_DISTANCE) then
		return false, "Talk to the Quest Master on your base to claim it!"
	end
	local now_ = counters(player, data)
	local job, progress = jobState(player, data, now_)
	if not job then
		return false, "Finish the tutorial first!"
	end
	if progress < Quests.target(job) then
		return false, "That job isn't done yet!"
	end
	local n = data.Flags.QuestJob
	local got = S.RewardService:Grant(player, job.Reward or { Kind = "Cash", Seconds = 300 }, "QuestJob" .. n)
	S.AnalyticsService:Custom(player, "QuestJob", n, nil)
	data.Flags.QuestJob = n + 1
	data.Flags.QuestBase = table.clone(now_)
	S.StateService:Mark(player)
	return true, got
end

local function claimDaily(player: Player, index: any): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return false, "Still loading"
	end
	local now_ = counters(player, data)
	local daily = dailyState(player, data, now_)
	local q = daily and type(index) == "number" and daily.List[index]
	if not q then
		return false, "That quest is gone. New ones every day!"
	end
	if q.Claimed then
		return false, "Already claimed!"
	end
	if dailyProgress(q, data, now_) < Quests.target(q) then
		return false, "Not done yet!"
	end
	q.Claimed = true
	local got = S.RewardService:Grant(player, rewardOfDaily(q.Kind), "QuestDaily")
	S.AnalyticsService:Custom(player, "QuestDaily", index, { Kind = q.Kind })
	S.StateService:Mark(player)
	return true, got
end

local function claimBonus(player: Player): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return false, "Still loading"
	end
	local daily = dailyState(player, data, counters(player, data))
	if not daily then
		return false, "Finish the tutorial first!"
	end
	if daily.Bonus then
		return false, "Already claimed today. Come back tomorrow!"
	end
	for _, q in daily.List do
		if not q.Claimed then
			return false, "Claim all daily quests first!"
		end
	end
	daily.Bonus = true
	local got = S.RewardService:Grant(player, Quests.DailyBonus, "QuestBonus")
	S.AnalyticsService:Custom(player, "QuestBonus", 1, nil)
	S.StateService:Mark(player)
	return true, got
end

-------------------------------------------------------------------------- snapshot

local function rewardText(r: Quests.Reward?): string
	if not r then
		return ""
	end
	local text
	if r.Kind == "Cash" then
		text = "Cash"
	elseif r.Kind == "Item" then
		local def = Items.ById[r.Item or ""]
		text = if def then def.Name else "Potion"
		if (r.Amount or 1) > 1 then
			text ..= ` x{r.Amount}`
		end
	elseif r.Kind == "Egg" then
		text = `{r.Rarity or "Common"} Egg`
	elseif r.Kind == "Spin" then
		text = if (r.Amount or 1) > 1 then `{r.Amount} Spins` else "Free Spin"
	else
		text = r.Kind
	end
	return text
end

-- What the strip, window and Quest Master show. nil before the tutorial is done.
function QuestService:Snapshot(player: Player): any
	local data = S.DataService:GetData(player)
	if not data or data.Flags.TutorialDone ~= true then
		return nil
	end
	local now_ = counters(player, data)
	local out: any = { Ready = 0 }
	local job, jp = jobState(player, data, now_)
	if job then
		local target = Quests.target(job)
		out.Job = {
			Number = data.Flags.QuestJob,
			Text = Quests.text(job),
			Progress = Quests.progressText(job, jp),
			Fraction = jp / target,
			Done = jp >= target,
			Reward = rewardText(job.Reward),
			RewardKind = job.Reward and job.Reward.Kind or "Cash",
			RewardItem = job.Reward and (job.Reward.Item or job.Reward.Rarity),
		}
		if out.Job.Done then
			out.Ready += 1
		end
	end
	local daily = dailyState(player, data, now_)
	if daily then
		local list = {}
		local allClaimed = true
		for i, q in daily.List do
			local p = dailyProgress(q, data, now_)
			local target = Quests.target(q)
			local reward = rewardOfDaily(q.Kind)
			list[i] = {
				Text = Quests.text(q),
				Progress = Quests.progressText(q, p),
				Fraction = p / target,
				Done = p >= target,
				Claimed = q.Claimed,
				Reward = rewardText(reward),
				RewardKind = reward.Kind,
				RewardItem = reward.Item or reward.Rarity,
			}
			if p >= target and not q.Claimed then
				out.Ready += 1
			end
			allClaimed = allClaimed and q.Claimed
		end
		out.Daily = {
			List = list,
			Bonus = Quests.DailyBonusText,
			BonusReady = allClaimed and not daily.Bonus,
			BonusClaimed = daily.Bonus == true,
			ResetsAt = (daily.Day + 1) * 86400,
		}
		if out.Daily.BonusReady then
			out.Ready += 1
		end
	end
	return out
end

-------------------------------------------------------------------------- NPCs

local function build(index: number)
	local root = Npc.build({
		Name = "QuestMaster" .. index,
		Title = Quests.NpcName,
		Sub = "Jobs and rewards",
		TitleColor = Color3.fromRGB(110, 190, 255),
		Opens = "Quests",
		Skin = Color3.fromRGB(234, 184, 146),
		Shirt = Color3.fromRGB(47, 130, 230),
		Pants = Color3.fromRGB(64, 62, 78),
	}, World.questCFrame(index), folder)
	if root then
		local model = root.Parent :: Instance
		model:SetAttribute("Base", index)
		table.insert(roots, root)
	end
end

function QuestService:IsNear(player: Player): boolean
	return Npc.isNear(player, roots, CLAIM_DISTANCE)
end

function QuestService:Init(services)
	S = services
	folder = Instance.new("Folder")
	folder.Name = "QuestMasters"
	folder.Parent = Workspace
end

function QuestService:Start()
	Net.onInvoke("Quests", function(player: Player, action: any, arg: any)
		if action == "ClaimJob" then
			return claimJob(player)
		elseif action == "ClaimDaily" then
			return claimDaily(player, arg)
		elseif action == "ClaimBonus" then
			return claimBonus(player)
		end
		return false, "Unknown action"
	end)
	for i = 1, World.BaseCount do
		task.spawn(build, i)
	end
end

return QuestService
