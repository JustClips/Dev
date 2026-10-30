--!strict
-- leaderstats (Cash as a formatted string, Rebirths). No overhead tag (Dev: clutter).
--
-- Global leaderboards (Dev, 2026-10-30): total cash earned (all time), best cash per second
-- ever reached, and most rebirths, each the top 10 across every server. Scores go to
-- OrderedDataStores every SAVE_SECONDS and the plaza leaderboard stands (MapBuilder leaderboards)
-- reload every LOAD_SECONDS. OrderedDataStores only hold whole numbers, so cash values are
-- stored as round(log10(value + 1) * SCALE) and turned back for display.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Format = require(Shared.Format)
local World = require(Shared.Config.World)

local REFRESH_SECONDS = 1
local SAVE_SECONDS = 120
local LOAD_SECONDS = 90
local TOP = 10
local SCALE = 1e12
local FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
local RANK_COLORS = { Color3.fromRGB(255, 205, 60), Color3.fromRGB(215, 222, 235), Color3.fromRGB(230, 150, 90) }

local LeaderboardService = {}

local S: any
local stores: { [string]: OrderedDataStore } = {}
local names: { [number]: string } = {}

local function ensureStats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Value = "$0"
	cash.Parent = stats
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = stats
	stats.Parent = player
end

local function refresh(player: Player, data)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		(stats:FindFirstChild("Cash") :: StringValue).Value = Format.cash(data.Cash);
		(stats:FindFirstChild("Rebirths") :: IntValue).Value = data.Rebirths
	end
	-- Best cash per second this player has ever reached.
	local perSec = S.AlienService:GetIncomePerSec(player)
	if perSec > (data.Stats.BestPerSec or 0) then
		data.Stats.BestPerSec = perSec
	end
end

-- Adds to the all-time cash earned (called wherever cash is gained).
function LeaderboardService:AddEarned(player: Player, amount: any)
	local data = S.DataService:GetData(player)
	if data and BigNum.toNumber(amount) > 0 then
		data.Stats.CashEarned = BigNum.add(data.Stats.CashEarned or BigNum.zero(), amount)
	end
end

local function encodeCash(value: any): number
	local n = BigNum.from(value)
	if n.m <= 0 then
		return 0
	end
	-- log10 of m * 10^e, without turning huge values into inf
	local log = if n.e == 0 then math.log10(n.m + 1) else math.log10(n.m) + n.e
	return math.max(0, math.round(log * SCALE))
end

local function decodeCash(score: number): any
	local log = score / SCALE
	if log < 15 then
		return math.max(0, math.round(10 ^ log - 1))
	end
	local e = math.floor(log)
	return { m = 10 ^ (log - e), e = e }
end

local function scoresOf(data): { [string]: number }
	return {
		Earned = encodeCash(data.Stats.CashEarned or 0),
		PerSec = encodeCash(data.Stats.BestPerSec or 0),
		Rebirths = data.Rebirths,
	}
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	names[userId] = if ok and type(name) == "string" then name else "Player"
	return names[userId]
end

local function save(player: Player, data)
	if not data or player.UserId <= 0 then
		return
	end
	for key, score in scoresOf(data) do
		local store = stores[key]
		if store and score > 0 then
			pcall(store.SetAsync, store, tostring(player.UserId), score)
		end
	end
end

local function row(parent: Instance, rank: number, userId: number, value: string)
	local frame = Instance.new("Frame")
	frame.Name = "Row"
	frame.LayoutOrder = rank
	frame.Size = UDim2.new(1, 0, 0, 33)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = if rank % 2 == 1 then 0.92 else 1
	frame.BorderSizePixel = 0
	local function text(name: string, t: string, x: number, w: number, align: Enum.TextXAlignment, color: Color3)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Position = UDim2.new(x, if x == 0 then 2 else 0, 0, 1)
		label.Size = UDim2.new(w, 0, 1, -2)
		label.FontFace = FONT
		label.Text = t
		label.TextScaled = true
		label.TextXAlignment = align
		label.TextColor3 = color
		label.Parent = frame
	end
	text("Rank", `#{rank}`, 0, 0.11, Enum.TextXAlignment.Left, RANK_COLORS[rank] or Color3.fromRGB(200, 205, 220))
	local head = Instance.new("ImageLabel")
	head.BackgroundTransparency = 1
	head.Position = UDim2.new(0.11, 0, 0, 1)
	head.Size = UDim2.fromOffset(31, 31)
	head.Image = `rbxthumb://type=AvatarHeadShot&id={userId}&w=48&h=48`
	head.Parent = frame
	text("Name", nameOf(userId), 0.2, 0.48, Enum.TextXAlignment.Left, Color3.new(1, 1, 1))
	text("Value", value, 0.68, 0.31, Enum.TextXAlignment.Right, RANK_COLORS[rank] or Color3.fromRGB(140, 230, 140))
	frame.Parent = parent
end

local function load()
	local folder = Workspace:FindFirstChild("Structures")
	local boards = folder and folder:FindFirstChild("Leaderboards")
	if not boards then
		return
	end
	for _, def in World.Leaderboards do
		local store = stores[def.Key]
		local part = boards:FindFirstChild("Board_" .. def.Key, true)
		local rows = part and part:FindFirstChild("Rows", true)
		if not store or not rows then
			continue
		end
		local ok, pages = pcall(store.GetSortedAsync, store, false, TOP)
		if not ok then
			continue
		end
		local list = (pages :: DataStorePages):GetCurrentPage()
		for _, child in rows:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for rank, entry in list do
			local userId = tonumber(entry.key)
			if userId then
				local score = entry.value
				local value = if def.Key == "Rebirths" then tostring(score) elseif def.Key == "PerSec" then `{Format.cash(decodeCash(score))}/s` else Format.cash(decodeCash(score))
				row(rows, rank, userId, value)
			end
		end
	end
end

function LeaderboardService:Init(services)
	S = services
	S.DataService.ProfileLoaded:Connect(function(player, session)
		ensureStats(player)
		-- Profiles from before the boards start from the cash they hold now.
		local data = session.Data
		if not data.Stats.CashEarned then
			data.Stats.CashEarned = BigNum.from(data.Cash)
		end
	end)
	for _, def in World.Leaderboards do
		local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, "Leaderboard_" .. def.Key .. "_v1")
		if ok then
			stores[def.Key] = store
		end
	end
end

function LeaderboardService:Start()
	task.spawn(function()
		while true do
			task.wait(REFRESH_SECONDS)
			for player, session in S.DataService:GetSessions() do
				refresh(player, session.Data)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(SAVE_SECONDS)
			for player, session in S.DataService:GetSessions() do
				save(player, session.Data)
				task.wait(0.5)
			end
		end
	end)
	task.spawn(function()
		task.wait(5)
		while true do
			load()
			task.wait(LOAD_SECONDS)
		end
	end)
	S.DataService.ProfileReleasing:Connect(function(player, session)
		save(player, session.Data)
	end)
end

return LeaderboardService
