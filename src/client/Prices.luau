--!strict
-- Robux prices as THIS player pays them. With Roblox regional pricing on, players in some
-- countries pay less than the price in Products.luau, so the UI asks Roblox for the real
-- price instead of showing the hard-coded one. Until the answer arrives (or if it fails)
-- the Products.luau price is shown.
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Products = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Products"))

local Prices = {}

local byId: { [number]: number } = {}
local changed = Instance.new("BindableEvent")
Prices.Changed = changed.Event
local started = false

-- The price this player pays for a product or pass entry from Products.luau.
function Prices.of(def: { Id: number, Price: number }?): number
	if not def then
		return 0
	end
	return byId[def.Id] or def.Price
end

local function loadProducts()
	local ok, pages = pcall(function()
		return MarketplaceService:GetDeveloperProductsAsync()
	end)
	if not ok or not pages then
		return
	end
	while true do
		for _, info in pages:GetCurrentPage() do
			local id = info.ProductId or info.DeveloperProductId
			if type(id) == "number" and type(info.PriceInRobux) == "number" then
				byId[id] = info.PriceInRobux
			end
		end
		if pages.IsFinished then
			break
		end
		if not pcall(function()
			pages:AdvanceToNextPageAsync()
		end) then
			break
		end
	end
end

local function loadPasses()
	for _, pass in Products.Gamepasses do
		if pass.Id and pass.Id ~= 0 then
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfoAsync(pass.Id, Enum.InfoType.GamePass)
			end)
			if ok and info and type(info.PriceInRobux) == "number" then
				byId[pass.Id] = info.PriceInRobux
			end
		end
	end
end

function Prices.load()
	if started then
		return
	end
	started = true
	task.spawn(function()
		loadProducts()
		loadPasses()
		changed:Fire()
	end)
end

return Prices
