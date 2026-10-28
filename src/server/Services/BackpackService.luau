--!strict
-- Backpack (dust carried) and selling at the Rocket. The backpack stores dust units plus
-- their base cash value, so dust from rich zones keeps its zone multiplier until sold.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local World = require(Shared.Config.World)

local BackpackService = {}

local S: any
local lastSell: { [Player]: number } = {}

-- Adds cash (number or BigNum) and logs it as an economy source.
function BackpackService:GiveCash(player: Player, amount: any, sku: string, transactionType: Enum.AnalyticsEconomyTransactionType?)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	data.Cash = BigNum.add(data.Cash, amount)
	S.AnalyticsService:Source(player, BigNum.toNumber(amount), transactionType or Enum.AnalyticsEconomyTransactionType.Gameplay, sku)
	S.StateService:Mark(player)
end

-- Spends cash if the player has enough. Returns true on success.
function BackpackService:TrySpend(player: Player, amount: any, sku: string): boolean
	local data = S.DataService:GetData(player)
	if not data or BigNum.lt(data.Cash, amount) then
		return false
	end
	data.Cash = BigNum.sub(data.Cash, amount)
	S.AnalyticsService:Sink(player, BigNum.toNumber(amount), Enum.AnalyticsEconomyTransactionType.Gameplay, sku)
	S.StateService:Mark(player)
	return true
end

function BackpackService:IsFull(player: Player): boolean
	local data = S.DataService:GetData(player)
	return data ~= nil and data.Backpack >= S.ToolService:GetCapacity(player)
end

-- Adds dust from one cleared tile. Returns units actually added and their base value.
function BackpackService:AddDust(player: Player, zone, power: number): (number, number)
	local session = S.DataService:GetSession(player)
	if not session then
		return 0, 0
	end
	local data = session.Data
	local capacity = S.ToolService:GetCapacity(player)
	local room = capacity - data.Backpack
	if room <= 0 then
		return 0, 0
	end
	local units = math.min(room, zone.DustPerTile * power)
	local value = units * zone.CashMult
	data.Backpack += units
	data.BackpackValue += value
	if data.Backpack >= capacity and not session.Runtime.WasFull then
		session.Runtime.WasFull = true
		S.OfferService:OnBackpackFull(player)
	end
	return units, value
end

local function sell(player: Player)
	local session = S.DataService:GetSession(player)
	if not session then
		return
	end
	local data = session.Data
	if data.Backpack <= 0 then
		return
	end
	local now = os.clock()
	if (lastSell[player] or 0) + Economy.SellCooldown > now then
		return
	end
	lastSell[player] = now

	local cash = data.BackpackValue * S.BoostService:GetCashMultiplier(player)
	data.TotalDust = BigNum.add(data.TotalDust, data.Backpack)
	data.Backpack = 0
	data.BackpackValue = 0
	data.Stats.Sells += 1
	session.Runtime.WasFull = false
	BackpackService:GiveCash(player, cash, "SellDust")
	S.AnalyticsService:Funnel(player, "FirstSell")
	Net.fire("Notify", player, `Sold dust for {Format.cash(cash)}!`, "Sell")
end

function BackpackService:Init(services)
	S = services
end

-- Selling is a distance check around the Rocket instead of Touched: Touched on a
-- non-colliding pad was unreliable in playtests, and this also works from vehicles.
local CHECK_EVERY = 0.2
local SELL_HEIGHT = 14

local function inSellZone(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local offset = root.Position - World.RocketPosition
	return Vector2.new(offset.X, offset.Z).Magnitude <= World.SellRadius and math.abs(offset.Y) <= SELL_HEIGHT
end

function BackpackService:Start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < CHECK_EVERY then
			return
		end
		acc = 0
		for _, player in Players:GetPlayers() do
			if inSellZone(player) then
				local ok, err = pcall(sell, player)
				if not ok then
					warn("[BackpackService] sell failed: " .. tostring(err))
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastSell[player] = nil
	end)
end

return BackpackService
