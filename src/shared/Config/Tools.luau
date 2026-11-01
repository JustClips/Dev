--!strict
-- The hand tool ladder (GAME_PLAN §5.5) and the cars sold at the Garage. Prices are in cash.
-- Cars are separate from tools: they live in their own HUD slot, you can own several,
-- and in a car you sweep with the car's radius and power.
local Types = require(script.Parent.Parent.Types)

type ToolDef = Types.ToolDef
type VehicleDef = Types.VehicleDef

-- Style: how the tool clears leaves and which effects it makes (LeafController, ToolFxController):
-- Scrub/Brush sweep leaves into your backpack, Blower and Spray blow them away, Vacuum sucks
-- them into the nozzle. 16 tools since 2026-10-31; prices are fitted by tools/balance/fit.py.
local List: { ToolDef } = {
	{ Tier = 1, Id = "Toothbrush", Name = "Toothbrush", Style = "Scrub", Radius = 4, Power = 1, Capacity = 150, Price = 0, IsVehicle = false, Color = Color3.fromRGB(120, 200, 255), Scale = 1 },
	{ Tier = 2, Id = "Broom", Name = "Broom", Style = "Brush", Radius = 5, Power = 2, Capacity = 400, Price = 150, IsVehicle = false, Color = Color3.fromRGB(220, 170, 90), Scale = 1.3 },
	{ Tier = 3, Id = "Rake", Name = "Rake", Style = "Brush", Radius = 5.5, Power = 3, Capacity = 800, Price = 1_300, IsVehicle = false, Color = Color3.fromRGB(80, 200, 90), Scale = 1.35 },
	{ Tier = 4, Id = "Mop", Name = "Mop", Style = "Brush", Radius = 6, Power = 4, Capacity = 1_500, Price = 1_500, IsVehicle = false, Color = Color3.fromRGB(150, 230, 200), Scale = 1.45 },
	{ Tier = 5, Id = "PushBroom", Name = "Push Broom", Style = "Brush", Radius = 7, Power = 6, Capacity = 2_800, Price = 44_000, IsVehicle = false, Color = Color3.fromRGB(225, 75, 75), Scale = 1.5 },
	{ Tier = 6, Id = "LeafBlower", Name = "Leaf Blower", Style = "Blower", Radius = 8, Power = 8, Capacity = 4_500, Price = 180_000, IsVehicle = false, Color = Color3.fromRGB(255, 140, 60), Scale = 1.6 },
	{ Tier = 7, Id = "LeafVac", Name = "Leaf Vacuum", Style = "Vacuum", Radius = 9, Power = 12, Capacity = 8_000, Price = 1_600_000, IsVehicle = false, Color = Color3.fromRGB(90, 185, 75), Scale = 1.7 },
	{ Tier = 8, Id = "ShopVac", Name = "Shop Vac", Style = "Vacuum", Radius = 10, Power = 16, Capacity = 15_000, Price = 2_900_000, IsVehicle = false, Color = Color3.fromRGB(255, 210, 60), Scale = 1.8 },
	{ Tier = 9, Id = "PressureWasher", Name = "Pressure Washer", Style = "Spray", Radius = 11, Power = 24, Capacity = 26_000, Price = 4_800_000, IsVehicle = false, Color = Color3.fromRGB(60, 140, 255), Scale = 1.9 },
	{ Tier = 10, Id = "TurboVacuum", Name = "Turbo Vacuum", Style = "Vacuum", Radius = 12, Power = 32, Capacity = 45_000, Price = 42_000_000, IsVehicle = false, Color = Color3.fromRGB(200, 90, 255), Scale = 2 },
	{ Tier = 11, Id = "GoldenBroom", Name = "Golden Broom", Style = "Brush", Radius = 13, Power = 45, Capacity = 70_000, Price = 330_000_000, IsVehicle = false, Color = Color3.fromRGB(255, 200, 60), Scale = 2 },
	{ Tier = 12, Id = "StormBlower", Name = "Storm Blower", Style = "Blower", Radius = 14, Power = 60, Capacity = 100_000, Price = 1_400_000_000, IsVehicle = false, Color = Color3.fromRGB(60, 80, 160), Scale = 2.1 },
	{ Tier = 13, Id = "TornadoVac", Name = "Tornado Vac", Style = "Vacuum", Radius = 15, Power = 80, Capacity = 150_000, Price = 6_700_000_000, IsVehicle = false, Color = Color3.fromRGB(40, 180, 180), Scale = 2.1 },
	{ Tier = 14, Id = "DiamondMop", Name = "Diamond Mop", Style = "Brush", Radius = 16, Power = 110, Capacity = 220_000, Price = 10_000_000_000, IsVehicle = false, Color = Color3.fromRGB(90, 230, 255), Scale = 2.2 },
	{ Tier = 15, Id = "RainbowDuster", Name = "Rainbow Duster", Style = "Brush", Radius = 17, Power = 150, Capacity = 320_000, Price = 14_000_000_000, IsVehicle = false, Color = Color3.fromRGB(255, 110, 200), Scale = 2.2 },
	{ Tier = 16, Id = "GalaxyVacuum", Name = "Galaxy Vacuum", Style = "Vacuum", Radius = 18, Power = 200, Capacity = 450_000, Price = 16_000_000_000, IsVehicle = false, Color = Color3.fromRGB(120, 60, 200), Scale = 2.3 },
}

