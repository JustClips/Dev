--!strict
-- Quests (Dev, 2026-10-31; replaced the 3-goal strip). Two kinds:
--   Jobs   the Quest Master's chain on the left of every base. One at a time. When it's done
--          you walk back to him and talk to claim the reward, then he hands you the next.
--          After the list the jobs keep coming (Quests.job scales them up).
--   Daily  3 new quests every UTC day, sized to how far you are (Quests.daily). Claimed
--          anywhere from the Quests window; all 3 claimed = the bonus (a free spin).
-- Server: QuestService. Client: QuestController (strip + window + NPC dialog).
--
-- Kinds counted from when the quest started (a Stats counter, or cash earned):
--   Leaves, Cash, Hatches, Eggs (eggs found), Sells, Bunnies, Golden (golden piles),
--   Trash, Upgrades (levels bought), Spins (wheel spins), Items (items used),
--   Minutes (minutes played)
-- Kinds that check what you have right now:
--   Pet (own a pet of at least Rarity), Tool (own tool tier Goal), Zones (zones unlocked),
--   Placed (pets on your base), Index (pets discovered), Rebirths
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Tools = require(Shared.Config.Tools)

export type Reward = { Kind: string, Seconds: number?, Floor: number?, Item: string?, Amount: number?, Rarity: string?, Bonus: Reward? }
export type Quest = { Kind: string, Goal: number?, Rarity: string?, Reward: Reward? }

local Quests = {}

Quests.NpcName = "Quest Master"

-- Counted kinds: which Stats counter each one reads.
Quests.Counters = {
	Leaves = "TilesCleared",
	Hatches = "Hatches",
	Eggs = "EggsFound",
	Sells = "Sells",
	Bunnies = "Bunnies",
	Golden = "Golden",
	Trash = "Trash",
	Upgrades = "Upgrades",
	Spins = "Spins",
	Items = "ItemsUsed",
	-- Cash and Minutes are worked out by QuestService (BigNum cash, live playtime).
	Cash = true,
	Minutes = true,
} :: { [string]: any }

local CASH = function(seconds: number, floor: number?): Reward
	return { Kind = "Cash", Seconds = seconds, Floor = floor or 0.3 }
end
local ITEM = function(id: string, amount: number?): Reward
	return { Kind = "Item", Item = id, Amount = amount or 1 }
end
local EGG = function(rarity: string): Reward
	return { Kind = "Egg", Rarity = rarity }
end
local SPIN = function(amount: number?): Reward
	return { Kind = "Spin", Amount = amount or 1 }
end

-- The Quest Master's jobs, in order. They start once the tutorial is done (the tutorial
-- already covers the first sweep, egg, sell, broom, upgrade and spin).
Quests.Jobs = {
	{ Kind = "Leaves", Goal = 200, Reward = CASH(120, 0.3) },
	{ Kind = "Sells", Goal = 3, Reward = ITEM("LuckPotion") },
	{ Kind = "Bunnies", Goal = 2, Reward = CASH(180, 0.3) },
	{ Kind = "Hatches", Goal = 3, Reward = ITEM("HatchPotion", 2) },
	{ Kind = "Golden", Goal = 3, Reward = CASH(240, 0.4) },
	{ Kind = "Upgrades", Goal = 5, Reward = ITEM("SpeedPotion") },
	{ Kind = "Tool", Goal = 3, Reward = CASH(300, 0.4) },
	{ Kind = "Placed", Goal = 4, Reward = EGG("Rare") },
	{ Kind = "Pet", Rarity = "Rare", Reward = SPIN(1) },
	{ Kind = "Trash", Goal = 10, Reward = ITEM("CashPotion") },
	{ Kind = "Items", Goal = 1, Reward = CASH(300, 0.5) },
	{ Kind = "Cash", Goal = 50_000, Reward = ITEM("LuckPotion", 2) },
	{ Kind = "Zones", Goal = 2, Reward = EGG("Epic") },
	{ Kind = "Eggs", Goal = 15, Reward = SPIN(2) },
	{ Kind = "Hatches", Goal = 25, Reward = ITEM("SuperLuckPotion") },
	{ Kind = "Pet", Rarity = "Epic", Reward = ITEM("HugeCharm") },
	{ Kind = "Tool", Goal = 5, Reward = CASH(600, 0.5) },
	{ Kind = "Index", Goal = 15, Reward = SPIN(2) },
	{ Kind = "Cash", Goal = 1_000_000, Reward = ITEM("MegaCashPotion") },
	{ Kind = "Rebirths", Goal = 1, Reward = EGG("Legendary") },
} :: { Quest }

