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
	alien.Zone = "Landing"
	landing[alien.Id] = alien
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
