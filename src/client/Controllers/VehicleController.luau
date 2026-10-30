--!strict
-- Drives your own car. The server gives this client network ownership; we read the
-- VehicleSeat's throttle/steer (keyboard, gamepad and the mobile thumbstick all feed it).
-- Arcade physics (Dev, 2026-10-30: "proper physics"): the chassis box rides on four ray
-- springs a little above the ground, so it never snags on floor seams and climbs small
-- steps; it speeds up and brakes over time, only turns while rolling, grips with a little
-- slide, follows slopes (the body tilts with the ground) and leans out of corners.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TURN_RATE = math.rad(100) -- at full steer and speed
local ACCEL_TIME = 1.6 -- seconds from standstill to top speed
local BRAKE = 3 -- braking (throttle against the motion) is this much stronger
local COAST = 0.6 -- rolling to a stop with no throttle, relative to accelerating
local REVERSE = 0.5 -- reverse top speed, relative to forward
local GRIP = 9 -- how fast sideways sliding dies out (per second)
local SPRING = 12 -- how fast the body settles to ride height (per second)
local MAX_LIFT = 40 -- studs per second the springs may move the body up or down
local STEP_REACH = 2.5 -- the springs feel this far under the wheels (then you're airborne)
local LEAN = math.rad(5) -- body roll out of a full-speed corner
local MAX_TILT = math.rad(35) -- steeper ground than this doesn't tilt the body further

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

local function moveToward(value: number, target: number, step: number): number
	if value < target then
		return math.min(value + step, target)
	end
	return math.max(value - step, target)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
rayParams.CollisionGroup = "Vehicles" -- skips players and other cars like the car itself does

local lean = 0

local function drive(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not seat or not seat:IsA("VehicleSeat") or seat:GetAttribute("OwnerUserId") ~= player.UserId then
		yaw = nil
		lean = 0
		return
	end
	local model = seat.Parent :: Model
	local chassis = model.PrimaryPart
	local align = chassis and chassis:FindFirstChild("Upright") :: AlignOrientation?
	if not chassis or not align then
		return
	end
	dt = math.min(dt, 0.05)
	local cf = chassis.CFrame
	if yaw == nil then
		local look = cf.LookVector
		yaw = math.atan2(-look.X, -look.Z)
	end
	local clearance = (chassis:GetAttribute("Clearance") :: number?) or 0.8
	local half = chassis.Size / 2
	local maxSpeed = (seat:GetAttribute("Speed") :: number?) or 40

	-- Suspension: a ray down at each corner.
	rayParams.FilterDescendantsInstances = { model, character :: Model }
	local reach = half.Y + clearance + STEP_REACH
	local groundY, normal, hits = 0, Vector3.zero, 0
	for _, x in { -0.8, 0.8 } do
		for _, z in { -0.8, 0.8 } do
			local origin = (cf * CFrame.new(half.X * x, 0, half.Z * z)).Position
			local hit = Workspace:Raycast(origin, Vector3.new(0, -reach, 0), rayParams)
			if hit then
				groundY += hit.Position.Y
				normal += hit.Normal
				hits += 1
			end
		end
	end
	local grounded = hits >= 2

	-- Steering: only while rolling (reversing turns the other way), a bit less at top speed.
	local velocity = chassis.AssemblyLinearVelocity
	local heading = CFrame.Angles(0, yaw :: number, 0)
	local forward = velocity:Dot(heading.LookVector)
	local speedFrac = math.clamp(math.abs(forward) / maxSpeed, 0, 1)
	local steerScale = math.clamp(math.abs(forward) / (maxSpeed * 0.2), 0, 1) * (1 - 0.3 * speedFrac)
	local direction = if forward < -0.5 then -1 else 1
	yaw = (yaw :: number) - seat.SteerFloat * TURN_RATE * steerScale * direction * dt
	heading = CFrame.Angles(0, yaw :: number, 0)
	local look = heading.LookVector
	local right = heading.RightVector
	forward = velocity:Dot(look)
	local side = velocity:Dot(right)

	-- Throttle, brakes and coasting (only with wheels on the ground).
	if grounded then
		local throttle = seat.ThrottleFloat
		local accel = maxSpeed / ACCEL_TIME
		if throttle ~= 0 then
			local target = throttle * maxSpeed * (if throttle > 0 then 1 else REVERSE)
			local rate = if forward * throttle < 0 then accel * BRAKE else accel
			forward = moveToward(forward, target, rate * dt)
		else
			forward = moveToward(forward, 0, accel * COAST * dt)
		end
		side *= math.exp(-GRIP * dt)
	end

	-- Ride height: springs pull the body to `clearance` over the ground; airborne, gravity.
	local vy = velocity.Y
	if grounded then
		local target = groundY / hits + clearance + half.Y
		vy = math.clamp((target - cf.Position.Y) * SPRING, -MAX_LIFT, MAX_LIFT)
	end
	chassis.AssemblyLinearVelocity = look * forward + right * side + Vector3.new(0, vy, 0)

	-- Body: follows the ground's slope and leans out of corners.
	local up = Vector3.yAxis
	if grounded then
		local n = (normal / hits).Unit
		local tilt = math.acos(math.clamp(n.Y, -1, 1))
		up = if tilt > MAX_TILT then Vector3.yAxis:Lerp(n, MAX_TILT / tilt).Unit else n
	end
	local targetLean = if grounded then seat.SteerFloat * direction * speedFrac * LEAN else 0
	lean += (targetLean - lean) * math.min(1, dt * 6)
	local r = look:Cross(up).Unit
	local f = up:Cross(r).Unit
	align.CFrame = CFrame.fromMatrix(Vector3.zero, r, up, -f) * CFrame.Angles(0, 0, lean)
end

function VehicleController:Start()
	RunService.RenderStepped:Connect(animateCars)
	RunService.Heartbeat:Connect(drive)
end

return VehicleController