-- Capacity: a car raises your backpack size while you own it. Later cars need rebirths.
-- Prices are fitted by tools/balance/fit.py (first car ~1 h, rebirth 1 ~1.5 h, rebirth 5 ~15 h).
local Vehicles: { VehicleDef } = {
	{ Order = 1, Id = "SweeperCart", Name = "Sweeper Cart", Radius = 14, Power = 50, Capacity = 100_000, Price = 4_300_000_000, RequiredRebirths = 0, Color = Color3.fromRGB(80, 200, 120), Scale = 1, Speed = 44, RentKey = "RentSweeperCart", UnlockKey = "UnlockSweeperCart" },
	{ Order = 2, Id = "MoonBuggy", Name = "Golf Cart", Radius = 16, Power = 90, Capacity = 180_000, Price = 8_500_000_000, RequiredRebirths = 0, Color = Color3.fromRGB(255, 140, 60), Scale = 1.15, Speed = 47, RentKey = "RentMoonBuggy", UnlockKey = "UnlockMoonBuggy" },
	{ Order = 3, Id = "DustTruck", Name = "Garbage Truck", Radius = 20, Power = 180, Capacity = 450_000, Price = 910_000_000_000, RequiredRebirths = 1, Color = Color3.fromRGB(255, 180, 40), Scale = 1.35, Speed = 50, RentKey = "RentDustTruck", UnlockKey = "UnlockDustTruck", SeatDrop = 1.8 },
	{ Order = 4, Id = "HoverSweeper", Name = "Street Sweeper", Radius = 24, Power = 400, Capacity = 1_100_000, Price = 2_200_000_000_000, RequiredRebirths = 2, Color = Color3.fromRGB(180, 120, 255), Scale = 1.5, Speed = 53, RentKey = "RentHoverSweeper", UnlockKey = "UnlockHoverSweeper", SeatDrop = 1.8 },
	{ Order = 5, Id = "MoonCrawler", Name = "Lawn Tractor", Radius = 28, Power = 900, Capacity = 3_500_000, Price = 130_000_000_000_000, RequiredRebirths = 3, Color = Color3.fromRGB(90, 160, 255), Scale = 1.8, Speed = 56, RentKey = "RentMoonCrawler", UnlockKey = "UnlockMoonCrawler" },
	{ Order = 6, Id = "SolarRover", Name = "Snow Plow", Radius = 32, Power = 2_000, Capacity = 8_000_000, Price = 1_400_000_000_000_000, RequiredRebirths = 4, Color = Color3.fromRGB(240, 240, 245), Scale = 2, Speed = 58, RentKey = "RentSolarRover", UnlockKey = "UnlockSolarRover", SeatDrop = 1.8 },
	{ Order = 7, Id = "RocketSweeper", Name = "Mega Sweeper", Radius = 38, Power = 5_000, Capacity = 20_000_000, Price = 17_000_000_000_000_000, RequiredRebirths = 5, Color = Color3.fromRGB(255, 74, 90), Scale = 2.2, Speed = 64, RentKey = "RentRocketSweeper", UnlockKey = "UnlockRocketSweeper", SeatDrop = 1.8 },
}

local Tools = {
	List = List,
	MaxTier = #List,
	Vehicles = Vehicles,
	VehicleById = {} :: { [string]: VehicleDef },
	ById = {} :: { [string]: ToolDef },
}

for _, t in List do
	Tools.ById[t.Id] = t
end

for _, v in Vehicles do
	Tools.VehicleById[v.Id] = v
end

-- Your best hand tool powers your car's brush too (Dev, 2026-10-31: tools bought after the
-- first car have to stay worth it). From the Leaf Blower up, each tier adds PerTier.
Tools.CarBoost = { FromTier = 6, PerTier = 0.15 }

function Tools.carBoost(bestTier: number): number
	return 1 + Tools.CarBoost.PerTier * math.max(0, bestTier - Tools.CarBoost.FromTier)
end

function Tools.get(tier: number): ToolDef
	return List[math.clamp(tier, 1, #List)]
end

-- The first tool (Broom) and the first Sweep Power level are always FREE. They used to be
-- tutorial steps; since 2026-10-31 (shorter tutorial) they are the Quest Master's first
-- jobs, so they stay free after the tutorial too. Callers only use this for Broom (tier 2)
-- and Sweep Power level 0. Arguments kept so the call sites stay the same.
Tools.FreeTier = 2
function Tools.tutorialPrice(_price: number, _cash: number, _tutorialDone: boolean): number
	return 0
end

function Tools.vehicle(id: string): VehicleDef?
	return Tools.VehicleById[id]
end

-- Only cars you bought (or unlocked) count: buying one does NOT unlock the cheaper ones
-- (Dev, 2026-10-31).
function Tools.hasVehicle(vehicles: { [string]: boolean }, id: string): boolean
	return vehicles[id] == true
end

return Tools
