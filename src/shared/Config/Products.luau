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
	{ Key = "VIP", Id = 2060219551, Price = 249, Name = "VIP", Description = "+20% cash, VIP tag, 4 h offline income." },
	{ Key = "FasterHatch", Id = 2057507586, Price = 229, Name = "Faster Hatch", Description = "All hatch timers halved." },
	{ Key = "SellAnywhere", Id = 2058462006, Price = 199, Name = "Sell Anywhere", Description = "Sell your whole bag from anywhere with one tap, plus Auto Sell when it fills up." },
}

local Products: { ProductDef } = {
	{ Key = "StarterPack", Id = 3723358524, Price = 9, Name = "Starter Pack", Kind = "StarterPack", Category = "Special", Giftable = false },

	{ Key = "ServerLuck2", Id = 3723358734, Price = 19, Name = "2x Server Luck (15 min)", Kind = "ServerLuck", Category = "Boosts", Giftable = false, Mult = 2, Minutes = 15 },
	{ Key = "ServerLuck4", Id = 3723358741, Price = 39, Name = "4x Server Luck (15 min)", Kind = "ServerLuck", Category = "Boosts", Giftable = false, Mult = 4, Minutes = 15 },
	{ Key = "ServerLuck8", Id = 3723358752, Price = 79, Name = "8x Server Luck (15 min)", Kind = "ServerLuck", Category = "Boosts", Giftable = false, Mult = 8, Minutes = 15 },
	{ Key = "ServerLuck16", Id = 3723358764, Price = 159, Name = "16x Server Luck (15 min)", Kind = "ServerLuck", Category = "Boosts", Giftable = false, Mult = 16, Minutes = 15 },
	{ Key = "MeteorShower", Id = 3723358773, Price = 199, Name = "Egg Rain Now", Kind = "MeteorShower", Category = "Boosts", Giftable = false },

	{ Key = "SkipHatchCommon", Id = 3723358783, Price = 5, Name = "Skip Hatch (Common)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Common" },
	{ Key = "SkipHatchUncommon", Id = 3723358792, Price = 15, Name = "Skip Hatch (Uncommon)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Uncommon" },
	{ Key = "SkipHatchRare", Id = 3723358806, Price = 35, Name = "Skip Hatch (Rare)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Rare" },
	{ Key = "SkipHatchEpic", Id = 3723358816, Price = 45, Name = "Skip Hatch (Epic)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Epic" },
	{ Key = "SkipHatchLegendary", Id = 3723358824, Price = 65, Name = "Skip Hatch (Legendary)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Legendary" },
	{ Key = "SkipHatchMythic", Id = 3723358840, Price = 85, Name = "Skip Hatch (Mythic)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Mythic" },
	{ Key = "SkipHatchCosmic", Id = 3723358849, Price = 105, Name = "Skip Hatch (Cosmic)", Kind = "SkipHatch", Category = "Eggs", Giftable = true, Rarity = "Cosmic" },
	{ Key = "CosmicEgg1", Id = 3723358859, Price = 99, Name = "Cosmic Egg", Kind = "EggPack", Category = "Eggs", Giftable = true, Rarity = "Cosmic", Count = 1 },
	{ Key = "CosmicEgg3", Id = 3723358868, Price = 249, Name = "3 Cosmic Eggs", Kind = "EggPack", Category = "Eggs", Giftable = true, Rarity = "Cosmic", Count = 3 },

	-- "Next tool now": priced per target tier.
	{ Key = "ToolSkip2", Id = 3723358874, Price = 3, Name = "Unlock Broom", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 2 },
	{ Key = "ToolSkip3", Id = 3723358883, Price = 9, Name = "Unlock Mop", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 3 },
	{ Key = "ToolSkip4", Id = 3723358889, Price = 25, Name = "Unlock Leaf Blower", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 4 },
	{ Key = "ToolSkip5", Id = 3723358904, Price = 59, Name = "Unlock Shop Vac", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 5 },
	{ Key = "ToolSkip6", Id = 3723358915, Price = 129, Name = "Unlock Turbo Vacuum", Kind = "ToolSkip", Category = "Tools", Giftable = true, Tier = 6 },

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
	{ Key = "DoubleOffline", Id = 3723359071, Price = 49, Name = "Double Offline Reward", Kind = "DoubleOffline", Category = "Special", Giftable = false },

	-- Gamepass gifts: Roblox can't gift a gamepass, so each pass has a product you buy for a
	-- friend. It unlocks the pass for them for good (data.GiftedPasses). Gift only.
	{ Key = "GiftCash2x", Id = 3723394046, Price = 99, Name = "Gift: 2x Cash", Kind = "GiftPass", Category = "Gifts", Giftable = true, Pass = "Cash2x" },
	{ Key = "GiftAutoSweep", Id = 3723394058, Price = 149, Name = "Gift: Auto Sweep", Kind = "GiftPass", Category = "Gifts", Giftable = true, Pass = "AutoSweep" },
	{ Key = "GiftExtraSlots", Id = 3723394066, Price = 199, Name = "Gift: +3 Pet Slots", Kind = "GiftPass", Category = "Gifts", Giftable = true, Pass = "ExtraSlots" },
	{ Key = "GiftCarry3", Id = 3723394082, Price = 129, Name = "Gift: Carry 3 Eggs", Kind = "GiftPass", Category = "Gifts", Giftable = true, Pass = "Carry3" },
	{ Key = "GiftVIP", Id = 3723394088, Price = 249, Name = "Gift: VIP", Kind = "GiftPass", Category = "Gifts", Giftable = true, Pass = "VIP" },
	{ Key = "GiftFasterHatch", Id = 3723394096, Price = 229, Name = "Gift: Faster Hatch", Kind = "GiftPass", Category = "Gifts", Giftable = true, Pass = "FasterHatch" },
	{ Key = "GiftSellAnywhere", Id = 3723696966, Price = 199, Name = "Gift: Sell Anywhere", Kind = "GiftPass", Category = "Gifts", Giftable = true, Pass = "SellAnywhere" },
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

-- The gift product for a gamepass, if it exists and is live.
function Config.passGift(passKey: string): ProductDef?
	local def = Config.ProductByKey["Gift" .. passKey]
	return if def and def.Id ~= 0 and def.Kind == "GiftPass" then def else nil
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
