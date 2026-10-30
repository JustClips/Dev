--!strict
-- Free rewards from Config/Rewards: daily streak, playtime gifts, the stay offer, the group
-- reward and event sign-ups. One remote, Rewards(action, arg) -> ok, message:
--   ClaimDaily, ClaimPlaytime(index), StartStay, ClaimGroup, SignUp(eventId).
-- Session playtime is counted by this service's 1 s loop (not wall time), so it pauses
-- while a profile is still loading and resets when the player rejoins.
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Rewards = require(Shared.Config.Rewards)
local Zones = require(Shared.Config.Zones)

local SIGNED = 1
local REWARDED = 2

local RewardService = {}

local S: any
local clockOffset = 0

local function now(): number
	return os.time() + clockOffset
end

-- Tests move the calendar (daily streak, events) without waiting for real days.
function RewardService:SkewClock(seconds: number)
	clockOffset += seconds
end

local function notify(player: Player, text: string, kind: string?)
	Net.fire("Notify", player, text, kind or "Good")
end

-- Best unlocked zone that can drop this rarity (so the egg hatches into that zone's pets).
local function eggZone(data, rarity: string): string
	local best = "Landing"
	for _, zone in Zones.List do
		if data.ZonesUnlocked[zone.Id] and Eggs.order(zone.MaxRarity) >= Eggs.order(rarity) then
			best = zone.Id
		end
	end
	return best
end

-- Gives one reward and returns a short description ("$1.2K", "Luck Potion x2", "Rare Egg").
local function grant(player: Player, reward: Rewards.Reward, sku: string): string
	local data = S.DataService:GetData(player)
	if not data then
		return ""
	end
	if reward.Kind == "Cash" then
		local cash = S.ShopService:CashFor(player, reward.Seconds or 60, reward.Floor)
		S.BackpackService:GiveCash(player, cash, sku)
		return Format.cash(cash)
	elseif reward.Kind == "Item" then
		local item = Items.ById[reward.Item or ""]
		if not item then
			return ""
		end
		local amount = reward.Amount or 1
		S.InventoryService:AddItem(player, item.Id, amount)
		return if amount > 1 then `{item.Name} x{amount}` else item.Name
	elseif reward.Kind == "Egg" then
		local rarity = reward.Rarity or "Common"
		S.InventoryService:AddEgg(player, rarity, eggZone(data, rarity), true)
		return `{rarity} Egg`
	elseif reward.Kind == "Spin" then
		local amount = reward.Amount or 1
		data.Spins = (data.Spins or 0) + amount
		return if amount > 1 then `{amount} Wheel Spins` else "Wheel Spin"
	end
	return ""
end

-- Other services (CodeService) give rewards the same way.
function RewardService:Grant(player: Player, reward: Rewards.Reward, sku: string): string
	return grant(player, reward, sku)
end

local function runtime(player: Player): any
	local session = S.DataService:GetSession(player)
	return session and session.Runtime
end

-------------------------------------------------------------------------- daily

-- When the player last claimed a daily reward. Saves from before the 24-hour clock only
-- kept the UTC day: count those as claimed at the end of that day.
local function lastClaim(daily): number
	if type(daily.LastClaim) == "number" and daily.LastClaim > 0 then
		return daily.LastClaim
	end
	if daily.LastDay and daily.LastDay > 0 then
		return (daily.LastDay + 1) * 86400 - 1
	end
	return 0
end

-- Where the streak stands now: the card to show (1-7), whether it can be claimed, the
-- streak count to display, and when the next one opens (0 when it's open now).
function RewardService:DailyStatus(data): (number, boolean, number, number)
	local daily = data.Daily
	local count = #Rewards.Daily
	local last = lastClaim(daily)
	local t = now()
	if daily.Streak <= 0 or last <= 0 or t - last >= Rewards.DailyStreakWindow then
		return 1, true, 0, 0
	end
	if t - last < Rewards.DailyCooldown then
		return (daily.Streak - 1) % count + 1, false, daily.Streak, last + Rewards.DailyCooldown
	end
	return daily.Streak % count + 1, true, daily.Streak, 0
end

local function claimDaily(player: Player): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return false, "Still loading"
	end
	local index, ready, streak = RewardService:DailyStatus(data)
	if not ready then
		return false, "Come back tomorrow for the next reward!"
	end
	data.Daily.Streak = streak + 1
	data.Daily.LastDay = Rewards.day(now())
	data.Daily.LastClaim = now()
	local got = grant(player, Rewards.Daily[index], "Daily" .. index)
	S.StateService:Mark(player)
	return true, `Day {index} reward: {got}!`
end

-------------------------------------------------------------------------- playtime

local function claimPlaytime(player: Player, index: any): (boolean, string?)
	local rt = runtime(player)
	local entry = type(index) == "number" and Rewards.Playtime[index]
	if not rt or not entry then
		return false, nil
	end
	if rt.PlaytimeClaimed[index] then
		return false, "Already claimed"
	end
	if rt.Playtime < entry.Minutes * 60 then
		return false, `Play {Format.time(entry.Minutes * 60 - rt.Playtime)} more to unlock this gift`
	end
	rt.PlaytimeClaimed[index] = true
	local got = grant(player, entry.Reward, "Playtime" .. index)
	S.StateService:Mark(player)
	return true, `Gift: {got}!`
end

-------------------------------------------------------------------------- lucky wheel

local wheelRng = Random.new()

-- Whether the free spin can be used now, and when the next one opens (nil = never again).
local function freeSpin(data): (boolean, number?)
	local at = data.Flags.FreeSpinAt
	if type(at) ~= "number" then
		return true, nil
	end
	local every = Rewards.Wheel.FreeEvery
	if not every then
		return false, nil
	end
	return now() - at >= every, at + every
end

function RewardService:AddSpins(player: Player, count: number): number
	local data = S.DataService:GetData(player)
	if not data then
		return 0
	end
	data.Spins = (data.Spins or 0) + count
	S.StateService:Mark(player)
	return data.Spins
end

local function rollSegment(): number
	local pick = wheelRng:NextNumber() * Rewards.wheelTotal()
	for i, seg in Rewards.Wheel.Segments do
		pick -= seg.Weight
		if pick < 0 then
			return i
		end
	end
	return 1
end

local function spin(player: Player): (boolean, string?, number?)
	local data = S.DataService:GetData(player)
	local rt = runtime(player)
	if not data or not rt then
		return false, "Still loading"
	end
	-- One spin at a time: the next one waits for the wheel to stop.
	if (rt.WheelBusyUntil or 0) > os.clock() then
		return false, nil
	end
	local free = freeSpin(data)
	if free then
		data.Flags.FreeSpinAt = now()
	elseif (data.Spins or 0) > 0 then
		data.Spins -= 1
	else
		return false, "No spins left. Get more below!"
	end
	rt.WheelBusyUntil = os.clock() + Rewards.Wheel.SpinSeconds - 0.4
	local index = rollSegment()
	local seg = Rewards.Wheel.Segments[index]
	local got = grant(player, seg.Reward, "Wheel" .. index)
	S.StateService:Mark(player)
	if free then
		-- The tutorial's wheel step finishes once the wheel has stopped (StateService).
		task.delay(Rewards.Wheel.SpinSeconds + 1, function()
			if player.Parent then
				S.StateService:Mark(player)
			end
		end)
	end
	S.AnalyticsService:Custom(player, "WheelSpin", index, { Free = tostring(free) })
	S.AnalyticsService:WheelSpun(player)
	if seg.Weight <= 1 then
		-- After the wheel stops, so the spinner sees it land first.
		local name = player.DisplayName
		task.delay(Rewards.Wheel.SpinSeconds, function()
			Net.fireAll("Announce", `{name} hit the JACKPOT on the Lucky Wheel: {got}!`, "Event")
		end)
	end
	return true, `You won {got}!`, index
end

-------------------------------------------------------------------------- stay

local function startStay(player: Player): (boolean, string?)
	local rt = runtime(player)
	if not rt then
		return false, nil
	end
	if rt.StayAt then
		return true, nil -- already counting
	end
	if rt.Playtime < (rt.StayCooldownUntil or 0) then
		return false, nil
	end
	rt.StayAt = rt.Playtime + Rewards.Stay.Minutes * 60
	S.StateService:Mark(player)
	return true, `Stay {Rewards.Stay.Minutes} minutes for a free potion!`
end

local function tickStay(player: Player, rt)
	if rt.StayAt and rt.Playtime >= rt.StayAt then
		rt.StayAt = nil
		rt.StayCooldownUntil = rt.Playtime + Rewards.Stay.CooldownMinutes * 60
		local got = grant(player, Rewards.Stay.Reward, "Stay")
		notify(player, `Thanks for staying! You got a {got}.`)
		S.StateService:Mark(player)
	end
end

-------------------------------------------------------------------------- group

local function inGroup(player: Player): boolean
	local ok, result = pcall(function()
		return player:IsInGroup(Rewards.Group.Id)
	end)
	if ok and result == true then
		return true
	end
	-- IsInGroup is cached for the session, so someone who just joined from the in-game
	-- prompt reads as "not in": ask the groups web API instead.
	local fresh, groups = pcall(function()
		return GroupService:GetGroupsAsync(player.UserId)
	end)
	if fresh and type(groups) == "table" then
		for _, g in groups do
			if g.Id == Rewards.Group.Id then
				return true
			end
		end
	end
	return false
end

local function claimGroup(player: Player): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data or Rewards.Group.Id == 0 then
		return false, nil
	end
	if data.Flags.GroupRewardClaimed then
		return false, "You already got the group reward"
	end
	if not inGroup(player) then
		return false, `Join {Rewards.Group.Name} first (press Join Group), then claim!`
	end
	data.Flags.GroupRewardClaimed = true
	local got = {}
	for i, reward in Rewards.Group.Rewards do
		table.insert(got, grant(player, reward, "Group" .. i))
	end
	S.StateService:Mark(player)
	return true, `Thanks for joining! You got {table.concat(got, " + ")}`
end

-------------------------------------------------------------------------- events

local function giveEventReward(player: Player, event: Rewards.EventDef)
	local data = S.DataService:GetData(player)
	if not data or data.Flags.EventSignups[event.Id] ~= SIGNED then
		return
	end
	data.Flags.EventSignups[event.Id] = REWARDED
	local got = grant(player, event.Reward, "Event_" .. event.Id)
	notify(player, `{event.Name} is on! Your sign-up gift: {got}`, "Good")
	S.StateService:Mark(player)
end

local function signUp(player: Player, eventId: any): (boolean, string?)
	local data = S.DataService:GetData(player)
	local event = Rewards.currentOrNextEvent(now())
	if not data or not event or event.Id ~= eventId then
		return false, "No event to sign up for right now"
	end
	if data.Flags.EventSignups[event.Id] then
		return false, "You're already signed up!"
	end
	data.Flags.EventSignups[event.Id] = SIGNED
	S.StateService:Mark(player)
	if Rewards.activeEvent(now()) == event then
		giveEventReward(player, event)
		return true, nil
	end
	return true, `Signed up for {event.Name}! Join while it's on to get your gift.`
end

-------------------------------------------------------------------------- snapshot

-- Added to the player snapshot (StateService) as data.Rewards.
function RewardService:Snapshot(player: Player): { [string]: any }?
	local data = S.DataService:GetData(player)
	local rt = runtime(player)
	if not data or not rt then
		return nil
	end
	local index, ready, streak, nextAt = RewardService:DailyStatus(data)
	local event = Rewards.currentOrNextEvent(now())
	-- A plain list of booleans: sparse number keys don't survive remotes.
	local claimed = {}
	for i in Rewards.Playtime do
		claimed[i] = rt.PlaytimeClaimed[i] == true
	end
	return {
		DailyIndex = index,
		DailyReady = ready,
		DailyStreak = streak,
		DailyNextAt = nextAt,
		Playtime = rt.Playtime,
		PlaytimeClaimed = claimed,
		StayLeft = if rt.StayAt then rt.StayAt - rt.Playtime else nil,
		StayAvailable = rt.StayAt == nil and rt.Playtime >= (rt.StayCooldownUntil or 0),
		GroupId = Rewards.Group.Id,
		GroupClaimed = data.Flags.GroupRewardClaimed == true,
		EventId = if event then event.Id else nil,
		EventSignedUp = if event then data.Flags.EventSignups[event.Id] ~= nil else false,
		Spins = data.Spins or 0,
		FreeSpin = (freeSpin(data)),
		FreeSpinAt = select(2, freeSpin(data)),
		Now = now(),
	}
end

local ACTIONS: { [string]: (Player, any) -> (boolean, string?, any) } = {
	ClaimDaily = claimDaily,
	ClaimPlaytime = claimPlaytime,
	StartStay = startStay,
	ClaimGroup = claimGroup,
	SignUp = signUp,
	Spin = spin,
}

function RewardService:Do(player: Player, action: string, arg: any): (boolean, string?, any)
	local handler = ACTIONS[action]
	if not handler then
		return false, nil
	end
	return handler(player, arg)
end

function RewardService:Init(services)
	S = services
	Net.onInvoke("Rewards", function(player, action, arg)
		if type(action) ~= "string" then
			return false, nil
		end
		return RewardService:Do(player, action, arg)
	end)
	S.DataService.ProfileLoaded:Connect(function(player, session)
		session.Runtime.Playtime = 0
		session.Runtime.PlaytimeClaimed = {}
		local event = Rewards.activeEvent(now())
		if event then
			giveEventReward(player, event)
		end
	end)
end

function RewardService:Start()
	task.spawn(function()
		while true do
			task.wait(1)
			for player, session in S.DataService:GetSessions() do
				local rt = session.Runtime
				if rt.Playtime then
					rt.Playtime += 1
					-- Badge on the Rewards button: refresh the snapshot when a gift unlocks.
					for _, entry in Rewards.Playtime do
						if rt.Playtime == entry.Minutes * 60 then
							S.StateService:Mark(player)
						end
					end
					tickStay(player, rt)
				end
				-- And when the next daily reward opens (24 hours after the last claim).
				if session.Data then
					local _, ready = RewardService:DailyStatus(session.Data)
					if ready and rt.DailyWasReady == false then
						S.StateService:Mark(player)
					end
					rt.DailyWasReady = ready
				end
			end
		end
	end)
end

return RewardService
