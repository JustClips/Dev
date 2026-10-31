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
--
-- Pet combat (CombatService): when their owner has a CombatTarget, awake pets run to a spot
-- around that enemy, face it and play their attack move on every hit (shared/Combat
-- styles: Pounce, Bite, Charge, Dive). Each pet shows a small health
-- bar during fights; a knocked-out pet lies on its side where it fell with a "Zzz"
-- countdown until it wakes up (PetSleep), then runs back.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Combat = require(Shared.Combat)

local FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
local INK = Color3.fromRGB(16, 18, 28)
local FIGHT_ANGLES = { math.rad(-60), math.rad(60), 0 } -- around the enemy, from the owner's side

-- An attack move at time t (0-1): how far forward and up the pet is, and its nose tilt
-- (radians, + = nose up). Forward is toward the enemy.
local function attackPose(style: string, t: number): (number, number, number)
	local function ease(x: number): number
		return 1 - (1 - x) * (1 - x)
	end
	if style == "Bite" then
		-- Two quick nips.
		local k = math.abs(math.sin(t * math.pi * 2))
		return k * 1.1, k * 0.15, -0.3 * k
	elseif style == "Charge" then
		-- Back up, ram forward head down, walk back.
		if t < 0.35 then
			local k = ease(t / 0.35)
			return -1.2 * k, 0, 0.12 * k
		elseif t < 0.65 then
			local k = (t - 0.35) / 0.3
			return -1.2 + 3.8 * k * k, math.sin(k * math.pi) * 0.25, 0.12 - 0.42 * k
		end
		local k = ease((t - 0.65) / 0.35)
		return 2.6 * (1 - k), 0, -0.3 * (1 - k)
	elseif style == "Dive" then
		-- Rise up, then sting-dive nose first into the enemy, and float back.
		if t < 0.4 then
			local k = ease(t / 0.4)
			return -0.8 * k, 2.2 * k, 0.5 * k
		elseif t < 0.63 then
			local k = (t - 0.4) / 0.23
			return -0.8 + 3.2 * k, 2.2 * (1 - k) - 0.6 * k, 0.5 - 1.4 * k
		end
		local k = ease((t - 0.63) / 0.37)
		return 2.4 * (1 - k), -0.6 * (1 - k), -0.9 * (1 - k)
	end
	-- Pounce: crouch back, hop forward and slam down, then step back.
	if t < 0.3 then
		local k = ease(t / 0.3)
		return -0.35 * k, 0, 0.18 * k
	elseif t < 0.62 then
		local k = (t - 0.3) / 0.32
		return -0.35 + 2.15 * k, math.sin(k * math.pi) * 1.3, 0.25 - 0.7 * k
	end
	local k = ease((t - 0.62) / 0.38)
	return 1.8 * (1 - k), 0, -0.45 * (1 - k)
end

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
	size: Vector3, -- extents after scaling (to lie down on its side)
	attack: Combat.PetAttack,
	style: Combat.AttackStyle,
	attackAt: number, -- os.clock() its current attack move started (0 = none)
	lungeAt: Vector3?,
	hp: number, -- 0-1
	wakeAt: number, -- server time; 0 = awake
	gui: BillboardGui?,
	fill: Frame?,
	back: Frame?,
	zzz: TextLabel?,
}
type Entry = { key: string, models: { Follower }, hpKey: string?, sleepKey: string? }
local entries: { [Player]: Entry } = {}
local folder: Folder
local controllers: any

