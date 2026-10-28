--!strict
-- Gamepasses and developer products (GAME_PLAN §6).
-- TODO(Dev): create these in the Creator Dashboard (universe 10773346969) and paste the IDs.
-- An Id of 0 means "not created yet": its button is hidden and the server logs a warning once.
local Types = require(script.Parent.Parent.Types)

type ProductDef = Types.ProductDef
type GamepassDef = Types.GamepassDef

local Gamepasses: { GamepassDef } = {
	{ Key = "Cash2x", Id = 0, Price = 99, Name = "2x Cash", Description = "All cash x2, forever." }, -- TODO(Dev)
	{ Key = "AutoSweep", Id = 0, Price = 149, Name = "Auto Sweep", Description = "Sweeps around you automatically while you move." }, -- TODO(Dev)
	{ Key = "ExtraSlots", Id = 0, Price = 199, Name = "+3 Alien Slots", Description = "Three more aliens on your base." }, -- TODO(Dev)
	{ Key = "Carry3", Id = 0, Price = 129, Name = "Carry 3 Eggs", Description = "Carry up to 3 eggs per trip." }, -- TODO(Dev)
	{ Key = "VIP", Id = 0, Price = 249, Name = "VIP", Description = "+20% cash, VIP tag, 4 h offline income." }, -- TODO(Dev)
	{ Key = "FasterHatch", Id = 0, Price = 229, Name = "Faster Hatch", Description = "All hatch timers halved." }, -- TODO(Dev)
}

