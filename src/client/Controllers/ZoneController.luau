--!strict
-- Makes gates passable for zones this player unlocked. The gate stays solid on the server;
-- turning off collision locally works because each client simulates its own character
-- (and the vehicle it drives).
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Zones = require(ReplicatedStorage:WaitForChild("Shared").Config.Zones)

local ZoneController = {}
local C: any

local gates: Instance

-- Zones open at the last apply (nil until the first one, so joining doesn't celebrate).
local wasOpen: { [string]: boolean }? = nil
local revealing: { [string]: boolean } = {}

-- The moment a zone opens (2026-11-07: under 30% of new players ever opened the Park):
-- the gate fades and sinks, then the big celebration names what's new there.
local function reveal(gate: BasePart, zoneId: string)
	local zone = Zones.ById[zoneId]
	if not zone then
		return
	end
	local from = gate.CFrame
	revealing[zoneId] = true
	gate.Transparency = 0.35
	local sink = TweenService:Create(gate, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = from - Vector3.new(0, gate.Size.Y, 0),
		Transparency = 1,
	})
	sink.Completed:Connect(function()
		gate.CFrame = from
		gate.Transparency = 0.85
		revealing[zoneId] = nil
	end)
	sink:Play()
	Ui.sound("Reveal")
	local eggs = if zone.MaxRarity then ` + {zone.MaxRarity} eggs` else ""
	C.PurchaseController:Celebrate("Zone:" .. zoneId, { Title = "NEW AREA!", Sub = `{zone.CashMult}x cash{eggs}! Walk in for a free egg!` })
end

local function apply(data)
	local first = wasOpen == nil
	local seen = wasOpen or {}
	for _, gate in gates:GetChildren() do
		if not gate:IsA("BasePart") then
			continue
		end
		local zoneId = string.match(gate.Name, "^Gate_(.+)$")
		local open = zoneId ~= nil and data.ZonesUnlocked[zoneId] == true
		gate.CanCollide = not open
		if zoneId and open and not first and not seen[zoneId] then
			reveal(gate, zoneId)
		elseif not (zoneId and revealing[zoneId]) then
			gate.Transparency = if open then 0.85 else 0.35
		end
		if zoneId then
			seen[zoneId] = open
		end
		local prompt = gate:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = not open
		end
		for _, gui in gate:GetChildren() do
			if gui:IsA("SurfaceGui") then
				gui.Enabled = not open
			end
		end
	end
	wasOpen = seen
end

function ZoneController:Init(controllers)
	C = controllers
end

function ZoneController:Start()
	gates = Workspace:WaitForChild("Moon"):WaitForChild("Gates")
	State.observe(apply)
	-- The prompt is created by the server after boot; re-apply when it shows up.
	gates.DescendantAdded:Connect(function()
		if State.data then
			apply(State.data)
		end
	end)
end

return ZoneController
