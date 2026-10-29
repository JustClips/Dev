--!strict
-- Alien pets (GAME_PLAN §5.4). The Landing Site set has 3 per rarity from Common to Mythic
-- plus 1 Cosmic event alien. Every later zone has its own 7-pet set (Crystal, Shadow,
-- Magma, Frost): remixes of the Landing models with new colours and extras, earning the
-- zone's cash multiplier. Eggs remember the zone they were found in and hatch from that
-- zone's set. Income is cash per second before multipliers.
local Types = require(script.Parent.Parent.Types)
local Eggs = require(script.Parent.Eggs)
local Weights = require(script.Parent.Weights)

type AlienDef = Types.AlienDef

-- Dev is remaking every pet from scratch in the voxel style (art/blender/voxpets.py,
-- 2026-10-29). Roster: the "Voxel Pet Roster" doc. Rarities with no pets yet fall
-- back to the Common pool (Aliens.pool). Saves holding removed pets are converted
-- to these on load (DataService).
local List: { AlienDef } = {
	{ Id = "Cat", Name = "Cat", Rarity = "Common", Income = 1, Color = Color3.fromRGB(242, 138, 46), Size = 1.8,
		Passive = { Name = "Lucky Paws", Stat = "Crit", Value = 0.02 } },
	{ Id = "Dog", Name = "Dog", Rarity = "Common", Income = 1.5, Color = Color3.fromRGB(217, 140, 69), Size = 2,
		Passive = { Name = "Good Boy", Stat = "PetIncome", Value = 0.03 } },
	{ Id = "Bunny", Name = "Bunny", Rarity = "Common", Income = 2, Color = Color3.fromRGB(244, 241, 236), Size = 2.2,
		Passive = { Name = "Quick Hop", Stat = "HatchSpeed", Value = 0.05 } },

	{ Id = "Squirrel", Name = "Squirrel", Rarity = "Uncommon", Income = 6, Color = Color3.fromRGB(185, 88, 42), Size = 2,
		Passive = { Name = "Hoarder", Stat = "Backpack", Value = 0.1 } },
	{ Id = "Raccoon", Name = "Raccoon", Rarity = "Uncommon", Income = 8, Color = Color3.fromRGB(143, 140, 137), Size = 2.1,
		Passive = { Name = "Trash Bandit", Stat = "DustValue", Value = 0.1 } },
	{ Id = "Duck", Name = "Duck", Rarity = "Uncommon", Income = 10, Color = Color3.fromRGB(255, 212, 59), Size = 2,
		Passive = { Name = "Splash Combo", Stat = "ComboTime", Value = 0.5 } },

	{ Id = "Fox", Name = "Fox", Rarity = "Rare", Income = 30, Color = Color3.fromRGB(232, 116, 42), Size = 2.2,
		Passive = { Name = "Sly Luck", Stat = "Luck", Value = 0.08 } },
	{ Id = "Turtle", Name = "Turtle", Rarity = "Rare", Income = 40, Color = Color3.fromRGB(124, 196, 106), Size = 1.6,
		Passive = { Name = "Slow and Steady", Stat = "Offline", Value = 0.25 } },
	{ Id = "Penguin", Name = "Penguin", Rarity = "Rare", Income = 50, Color = Color3.fromRGB(38, 40, 46), Size = 2.4,
		Passive = { Name = "Ice Slide", Stat = "Golden", Value = 0.15 } },

	{ Id = "Panda", Name = "Panda", Rarity = "Epic", Income = 180, Color = Color3.fromRGB(242, 242, 238), Size = 2.6,
		Passive = { Name = "Bamboo Feast", Stat = "PetIncome", Value = 0.1 } },
	{ Id = "Owl", Name = "Snowy Owl", Rarity = "Epic", Income = 230, Color = Color3.fromRGB(243, 243, 247), Size = 2.4,
		Passive = { Name = "Night Vision", Stat = "Luck", Value = 0.15 } },
	{ Id = "Tiger", Name = "Tiger", Rarity = "Epic", Income = 290, Color = Color3.fromRGB(240, 138, 36), Size = 2.6,
		Passive = { Name = "Pounce", Stat = "Power", Value = 0.15 } },

	{ Id = "Lion", Name = "Lion", Rarity = "Legendary", Income = 1_100, Color = Color3.fromRGB(232, 169, 58), Size = 3,
		Passive = { Name = "King's Share", Stat = "Cash", Value = 0.1 } },
	{ Id = "ArcticWolf", Name = "Arctic Wolf", Rarity = "Legendary", Income = 1_400, Color = Color3.fromRGB(220, 230, 240), Size = 3.1,
		Passive = { Name = "Pack Hunter", Stat = "Radius", Value = 0.2 } },
	{ Id = "Unicorn", Name = "Unicorn", Rarity = "Legendary", Income = 1_800, Color = Color3.fromRGB(250, 248, 255), Size = 3.3,
		Passive = { Name = "Rainbow Luck", Stat = "Luck", Value = 0.25 } },

	{ Id = "Dragon", Name = "Dragon", Rarity = "Mythic", Income = 8_000, Color = Color3.fromRGB(216, 52, 44), Size = 3.4,
		Passive = { Name = "Dragon's Hoard", Stat = "CritMult", Value = 1 } },
	{ Id = "Phoenix", Name = "Phoenix", Rarity = "Mythic", Income = 10_000, Color = Color3.fromRGB(255, 122, 26), Size = 3,
		Passive = { Name = "Rebirth Flame", Stat = "HatchSpeed", Value = 0.3 } },
	{ Id = "Kitsune", Name = "Kitsune", Rarity = "Mythic", Income = 12_500, Color = Color3.fromRGB(248, 246, 242), Size = 3.2,
		Passive = { Name = "Fox Fire", Stat = "Incubators", Value = 1 } },

	{ Id = "AutumnStag", Name = "Autumn Stag", Rarity = "Cosmic", Income = 60_000, Color = Color3.fromRGB(232, 116, 42), Size = 3.8,
		Passive = { Name = "Forest Spirit", Stat = "Cash", Value = 0.25 } },

	-- Park (zone Crater): its own animals, income x4.
	{ Id = "Hedgehog", Name = "Hedgehog", Rarity = "Common", Zone = "Crater", Income = 6, Color = Color3.fromRGB(140, 100, 64), Size = 1.6,
		Passive = { Name = "Prickly Sweep", Stat = "Power", Value = 0.04 } },
	{ Id = "Frog", Name = "Frog", Rarity = "Uncommon", Zone = "Crater", Income = 32, Color = Color3.fromRGB(108, 194, 74), Size = 1.6,
		Passive = { Name = "Leap", Stat = "ComboMax", Value = 0.25 } },
	{ Id = "Swan", Name = "Swan", Rarity = "Rare", Zone = "Crater", Income = 160, Color = Color3.fromRGB(247, 247, 244), Size = 2.4,
		Passive = { Name = "Graceful", Stat = "Golden", Value = 0.2 } },
	{ Id = "Beaver", Name = "Beaver", Rarity = "Epic", Zone = "Crater", Income = 920, Color = Color3.fromRGB(139, 90, 43), Size = 2,
		Passive = { Name = "Busy Builder", Stat = "Backpack", Value = 0.2 } },
	{ Id = "Peacock", Name = "Peacock", Rarity = "Legendary", Zone = "Crater", Income = 5_600, Color = Color3.fromRGB(31, 95, 208), Size = 3,
		Passive = { Name = "Show Off", Stat = "Cash", Value = 0.12 } },
	{ Id = "Griffin", Name = "Griffin", Rarity = "Mythic", Zone = "Crater", Income = 40_000, Color = Color3.fromRGB(217, 164, 90), Size = 4,
		Passive = { Name = "Sky Hunter", Stat = "Luck", Value = 0.35 } },

	-- Beach (zone DarkSide): income x15.
	{ Id = "Crab", Name = "Crab", Rarity = "Common", Zone = "DarkSide", Income = 22, Color = Color3.fromRGB(226, 72, 58), Size = 1.6,
		Passive = { Name = "Pinch", Stat = "Crit", Value = 0.03 } },
	{ Id = "Seagull", Name = "Seagull", Rarity = "Uncommon", Zone = "DarkSide", Income = 120, Color = Color3.fromRGB(247, 247, 244), Size = 1.9,
		Passive = { Name = "Scavenger", Stat = "DustValue", Value = 0.15 } },
	{ Id = "Seal", Name = "Seal", Rarity = "Rare", Zone = "DarkSide", Income = 600, Color = Color3.fromRGB(154, 163, 174), Size = 2,
		Passive = { Name = "Belly Slide", Stat = "ComboTime", Value = 0.8 } },
	{ Id = "Dolphin", Name = "Dolphin", Rarity = "Epic", Zone = "DarkSide", Income = 3_450, Color = Color3.fromRGB(106, 154, 216), Size = 2.6,
		Passive = { Name = "Echo Finder", Stat = "Luck", Value = 0.2 } },
	{ Id = "Shark", Name = "Shark", Rarity = "Legendary", Zone = "DarkSide", Income = 21_000, Color = Color3.fromRGB(110, 126, 142), Size = 3.4,
		Passive = { Name = "Feeding Frenzy", Stat = "Power", Value = 0.25 } },
	{ Id = "SeaSerpent", Name = "Sea Serpent", Rarity = "Mythic", Zone = "DarkSide", Income = 150_000, Color = Color3.fromRGB(31, 165, 154), Size = 4.5,
		Passive = { Name = "Tidal Wave", Stat = "Radius", Value = 0.3 } },

	-- City (zone Mars): income x60.
	{ Id = "Pigeon", Name = "Pigeon", Rarity = "Common", Zone = "Mars", Income = 90, Color = Color3.fromRGB(140, 148, 164), Size = 1.8,
		Passive = { Name = "Crumb Finder", Stat = "DustValue", Value = 0.08 } },
	{ Id = "Rat", Name = "Rat", Rarity = "Uncommon", Zone = "Mars", Income = 480, Color = Color3.fromRGB(128, 120, 116), Size = 1.6,
		Passive = { Name = "Scurry", Stat = "ComboTime", Value = 0.5 } },
	{ Id = "Corgi", Name = "Corgi", Rarity = "Rare", Zone = "Mars", Income = 2_400, Color = Color3.fromRGB(226, 146, 66), Size = 2,
		Passive = { Name = "Royal Waddle", Stat = "PetIncome", Value = 0.08 } },
	{ Id = "Bulldog", Name = "Bulldog", Rarity = "Epic", Zone = "Mars", Income = 13_800, Color = Color3.fromRGB(210, 180, 140), Size = 2.4,
		Passive = { Name = "Stubborn", Stat = "Offline", Value = 0.25 } },
	{ Id = "RoboPup", Name = "Robo Pup", Rarity = "Legendary", Zone = "Mars", Income = 84_000, Color = Color3.fromRGB(176, 190, 204), Size = 2.8,
		Passive = { Name = "Overclock", Stat = "HatchSpeed", Value = 0.25 } },
	{ Id = "Gargoyle", Name = "Gargoyle", Rarity = "Mythic", Zone = "Mars", Income = 600_000, Color = Color3.fromRGB(110, 112, 124), Size = 4.4,
		Passive = { Name = "Stone Guardian", Stat = "Backpack", Value = 0.35 } },

	-- Snowy Peaks (zone Europa): income x250.
	{ Id = "SnowHare", Name = "Snow Hare", Rarity = "Common", Zone = "Europa", Income = 375, Color = Color3.fromRGB(246, 248, 252), Size = 2.2,
		Passive = { Name = "Snowshoes", Stat = "ComboTime", Value = 0.4 } },
	{ Id = "MountainGoat", Name = "Mountain Goat", Rarity = "Uncommon", Zone = "Europa", Income = 2_000, Color = Color3.fromRGB(242, 240, 234), Size = 2.4,
		Passive = { Name = "Sure Footed", Stat = "Power", Value = 0.1 } },
	{ Id = "SnowLeopard", Name = "Snow Leopard", Rarity = "Rare", Zone = "Europa", Income = 10_000, Color = Color3.fromRGB(230, 232, 236), Size = 2.4,
		Passive = { Name = "Silent Stalk", Stat = "Crit", Value = 0.04 } },
	{ Id = "Mammoth", Name = "Mammoth", Rarity = "Epic", Zone = "Europa", Income = 57_500, Color = Color3.fromRGB(138, 90, 54), Size = 4,
		Passive = { Name = "Ice Age Hoard", Stat = "Backpack", Value = 0.25 } },
	{ Id = "FrostEagle", Name = "Frost Eagle", Rarity = "Legendary", Zone = "Europa", Income = 350_000, Color = Color3.fromRGB(122, 168, 216), Size = 3.6,
		Passive = { Name = "Eagle Eye", Stat = "Luck", Value = 0.3 } },
	{ Id = "Yeti", Name = "Yeti", Rarity = "Mythic", Zone = "Europa", Income = 2_500_000, Color = Color3.fromRGB(244, 246, 250), Size = 5,
		Passive = { Name = "Avalanche", Stat = "Radius", Value = 0.35 } },

	-- Zone Cosmic pets (Cosmic eggs hatched in that zone).
	{ Id = "ButterflyQueen", Name = "Butterfly Queen", Rarity = "Cosmic", Zone = "Crater", Income = 240_000, Color = Color3.fromRGB(255, 122, 200), Size = 4.2,
		Passive = { Name = "Pollinate", Stat = "HatchSpeed", Value = 0.4 } },
	{ Id = "Kraken", Name = "Kraken", Rarity = "Cosmic", Zone = "DarkSide", Income = 900_000, Color = Color3.fromRGB(184, 48, 74), Size = 5,
		Passive = { Name = "Many Arms", Stat = "Backpack", Value = 0.4 } },
	{ Id = "MechaRex", Name = "Mecha Rex", Rarity = "Cosmic", Zone = "Mars", Income = 3_600_000, Color = Color3.fromRGB(255, 58, 216), Size = 5,
		Passive = { Name = "Overdrive", Stat = "Power", Value = 0.35 } },
	{ Id = "AuroraWhale", Name = "Aurora Whale", Rarity = "Cosmic", Zone = "Europa", Income = 15_000_000, Color = Color3.fromRGB(79, 216, 255), Size = 5.5,
		Passive = { Name = "Northern Lights", Stat = "Cash", Value = 0.3 } },
}

