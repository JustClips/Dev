--!strict
-- Leaf drops you can pick up (DropService, Slime RNG style), your Treasure Map's red X and
-- the Leaf Bomb blast.
--
-- A drop pops out of the pile it came from, lands, and bobs on the ground with its icon,
-- a glow ring in its rarity's colour and (Rare and up) a light beam so you spot it from
-- far away. Walk within your coin magnet range and it zips into you. Only you see your own
-- drops. Drops left too long are given to you by the server and fly in (ItemsAuto).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Format = require(Shared.Format)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)

local DropController = {}

local C: any
local FLY_OUT = 0.55
local FLY_IN = 0.25
local HOVER = 2.4 -- studs above the ground (the glow orb is ~4 studs wide)
local REPORT_EVERY = 0.15
local POUCH_COLOR = Color3.fromRGB(255, 205, 40)
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
-- Cartoon 4-point star (tools/gen_vfx.py), or the stock sparkle when it is missing.
local STAR = if AssetLibrary.image("Vfx_Star") ~= "" then AssetLibrary.image("Vfx_Star") else SPARKLE
local POUCH_HOVER = 1.7 -- the pouch model's centre above the ground (it is ~2.3 studs tall)

type Drop = {
	id: number,
	item: string?,
	cash: number?,
	model: Model,
	root: BasePart,
	from: Vector3,
	to: Vector3,
	start: number,
	state: string, -- "out" | "ground" | "in"
	inStart: number,
	inFrom: Vector3,
	report: boolean,
	pouch: boolean, -- the modelled Coin_Pouch spins instead of showing an icon
	baseSize: Vector3?,
}

local folder: Folder
local drops: { [number]: Drop } = {}
local toReport: { number } = {}
local lastReport = 0

local function rarityOf(item: string?): string
	local def = item and Items.ById[item]
	return if def then def.Rarity else "Common"
end

local function colorOf(item: string?): Color3
	if not item then
		return POUCH_COLOR
	end
	return Items.RarityColors[rarityOf(item)] or POUCH_COLOR
end

local function part(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	local any: any = p
	for k, v in props do
		any[k] = v
	end
	return p
end

-- Coin pouches are the modelled Coin_Pouch mesh (art/blender/coins.py: a lumpy burlap
-- money sack, gold rope, a gold "$" and coins poking out the top, dark cartoon outline).
-- The mesh itself is the root the movement code moves: no welds (welded pieces set up
-- outside Workspace stay behind at the map origin, so only the glow would follow).
local function pouchMesh(): BasePart?
	local model = AssetLibrary.get("Coin_Pouch")
	local body = model and model:FindFirstChild("Body")
	if not (model and body and body:IsA("BasePart")) then
		if model then
			model:Destroy()
		end
		return nil
	end
	body.Parent = nil
	model:Destroy()
	body.Name = "Root"
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CastShadow = true
	body.Material = Enum.Material.SmoothPlastic
	return body
end

-- Cartoon VFX around the pouch: a soft gold glow, twinkle stars popping on its surface and
-- gold sparkles drifting up.
local function pouchVfx(root: BasePart)
	local halo = Instance.new("BillboardGui")
	halo.Name = "Halo"
	halo.Size = UDim2.fromScale(4.6, 4.6)
	halo.LightInfluence = 0
	halo.MaxDistance = 220
	halo.Parent = root
	local glow = Instance.new("ImageLabel")
	glow.BackgroundTransparency = 1
	glow.Size = UDim2.fromScale(1, 1)
	glow.Image = AssetLibrary.image("Vfx_Glow")
	glow.ImageColor3 = POUCH_COLOR
	glow.ImageTransparency = 0.45
	glow.Parent = halo
	local twinkle = Instance.new("ParticleEmitter")
	twinkle.Name = "Twinkle"
	twinkle.Texture = STAR
	twinkle.Color = ColorSequence.new(Color3.fromRGB(255, 255, 235), Color3.fromRGB(255, 230, 120))
	twinkle.LightEmission = 0.7
	twinkle.LightInfluence = 0
	twinkle.Rate = 5
	twinkle.Lifetime = NumberRange.new(0.45, 0.75)
	twinkle.Speed = NumberRange.new(0.2, 0.8)
	twinkle.SpreadAngle = Vector2.new(180, 180)
	twinkle.Shape = Enum.ParticleEmitterShape.Sphere
	twinkle.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	twinkle.Rotation = NumberRange.new(-20, 20)
	twinkle.RotSpeed = NumberRange.new(-90, 90)
	twinkle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 1.1),
		NumberSequenceKeypoint.new(1, 0),
	})
	twinkle.Parent = root
	local rise = Instance.new("ParticleEmitter")
	rise.Name = "Rise"
	rise.Texture = SPARKLE
	rise.Color = ColorSequence.new(Color3.fromRGB(255, 245, 190), POUCH_COLOR)
	rise.LightEmission = 0.8
	rise.LightInfluence = 0
	rise.Rate = 6
	rise.Lifetime = NumberRange.new(0.8, 1.3)
	rise.Speed = NumberRange.new(1.5, 3)
	rise.SpreadAngle = Vector2.new(25, 25)
	rise.EmissionDirection = Enum.NormalId.Top
	rise.Size = NumberSequence.new(0.3, 0)
	rise.Parent = root
