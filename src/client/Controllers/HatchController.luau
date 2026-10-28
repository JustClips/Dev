--!strict
-- Eggs growing in the pet parks, and opening them.
--
-- Growing (every park, every player): an egg starts small and grows until it's ready
-- (Eggs.growScale). It wobbles now and then, more often and harder as it gets close, and a
-- bar under its timer fills up. A ready egg bounces and glows in a beam of its colour.
--
-- Opening, when you're near the egg (your camera stays yours): the egg wobbles harder and
-- harder, swells up and turns white, then bursts (flash, rays, sparkles, shockwave) and the
-- pet pops out and dances. The card at the bottom shows what it is (rarity, name, weight,
-- cash) with Place on base / Keep in bag. Far from your base the same show plays in a window
-- in the middle of the screen. Click or tap to skip ahead. Rarer pets get a longer build up,
-- a bigger burst and a fanfare.
--
-- Owner prompts on growing eggs: Skip Hatch (Robux) while growing, Open when ready.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AlienModel = require(Shared.AlienModel)
local AssetLibrary = require(Shared.AssetLibrary)
local Aliens = require(Shared.Config.Aliens)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Weights = require(Shared.Config.Weights)
local World = require(Shared.Config.World)

local WORLD_RANGE = 140 -- studs from the egg to open it in the world (else on screen)
local GROW_RANGE = 220 -- studs from the camera to animate growing eggs
local REVEAL_SECONDS = 2.6
local WHITE = Color3.new(1, 1, 1)

local HatchController = {}

local C: any
local gui: ScreenGui
local stage: Frame
local stageScale: UIScale
local viewport: ViewportFrame
local worldModel: WorldModel
local rays: ImageLabel
local glow: ImageLabel
local flash: Frame
local card: Frame
local cardScale: UIScale
local rarityLabel: TextLabel
local nameLabel: TextLabel
local infoLabel: TextLabel
local newBadge: Frame
local hintLabel: TextLabel
local choice: Frame
local confetti: Frame
local confettiTemplate: ImageLabel
local chosen: string? = nil
local queue = {}
local playing = false
local skipRequested = false

------------------------------------------------------------------ small helpers

local function waitOrSkip(seconds: number)
	local deadline = os.clock() + seconds
	while os.clock() < deadline and not skipRequested do
		task.wait()
	end
end

-- Runs fn(alpha 0-1) every frame for `seconds` (cut short by a skip unless `always`).
local function animate(seconds: number, fn: (number) -> (), always: boolean?)
	local start = os.clock()
	while true do
		local alpha = math.clamp((os.clock() - start) / math.max(seconds, 0.001), 0, 1)
		if skipRequested and not always then
			alpha = 1
		end
		fn(alpha)
		if alpha >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

local function backOut(t: number): number
	local s = 1.9
	t -= 1
	return t * t * ((s + 1) * t + s) + 1
end

type PartLook = { part: BasePart, color: Color3, material: Enum.Material, texture: string? }

-- Remembers each part's look, so an egg can fade to white.
local function looks(model: Model): { PartLook }
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			table.insert(list, {
				part = d,
				color = d.Color,
				material = d.Material,
				texture = if d:IsA("MeshPart") then d.TextureID else nil,
			})
		end
	end
	return list
end

local function whiten(list: { PartLook }, t: number)
	for _, look in list do
		look.part.Color = look.color:Lerp(WHITE, t)
		if t > 0.55 and look.part.Material ~= Enum.Material.Neon then
			look.part.Material = Enum.Material.Neon
			if look.texture and look.part:IsA("MeshPart") then
				look.part.TextureID = ""
			end
			-- Painted-on looks would hide the white glow.
			for _, child in look.part:GetChildren() do
				if child:IsA("SurfaceAppearance") or child:IsA("Decal") or child:IsA("Texture") then
					child:Destroy()
				end
			end
		end
	end
end

local function rarityOf(name: string)
	return Eggs.ByName[name] or Eggs.Rarities[1]
end

