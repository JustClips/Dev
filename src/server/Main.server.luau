--!strict
-- Boots every server service in a fixed order: all Init() first, then all Start().
-- Services get the shared `services` table in Init so they can call each other
-- without require cycles.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local bootStart = os.clock()
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
Net.setup()

local ORDER = {
	"AssetService",
	"DataService",
	"AnalyticsService",
	"StateService",
	"WorldService",
	"BaseService",
	"BoostService",
	"DustService",
	"ToolService",
	"UpgradeService",
	"BackpackService",
	"CoinService",
	"ZoneService",
	"EggService",
	"HatchService",
	"InventoryService",
	"TraderService",
	"AlienService",
	"RebirthService",
	"EventService",
	"WeatherService",
	"ShopService",
	"RewardService",
	"OfferService",
	"LeaderboardService",
	"DustBunnyService",
	"SweepService",
	"AdminService",
}

local folder = script.Parent:WaitForChild("Services")
local services: { [string]: any } = {}
for _, name in ORDER do
	services[name] = require(folder:WaitForChild(name) :: ModuleScript)
end

for _, name in ORDER do
	local service = services[name]
	if service.Init then
		service:Init(services)
	end
end
for _, name in ORDER do
	local service = services[name]
	if service.Start then
		service:Start()
	end
end

print(string.format("[Server] %d services started in %.0f ms", #ORDER, (os.clock() - bootStart) * 1000))
