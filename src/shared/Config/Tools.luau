--!strict
-- The tool and vehicle ladder (GAME_PLAN §5.5). Prices are in cash.
local Types = require(script.Parent.Parent.Types)

type ToolDef = Types.ToolDef

local List: { ToolDef } = {
	{ Tier = 1, Id = "Toothbrush", Name = "Toothbrush", Radius = 3, Power = 1, Capacity = 50, Price = 0, IsVehicle = false, Color = Color3.fromRGB(120, 200, 255), Scale = 1 },
	{ Tier = 2, Id = "Broom", Name = "Broom", Radius = 5, Power = 2, Capacity = 150, Price = 250, IsVehicle = false, Color = Color3.fromRGB(220, 170, 90), Scale = 1.3 },
	{ Tier = 3, Id = "Mop", Name = "Mop", Radius = 6, Power = 4, Capacity = 400, Price = 1_500, IsVehicle = false, Color = Color3.fromRGB(150, 230, 200), Scale = 1.45 },
	{ Tier = 4, Id = "LeafBlower", Name = "Leaf Blower", Radius = 8, Power = 7, Capacity = 1_000, Price = 8_000, IsVehicle = false, Color = Color3.fromRGB(255, 140, 60), Scale = 1.6 },
	{ Tier = 5, Id = "ShopVac", Name = "Shop Vac", Radius = 10, Power = 12, Capacity = 3_000, Price = 40_000, IsVehicle = false, Color = Color3.fromRGB(255, 210, 60), Scale = 1.8 },
	{ Tier = 6, Id = "TurboVacuum", Name = "Turbo Vacuum", Radius = 12, Power = 20, Capacity = 8_000, Price = 200_000, IsVehicle = false, Color = Color3.fromRGB(200, 90, 255), Scale = 2 },
	{ Tier = 7, Id = "SweeperCart", Name = "Sweeper Cart", Radius = 16, Power = 35, Capacity = 25_000, Price = 1_200_000, IsVehicle = true, Color = Color3.fromRGB(80, 200, 120), Scale = 1, VehicleSpeed = 34 },
	{ Tier = 8, Id = "DustTruck", Name = "Dust Truck", Radius = 22, Power = 60, Capacity = 80_000, Price = 8_000_000, IsVehicle = true, Color = Color3.fromRGB(255, 180, 40), Scale = 1.35, VehicleSpeed = 38 },
	{ Tier = 9, Id = "MoonCrawler", Name = "Moon Crawler", Radius = 32, Power = 120, Capacity = 300_000, Price = 60_000_000, IsVehicle = true, Color = Color3.fromRGB(90, 160, 255), Scale = 1.8, VehicleSpeed = 42 },
}

local Tools = {
	List = List,
	MaxTier = #List,
	-- On foot, a vehicle-tier owner sweeps with the best hand tool.
	MaxHandTier = 6,
}

function Tools.get(tier: number): ToolDef
	return List[math.clamp(tier, 1, #List)]
end

return Tools
