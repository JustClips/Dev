--!strict
-- Your coins from selling (CoinService). They fly out of the dump (or burst out around you
-- with Sell Anywhere), land, and spin on the ground. Walk within your magnet range (the
-- Money Magnet upgrades make it bigger) and they zip into you with a chime that climbs in
-- pitch. Only you see your own coins. Coins left too long are paid out by the server and
-- fly to you on their own (CoinsAuto).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local CoinController = {}

local GOLD = Color3.fromRGB(255, 196, 40)
local FLY_OUT = 0.55 -- seconds from the slot to the ground
local FLY_IN = 0.22 -- seconds from the ground into you
local REPORT_EVERY = 0.15
local MAX_COINS = 120

type Coin = {
	id: number,
	part: BasePart,
	from: Vector3,
	to: Vector3,
	start: number,
	spin: number,
	state: string, -- "out" | "ground" | "in"
	inStart: number,
	inFrom: Vector3,
	report: boolean,
}

local folder: Folder
local pool: { BasePart } = {}
local coins: { [number]: Coin } = {}
local count = 0
local toReport: { number } = {}
local lastReport = 0
local streak = 0
local lastPickup = 0

local function take(): BasePart
	local part = table.remove(pool)
	if part then
		return part
	end
	local p = Instance.new("Part")
	p.Name = "Coin"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.35, 2, 2)
	p.Color = GOLD
	p.Material = Enum.Material.Metal
	p.Reflectance = 0.15
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function give(part: BasePart)
	part.Parent = nil
	table.insert(pool, part)
end

local function remove(coin: Coin)
	coins[coin.id] = nil
	count -= 1
	give(coin.part)
end

local function rootPart(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function startIn(coin: Coin, report: boolean, now: number)
	if coin.state == "in" then
		return
	end
	coin.state = "in"
	coin.inStart = now
	coin.inFrom = coin.part.Position
	coin.report = report
end

local function onDropped(origin: Vector3, list: any)
	if type(list) ~= "table" then
		return
	end
	local now = os.clock()
	for i, item in list do
		if count >= MAX_COINS or type(item) ~= "table" or typeof(item.Pos) ~= "Vector3" then
			continue
		end
		local part = take()
		local coin: Coin = {
			id = item.Id,
			part = part,
			from = origin,
			to = item.Pos + Vector3.new(0, 1.1, 0),
			start = now + (i - 1) * 0.04,
			spin = math.random() * math.pi * 2,
			state = "out",
			inStart = 0,
			inFrom = origin,
			report = false,
		}
		part.CFrame = CFrame.new(origin)
		part.Parent = folder
		coins[coin.id] = coin
		count += 1
	end
	Ui.sound("Coin", 1.1)
end

local function onAuto(ids: any)
	if type(ids) ~= "table" then
		return
	end
	local now = os.clock()
	for _, id in ids do
		local coin = coins[id]
		if coin then
			startIn(coin, false, now) -- already paid: no report
		end
	end
end

local function step()
	local now = os.clock()
	local root = rootPart()
	local magnet = Players.LocalPlayer:GetAttribute("CoinMagnet")
	local range = if type(magnet) == "number" then magnet else 7
	local target = if root then root.Position else nil
	for _, coin in coins do
		local part = coin.part
		if coin.state == "out" then
			local t = math.clamp((now - coin.start) / FLY_OUT, 0, 1)
			local pos = coin.from:Lerp(coin.to, t) + Vector3.new(0, math.sin(t * math.pi) * 5, 0)
			part.CFrame = CFrame.new(pos) * CFrame.Angles(0, t * 12, math.pi / 2)
			if t >= 1 then
				coin.state = "ground"
			end
		elseif coin.state == "ground" then
			-- Spins slowly and bobs while it waits.
			local bob = math.sin(now * 3 + coin.spin) * 0.25
			part.CFrame = CFrame.new(coin.to + Vector3.new(0, bob, 0)) * CFrame.Angles(0, now * 2.5 + coin.spin, math.pi / 2)
			if target then
				local d = target - coin.to
				if Vector2.new(d.X, d.Z).Magnitude <= range and math.abs(d.Y) < 14 then
					startIn(coin, true, now)
				end
			end
		else
			local t = math.clamp((now - coin.inStart) / FLY_IN, 0, 1)
			local goal = if target then target else coin.inFrom
			part.CFrame = CFrame.new(coin.inFrom:Lerp(goal, t * t)) * CFrame.Angles(0, now * 10, math.pi / 2)
			if t >= 1 then
				if coin.report then
					table.insert(toReport, coin.id)
				end
				-- A chime that climbs while you scoop up a pile.
				streak = if now - lastPickup < 0.6 then math.min(streak + 1, 12) else 0
				lastPickup = now
				Ui.sound("Coin", 1 + streak * 0.05)
				remove(coin)
			end
		end
	end
	if #toReport > 0 and now - lastReport >= REPORT_EVERY then
		lastReport = now
		local batch = toReport
		toReport = {}
		Net.event("CoinsCollect"):FireServer(batch)
	end
end

function CoinController:Init() end

function CoinController:Start()
	folder = Instance.new("Folder")
	folder.Name = "MyCoins"
	folder.Parent = Workspace
	Net.event("CoinsDropped").OnClientEvent:Connect(onDropped)
	Net.event("CoinsAuto").OnClientEvent:Connect(onAuto)
	RunService.RenderStepped:Connect(step)
end

return CoinController
