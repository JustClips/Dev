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
local MapBuilder = require(script.Parent.Parent.Lib.MapBuilder)

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
	end
	return ""
end

local function runtime(player: Player): any
	local session = S.DataService:GetSession(player)
	return session and session.Runtime
end

-------------------------------------------------------------------------- daily

-- Where the streak stands today: the card to show (1-7), whether it can be claimed now,
-- and the streak count to display.
function RewardService:DailyStatus(data): (number, boolean, number)
	local today = Rewards.day(now())
	local daily = data.Daily
	local count = #Rewards.Daily
	if daily.LastDay == today then
		return (daily.Streak - 1) % count + 1, false, daily.Streak
	elseif daily.LastDay == today - 1 then
		return daily.Streak % count + 1, true, daily.Streak
	end
	return 1, true, 0
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
	local index, ready, streak = RewardService:DailyStatus(data)
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
		Playtime = rt.Playtime,
		PlaytimeClaimed = claimed,
		StayLeft = if rt.StayAt then rt.StayAt - rt.Playtime else nil,
		StayAvailable = rt.StayAt == nil and rt.Playtime >= (rt.StayCooldownUntil or 0),
		GroupId = Rewards.Group.Id,
		GroupClaimed = data.Flags.GroupRewardClaimed == true,
		EventId = if event then event.Id else nil,
		EventSignedUp = if event then data.Flags.EventSignups[event.Id] ~= nil else false,
		Now = now(),
	}
end

local ACTIONS: { [string]: (Player, any) -> (boolean, string?) } = {
	ClaimDaily = claimDaily,
	ClaimPlaytime = claimPlaytime,
	StartStay = startStay,
	ClaimGroup = claimGroup,
	SignUp = signUp,
}

function RewardService:Do(player: Player, action: string, arg: any): (boolean, string?)
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

-- The plaza board: event name and how long until it starts / ends.
local function updateBoard()
	local sign = MapBuilder.getEventSign()
	if not sign then
		return
	end
	local t = now()
	local event = Rewards.currentOrNextEvent(t)
	local title, sub = "EVENTS", "No event right now. Check back soon!"
	if event then
		title = string.upper(event.Name)
		sub = if t >= event.StartsAt
			then `LIVE! {event.LuckMult}x luck. Ends in {Format.countdown(event.EndsAt - t)}`
			else `Starts in {Format.countdown(event.StartsAt - t)}. Sign up below!`
	end
	for _, label in sign.Titles do
		label.Text = title
	end
	for _, label in sign.Subs do
		label.Text = sub
		label.Visible = true
	end
end

function RewardService:Start()
	task.spawn(function()
		while true do
			task.wait(1)
			updateBoard()
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
			end
		end
	end)
end

return RewardService
