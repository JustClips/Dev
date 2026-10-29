--!strict
-- Free rewards that bring players back and keep them playing:
--   Daily: a 7-day streak (miss a day and it starts over). Day 7 is the big one.
--   Playtime: gifts after 2, 5, 10, 20, 35 and 60 minutes in one session (front-loaded so new
--     players get something right away).
--   Stay: when a player opens the Roblox menu (about to leave), offer a potion for 5 more minutes.
--   Group: join the group for potions + cash. Hidden while Group.Id is 0.
--   Events: sign up on the board in the plaza. Everyone gets the event's luck while it runs,
--     and signed-up players get the event reward when they join during it.
-- Cash rewards scale like cash packs: Seconds of the player's earnings, and at least
-- Floor x the price of the next thing they're saving for.

export type Reward = {
	Kind: string, -- "Cash" | "Item" | "Egg"
	Seconds: number?, -- Cash
	Floor: number?, -- Cash
	Item: string?, -- Item
	Amount: number?, -- Item
	Rarity: string?, -- Egg
}

export type EventDef = {
	Id: string,
	Name: string,
	Description: string,
	StartsAt: number, -- unix time (UTC)
	EndsAt: number,
	LuckMult: number,
	Reward: Reward,
}

local Rewards = {}

Rewards.Daily = {
	{ Kind = "Cash", Seconds = 300, Floor = 0.3 },
	{ Kind = "Item", Item = "LuckPotion", Amount = 1 },
	{ Kind = "Cash", Seconds = 600, Floor = 0.5 },
	{ Kind = "Item", Item = "CashPotion", Amount = 2 },
	{ Kind = "Egg", Rarity = "Rare" },
	{ Kind = "Item", Item = "HatchPotion", Amount = 2 },
	{ Kind = "Egg", Rarity = "Epic" },
} :: { Reward }

-- Minutes of play in one session -> gift. Claimed ones reset when the player rejoins.
Rewards.Playtime = {
	{ Minutes = 2, Reward = { Kind = "Cash", Seconds = 120, Floor = 0.2 } },
	{ Minutes = 5, Reward = { Kind = "Item", Item = "SpeedPotion", Amount = 1 } },
	{ Minutes = 10, Reward = { Kind = "Cash", Seconds = 300, Floor = 0.3 } },
	{ Minutes = 20, Reward = { Kind = "Item", Item = "LuckPotion", Amount = 1 } },
	{ Minutes = 35, Reward = { Kind = "Egg", Rarity = "Rare" } },
	{ Minutes = 60, Reward = { Kind = "Item", Item = "HatchPotion", Amount = 2 } },
} :: { { Minutes: number, Reward: Reward } }

-- Finishing the tutorial (first egg hatched, pet placed, first sell, first tool bought).
Rewards.Tutorial = {
	Cash = 750,
	Items = { LuckPotion = 1, CashPotion = 1 } :: { [string]: number },
}

Rewards.Stay = {
	Minutes = 5,
	CooldownMinutes = 30, -- one stay offer per half hour
	Reward = { Kind = "Item", Item = "LuckPotion", Amount = 1 } :: Reward,
}

Rewards.Group = {
	Id = 351097046, -- the Roblox group (0 turns the group reward off)
	Name = "Eclipse Technologies",
	Rewards = {
		{ Kind = "Item", Item = "LuckPotion", Amount = 2 },
		{ Kind = "Cash", Seconds = 600, Floor = 0.5 },
	} :: { Reward },
}

Rewards.Events = {
	{
		Id = "MeteorWeekend1",
		Name = "Egg Rain Weekend",
		Description = "2x egg luck for all! Sign up for 3 free Hatch Potions.",
		StartsAt = 1793462400, -- Sat 31 Oct 2026 16:00 UTC
		EndsAt = 1793635200, -- Mon 2 Nov 2026 16:00 UTC
		LuckMult = 2,
		Reward = { Kind = "Item", Item = "HatchPotion", Amount = 3 },
	},
} :: { EventDef }

-- The event that is running at `now`, if any.
function Rewards.activeEvent(now: number): EventDef?
	for _, event in Rewards.Events do
		if now >= event.StartsAt and now < event.EndsAt then
			return event
		end
	end
	return nil
end

-- The running event, or else the next one to come (for the sign-up board).
function Rewards.currentOrNextEvent(now: number): EventDef?
	local active = Rewards.activeEvent(now)
	if active then
		return active
	end
	local best: EventDef? = nil
	for _, event in Rewards.Events do
		if event.StartsAt > now and (best == nil or event.StartsAt < best.StartsAt) then
			best = event
		end
	end
	return best
end

-- Day number (UTC). Old saves recorded the daily claim this way (Daily.LastDay).
function Rewards.day(now: number): number
	return now // 86400
end

-- The daily reward runs on each player's own clock: the next one opens 24 hours after the
-- last claim, and the streak resets if it isn't claimed within 48 hours.
Rewards.DailyCooldown = 24 * 3600
Rewards.DailyStreakWindow = 48 * 3600

return Rewards
