--!strict
-- Starter goals (Dev, 2026-10-31): after the tutorial, a short list of next goals with
-- small bonuses for new players, shown one at a time on the step card above the hotbar.
-- GoalService checks them whenever your state changes and pays the bonus on its own.
-- Every goal is doable for free. After the last one the card goes away.
--
-- "count" stats count from when the goal started (Stats deltas); "reach" stats look at
-- where you are now.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Items = require(Shared.Config.Items)

export type Reward = { Kind: string, Seconds: number?, Item: string?, Amount: number?, Rarity: string? }
export type Goal = { Text: string, Stat: string, Goal: number, Reward: Reward, Icon: string }

local Goals = {}

Goals.Stats = {
	Leaves = "count", -- Stats.TilesCleared
	EggsFound = "count", -- Stats.EggsFound
	Hatches = "count", -- Stats.Hatches
	Placed = "reach", -- pets on your base right now
	Power = "reach", -- Sweep Power level
	Tool = "reach", -- tool tier owned
	Zones = "reach", -- zones unlocked (Backyard counts)
} :: { [string]: string }

Goals.List = {
	{ Text = "Sweep {goal} leaf piles", Stat = "Leaves", Goal = 150, Reward = { Kind = "Cash", Seconds = 60 }, Icon = "Icon_Dust" },
	{ Text = "Find {goal} eggs in the leaves", Stat = "EggsFound", Goal = 2, Reward = { Kind = "Item", Item = "LuckPotion", Amount = 1 }, Icon = "Icon_Egg" },
	{ Text = "Hatch {goal} eggs", Stat = "Hatches", Goal = 2, Reward = { Kind = "Cash", Seconds = 90 }, Icon = "Icon_Egg" },
	{ Text = "Have {goal} pets on your base", Stat = "Placed", Goal = 3, Reward = { Kind = "Item", Item = "HatchPotion", Amount = 1 }, Icon = "Icon_Alien" },
	{ Text = "Get Sweep Power to level {goal}", Stat = "Power", Goal = 3, Reward = { Kind = "Cash", Seconds = 120 }, Icon = "Icon_Upgrade" },
	{ Text = "Get the Mop in Gear", Stat = "Tool", Goal = 3, Reward = { Kind = "Item", Item = "SpeedPotion", Amount = 1 }, Icon = "Icon_Tool_Mop" },
	{ Text = "Unlock the Park", Stat = "Zones", Goal = 2, Reward = { Kind = "Egg", Rarity = "Uncommon" }, Icon = "Icon_Zones" },
	{ Text = "Hatch {goal} eggs", Stat = "Hatches", Goal = 10, Reward = { Kind = "Egg", Rarity = "Rare" }, Icon = "Icon_Egg" },
} :: { Goal }

for _, goal in Goals.List do
	assert(Goals.Stats[goal.Stat], `Goals: unknown stat {goal.Stat}`)
end

function Goals.text(goal: Goal): string
	return (string.gsub(goal.Text, "{goal}", Format.number(goal.Goal)))
end

-- "Rare Egg", "Luck Potion", "Cash".
function Goals.describe(reward: Reward): string
	if reward.Kind == "Egg" then
		return `{reward.Rarity} Egg`
	elseif reward.Kind == "Item" then
		local def = Items.ById[reward.Item or ""]
		local name = if def then def.Name else "Item"
		return if (reward.Amount or 1) > 1 then `{name} x{reward.Amount}` else name
	end
	return "Cash"
end

return Goals
