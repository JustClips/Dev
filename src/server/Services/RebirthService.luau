--!strict
-- Rebirth: resets cash, tools, cars, upgrades and backpack; keeps aliens, index and zones.
-- Each rebirth adds +50% cash and every 2nd adds a base slot. Rebirth 1 opens the Mars gate.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local RebirthService = {}

local S: any

function RebirthService:GetCost(data): BigNum.BigNum
	return BigNum.new(Economy.rebirthCost(data.Rebirths))
end

-- Performs the rebirth. paid = false for the Skip Rebirth product.
function RebirthService:DoRebirth(player: Player, paid: boolean): (boolean, string)
	local data = S.DataService:GetData(player)
	if not data then
		return false, "Still loading"
	end
	local cost = RebirthService:GetCost(data)
	if paid then
		if BigNum.lt(data.Cash, cost) then
			S.ShopService:OfferCashFor(player, BigNum.sub(cost, data.Cash))
			return false, `Need {Format.cash(cost)} to rebirth`
		end
		S.AnalyticsService:Sink(player, BigNum.toNumber(cost), Enum.AnalyticsEconomyTransactionType.Gameplay, "Rebirth")
	end
	data.Rebirths += 1
	data.Cash = BigNum.zero()
	data.Backpack = 0
	data.BackpackValue = 0
	S.ToolService:ResetForRebirth(player)
	S.UpgradeService:ResetForRebirth(player)
	S.AlienService:RefreshBase(player)
	S.AnalyticsService:Funnel(player, "FirstRebirth")
	S.StateService:Mark(player)
	local bonus = math.floor(data.Rebirths * Economy.RebirthCashBonus * 100)
	Net.fireAll("Announce", `{player.DisplayName} reached Rebirth {data.Rebirths}!`, "Rebirth")
	S.FavoriteService:Moment(player)
	return true, `Rebirth {data.Rebirths}! Permanent +{bonus}% cash.`
end

function RebirthService:Init(services)
	S = services
	Net.onInvoke("Rebirth", function(player)
		return RebirthService:DoRebirth(player, true)
	end)
end

return RebirthService
