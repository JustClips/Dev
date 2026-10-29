--!strict
-- The hand tool ladder (GAME_PLAN §5.5) and the cars sold at the Garage. Prices are in cash.
-- Cars are separate from tools: they live in their own HUD slot, you can own several,
-- and in a car you sweep with the car's radius and power.
local Types = require(script.Parent.Parent.Types)

type ToolDef = Types.ToolDef
type VehicleDef = Types.VehicleDef

local List: { ToolDef } = {
	{ Tier = 1, Id = "Toothbrush", Name = "Toothbrush", Radius = 4, Power = 1, Capacity = 150, Price = 0, IsVehicle = false, Color = Color3.fromRGB(120, 200, 255), Scale = 1 },
	{ Tier = 2, Id = "Broom", Name = "Broom", Radius = 5, Power = 2, Capacity = 400, Price = 150, IsVehicle = false, Color = Color3.fromRGB(220, 170, 90), Scale = 1.3 },
	{ Tier = 3, Id = "Mop", Name = "Mop", Radius = 6, Power = 4, Capacity = 1_500, Price = 2_000, IsVehicle = false, Color = Color3.fromRGB(150, 230, 200), Scale = 1.45 },
	{ Tier = 4, Id = "LeafBlower", Name = "Leaf Blower", Radius = 8, Power = 8, Capacity = 4_500, Price = 250_000, IsVehicle = false, Color = Color3.fromRGB(255, 140, 60), Scale = 1.6 },
	{ Tier = 5, Id = "ShopVac", Name = "Shop Vac", Radius = 10, Power = 16, Capacity = 15_000, Price = 1_500_000, IsVehicle = false, Color = Color3.fromRGB(255, 210, 60), Scale = 1.8 },
	{ Tier = 6, Id = "TurboVacuum", Name = "Turbo Vacuum", Radius = 12, Power = 32, Capacity = 45_000, Price = 590_000_000, IsVehicle = false, Color = Color3.fromRGB(200, 90, 255), Scale = 2 },
}

-- Capacity: a car raises your backpack size while you own it. Later cars need rebirths.
-- Prices are fitted by tools/balance/fit.py (first car ~1 h, rebirth 1 ~1.5 h, rebirth 5 ~15 h).
local Vehicles: { VehicleDef } = {
	{ Order = 1, Id = "SweeperCart", Name = "Sweeper Cart", Radius = 14, Power = 50, Capacity = 100_000, Price = 3_900_000_000, RequiredRebirths = 0, Color = Color3.fromRGB(80, 200, 120), Scale = 1, Speed = 34, RentKey = "RentSweeperCart", UnlockKey = "UnlockSweeperCart" },
	{ Order = 2, Id = "MoonBuggy", Name = "Golf Cart", Radius = 16, Power = 90, Capacity = 180_000, Price = 7_100_000_000, RequiredRebirths = 0, Color = Color3.fromRGB(255, 140, 60), Scale = 1.15, Speed = 36, RentKey = "RentMoonBuggy", UnlockKey = "UnlockMoonBuggy" },
	{ Order = 3, Id = "DustTruck", Name = "Garbage Truck", Radius = 20, Power = 180, Capacity = 450_000, Price = 26_000_000_000, RequiredRebirths = 1, Color = Color3.fromRGB(255, 180, 40), Scale = 1.35, Speed = 38, RentKey = "RentDustTruck", UnlockKey = "UnlockDustTruck", SeatDrop = 1.8 },
	{ Order = 4, Id = "HoverSweeper", Name = "Street Sweeper", Radius = 24, Power = 400, Capacity = 1_100_000, Price = 220_000_000_000, RequiredRebirths = 2, Color = Color3.fromRGB(180, 120, 255), Scale = 1.5, Speed = 40, RentKey = "RentHoverSweeper", UnlockKey = "UnlockHoverSweeper", SeatDrop = 1.8 },
	{ Order = 5, Id = "MoonCrawler", Name = "Lawn Tractor", Radius = 28, Power = 900, Capacity = 3_500_000, Price = 4_000_000_000_000, RequiredRebirths = 3, Color = Color3.fromRGB(90, 160, 255), Scale = 1.8, Speed = 42, RentKey = "RentMoonCrawler", UnlockKey = "UnlockMoonCrawler" },
	{ Order = 6, Id = "SolarRover", Name = "Snow Plow", Radius = 32, Power = 2_000, Capacity = 8_000_000, Price = 110_000_000_000_000, RequiredRebirths = 4, Color = Color3.fromRGB(240, 240, 245), Scale = 2, Speed = 44, RentKey = "RentSolarRover", UnlockKey = "UnlockSolarRover", SeatDrop = 1.8 },
	{ Order = 7, Id = "RocketSweeper", Name = "Mega Sweeper", Radius = 38, Power = 5_000, Capacity = 20_000_000, Price = 930_000_000_000_000, RequiredRebirths = 5, Color = Color3.fromRGB(255, 74, 90), Scale = 2.2, Speed = 48, RentKey = "RentRocketSweeper", UnlockKey = "UnlockRocketSweeper", SeatDrop = 1.8 },
}

local Tools = {
	List = List,
	MaxTier = #List,
	Vehicles = Vehicles,
	VehicleById = {} :: { [string]: VehicleDef },
}

for _, v in Vehicles do
	Tools.VehicleById[v.Id] = v
end

function Tools.get(tier: number): ToolDef
	return List[math.clamp(tier, 1, #List)]
end

function Tools.vehicle(id: string): VehicleDef?
	return Tools.VehicleById[id]
end

return Tools