-- Sparkles flying out from a point on screen.
local function burstConfetti(at: Vector2, color: Color3, count: number)
	for i = 1, count do
		local piece = confettiTemplate:Clone()
		piece.Visible = true
		piece.Name = "Piece"
		piece.Position = UDim2.fromOffset(at.X, at.Y)
		local size = math.random(14, 34) * Ui.scale()
		piece.Size = UDim2.fromOffset(size, size)
		local pick = i % 3
		piece.ImageColor3 = if pick == 0 then color elseif pick == 1 then WHITE else Color3.fromRGB(255, 214, 90)
		piece.Rotation = math.random(0, 90)
		piece.Parent = confetti
		local angle = math.random() * math.pi * 2
		local dist = math.random(140, 380) * Ui.scale()
		local goal = at + Vector2.new(math.cos(angle) * dist, math.sin(angle) * dist * 0.8 + 60)
		local time = math.random(55, 95) / 100
		TweenService:Create(piece, TweenInfo.new(time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(goal.X, goal.Y),
			Rotation = piece.Rotation + math.random(-180, 180),
		}):Play()
		TweenService:Create(piece, TweenInfo.new(time * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, time * 0.5), {
			ImageTransparency = 1,
			Size = UDim2.fromOffset(size * 0.3, size * 0.3),
		}):Play()
		task.delay(time + 0.1, function()
			piece:Destroy()
		end)
	end
end

local function flashScreen(strength: number, seconds: number)
	flash.BackgroundTransparency = 1 - strength
	TweenService:Create(flash, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

-- Where your pet park is on screen (the screen-mode pet flies there after the reveal).
local function parkScreenPosition(): UDim2
	local camera = Workspace.CurrentCamera
	local data = State.data
	if camera and data and data.BaseIndex and data.BaseIndex ~= 0 then
		local center = (World.Base.ParkMin + World.Base.ParkMax) / 2
		local world = World.baseCFrame(data.BaseIndex) * Vector3.new(center.X, 2, center.Y)
		local point, visible = camera:WorldToViewportPoint(world)
		if visible then
			return UDim2.fromOffset(point.X, point.Y)
		end
	end
	return UDim2.fromScale(0.5, 1.2)
end

-- Where the opened egg sat in the park, if we know.
local function eggSpot(info): CFrame?
	local data = State.data
	if not info.X or not info.Z or not data or not data.BaseIndex or data.BaseIndex == 0 then
		return nil
	end
	return World.baseCFrame(data.BaseIndex) * CFrame.new(info.X, 0.2, info.Z)
end

------------------------------------------------------------------ the card

local function showCard(info)
	local rarity = rarityOf(info.Rarity)
	local petRarityKg = Weights.petKg(info.Rarity)
	local weight = info.Weight or petRarityKg
	local mult = Weights.incomeMult(info.Rarity, info.Weight)
	local class = Weights.classFor(mult)
	rarityLabel.Text = string.upper((if info.Huge then "Huge " else "") .. info.Rarity)
	rarityLabel.TextColor3 = rarity.Color
	nameLabel.Text = (if info.Huge then "HUGE " else "") .. AlienModel.displayName(info.AlienId, info.Mutation)
	nameLabel.TextColor3 = rarity.Color
	local def = Aliens.ById[info.AlienId]
	local income = info.Income or (def and def.Income or 0)
	local hex = class.Color:ToHex()
	infoLabel.Text = `<font color="#{hex}">{Weights.format(weight)} ({class.Name})</font>   +{Format.cash(income)}/s`
	newBadge.Visible = info.IsNew == true
	choice.Visible = false
	hintLabel.Text = if UserInputService.TouchEnabled then "Tap to skip" else "Click to skip"
	hintLabel.Visible = true
	card.Visible = true
	cardScale.Scale = Ui.scale() * 0.6
	TweenService:Create(cardScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = Ui.scale() }):Play()
end

local function hideCard()
	local tween = TweenService:Create(cardScale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.01 })
	tween:Play()
	tween.Completed:Wait()
	card.Visible = false
end

-- Place on base / Keep in bag (only offered with a free slot). Returns the choice.
local function askPlace(info): string
	if not (info.FreeSlot and info.Uid) then
		C.HudController:Toast("Added to your bag (press 3 or B).", "Info")
		return "Keep"
	end
	hintLabel.Visible = false
	chosen = nil
	choice.Visible = true
	local deadline = os.clock() + 8
	while chosen == nil and os.clock() < deadline do
		task.wait()
	end
	choice.Visible = false
	if chosen == "Place" then
		local ok, message = Net.func("Inventory"):InvokeServer("PlacePet", info.Uid)
		if not ok and message then
			C.HudController:Toast(message, "Bad")
		end
		return "Place"
	end
	C.HudController:Toast("Saved in your bag (press 3 or B).", "Info")
	return "Keep"
