--!strict
-- Pets in every base's pet park (like Steal an Egg): the server publishes each player's
-- aliens as Folders in base.Aliens (AlienId / Mutation / Income attributes). Every client
-- builds the Blender models locally and lets them wander inside the fenced park with
-- Idle / Walk animations, a Happy dance now and then, and a name + income tag.
-- Only parks near the camera are simulated; far ones are parked out of the world.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AlienModel = require(Shared.AlienModel)
local AssetLibrary = require(Shared.AssetLibrary)
local Aliens = require(Shared.Config.Aliens)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Weights = require(Shared.Config.Weights)
local World = require(Shared.Config.World)

local PARK_SCALE = 1.4
local ACTIVE_DISTANCE = 230 -- camera focus to base centre
local MARGIN = 3 -- keep this far from the fence
local WALK_SPEED = 4.5 -- studs per second (bigger pets walk a bit faster)
local TURN_SPEED = 6
local IDLE_TIME = NumberRange.new(2, 6)
local HAPPY_EVERY = NumberRange.new(18, 40)
local FLOAT_HEIGHT = 1.2

local PetController = {}

local C: any

type Pet = {
	key: string,
	model: Model,
	position: Vector2, -- park local X/Z
	yaw: number,
	target: Vector2?,
	waitUntil: number,
	nextHappy: number,
	floats: boolean,
	speed: number,
	idle: AnimationTrack?,
	walk: AnimationTrack?,
	happy: AnimationTrack?,
	walking: boolean,
}

type Park = {
	index: number,
	cframe: CFrame,
	pets: { [string]: Pet },
	active: boolean,
	folder: Folder,
}

local parks: { [number]: Park } = {}
local root: Folder
local rng = Random.new()

local function lerpAngle(a: number, b: number, t: number): number
	local diff = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + diff * t
end

-- True if the point is clear of park props (habitat, pond, trees...).
local function clearAt(p: Vector2, pad: number): boolean
	for _, prop in World.Base.ParkProps do
		local c = Vector2.new(prop.Position.X, prop.Position.Z)
		if (p - c).Magnitude < prop.Radius + pad then
			return false
		end
	end
	return true
end

-- True if walking a -> b doesn't cut through a prop.
local function clearPath(a: Vector2, b: Vector2, pad: number): boolean
	local ab = b - a
	local len2 = ab:Dot(ab)
	for _, prop in World.Base.ParkProps do
		local c = Vector2.new(prop.Position.X, prop.Position.Z)
		local t = if len2 > 0 then math.clamp((c - a):Dot(ab) / len2, 0, 1) else 0
		if (a + ab * t - c).Magnitude < prop.Radius + pad then
			return false
		end
	end
	return true
end

local function randomSpot(from: Vector2?): Vector2?
	local min, max = World.Base.ParkMin, World.Base.ParkMax
	for _ = 1, 10 do
		local p = Vector2.new(rng:NextNumber(min.X + MARGIN, max.X - MARGIN), rng:NextNumber(min.Y + MARGIN, max.Y - MARGIN))
		if clearAt(p, 2) and (not from or clearPath(from, p, 1.5)) then
			return p
		end
	end
	return nil
end

local function tag(model: Model, alienId: string, mutation: string?, income: number, huge: boolean)
	local def = Aliens.ById[alienId]
	local rarity = def and Eggs.ByName[def.Rarity]
	local _, size = model:GetBoundingBox()
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Tag"
	billboard.Size = UDim2.fromOffset(150, 46)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, size.Y + 1.2, 0)
	billboard.MaxDistance = 55
	billboard.LightInfluence = 0
	billboard.Adornee = model.PrimaryPart
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0.55, 0)
	name.BackgroundTransparency = 1
	name.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold)
	name.TextSize = 20
	name.TextColor3 = if rarity then rarity.Color else Color3.new(1, 1, 1)
	name.Text = (if huge then "HUGE " else "") .. AlienModel.displayName(alienId, mutation)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(27, 31, 58)
	stroke.Parent = name
	name.Parent = billboard
	local cash = Instance.new("TextLabel")
	cash.Size = UDim2.new(1, 0, 0.45, 0)
	cash.Position = UDim2.fromScale(0, 0.55)
	cash.BackgroundTransparency = 1
	cash.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold)
	cash.TextSize = 17
	cash.TextColor3 = Color3.fromRGB(124, 245, 140)
	cash.Name = "Cash"
	cash.Text = `+{Format.cash(income)}/s`
	local stroke2 = stroke:Clone()
	stroke2.Parent = cash
	cash.Parent = billboard
	billboard.Parent = model
end

local PARK_TOP = 0.2

