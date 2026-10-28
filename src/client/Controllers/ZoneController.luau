--!strict
-- Makes gates passable for zones this player unlocked. The gate stays solid on the server;
-- turning off collision locally works because each client simulates its own character
-- (and the vehicle it drives).
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local State = require(Client.State)

local ZoneController = {}

local gates: Instance

local function apply(data)
	for _, gate in gates:GetChildren() do
		if not gate:IsA("BasePart") then
			continue
		end
		local zoneId = string.match(gate.Name, "^Gate_(.+)$")
		local open = zoneId ~= nil and data.ZonesUnlocked[zoneId] == true
		gate.CanCollide = not open
		gate.Transparency = if open then 0.85 else 0.35
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