end

-- The drop: the pouch model, or an invisible root with the item's icon on a billboard,
-- plus a glow ring and maybe a beam.
local function build(item: string?): (Model, BasePart, boolean)
	local model = Instance.new("Model")
	model.Name = "Drop"
	local color = colorOf(item)
	local rarity = rarityOf(item)
	local mesh = if item == nil then pouchMesh() else nil
	local root = mesh or part({ Name = "Root", Size = Vector3.new(0.4, 0.4, 0.4), Transparency = 1 })
	root.Parent = model
	model.PrimaryPart = root
	if mesh then
		pouchVfx(mesh)
	else
		local big = rarity == "Epic" or rarity == "Legendary"
		local gui = Instance.new("BillboardGui")
		gui.Name = "Icon"
		gui.Size = UDim2.fromScale(if big then 5 else 4.2, if big then 5 else 4.2)
		gui.LightInfluence = 0
		gui.MaxDistance = 220
		gui.Adornee = root
		gui.Parent = root
		-- Glowing orb behind the icon, Pet Sim style (Dev 2026-10-31: drops were hard to see).
		local glow = Instance.new("ImageLabel")
		glow.Name = "Glow"
		glow.Size = UDim2.fromScale(1, 1)
		glow.BackgroundTransparency = 1
		glow.Image = AssetLibrary.image("Vfx_Glow")
		glow.ImageColor3 = color
		glow.ZIndex = 1
		glow.Parent = gui
		local image = Instance.new("ImageLabel")
		image.Name = "Item"
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromScale(0.62, 0.62)
		image.BackgroundTransparency = 1
		image.ZIndex = 2
		image.Image = AssetLibrary.image(if item and Items.ById[item] then Items.ById[item].Icon else "Icon_Cash")
		image.Parent = gui
		local pop = Instance.new("UIScale")
		pop.Name = "Pop"
		pop.Parent = image
	end
	-- Glow ring on the ground (a flat neon disc).
	local ring = part({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 3.6, 3.6),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
	})
	ring.Parent = model
	local big = rarity == "Epic" or rarity == "Legendary"
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = SPARKLE
	sparkle.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	sparkle.LightEmission = 0.7
	sparkle.Rate = if rarity == "Common" then 4 else 8
	sparkle.Lifetime = NumberRange.new(0.6, 1)
	sparkle.Speed = NumberRange.new(1, 2.5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new(0.35, 0)
	sparkle.Parent = root
	if rarity ~= "Common" and rarity ~= "Uncommon" then
		-- A light beam you can see across the field (Slime RNG drops do this).
		local beam = part({
			Name = "Beam",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(if big then 40 else 24, 0.7, 0.7),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.55,
		})
		beam.Parent = model
	end
	model.Parent = folder
	return model, root, mesh ~= nil
end

local function place(d: Drop, at: Vector3, now: number)
	local bob = math.sin(now * 3 + d.id) * 0.25
	if d.pouch then
		-- slow spin with a little cartoon wobble
		d.root.CFrame = CFrame.new(at + Vector3.new(0, POUCH_HOVER + bob, 0))
			* CFrame.Angles(0, now * 1.8 + d.id, 0)
			* CFrame.Angles(math.sin(now * 2.4 + d.id) * 0.12, 0, 0)
	else
		d.root.CFrame = CFrame.new(at + Vector3.new(0, HOVER + bob, 0))
	end
	local ring = d.model:FindFirstChild("Ring") :: BasePart?
	if ring then
		ring.CFrame = CFrame.new(at + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, now * 1.5, math.rad(90))
	end
	local beam = d.model:FindFirstChild("Beam") :: BasePart?
	if beam then
		beam.CFrame = CFrame.new(at + Vector3.new(0, beam.Size.X / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	end
end

local function rootPart(): BasePart?
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function startIn(d: Drop, report: boolean, now: number)
	if d.state == "in" then
		return
	end
	d.state = "in"
	d.inStart = now
	d.inFrom = d.root.Position
	d.report = report
	-- The trail parts vanish once it's on its way.
	for _, name in { "Ring", "Beam" } do
		local p = d.model:FindFirstChild(name)
		if p then
			p:Destroy()
		end
	end
end

-- Squash and stretch on a MeshPart by its Size (it scales the mesh).
local function squash(d: Drop)
	local base = d.baseSize
	if not base or Ui.reducedMotion() then
		return
	end
	d.root.Size = base * Vector3.new(1.3, 0.7, 1.3)
	TweenService:Create(d.root, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = base })
		:Play()
end

local pouchPop: (at: Vector3) -> ()

local function landed(d: Drop)
	if d.pouch then
		squash(d)
	end
	local rarity = rarityOf(d.item)
	if rarity ~= "Common" then
		Ui.sound(if rarity == "Epic" or rarity == "Legendary" then "RareReveal" else "Sparkle")
	else
		Ui.sound("Pop", 1.2)
	end
end

local function pickedUp(d: Drop)
	if d.cash then
		if d.pouch then
			pouchPop(d.root.Position)
		end
		Ui.sound("Coin", 1.1)
		C.HudController:Toast(`Coin pouch! +{Format.cash(d.cash)}`, "Sell")
	else
		Ui.sound("Gift")
	end
end

local function onDropped(list: any)
	if type(list) ~= "table" then
		return
	end
	local now = os.clock()
	for _, info in list do
		if type(info) ~= "table" or typeof(info.Pos) ~= "Vector3" or type(info.Id) ~= "number" then
			continue
		end
		local item = if type(info.Item) == "string" then info.Item else nil
		local model, root, pouch = build(item)
		local to = info.Pos :: Vector3
		local d: Drop = {
			id = info.Id,
			item = item,
			cash = if type(info.Cash) == "number" then info.Cash else nil,
			model = model,
			root = root,
			from = to + Vector3.new(0, 1, 0),
			to = to,
			start = now,
			state = "out",
			inStart = 0,
			inFrom = to,
			report = true,
			pouch = pouch,
			baseSize = if pouch then root.Size else nil,
		}
		drops[d.id] = d
		if pouch and not Ui.reducedMotion() then
			-- pops out of the pile from tiny to full size
			local full = root.Size
			root.Size = full * 0.2
			TweenService
				:Create(root, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = full })
				:Play()
		end
		local icon = root:FindFirstChild("Icon")
		local pop = icon and icon:FindFirstChild("Item")
		local scale = pop and pop:FindFirstChild("Pop") :: UIScale?
		if scale and not Ui.reducedMotion() then
			scale.Scale = 0.2
			TweenService
				:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
				:Play()
		end
	end
end

local function onAuto(ids: any)
	if type(ids) ~= "table" then
		return
	end
	local now = os.clock()
	for _, id in ids do
		local d = type(id) == "number" and drops[id] or nil
		if d then
			startIn(d, false, now)
		end
	end
end

local function step()
	local now = os.clock()
	local root = rootPart()
	local range = (Players.LocalPlayer:GetAttribute("CoinMagnet") or 7) :: number
	for id, d in drops do
		if d.state == "out" then
			local t = math.clamp((now - d.start) / FLY_OUT, 0, 1)
			local p = d.from:Lerp(d.to, t) + Vector3.new(0, math.sin(t * math.pi) * 5, 0)
			place(d, p - Vector3.new(0, HOVER * (1 - t), 0), now)
			if t >= 1 then
				d.state = "ground"
				landed(d)
			end
		elseif d.state == "ground" then
			place(d, d.to, now)
			if root then
				local off = root.Position - d.to
				if Vector2.new(off.X, off.Z).Magnitude <= range then
					startIn(d, true, now)
				end
			end
		else
			local t = math.clamp((now - d.inStart) / FLY_IN, 0, 1)
			local target = if root then root.Position else d.inFrom
			local spin = if d.pouch then CFrame.Angles(0, now * 9, 0) else CFrame.identity
			d.root.CFrame = CFrame.new(d.inFrom:Lerp(target, t * t)) * spin
			if d.pouch and d.baseSize then
				d.root.Size = d.baseSize * (1 - 0.55 * t)
			end
			if t >= 1 then
				if d.report then
					table.insert(toReport, id)
				end
				pickedUp(d)
				d.model:Destroy()
				drops[id] = nil
			end
		end
	end
	if #toReport > 0 and now - lastReport >= REPORT_EVERY then
		lastReport = now
		local batch = toReport
		toReport = {}
		Net.event("ItemsCollect"):FireServer(batch)
	end
end

-- Treasure Map ----------------------------------------------------------------------------

local marker: Model? = nil

local function clearMarker()
	if marker then
		marker:Destroy()
		marker = nil
	end
end

local function showMarker(at: Vector3)
	clearMarker()
	local model = Instance.new("Model")
	model.Name = "TreasureX"
	local red = Color3.fromRGB(255, 60, 70)
	local beam = part({
		Name = "Beam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(60, 1.2, 1.2),
		CFrame = CFrame.new(at + Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = red,
		Material = Enum.Material.Neon,
		Transparency = 0.45,
	})
	beam.Parent = model
	local anchor = part({
		Name = "Anchor",
		Size = Vector3.new(0.4, 0.4, 0.4),
		Transparency = 1,
		CFrame = CFrame.new(at + Vector3.new(0, 3, 0)),
	})
	anchor.Parent = model
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(84, 84)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 1000
	gui.Adornee = anchor
	gui.Parent = anchor
	local x = Instance.new("TextLabel")
	x.Size = UDim2.fromScale(1, 0.7)
	x.BackgroundTransparency = 1
	x.Text = "X"
	x.TextScaled = true
	x.TextColor3 = red
	x.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
	x.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = x
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 0.3)
	label.Position = UDim2.fromScale(0, 0.7)
	label.BackgroundTransparency = 1
	label.Text = "TREASURE"
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
	label.Parent = gui
	local stroke2 = stroke:Clone()
	stroke2.Thickness = 2
	stroke2.Parent = label
	model.Parent = folder
	marker = model
end

-- A quick burst of sparkles and a sound where something big happened.
local function burst(at: Vector3, color: Color3, count: number, speed: number)
	local p = part({ Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(at) })
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLE
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	e.LightEmission = 0.6
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -20, 0)
	e.Size = NumberSequence.new(0.7, 0)
	e.Parent = p
	p.Parent = folder
	e:Emit(count)
	task.delay(1.5, function()
		p:Destroy()
	end)
