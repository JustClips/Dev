--!strict
-- What's inside everyone's backpack (BackpackService welds the "LeafBag" model on every
-- character). Real leaf meshes (LeafMeshes) pile up in the bag as the player's BagFill
-- attribute goes up: each new leaf drops in from above the rim with a little spin, in the
-- colours of the zone you're sweeping, and they pile up past the rim when it's full.
-- Dumping takes them out from the top down. Under the leaves a low, dark heap (the bag's
-- "Fill" part) fills the gaps so the bag never looks see-through.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local LeafMeshes = require(Client.LeafMeshes)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Grid = require(Shared.Grid)

local BackpackController = {}

local C: any

local LEAVES = 30 -- leaves in a full bag
local EASE = 6 -- how fast the shown fill follows the real one
local DROP_TIME = 0.28 -- a new leaf falling in
local DROP_HEIGHT = 1.6 -- from this far above its spot (in bag sizes)
local RANGE = 140 -- studs from the camera to draw the leaves
local BED_COLOR = Color3.fromRGB(122, 70, 32)

type Slot = {
	offset: CFrame, -- where it rests, in the bag body's space
	leaf: BasePart?,
	t: number, -- 0..1 drop-in progress
	spin: number,
}
type Bag = {
	body: BasePart,
	fill: BasePart,
	weld: Weld,
	full: Vector3,
	bottom: Vector3,
	c0: CFrame,
	shown: number,
	bounce: number,
	goal: number,
	slots: { Slot },
	size: number, -- bag width, sets the leaf size
}
local bags: { [Player]: Bag } = {}
local folder: Folder

-- Resting spots, bottom to top: a heap that's widest low down and rounds off on top,
-- poking a little over the rim when the bag is full.
local function makeSlots(full: Vector3, bottom: Vector3, centre: Vector3, rng: Random): { Slot }
	local slots: { Slot } = {}
	local top = centre.Y + full.Y * 0.62 -- a bit over the rim
	for i = 1, LEAVES do
		local h = (i - 0.5) / LEAVES
		local narrow = 1 - 0.45 * h * h
		local x = centre.X + rng:NextNumber(-0.42, 0.42) * full.X * narrow
		local z = centre.Z + rng:NextNumber(-0.42, 0.42) * full.Z * narrow
		local y = bottom.Y + (top - bottom.Y) * h
		local tilt = CFrame.Angles(rng:NextNumber(-0.9, 0.9), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.9, 0.9))
		table.insert(slots, { offset = CFrame.new(x, y, z) * tilt, leaf = nil, t = 0, spin = rng:NextNumber(-8, 8) })
	end
	return slots
end

local function release(slot: Slot)
	if slot.leaf then
		LeafMeshes.give(slot.leaf)
		slot.leaf = nil
	end
	slot.t = 0
end

local function clear(bag: Bag)
	for _, slot in bag.slots do
		release(slot)
	end
end

local function find(player: Player): Bag?
	local existing = bags[player]
	if existing and existing.fill.Parent and existing.weld.Parent and existing.body.Parent then
		return existing
	end
	if existing then
		clear(existing)
	end
	bags[player] = nil
	local character = player.Character
	local model = character and character:FindFirstChild("LeafBag")
	local fill = model and model:FindFirstChild("Fill")
	local body = model and model:FindFirstChild("Body")
	local weld = fill and fill:FindFirstChild("FillWeld")
	if not fill or not fill:IsA("BasePart") or not weld or not weld:IsA("Weld") or not body or not body:IsA("BasePart") then
		return nil
	end
	local full = fill:GetAttribute("FullSize")
	local bottom = fill:GetAttribute("Bottom")
	if typeof(full) ~= "Vector3" or typeof(bottom) ~= "Vector3" then
		return nil
	end
	fill.Color = BED_COLOR
	local rng = Random.new(player.UserId)
	local bag: Bag = {
		body = body,
		fill = fill,
		weld = weld,
		full = full,
		bottom = bottom,
		c0 = weld.C0,
		shown = -1,
		bounce = 0,
		goal = 0,
		slots = makeSlots(full, bottom, weld.C0.Position, rng),
		size = math.min(full.X, full.Z),
	}
	bags[player] = bag
	return bag
end

