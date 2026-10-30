--!strict
-- Every player's top 3 pets follow them around (from the "Followers" player attribute
-- the server sets), drawn locally and only when nearby. They really walk: each pet heads
-- for its spot behind its owner at walking pace, turns to face where it's going, keeps its
-- feet on the ground (raycast, so it follows slopes and steps), and plays its walk cycle at
-- a speed that matches how fast it moves. Fall behind and it breaks into a run (faster,
-- with little hops) to catch up; fall far behind (a teleport, a fast car) and it pops
-- over to you. While their owner drives a car they follow on the ground behind the
-- car's back end instead of behind the driver (Dev, 2026-10-30: they ran inside the truck),
-- keeping up with it however fast it goes.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)

local SCALE = 0.8
local RENDER_DISTANCE = 150
local OFFSETS = { Vector3.new(-3.5, 0, 4), Vector3.new(3.5, 0, 4), Vector3.new(0, 0, 7) }
local FLOAT_HEIGHT = 1.5
local ARRIVE = 0.7 -- studs from its spot where a pet stops walking
local RUN_GAP = 10 -- further than this behind and it runs
local TELEPORT_GAP = 55 -- further than this and it pops over to you
local ACCEL = 45 -- studs/s² speeding up or slowing down
local TURN_RATE = 10 -- how fast it turns toward where it's walking
local ANIM_WALK_SPEED = 9 -- studs/s the walk animation looks right at (speed 1)

local FollowerController = {}

type Follower = {
	model: Model,
	floats: boolean,
	walk: AnimationTrack?,
	walking: boolean,
	pos: Vector3?, -- feet position (nil until first placed)
	yaw: number,
	speed: number,
	groundY: number,
}
type Entry = { key: string, models: { Follower } }
local entries: { [Player]: Entry } = {}
local folder: Folder

local function clear(player: Player)
	local entry = entries[player]
	if entry then
		for _, follower in entry.models do
			follower.model:Destroy()
		end
		entries[player] = nil
	end
end

local function rebuild(player: Player)
	local key = player:GetAttribute("Followers") or ""
	local entry = entries[player]
	if entry and entry.key == key then
		return
	end
	clear(player)
	local models = {}
	for spec in string.gmatch(key, "[^,]+") do
		-- "AlienId:Mutation:H" (H = Huge); empty fields are left blank.
		local fields = string.split(spec, ":")
		local id, mutation, huge = fields[1], fields[2], fields[3] == "H"
		if id and id ~= "" then
			local model = AssetLibrary.alien(id, if mutation and mutation ~= "" then mutation else nil)
			model:ScaleTo(if huge then SCALE * 1.6 else SCALE)
			if model:GetAttribute("Placeholder") then
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored = true
					end
				end
			end
			model.Parent = folder
			local meta = AssetLibrary.meta("Alien_" .. id)
			local idle = AssetLibrary.loadTrack(model, "Pet_Idle")
			if idle then
				idle:Play()
			end
			table.insert(models, {
				model = model,
				floats = meta ~= nil and meta.float == true,
				walk = AssetLibrary.loadTrack(model, "Pet_Walk"),
				walking = false,
				pos = nil,
				yaw = 0,
				speed = 0,
				groundY = 0,
			})
		end
	end
	entries[player] = { key = key, models = models }
end

local function watch(player: Player)
	rebuild(player)
	player:GetAttributeChangedSignal("Followers"):Connect(function()
		rebuild(player)
	end)
end

function FollowerController:Init()
	folder = Instance.new("Folder")
	folder.Name = "Followers"
	folder.Parent = Workspace
end

