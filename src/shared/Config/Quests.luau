--!strict
-- Quests (Dev, 2026-10-31: new players finished the tutorial and left within ~5 minutes
-- with nothing to aim for). Shown after the tutorial in the step card above the hotbar
-- (tap it for the Quests window). QuestService checks progress whenever your state
-- changes and pays the reward on its own.
--   * Story: one at a time, in order. Short ones first for quick wins.
--   * Daily: 3 a day (UTC day), picked from the pool per player. All 3 done = the daily
--     chest; every 7th day in a row the chest is bigger.
-- Every quest is doable for free: no Robux, no luck needed.
--
-- Stats: "count" quests count from when the quest started (Stats.* deltas), "reach"
-- quests look at where you are now.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Items = require(Shared.Config.Items)

export type Reward = { Kind: string, Seconds: number?, Item: string?, Amount: number?, Rarity: string? }
export type Quest = {
	Id: string,
	Text: string, -- "{goal}" is replaced by the goal number
	Stat: string,
	Goal: number,
	Reward: Reward,
	Icon: string,
}

-- Stat -> how it's counted. count = grows from the quest's start; reach = current value.
local STATS: { [string]: string } = {
	Leaves = "count", -- Stats.TilesCleared
	EggsFound = "count", -- Stats.EggsFound
	Hatches = "count", -- Stats.Hatches
	Sells = "count", -- Stats.Sells
	Upgrades = "count", -- levels bought in the upgrade tree (all hexes added up)
	Placed = "reach", -- pets on your base right now
	Power = "reach", -- Sweep Power level
	Tool = "reach", -- tool tier owned
	Zones = "reach", -- zones unlocked (Backyard counts)
	Index = "reach", -- different pets found
	Rebirths = "reach",
}

local function cash(seconds: number): Reward
	return { Kind = "Cash", Seconds = seconds }
end
local function item(id: string, amount: number?): Reward
	return { Kind = "Item", Item = id, Amount = amount or 1 }
end
local function egg(rarity: string): Reward
	return { Kind = "Egg", Rarity = rarity }
end

local Quests = {}
Quests.Stats = STATS

Quests.Story = {
	{ Id = "S1", Text = "Sweep {goal} leaf piles", Stat = "Leaves", Goal = 150, Reward = cash(60), Icon = "Icon_Dust" },
	{ Id = "S2", Text = "Find {goal} eggs in the leaves", Stat = "EggsFound", Goal = 2, Reward = item("LuckPotion"), Icon = "Icon_Egg" },
	{ Id = "S3", Text = "Hatch {goal} eggs", Stat = "Hatches", Goal = 2, Reward = cash(120), Icon = "Icon_Egg" },
	{ Id = "S4", Text = "Have {goal} pets on your base", Stat = "Placed", Goal = 3, Reward = item("HatchPotion", 2), Icon = "Icon_Alien" },
	{ Id = "S5", Text = "Get Sweep Power to level {goal}", Stat = "Power", Goal = 3, Reward = cash(120), Icon = "Icon_Upgrade" },
	{ Id = "S6", Text = "Sell your leaves {goal} times", Stat = "Sells", Goal = 5, Reward = item("SpeedPotion"), Icon = "Icon_Sell" },
	{ Id = "S7", Text = "Get the Mop in Gear", Stat = "Tool", Goal = 3, Reward = egg("Uncommon"), Icon = "Icon_Tool_Mop" },
	{ Id = "S8", Text = "Unlock the Park", Stat = "Zones", Goal = 2, Reward = item("CashPotion"), Icon = "Icon_Zones" },
	{ Id = "S9", Text = "Hatch {goal} eggs", Stat = "Hatches", Goal = 10, Reward = egg("Rare"), Icon = "Icon_Egg" },
	{ Id = "S10", Text = "Find {goal} different pets", Stat = "Index", Goal = 6, Reward = item("LuckPotion", 2), Icon = "Icon_Index" },
	{ Id = "S11", Text = "Buy {goal} upgrade levels", Stat = "Upgrades", Goal = 15, Reward = cash(300), Icon = "Icon_Upgrade" },
	{ Id = "S12", Text = "Get the Leaf Blower in Gear", Stat = "Tool", Goal = 4, Reward = egg("Rare"), Icon = "Icon_Tool_LeafBlower" },
	{ Id = "S13", Text = "Hatch {goal} eggs", Stat = "Hatches", Goal = 30, Reward = item("HatchPotion", 3), Icon = "Icon_Egg" },
	{ Id = "S14", Text = "Unlock the Beach", Stat = "Zones", Goal = 3, Reward = egg("Epic"), Icon = "Icon_Zones" },
	{ Id = "S15", Text = "Rebirth once", Stat = "Rebirths", Goal = 1, Reward = egg("Epic"), Icon = "Icon_Rebirth" },
	{ Id = "S16", Text = "Find {goal} different pets", Stat = "Index", Goal = 15, Reward = item("SuperLuckPotion"), Icon = "Icon_Index" },
	{ Id = "S17", Text = "Hatch {goal} eggs", Stat = "Hatches", Goal = 100, Reward = egg("Epic"), Icon = "Icon_Egg" },
	{ Id = "S18", Text = "Unlock the City", Stat = "Zones", Goal = 4, Reward = egg("Legendary"), Icon = "Icon_Zones" },
} :: { Quest }

