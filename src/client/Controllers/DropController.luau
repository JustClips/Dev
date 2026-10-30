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
local HOVER = 1.6 -- studs above the ground
local REPORT_EVERY = 0.15
local POUCH_COLOR = Color3.fromRGB(255, 205, 40)
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

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

-- The drop: an invisible root with the icon on a billboard, a glow ring and maybe a beam.
local function build(item: string?): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Drop"
	local color = colorOf(item)
	local rarity = rarityOf(item)
	local root = part({ Name = "Root", Size = Vector3.new(0.4, 0.4, 0.4), Transparency = 1 })
	root.Parent = model
	model.PrimaryPart = root
	local big = rarity == "Epic" or rarity == "Legendary"
	local gui = Instance.new("BillboardGui")
	gui.Name = "Icon"
	gui.Size = UDim2.fromScale(if big then 3.4 else 2.6, if big then 3.4 else 2.6)
	gui.LightInfluence = 0
	gui.MaxDistance = 220
	gui.Adornee = root
	gui.Parent = root
	local image = Instance.new("ImageLabel")
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.Image = AssetLibrary.image(if item and Items.ById[item] then Items.ById[item].Icon else "Icon_Cash")
	image.Parent = gui
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = image
	-- Glow ring on the ground (a flat neon disc).
	local ring = part({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 3, 3),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.45,
	})
	ring.Parent = model
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = SPARKLE
	sparkle.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	sparkle.LightEmission = 0.7
	sparkle.Rate = if rarity == "Common" then 2 else 6
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
	return model, root
end

local function place(d: Drop, at: Vector3, now: number)
	local bob = math.sin(now * 3 + d.id) * 0.25
	d.root.CFrame = CFrame.new(at + Vector3.new(0, HOVER + bob, 0))
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

local function landed(d: Drop)
	local rarity = rarityOf(d.item)
	if rarity ~= "Common" then
		Ui.sound(if rarity == "Epic" or rarity == "Legendary" then "RareReveal" else "Sparkle")
	else
		Ui.sound("Pop", 1.2)
	end
end

local function pickedUp(d: Drop)
	if d.cash then
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
		local model, root = build(item)
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
		}
		drops[d.id] = d
		local pop = (root:FindFirstChild("Icon") :: BillboardGui):FindFirstChildOfClass("ImageLabel")
		local scale = pop and pop:FindFirstChild("Pop") :: UIScale?
		if scale and not Ui.reducedMotion() then
			scale.Scale = 0.2
			TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
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
			d.root.CFrame = CFrame.new(d.inFrom:Lerp(target, t * t))
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
	local anchor = part({ Name = "Anchor", Size = Vector3.new(0.4, 0.4, 0.4), Transparency = 1, CFrame = CFrame.new(at + Vector3.new(0, 3, 0)) })
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
