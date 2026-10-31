--!strict
-- Goals (Dev, 2026-10-31): after the tutorial, three goals are always on screen above the
-- backpack bar (like "Clean 150 leaves", "Earn $1K", "Get a Rare pet"). Finishing all three
-- gives a free Lucky Wheel spin, then the next, bigger three show up. Endless: rounds past
-- the list scale up from the last one. Every goal is doable for free.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)

-- Kind: Leaves (cleaned since the round started), Cash (earned since the round started),
-- Pet (own a pet of at least this rarity), Hatches (hatched since the round started).
export type Goal = { Kind: string, Goal: number?, Rarity: string? }
export type Round = { Goal }

local Goals = {}

Goals.Rounds = {
	{ { Kind = "Leaves", Goal = 150 }, { Kind = "Cash", Goal = 1_000 }, { Kind = "Pet", Rarity = "Rare" } },
	{ { Kind = "Leaves", Goal = 1_000 }, { Kind = "Cash", Goal = 25_000 }, { Kind = "Pet", Rarity = "Epic" } },
	{ { Kind = "Leaves", Goal = 4_000 }, { Kind = "Cash", Goal = 1_000_000 }, { Kind = "Hatches", Goal = 25 } },
} :: { Round }

-- What finishing a round gives (RewardService reward).
Goals.Reward = { Kind = "Spin", Amount = 1 }
Goals.RewardText = "a FREE SPIN"

-- Round n (1-based). Past the list: leaves x2, cash x10 and hatches +15 per round.
function Goals.round(n: number): Round
	local fixed = Goals.Rounds[n]
	if fixed then
		return fixed
	end
	local extra = n - #Goals.Rounds
	return {
		{ Kind = "Leaves", Goal = 4_000 * 2 ^ extra },
		{ Kind = "Cash", Goal = 1_000_000 * 10 ^ extra },
		{ Kind = "Hatches", Goal = 25 + 15 * extra },
	}
end

function Goals.text(goal: Goal): string
	if goal.Kind == "Leaves" then
		return `Clean {Format.number(goal.Goal or 0)} leaves`
	elseif goal.Kind == "Cash" then
		return `Earn {Format.cash(goal.Goal or 0)}`
	elseif goal.Kind == "Pet" then
		local rarity = goal.Rarity or "Rare"
		local article = if string.match(rarity, "^[AEIOU]") then "an" else "a"
		return `Get {article} {rarity} pet`
	elseif goal.Kind == "Hatches" then
		return `Hatch {Format.number(goal.Goal or 0)} eggs`
	end
	return "?"
end

-- "45/150", "$450/$1K", "0/1".
function Goals.progressText(goal: Goal, progress: number): string
	if goal.Kind == "Cash" then
		return `{Format.cash(progress)}/{Format.cash(goal.Goal or 0)}`
	elseif goal.Kind == "Pet" then
		return `{progress}/1`
	end
	return `{Format.number(progress)}/{Format.number(goal.Goal or 0)}`
end

return Goals
