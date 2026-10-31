--!strict
-- Leaf dumps (like making honey in Bee Swarm): while a player stands or drives on a dump's
-- circle (player attribute "Dumping" = dump index, set by BackpackService), 3D leaves pour
-- out of their backpack (or car) one by one in an arc into the hopper, the rollers spin, the pile inside rises and coins pop
-- out of the slot. For you, a "+$" counter over the dump adds up each bit of cash (DumpTick)
-- with a coin blip that climbs in pitch. Sell Anywhere gets a quick leaf burst (SellBurst).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local LeafMeshes = require(Client.LeafMeshes)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Config.Assets)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local DumpController = {}

local C: any

local VIEW_DISTANCE = 220
local POUR_EVERY = 0.05 -- seconds between leaves per dumping player
local FLIGHT = 0.55
local MAX_LEAVES = 90
local PILE_MAX = 1.6 -- studs the pile rises while someone dumps
local HEAP_LEAVES = 22 -- leaf meshes in the pile inside the hopper

type Leaf = { part: BasePart, from: Vector3, to: () -> Vector3, start: number, spin: Vector3, time: number, rise: number }
type DumpVisual = {
	model: Model,
	rollers: { { part: BasePart, base: CFrame } },
	pile: BasePart?,
	pileBase: CFrame?,
	pileLevel: number,
	heap: { { offset: CFrame, part: BasePart? } },
	look: LeafMeshes.Look?,
	coins: ParticleEmitter?,
	mouth: Attachment?,
	busyUntil: number,
}

local folder: Folder
local leaves: { Leaf } = {}
local dumps: { [number]: DumpVisual } = {}
local nextPour: { [Player]: number } = {}
local counter: BillboardGui? = nil
local counterLabel: TextLabel? = nil
local counterTotal = 0
local counterUntil = 0
local tickCount = 0

local function image(name: string): string
	return Assets.Images[name] or ""
end

local function launch(from: Vector3, to: () -> Vector3, time: number, rise: number, look: LeafMeshes.Look?)
	if #leaves >= MAX_LEAVES then
		return
	end
	-- Real leaf meshes (LeafMeshes) in the colours of what's in the bag; nothing until
	-- they've loaded.
	if not LeafMeshes.ready() then
		return
	end
	local part = LeafMeshes.random(look or LeafMeshes.lookFor(nil), 1 + math.random() * 0.6)
	if not part then
		return
	end
	part.CFrame = CFrame.new(from)
	part.Parent = folder
	table.insert(leaves, {
		part = part,
		from = from,
		to = to,
		start = os.clock(),
		spin = Vector3.new(math.random() * 8 - 4, math.random() * 10 - 5, math.random() * 8 - 4),
		time = time,
		rise = rise,
	})
end

local function stepLeaves(now: number)
	for i = #leaves, 1, -1 do
		local l = leaves[i]
		local t = (now - l.start) / l.time
		if t >= 1 then
			table.remove(leaves, i)
			LeafMeshes.give(l.part)
			continue
		end
		local to = l.to()
		local pos = l.from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * l.rise, 0)
		l.part.CFrame = CFrame.new(pos) * CFrame.Angles(l.spin.X * t, l.spin.Y * t, l.spin.Z * t)
	end
end

