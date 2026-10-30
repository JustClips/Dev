--!strict
-- Backpack (leaves carried) and selling. The backpack stores units plus their base cash
-- value, so leaves from rich zones keep their zone multiplier until sold. Selling:
--   * Leaf dumps beside the market hall (World.Dumps): stand or drive on the circle and the
--     bag pours in bit by bit, cash ticking up (like making honey in Bee Swarm).
--   * Sell Anywhere pass: the HUD Sell button sells the whole bag on the spot, and Auto Sell
--     does it whenever the bag fills up.
-- Every character wears the voxel leaf backpack ("Backpack" model, welded to the torso as
-- "LeafBag"). Player attribute BagFill (0..1 in 5% steps) says how full it is, and
-- BackpackController grows the leaf heap inside it on every client.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Assets = require(Shared.Config.Assets)
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

-- How many coins `units` of leaves turn into: a full bag is Economy.Coins.FullBagCoins.
local function coinCount(player: Player, units: number): number
	local capacity = math.max(1, S.ToolService:GetCapacity(player))
	return math.clamp(math.round(units / capacity * Economy.Coins.FullBagCoins), 1, Economy.Coins.FullBagCoins * 2)
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
	local units = session.Data.Backpack
	local cash = cashOut(player, session, units)
	session.Data.Stats.Sells += 1
	S.AnalyticsService:Source(player, cash, Enum.AnalyticsEconomyTransactionType.Gameplay, "SellAnywhere")
	S.AnalyticsService:Funnel(player, "FirstSell")
	-- The cash bursts out around you as coins to pick up (CoinService).
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root then
		local feet = root.Position - Vector3.new(0, (if humanoid then humanoid.HipHeight else 2) + root.Size.Y / 2, 0)
		S.CoinService:Drop(player, cash, root.Position + Vector3.new(0, 2, 0), feet, math.max(Economy.Coins.MinSellAll, coinCount(player, units)), 5, 16)
	else
		S.CoinService:Drop(player, cash, Vector3.zero, Vector3.zero, 1, 0, 0)
	end
	S.StateService:Mark(player)
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

type Dump = { spot: number, rate: number, total: number, unpaid: number, unpaidUnits: number, nextDrop: number }

-- The cash poured so far comes out of the dump's coin slot as coins (CoinService).
local function dropCoins(player: Player, dump: Dump)
	if dump.unpaid <= 0 then
		return
	end
	local count = math.max(Economy.Coins.MinBurst, coinCount(player, dump.unpaidUnits))
	local cf = World.Dumps[dump.spot]
	-- Out over the leaf field in front of the dump, well clear of the market hall.
	S.CoinService:Drop(player, dump.unpaid, (cf * CFrame.new(0, 3, -3.8)).Position, World.dumpSpot(dump.spot), count, 7, 26, cf.LookVector)
	dump.unpaid = 0
	dump.unpaidUnits = 0
end

local function stopDump(player: Player, session)
	local dump: Dump? = session.Runtime.Dump
	if not dump then
		return
	end
	session.Runtime.Dump = nil
	player:SetAttribute("Dumping", nil)
	dropCoins(player, dump)
	if dump.total > 0 then
		session.Data.Stats.Sells += 1
		S.AnalyticsService:Source(player, BigNum.toNumber(dump.total), Enum.AnalyticsEconomyTransactionType.Gameplay, "SellDust")
		S.AnalyticsService:Funnel(player, "FirstSell")
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
		dump = { spot = spot, rate = rate, total = 0, unpaid = 0, unpaidUnits = 0, nextDrop = os.clock() + Economy.Coins.DumpEvery }
		session.Runtime.Dump = dump
		player:SetAttribute("Dumping", spot)
	end
	local d = dump :: Dump
	local units = math.ceil(d.rate * dt)
	local before = data.Backpack
	local cash = cashOut(player, session, units)
	d.total += cash
	d.unpaid += cash
	d.unpaidUnits += before - data.Backpack
	if os.clock() >= d.nextDrop then
		d.nextDrop = os.clock() + Economy.Coins.DumpEvery
		dropCoins(player, d)
	end
	S.StateService:Mark(player)
	local capacity = math.max(1, S.ToolService:GetCapacity(player))
	Net.fire("DumpTick", player, cash, data.Backpack / capacity)
	if data.Backpack <= 0 then
		stopDump(player, session)
	end
end

-- Worn backpack -----------------------------------------------------------------------

local BAG_SCALE = 0.8 -- of the modelled size, on a standard 2-stud-wide torso

local function wear(character: Model)
	local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
	if not torso or character:FindFirstChild("LeafBag") then
		return
	end
	local model = AssetLibrary.get("Backpack")
	local body = model and model:FindFirstChild("Body") :: BasePart?
	local fill = model and model:FindFirstChild("Fill") :: BasePart?
	if not model or not body then
		if model then
			model:Destroy()
		end
		return
	end
	model.Name = "LeafBag"
	local scale = BAG_SCALE * math.clamp(torso.Size.X / 2, 0.6, 1.6)
	model:ScaleTo(scale)
	model:PivotTo(torso.CFrame * CFrame.new(0, 0.05 * scale, torso.Size.Z / 2))
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
		end
	end
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part ~= fill then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = torso
			weld.Part1 = part
			weld.Parent = part
		end
	end
	if fill then
		-- A plain Weld so clients can move the heap's centre as it grows from the bottom.
		local meta = Assets.Models.Backpack
		local joint = (meta and meta.parts.Fill and (meta.parts.Fill :: any).joint) or Vector3.new(0, -1.18, 0.6)
		local bottom = model:GetPivot() * CFrame.new(joint * scale)
		local weld = Instance.new("Weld")
		weld.Name = "FillWeld"
		weld.Part0 = body
		weld.Part1 = fill
		weld.C0 = body.CFrame:Inverse() * fill.CFrame
		weld.Parent = fill
		fill:SetAttribute("FullSize", fill.Size)
		fill:SetAttribute("Bottom", body.CFrame:PointToObjectSpace(bottom.Position))
		fill.Color = Color3.fromRGB(232, 140, 45)
	end
	model.Parent = character
end

local function updateFill(player: Player, session)
	local capacity = math.max(1, S.ToolService:GetCapacity(player))
	local fill = math.floor(math.clamp(session.Data.Backpack / capacity, 0, 1) * 20 + 0.5) / 20
	if player:GetAttribute("BagFill") ~= fill then
		player:SetAttribute("BagFill", fill)
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
			updateFill(player, session)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastSell[player] = nil
	end)
	S.BaseService.CharacterReady:Connect(function(_player: Player, character: Model)
		if AssetLibrary.has("Backpack") then
			wear(character)
		else
			task.spawn(function()
				if AssetLibrary.waitReady(180) and character.Parent then
					wear(character)
				end
			end)
		end
	end)
end

return BackpackService
