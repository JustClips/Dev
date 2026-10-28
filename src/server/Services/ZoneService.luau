--!strict
-- Zone gates: price labels, a ProximityPrompt to pay, and the saved unlock.
-- Gates stay solid on the server; each client turns off collision locally for the
-- zones it owns (ZoneController). Also handles the HUD teleport buttons.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local World = require(Shared.Config.World)
local Zones = require(Shared.Config.Zones)

local TELEPORT_COOLDOWN = 3

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

local lastTeleport: { [Player]: number } = {}

-- Where a teleport to `target` lands. A locked zone sends you to the first locked gate on
-- the way, so you can buy it there.
local function teleportCFrame(player: Player, target: string): (CFrame?, string?)
	if target == "Base" then
		local index = S.BaseService:GetBaseIndex(player)
		return if index then S.WorldService:GetSpawnCFrame(index) else nil, nil
	end
	if target == "Rocket" then
		return World.Teleports.Rocket, nil
	end
	local zone = Zones.ById[target]
	if not zone or not World.Teleports[target] then
		return nil, nil
	end
	if ZoneService:IsUnlocked(player, target) then
		return World.Teleports[target], nil
	end
	for _, corridor in World.Corridors do
		if not ZoneService:IsUnlocked(player, corridor.Zone) then
			local name = Zones.ById[corridor.Zone].Name
			local spot = Vector3.new(0, corridor.FromY + 5, corridor.GateZ + 12)
			return CFrame.lookAt(spot, spot - Vector3.new(0, 0, 1)), `Unlock {name} at the gate`
		end
	end
	return World.Teleports[target], nil
end

function ZoneService:Teleport(player: Player, target: string): (boolean, string?)
	if type(target) ~= "string" then
		return false, nil
	end
	local now = os.clock()
	if now - (lastTeleport[player] or 0) < TELEPORT_COOLDOWN then
		return false, "Wait a moment"
	end
	-- Eggs have to be carried home on foot (that's the risky part of the loop).
	local session = S.DataService:GetSession(player)
	if session and #(session.Runtime.Carried or {}) > 0 then
		return false, "Walk your egg home first!"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false, nil
	end
	local cframe, message = teleportCFrame(player, target)
	if not cframe then
		return false, "Can't go there"
	end
	-- Leave a vehicle first so it isn't dragged along.
	local seat = humanoid.SeatPart
	if seat then
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		humanoid.Sit = false
	end
	lastTeleport[player] = now
	character:PivotTo(cframe + Vector3.new(0, 3, 0))
	return true, message
end

function ZoneService:Init(services)
	S = services
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastTeleport[player] = nil
	end)
end

function ZoneService:Start()
	Net.onInvoke("Teleport", function(player, target)
		return ZoneService:Teleport(player, target)
	end)
	for _, zone in Zones.List do
		if zone.UnlockCost > 0 or zone.RequiredRebirths > 0 then
			setupGate(zone)
		end
	end
end

return ZoneService