-- Finds the parts of dump i in the world (MapBuilder.leafDump).
local function visual(i: number): DumpVisual?
	local existing = dumps[i]
	if existing and existing.model.Parent then
		return existing
	end
	local structures = Workspace:FindFirstChild("Structures")
	local model = structures and structures:FindFirstChild("LeafDump" .. i)
	if not model or not model:IsA("Model") then
		return nil
	end
	local v: DumpVisual = { model = model, rollers = {}, pileLevel = 0, busyUntil = 0, heap = {} }
	for _, name in { "Roller1", "Roller2" } do
		local r = model:FindFirstChild(name)
		if r and r:IsA("BasePart") then
			table.insert(v.rollers, { part = r, base = r.CFrame })
		end
	end
	local pile = model:FindFirstChild("Pile")
	if pile and pile:IsA("BasePart") then
		v.pile = pile
		v.pileBase = pile.CFrame
		-- The heap is made of real leaf meshes (the old flat leaf picture goes).
		for _, d in pile:GetChildren() do
			if d:IsA("Decal") then
				d:Destroy()
			end
		end
		local rng = Random.new(i)
		for k = 1, HEAP_LEAVES do
			local h = k / HEAP_LEAVES
			local spread = 1 - 0.5 * h -- wide at the bottom, rounded on top
			local offset = CFrame.new(rng:NextNumber(-3.2, 3.2) * spread, h * 0.9, rng:NextNumber(-2.7, 2.7) * spread)
				* CFrame.Angles(rng:NextNumber(-0.7, 0.7), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.7, 0.7))
			table.insert(v.heap, { offset = offset })
		end
	end
	local body = model:FindFirstChild("Body")
	local mouth = body and body:FindFirstChild("Mouth")
	v.mouth = if mouth and mouth:IsA("Attachment") then mouth else nil
	local slot = model:FindFirstChild("CoinSlot")
	local out = slot and slot:FindFirstChild("CoinOut")
	if out and out:IsA("Attachment") then
		local e = Instance.new("ParticleEmitter")
		e.Name = "Coins"
		e.Texture = image("Icon_Cash")
		e.Enabled = false
		e.Lifetime = NumberRange.new(0.6, 0.9)
		e.Speed = NumberRange.new(10, 16)
		e.SpreadAngle = Vector2.new(25, 25)
		e.EmissionDirection = Enum.NormalId.Front
		e.Acceleration = Vector3.new(0, -40, 0)
		e.Size = NumberSequence.new(1.1)
		e.Rotation = NumberRange.new(-30, 30)
		e.RotSpeed = NumberRange.new(-200, 200)
		e.LightInfluence = 0
		e.Parent = out
		v.coins = e
	end
	dumps[i] = v
	return v
end

local function mouthOf(v: DumpVisual): () -> Vector3
	local mouth = v.mouth
	if mouth then
		return function()
			return mouth.WorldPosition + Vector3.new(math.random() * 4 - 2, 0, math.random() * 3 - 1.5)
		end
	end
	local at = v.model:GetPivot().Position + Vector3.new(0, 6, 0)
	return function()
		return at
	end
end