end

------------------------------------------------------------------ the show

type Scene = {
	world: boolean,
	parent: Instance,
	camera: Camera,
	origin: CFrame, -- where the egg rests (pivot at its bottom)
	eggScale: number,
	fx: Folder?,
}

local function makeNest(scene: Scene, scale: number): BasePart
	local nest = Instance.new("Part")
	nest.Name = "Nest"
	nest.Shape = Enum.PartType.Cylinder
	nest.Size = Vector3.new(0.5, 3.4 * scale, 3.4 * scale)
	nest.CFrame = scene.origin * CFrame.new(0, -0.1, 0) * CFrame.Angles(0, 0, math.rad(90))
	nest.Color = Color3.fromRGB(245, 210, 110)
	nest.Material = Enum.Material.Fabric
	nest.Anchored = true
	nest.CanCollide = false
	nest.CanQuery = false
	nest.CanTouch = false
	nest.Parent = scene.parent
	return nest
end

-- A flat glowing ring that races outwards along the ground.
local function shockwave(scene: Scene, color: Color3, radius: number)
	local ring = Instance.new("Part")
	ring.Name = "Shockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = scene.origin * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.25
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Parent = scene.parent
	TweenService:Create(ring, TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	task.delay(0.6, function()
		ring:Destroy()
	end)
end

-- Spinning sunburst + glow behind the pet (world: a billboard just behind it).
local function worldRays(scene: Scene, center: Vector3, size: number, color: Color3): (BillboardGui, ImageLabel, ImageLabel)
	local anchor = Instance.new("Part")
	anchor.Name = "RaysAnchor"
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	local back = (center - scene.camera.CFrame.Position).Unit
	anchor.CFrame = CFrame.new(center + back * size * 0.6)
	anchor.Parent = scene.parent
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromScale(size * 2.6, size * 2.6)
	board.LightInfluence = 0
	board.Adornee = anchor
	board.Parent = anchor
	local g = Instance.new("ImageLabel")
	g.BackgroundTransparency = 1
	g.Size = UDim2.fromScale(0.8, 0.8)
	g.Position = UDim2.fromScale(0.5, 0.5)
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Image = AssetLibrary.image("Glow")
	g.ImageColor3 = color
	g.ImageTransparency = 1
	g.Parent = board
	local r = Instance.new("ImageLabel")
	r.BackgroundTransparency = 1
	r.Size = UDim2.fromScale(1, 1)
	r.Image = AssetLibrary.image("Rays")
	r.ImageColor3 = color
	r.ImageTransparency = 1
	r.Parent = board
	return board, r, g
end

local function sparkleBurst(scene: Scene, at: Vector3, color: Color3, count: number)
	local holder = Instance.new("Attachment")
	local anchor = Instance.new("Part")
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CFrame = CFrame.new(at)
	anchor.Parent = scene.parent
	holder.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = AssetLibrary.image("Sparkle")
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.4, color),
		ColorSequenceKeypoint.new(1, color),
	})
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.3) })
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(10, 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -18, 0)
	emitter.Drag = 2
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-200, 200)
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(count)
	task.delay(1.6, function()
		anchor:Destroy()
	end)
end

