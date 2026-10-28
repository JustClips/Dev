--!strict
-- The hand tool ladder (GAME_PLAN §5.5) and the cars sold at the Garage. Prices are in cash.
-- Cars are separate from tools: they live in their own HUD slot, you can own several,
-- and in a car you sweep with the car's radius and power.
local Types = require(script.Parent.Parent.Types)

type ToolDef = Types.ToolDef
type VehicleDef = Types.VehicleDef

local List: { ToolDef } = {
	{ Tier = 1, Id = "Toothbrush", Name = "Toothbrush", Radius = 3, Power = 1, Capacity = 50, Price = 0, IsVehicle = false, Color = Color3.fromRGB(120, 200, 255), Scale = 1 },
	{ Tier = 2, Id = "Broom", Name = "Broom", Radius = 5, Power = 2, Capacity = 150, Price = 250, IsVehicle = false, Color = Color3.fromRGB(220, 170, 90), Scale = 1.3 },
	{ Tier = 3, Id = "Mop", Name = "Mop", Radius = 6, Power = 4, Capacity = 400, Price = 1_500, IsVehicle = false, Color = Color3.fromRGB(150, 230, 200), Scale = 1.45 },
	{ Tier = 4, Id = "LeafBlower", Name = "Leaf Blower", Radius = 8, Power = 7, Capacity = 1_000, Price = 8_000, IsVehicle = false, Color = Color3.fromRGB(255, 140, 60), Scale = 1.6 },
	{ Tier = 5, Id = "ShopVac", Name = "Shop Vac", Radius = 10, Power = 12, Capacity = 3_000, Price = 40_000, IsVehicle = false, Color = Color3.fromRGB(255, 210, 60), Scale = 1.8 },
	{ Tier = 6, Id = "TurboVacuum", Name = "Turbo Vacuum", Radius = 12, Power = 20, Capacity = 8_000, Price = 200_000, IsVehicle = false, Color = Color3.fromRGB(200, 90, 255), Scale = 2 },
}

-- Capacity: a car raises your backpack size while you own it.
local Vehicles: { VehicleDef } = {
	{ Order = 1, Id = "SweeperCart", Name = "Sweeper Cart", Radius = 16, Power = 35, Capacity = 25_000, Price = 1_200_000, Color = Color3.fromRGB(80, 200, 120), Scale = 1, Speed = 34, RentKey = "RentSweeperCart", UnlockKey = "UnlockSweeperCart" },
	{ Order = 2, Id = "DustTruck", Name = "Dust Truck", Radius = 22, Power = 60, Capacity = 80_000, Price = 8_000_000, Color = Color3.fromRGB(255, 180, 40), Scale = 1.35, Speed = 38, RentKey = "RentDustTruck", UnlockKey = "UnlockDustTruck" },
	{ Order = 3, Id = "MoonCrawler", Name = "Moon Crawler", Radius = 32, Power = 120, Capacity = 300_000, Price = 60_000_000, Color = Color3.fromRGB(90, 160, 255), Scale = 1.8, Speed = 42, RentKey = "RentMoonCrawler", UnlockKey = "UnlockMoonCrawler" },
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
