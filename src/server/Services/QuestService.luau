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
--   "ClaimJob"        the finished job's reward (Quest Master dialog or Quests window)
--   "ClaimDaily", i   daily quest i's reward (anywhere)
--   "ClaimBonus"      all daily quests claimed -> the bonus (anywhere)
--
-- The Quest Masters themselves stand on the left of every base (Lib/Npc, stall: MapBuilder).
--
-- Zone questlines (Config/ZoneQuests): one quest giver inside every zone with a chain of
-- quests that only count what you do in that zone (Stats.Zone[zoneId] counters, bumped
-- through ZoneCount). Save: Flags.ZoneQuest[zoneId] = { Step, Base }, Flags.ZonePass
-- (next zone half price, ZoneService:Unlock), Flags.ZoneVisited (first-visit egg given).
--   "ClaimZone", zoneId   the finished step's reward (NPC dialog or Quests window)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Aliens = require(Shared.Config.Aliens)
local BigNum = require(Shared.BigNum)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Grid = require(Shared.Grid)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Quests = require(Shared.Config.Quests)
local Rewards = require(Shared.Config.Rewards)
local World = require(Shared.Config.World)
local ZoneQuests = require(Shared.Config.ZoneQuests)
local Zones = require(Shared.Config.Zones)
local Npc = require(script.Parent.Parent.Lib.Npc)

local QuestService = {}

local S: any
local folder: Folder
local roots: { BasePart } = {}
local zoneFolder: Folder
local zoneRoots: { [string]: BasePart } = {}
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
	elseif k == "Power" then
		value = data.Upgrades.Power or 0
	elseif k == "FreeSpin" then
		value = if type(data.Flags.FreeSpinAt) == "number" then 1 else 0
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
		flags.QuestJobsV = Quests.JobsVersion
	elseif flags.QuestJobsV ~= Quests.JobsVersion then
		-- Keep saves on the same job when jobs were added or removed in front of it.
		-- v1 (none) -> v3: +1 (FreeSpin added). v2 -> v3: Broom and Power (jobs 1-2)
		-- removed, so jobs 1-2 become job 1 and later ones move down 2.
		if flags.QuestJobsV == 2 then
			flags.QuestJob = math.max(1, flags.QuestJob - 2)
		else
			flags.QuestJob += 1
		end
		flags.QuestJobsV = Quests.JobsVersion
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


-------------------------------------------------------------------------- zone questlines

-- Called by the services that count things (sweeps, eggs found, bunnies, hatches).
function QuestService:ZoneCount(player: Player, zoneId: string?, kind: string, n: number)
	local data = S.DataService:GetData(player)
	if not data or type(zoneId) ~= "string" then
		return
	end
	local all = data.Stats.Zone
	if type(all) ~= "table" then
		all = {}
		data.Stats.Zone = all
	end
	local z = all[zoneId]
	if type(z) ~= "table" then
		z = {}
		all[zoneId] = z
	end
	z[kind] = (z[kind] or 0) + n
end

local function zoneCounters(data, zoneId: string): { [string]: number }
	local all = data.Stats.Zone
	local z = type(all) == "table" and all[zoneId]
	return if type(z) == "table" then z else {}
end