local function play(info)
	playing = true
	skipRequested = false
	local rarity = rarityOf(info.Rarity)
	local eggRarity = info.EggRarity or info.Rarity
	local order = Eggs.order(info.Rarity)
	local big = info.Huge == true or info.Mutation ~= nil or order >= Eggs.order("Epic")
	local quick = #queue > 0 -- more eggs waiting: a shorter show
	local tempo = if quick then 0.55 else 1

	-- World or screen?
	local camera = Workspace.CurrentCamera :: Camera
	local spot = eggSpot(info)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local inWorld = spot ~= nil and root ~= nil and (root.Position - spot.Position).Magnitude < WORLD_RANGE and not Ui.reducedMotion()

	local scene: Scene
	if inWorld then
		local fx = Instance.new("Folder")
		fx.Name = "HatchShow"
		fx.Parent = Workspace
		local eggScale = Weights.visualScale(Weights.eggMult(eggRarity, info.EggWeight)) * 1.25
		scene = {
			world = true,
			parent = fx,
			camera = camera,
			origin = (spot :: CFrame) * CFrame.new(0, 0.35, 0),
			eggScale = eggScale,
			fx = fx,
		}
		stage.Visible = false
	else
		worldModel:ClearAllChildren()
		scene = {
			world = false,
			parent = worldModel,
			camera = viewport.CurrentCamera :: Camera,
			origin = CFrame.new(),
			eggScale = 1,
		}
		stage.Visible = true
		stage.Position = UDim2.fromScale(0.5, 0.45)
		stageScale.Scale = Ui.scale()
		rays.ImageColor3 = rarity.Color
		glow.ImageColor3 = rarity.Color
		rays.ImageTransparency = 1
		glow.ImageTransparency = 1
	end
	card.Visible = false
	gui.Enabled = true

	-- 1. The egg (a local copy where the real one sat), on its nest. Hide the real one if
	-- it's still there for a moment.
	if info.EggUid and State.data and State.data.BaseIndex then
		local moon = Workspace:FindFirstChild("Moon")
		local bases = moon and moon:FindFirstChild("Bases")
		local base = bases and bases:FindFirstChild("Base" .. State.data.BaseIndex)
		local folder = base and base:FindFirstChild("Hatching")
		local old = folder and folder:FindFirstChild(info.EggUid)
		if old then
			for _, d in old:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = 1
				elseif d:IsA("BillboardGui") or d:IsA("ProximityPrompt") then
					d.Enabled = false
				end
			end
		end
	end
	local egg = AssetLibrary.egg(eggRarity)
	egg.Name = "OpeningEgg"
	local eggLooks = looks(egg)
	egg:ScaleTo(scene.eggScale)
	egg:PivotTo(scene.origin)
	egg.Parent = scene.parent
	local nest = if scene.world then makeNest(scene, scene.eggScale / 1.25) else nil
	local _, eggSize = egg:GetBoundingBox()
	local eggHeight = math.max(eggSize.Y, 1.5)
	local focus = scene.origin.Position + Vector3.new(0, eggHeight * 0.55, 0)
	local light = Instance.new("PointLight")
	light.Color = rarityOf(eggRarity).Color
	light.Brightness = 0
	light.Range = eggHeight * 5
	light.Parent = egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")
	local highlight: Highlight? = nil
	if scene.world then
		local h = Instance.new("Highlight")
		h.FillColor = WHITE
		h.FillTransparency = 1
		h.OutlineTransparency = 1
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Adornee = egg
		h.Parent = egg
		highlight = h
	end

	-- The player keeps their camera: the show plays where the egg sits.
	if not scene.world then
		scene.camera.CFrame = CFrame.lookAt(Vector3.new(0, eggHeight * 0.75, -eggHeight * 2.7), Vector3.new(0, eggHeight * 0.48, 0))
		Ui.popIn(gui)
	end

	-- 2. Wobbles, each harder than the last (more of them for rare pets).
	local bursts = if quick then 2 elseif big then 4 else 3
	for i = 1, bursts do
		if skipRequested then
			break
		end
		Ui.sound("Wobble", 0.9 + i * 0.12)
		local amp = math.rad(8 + i * 6)
		local length = 0.38 * tempo
		animate(length, function(t)
			local fade = 1 - t
			local angle = math.sin(t * math.pi * 6) * amp * fade
			local hop = math.sin(t * math.pi) * eggHeight * 0.08 * i
			egg:PivotTo(scene.origin * CFrame.new(0, hop, 0) * CFrame.Angles(angle * 0.4, 0, angle))
		end)
		egg:PivotTo(scene.origin)
		waitOrSkip((0.22 - i * 0.03) * tempo)
	end

	-- 3. Charge: swells up, shakes, turns white and glows.
	Ui.sound("Charge")
	animate(0.6 * tempo, function(t)
		local shake = math.rad(5) * t
		egg:ScaleTo(scene.eggScale * (1 + 0.38 * t * t))
		egg:PivotTo(scene.origin * CFrame.Angles(math.random(-100, 100) / 100 * shake, 0, math.random(-100, 100) / 100 * shake))
		whiten(eggLooks, t)
		light.Brightness = 8 * t
		if highlight then
			highlight.FillTransparency = 1 - t * 0.9
		end
		if not scene.world then
			glow.ImageTransparency = 1 - t * 0.7
		end
	end, true)

	-- 4. Burst!
	Ui.sound("Crack")
	Ui.sound("Hatch")
	flashScreen(if big then 1 else 0.75, if big then 0.9 else 0.55)
	local screenPoint = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y * 0.45)
	if scene.world then
		local point, visible = camera:WorldToViewportPoint(focus)
		if visible then
			screenPoint = Vector2.new(point.X, point.Y)
		end
		shockwave(scene, rarity.Color, math.max(10, eggHeight * 5))
		sparkleBurst(scene, focus, rarity.Color, 30 + order * 8)
	end
	burstConfetti(screenPoint, rarity.Color, if big then 30 else 18)
	egg:Destroy()
	if nest then
		TweenService:Create(nest, TweenInfo.new(0.6), { Transparency = 1 }):Play()
	end

	-- 5. The pet pops out, faces you and dances.
	local model = AssetLibrary.alien(info.AlienId, info.Mutation)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local petScale = Weights.visualScale(Weights.incomeMult(info.Rarity, info.Weight)) * (if info.Huge then Aliens.HugeScale else 1)
	local face: CFrame
	if scene.world then
		local look = Vector3.new(camera.CFrame.Position.X, scene.origin.Position.Y, camera.CFrame.Position.Z)
		face = CFrame.lookAt(scene.origin.Position, look)
	else
		face = CFrame.new() -- the window camera looks at the pet's front
	end
	model:PivotTo(face)
	model.Parent = scene.parent
	model:ScaleTo(0.05)
	local _, size3 = model:GetBoundingBox()
	local happy = AssetLibrary.loadTrack(model, "Pet_Happy")
	local idle = AssetLibrary.loadTrack(model, "Pet_Idle")
	if idle then
		idle:Play()
	end
	if happy then
		happy:Play(0.05)
	end
	animate(0.42, function(t)
		model:ScaleTo(math.max(0.05, petScale * backOut(t)))
		model:PivotTo(face * CFrame.new(0, math.sin(t * math.pi) * 1.2, 0))
	end, true)
	model:PivotTo(face)
	local finalSize = size3 / 0.05 * petScale
	local petSize = math.max(finalSize.X, finalSize.Y, finalSize.Z, 1.5)
	Ui.sound(if big then "RareReveal" else "Reveal")
	Ui.sound("Sparkle")

	-- Rays behind the pet.
	local raysImage: ImageLabel
	local glowImage: ImageLabel
	if scene.world then
		local center = scene.origin.Position + Vector3.new(0, petSize * 0.45, 0)
		local _, r, g = worldRays(scene, center, petSize, rarity.Color)
		raysImage, glowImage = r, g
	else
		raysImage, glowImage = rays, glow
		scene.camera.CFrame = CFrame.lookAt(Vector3.new(petSize * 0.35, petSize * 0.7, -petSize * 2.4), Vector3.new(0, petSize * 0.42, 0))
	end
	TweenService:Create(raysImage, TweenInfo.new(0.3), { ImageTransparency = if big then 0.15 else 0.35 }):Play()
	TweenService:Create(glowImage, TweenInfo.new(0.3), { ImageTransparency = 0.3 }):Play()
	local spin = RunService.RenderStepped:Connect(function(dt)
		raysImage.Rotation = (raysImage.Rotation + dt * 25) % 360
	end)

	skipRequested = false
	showCard(info)
	waitOrSkip(REVEAL_SECONDS * tempo)
	local placed = askPlace(info)

	-- 6. Wrap up: the pet hops off (to the park or your bag).
	TweenService:Create(raysImage, TweenInfo.new(0.3), { ImageTransparency = 1 }):Play()
	TweenService:Create(glowImage, TweenInfo.new(0.3), { ImageTransparency = 1 }):Play()
	task.spawn(hideCard)
	if scene.world then
		Ui.sound("Pop")
		animate(0.3, function(t)
			model:ScaleTo(math.max(0.02, petScale * (1 - t)))
			model:PivotTo(face * CFrame.new(0, t * 2, 0))
		end, true)
		if placed == "Place" then
			sparkleBurst(scene, scene.origin.Position + Vector3.new(0, 1, 0), rarity.Color, 12)
		end
		task.wait(0.2)
		task.delay(1.7, function()
			if scene.fx then
				scene.fx:Destroy()
			end
		end)
	else
		local fly = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(stage, fly, { Position = parkScreenPosition() }):Play()
		local shrink = TweenService:Create(stageScale, fly, { Scale = 0.05 })
		shrink:Play()
		shrink.Completed:Wait()
		worldModel:ClearAllChildren()
	end
	spin:Disconnect()
	stage.Visible = false
	gui.Enabled = false
	playing = false
