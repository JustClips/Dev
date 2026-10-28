--!strict
-- Drives your own vehicle (tiers 7-9). The server gives this client network ownership;
-- we read the VehicleSeat's throttle/steer (keyboard, gamepad and the mobile thumbstick all
-- feed it) and set velocity + heading directly. Simple and stable for a placeholder.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local TURN_RATE = math.rad(110) -- degrees per second at full steer
local ACCELERATION = 4

local VehicleController = {}

local player = Players.LocalPlayer
local yaw: number? = nil

function VehicleController:Start()
	RunService.RenderStepped:Connect(function(dt)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local seat = humanoid and humanoid.SeatPart
		if not seat or not seat:IsA("VehicleSeat") or seat:GetAttribute("OwnerUserId") ~= player.UserId then
			yaw = nil
			return
		end
		local model = seat.Parent :: Model
		local chassis = model.PrimaryPart
		local align = chassis and chassis:FindFirstChild("Upright") :: AlignOrientation?
		if not chassis or not align then
			return
		end
		if yaw == nil then
			local look = chassis.CFrame.LookVector
			yaw = math.atan2(-look.X, -look.Z)
		end
		local currentYaw = (yaw :: number) - seat.SteerFloat * TURN_RATE * dt
		yaw = currentYaw
		local heading = CFrame.Angles(0, currentYaw, 0)
		align.CFrame = heading

		local speed = seat:GetAttribute("Speed") or 30
		local target = heading.LookVector * seat.ThrottleFloat * speed
		local velocity = chassis.AssemblyLinearVelocity
		local horizontal = Vector3.new(velocity.X, 0, velocity.Z):Lerp(target, math.min(1, dt * ACCELERATION))
		chassis.AssemblyLinearVelocity = Vector3.new(horizontal.X, velocity.Y, horizontal.Z)
	end)
end

return VehicleController