-- The dark bed under the leaves: up to 80 % of the heap, so leaves stick out of it.
local function applyBed(bag: Bag, f: number)
	local h = f * 0.8
	if h < 0.04 then
		bag.fill.Transparency = 1
		return
	end
	bag.fill.Transparency = 0
	local squash = 1 + bag.bounce * 0.1
	bag.fill.Size = Vector3.new(bag.full.X * squash * 0.96, bag.full.Y * h, bag.full.Z * squash * 0.96)
	local centre = bag.c0.Position
	local y = bag.bottom.Y + (centre.Y - bag.bottom.Y) * h
	bag.weld.C0 = CFrame.new(centre.X, y, centre.Z) * bag.c0.Rotation
end

-- The leaves of the zone this player is in (new leaves only; the old ones keep theirs).
local function lookFor(player: Player): LeafMeshes.Look
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local zone = root and Grid.zoneAt(root.Position)
	return LeafMeshes.lookFor(zone and (zone :: any).Ground)
end

-- The leaves going into each player's bag right now (for the dump's pour colours).
local looks: { [Player]: LeafMeshes.Look } = {}

local function updateLeaves(bag: Bag, player: Player, dt: number, near: boolean)
	if not near or not LeafMeshes.ready() then
		clear(bag)
		return
	end
	local want = math.floor(bag.shown * LEAVES + 0.5)
	local look: LeafMeshes.Look? = nil
	local bodyCf = bag.body.CFrame
	for i, slot in bag.slots do
		if i <= want then
			if not slot.leaf then
				look = look or lookFor(player)
				looks[player] = look :: LeafMeshes.Look
				local leaf = LeafMeshes.random(look :: LeafMeshes.Look, bag.size * 0.5)
				if leaf then
					leaf.Parent = folder
					slot.leaf = leaf
					slot.t = 0
				end
			end
			slot.t = math.min(1, slot.t + dt / DROP_TIME)
		elseif slot.leaf then
			-- Selling: the bag's own leaves fly out, top down, into the dump you're at (or
			-- up and away with Sell Anywhere).
			local leaf = slot.leaf :: BasePart
			slot.leaf = nil
			slot.t = 0
			if not leaf.Parent then
				LeafMeshes.give(leaf)
			else
				C.DumpController:Throw(player, leaf)
			end
		end
		local leaf = slot.leaf
		if leaf then
			local cf = bodyCf * slot.offset
			if slot.t < 1 then
				-- Falls in from above the rim, turning, and lands with a tiny settle.
				local e = 1 - (1 - slot.t) ^ 2
				local lift = (1 - e) * DROP_HEIGHT * bag.size
				leaf.CFrame = (bodyCf * CFrame.new(0, lift, 0)) * slot.offset * CFrame.Angles(0, (1 - e) * slot.spin, 0)
			else
				leaf.CFrame = cf
			end
		end
	end
end

-- The leaf colours in this player's bag (nil: the default autumn leaves).
function BackpackController:LookOf(player: Player): LeafMeshes.Look?
	return looks[player]
end

function BackpackController:Init(controllers)
	C = controllers
end

function BackpackController:Start()
	folder = Instance.new("Folder")
	folder.Name = "BagLeaves"
	folder.Parent = Workspace
	Players.PlayerRemoving:Connect(function(player)
		local bag = bags[player]
		if bag then
			clear(bag)
		end
		bags[player] = nil
		looks[player] = nil
	end)
	RunService.RenderStepped:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		local camPos = if camera then camera.CFrame.Position else Vector3.zero
		for _, player in Players:GetPlayers() do
			local bag = find(player)
			if not bag then
				continue
			end
			local target = player:GetAttribute("BagFill")
			local goal = if type(target) == "number" then target else 0
			if bag.shown < 0 then
				bag.shown = goal
				bag.goal = goal
			end
			if goal > bag.goal then
				bag.bounce = 1 -- more leaves went in
			end
			bag.goal = goal
			bag.shown += (goal - bag.shown) * math.min(1, dt * EASE)
			bag.bounce = math.max(0, bag.bounce - dt * 4)
			applyBed(bag, bag.shown)
			local near = (bag.body.Position - camPos).Magnitude < RANGE
			updateLeaves(bag, player, dt, near)
		end
	end)
end

return BackpackController