-- Where a player's leaves come out: the car they drive, or their backpack.
local function source(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local seat = humanoid and humanoid.SeatPart
	if seat and seat.Parent and seat.Parent:IsA("Model") then
		return seat.Parent:GetPivot().Position + Vector3.new(0, 3, 0)
	end
	-- Out of the top of the backpack they wear.
	local bag = character and character:FindFirstChild("LeafBag")
	local body = bag and bag:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		return body.Position + Vector3.new(0, body.Size.Y * 0.5, 0)
	end
	return root.Position - root.CFrame.LookVector * 0.8 + Vector3.new(0, 1, 0)
end

-- The leaf heap inside the hopper: grows with the pile level, empty when nobody dumps.
local function updateHeap(v: DumpVisual)
	local pile = v.pile :: BasePart
	local want = if LeafMeshes.ready() then math.floor(v.pileLevel * HEAP_LEAVES + 0.5) else 0
	local look: LeafMeshes.Look? = nil
	for k, slot in v.heap do
		if k <= want then
			if not slot.part then
				-- What the dumping player swept (snow, seaweed, paper...), not always leaves.
				look = look or v.look or LeafMeshes.lookFor(nil)
				local part = LeafMeshes.random(look :: LeafMeshes.Look, 1.3 + (k % 3) * 0.2)
				if part then
					part.Parent = folder
					slot.part = part
				end
			end
			if slot.part then
				slot.part.CFrame = pile.CFrame * slot.offset
			end
		elseif slot.part then
			LeafMeshes.give(slot.part)
			slot.part = nil
		end
	end
end

local function stepDumps(now: number, dt: number)
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	for _, player in Players:GetPlayers() do
		local index = player:GetAttribute("Dumping")
		if type(index) ~= "number" then
			nextPour[player] = nil
			continue
		end
		local v = visual(index)
		local from = source(player)
		if not v or not from or (from - eye).Magnitude > VIEW_DISTANCE then
			continue
		end
		v.busyUntil = now + 0.4
		local look = C.BackpackController:LookOf(player)
		if look and v.look ~= look then
			-- A different kind of trash: the heap is rebuilt in its colours.
			v.look = look
			for _, slot in v.heap do
				if slot.part then
					LeafMeshes.give(slot.part)
					slot.part = nil
				end
			end
		end
		-- Only your own leaves pour (other players' dumps just run their rollers): less to
		-- animate with a full server.
		if player == Players.LocalPlayer and now >= (nextPour[player] or 0) then
			nextPour[player] = now + POUR_EVERY
			launch(from, mouthOf(v), FLIGHT, 5 + math.random() * 2, look)
		end
	end
	-- Rollers spin and the pile rises while busy, then settle.
	for _, v in dumps do
		local busy = now < v.busyUntil
		local target = if busy then 1 else 0
		v.pileLevel += (target - v.pileLevel) * math.min(1, dt * (if busy then 1.2 else 0.8))
		if v.pile and v.pileBase then
			v.pile.CFrame = v.pileBase * CFrame.new(0, v.pileLevel * PILE_MAX, 0)
			updateHeap(v)
		end
		if busy then
			for k, r in v.rollers do
				local dir = if k == 1 then 1 else -1
				r.part.CFrame = r.part.CFrame * CFrame.Angles(dt * 14 * dir, 0, 0)
			end
		end
	end
end

local function ensureCounter(): (BillboardGui, TextLabel)
	if counter and counterLabel then
		return counter, counterLabel
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "DumpCounter"
	gui.Size = UDim2.fromOffset(240, 60)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Enabled = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
	label.TextColor3 = Color3.fromRGB(139, 224, 78)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(23, 25, 30)
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Name = "Pop"
	scale.Parent = label
	gui.Parent = folder
	counter, counterLabel = gui, label
	return gui, label
end

local function onDumpTick(cash: number, _left: number)
	local index = Players.LocalPlayer:GetAttribute("Dumping")
	local v = if type(index) == "number" then visual(index) else nil
	local now = os.clock()
	if now > counterUntil then
		counterTotal = 0
		tickCount = 0
	end
	counterTotal += cash
	counterUntil = now + 2
	tickCount += 1
	local gui, label = ensureCounter()
	if v and v.mouth then
		gui.Adornee = v.mouth
	end
	gui.Enabled = true
	label.Text = "+" .. Format.cash(counterTotal)
	local pop = label:FindFirstChild("Pop") :: UIScale
	pop.Scale = 1.2
	TweenService:Create(pop, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	if v and v.coins then
		v.coins:Emit(3)
	end
	Ui.sound("Coin", 0.9 + math.min(tickCount, 20) * 0.03)
	task.delay(2.05, function()
		if os.clock() >= counterUntil and counter then
			counter.Enabled = false
		end
	end)
end

-- A leaf that was in someone's backpack flies out: into the dump they're standing at, or
-- up and away (Sell Anywhere). The part is ours from here and goes back to LeafMeshes when
-- it lands.
function DumpController:Throw(player: Player, part: BasePart)
	if #leaves >= MAX_LEAVES then
		LeafMeshes.give(part)
		return
	end
	local from = part.Position
	local index = player:GetAttribute("Dumping")
	local v = if type(index) == "number" then visual(index) else nil
	local to: () -> Vector3
	local rise: number
	if v then
		to = mouthOf(v)
		rise = 5 + math.random() * 2
	else
		local a = math.random() * math.pi * 2
		local spot = from + Vector3.new(math.cos(a) * 5, 8 + math.random() * 4, math.sin(a) * 5)
		to = function()
			return spot
		end
		rise = 2
	end
	part.Parent = folder
	table.insert(leaves, {
		part = part,
		from = from,
		to = to,
		start = os.clock(),
		spin = Vector3.new(math.random() * 8 - 4, math.random() * 10 - 5, math.random() * 8 - 4),
		time = FLIGHT + math.random() * 0.15,
		rise = rise,
	})
end

-- Sell Anywhere: the bag bursts out of you in a puff of leaves.
function DumpController:SellBurst()
	local from = source(Players.LocalPlayer)
	if not from then
		return
	end
	Ui.sound("Sell")
	for _ = 1, 24 do
		local a = math.random() * math.pi * 2
		local to = from + Vector3.new(math.cos(a) * 6, 10 + math.random() * 4, math.sin(a) * 6)
		launch(from, function()
			return to
		end, 0.6 + math.random() * 0.3, 2, C.BackpackController:LookOf(Players.LocalPlayer))
	end
end

function DumpController:Init(controllers)
	C = controllers
	folder = Instance.new("Folder")
	folder.Name = "DumpFx"
	folder.Parent = Workspace
end

function DumpController:Start()
	Net.event("DumpTick").OnClientEvent:Connect(onDumpTick)
	Players.PlayerRemoving:Connect(function(player)
		nextPour[player] = nil
	end)
	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		stepDumps(now, dt)
		stepLeaves(now)
	end)
end

return DumpController