-- Daily pool: 3 are picked each day. Short (about 10-15 minutes all together).
Quests.Daily = {
	{ Id = "D_Leaves", Text = "Sweep {goal} leaf piles", Stat = "Leaves", Goal = 800, Reward = cash(240), Icon = "Icon_Dust" },
	{ Id = "D_Hatch", Text = "Hatch {goal} eggs", Stat = "Hatches", Goal = 5, Reward = item("LuckPotion"), Icon = "Icon_Egg" },
	{ Id = "D_Eggs", Text = "Find {goal} eggs", Stat = "EggsFound", Goal = 6, Reward = item("HatchPotion", 2), Icon = "Icon_Egg" },
	{ Id = "D_Sell", Text = "Sell your leaves {goal} times", Stat = "Sells", Goal = 8, Reward = cash(240), Icon = "Icon_Sell" },
	{ Id = "D_Upgrade", Text = "Buy {goal} upgrade levels", Stat = "Upgrades", Goal = 5, Reward = item("CashPotion"), Icon = "Icon_Upgrade" },
	{ Id = "D_BigSweep", Text = "Sweep {goal} leaf piles", Stat = "Leaves", Goal = 2000, Reward = item("SpeedPotion", 2), Icon = "Icon_Dust" },
} :: { Quest }

Quests.DailyCount = 3
-- All 3 daily quests done.
Quests.DailyChest = egg("Rare")
-- ... on every 7th day in a row.
Quests.WeekChest = egg("Epic")

Quests.ById = {} :: { [string]: Quest }
for _, list in { Quests.Story, Quests.Daily } do
	for _, quest in list do
		assert(STATS[quest.Stat], `Quests: unknown stat {quest.Stat}`)
		Quests.ById[quest.Id] = quest
	end
end

function Quests.text(quest: Quest): string
	return (string.gsub(quest.Text, "{goal}", Format.number(quest.Goal)))
end

-- "Rare Egg", "Luck Potion x2", "Cash".
function Quests.describe(reward: Reward): string
	if reward.Kind == "Egg" then
		return `{reward.Rarity} Egg`
	elseif reward.Kind == "Item" then
		local def = Items.ById[reward.Item or ""]
		local name = if def then def.Name else "Item"
		return if (reward.Amount or 1) > 1 then `{name} x{reward.Amount}` else name
	end
	return "Cash"
end

-- Icon for a reward.
function Quests.rewardIcon(reward: Reward): string
	if reward.Kind == "Egg" then
		return "Icon_Egg"
	elseif reward.Kind == "Item" then
		local def = Items.ById[reward.Item or ""]
		return if def then def.Icon else "Icon_Gift"
	end
	return "Icon_Cash"
end

return Quests
