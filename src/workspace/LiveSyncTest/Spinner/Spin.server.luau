-- Spins the block. Change SpinSpeed (degrees per second) on the Spinner model in
-- init.meta.json and push: the new speed applies live.
local RunService = game:GetService("RunService")

local model = script.Parent
local block = model:WaitForChild("Block") :: BasePart

RunService.Heartbeat:Connect(function(dt)
	local speed = model:GetAttribute("SpinSpeed") or 0
	block.CFrame *= CFrame.Angles(0, math.rad(speed * dt), 0)
end)
