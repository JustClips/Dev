--!strict
-- Rarities, hatch times and mutations (GAME_PLAN §5.3).
local Types = require(script.Parent.Parent.Types)

type RarityDef = Types.RarityDef
type MutationDef = Types.MutationDef

local Rarities: { RarityDef } = {
	{ Name = "Common", Order = 1, Weight = 100, HatchSeconds = 15, Color = Color3.fromRGB(190, 190, 190) },
	{ Name = "Uncommon", Order = 2, Weight = 32, HatchSeconds = 45, Color = Color3.fromRGB(90, 220, 110) },
	{ Name = "Rare", Order = 3, Weight = 9, HatchSeconds = 120, Color = Color3.fromRGB(70, 150, 255) },
	{ Name = "Epic", Order = 4, Weight = 2.5, HatchSeconds = 300, Color = Color3.fromRGB(170, 90, 255) },
	{ Name = "Legendary", Order = 5, Weight = 0.6, HatchSeconds = 720, Color = Color3.fromRGB(255, 200, 40) },
	{ Name = "Mythic", Order = 6, Weight = 0.12, HatchSeconds = 1800, Color = Color3.fromRGB(255, 60, 70) },
	{ Name = "Cosmic", Order = 7, Weight = 0.02, HatchSeconds = 3600, Color = Color3.fromRGB(255, 120, 230) },
}

local Mutations: { MutationDef } = {
	-- Checked rarest first.
	{ Name = "MoonDusted", Label = "Sparkly", Chance = 500, IncomeMult = 5, Color = Color3.fromRGB(220, 235, 255) },
	{ Name = "Rainbow", Label = "Rainbow", Chance = 100, IncomeMult = 3, Color = Color3.fromRGB(255, 120, 230) },
	{ Name = "Golden", Label = "Golden", Chance = 20, IncomeMult = 2, Color = Color3.fromRGB(255, 205, 50) },
	-- Weather mutations: only during their weather (Config/Weather), never in the roll above.
	{ Name = "Starstruck", Label = "Starstruck", Chance = 0, IncomeMult = 5, Color = Color3.fromRGB(255, 225, 110), WeatherOnly = true },
	{ Name = "Starlit", Label = "Starlit", Chance = 0, IncomeMult = 4, Color = Color3.fromRGB(120, 255, 210), WeatherOnly = true },
	{ Name = "Bloodlit", Label = "Bloodlit", Chance = 0, IncomeMult = 4, Color = Color3.fromRGB(230, 40, 50), WeatherOnly = true },
	{ Name = "Disco", Label = "Disco", Chance = 0, IncomeMult = 3, Color = Color3.fromRGB(200, 90, 255), WeatherOnly = true },
	{ Name = "Shocked", Label = "Charged", Chance = 0, IncomeMult = 2.5, Color = Color3.fromRGB(255, 230, 70), WeatherOnly = true },
	{ Name = "Frozen", Label = "Frozen", Chance = 0, IncomeMult = 2, Color = Color3.fromRGB(170, 225, 255), WeatherOnly = true },
	{ Name = "Windswept", Label = "Windswept", Chance = 0, IncomeMult = 1.5, Color = Color3.fromRGB(255, 165, 70), WeatherOnly = true },
	{ Name = "Wet", Label = "Wet", Chance = 0, IncomeMult = 1.5, Color = Color3.fromRGB(80, 160, 255), WeatherOnly = true },
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
	-- A brand-new player's first egg opens after this many seconds (HatchService).
	FirstEggSeconds = 3,
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

-- Any egg can hatch any rarity (Dev, 2026-10-30). The egg's rarity is the most likely
-- result; it can step up (rarer the further) or drop up to 3 tiers. Chances are % per
-- tiers moved. A Common egg hatches a Cosmic 1 in 1,000,000 times.
Eggs.HatchOdds = {
	Up = { 5, 0.5, 0.06, 0.006, 0.0008, 0.0001 }, -- 1, 2, ... 6 tiers up
	Down = { 10, 3, 1 }, -- 1, 2, 3 tiers down (never further)
	UpCap = 40, -- with luck, step-ups never take more than this %
}

-- Chance (%) of each pet rarity from an egg, by rarity order. Luck (1 = none) multiplies
-- every step-up by sqrt(luck): luck already counted once when the egg was found.
-- noDrop removes the drops (used after a drop on Mythic and Cosmic eggs).
function Eggs.hatchOdds(eggRarity: string, luck: number?, noDrop: boolean?): { number }
	local e = Eggs.order(eggRarity)
	local odds = table.create(#Rarities, 0)
	if e == 0 then
		odds[1] = 100
		return odds
	end
	local boost = math.sqrt(math.max(1, luck or 1))
	local up = 0
	for k = 1, #Rarities - e do
		odds[e + k] = (Eggs.HatchOdds.Up[k] or 0) * boost
		up += odds[e + k]
	end
	if up > Eggs.HatchOdds.UpCap then
		for k = e + 1, #Rarities do
			odds[k] *= Eggs.HatchOdds.UpCap / up
		end
		up = Eggs.HatchOdds.UpCap
	end
	local down = 0
	if not noDrop then
		for k = 1, math.min(e - 1, #Eggs.HatchOdds.Down) do
			odds[e - k] = Eggs.HatchOdds.Down[k]
			down += odds[e - k]
		end
	end
	odds[e] = 100 - up - down
	return odds
end

-- Rolls the pet rarity inside an egg.
function Eggs.rollPetRarity(rng: Random, eggRarity: string, luck: number?, noDrop: boolean?): string
	local odds = Eggs.hatchOdds(eggRarity, luck, noDrop)
	local roll = rng:NextNumber() * 100
	for i, chance in odds do
		roll -= chance
		if roll < 0 then
			return Rarities[i].Name
		end
	end
	return if Eggs.ByName[eggRarity] then eggRarity else "Common"
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
