--!strict
-- The limited egg in the shop (Dev, 2026-10-31, after a "Halloween Egg" reference): its own
-- set of exclusive pets with the odds shown on the shop banner, sold in packs of 1 / 3 / 10
-- (Products Kind "LimitedEgg") until EndsAt. Bought eggs go to your bag like any egg; the
-- egg is tagged with Zone = Id, so HatchService rolls from Odds instead of a zone pool.
-- For the next limited egg: new Id, Name, EndsAt, pets (Config/Aliens, Exclusive = Id) and
-- products.
local LimitedEgg = {
	Id = "Halloween",
	Name = "Halloween Egg",
	EndsAt = 1794009600, -- 2026-11-07 00:00 UTC
	EggRarity = "Legendary", -- egg model and hatch time
	EggMutation = "Bloodlit", -- the egg's spooky skin (the pet doesn't inherit it)
	-- Chances in percent, shown in the shop. They must add up to 100.
	Odds = {
		{ Pet = "PumpkinCat", Chance = 40 },
		{ Pet = "WitchCat", Chance = 25 },
		{ Pet = "ZombieDog", Chance = 18 },
		{ Pet = "VampireBat", Chance = 11 },
		{ Pet = "SkeletonWolf", Chance = 5.5 },
		{ Pet = "ShadowDragon", Chance = 0.5 },
	},
}

local total = 0
for _, entry in LimitedEgg.Odds do
	total += entry.Chance
end
assert(math.abs(total - 100) < 1e-6, `LimitedEgg odds add up to {total}, not 100`)

function LimitedEgg.onSale(now: number): boolean
	return now < LimitedEgg.EndsAt
end

-- Is this egg (or hatching entry) the limited egg?
function LimitedEgg.isEgg(egg: { Zone: string? }): boolean
	return egg.Zone == LimitedEgg.Id
end

-- One pet id, by the odds above.
function LimitedEgg.roll(rng: Random): string
	local pick = rng:NextNumber() * 100
	for _, entry in LimitedEgg.Odds do
		pick -= entry.Chance
		if pick <= 0 then
			return entry.Pet
		end
	end
	return LimitedEgg.Odds[1].Pet
end

return LimitedEgg
