--!strict
-- Gamepasses and developer products (GAME_PLAN §6).
-- Created through Open Cloud by tools/create_products.py (universe 10773346969).
-- An Id of 0 means "not created yet": its button is hidden and the server logs a warning once.
local Types = require(script.Parent.Parent.Types)
local Economy = require(script.Parent.Economy)

type ProductDef = Types.ProductDef
type GamepassDef = Types.GamepassDef

local Gamepasses: { GamepassDef } = {
	{ Key = "Cash2x", Id = 2056961597, Price = 99, Name = "2x Cash", Description = "All cash x2, forever." },
	{ Key = "AutoSweep", Id = 2058257553, Price = 149, Name = "Auto Sweep", Description = "Sweeps around you automatically while you move." },
	{ Key = "ExtraSlots", Id = 2060650790, Price = 199, Name = "+3 Pet Slots", Description = "Three more pets on your base." },
	{ Key = "Carry3", Id = 2057249582, Price = 129, Name = "Carry 3 Eggs", Description = "Carry up to 3 eggs per trip." },
	{ Key = "VIP", Id = 2060219551, Price = 249, Name = "VIP", Description = "+20% cash, +10% egg luck, VIP chat tag, a free gift every day and 4 h offline income." },
	{ Key = "FasterHatch", Id = 2057507586, Price = 229, Name = "Faster Hatch", Description = "All hatch timers halved." },
	{ Key = "FastWalk", Id = 2061565724, Price = 49, Name = "Fast Walk", Description = "Walk 30% faster, forever." },
	{ Key = "BigBag", Id = 2058855087, Price = 79, Name = "Big Bag", Description = "Your bag holds 2x as many leaves, forever." },
	{ Key = "Lucky", Id = 2061889578, Price = 149, Name = "Lucky", Description = "+50% egg luck forever: rarer pets, more mutations and Huge pets." },
	{ Key = "SellAnywhere", Id = 2058462006, Price = 199, Name = "Sell Anywhere", Description = "Sell your whole bag from anywhere with one tap, plus Auto Sell when it fills up." },
}