local function pivot(park: Park, pet: Pet, bob: number)
	-- The park lawn (MapBuilder) is 0.2 stud above the base floor.
	local y = PARK_TOP + (if pet.floats then FLOAT_HEIGHT + bob else 0)
	pet.model:PivotTo(park.cframe * CFrame.new(pet.position.X, y, pet.position.Y) * CFrame.Angles(0, pet.yaw, 0))
end

local function setWalking(pet: Pet, walking: boolean)
	if pet.walking == walking then
		return
	end
	pet.walking = walking
	if walking then
		if pet.walk then
			pet.walk:Play(0.2)
		end
	elseif pet.walk then
		pet.walk:Stop(0.25)
	end
end

-- Your own pets get a "Pick up" prompt (back into your inventory).
local function addPickup(model: Model, uid: string)
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not root then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickUp"
	prompt.ActionText = "Pick up"
	prompt.ObjectText = model:GetAttribute("DisplayName") or ""
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = root
	prompt.Triggered:Connect(function()
		local ok, message = Net.func("Inventory"):InvokeServer("PickUpPet", uid)
		if message then
			C.HudController:Toast(message, if ok then "Good" else "Bad")
		end
	end)
end

local function spawnPet(park: Park, key: string, entry: Folder, fresh: boolean, owned: boolean)
	local alienId = entry:GetAttribute("AlienId") :: string
	local mutation = entry:GetAttribute("Mutation") :: string?
	local huge = entry:GetAttribute("Huge") == true
	local weightMult = entry:GetAttribute("WeightMult") or 1
	local model = AssetLibrary.alien(alienId, mutation)
	-- Heavier pets are drawn a bit bigger.
	model:ScaleTo(PARK_SCALE * (if huge then Aliens.HugeScale else 1) * Weights.visualScale(weightMult))
	model:SetAttribute("DisplayName", (if huge then "Huge " else "") .. AlienModel.displayName(alienId, mutation))
	-- Read by HoverController for the hover card.
	model:SetAttribute("AlienId", alienId)
	model:SetAttribute("Mutation", mutation)
	model:SetAttribute("Huge", huge)
	model:SetAttribute("Weight", entry:GetAttribute("Weight"))
	model:SetAttribute("WeightMult", weightMult)
	model:SetAttribute("Income", entry:GetAttribute("Income") or 0)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= model.PrimaryPart then
			part.CanQuery = true -- so the mouse can find it
		end
	end
	local meta = AssetLibrary.meta("Alien_" .. alienId)
	local start = randomSpot(nil) or (World.Base.ParkMin + World.Base.ParkMax) / 2
	local _, size = model:GetBoundingBox()
	local pet: Pet = {
		key = key,
		model = model,
		position = start,
		yaw = rng:NextNumber(0, math.pi * 2),
		target = nil,
		waitUntil = os.clock() + rng:NextNumber(0, 2),
		nextHappy = os.clock() + rng:NextNumber(HAPPY_EVERY.Min, HAPPY_EVERY.Max),
		floats = meta ~= nil and meta.float == true,
		speed = WALK_SPEED * math.clamp(size.Y / 3, 0.8, 1.5),
		idle = nil,
		walk = nil,
		happy = nil,
		walking = false,
	}
	tag(model, alienId, mutation, entry:GetAttribute("Income") or 0, huge)
	if owned then
		addPickup(model, entry.Name)
	end
	pivot(park, pet, 0)
	model.Parent = park.folder
	pet.idle = AssetLibrary.loadTrack(model, "Pet_Idle")
	pet.walk = AssetLibrary.loadTrack(model, "Pet_Walk")
	pet.happy = AssetLibrary.loadTrack(model, "Pet_Happy")
	if pet.idle then
		pet.idle:Play()
	end
	if fresh and pet.happy then
		-- Just hatched: celebrate.
		pet.happy:Play(0.1)
		pet.waitUntil = os.clock() + 1.2
	end
	park.pets[key] = pet
end

local function entryKey(entry: Folder): string
	return `{entry.Name}:{entry:GetAttribute("AlienId")}:{entry:GetAttribute("Mutation") or ""}:{entry:GetAttribute("Huge") == true}`
end

