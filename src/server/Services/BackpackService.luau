--!strict
-- Backpack (leaves carried) and selling. The backpack stores units plus their base cash
-- value, so leaves from rich zones keep their zone multiplier until sold. Selling:
--   * Leaf dumps beside the market hall (World.Dumps): stand or drive on the circle and the
--     bag pours in bit by bit, cash ticking up (like making honey in Bee Swarm).
--   * Sell Anywhere pass: the HUD Sell button sells the whole bag on the spot, and Auto Sell
--     does it whenever the bag fills up.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Upgrades = require(Shared.Config.Upgrades)
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)
local World = require(Shared.Config.World)

local BackpackService = {}

local S: any
local lastSell: { [Player]: number } = {}

-- Adds cash (number or BigNum) and logs it as an economy source.
-- Sources that show their own feedback (the cash pop for these comes from elsewhere or not at all).
local QUIET_SOURCES = { SellPet = true, OfflineIncome = true, TutorialReward = true }

function BackpackService:GiveCash(player: Player, amount: any, sku: string, transactionType: Enum.AnalyticsEconomyTransactionType?)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	data.Cash = BigNum.add(data.Cash, amount)
	S.AnalyticsService:Source(player, BigNum.toNumber(amount), transactionType or Enum.AnalyticsEconomyTransactionType.Gameplay, sku)
	S.StateService:Mark(player)
	-- Big one-off gains get the "you got" popup; selling and offline income have their own.
	if not QUIET_SOURCES[sku] then
		Net.fire("CashGained", player, { Amount = BigNum.from(amount), Source = sku })
	end
end

-- Cash earned per second from selling dust over the last few minutes (cash packs scale
-- with it, so late-game packs stay worth buying).
local EARN_BUCKET = 30
local EARN_BUCKETS = 10

local function recordEarning(session, amount: number)
	local log = session.Runtime.EarnLog
	if not log then
		log = {}
		session.Runtime.EarnLog = log
	end
	local bucket = math.floor(os.time() / EARN_BUCKET)
	log[bucket] = (log[bucket] or 0) + amount
	log[bucket - EARN_BUCKETS] = nil
end

function BackpackService:GetEarnRate(player: Player): number
	local session = S.DataService:GetSession(player)
	local log = session and session.Runtime.EarnLog
	if not log then
		return 0
	end
	local now = math.floor(os.time() / EARN_BUCKET)
	local total = 0
	for bucket, amount in log do
		if bucket > now - EARN_BUCKETS then
			total += amount
		end
	end
	local seconds = math.min(EARN_BUCKET * EARN_BUCKETS, os.time() - session.JoinedAt + EARN_BUCKET)
	return total / math.max(seconds, EARN_BUCKET)
end

-- Spends cash if the player has enough. Returns true on success. When they're short,
-- the server offers the cash pack that covers the gap (ShopService), unless quiet = true.
function BackpackService:TrySpend(player: Player, amount: any, sku: string, quiet: boolean?): boolean
	local data = S.DataService:GetData(player)
	if not data then
		return false
	end
	if BigNum.lt(data.Cash, amount) then
		if not quiet then
			S.ShopService:OfferCashFor(player, BigNum.sub(amount, data.Cash))
		end
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
function BackpackService:AddDust(player: Player, zone, power: number, mult: number?): (number, number)
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
	local value = units * zone.CashMult * (mult or 1) * Upgrades.multiplier(data.Upgrades, "DustValue")
	data.Backpack += units
	data.BackpackValue += value
	if data.Backpack >= capacity and not session.Runtime.WasFull then
		session.Runtime.WasFull = true
		S.OfferService:OnBackpackFull(player)
	end
	return units, value
end

-- Pays for part of the bag (units of it). Returns the cash paid.
local function cashOut(player: Player, session, units: number): number
	local data = session.Data
	units = math.min(units, data.Backpack)
	if units <= 0 then
		return 0
	end
	local value = if units >= data.Backpack then data.BackpackValue else data.BackpackValue * units / data.Backpack
	local cash = value * S.BoostService:GetCashMultiplier(player)
	data.TotalDust = BigNum.add(data.TotalDust, units)
	data.Backpack -= units
	data.BackpackValue = math.max(0, data.BackpackValue - value)
	if data.Backpack <= 0 then
		data.Backpack = 0
		data.BackpackValue = 0
	end
	session.Runtime.WasFull = false
	recordEarning(session, cash)
	return cash
end

