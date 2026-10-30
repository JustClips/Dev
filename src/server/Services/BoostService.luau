--!strict
-- Server luck (2x/4x/8x/16x), personal boosts (potions, +10% luck per friend in the
-- server), plus the one place that computes a player's cash multiplier. Luck timers stack
-- additively per tier; the highest active tier is the server's luck.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Upgrades = require(Shared.Config.Upgrades)
local Economy = require(Shared.Config.Economy)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Rewards = require(Shared.Config.Rewards)

local LUCK_TIERS = { 2, 4, 8, 16 }

local BoostService = {}

local S: any
local luckEnds: { [number]: number } = {}
-- Friend boost: who each player is friends with in this server (by UserId). Filled when
-- someone joins (IsFriendsWith is a web call, so it's asked once per pair).
local friendsOf: { [Player]: { [number]: boolean } } = {}

local function publish()
	local state = S.StateService:GetServerState()
	for _, tier in LUCK_TIERS do
		local ends = luckEnds[tier] or 0
		state:SetAttribute("Luck" .. tier, if ends > os.time() then ends else 0)
	end
	state:SetAttribute("LuckMult", BoostService:GetServerLuck())
end

function BoostService:GetServerLuck(): number
	local now = os.time()
	local best = 1
	for _, tier in LUCK_TIERS do
		if (luckEnds[tier] or 0) > now and tier > best then
			best = tier
		end
	end
	-- A live event (Config/Rewards.Events) multiplies whatever luck is running.
	local event = Rewards.activeEvent(now)
	-- So does the weather (Rainbow, Aurora Night).
	-- Admin events (AdminService) stack on top.
	return best * (if event then event.LuckMult else 1) * S.WeatherService:GetLuckMult() * S.AdminService:Mult("Luck")
end

function BoostService:AddServerLuck(mult: number, minutes: number, buyer: Player?)
	if not table.find(LUCK_TIERS, mult) then
		warn("[BoostService] unknown luck tier " .. mult)
		return
	end
	local now = os.time()
	luckEnds[mult] = math.max(luckEnds[mult] or 0, now) + minutes * 60
	publish()
	local who = if buyer then buyer.DisplayName else "Someone"
	Net.fireAll("Announce", `{who} activated {mult}x Server Luck for {minutes} min!`, "Luck")
end

-- Personal timed boost (stacks time). Stored as an expiry unix time in the profile.
function BoostService:AddPersonalBoost(player: Player, key: string, minutes: number)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	local now = os.time()
	data.Boosts[key] = math.max(data.Boosts[key] or 0, now) + minutes * 60
	S.StateService:Mark(player)
end

function BoostService:IsBoostActive(player: Player, key: string): boolean
	local data = S.DataService:GetData(player)
	return data ~= nil and (data.Boosts[key] or 0) > os.time()
end

-- Friends of this player who are in the server right now.
function BoostService:GetFriendCount(player: Player): number
	local count = 0
	for userId in friendsOf[player] or {} do
		local other = Players:GetPlayerByUserId(userId)
		if other and other ~= player then
			count += 1
		end
	end
	return count
end

-- +10% egg luck per friend in the server (Economy.FriendLuckPerFriend), capped.
function BoostService:GetFriendLuck(player: Player): number
	local friends = math.min(BoostService:GetFriendCount(player), Economy.FriendLuckMaxFriends)
	return 1 + friends * Economy.FriendLuckPerFriend
end

-- Personal luck: the Luck potion times the friend boost. Multiplies egg rarity luck,
-- mutations and Huge chance.
function BoostService:GetPersonalLuck(player: Player): number
	local potion = if BoostService:IsBoostActive(player, "Luck2x") then Items.LuckMult else 1
	return potion * BoostService:GetFriendLuck(player)
end

local function areFriends(a: Player, b: Player): boolean
	local ok, result = pcall(function()
		return a:IsFriendsWith(b.UserId)
	end)
	return ok and result == true
end

local function markFriends(player: Player)
	if player.Parent and S.DataService:GetSession(player) then
		S.StateService:Mark(player)
	end
end

local function onJoin(player: Player)
	friendsOf[player] = friendsOf[player] or {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			task.spawn(function()
				if not areFriends(player, other) or not player.Parent or not other.Parent then
					return
				end
				local mine, theirs = friendsOf[player], friendsOf[other]
				if not mine or mine[other.UserId] then
					return -- left meanwhile, or already counted
				end
				mine[other.UserId] = true
				if theirs then
					theirs[player.UserId] = true
				end
				markFriends(player)
				markFriends(other)
				local pct = math.floor(Economy.FriendLuckPerFriend * 100 + 0.5)
				Net.fire("Notify", other, `Your friend {player.DisplayName} joined: +{pct}% luck!`, "Good")
			end)
		end
	end
end

local function onLeave(player: Player)
	friendsOf[player] = nil
	for other, list in friendsOf do
		if list[player.UserId] then
			list[player.UserId] = nil
			markFriends(other)
		end
	end
end

-- Speed potion: extra walk speed while active.
function BoostService:GetSpeedBonus(player: Player): number
	return (if BoostService:IsBoostActive(player, "Speed") then Items.SpeedBonus else 0) + S.AdminService:Add("Speed")
end

function BoostService:HasPass(player: Player, key: string): boolean
	local data = S.DataService:GetData(player)
	return data ~= nil and data.Gamepasses[key] == true
end

-- rebirths x upgrade tree x 2x pass x VIP x timed 2x
function BoostService:GetCashMultiplier(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return 1
	end
	local mult = (1 + data.Rebirths * Economy.RebirthCashBonus) * Upgrades.multiplier(data.Upgrades, "Cash")
	if data.Gamepasses.Cash2x then
		mult *= Economy.Cash2xPassMult
	end
	if data.Gamepasses.VIP then
		mult *= 1 + Economy.VIPCashBonus
	end
	if (data.Boosts.Cash2x or 0) > os.time() then
		mult *= Economy.Cash2xBoostMult
	end
	return mult * S.AdminService:Mult("Cash")
end

-- Same as above without temporary boosts (used for offline income).
function BoostService:GetBaseCashMultiplier(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return 1
	end
	local mult = (1 + data.Rebirths * Economy.RebirthCashBonus) * Upgrades.multiplier(data.Upgrades, "Cash")
	if data.Gamepasses.Cash2x then
		mult *= Economy.Cash2xPassMult
	end
	if data.Gamepasses.VIP then
		mult *= 1 + Economy.VIPCashBonus
	end
	return mult
end

function BoostService:Init(services)
	S = services
end

function BoostService:Start()
	publish()
	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(onLeave)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
	local lastLuck = 1
	task.spawn(function()
		while true do
			task.wait(1)
			local luck = BoostService:GetServerLuck()
			if luck ~= lastLuck then
				lastLuck = luck
				publish()
			end
		end
	end)
end

return BoostService
