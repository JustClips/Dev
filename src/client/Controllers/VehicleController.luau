--!strict
-- Drives your own vehicle (tiers 7-9). The server gives this client network ownership;
-- we read the VehicleSeat's throttle/steer (keyboard, gamepad and the mobile thumbstick all
-- feed it) and set velocity + heading directly. Simple and stable for a placeholder.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TURN_RATE = math.rad(110) -- degrees per second at full steer
local ACCELERATION = 4

local VehicleController = {}

local player = Players.LocalPlayer
local yaw: number? = nil

-- Every car on the server: wheels roll with the car's speed, the front wheels turn into
-- corners and the brush roller spins while driving. Motor6D.Transform is local only, so each
-- client animates every car it can see.
local MAX_STEER = math.rad(28)
local ANIM_DISTANCE = 250
type Wheel = { motor: Motor6D, radius: number, steer: boolean, brush: boolean, angle: number }
local cars: { [Model]: { wheels: { Wheel }, steer: number } } = {}

local function collect(model: Model)
	local wheels = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Name == "Spin" then
			table.insert(wheels, {
				motor = d,
				radius = (d:GetAttribute("Radius") :: number?) or 1,
				steer = d:GetAttribute("Steer") == true,
				brush = d:GetAttribute("Brush") == true,
				angle = 0,
			})
		end
	end
	return wheels
end

local function animateCars(dt: number)
	local camera = Workspace.CurrentCamera
	for _, model in CollectionService:GetTagged("SweepVehicle") do
		if not model:IsA("Model") or not model.Parent then
			continue
		end
		local chassis = model.PrimaryPart
		if not chassis then
			continue
		end
		if camera and (chassis.Position - camera.CFrame.Position).Magnitude > ANIM_DISTANCE then
			continue
		end
		local car = cars[model]
		if not car or #car.wheels == 0 then
			car = { wheels = collect(model), steer = 0 }
			cars[model] = car
		end
		local look = chassis.CFrame.LookVector
		local forward = chassis.AssemblyLinearVelocity:Dot(look)
		local seat = model:FindFirstChild("Seat")
		-- The driver's steer input when we can read it, else how fast the car is turning.
		local steerInput = if seat and seat:IsA("VehicleSeat") and seat.Occupant then seat.SteerFloat else 0
		if steerInput == 0 then
			steerInput = math.clamp(-chassis.AssemblyAngularVelocity.Y * 0.8, -1, 1)
		end
		local c = car :: { wheels: { Wheel }, steer: number }
		c.steer += (steerInput * MAX_STEER - c.steer) * math.min(1, dt * 10)
		for _, w in c.wheels do
			if w.brush then
				w.angle = (w.angle + dt * (4 + math.abs(forward) * 0.6)) % (2 * math.pi)
				w.motor.Transform = CFrame.Angles(w.angle, 0, 0)
			else
				w.angle = (w.angle - forward / w.radius * dt) % (2 * math.pi)
				local steer = if w.steer then -c.steer else 0
				w.motor.Transform = CFrame.Angles(0, steer, 0) * CFrame.Angles(w.angle, 0, 0)
			end
		end
	end
	for model in cars do
		if not model.Parent then
			cars[model] = nil
		end
	end
end

function VehicleController:Start()
	RunService.RenderStepped:Connect(animateCars)
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
