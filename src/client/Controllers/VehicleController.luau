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
local SLOPE_PULL = 0.5 -- share of gravity along the slope that speeds you up downhill
local DOWNHILL_MAX = 1.35 -- top speed downhill, relative to the car's speed

local VehicleController = {}

local player = Players.LocalPlayer
local yaw: number? = nil

-- Every car on the server: wheels roll with the car's speed, the front wheels turn into
-- corners and the brush roller spins while driving. Motor6D.Transform is local only, so each
-- client animates every car it can see.
local MAX_STEER = math.rad(28)
local ANIM_DISTANCE = 250
type Wheel = { motor: Motor6D, radius: number, steer: boolean, brush: boolean, angle: number, hub: Vector3, dy: number }
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
				hub = d.C0.Position, -- in the chassis' space
				dy = 0,
			})
		end
	end
	return wheels
end

-- Each wheel reaches for the ground on its own (Dev, 2026-10-30: front wheels floated and
-- back ones sank on ramps): a ray under the hub moves the wheel up or down within its travel.
local wheelRay = RaycastParams.new()
wheelRay.FilterType = Enum.RaycastFilterType.Exclude
wheelRay.RespectCanCollide = true
wheelRay.CollisionGroup = "Vehicles" -- skips players and cars

local function wheelDrop(chassis: BasePart, w: Wheel, dt: number)
	local cf = chassis.CFrame
	local up = cf.UpVector
	local travel = w.radius * 0.6
	local hub = cf * w.hub
	local hit = Workspace:Raycast(hub + up * travel, Vector3.new(0, -(travel * 2 + w.radius), 0), wheelRay)
	local target = -travel
	if hit then
		target = math.clamp((hit.Position.Y + w.radius - hub.Y) / math.max(up.Y, 0.5), -travel, travel)
	end
	w.dy += (target - w.dy) * math.min(1, dt * 20)
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
		wheelRay.FilterDescendantsInstances = { model }
		for _, w in c.wheels do
			if w.brush then
				w.angle = (w.angle + dt * (4 + math.abs(forward) * 0.6)) % (2 * math.pi)
				w.motor.Transform = CFrame.Angles(w.angle, 0, 0)
			else
				w.angle = (w.angle - forward / w.radius * dt) % (2 * math.pi)
				local steer = if w.steer then -c.steer else 0
				wheelDrop(chassis, w, dt)
				w.motor.Transform = CFrame.new(0, w.dy, 0) * CFrame.Angles(0, steer, 0) * CFrame.Angles(w.angle, 0, 0)
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
local smoothUp = Vector3.yAxis
local stuckTime = 0
local UNSTICK_AFTER = 0.8 -- seconds of throttle without moving
local UNSTICK_HOP = 3 -- studs up
-- Corner order matters for the slope: 1 back-left, 2 back-right, 3 front-left, 4 front-right
-- (x, z in half-sizes; -z is the front).
local CORNERS = { Vector2.new(-0.8, 0.8), Vector2.new(0.8, 0.8), Vector2.new(-0.8, -0.8), Vector2.new(0.8, -0.8) }

-- Where the suspension feels for the ground, in the chassis' space (x, z), in CORNERS
-- order: under the real wheels when the car has them, so the body tilts the way its wheels
-- sit; else near the chassis corners.
local function groundSpots(model: Model, half: Vector3): { Vector2 }
	local car = cars[model]
	local hubs = {}
	for _, w in (car and car.wheels or {}) do
		if not w.brush then
			table.insert(hubs, w.hub)
		end
	end
	local spots = {}
	if #hubs == 4 then
		for i, corner in CORNERS do
			-- The wheel on the same side and end as this corner.
			for _, hub in hubs do
				if (hub.X < 0) == (corner.X < 0) and (hub.Z < 0) == (corner.Y < 0) then
					spots[i] = Vector2.new(hub.X, hub.Z)
				end
			end
		end
		if #spots == 4 then
			return spots
		end
	end
	table.clear(spots)
	for i, corner in CORNERS do
		spots[i] = Vector2.new(half.X * corner.X, half.Z * corner.Y)
	end
	return spots
end

-- Throttle and steer. The VehicleSeat gets them from Roblox's controls, but read the raw
-- move input too (keyboard, thumbstick, gamepad) in case the seat's values don't come through.
local controls: any = nil
local function readInput(seat: VehicleSeat): (number, number)
	local throttle, steer = seat.ThrottleFloat, seat.SteerFloat
	if throttle ~= 0 or steer ~= 0 then
		return throttle, steer
	end
	if controls == nil then
		local scripts = player:FindFirstChild("PlayerScripts")
		local playerModule = scripts and scripts:FindFirstChild("PlayerModule")
		if playerModule and playerModule:IsA("ModuleScript") then
			local ok, module = pcall(function()
				return (require(playerModule) :: any):GetControls()
			end)
			controls = if ok and module then module else false
		end
	end
	if controls then
		local ok, move = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(move) == "Vector3" then
			return math.clamp(-move.Z, -1, 1), math.clamp(move.X, -1, 1)
		end
	end
	return 0, 0
end

