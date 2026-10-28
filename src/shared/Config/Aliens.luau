--!strict
-- Alien pets (GAME_PLAN §5.4): 3 per rarity from Common to Mythic, plus 1 Cosmic event alien.
-- Income is cash per second before multipliers. Models are placeholders built in code.
local Types = require(script.Parent.Parent.Types)

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

local Aliens = {
	List = List,
	ById = {} :: { [string]: AlienDef },
	ByRarity = {} :: { [string]: { AlienDef } },
}

for _, alien in List do
	Aliens.ById[alien.Id] = alien
	local bucket = Aliens.ByRarity[alien.Rarity]
	if not bucket then
		bucket = {}
		Aliens.ByRarity[alien.Rarity] = bucket
	end
	table.insert(bucket, alien)
end

return Aliens
