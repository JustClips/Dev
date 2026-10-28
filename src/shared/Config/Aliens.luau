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

local List: { AlienDef } = {
	{ Id = "Blip", Name = "Blip", Rarity = "Common", Income = 1, Color = Color3.fromRGB(170, 230, 170), Size = 1.6 },
	{ Id = "MoonMite", Name = "Moon Mite", Rarity = "Common", Income = 1.5, Color = Color3.fromRGB(200, 200, 215), Size = 1.5 },
	{ Id = "Dusty", Name = "Dusty", Rarity = "Common", Income = 2, Color = Color3.fromRGB(220, 200, 160), Size = 1.7 },

	{ Id = "Glorp", Name = "Glorp", Rarity = "Uncommon", Income = 6, Color = Color3.fromRGB(110, 230, 90), Size = 1.9 },
	{ Id = "Zib", Name = "Zib", Rarity = "Uncommon", Income = 8, Color = Color3.fromRGB(90, 220, 200), Size = 1.8 },
	{ Id = "CraterCrab", Name = "Crater Crab", Rarity = "Uncommon", Income = 10, Color = Color3.fromRGB(240, 120, 90), Size = 2 },

	{ Id = "Nebby", Name = "Nebby", Rarity = "Rare", Income = 30, Color = Color3.fromRGB(120, 140, 255), Size = 2.1 },
	{ Id = "Orbo", Name = "Orbo", Rarity = "Rare", Income = 40, Color = Color3.fromRGB(80, 190, 255), Size = 2.2 },
	{ Id = "LunarSlug", Name = "Lunar Slug", Rarity = "Rare", Income = 50, Color = Color3.fromRGB(180, 220, 255), Size = 2.3 },

	{ Id = "Zorblax", Name = "Zorblax", Rarity = "Epic", Income = 180, Color = Color3.fromRGB(170, 90, 255), Size = 2.5 },
	{ Id = "CometCat", Name = "Comet Cat", Rarity = "Epic", Income = 230, Color = Color3.fromRGB(255, 150, 220), Size = 2.4 },
	{ Id = "QuasarPup", Name = "Quasar Pup", Rarity = "Epic", Income = 290, Color = Color3.fromRGB(140, 120, 255), Size = 2.6 },

	{ Id = "StarWhale", Name = "Star Whale", Rarity = "Legendary", Income = 1_100, Color = Color3.fromRGB(60, 120, 255), Size = 3 },
	{ Id = "GalaxyGus", Name = "Galaxy Gus", Rarity = "Legendary", Income = 1_400, Color = Color3.fromRGB(255, 200, 60), Size = 2.8 },
	{ Id = "AstroAxolotl", Name = "Astro Axolotl", Rarity = "Legendary", Income = 1_800, Color = Color3.fromRGB(255, 160, 200), Size = 2.9 },

	{ Id = "VoidKing", Name = "Void King", Rarity = "Mythic", Income = 8_000, Color = Color3.fromRGB(40, 20, 60), Size = 3.3 },
	{ Id = "EclipseDragon", Name = "Eclipse Dragon", Rarity = "Mythic", Income = 10_000, Color = Color3.fromRGB(255, 80, 40), Size = 3.5 },
	{ Id = "NovaQueen", Name = "Nova Queen", Rarity = "Mythic", Income = 12_500, Color = Color3.fromRGB(255, 240, 150), Size = 3.4 },

	{ Id = "Cosmo", Name = "Cosmo the Infinite", Rarity = "Cosmic", Income = 60_000, Color = Color3.fromRGB(255, 120, 230), Size = 3.8 },
}

-- Zone sets: each entry is a Landing alien the variant is based on. The variant keeps the
-- base's rarity and multiplies its income. Models: art/blender/aliens.py VARIANTS.
local ZONE_SETS = {
	{
		Zone = "Crater",
		Prefix = "Crystal",
		IncomeMult = 4,
		Color = Color3.fromRGB(120, 220, 255),
		Bases = { "Blip", "MoonMite", "Glorp", "CraterCrab", "Orbo", "LunarSlug", "CometCat" },
	},
	{
		Zone = "DarkSide",
		Prefix = "Shadow",
		IncomeMult = 15,
		Color = Color3.fromRGB(150, 90, 230),
		Bases = { "Dusty", "Zib", "Nebby", "Zorblax", "QuasarPup", "StarWhale", "GalaxyGus" },
	},
	{
		Zone = "Mars",
		Prefix = "Magma",
		IncomeMult = 60,
		Color = Color3.fromRGB(255, 110, 50),
		Bases = { "Blip", "CraterCrab", "LunarSlug", "CometCat", "AstroAxolotl", "EclipseDragon", "VoidKing" },
	},
	{
		Zone = "Europa",
		Prefix = "Frost",
		IncomeMult = 250,
		Color = Color3.fromRGB(190, 235, 255),
		Bases = { "MoonMite", "Glorp", "Orbo", "QuasarPup", "StarWhale", "NovaQueen", "EclipseDragon" },
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