-- Different pets of this zone in your Index (daily exclusives don't count).
local function zonePets(data, zoneId: string): number
	local n = 0
	for id in data.Index do
		local def = Aliens.ById[id]
		if def and not def.Exclusive and (def.Zone or "Landing") == zoneId then
			n += 1
		end
	end
	return n
end

local function zoneOpen(data, zoneId: string): boolean
	if data.Flags.TutorialDone ~= true then
		return false
	end
	return zoneId == Zones.StartZone or data.ZonesUnlocked[zoneId] == true
end

-- Where the player is on a zone's chain: the step number (nil = zone not open yet), the
-- step (nil = chain finished) and its progress.
local function zoneState(data, line: ZoneQuests.Line): (number?, ZoneQuests.Step?, number)
	if not zoneOpen(data, line.Zone) then
		return nil, nil, 0
	end
	local all = data.Flags.ZoneQuest
	if type(all) ~= "table" then
		all = {}
		data.Flags.ZoneQuest = all
	end
	local st = all[line.Zone]
	if type(st) ~= "table" or type(st.Step) ~= "number" or type(st.Base) ~= "table" then
		st = { Step = 1, Base = table.clone(zoneCounters(data, line.Zone)) }
		all[line.Zone] = st
	end
	local step = line.Steps[st.Step]
	if not step then
		return st.Step, nil, 0
	end
	local value = 0
	if ZoneQuests.Counted[step.Kind] then
		local now_ = zoneCounters(data, line.Zone)[step.Kind] or 0
		local from = st.Base[step.Kind] or 0
		if from > now_ then
			st.Base[step.Kind] = now_
			from = now_
		end
		value = now_ - from
	elseif step.Kind == "Pets" then
		value = zonePets(data, line.Zone)
	end
	return st.Step, step, math.clamp(value, 0, step.Goal)
end

local function zoneProgressText(step: ZoneQuests.Step, progress: number): string
	return `{Format.number(progress)}/{Format.number(step.Goal)}`
end

-------------------------------------------------------------------------- update + notify

-- Fires QuestReady once per finished quest (not for ones already done when you joined).
local function notifyReady(player: Player, key: string, text: string, isJob: boolean, npc: string?)
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
	Net.fire("QuestReady", player, { Text = text, Job = isJob, Npc = npc })
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
	for _, line in ZoneQuests.Lines do
		local n, step, p = zoneState(data, line)
		if n and step and p >= step.Goal then
			notifyReady(player, `Z{line.Zone}_{n}`, ZoneQuests.text(step, Zones.ById[line.Zone].Name), false, line.Npc)
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
	-- Claimable from the Quests window too, so no distance check (it used to need the NPC).
	local now_ = counters(player, data)
	local job, progress = jobState(player, data, now_)
	if not job then
		return false, "Finish the tutorial first!"
	end
	if progress < Quests.target(job) then
		return false, "That quest isn't done yet!"
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

local function claimZone(player: Player, zoneId: any): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return false, "Still loading"
	end
	local line = type(zoneId) == "string" and ZoneQuests.ByZone[zoneId]
	if not line then
		return false, "Unknown zone"
	end
	-- Claimable from the Quests window too, so no distance check (it used to need the NPC).
	local n, step, progress = zoneState(data, line)
	if not n then
		return false, `Unlock {Zones.ById[line.Zone].Name} first!`
	end
	if not step then
		return false, "You've done all my quests!"
	end
	if progress < step.Goal then
		return false, "That one isn't done yet!"
	end
	local got = S.RewardService:Grant(player, step.Reward, `ZoneQuest_{line.Zone}_{n}`)
	local st = data.Flags.ZoneQuest[line.Zone]
	st.Step = n + 1
	st.Base = table.clone(zoneCounters(data, line.Zone))
	-- The last step: a Zone Pass for the next zone (if it's still locked).
	if n == #line.Steps and line.Next and data.ZonesUnlocked[line.Next] ~= true then
		local passes = data.Flags.ZonePass
		if type(passes) ~= "table" then
			passes = {}
			data.Flags.ZonePass = passes
		end
		passes[line.Next] = true
		got ..= ` + {Zones.ById[line.Next].Name} Zone Pass`
	end
	S.AnalyticsService:Custom(player, "ZoneQuest", n, { Zone = line.Zone })
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
		local zone = (r :: any).Zone and Zones.ById[(r :: any).Zone]
		text = if zone then `{r.Rarity or "Common"} {zone.Name} Egg` else `{r.Rarity or "Common"} Egg`
	elseif r.Kind == "Pet" then
		local def = Aliens.ById[(r :: any).Pet or ""]
		text = if def then (if (r :: any).Huge then `Huge {def.Name}` else def.Name) else "Pet"
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
			Kind = job.Kind,
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
	local zones = {}
	for i, line in ZoneQuests.Lines do
		local n, step, p = zoneState(data, line)
		local entry: any = {
			Zone = line.Zone,
			ZoneName = Zones.ById[line.Zone].Name,
			Npc = line.Npc,
			Open = n ~= nil,
			Steps = #line.Steps,
			Step = n or 0,
			Finished = n ~= nil and step == nil,
		}
		if step then
			entry.Text = ZoneQuests.text(step, Zones.ById[line.Zone].Name)
			entry.Say = step.Say
			entry.Progress = zoneProgressText(step, p)
			entry.Fraction = p / step.Goal
			entry.Done = p >= step.Goal
			entry.Fresh = n == 1 and p == 0
			entry.Reward = rewardText(step.Reward :: any)
			entry.RewardKind = step.Reward.Kind
			entry.RewardItem = step.Reward.Item or step.Reward.Rarity
			entry.Last = n == #line.Steps
			if entry.Done then
				out.Ready += 1
				out.ZoneReady = (out.ZoneReady or 0) + 1
			end
		end
		zones[i] = entry
	end
	out.Zones = zones
	return out
end

-------------------------------------------------------------------------- NPCs

local function build(index: number)
	local root = Npc.build({
		Name = "QuestMaster" .. index,
		Title = Quests.NpcName,
		Sub = "Quests and rewards",
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

-- A zone's quest giver, standing on the real ground at World.ZoneNpc.
local function buildZoneNpc(line: ZoneQuests.Line)
	local cf = World.zoneNpcCFrame(line.Zone)
	if not cf then
		return
	end
	-- Only the terrain counts as ground (not trees or props).
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	local hit = Workspace:Raycast(cf.Position + Vector3.new(0, 20, 0), Vector3.new(0, -40, 0), params)
	if hit then
		cf = cf - cf.Position + Vector3.new(cf.Position.X, hit.Position.Y, cf.Position.Z)
	end
	local root = Npc.build({
		Name = "ZoneNpc_" .. line.Zone,
		Title = line.Npc,
		Sub = line.Sub,
		TitleColor = line.Color,
		Opens = "ZoneQuest",
		Skin = line.Skin,
		Shirt = line.Shirt,
		Pants = line.Pants,
	}, cf, zoneFolder)
	if root then
		local prompt = root:FindFirstChild("TalkPrompt")
		if prompt then
			prompt:SetAttribute("Zone", line.Zone)
		end
		(root.Parent :: Instance):SetAttribute("Zone", line.Zone)
		zoneRoots[line.Zone] = root
	end
end

-- The first time you walk into an unlocked zone: a free egg of that zone.
local function checkVisits()
	for _, player in Players:GetPlayers() do
		local data = S.DataService:GetData(player)
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not data or not hrp or data.Flags.TutorialDone ~= true then
			continue
		end
		local zone = Grid.zoneAt(hrp.Position)
		local rarity = zone and ZoneQuests.FirstVisitEgg[zone.Id]
		if not zone or not rarity or data.ZonesUnlocked[zone.Id] ~= true then
			continue
		end
		local seen = data.Flags.ZoneVisited
		if type(seen) ~= "table" then
			seen = {}
			data.Flags.ZoneVisited = seen
		end
		if seen[zone.Id] then
			continue
		end
		seen[zone.Id] = true
		S.InventoryService:AddEgg(player, rarity, zone.Id, true)
		S.AnalyticsService:Custom(player, "ZoneFirstVisit", 1, { Zone = zone.Id })
		local line = ZoneQuests.ByZone[zone.Id]
		local talk = if line then ` Talk to {line.Npc} for quests!` else ""
		Net.fire("Notify", player, `Welcome to the {zone.Name}! A free {rarity} {zone.Name} Egg is in your bag.{talk}`, "Egg")
		S.StateService:Mark(player)
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
	zoneFolder = Instance.new("Folder")
	zoneFolder.Name = "ZoneNpcs"
	zoneFolder.Parent = Workspace
end

function QuestService:Start()
	Net.onInvoke("Quests", function(player: Player, action: any, arg: any)
		if action == "ClaimJob" then
			return claimJob(player)
		elseif action == "ClaimDaily" then
			return claimDaily(player, arg)
		elseif action == "ClaimBonus" then
			return claimBonus(player)
		elseif action == "ClaimZone" then
			return claimZone(player, arg)
		elseif action == "Accept" then
			-- The tutorial's last step: talk to your Quest Master and accept. The tutorial
			-- ends on the next snapshot (StateService) and the first job starts then.
			local data = S.DataService:GetData(player)
			if not data then
				return false, "Still loading"
			end
			if not QuestService:IsNear(player) then
				return false, "Walk up to the Quest Master first!"
			end
			data.Flags.QuestMet = true
			S.StateService:Mark(player)
			return true, nil
		end
		return false, "Unknown action"
	end)
	for i = 1, World.BaseCount do
		task.spawn(build, i)
	end
	-- Zone NPCs wait a moment so the runtime terrain is there to stand on.
	task.delay(4, function()
		for _, line in ZoneQuests.Lines do
			task.spawn(buildZoneNpc, line)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			checkVisits()
		end
	end)
end

return QuestService