-- Rebuilds a park from base.Aliens, keeping pets that didn't change (the server rebuilds
-- the folder on every change).
local function sync(park: Park, base: Instance, initial: boolean)
	local folder = base:FindFirstChild("Aliens")
	local owned = folder ~= nil and folder:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId
	local wanted: { [string]: Folder } = {}
	if folder then
		for _, entry in folder:GetChildren() do
			if entry:IsA("Folder") and entry:GetAttribute("AlienId") then
				wanted[entryKey(entry)] = entry
			end
		end
	end
	for key, pet in park.pets do
		if not wanted[key] then
			pet.model:Destroy()
			park.pets[key] = nil
		end
	end
	for key, entry in wanted do
		local pet = park.pets[key]
		if not pet then
			spawnPet(park, key, entry, not initial, owned)
		else
			-- Income changes with boosts: refresh the tag in place (no respawn).
			local income = entry:GetAttribute("Income") or 0
			if pet.model:GetAttribute("Income") ~= income then
				pet.model:SetAttribute("Income", income)
				local tagGui = pet.model:FindFirstChild("Tag")
				local cash = tagGui and tagGui:FindFirstChild("Cash") :: TextLabel?
				if cash then
					cash.Text = `+{Format.cash(income)}/s`
				end
			end
		end
	end
end

local function watchBase(index: number, base: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Park" .. index
	folder.Parent = root
	local park: Park = { index = index, cframe = World.baseCFrame(index), pets = {}, active = true, folder = folder }
	parks[index] = park
	local pending = false
	local function schedule()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			sync(park, base, false)
		end)
	end
	sync(park, base, true)
	base.ChildAdded:Connect(function(child)
		if child.Name == "Aliens" then
			schedule()
			child.ChildAdded:Connect(schedule)
		end
	end)
	base.ChildRemoved:Connect(function(child)
		if child.Name == "Aliens" then
			schedule()
		end
	end)
	local current = base:FindFirstChild("Aliens")
	if current then
		current.ChildAdded:Connect(schedule)
	end
end

local function setActive(park: Park, active: boolean)
	if park.active == active then
		return
	end
	park.active = active
	park.folder.Parent = if active then root else nil
	if active then
		-- Tracks stop when a model leaves the world; start them again.
		for _, pet in park.pets do
			pet.walking = false
			if pet.idle then
				pet.idle:Play()
			end
		end
	end
end

local function step(park: Park, dt: number, now: number)
	local bob = math.sin(now * 2.2) * 0.25
	for _, pet in park.pets do
		if pet.happy and pet.happy.IsPlaying then
			pivot(park, pet, bob)
			continue
		end
		if now >= pet.nextHappy and not pet.walking and pet.happy then
			pet.nextHappy = now + rng:NextNumber(HAPPY_EVERY.Min, HAPPY_EVERY.Max)
			pet.happy:Play(0.1)
			continue
		end
		local target = pet.target
		if target then
			local delta = target - pet.position
			local dist = delta.Magnitude
			if dist < 0.3 then
				pet.target = nil
				pet.waitUntil = now + rng:NextNumber(IDLE_TIME.Min, IDLE_TIME.Max)
				setWalking(pet, false)
			else
				local dir = delta / dist
				local want = math.atan2(-dir.X, -dir.Y)
				pet.yaw = lerpAngle(pet.yaw, want, math.min(1, dt * TURN_SPEED))
				pet.position += dir * math.min(dist, pet.speed * dt)
				setWalking(pet, true)
			end
		elseif now >= pet.waitUntil then
			pet.target = randomSpot(pet.position)
			if not pet.target then
				pet.waitUntil = now + 1
			end
		end
		pivot(park, pet, bob)
	end
end

local function cycleRainbows(now: number)
	for _, model in CollectionService:GetTagged("RainbowPet") do
		if model:IsDescendantOf(Workspace) or model:FindFirstAncestorOfClass("ViewportFrame") then
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					local offset = d:GetAttribute("RainbowOffset")
					if offset then
						d.Color = Color3.fromHSV((now * 0.25 + offset) % 1, 0.7, 1)
					end
				end
			end
		end
	end
end

function PetController:Init(controllers)
	C = controllers
	root = Instance.new("Folder")
	root.Name = "PetParks"
	root.Parent = Workspace
end

function PetController:Start()
	-- Wait for the Blender models so parks don't fill with placeholders first.
	AssetLibrary.waitReady(45)
	local bases = Workspace:WaitForChild("Moon"):WaitForChild("Bases")
	for i = 1, World.BaseCount do
		local base = bases:WaitForChild("Base" .. i, 30)
		if base then
			watchBase(i, base)
		end
	end
	local rainbowClock = 0
	RunService.Heartbeat:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		local focus = if camera then camera.Focus.Position else Vector3.zero
		local now = os.clock()
		for _, park in parks do
			local near = (park.cframe.Position - focus).Magnitude < ACTIVE_DISTANCE
			setActive(park, near)
			if near then
				step(park, dt, now)
			end
		end
		rainbowClock += dt
		if rainbowClock > 0.1 then
			rainbowClock = 0
			cycleRainbows(now)
		end
	end)
end

return PetController