end

local function pump()
	if playing then
		return
	end
	local info = table.remove(queue, 1)
	if info then
		task.spawn(function()
			local ok, err = pcall(play, info)
			if not ok then
				warn("[HatchController] " .. tostring(err))
				gui.Enabled = false
				card.Visible = false
				playing = false
			end
			pump()
		end)
	end
end

------------------------------------------------------------------ growing eggs

type Growing = {
	base: CFrame,
	nextWobble: number,
	wobbleAt: number,
	beam: BasePart?,
	label: BillboardGui?,
	fill: Frame?,
}
local growing: { [Model]: Growing } = {}

local function readyBeam(egg: Model, color: Color3): BasePart
	local _, size = egg:GetBoundingBox()
	local beam = Instance.new("Part")
	beam.Name = "ReadyBeam"
	beam.Shape = Enum.PartType.Cylinder
	beam.Size = Vector3.new(16, size.X * 0.9, size.X * 0.9)
	beam.CFrame = egg:GetPivot() * CFrame.new(0, 8, 0) * CFrame.Angles(0, 0, math.rad(90))
	beam.Color = color
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.82
	beam.CastShadow = false
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 2
	light.Range = 12
	light.Parent = beam
	beam.Parent = Workspace
	return beam
end

local function track(egg: Instance)
	if not egg:IsA("Model") or growing[egg] then
		return
	end
	local entry: Growing = {
		base = egg:GetPivot(),
		nextWobble = os.clock() + math.random() * 3,
		wobbleAt = -10,
	}
	local primary = egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")
	entry.label = primary and primary:FindFirstChildOfClass("BillboardGui") or nil
	if entry.label then
		entry.fill = entry.label:FindFirstChild("Fill", true) :: Frame?
	end
	growing[egg] = entry
	egg.Destroying:Once(function()
		if entry.beam then
			entry.beam:Destroy()
		end
		growing[egg] = nil
	end)
