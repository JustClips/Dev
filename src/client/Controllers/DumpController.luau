--!strict
-- Leaf dumps (like making honey in Bee Swarm): while a player stands or drives on a dump's
-- circle (player attribute "Dumping" = dump index, set by BackpackService), leaves pour out
-- of them in an arc into the hopper, the rollers spin, the pile inside rises and coins pop
-- out of the slot. For you, a "+$" counter over the dump adds up each bit of cash (DumpTick)
-- with a coin blip that climbs in pitch. Sell Anywhere gets a quick leaf burst (SellBurst).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Config.Assets)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local DumpController = {}

local VIEW_DISTANCE = 220
local POUR_EVERY = 0.05 -- seconds between leaves per dumping player
local FLIGHT = 0.55
local MAX_LEAVES = 90
local PILE_MAX = 1.6 -- studs the pile rises while someone dumps
local LEAF_IMAGES = { "Vfx_LeafMaple", "Vfx_LeafOval", "Vfx_LeafGreen", "Vfx_LeafMaple" }

type Leaf = { part: BasePart, from: Vector3, to: () -> Vector3, start: number, spin: Vector3, time: number, rise: number }
type DumpVisual = {
	model: Model,
	rollers: { { part: BasePart, base: CFrame } },
	pile: BasePart?,
	pileBase: CFrame?,
	pileLevel: number,
	coins: ParticleEmitter?,
	mouth: Attachment?,
	busyUntil: number,
}

local folder: Folder
local pool: { BasePart } = {}
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

local function takeLeaf(): BasePart
	local p = table.remove(pool)
	if p then
		return p
	end
	local part = Instance.new("Part")
	part.Name = "PouringLeaf"
	part.Size = Vector3.new(1.3, 0.05, 1.3)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	for _, face in { Enum.NormalId.Top, Enum.NormalId.Bottom } do
		local decal = Instance.new("Decal")
		decal.Face = face
		decal.Parent = part
	end
	return part
end

local function launch(from: Vector3, to: () -> Vector3, time: number, rise: number)
	if #leaves >= MAX_LEAVES then
		return
	end
	local part = takeLeaf()
	local texture = image(LEAF_IMAGES[math.random(1, #LEAF_IMAGES)])
	for _, d in part:GetChildren() do
		if d:IsA("Decal") then
			d.Texture = texture
		end
	end
	local size = 0.9 + math.random() * 0.7
	part.Size = Vector3.new(size, 0.05, size)
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
			l.part.Parent = nil
			table.insert(pool, l.part)
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
	local v: DumpVisual = { model = model, rollers = {}, pileLevel = 0, busyUntil = 0 }
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

-- Where a player's leaves come out: the car they drive, or their back.
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
	return root.Position - root.CFrame.LookVector * 0.8 + Vector3.new(0, 1, 0)
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
		if now >= (nextPour[player] or 0) then
			nextPour[player] = now + POUR_EVERY
			launch(from, mouthOf(v), FLIGHT, 5 + math.random() * 2)
		end
	end
	-- Rollers spin and the pile rises while busy, then settle.
	for _, v in dumps do
		local busy = now < v.busyUntil
		local target = if busy then 1 else 0
		v.pileLevel += (target - v.pileLevel) * math.min(1, dt * (if busy then 1.2 else 0.8))
		if v.pile and v.pileBase then
			v.pile.CFrame = v.pileBase * CFrame.new(0, v.pileLevel * PILE_MAX, 0)
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
		end, 0.6 + math.random() * 0.3, 2)
	end
end

function DumpController:Init()
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
