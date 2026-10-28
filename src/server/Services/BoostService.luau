--!strict
-- Server luck (2x/4x/8x/16x) and personal boosts, plus the one place that computes a
-- player's cash multiplier. Luck timers stack additively per tier; the highest active
-- tier is the server's luck.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Rewards = require(Shared.Config.Rewards)

local LUCK_TIERS = { 2, 4, 8, 16 }

local BoostService = {}

local S: any
local luckEnds: { [number]: number } = {}

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
	return best * (if event then event.LuckMult else 1)
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

-- Luck potion (personal). Multiplies egg rarity luck, mutations and Huge chance.
function BoostService:GetPersonalLuck(player: Player): number
	return if BoostService:IsBoostActive(player, "Luck2x") then Items.LuckMult else 1
end

-- Speed potion: extra walk speed while active.
function BoostService:GetSpeedBonus(player: Player): number
	return if BoostService:IsBoostActive(player, "Speed") then Items.SpeedBonus else 0
end

function BoostService:HasPass(player: Player, key: string): boolean
	local data = S.DataService:GetData(player)
	return data ~= nil and data.Gamepasses[key] == true
end

-- rebirths x 2x pass x VIP x timed 2x
function BoostService:GetCashMultiplier(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return 1
	end
	local mult = 1 + data.Rebirths * Economy.RebirthCashBonus
	if data.Gamepasses.Cash2x then
		mult *= Economy.Cash2xPassMult
	end
	if data.Gamepasses.VIP then
		mult *= 1 + Economy.VIPCashBonus
	end
	if (data.Boosts.Cash2x or 0) > os.time() then
		mult *= Economy.Cash2xBoostMult
	end
	return mult
end

-- Same as above without temporary boosts (used for offline income).
function BoostService:GetBaseCashMultiplier(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return 1
	end
	local mult = 1 + data.Rebirths * Economy.RebirthCashBonus
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