end

local function updateGrowing()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local clock = os.clock()
	local camPos = camera.CFrame.Position
	for egg, g in growing do
		if not egg.Parent then
			continue
		end
		local endsAt = egg:GetAttribute("EndsAt") or 0
		local progress = Eggs.progress(egg:GetAttribute("StartsAt"), endsAt, now)
		local grow = Eggs.growScale(progress)
		if g.fill then
			g.fill.Size = UDim2.fromScale(progress, 1)
		end
		if g.label then
			local height = egg:GetAttribute("LabelHeight") or 3
			g.label.StudsOffsetWorldSpace = Vector3.new(0, height * grow + 0.8 * (1 - grow), 0)
		end
		if (g.base.Position - camPos).Magnitude > GROW_RANGE then
			continue
		end
		local full = egg:GetAttribute("FullScale") or 1
		local target = full * grow
		if math.abs(egg:GetScale() - target) > 0.003 then
			egg:ScaleTo(target)
		end
		local ready = progress >= 1
		-- Wobble now and then: more often and harder as it gets close.
		if clock >= g.nextWobble then
			g.wobbleAt = clock
			local gap = if ready then 1.6 else 6 - 4.5 * progress
			g.nextWobble = clock + gap * (0.7 + math.random() * 0.6)
		end
		local w = clock - g.wobbleAt
		local offset = CFrame.new()
		if w < 0.5 then
			local amp = math.rad(if ready then 14 else 3 + 9 * progress)
			local angle = math.sin(w / 0.5 * math.pi * 4) * amp * (1 - w / 0.5)
			offset = CFrame.Angles(angle * 0.4, 0, angle)
		end
		if ready then
			local hop = math.abs(math.sin(clock * 3.2)) * 0.35 * grow
			offset = CFrame.new(0, hop, 0) * offset
			if not g.beam then
				g.beam = readyBeam(egg, rarityOf(egg:GetAttribute("Rarity") :: string).Color)
			end
		elseif g.beam then
			g.beam:Destroy()
			g.beam = nil
		end
		egg:PivotTo(g.base * offset)
	end