-- Zone sets: each entry is a Landing alien the variant is based on (empty until the new
-- voxel pets get zone variants). The variant keeps the
-- base's rarity and multiplies its income. Models: art/blender/aliens.py VARIANTS.
local ZONE_SETS = {
	{
		Zone = "Crater",
		Prefix = "Crystal",
		IncomeMult = 4,
		Color = Color3.fromRGB(120, 220, 255),
		Bases = {} :: { string },
	},
	{
		Zone = "DarkSide",
		Prefix = "Shadow",
		IncomeMult = 15,
		Color = Color3.fromRGB(150, 90, 230),
		Bases = {} :: { string },
	},
	{
		Zone = "Mars",
		Prefix = "Magma",
		IncomeMult = 60,
		Color = Color3.fromRGB(255, 110, 50),
		Bases = {} :: { string },
	},
	{
		Zone = "Europa",
		Prefix = "Frost",
		IncomeMult = 250,
		Color = Color3.fromRGB(190, 235, 255),
		Bases = {} :: { string },
	},
}

local landing: { [string]: AlienDef } = {}
for _, alien in List do
	alien.Zone = alien.Zone or "Landing" -- zone pets name their zone
	if alien.Zone == "Landing" then
		landing[alien.Id] = alien
	end
end
for _, set in ZONE_SETS do
	for _, baseId in set.Bases do
		local base = landing[baseId]
		table.insert(List, {
			Id = set.Prefix .. baseId,
			Name = `{set.Prefix} {base.Name}`,
			Rarity = base.Rarity,
			Income = base.Income * set.IncomeMult,
			Color = base.Color:Lerp(set.Color, 0.6),
			Size = base.Size,
			Zone = set.Zone,
			Base = baseId,
		})
	end