local Products: { ProductDef } = {
	{ Key = "StarterPack", Id = 3723358524, Price = 9, Name = "Starter Pack", Kind = "StarterPack", Category = "Special", Giftable = false },

	{ Key = "ServerLuck2", Id = 3723358734, Price = 19, Name = "2x Server Luck (15 min)", Kind = "ServerLuck", Category = "Boosts", Giftable = false, Mult = 2, Minutes = 15 },
	{ Key = "ServerLuck4", Id = 3723358741, Price = 39, Name = "4x Server Luck (15 min)", Kind = "ServerLuck", Category = "Boosts", Giftable = false, Mult = 4, Minutes = 15 },
	{ Key = "ServerLuck8", Id = 3723358752, Price = 79, Name = "8x Server Luck (15 min)", Kind = "ServerLuck", Category = "Boosts", Giftable = false, Mult = 8, Minutes = 15 },
	{ Key = "ServerLuck16", Id = 3723358764, Price = 159, Name = "16x Server Luck (15 min)", Kind = "ServerLuck", Category = "Boosts", Giftable = false, Mult = 16, Minutes = 15 },
	{ Key = "MeteorShower", Id = 3723358773, Price = 199, Name = "Egg Rain Now", Kind = "MeteorShower", Category = "Boosts", Giftable = false },
	{ Key = "WeatherTotem1", Id = 3725034762, Price = 49, Name = "Weather Totem", Kind = "ItemPack", Category = "Boosts", Giftable = true, Item = "WeatherTotem", Count = 1 },

	-- Small buys: potions and charms straight into your bag (use them from the Items tab).
	{ Key = "LeafBomb3", Id = 3725034793, Price = 9, Name = "3 Leaf Bombs", Kind = "ItemPack", Category = "Potions", Giftable = true, Item = "LeafBomb", Count = 3 },
	{ Key = "LuckyClover1", Id = 3725034819, Price = 15, Name = "Lucky Clover", Kind = "ItemPack", Category = "Potions", Giftable = true, Item = "LuckyClover", Count = 1 },
	{ Key = "LuckPotion3", Id = 3725034825, Price = 19, Name = "3 Luck Potions", Kind = "ItemPack", Category = "Potions", Giftable = true, Item = "LuckPotion", Count = 3 },
	{ Key = "CashPotion3", Id = 3725034833, Price = 25, Name = "3 Cash Potions", Kind = "ItemPack", Category = "Potions", Giftable = true, Item = "CashPotion", Count = 3 },
	{ Key = "MutationSpray1", Id = 3725034852, Price = 25, Name = "Mutation Spray", Kind = "ItemPack", Category = "Potions", Giftable = true, Item = "MutationSpray", Count = 1 },
	{ Key = "SuperLuckPotion1", Id = 3725034861, Price = 29, Name = "Super Luck Potion", Kind = "ItemPack", Category = "Potions", Giftable = true, Item = "SuperLuckPotion", Count = 1 },
	{ Key = "MegaCashPotion1", Id = 3725034877, Price = 35, Name = "Mega Cash Potion", Kind = "ItemPack", Category = "Potions", Giftable = true, Item = "MegaCashPotion", Count = 1 },
	{ Key = "HugeCharm1", Id = 3725034899, Price = 49, Name = "Huge Charm", Kind = "ItemPack", Category = "Potions", Giftable = true, Item = "HugeCharm", Count = 1 },

	{ Key = "SkipHatchCommon", Id = 3723358783, Price = 3, Name = "Skip Hatch (Common)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Common" },
	{ Key = "SkipHatchUncommon", Id = 3723358792, Price = 5, Name = "Skip Hatch (Uncommon)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Uncommon" },
	{ Key = "SkipHatchRare", Id = 3723358806, Price = 9, Name = "Skip Hatch (Rare)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Rare" },
	{ Key = "SkipHatchEpic", Id = 3723358816, Price = 19, Name = "Skip Hatch (Epic)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Epic" },
	{ Key = "SkipHatchLegendary", Id = 3723358824, Price = 35, Name = "Skip Hatch (Legendary)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Legendary" },
	{ Key = "SkipHatchMythic", Id = 3723358840, Price = 59, Name = "Skip Hatch (Mythic)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Mythic" },
	{ Key = "SkipHatchCosmic", Id = 3723358849, Price = 89, Name = "Skip Hatch (Cosmic)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Cosmic" },
	-- Egg ladder: each rarity in packs of 1, 3 and 10 (the shop shows one card per rarity and
	-- asks how many). Bought eggs always hatch their own rarity, from your best zone.
	{ Key = "EpicEgg1", Id = 3725049748, Price = 25, Name = "Epic Egg", Kind = "EggPack", Category = "Eggs", Giftable = true, Rarity = "Epic", Count = 1 },
	{ Key = "EpicEgg3", Id = 3725049761, Price = 65, Name = "3 Epic Eggs", Kind = "EggPack", Category = "Eggs", Giftable = true, Rarity = "Epic", Count = 3 },
	{ Key = "EpicEgg10", Id = 3725049768, Price = 199, Name = "10 Epic Eggs", Kind = "EggPack", Category = "Eggs", Giftable = true, Rarity = "Epic", Count = 10 },
	{ Key = "LegendaryEgg1", Id = 3725049777, Price = 45, Name = "Legendary Egg", Kind = "EggPack", Category = "Eggs", Giftable = true, Rarity = "Legendary", Count = 1 },
	{ Key = "LegendaryEgg3", Id = 3725049800, Price = 119, Name = "3 Legendary Eggs", Kind = "EggPack", Category = "Eggs", Giftable = true, Rarity = "Legendary", Count = 3 },
	{ Key = "LegendaryEgg10", Id = 3725049816, Price = 349, Name = "10 Legendary Eggs", Kind = "EggPack", Category = "Eggs", Giftable = true, Rarity = "Legendary", Count = 10 },
	{ Key = "MythicEgg1", Id = 3725049824, Price = 69, Name = "Mythic Egg", Kind = "EggPack", Category = "Eggs", Giftable = true, Rarity = "Mythic", Count = 1 },
	{ Key = "MythicEgg3", Id = 3725049840, Price = 179, Name = "3 Mythic Eggs", Kind = "EggPack", Category = "Eggs", Giftable = true, Rarity = "Mythic", Count = 3 },
	{ Key = "MythicEgg10", Id = 3725049854, Price = 549, Name = "10 Mythic Eggs", Kind = "EggPack", Category = "Eggs", Giftable = true, Rarity = "Mythic", Count = 10 },
	{ Key = "CosmicEgg1", Id = 3723358859, Price = 99, Name = "Cosmic Egg", Kind = "EggPack", Category = "Eggs", Giftable = true, Rarity = "Cosmic", Count = 1 },
	{ Key = "CosmicEgg3", Id = 3723358868, Price = 249, Name = "3 Cosmic Eggs", Kind = "EggPack", Category = "Eggs", Giftable = true, Rarity = "Cosmic", Count = 3 },
	{ Key = "CosmicEgg10", Id = 3725049875, Price = 799, Name = "10 Cosmic Eggs", Kind = "EggPack", Category = "Eggs", Giftable = true, Rarity = "Cosmic", Count = 10 },

	-- Limited bundle (Economy.LimitedPack): once per player, gone after its end date.
	{ Key = "HalloweenPack", Id = 3725049892, Price = 149, Name = "Spooky Halloween Pack", Kind = "LimitedPack", Category = "Special", Giftable = false },

	-- "Next tool now": priced per target tier.
	{ Key = "ToolSkip2", Id = 3723358874, Price = 3, Name = "Unlock Broom", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 2 },
	{ Key = "ToolSkip3", Id = 3724878294, Price = 5, Name = "Unlock Rake", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 3 },
	{ Key = "ToolSkip4", Id = 3723358883, Price = 9, Name = "Unlock Mop", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 4 },
	{ Key = "ToolSkip5", Id = 3724878303, Price = 15, Name = "Unlock Push Broom", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 5 },
	{ Key = "ToolSkip6", Id = 3723358889, Price = 25, Name = "Unlock Leaf Blower", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 6 },
	{ Key = "ToolSkip7", Id = 3724878312, Price = 39, Name = "Unlock Leaf Vacuum", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 7 },
	{ Key = "ToolSkip8", Id = 3723358904, Price = 59, Name = "Unlock Shop Vac", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 8 },
	{ Key = "ToolSkip9", Id = 3724878325, Price = 89, Name = "Unlock Pressure Washer", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 9 },
	{ Key = "ToolSkip10", Id = 3723358915, Price = 129, Name = "Unlock Turbo Vacuum", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 10 },
	{ Key = "ToolSkip11", Id = 3724878338, Price = 169, Name = "Unlock Golden Broom", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 11 },
	{ Key = "ToolSkip12", Id = 3724878349, Price = 199, Name = "Unlock Storm Blower", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 12 },
	{ Key = "ToolSkip13", Id = 3724878366, Price = 249, Name = "Unlock Tornado Vac", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 13 },
	{ Key = "ToolSkip14", Id = 3724878378, Price = 299, Name = "Unlock Diamond Mop", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 14 },
	{ Key = "ToolSkip15", Id = 3724878385, Price = 349, Name = "Unlock Rainbow Duster", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 15 },
	{ Key = "ToolSkip16", Id = 3724878401, Price = 399, Name = "Unlock Galaxy Vacuum", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 16 },

	-- Cars (sold in the Garage). Unlock = owned until rebirth; Rent = until you leave or rebirth.
	-- Both need the car's rebirth level, so Robux can't jump ahead of the progression.
	{ Key = "UnlockSweeperCart", Id = 3723358932, Price = 249, Name = "Unlock Sweeper Cart", Kind = "VehicleUnlock", Category = "Vehicles", Giftable = true, Vehicle = "SweeperCart" },
	{ Key = "UnlockMoonBuggy", Id = 3723367542, Price = 349, Name = "Unlock Golf Cart", Kind = "VehicleUnlock", Category = "Vehicles", Giftable = true, Vehicle = "MoonBuggy" },
	{ Key = "UnlockDustTruck", Id = 3723358946, Price = 499, Name = "Unlock Garbage Truck", Kind = "VehicleUnlock", Category = "Vehicles", Giftable = true, Vehicle = "DustTruck" },
	{ Key = "UnlockHoverSweeper", Id = 3723367553, Price = 699, Name = "Unlock Street Sweeper", Kind = "VehicleUnlock", Category = "Vehicles", Giftable = true, Vehicle = "HoverSweeper" },
	{ Key = "UnlockMoonCrawler", Id = 3723358959, Price = 999, Name = "Unlock Lawn Tractor", Kind = "VehicleUnlock", Category = "Vehicles", Giftable = true, Vehicle = "MoonCrawler" },
	{ Key = "UnlockSolarRover", Id = 3723367560, Price = 1299, Name = "Unlock Snow Plow", Kind = "VehicleUnlock", Category = "Vehicles", Giftable = true, Vehicle = "SolarRover" },
	{ Key = "UnlockRocketSweeper", Id = 3723367567, Price = 1699, Name = "Unlock Mega Sweeper", Kind = "VehicleUnlock", Category = "Vehicles", Giftable = true, Vehicle = "RocketSweeper" },
	{ Key = "RentSweeperCart", Id = 3723358973, Price = 59, Name = "Sweeper Cart (this run)", Kind = "VehicleRental", Category = "Vehicles", Giftable = true, Vehicle = "SweeperCart" },
	{ Key = "RentMoonBuggy", Id = 3723367579, Price = 99, Name = "Golf Cart (this run)", Kind = "VehicleRental", Category = "Vehicles", Giftable = true, Vehicle = "MoonBuggy" },
	{ Key = "RentDustTruck", Id = 3723358981, Price = 149, Name = "Garbage Truck (this run)", Kind = "VehicleRental", Category = "Vehicles", Giftable = true, Vehicle = "DustTruck" },
	{ Key = "RentHoverSweeper", Id = 3723367587, Price = 199, Name = "Street Sweeper (this run)", Kind = "VehicleRental", Category = "Vehicles", Giftable = true, Vehicle = "HoverSweeper" },
	{ Key = "RentMoonCrawler", Id = 3723358993, Price = 299, Name = "Lawn Tractor (this run)", Kind = "VehicleRental", Category = "Vehicles", Giftable = true, Vehicle = "MoonCrawler" },
	{ Key = "RentSolarRover", Id = 3723367594, Price = 399, Name = "Snow Plow (this run)", Kind = "VehicleRental", Category = "Vehicles", Giftable = true, Vehicle = "SolarRover" },
	{ Key = "RentRocketSweeper", Id = 3723367601, Price = 499, Name = "Mega Sweeper (this run)", Kind = "VehicleRental", Category = "Vehicles", Giftable = true, Vehicle = "RocketSweeper" },

	-- Cash packs scale with the player: max(Seconds of income, FloorFactor x next tool price).
	-- Floors are kept small so a pack speeds you up instead of skipping several tools at once.
	{ Key = "Cash1", Id = 3723359007, Price = 24, Name = "Pile of Cash", Kind = "CashPack", Category = "Cash", Giftable = true, Seconds = 600, FloorFactor = 0.25 },
	{ Key = "Cash2", Id = 3723359023, Price = 59, Name = "Bag of Cash", Kind = "CashPack", Category = "Cash", Giftable = true, Seconds = 1800, FloorFactor = 0.5 },
	{ Key = "Cash3", Id = 3723359034, Price = 149, Name = "Crate of Cash", Kind = "CashPack", Category = "Cash", Giftable = true, Seconds = 5400, FloorFactor = 1 },
	{ Key = "Cash4", Id = 3723359049, Price = 399, Name = "Vault of Cash", Kind = "CashPack", Category = "Cash", Giftable = true, Seconds = 14400, FloorFactor = 2 },
	{ Key = "Cash5", Id = 3723359058, Price = 999, Name = "Mountain of Cash", Kind = "CashPack", Category = "Cash", Giftable = true, Seconds = 43200, FloorFactor = 4 },

	-- Skip Rebirth gets pricier the further you are (Rebirth = the rebirth it takes you to).
	-- Past the last one, the last price is used again. See Products.skipRebirthFor.
	{ Key = "SkipRebirth", Id = 3723359064, Price = 79, Name = "Skip Rebirth", Kind = "SkipRebirth", Category = "Special", Giftable = true, Rebirth = 1 },
	{ Key = "SkipRebirth2", Id = 3723367608, Price = 149, Name = "Skip to Rebirth 2", Kind = "SkipRebirth", Category = "Special", Giftable = true, Rebirth = 2 },
	{ Key = "SkipRebirth3", Id = 3723367615, Price = 249, Name = "Skip to Rebirth 3", Kind = "SkipRebirth", Category = "Special", Giftable = true, Rebirth = 3 },
	{ Key = "SkipRebirth4", Id = 3723367622, Price = 399, Name = "Skip to Rebirth 4", Kind = "SkipRebirth", Category = "Special", Giftable = true, Rebirth = 4 },
	{ Key = "SkipRebirth5", Id = 3723367627, Price = 599, Name = "Skip to Rebirth 5", Kind = "SkipRebirth", Category = "Special", Giftable = true, Rebirth = 5 },
	{ Key = "SkipRebirth6", Id = 3723367635, Price = 849, Name = "Skip to Rebirth 6", Kind = "SkipRebirth", Category = "Special", Giftable = true, Rebirth = 6 },
	{ Key = "SkipRebirth7", Id = 3723367645, Price = 1199, Name = "Skip to Rebirth 7+", Kind = "SkipRebirth", Category = "Special", Giftable = true, Rebirth = 7 },
	-- Lucky Wheel spins (sold in the wheel window, not the Shop). Count = spins.
	{ Key = "WheelSpin1", Id = 3724118622, Price = 19, Name = "1 Wheel Spin", Kind = "WheelSpins", Category = "Wheel", Giftable = true, Count = 1 },
	{ Key = "WheelSpin5", Id = 3724118638, Price = 79, Name = "5 Wheel Spins", Kind = "WheelSpins", Category = "Wheel", Giftable = true, Count = 5 },
	{ Key = "WheelSpin10", Id = 3724118654, Price = 149, Name = "10 Wheel Spins", Kind = "WheelSpins", Category = "Wheel", Giftable = true, Count = 10 },
	-- Traveling Merchant: a fresh set of wares just for you (sold in the merchant window).
	{ Key = "MerchantRestock", Id = 3724147406, Price = 29, Name = "Merchant Restock", Kind = "MerchantRestock", Category = "Merchant", Giftable = false },
	{ Key = "DoubleOffline", Id = 3723359071, Price = 49, Name = "Double Offline Reward", Kind = "DoubleOffline", Category = "Special", Giftable = false },

	-- Gamepass gifts: Roblox can't gift a gamepass, so each pass has a product you buy for a
	-- friend. It unlocks the pass for them for good (data.GiftedPasses). Gift only.
	{ Key = "GiftCash2x", Id = 3723394046, Price = 99, Name = "Gift: 2x Cash", Kind = "GiftPass", Category = "Gifts", Giftable = true, Pass = "Cash2x" },
	{ Key = "GiftAutoSweep", Id = 3723394058, Price = 149, Name = "Gift: Auto Sweep", Kind = "GiftPass", Category = "Gifts", Giftable = true, Pass = "AutoSweep" },
	{ Key = "GiftExtraSlots", Id = 3723394066, Price = 199, Name = "Gift: +3 Pet Slots", Kind = "GiftPass", Category = "Gifts", Giftable = true, Pass = "ExtraSlots" },
	{ Key = "GiftCarry3", Id = 3723394082, Price = 129, Name = "Gift: Carry 3 Eggs", Kind = "GiftPass", Category = "Gifts", Giftable = true, Pass = "Carry3" },
	{ Key = "GiftVIP", Id = 3723394088, Price = 249, Name = "Gift: VIP", Kind = "GiftPass", Category = "Gifts", Giftable = true, Pass = "VIP" },
	{ Key = "GiftFasterHatch", Id = 3723394096, Price = 229, Name = "Gift: Faster Hatch", Kind = "GiftPass", Category = "Gifts", Giftable = true, Pass = "FasterHatch" },
	{ Key = "GiftFastWalk", Id = 3725049902, Price = 49, Name = "Gift: Fast Walk", Kind = "GiftPass", Category = "Gifts", Giftable = true, Pass = "FastWalk" },
	{ Key = "GiftBigBag", Id = 3725049913, Price = 79, Name = "Gift: Big Bag", Kind = "GiftPass", Category = "Gifts", Giftable = true, Pass = "BigBag" },
	{ Key = "GiftLucky", Id = 3725049926, Price = 149, Name = "Gift: Lucky", Kind = "GiftPass", Category = "Gifts", Giftable = true, Pass = "Lucky" },
	{ Key = "GiftSellAnywhere", Id = 3723696966, Price = 199, Name = "Gift: Sell Anywhere", Kind = "GiftPass", Category = "Gifts", Giftable = true, Pass = "SellAnywhere" },
}