local function drive(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not seat or not seat:IsA("VehicleSeat") or seat:GetAttribute("OwnerUserId") ~= player.UserId then
		yaw = nil
		lean = 0
		smoothUp = Vector3.yAxis
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
	local throttleIn, steerIn = readInput(seat)

	-- Suspension: a ray down at each corner. Walls and steep faces don't count as ground.
	rayParams.FilterDescendantsInstances = { model, character :: Model }
	local reach = half.Y + clearance + STEP_REACH
	local points: { [number]: Vector3 } = {}
	local groundY, normalSum, hits = 0, Vector3.zero, 0
	for i, spot in groundSpots(model, half) do
		local origin = (cf * CFrame.new(spot.X, 0, spot.Y)).Position
		local hit = Workspace:Raycast(origin, Vector3.new(0, -reach, 0), rayParams)
		if hit and hit.Normal.Y > 0.55 then
			points[i] = hit.Position
			groundY += hit.Position.Y
			normalSum += hit.Normal
			hits += 1
		end
	end
	local grounded = hits >= 2

	-- The ground's slope: from the four contact points (smooth over seams between parts),
	-- else the average surface normal; eased so the body tilts smoothly.
	local ground = Vector3.yAxis
	if hits == 4 then
		local n = (points[2] - points[3]):Cross(points[1] - points[4])
		if n.Magnitude > 1e-3 then
			n = n.Unit
			ground = if n.Y < 0 then -n else n
		end
	elseif grounded then
		ground = (normalSum / hits).Unit
	end
	local tilt = math.acos(math.clamp(ground.Y, -1, 1))
	if tilt > MAX_TILT then
		ground = Vector3.yAxis:Lerp(ground, MAX_TILT / tilt).Unit
	end
	smoothUp = smoothUp:Lerp(if grounded then ground else Vector3.yAxis, math.min(1, dt * (if grounded then 16 else 2))).Unit

	-- Steering: only while rolling (reversing turns the other way), a bit less at top speed.
	local velocity = chassis.AssemblyLinearVelocity
	local heading = CFrame.Angles(0, yaw :: number, 0)
	local forward = velocity:Dot(heading.LookVector)
	local speedFrac = math.clamp(math.abs(forward) / maxSpeed, 0, 1)
	local steerScale = math.clamp(math.abs(forward) / (maxSpeed * 0.2), 0, 1) * (1 - 0.3 * speedFrac)
	local direction = if forward < -0.5 then -1 else 1
	yaw = (yaw :: number) - steerIn * TURN_RATE * steerScale * direction * dt
	heading = CFrame.Angles(0, yaw :: number, 0)
	-- Forward and right along the ground, so the car drives down (and up) the slope itself
	-- instead of sliding flat and dropping in steps.
	local right = heading.LookVector:Cross(smoothUp).Unit
	local look = smoothUp:Cross(right).Unit

	if grounded then
		forward = velocity:Dot(look)
		local side = velocity:Dot(right)
		-- Throttle, brakes and coasting.
		local accel = maxSpeed / ACCEL_TIME
		if throttleIn ~= 0 then
			local target = throttleIn * maxSpeed * (if throttleIn > 0 then 1 else REVERSE)
			local rate = if forward * throttleIn < 0 then accel * BRAKE else accel
			forward = moveToward(forward, target, rate * dt)
		else
			forward = moveToward(forward, 0, accel * COAST * dt)
		end
		-- Gravity along the slope rolls you downhill. Uphill only when you let go: with
		-- throttle the engine wins (Dev, 2026-10-30: the truck couldn't climb a ramp).
		if look.Y < 0 or throttleIn == 0 then
			forward -= Workspace.Gravity * SLOPE_PULL * look.Y * dt
		end
		forward = math.clamp(forward, -maxSpeed * DOWNHILL_MAX, maxSpeed * DOWNHILL_MAX)
		side *= math.exp(-GRIP * dt)
		-- Ride height: a small spring correction on top of following the slope.
		local target = groundY / hits + clearance + half.Y
		local lift = math.clamp((target - cf.Position.Y) * SPRING, -MAX_LIFT, MAX_LIFT)
		chassis.AssemblyLinearVelocity = look * forward + right * side + Vector3.new(0, lift, 0)
	end
	-- Airborne: the engine's gravity and momentum carry the car; only the heading changes.

	-- Never stuck (Dev, 2026-10-30): pressing throttle but not moving for a moment (caught
	-- on an edge, wedged on a slope) hops the car up and a little ahead.
	local moving = math.abs(velocity:Dot(heading.LookVector))
	if math.abs(throttleIn) > 0.5 and moving < 3 then
		stuckTime += dt
	else
		stuckTime = 0
	end
	if stuckTime > UNSTICK_AFTER then
		stuckTime = 0
		local flat = heading.LookVector * math.sign(throttleIn)
		chassis.CFrame = CFrame.new(Vector3.new(0, UNSTICK_HOP, 0) + flat * 2) * chassis.CFrame
		chassis.AssemblyLinearVelocity = flat * maxSpeed * 0.3
	end

	-- Body: follows the ground's slope and leans out of corners.
	local targetLean = if grounded then steerIn * direction * speedFrac * LEAN else 0
	lean += (targetLean - lean) * math.min(1, dt * 6)
	align.CFrame = CFrame.fromMatrix(Vector3.zero, right, smoothUp, -look) * CFrame.Angles(0, 0, lean)
end

function VehicleController:Start()
	RunService.RenderStepped:Connect(animateCars)
	RunService.Heartbeat:Connect(drive)
end

return VehicleController