function FollowerController:Start()
	AssetLibrary.waitFor("CoreReady", 45)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(clear)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = false
	local function refreshFilter()
		local list: { Instance } = { folder }
		local leaves = Workspace:FindFirstChild("Leaves")
		if leaves then
			table.insert(list, leaves)
		end
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(list, p.Character)
			end
		end
		-- Cars too, so a pet catching up behind one never steps onto it.
		for _, car in CollectionService:GetTagged("SweepVehicle") do
			table.insert(list, car)
		end
		params.FilterDescendantsInstances = list
	end
	local filterAcc = 1

	-- The ground under a point (or the given fallback height).
	local function groundAt(x: number, z: number, near: number): number
		local hit = Workspace:Raycast(Vector3.new(x, near + 6, z), Vector3.new(0, -16, 0), params)
		return if hit then hit.Position.Y else near
	end

	local function yawToward(dir: Vector3): number
		return math.atan2(-dir.X, -dir.Z)
	end

	local function turn(from: number, to: number, k: number): number
		local d = (to - from + math.pi) % (math.pi * 2) - math.pi
		return from + d * k
	end

	-- Cars: how far back the car reaches and how wide it is, in the chassis's space,
	-- measured from its parts (the body doesn't take raycasts). Measured again now and then,
	-- in case parts streamed in late.
	type CarSize = { back: number, half: number, at: number }
	local carSizes: { [Model]: CarSize } = setmetatable({}, { __mode = "k" }) :: any
	local function carSize(vehicle: Model, chassis: BasePart, now: number): CarSize
		local cached = carSizes[vehicle]
		if cached and now - cached.at < 3 then
			return cached
		end
		local inv = chassis.CFrame:Inverse()
		local right, look = chassis.CFrame.RightVector, chassis.CFrame.LookVector
		local back, half = chassis.Size.Z / 2, chassis.Size.X / 2
		for _, part in vehicle:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 1 then
				local c = inv * part.Position
				local h = part.Size / 2
				local r = part.CFrame
				local function reach(axis: Vector3): number
					return math.abs(axis:Dot(r.XVector)) * h.X + math.abs(axis:Dot(r.YVector)) * h.Y + math.abs(axis:Dot(r.ZVector)) * h.Z
				end
				back = math.max(back, c.Z + reach(look)) -- cars face -Z, so +Z is the back
				half = math.max(half, math.abs(c.X) + reach(right))
			end
		end
		local size = { back = back, half = half, at = now }
		carSizes[vehicle] = size
		return size
	end
	-- Spots behind the car: two side by side just past the back end, one behind them.
	local function carSlot(i: number, size: CarSize): Vector3
		local side = math.min(size.half * 0.6, 2.4)
		if i == 1 then
			return Vector3.new(-side, 0, size.back + 2.5)
		elseif i == 2 then
			return Vector3.new(side, 0, size.back + 2.5)
		end
		return Vector3.new(0, 0, size.back + 2.5 + 3.5)
	end

	RunService.RenderStepped:Connect(function(dt)
		dt = math.min(dt, 1 / 20)
		filterAcc += dt
		if filterAcc > 1 then
			filterAcc = 0
			refreshFilter()
		end
		local camera = Workspace.CurrentCamera
		local focus = if camera then camera.Focus.Position else Vector3.zero
		local now = os.clock()
		local bob = math.sin(now * 3) * 0.4
		for player, entry in entries do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			for i, follower in entry.models do
				local model = follower.model
				if not root or not humanoid or (root.Position - focus).Magnitude > RENDER_DISTANCE then
					model:PivotTo(CFrame.new(0, -500, 0))
					follower.pos = nil
					continue
				end
				-- Its spot behind the owner, turned with the owner (only their heading counts),
				-- or behind their car.
				local seat = (humanoid :: Humanoid).SeatPart
				local vehicle = if seat and seat:IsA("VehicleSeat") then seat.Parent else nil
				local chassis = if vehicle and vehicle:IsA("Model") then vehicle.PrimaryPart else nil
				local heading = root.CFrame
				local feetY = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
				local slot: Vector3
				local pace = humanoid.WalkSpeed
				if vehicle and chassis then
					heading = chassis.CFrame
					local clearance = chassis:GetAttribute("Clearance")
					feetY = chassis.Position.Y - chassis.Size.Y / 2 - (if type(clearance) == "number" then clearance else 0)
					local spot = heading * carSlot(i, carSize(vehicle :: Model, chassis, now))
					slot = Vector3.new(spot.X, feetY, spot.Z)
					-- Keep up with the car.
					pace = math.max(pace, chassis.AssemblyLinearVelocity.Magnitude)
				else
					local offset = root.CFrame:VectorToWorldSpace(OFFSETS[i])
					slot = Vector3.new(root.Position.X + offset.X, feetY, root.Position.Z + offset.Z)
				end
				local pos = follower.pos
				if not pos or (Vector3.new(pos.X - slot.X, 0, pos.Z - slot.Z)).Magnitude > TELEPORT_GAP then
					-- First time, or left far behind: pop over to the spot.
					pos = slot
					follower.speed = 0
					follower.groundY = groundAt(slot.X, slot.Z, feetY)
					local look = heading.LookVector
					follower.yaw = yawToward(Vector3.new(look.X, 0, look.Z))
				end
				local p = pos :: Vector3
				local toSlot = Vector3.new(slot.X - p.X, 0, slot.Z - p.Z)
				local gap = toSlot.Magnitude
				-- How fast it wants to go: walk pace, a run when far behind, easing in at the end.
				local walkSpeed = pace
				local cap = if gap > RUN_GAP then walkSpeed * 1.7 + 8 else walkSpeed * 1.1
				local want = if gap < ARRIVE then 0 else math.min(cap, gap * 3.5)
				local change = ACCEL * dt
				follower.speed = math.clamp(want, follower.speed - change, follower.speed + change)
				local step = math.min(follower.speed * dt, gap)
				if gap > 0.001 and step > 0 then
					p += toSlot.Unit * step
					follower.yaw = turn(follower.yaw, yawToward(toSlot), math.min(1, dt * TURN_RATE))
				elseif follower.speed < 0.3 then
					-- Standing: slowly turn to face the same way as the owner.
					local look = heading.LookVector
					follower.yaw = turn(follower.yaw, yawToward(Vector3.new(look.X, 0, look.Z)), math.min(1, dt * 3))
				end
				-- Feet on the ground.
				local ground = groundAt(p.X, p.Z, math.max(feetY, follower.groundY))
				follower.groundY += (ground - follower.groundY) * math.min(1, dt * 18)
				p = Vector3.new(p.X, follower.groundY, p.Z)
				follower.pos = p
				local running = follower.speed > walkSpeed * 1.25
				local hop = if running and not follower.floats then math.abs(math.sin(now * 14 + i)) * 0.35 else 0
				local lift = if follower.floats then FLOAT_HEIGHT + bob else hop
				model:PivotTo(CFrame.new(p.X, p.Y + lift, p.Z) * CFrame.Angles(0, follower.yaw, 0))
				-- Walk cycle at the speed it actually moves.
				local walk = follower.walk
				local moving = follower.speed > 0.6
				if walk then
					if moving ~= follower.walking then
						follower.walking = moving
						if moving then
							walk:Play(0.15)
						else
							walk:Stop(0.25)
						end
					end
					if moving then
						walk:AdjustSpeed(math.clamp(follower.speed / ANIM_WALK_SPEED, 0.5, 2.6))
					end
				end
			end
		end
	end)
end

return FollowerController