local Config = {
	-- Server Luck is one card with levels (Dev, 2026-10-31): each buy raises the whole
	-- server one level and restarts the shared timer. The price is the product of the level
	-- you go to, so it climbs with the level. At the top level a buy adds time instead.
	ServerLuckLevels = { 2, 4, 8, 16 },
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

-- The gift product for a gamepass, if it exists and is live.
function Config.passGift(passKey: string): ProductDef?
	local def = Config.ProductByKey["Gift" .. passKey]
	return if def and def.Id ~= 0 and def.Kind == "GiftPass" then def else nil
end

-- The Server Luck product to sell when the server is at `level` (1 = no luck running):
-- the next level up, or the top level again (adds time) once it's maxed.
function Config.serverLuckNext(level: number): ProductDef?
	local top: ProductDef? = nil
	for _, mult in Config.ServerLuckLevels do
		local def = Config.ProductByKey["ServerLuck" .. mult]
		if def and def.Id ~= 0 then
			if mult > level then
				return def
			end
			top = def
		end
	end
	return top
end

-- When the limited pack stops being on sale for this player, or nil (bought or over).
function Config.limitedPackEnds(data: any, now: number): number?
	local def = Config.ProductByKey.HalloweenPack
	local pack = Economy.LimitedPack
	if not def or def.Id == 0 or data.Flags.LimitedPackBought == pack.Id or now >= pack.EndsAt then
		return nil
	end
	return pack.EndsAt
end

-- The egg packs for one rarity, smallest first (the shop's "how many?" picker).
function Config.eggPacks(rarity: string): { ProductDef }
	local out = {}
	for _, def in Products do
		if def.Kind == "EggPack" and def.Rarity == rarity and def.Id ~= 0 then
			table.insert(out, def)
		end
	end
	table.sort(out, function(a, b)
		return (a.Count or 1) < (b.Count or 1)
	end)
	return out
end

-- When the Starter Pack stops being on sale for this player (unix seconds), or nil if it
-- isn't on sale for them at all (bought, past the early game, or its time ran out).
function Config.starterPackEnds(data: any, now: number): number?
	local def = Config.ProductByKey.StarterPack
	local pack = Economy.StarterPack
	local ends = data.Flags.StarterPackEnds
	if not def or def.Id == 0 or data.Flags.StarterPackBought or type(ends) ~= "number" then
		return nil
	elseif data.ToolTier >= pack.HideAtToolTier or data.Rebirths > 0 or now >= ends then
		return nil
	end
	return ends
end

-- The Skip Rebirth product for a player who has `rebirths` rebirths now.
function Config.skipRebirthFor(rebirths: number): ProductDef?
	local best: ProductDef? = nil
	for _, def in Products do
		if def.Kind == "SkipRebirth" and def.Id ~= 0 and (def.Rebirth or 1) <= rebirths + 1 then
			if not best or (def.Rebirth or 1) > (best.Rebirth or 1) then
				best = def
			end
		end
	end
	return best
end

return Config