end

-- Coin pouch pickup: gold stars and coins burst out of you with a quick gold flash.
pouchPop = function(at: Vector3)
	local p = part({ Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(at) })
	local stars = Instance.new("ParticleEmitter")
	stars.Texture = STAR
	stars.Color = ColorSequence.new(Color3.fromRGB(255, 255, 230), POUCH_COLOR)
	stars.LightEmission = 1
	stars.LightInfluence = 0
	stars.Rate = 0
	stars.Lifetime = NumberRange.new(0.4, 0.7)
	stars.Speed = NumberRange.new(9, 16)
	stars.SpreadAngle = Vector2.new(180, 180)
	stars.Drag = 4
	stars.Rotation = NumberRange.new(0, 360)
	stars.RotSpeed = NumberRange.new(-180, 180)
	stars.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
	stars.Parent = p
	p.Parent = folder
	stars:Emit(14)
	-- a few real coins spray up and fall
	for i = 1, 6 do
		local model = AssetLibrary.get("Coin_Cash")
		local coin = model and model:FindFirstChild("Body")
		if not (coin and coin:IsA("BasePart")) then
			if model then
				model:Destroy()
			end
			break
		end
		coin.Parent = nil
		model:Destroy()
		coin.Anchored = true
		coin.CanCollide = false
		coin.CanQuery = false
		coin.CanTouch = false
		coin.CastShadow = false
		coin.Size *= 0.7
		local a = (i / 6) * math.pi * 2 + math.random() * 0.6
		local out = Vector3.new(math.cos(a), 0, math.sin(a)) * (2 + math.random() * 1.5)
		local start = os.clock()
		coin.CFrame = CFrame.new(at)
		coin.Parent = folder
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local t = (os.clock() - start) / 0.55
			if t >= 1 then
				conn:Disconnect()
				coin:Destroy()
				return
			end
			local pos = at + out * t + Vector3.new(0, 5 * t - 7 * t * t, 0)
			coin.CFrame = CFrame.new(pos) * CFrame.Angles(0, t * 12 + a, 0)
			coin.Transparency = math.max(0, (t - 0.7) / 0.3)
		end)
	end
	local flash = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.8,
		CFrame = CFrame.new(at),
		Color = Color3.fromRGB(255, 240, 150),
		Material = Enum.Material.Neon,
		Transparency = 0.1,
	})
	flash.Parent = folder
	TweenService:Create(flash, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * 3.4,
		Transparency = 1,
	}):Play()
	task.delay(1, function()
		flash:Destroy()
		p:Destroy()
	end)
