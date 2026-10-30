--!strict
-- Free rewards that bring players back and keep them playing:
--   Daily: a 7-day streak (miss a day and it starts over). Day 7 is the big one.
--   Playtime: gifts after 2, 5, 10, 20, 35 and 60 minutes in one session (front-loaded so new
--     players get something right away).
--   Stay: when a player opens the Roblox menu (about to leave), offer a potion for 5 more minutes.
--   Group: join the group for potions + cash. Hidden while Group.Id is 0.
--   Wheel: the Lucky Wheel (plaza + Spin button on the rail). One free spin, more from the
--     5-minute playtime gift or Robux (Products, Kind "WheelSpins").
--   Events: sign up in the Daily window. Everyone gets the event's luck while it runs,
--     and signed-up players get the event reward when they join during it. None scheduled.
-- Cash rewards scale like cash packs: Seconds of the player's earnings, and at least
-- Floor x the price of the next thing they're saving for.

export type Reward = {
	Kind: string, -- "Cash" | "Item" | "Egg" | "Spin" (Lucky Wheel spins)
	Seconds: number?, -- Cash
	Floor: number?, -- Cash
	Item: string?, -- Item
	Amount: number?, -- Item, Spin
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
	-- Dev (2026-10-30): the 2nd gift is a Lucky Wheel spin instead of the Rare Egg.
	{ Minutes = 5, Reward = { Kind = "Spin", Amount = 1 } },
	{ Minutes = 10, Reward = { Kind = "Cash", Seconds = 300, Floor = 0.3 } },
	{ Minutes = 20, Reward = { Kind = "Item", Item = "LuckPotion", Amount = 1 } },
	{ Minutes = 35, Reward = { Kind = "Item", Item = "SpeedPotion", Amount = 1 } },
	{ Minutes = 60, Reward = { Kind = "Item", Item = "HatchPotion", Amount = 2 } },
} :: { { Minutes: number, Reward: Reward } }

-- Lucky Wheel. Segment i is the wedge from (i-1)*45 to i*45 degrees clockwise from the top
-- (art/wheel_art.py draws the wedges in these colours). Weights add up to 100, so each one
-- is its chance in percent (shown in the wheel window: paid random rewards must show odds).
-- Balance (2026-10-30): a spin costs R$19 when bought. The common half (cash, potions) is
-- worth about 10 minutes of income, like a R$24 cash pack or a Cash Potion (2x for 10 min).
-- Eggs match the daily streak (Rare = day 5, Epic = day 7); the Legendary jackpot is 1 in
-- 100, while a Cosmic egg costs R$99, so spins speed you up without skipping progression.
-- FreeEvery: seconds between free spins, or nil for one free spin ever (Dev, 2026-10-30).
export type WheelSegment = { Reward: Reward, Weight: number, Label: string?, Color: Color3 }

Rewards.Wheel = {
	FreeEvery = nil :: number?,
	SpinSeconds = 4.6, -- how long the wheel turns before the prize shows
	Segments = {
		{ Reward = { Kind = "Cash", Seconds = 600, Floor = 0.4 }, Weight = 26, Color = Color3.fromRGB(92, 214, 92) },
		{ Reward = { Kind = "Item", Item = "LuckPotion", Amount = 1 }, Weight = 16, Color = Color3.fromRGB(76, 168, 255) },
		{ Reward = { Kind = "Egg", Rarity = "Rare" }, Weight = 12, Color = Color3.fromRGB(155, 107, 255) },
		{ Reward = { Kind = "Item", Item = "CashPotion", Amount = 1 }, Weight = 14, Color = Color3.fromRGB(255, 154, 60) },
		{ Reward = { Kind = "Egg", Rarity = "Legendary" }, Weight = 1, Color = Color3.fromRGB(255, 194, 46) },
		{ Reward = { Kind = "Item", Item = "HatchPotion", Amount = 2 }, Weight = 12, Color = Color3.fromRGB(127, 211, 255) },
		{ Reward = { Kind = "Item", Item = "SpeedPotion", Amount = 1 }, Weight = 14, Color = Color3.fromRGB(255, 126, 182) },
		{ Reward = { Kind = "Egg", Rarity = "Epic" }, Weight = 5, Color = Color3.fromRGB(255, 75, 85) },
	} :: { WheelSegment },
}

-- Total weight of the wheel (100 while the weights are percentages).
function Rewards.wheelTotal(): number
	local total = 0
	for _, seg in Rewards.Wheel.Segments do
		total += seg.Weight
	end
	return total
end

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

-- No events scheduled (Dev removed the sign-up event, 2026-10-29). Add one here to bring
-- back the Daily window panel, the HUD chip and the luck boost.
Rewards.Events = {} :: { EventDef }

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
