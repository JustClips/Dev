--!strict
-- Server luck (one shared level: 1x > 2x > 4x > 8x > 16x), personal boosts (potions, +10%
-- luck per friend in the server), plus the one place that computes a player's cash
-- multiplier. Each Server Luck buy raises the level one step and restarts the shared timer;
-- at the top level it adds time instead. When the timer runs out the server goes back to 1x.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Upgrades = require(Shared.Config.Upgrades)
local Economy = require(Shared.Config.Economy)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Rewards = require(Shared.Config.Rewards)

local LUCK_LEVELS = Products.ServerLuckLevels

local BoostService = {}

local S: any
local luckLevel = 1
local luckEnds = 0
-- Friend boost: who each player is friends with in this server (by UserId). Filled when
-- someone joins (IsFriendsWith is a web call, so it's asked once per pair).
local friendsOf: { [Player]: { [number]: boolean } } = {}

-- The bought Server Luck level right now (1 = none).
function BoostService:GetLuckLevel(): number
	return if luckEnds > os.time() then luckLevel else 1
end

local function publish()
	local state = S.StateService:GetServerState()
	local level = BoostService:GetLuckLevel()
	state:SetAttribute("LuckLevel", level)
	state:SetAttribute("LuckEnds", if level > 1 then luckEnds else 0)
	state:SetAttribute("LuckMult", BoostService:GetServerLuck())
end

function BoostService:GetServerLuck(): number
	local now = os.time()
	-- A live event (Config/Rewards.Events) multiplies whatever luck is running.
	local event = Rewards.activeEvent(now)
	-- So does the weather (Rainbow, Aurora Night).
	-- Admin events (AdminService) stack on top.
	return BoostService:GetLuckLevel() * (if event then event.LuckMult else 1) * S.WeatherService:GetLuckMult() * S.AdminService:Mult("Luck")
end

-- The Server Luck product the next buyer gets, or nil (and why) when nothing can be sold:
-- the top level with its timer already full.
function BoostService:NextLuckProduct(): (any, string?)
	local level = BoostService:GetLuckLevel()
	local def = Products.serverLuckNext(level)
	if not def then
		return nil, "Coming soon!"
	end
	local maxMinutes = Economy.ServerLuckMaxMinutes
	if (def.Mult or 0) <= level and luckEnds - os.time() > (maxMinutes - (def.Minutes or Economy.ServerLuckMinutes)) * 60 then
		return nil, `Server Luck is maxed out! Try again when it's under {maxMinutes - (def.Minutes or Economy.ServerLuckMinutes)} min.`
	end
	return def, nil
end

-- A paid Server Luck buy for level `mult`. If someone else raised the server to that level
-- while the prompt was open, the buyer still pushes it one level higher (or adds time at
-- the top), so nobody pays for nothing.
function BoostService:AddServerLuck(mult: number, minutes: number, buyer: Player?)
	if not table.find(LUCK_LEVELS, mult) then
		warn("[BoostService] unknown luck level " .. mult)
		return
	end
	local now = os.time()
	local current = BoostService:GetLuckLevel()
	local top = LUCK_LEVELS[#LUCK_LEVELS]
	local level = mult
	if mult <= current then
		level = current
		for _, step in LUCK_LEVELS do
			if step > current then
				level = step
				break
			end
		end
	end
	local who = if buyer then buyer.DisplayName else "Someone"
	if level > current then
		luckLevel = level
		luckEnds = now + minutes * 60
		Net.fireAll("Announce", `{who} has boosted Server Luck to {level}x!`, "Luck")
	else
		-- Already at the top: more time, up to the cap.
		luckLevel = top
		luckEnds = math.min(math.max(luckEnds, now) + minutes * 60, now + Economy.ServerLuckMaxMinutes * 60)
		Net.fireAll("Announce", `{who} added {minutes} min of {top}x Server Luck!`, "Luck")
	end
	publish()
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
	local potion = if BoostService:IsBoostActive(player, "Luck3x")
		then Items.SuperLuckMult
		elseif BoostService:IsBoostActive(player, "Luck2x") then Items.LuckMult
		else 1
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
	-- Cash potions: the Mega Cash one (3x) wins over the 2x one; they don't stack.
	local now = os.time()
	if (data.Boosts.Cash3x or 0) > now then
		mult *= Items.MegaCashMult
	elseif (data.Boosts.Cash2x or 0) > now then
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
