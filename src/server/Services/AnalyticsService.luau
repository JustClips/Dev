--!strict
-- Thin wrapper around Roblox AnalyticsService: onboarding funnel, economy and custom events.
-- Every call is pcall'd so analytics can never break gameplay.
local RobloxAnalytics = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)

local FUNNEL = { "Spawn", "FirstSweep", "FirstSell", "FirstEgg", "FirstHatch", "FirstTool", "FirstZone", "FirstRebirth" }
local FUNNEL_INDEX: { [string]: number } = {}
for i, name in FUNNEL do
	FUNNEL_INDEX[name] = i
end

local CURRENCY = "Cash"

local AnalyticsService = {}

local S: any
local incomeBuffer: { [Player]: number } = {}

local function balance(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return 0
	end
	return math.min(BigNum.toNumber(data.Cash), 1e300)
end

local function try(fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn("[Analytics] " .. tostring(err))
	end
end

-- Logs each funnel step once per player (stored in the profile).
function AnalyticsService:Funnel(player: Player, step: string)
	local data = S.DataService:GetData(player)
	local index = FUNNEL_INDEX[step]
	if not data or not index or data.Flags.Funnel[step] then
		return
	end
	data.Flags.Funnel[step] = true
	try(function()
		RobloxAnalytics:LogOnboardingFunnelStepEvent(player, index, step)
	end)
end

function AnalyticsService:Source(player: Player, amount: number, transactionType: Enum.AnalyticsEconomyTransactionType, sku: string?)
	if amount <= 0 then
		return
	end
	try(function()
		RobloxAnalytics:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Source, CURRENCY, math.min(amount, 1e300), balance(player), transactionType.Name, sku)
	end)
end

function AnalyticsService:Sink(player: Player, amount: number, transactionType: Enum.AnalyticsEconomyTransactionType, sku: string?)
	if amount <= 0 then
		return
	end
	try(function()
		RobloxAnalytics:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Sink, CURRENCY, math.min(amount, 1e300), balance(player), transactionType.Name, sku)
	end)
end

-- Alien income ticks every second; batch it into one event per minute.
function AnalyticsService:Income(player: Player, amount: number)
	incomeBuffer[player] = (incomeBuffer[player] or 0) + amount
end

function AnalyticsService:Custom(player: Player, eventName: string, value: number?, fields: { [string]: string }?)
	try(function()
		local customFields = nil
		if fields then
			-- Roblox accepts up to three custom fields using these keys.
			customFields = {}
			local keys = { Enum.AnalyticsCustomFieldKeys.CustomField01.Name, Enum.AnalyticsCustomFieldKeys.CustomField02.Name, Enum.AnalyticsCustomFieldKeys.CustomField03.Name }
			local i = 1
			for k, v in fields do
				if i > 3 then
					break
				end
				customFields[keys[i]] = `{k}:{v}`
				i += 1
			end
		end
		RobloxAnalytics:LogCustomEvent(player, eventName, value or 1, customFields)
	end)
end

function AnalyticsService:Init(services)
	S = services
	S.DataService.ProfileLoaded:Connect(function(player)
		AnalyticsService:Funnel(player, "Spawn")
	end)
	S.DataService.ProfileReleasing:Connect(function(player)
		local pending = incomeBuffer[player]
		incomeBuffer[player] = nil
		if pending then
			AnalyticsService:Source(player, pending, Enum.AnalyticsEconomyTransactionType.Gameplay, "AlienIncome")
		end
	end)
end

function AnalyticsService:Start()
	task.spawn(function()
		while true do
			task.wait(60)
			for player, amount in incomeBuffer do
				incomeBuffer[player] = nil
				AnalyticsService:Source(player, amount, Enum.AnalyticsEconomyTransactionType.Gameplay, "AlienIncome")
			end
		end
	end)
end

return AnalyticsService