end

------------------------------------------------------------------ timers and prompts

local function updateTimers()
	local now = State.now()
	for _, label in CollectionService:GetTagged("HatchTimer") do
		if label:IsA("TextLabel") then
			local endsAt = label:GetAttribute("EndsAt") or 0
			local left = endsAt - now
			label.Text = if left > 0 then Format.time(left) else "READY!"
		end
	end
end

local function invoke(action: string, arg: string?)
	local ok, message = Net.func("Inventory"):InvokeServer(action, arg)
	if message and message ~= "" then
		C.HudController:Toast(message, if ok then "Good" else "Bad")
	end
end

-- Owner prompts on growing eggs: Skip (Robux) while growing, Open when ready.
local function updateEggPrompts()
	local me = Players.LocalPlayer.UserId
	local now = State.now()
	for _, egg in CollectionService:GetTagged("HatchingEgg") do
		if not egg:IsA("Model") or egg:GetAttribute("OwnerUserId") ~= me then
			continue
		end
		local root = egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")
		if not root then
			continue
		end
		local prompt = root:FindFirstChild("EggPrompt") :: ProximityPrompt?
		if not prompt then
			local p = Instance.new("ProximityPrompt")
			p.Name = "EggPrompt"
			p.MaxActivationDistance = 12
			p.RequiresLineOfSight = false
			p.HoldDuration = 0.25
			p.Parent = root
			local uid = egg:GetAttribute("Uid") :: string
			p.Triggered:Connect(function()
				if p:GetAttribute("Ready") then
					invoke("OpenEgg", uid)
				else
					invoke("SkipHatch", uid)
				end
			end)
			prompt = p
		end
		local ready = (egg:GetAttribute("EndsAt") or 0) <= now
		local rarity = egg:GetAttribute("Rarity") :: string
		local p = prompt :: ProximityPrompt
		p:SetAttribute("Ready", ready)
		p.ObjectText = `{rarity} Egg`
		if ready then
			p.ActionText = "Open"
			p.Enabled = true
		else
			local product = Products.ProductByKey["SkipHatch" .. rarity]
			p.ActionText = if product and product.Id ~= 0 then `Skip Hatch {Ui.ROBUX}{product.Price}` else "Growing..."
			p.Enabled = product ~= nil and product.Id ~= 0
		end
	end
end

------------------------------------------------------------------ lifecycle

function HatchController:Init(controllers)
	C = controllers
	gui = Ui.screen("Hatch")
	stage = Ui.find(gui, "Stage")
	stageScale = Ui.find(gui, "Stage.AutoScale")
	viewport = Ui.find(gui, "Stage.Viewport")
	rays = Ui.find(gui, "Stage.Rays")
	glow = Ui.find(gui, "Stage.Glow")
	-- Animations only play inside a WorldModel.
	worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport
	flash = Ui.find(gui, "Flash")
	card = Ui.find(gui, "Card")
	cardScale = Ui.find(gui, "Card.AutoScale")
	rarityLabel = Ui.find(card, "Rarity")
	nameLabel = Ui.find(card, "Name")
	infoLabel = Ui.find(card, "Info")
	newBadge = Ui.find(card, "New")
	hintLabel = Ui.find(card, "Hint")
	choice = Ui.find(card, "Choice")
	confetti = Ui.find(gui, "Confetti")
	confettiTemplate = Ui.find(confetti, "Template")
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

function HatchController:Start()
	Net.event("HatchCompleted").OnClientEvent:Connect(function(info)
		table.insert(queue, info)
		pump()
	end)
	UserInputService.InputBegan:Connect(function(input)
		if playing and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			skipRequested = true
		end
	end)
	Ui.button(Ui.find(choice, "Place"), function()
		chosen = "Place"
	end)
	Ui.button(Ui.find(choice, "Keep"), function()
		chosen = "Keep"
	end)
	for _, egg in CollectionService:GetTagged("HatchingEgg") do
		track(egg)
	end
	CollectionService:GetInstanceAddedSignal("HatchingEgg"):Connect(track)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 1 / 30 then
			accumulator = 0
			updateGrowing()
		end
	end)
	while true do
		updateTimers()
		updateEggPrompts()
		task.wait(0.25)
	end
end

return HatchController