-- Small health bar + sleep label over a pet (made the first time it's needed).
local function ensureGui(follower: Follower)
	if follower.gui then
		return
	end
	local model = follower.model
	local gui = Instance.new("BillboardGui")
	gui.Name = "PetCombat"
	gui.Size = UDim2.fromOffset(54, 26)
	gui.StudsOffsetWorldSpace = Vector3.new(0, follower.size.Y + 0.8, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.Adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	gui.Enabled = false
	local back = Instance.new("Frame")
	back.BackgroundColor3 = Color3.fromRGB(30, 34, 44)
	back.BorderSizePixel = 0
	back.AnchorPoint = Vector2.new(0.5, 1)
	back.Position = UDim2.fromScale(0.5, 1)
	back.Size = UDim2.new(1, 0, 0, 7)
	back.Parent = gui
	local edge = Instance.new("UIStroke")
	edge.Color = INK
	edge.Thickness = 1.5
	edge.LineJoinMode = Enum.LineJoinMode.Miter
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = back
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Color3.fromRGB(92, 214, 92)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = back
	local zzz = Instance.new("TextLabel")
	zzz.BackgroundTransparency = 1
	zzz.Size = UDim2.fromScale(1, 1)
	zzz.FontFace = FONT
	zzz.TextSize = 16
	zzz.TextColor3 = Color3.fromRGB(170, 200, 255)
	zzz.Visible = false
	zzz.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 2
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.Parent = zzz
	gui.Parent = model
	follower.gui, follower.fill, follower.back, follower.zzz = gui, fill, back, zzz
end

-- Reads PetHp / PetSleep ("a,b,c") into the followers when they change.
local function readCombat(player: Player, entry: Entry)
	local hpKey = player:GetAttribute("PetHp")
	if hpKey ~= entry.hpKey then
		entry.hpKey = hpKey
		local parts = if type(hpKey) == "string" then string.split(hpKey, ",") else {}
		for i, follower in entry.models do
			follower.hp = tonumber(parts[i]) or 1
		end
	end
	local sleepKey = player:GetAttribute("PetSleep")
	if sleepKey ~= entry.sleepKey then
		entry.sleepKey = sleepKey
		local parts = if type(sleepKey) == "string" then string.split(sleepKey, ",") else {}
		for i, follower in entry.models do
			follower.wakeAt = tonumber(parts[i]) or 0
		end
	end
end

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
				size = model:GetExtentsSize(),
				attack = Combat.petAttack(id),
				style = Combat.Styles[Combat.petAttack(id).Style] or Combat.Styles.Pounce,
				attackAt = 0,
				lungeAt = nil,
				hp = 1,
				wakeAt = 0,
				gui = nil,
				fill = nil,
				back = nil,
				zzz = nil,
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

-- Where a player's pet in follower slot `slot` is drawn (damage numbers), if it is.
function FollowerController:PetPosition(userId: number, slot: number): Vector3?
	local player = Players:GetPlayerByUserId(userId)
	local entry = player and entries[player]
	local follower = entry and entry.models[slot]
	return follower and follower.pos
end

-- A pet hits an enemy: it plays its attack move. Returns how long until the move lands
-- (so the damage number shows on impact).
function FollowerController:Lunge(userId: number, slot: number, at: Vector3): number
	local player = Players:GetPlayerByUserId(userId)
	local entry = player and entries[player]
	local follower = entry and entry.models[slot]
	if follower and follower.pos then
		follower.attackAt = os.clock()
		follower.lungeAt = at
		return follower.style.Impact
	end
	return 0
end

function FollowerController:Init(all)
	controllers = all
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
			readCombat(player, entry)
			local serverNow = Workspace:GetServerTimeNow()
			-- The enemy this player's pets are fighting (drawn by EnemyController), if any.
			local targetName = player:GetAttribute("CombatTarget")
			local enemyAt: Vector3? = nil
			local enemyRadius = 2
			if root and type(targetName) == "string" and targetName ~= "" then
				enemyAt = controllers.EnemyController:Position(targetName)
				local def = controllers.EnemyController:Def(targetName)
				enemyRadius = if def then def.Radius else 2
				if enemyAt and (enemyAt - root.Position).Magnitude > Combat.LeashRange + 10 then
					enemyAt = nil
				end
			end
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
				local asleep = follower.wakeAt > serverNow
				-- Knocked out: lies on its side where it fell, with a Zzz countdown.
				local lying = follower.pos
				if asleep and lying and Vector3.new(lying.X - slot.X, 0, lying.Z - slot.Z).Magnitude <= TELEPORT_GAP then
					local w, h = follower.size.X, follower.size.Y
					model:PivotTo(
						CFrame.new(lying) * CFrame.Angles(0, follower.yaw, 0) * CFrame.new(0, w / 2, 0) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.new(0, -h / 2, 0)
					)
					follower.speed = 0
					follower.attackAt = 0
					if follower.walk and follower.walking then
						follower.walking = false
						follower.walk:Stop(0.1)
					end
					ensureGui(follower)
					local gui = follower.gui :: BillboardGui
					gui.Enabled = true
					gui.StudsOffsetWorldSpace = Vector3.new(0, w / 2 + 1.4, 0);
					(follower.back :: Frame).Visible = false
					local zzz = follower.zzz :: TextLabel
					zzz.Visible = true
					zzz.Text = "Zzz " .. math.max(1, math.ceil(follower.wakeAt - serverNow))
					continue
				end
				-- Fighting: run to a spot around the enemy (spread out from the owner's side).
				local fighting = false
				if enemyAt and not asleep and not vehicle then
					local away = Vector3.new(root.Position.X - enemyAt.X, 0, root.Position.Z - enemyAt.Z)
					if away.Magnitude < 0.1 then
						away = -Vector3.new(heading.LookVector.X, 0, heading.LookVector.Z)
					end
					local dir = CFrame.Angles(0, FIGHT_ANGLES[i] or 0, 0):VectorToWorldSpace(away.Unit)
					local reach = enemyRadius + 1.2 + follower.size.Z * 0.4
					slot = Vector3.new(enemyAt.X + dir.X * reach, feetY, enemyAt.Z + dir.Z * reach)
					pace = math.max(pace, 24)
					fighting = true
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
					if fighting and enemyAt then
						-- In a fight: face the enemy.
						local at = enemyAt :: Vector3
						follower.yaw = turn(follower.yaw, yawToward(Vector3.new(at.X - p.X, 0, at.Z - p.Z)), math.min(1, dt * 10))
					else
						-- Standing: slowly turn to face the same way as the owner.
						local look = heading.LookVector
						follower.yaw = turn(follower.yaw, yawToward(Vector3.new(look.X, 0, look.Z)), math.min(1, dt * 3))
					end
				end
				-- Feet on the ground.
				local ground = groundAt(p.X, p.Z, math.max(feetY, follower.groundY))
				follower.groundY += (ground - follower.groundY) * math.min(1, dt * 18)
				p = Vector3.new(p.X, follower.groundY, p.Z)
				follower.pos = p
				local running = follower.speed > walkSpeed * 1.25
				local hop = if running and not follower.floats then math.abs(math.sin(now * 14 + i)) * 0.35 else 0
				local lift = if follower.floats then FLOAT_HEIGHT + bob else hop
				-- Attack move (its style from shared/Combat), facing the enemy.
				local pose = CFrame.Angles(0, follower.yaw, 0)
				if follower.attackAt > 0 then
					local t = (now - follower.attackAt) / follower.style.Duration
					if t >= 1 then
						follower.attackAt = 0
					else
						local at = follower.lungeAt
						if at then
							local toward = Vector3.new(at.X - p.X, 0, at.Z - p.Z)
							if toward.Magnitude > 0.01 then
								follower.yaw = turn(follower.yaw, yawToward(toward), math.min(1, dt * 20))
							end
						end
						local forward, up, pitch = attackPose(follower.style.Name, t)
						pose = CFrame.Angles(0, follower.yaw, 0) * CFrame.new(0, up, -forward) * CFrame.Angles(pitch, 0, 0)
					end
				end
				model:PivotTo(CFrame.new(p.X, p.Y + lift, p.Z) * pose)
				-- Health bar while fighting or hurt.
				if fighting or follower.hp < 0.999 then
					ensureGui(follower)
					local gui = follower.gui :: BillboardGui
					gui.Enabled = true
					gui.StudsOffsetWorldSpace = Vector3.new(0, follower.size.Y + 0.8, 0)
					local back = follower.back :: Frame
					back.Visible = true
					local fill = follower.fill :: Frame
					fill.Size = UDim2.fromScale(math.clamp(follower.hp, 0, 1), 1)
					fill.BackgroundColor3 = if follower.hp > 0.5
						then Color3.fromRGB(92, 214, 92)
						elseif follower.hp > 0.25 then Color3.fromRGB(255, 196, 46)
						else Color3.fromRGB(240, 70, 60);
					(follower.zzz :: TextLabel).Visible = false
				elseif follower.gui then
					follower.gui.Enabled = false
				end
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
