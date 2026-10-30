--!strict
-- Your coins from selling (CoinService). They fly out of the dump (or burst out around you
-- with Sell Anywhere), land, and spin on the ground. Walk within your magnet range (the
-- Money Magnet upgrades make it bigger) and they zip into you with a chime that climbs in
-- pitch. Only you see your own coins. Coins left too long are paid out by the server and
-- fly to you on their own (CoinsAuto).
-- Like Pet Simulator, a "+$123" counter over your head adds up every coin you scoop while
-- you keep collecting: it counts up, punches bigger with each coin and fades when you stop.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local CoinController = {}

local GOLD = Color3.fromRGB(255, 196, 40)
local FLY_OUT = 0.7 -- seconds from the slot to the ground
local FLY_IN = 0.22 -- seconds from the ground into you
local REPORT_EVERY = 0.15
local MAX_COINS = 120

type Coin = {
	id: number,
	value: number,
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
			value = if type(item.Value) == "number" then item.Value else 0,
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

-- The "+$123" counter over your head ------------------------------------------------------

local COUNTER_HOLD = 1.4 -- seconds after the last coin before it fades
local counter: BillboardGui
local counterLabel: TextLabel
local counterScale: UIScale
local counterTotal = 0 -- cash collected this streak
local counterShown = 0 -- what the label shows (counts up to counterTotal)
local counterLast = -math.huge
local counterFading = false
local fadeTweens: { Tween } = {}

local function makeCounter()
	counter = Instance.new("BillboardGui")
	counter.Name = "CoinCounter"
	counter.Size = UDim2.fromOffset(240, 64)
	counter.StudsOffset = Vector3.new(0, 4.2, 0)
	counter.AlwaysOnTop = true
	counter.LightInfluence = 0
	counter.MaxDistance = 200
	counter.Enabled = false
	counter.ResetOnSpawn = false
	counterLabel = Instance.new("TextLabel")
	counterLabel.BackgroundTransparency = 1
	counterLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	counterLabel.Position = UDim2.fromScale(0.5, 0.5)
	counterLabel.Size = UDim2.fromScale(1, 1)
	counterLabel.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
	counterLabel.TextScaled = true
	counterLabel.TextColor3 = Color3.new(1, 1, 1)
	counterLabel.Parent = counter
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(70, 40, 0)
	stroke.Parent = counterLabel
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 250, 200), Color3.fromRGB(255, 170, 20))
	gradient.Parent = counterLabel
	counterScale = Instance.new("UIScale")
	counterScale.Parent = counterLabel
	counter.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function bump(value: number, root: BasePart?)
	if not root then
		return
	end
	local now = os.clock()
	if now - counterLast > COUNTER_HOLD or counterFading then
		counterTotal, counterShown = 0, 0
	end
	counterFading = false
	for _, tween in fadeTweens do
		tween:Cancel()
	end
	table.clear(fadeTweens)
	counterLast = now
	counterTotal += value
	counter.Adornee = root
	counter.StudsOffset = Vector3.new(0, 4.2, 0)
	counterLabel.TextTransparency = 0
	counter.Enabled = true
	-- Punch: bigger the longer the streak.
	counterScale.Scale = 1.35 + math.min(streak, 12) * 0.03
	TweenService:Create(counterScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1 + math.min(streak, 12) * 0.02,
	}):Play()
end

local function stepCounter(now: number, dt: number)
	if not counter.Enabled then
		return
	end
	if counterShown < counterTotal then
		-- Counts up quickly: catches up in about a quarter second.
		counterShown = math.min(counterTotal, counterShown + math.max((counterTotal - counterShown) * dt * 10, counterTotal * dt * 2))
		counterLabel.Text = "+" .. Format.cash(math.floor(counterShown + 0.5))
	end
	if not counterFading and now - counterLast > COUNTER_HOLD then
		counterFading = true
		local info = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		fadeTweens = {
			TweenService:Create(counterLabel, info, { TextTransparency = 1 }),
			TweenService:Create(counter, info, { StudsOffset = Vector3.new(0, 6, 0) }),
		}
		for _, tween in fadeTweens do
			tween:Play()
		end
		task.delay(0.45, function()
			if counterFading then
				counter.Enabled = false
			end
		end)
	end
end

local lastStep = os.clock()
local function step()
	local now = os.clock()
	local dt = math.min(now - lastStep, 0.1)
	lastStep = now
	local root = rootPart()
	local magnet = Players.LocalPlayer:GetAttribute("CoinMagnet")
	local range = if type(magnet) == "number" then magnet else 7
	local target = if root then root.Position else nil
	for _, coin in coins do
		local part = coin.part
		if coin.state == "out" then
			local t = math.clamp((now - coin.start) / FLY_OUT, 0, 1)
			local arc = 4 + (coin.to - coin.from).Magnitude * 0.25
			local pos = coin.from:Lerp(coin.to, t) + Vector3.new(0, math.sin(t * math.pi) * arc, 0)
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
				bump(coin.value, root)
				remove(coin)
			end
		end
	end
	stepCounter(now, dt)
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
	makeCounter()
	Net.event("CoinsDropped").OnClientEvent:Connect(onDropped)
	Net.event("CoinsAuto").OnClientEvent:Connect(onAuto)
	RunService.RenderStepped:Connect(step)
end

return CoinController