local Products: { ProductDef } = {
	-- TODO(Dev): every Id below is a placeholder.
	{ Key = "StarterPack", Id = 0, Price = 9, Name = "Starter Pack", Kind = "StarterPack", Category = "Special", Giftable = false },

	{ Key = "ServerLuck2", Id = 0, Price = 19, Name = "2x Server Luck (15 min)", Kind = "ServerLuck", Category = "Boosts", Giftable = false, Mult = 2, Minutes = 15 },
	{ Key = "ServerLuck4", Id = 0, Price = 39, Name = "4x Server Luck (15 min)", Kind = "ServerLuck", Category = "Boosts", Giftable = false, Mult = 4, Minutes = 15 },
	{ Key = "ServerLuck8", Id = 0, Price = 79, Name = "8x Server Luck (15 min)", Kind = "ServerLuck", Category = "Boosts", Giftable = false, Mult = 8, Minutes = 15 },
	{ Key = "ServerLuck16", Id = 0, Price = 159, Name = "16x Server Luck (15 min)", Kind = "ServerLuck", Category = "Boosts", Giftable = false, Mult = 16, Minutes = 15 },
	{ Key = "MeteorShower", Id = 0, Price = 199, Name = "Meteor Shower Now", Kind = "MeteorShower", Category = "Boosts", Giftable = false },

	{ Key = "SkipHatchCommon", Id = 0, Price = 5, Name = "Skip Hatch (Common)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Common" },
	{ Key = "SkipHatchUncommon", Id = 0, Price = 15, Name = "Skip Hatch (Uncommon)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Uncommon" },
	{ Key = "SkipHatchRare", Id = 0, Price = 35, Name = "Skip Hatch (Rare)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Rare" },
	{ Key = "SkipHatchEpic", Id = 0, Price = 45, Name = "Skip Hatch (Epic)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Epic" },
	{ Key = "SkipHatchLegendary", Id = 0, Price = 65, Name = "Skip Hatch (Legendary)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Legendary" },
	{ Key = "SkipHatchMythic", Id = 0, Price = 85, Name = "Skip Hatch (Mythic)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Mythic" },
	{ Key = "SkipHatchCosmic", Id = 0, Price = 105, Name = "Skip Hatch (Cosmic)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Cosmic" },
	{ Key = "CosmicEgg1", Id = 0, Price = 99, Name = "Cosmic Egg", Kind = "EggPack", Category = "Eggs", Giftable = true, Rarity = "Cosmic", Count = 1 },
	{ Key = "CosmicEgg3", Id = 0, Price = 249, Name = "3 Cosmic Eggs", Kind = "EggPack", Category = "Eggs", Giftable = true, Rarity = "Cosmic", Count = 3 },

	-- "Next tool now": priced per target tier.
	{ Key = "ToolSkip2", Id = 0, Price = 3, Name = "Unlock Broom", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 2 },
	{ Key = "ToolSkip3", Id = 0, Price = 9, Name = "Unlock Mop", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 3 },
	{ Key = "ToolSkip4", Id = 0, Price = 25, Name = "Unlock Leaf Blower", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 4 },
	{ Key = "ToolSkip5", Id = 0, Price = 59, Name = "Unlock Shop Vac", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 5 },
	{ Key = "ToolSkip6", Id = 0, Price = 129, Name = "Unlock Turbo Vacuum", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 6 },
	{ Key = "ToolSkip7", Id = 0, Price = 249, Name = "Unlock Sweeper Cart", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 7 },
	{ Key = "ToolSkip8", Id = 0, Price = 499, Name = "Unlock Dust Truck", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 8 },
	{ Key = "ToolSkip9", Id = 0, Price = 999, Name = "Unlock Moon Crawler", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 9 },

	-- Vehicle "This Run" rentals (cleared on rebirth or leave).
	{ Key = "RentSweeperCart", Id = 0, Price = 59, Name = "Sweeper Cart (this run)", Kind = "VehicleRental", Category = "Tools", Giftable = true, Tier = 7 },
	{ Key = "RentDustTruck", Id = 0, Price = 149, Name = "Dust Truck (this run)", Kind = "VehicleRental", Category = "Tools", Giftable = true, Tier = 8 },
	{ Key = "RentMoonCrawler", Id = 0, Price = 299, Name = "Moon Crawler (this run)", Kind = "VehicleRental", Category = "Tools", Giftable = true, Tier = 9 },

	-- Cash packs scale with the player: max(Seconds of income, FloorFactor x next tool price).
	{ Key = "Cash1", Id = 0, Price = 24, Name = "Pile of Cash", Kind = "CashPack", Category = "Cash", Giftable = true, Seconds = 600, FloorFactor = 0.5 },
	{ Key = "Cash2", Id = 0, Price = 59, Name = "Bag of Cash", Kind = "CashPack", Category = "Cash", Giftable = true, Seconds = 1800, FloorFactor = 1.5 },
	{ Key = "Cash3", Id = 0, Price = 149, Name = "Crate of Cash", Kind = "CashPack", Category = "Cash", Giftable = true, Seconds = 5400, FloorFactor = 4 },
	{ Key = "Cash4", Id = 0, Price = 399, Name = "Vault of Cash", Kind = "CashPack", Category = "Cash", Giftable = true, Seconds = 14400, FloorFactor = 10 },
	{ Key = "Cash5", Id = 0, Price = 999, Name = "Moon of Cash", Kind = "CashPack", Category = "Cash", Giftable = true, Seconds = 43200, FloorFactor = 25 },

	{ Key = "SkipRebirth", Id = 0, Price = 79, Name = "Skip Rebirth", Kind = "SkipRebirth", Category = "Special", Giftable = true },
	{ Key = "DoubleOffline", Id = 0, Price = 49, Name = "Double Offline Reward", Kind = "DoubleOffline", Category = "Special", Giftable = false },
}

local Config = {
	Gamepasses = Gamepasses,
	Products = Products,
	PassByKey = {} :: { [string]: GamepassDef },
	PassById = {} :: { [number]: GamepassDef },
	ProductByKey = {} :: { [string]: ProductDef },
	ProductById = {} :: { [number]: ProductDef },
	-- How long a "buy as gift" choice stays valid while the purchase prompt is open.
	GiftWindowSeconds = 300,
}

for _, pass in Gamepasses do
	Config.PassByKey[pass.Key] = pass
	if pass.Id ~= 0 then
		Config.PassById[pass.Id] = pass
	end
end
for _, product in Products do
	Config.ProductByKey[product.Key] = product
	if product.Id ~= 0 then
		Config.ProductById[product.Id] = product
	end
end

function Config.isLive(def: { Id: number }): boolean
	return def.Id ~= 0
end

return Config
