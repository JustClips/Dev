--!strict
-- Zone gates: price labels, a ProximityPrompt to pay, and the saved unlock.
-- Gates stay solid on the server; each client turns off collision locally for the
-- zones it owns (ZoneController), so no teleporting is needed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Zones = require(Shared.Config.Zones)

local ZoneService = {}

local S: any

function ZoneService:IsUnlocked(player: Player, zoneId: string): boolean
	local data = S.DataService:GetData(player)
	return data ~= nil and data.ZonesUnlocked[zoneId] == true
end

local function priceText(zone): string
	if zone.RequiredRebirths > 0 then
		return `Rebirth {zone.RequiredRebirths} + {Format.cash(zone.UnlockCost)}`
	end
	return Format.cash(zone.UnlockCost)
end

function ZoneService:Unlock(player: Player, zoneId: string): (boolean, string)
	local zone = Zones.ById[zoneId]
	local data = S.DataService:GetData(player)
	if not zone or not data then
		return false, "Unknown zone"
	end
	if data.ZonesUnlocked[zoneId] then
		return true, "Already unlocked"
	end
	if data.Rebirths < zone.RequiredRebirths then
		return false, `Rebirth {zone.RequiredRebirths} needed for {zone.Name}`
	end
	if not S.BackpackService:TrySpend(player, zone.UnlockCost, "Zone_" .. zoneId) then
		return false, `Need {Format.cash(zone.UnlockCost)} to open {zone.Name}`
	end
	data.ZonesUnlocked[zoneId] = true
	S.AnalyticsService:Funnel(player, "FirstZone")
	S.StateService:Mark(player)
	return true, `{zone.Name} unlocked!`
end

local function setupGate(zone)
	local gate = S.WorldService:GetGate(zone.Id)
	if not gate then
		warn(`[ZoneService] no gate part for {zone.Id}`)
		return
	end
	gate:SetAttribute("ZoneId", zone.Id)
	for _, gui in gate:GetDescendants() do
		if gui:IsA("TextLabel") then
			gui.Text = `{zone.Name}\n{priceText(zone)}`
		end
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Unlock"
	prompt.ObjectText = `{zone.Name} ({priceText(zone)})`
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = gate
	prompt.Triggered:Connect(function(player)
		local ok, message = ZoneService:Unlock(player, zone.Id)
		Net.fire("Notify", player, message, if ok then "Good" else "Bad")
	end)
end

function ZoneService:Init(services)
	S = services
end

function ZoneService:Start()
	for _, zone in Zones.List do
		if zone.UnlockCost > 0 or zone.RequiredRebirths > 0 then
			setupGate(zone)
		end
	end
end

return ZoneService
