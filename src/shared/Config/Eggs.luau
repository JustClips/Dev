--!strict
-- Rarities, hatch times and mutations (GAME_PLAN §5.3).
local Types = require(script.Parent.Parent.Types)

type RarityDef = Types.RarityDef
type MutationDef = Types.MutationDef

local Rarities: { RarityDef } = {
	{ Name = "Common", Order = 1, Weight = 100, HatchSeconds = 3, Color = Color3.fromRGB(190, 190, 190) },
	{ Name = "Uncommon", Order = 2, Weight = 32, HatchSeconds = 10, Color = Color3.fromRGB(90, 220, 110) },
	{ Name = "Rare", Order = 3, Weight = 9, HatchSeconds = 30, Color = Color3.fromRGB(70, 150, 255) },
	{ Name = "Epic", Order = 4, Weight = 2.5, HatchSeconds = 120, Color = Color3.fromRGB(170, 90, 255) },
	{ Name = "Legendary", Order = 5, Weight = 0.6, HatchSeconds = 300, Color = Color3.fromRGB(255, 200, 40) },
	{ Name = "Mythic", Order = 6, Weight = 0.12, HatchSeconds = 900, Color = Color3.fromRGB(255, 60, 70) },
	{ Name = "Cosmic", Order = 7, Weight = 0, HatchSeconds = 1800, Color = Color3.fromRGB(255, 120, 230) },
}

local Mutations: { MutationDef } = {
	-- Checked rarest first.
	{ Name = "MoonDusted", Label = "Sparkly", Chance = 500, IncomeMult = 5, Color = Color3.fromRGB(220, 235, 255) },
	{ Name = "Rainbow", Label = "Rainbow", Chance = 100, IncomeMult = 3, Color = Color3.fromRGB(255, 120, 230) },
	{ Name = "Golden", Label = "Golden", Chance = 20, IncomeMult = 2, Color = Color3.fromRGB(255, 205, 50) },
}

local Eggs = {
	Rarities = Rarities,
	ByName = {} :: { [string]: RarityDef },
	Mutations = Mutations,
	MutationByName = {} :: { [string]: MutationDef },
	-- Meteor Shower eggs are Rare or better.
	ShowerWeights = { Rare = 60, Epic = 28, Legendary = 9, Mythic = 3 } :: { [string]: number },
	-- "Faster Hatch" gamepass multiplier on hatch time.
	FasterHatchMult = 0.5,
}

for _, r in Rarities do
	Eggs.ByName[r.Name] = r
end
for _, m in Mutations do
	Eggs.MutationByName[m.Name] = m
end

function Eggs.order(rarity: string): number
	local def = Eggs.ByName[rarity]
	return if def then def.Order else 0
end

-- Growing eggs start small and grow until they're ready to open.
Eggs.StartScale = 0.4

-- How far along a growing egg is (0 just placed, 1 ready).
function Eggs.progress(startsAt: number?, endsAt: number, now: number): number
	local start = startsAt or endsAt
	if endsAt <= start then
		return if now >= endsAt then 1 else 0
	end
	return math.clamp((now - start) / (endsAt - start), 0, 1)
end

-- Size of a growing egg as a share of its full size (eases out, so the growth shows early).
function Eggs.growScale(progress: number): number
	local eased = 1 - (1 - progress) ^ 2
	return Eggs.StartScale + (1 - Eggs.StartScale) * eased
end

return Eggs