-- Job n (1-based). Past the list they loop over five kinds, bigger every lap.
local ENDLESS = { "Leaves", "Hatches", "Golden", "Bunnies", "Eggs" }
function Quests.job(n: number): Quest
	local fixed = Quests.Jobs[n]
	if fixed then
		return fixed
	end
	local extra = n - #Quests.Jobs - 1 -- 0, 1, 2...
	local kind = ENDLESS[extra % #ENDLESS + 1]
	local lap = extra // #ENDLESS + 1
	local goal = if kind == "Leaves"
		then 3_000 * lap
		elseif kind == "Hatches" then 20 + 10 * lap
		elseif kind == "Golden" then 15 + 10 * lap
		elseif kind == "Bunnies" then 8 + 4 * lap
		else 20 + 10 * lap
	local reward = if extra % 3 == 2 then SPIN(1) else CASH(600, 0.5)
	return { Kind = kind, Goal = goal, Reward = reward }
end

-- Daily quests --------------------------------------------------------------------
-- Each template: the kind, its size at tier t (t = 1 for new players, grows with jobs
-- done and rebirths) and the reward. Cash goals are set by QuestService from your income.
Quests.DailyPool = {
	{ Kind = "Leaves", Size = function(t: number) return 400 * t end, Reward = CASH(300, 0.4) },
	{ Kind = "Hatches", Size = function(t: number) return 3 + 2 * t end, Reward = ITEM("HatchPotion", 2) },
	{ Kind = "Sells", Size = function(t: number) return 4 + t end, Reward = CASH(300, 0.4) },
	{ Kind = "Golden", Size = function(t: number) return 4 + 2 * t end, Reward = ITEM("LuckPotion") },
	{ Kind = "Bunnies", Size = function(t: number) return 2 + t end, Reward = ITEM("SpeedPotion") },
	{ Kind = "Eggs", Size = function(t: number) return 4 + 2 * t end, Reward = CASH(300, 0.4) },
	{ Kind = "Trash", Size = function(t: number) return 15 + 10 * t end, Reward = ITEM("CashPotion") },
	{ Kind = "Upgrades", Size = function(t: number) return 4 + 2 * t end, Reward = CASH(300, 0.4) },
	{ Kind = "Minutes", Size = function(_t: number) return 15 end, Reward = ITEM("LuckPotion") },
	{ Kind = "Cash", Size = function(_t: number) return 0 end, Reward = ITEM("CashPotion") },
} :: { { Kind: string, Size: (number) -> number, Reward: Reward } }
Quests.DailyCount = 3
Quests.DailyBonus = SPIN(1)
Quests.DailyBonusText = "a FREE SPIN"

-- How big daily quests are for a player.
function Quests.tier(jobsDone: number, rebirths: number): number
	return math.clamp(1 + jobsDone // 5 + rebirths, 1, 12)
end

-- Text -------------------------------------------------------------------------
local function article(word: string): string
	return if string.match(word, "^[AEIOU]") then "an" else "a"
end

function Quests.text(q: Quest): string
	local n = q.Goal or 0
	local num = Format.number(n)
	local k = q.Kind
	if k == "Leaves" then
		return `Clean {num} leaves`
	elseif k == "Cash" then
		return `Earn {Format.cash(n)}`
	elseif k == "Hatches" then
		return if n == 1 then "Hatch an egg" else `Hatch {num} eggs`
	elseif k == "Eggs" then
		return if n == 1 then "Find an egg" else `Find {num} eggs`
	elseif k == "Sells" then
		return if n == 1 then "Sell your bag" else `Sell your bag {num} times`
	elseif k == "Bunnies" then
		return if n == 1 then "Catch a dust bunny" else `Catch {num} dust bunnies`
	elseif k == "Golden" then
		return if n == 1 then "Sweep a golden pile" else `Sweep {num} golden piles`
	elseif k == "Trash" then
		return `Pick up {num} trash`
	elseif k == "Upgrades" then
		return if n == 1 then "Buy an upgrade" else `Buy {num} upgrades`
	elseif k == "Spins" then
		return if n == 1 then "Spin the Lucky Wheel" else `Spin the wheel {num} times`
	elseif k == "Items" then
		return if n == 1 then "Use a potion" else `Use {num} potions`
	elseif k == "Minutes" then
		return `Play for {num} minutes`
	elseif k == "Pet" then
		local r = q.Rarity or "Rare"
		return `Get {article(r)} {r} pet`
	elseif k == "Tool" then
		local name = Tools.get(n).Name
		return `Get the {name}`
	elseif k == "Zones" then
		return if n <= 2 then "Unlock a new zone" else `Unlock {n - 1} new zones`
	elseif k == "Placed" then
		return `Put {num} pets on your base`
	elseif k == "Index" then
		return `Discover {num} pets`
	elseif k == "Rebirths" then
		return if n == 1 then "Rebirth" else `Rebirth {num} times`
	end
	return "?"
end

-- What a quest needs in total (Pet and Tool: 1, you have it or not).
function Quests.target(q: Quest): number
	if q.Kind == "Pet" or q.Kind == "Tool" then
		return 1
	end
	return math.max(1, q.Goal or 1)
end

-- "45/150", "$450/$1K", "0/1".
function Quests.progressText(q: Quest, progress: number): string
	if q.Kind == "Cash" then
		return `{Format.cash(progress)}/{Format.cash(q.Goal or 0)}`
	elseif q.Kind == "Tool" or q.Kind == "Pet" then
		return `{math.min(progress, 1)}/1`
	end
	return `{Format.number(progress)}/{Format.number(Quests.target(q))}`
end

return Quests