end

local Aliens = {
	List = List,
	ZoneSets = ZONE_SETS,
	ById = {} :: { [string]: AlienDef },
	ByRarity = {} :: { [string]: { AlienDef } },
	-- Zone -> Rarity -> aliens
	Pools = {} :: { [string]: { [string]: { AlienDef } } },
	-- Huge pets: a rare roll at hatch time. Bigger in the park and much more cash.
	HugeChance = 1 / 2000,
	HugeIncomeMult = 10,
	HugeScale = 2,
}

for _, alien in List do
	Aliens.ById[alien.Id] = alien
	local bucket = Aliens.ByRarity[alien.Rarity]
	if not bucket then
		bucket = {}
		Aliens.ByRarity[alien.Rarity] = bucket
	end
	table.insert(bucket, alien)
	local zone = Aliens.Pools[alien.Zone or "Landing"]
	if not zone then
		zone = {}
		Aliens.Pools[alien.Zone or "Landing"] = zone
	end
	zone[alien.Rarity] = zone[alien.Rarity] or {}
	table.insert(zone[alien.Rarity], alien)
end

-- What an egg from `zone` with `rarity` can hatch into (falls back to the Landing set).
function Aliens.pool(zone: string?, rarity: string): { AlienDef }
	local zonePool = Aliens.Pools[zone or "Landing"]
	local list = zonePool and zonePool[rarity]
	if list and #list > 0 then
		return list
	end
	return Aliens.Pools.Landing[rarity] or Aliens.Pools.Landing.Common
end

-- Cash per second of one pet before the player's multipliers. Heavier pets earn more
-- (Config/Weights).
function Aliens.income(pet: { Id: string, Mutation: string?, Huge: boolean?, Weight: number? }): number
	local def = Aliens.ById[pet.Id]
	if not def then
		return 0
	end
	local income = def.Income * Weights.incomeMult(def.Rarity, pet.Weight)
	if pet.Mutation then
		local mutation = Eggs.MutationByName[pet.Mutation]
		income *= if mutation then mutation.IncomeMult else 1
	end
	if pet.Huge then
		income *= Aliens.HugeIncomeMult
	end
	return income
end

return Aliens
