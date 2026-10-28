--!strict
-- The view from the Moon: a big, slowly turning Earth hanging in the sky (Blender model,
-- built locally so it costs the server nothing).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local World = require(Shared.Config.World)

local SPIN = math.rad(1.5) -- degrees per second

local SkyController = {}

function SkyController:Start()
	if not AssetLibrary.waitReady(60) then
		return
	end
	local earth = AssetLibrary.get("Earth")
	if not earth then
		return
	end
	earth.Name = "Earth"
	for _, d in earth:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CastShadow = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	earth:ScaleTo(World.EarthScale)
	local tilt = CFrame.Angles(math.rad(18), 0, math.rad(-12))
	local yaw = 0
	earth:PivotTo(CFrame.new(World.EarthPosition) * tilt)
	earth.Parent = Workspace
	RunService.Heartbeat:Connect(function(dt)
		yaw += dt * SPIN
		earth:PivotTo(CFrame.new(World.EarthPosition) * tilt * CFrame.Angles(0, yaw, 0))
	end)
end

return SkyController