end

local function onTreasure(pos: any, dugAt: any)
	if typeof(pos) == "Vector3" then
		showMarker(pos)
		return
	end
	clearMarker()
	if typeof(dugAt) == "Vector3" then
		burst(dugAt + Vector3.new(0, 2, 0), Color3.fromRGB(255, 205, 40), 60, 30)
		Ui.sound("RareReveal")
	end
end

-- Leaf Bomb -------------------------------------------------------------------------------

local function onLeafBomb(at: any, radius: any)
	if typeof(at) ~= "Vector3" or type(radius) ~= "number" then
		return
	end
	local ring = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 2, 2),
		CFrame = CFrame.new(at - Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 200, 90),
		Material = Enum.Material.Neon,
		Transparency = 0.2,
	})
	ring.Parent = folder
	local grow = TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, radius * 2, radius * 2),
		Transparency = 1,
	})
	grow:Play()
	grow.Completed:Connect(function()
		ring:Destroy()
	end)
	burst(at, Color3.fromRGB(139, 224, 78), 90, 45)
	Ui.sound("HatchBoom")
end

function DropController:Init(controllers)
	C = controllers
	folder = Instance.new("Folder")
	folder.Name = "MyDrops"
	folder.Parent = Workspace
end

function DropController:Start()
	Net.event("ItemsDropped").OnClientEvent:Connect(onDropped)
	Net.event("ItemsAuto").OnClientEvent:Connect(onAuto)
	Net.event("Treasure").OnClientEvent:Connect(onTreasure)
	Net.event("LeafBomb").OnClientEvent:Connect(onLeafBomb)
	RunService.RenderStepped:Connect(step)
end

return DropController
