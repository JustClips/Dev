--!strict
-- Egg and pet weights (like Grow a Garden fruit weights).
--   Every egg gets a size class when it's found (Normal, Big, Heavy, Giant, Colossal) and a
--   weight in kg. Luck makes the bigger classes more likely.
--   The pet that hatches weighs PetKg[rarity] x the egg's size multiplier x 0.85-1.15.
--   A pet earns (its weight / PetKg[rarity]) x its normal income, so a 2x-heavy pet earns 2x.
--   Old pets and eggs without a weight count as exactly average (multiplier 1).

export type SizeClass = {
	Name: string,
	Weight: number, -- roll weight
	Min: number, -- egg size multiplier range
	Max: number,
	Color: Color3,
}

local Weights = {}

-- Average egg weight per rarity (kg).
Weights.EggKg = {
	Common = 1,
	Uncommon = 1.4,
	Rare = 2,
	Epic = 3,
	Legendary = 4.5,
	Mythic = 7,
	Cosmic = 10,
} :: { [string]: number }

-- Average pet weight per rarity (kg).
Weights.PetKg = {
	Common = 1.2,
	Uncommon = 2,
	Rare = 3.5,
	Epic = 6,
	Legendary = 10,
	Mythic = 18,
	Cosmic = 30,
} :: { [string]: number }

Weights.Classes = {
	{ Name = "Normal", Weight = 64, Min = 0.8, Max = 1.2, Color = Color3.fromRGB(255, 255, 255) },
	{ Name = "Big", Weight = 26, Min = 1.2, Max = 1.7, Color = Color3.fromRGB(124, 255, 140) },
	{ Name = "Heavy", Weight = 8, Min = 1.7, Max = 2.6, Color = Color3.fromRGB(90, 190, 255) },
	{ Name = "Giant", Weight = 1.8, Min = 2.6, Max = 4, Color = Color3.fromRGB(190, 120, 255) },
	{ Name = "Colossal", Weight = 0.2, Min = 4, Max = 6, Color = Color3.fromRGB(255, 200, 60) },
} :: { SizeClass }

Weights.ByName = {} :: { [string]: SizeClass }
for _, class in Weights.Classes do
	Weights.ByName[class.Name] = class
end

-- How much a pet's weight can swing around the egg's size multiplier.
Weights.PetSpread = { Min = 0.85, Max = 1.15 }

function Weights.eggKg(rarity: string): number
	return Weights.EggKg[rarity] or 1
end

function Weights.petKg(rarity: string): number
	return Weights.PetKg[rarity] or 1
end

-- Rolls a size class; luck (1 = none) boosts every class above Normal by sqrt(luck).
function Weights.rollClass(rng: Random, luck: number): SizeClass
	local boost = math.sqrt(math.max(1, luck))
	local total = 0
	for i, class in Weights.Classes do
		total += class.Weight * (if i == 1 then 1 else boost)
	end
	local roll = rng:NextNumber() * total
	for i, class in Weights.Classes do
		roll -= class.Weight * (if i == 1 then 1 else boost)
		if roll <= 0 then
			return class
		end
	end
	return Weights.Classes[1]
end

-- A new egg's size class and weight (kg).
function Weights.rollEgg(rng: Random, rarity: string, luck: number): (string, number)
	local class = Weights.rollClass(rng, luck)
	local mult = rng:NextNumber(class.Min, class.Max)
	return class.Name, math.floor(Weights.eggKg(rarity) * mult * 100 + 0.5) / 100
end

-- The egg's size multiplier (1 = average).
function Weights.eggMult(rarity: string, eggWeight: number?): number
	return if eggWeight then eggWeight / Weights.eggKg(rarity) else 1
end

-- Weight of the pet hatching from an egg (kg).
function Weights.rollPet(rng: Random, petRarity: string, eggRarity: string, eggWeight: number?): number
	local mult = Weights.eggMult(eggRarity, eggWeight) * rng:NextNumber(Weights.PetSpread.Min, Weights.PetSpread.Max)
	return math.floor(Weights.petKg(petRarity) * mult * 100 + 0.5) / 100
end

-- The pet weights an egg can hatch (kg), for its tooltip.
function Weights.petRange(petRarity: string, eggRarity: string, eggWeight: number?): (number, number)
	local mult = Weights.eggMult(eggRarity, eggWeight)
	local kg = Weights.petKg(petRarity)
	return kg * mult * Weights.PetSpread.Min, kg * mult * Weights.PetSpread.Max
end

-- Income multiplier from a pet's weight.
function Weights.incomeMult(petRarity: string, petWeight: number?): number
	return if petWeight then petWeight / Weights.petKg(petRarity) else 1
end

-- Size class name for a multiplier (pets use it for their label).
function Weights.classFor(mult: number): SizeClass
	local best = Weights.Classes[1]
	for _, class in Weights.Classes do
		if mult >= class.Min then
			best = class
		end
	end
	return best
end

-- How much bigger to draw a heavy pet or egg in the world.
function Weights.visualScale(mult: number): number
	return math.clamp(mult ^ 0.35, 0.85, 1.8)
end

-- "0.95 kg", "12.4 kg", "230 kg"
function Weights.format(kg: number): string
	if kg < 10 then
		return string.format("%.2f kg", kg)
	elseif kg < 100 then
		return string.format("%.1f kg", kg)
	end
	return string.format("%d kg", math.floor(kg + 0.5))
end

return Weights