-- Sells the whole bag at once (Sell Anywhere). Returns the cash paid.
local function sellAll(player: Player): number
	local session = S.DataService:GetSession(player)
	if not session or session.Data.Backpack <= 0 then
		return 0
	end
	local now = os.clock()
	if (lastSell[player] or 0) + Economy.SellCooldown > now then
		return 0
	end
	lastSell[player] = now
	local cash = cashOut(player, session, session.Data.Backpack)
	session.Data.Stats.Sells += 1
	BackpackService:GiveCash(player, cash, "SellAnywhere")
	S.AnalyticsService:Funnel(player, "FirstSell")
	return cash
end

-- Leaf dumps -------------------------------------------------------------------------

local CHECK_EVERY = 0.2
local SPOT_HEIGHT = 14

-- Which dump's circle the player (or the car they drive) is on, if any.
local function dumpAt(player: Player): number?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	for i in World.Dumps do
		local d = root.Position - World.dumpSpot(i)
		if Vector2.new(d.X, d.Z).Magnitude <= World.DumpRadius + 1 and math.abs(d.Y) <= SPOT_HEIGHT then
			return i
		end
	end
	return nil
end

type Dump = { spot: number, rate: number, total: number }

local function stopDump(player: Player, session)
	local dump: Dump? = session.Runtime.Dump
	if not dump then
		return
	end
	session.Runtime.Dump = nil
	player:SetAttribute("Dumping", nil)
	if dump.total > 0 then
		session.Data.Stats.Sells += 1
		S.AnalyticsService:Source(player, BigNum.toNumber(dump.total), Enum.AnalyticsEconomyTransactionType.Gameplay, "SellDust")
		S.AnalyticsService:Funnel(player, "FirstSell")
		Net.fire("CashGained", player, { Amount = BigNum.from(dump.total), Source = "SellDust" })
	end
end

-- One step of pouring the bag into dump i: a full bag takes Economy.DumpSeconds, a small
-- one Economy.DumpMinSeconds.
local function dumpStep(player: Player, session, spot: number, dt: number)
	local data = session.Data
	local dump: Dump? = session.Runtime.Dump
	if dump and dump.spot ~= spot then
		stopDump(player, session)
		dump = nil
	end
	if data.Backpack <= 0 then
		stopDump(player, session)
		return
	end
	if not dump then
		local capacity = S.ToolService:GetCapacity(player)
		local rate = math.max(1, math.min(capacity / Economy.DumpSeconds, data.Backpack / Economy.DumpMinSeconds))
		dump = { spot = spot, rate = rate, total = 0 }
		session.Runtime.Dump = dump
		player:SetAttribute("Dumping", spot)
	end
	local d = dump :: Dump
	local units = math.ceil(d.rate * dt)
	local cash = cashOut(player, session, units)
	data.Cash = BigNum.add(data.Cash, cash)
	d.total += cash
	S.StateService:Mark(player)
	local capacity = math.max(1, S.ToolService:GetCapacity(player))
	Net.fire("DumpTick", player, cash, data.Backpack / capacity)
	if data.Backpack <= 0 then
		stopDump(player, session)
	end
end

function BackpackService:Init(services)
	S = services
	Net.onInvoke("SellNow", function(player: Player)
		local data = S.DataService:GetData(player)
		if not data then
			return false, "Not loaded yet"
		end
		if not data.Gamepasses.SellAnywhere then
			return false, "NoPass"
		end
		if data.Backpack <= 0 then
			return false, "Your bag is empty"
		end
		local cash = sellAll(player)
		return cash > 0, if cash > 0 then "Sold" else "Slow down"
	end)
	Net.onEvent("SetAutoSell", function(player, enabled)
		local data = S.DataService:GetData(player)
		if data and type(enabled) == "boolean" then
			data.Settings.AutoSell = enabled
			S.StateService:Mark(player)
		end
	end)
end

function BackpackService:Start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < CHECK_EVERY then
			return
		end
		local step = acc
		acc = 0
		for _, player in Players:GetPlayers() do
			local session = S.DataService:GetSession(player)
			if not session then
				continue
			end
			local ok, err = pcall(function()
				local spot = dumpAt(player)
				if spot then
					dumpStep(player, session, spot, step)
				else
					stopDump(player, session)
					local data = session.Data
					if data.Gamepasses.SellAnywhere and data.Settings.AutoSell ~= false and BackpackService:IsFull(player) then
						sellAll(player)
					end
				end
			end)
			if not ok then
				warn("[BackpackService] selling failed: " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastSell[player] = nil
	end)
end

return BackpackService
