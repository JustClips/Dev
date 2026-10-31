--!strict
-- Eggs growing in the pet parks, and opening them.
--
-- Growing (every park, every player): an egg starts small and grows until it's ready
-- (Eggs.growScale). It wobbles now and then, more often and harder as it gets close, and a
-- bar under its timer fills up. A ready egg keeps wobbling hard (no beam: Dev found it annoying).
--
-- Opening, when you're near the egg: the egg floats up over a glowing ring and wobbles, bricks
-- chip off it and a rarity name over it climbs up the rarities (one step per wobble) until it
-- reaches what's inside. Then it charges (swells, turns white, light leaks out of the cracks,
-- sparks get sucked in), bursts into flying bricks with a shockwave, the pets roll, and the
-- real one pops out. The camera stays yours (only a little shake).
-- The rarer the pet, the bigger the show (TIERS): a star flash from Rare, an energy swirl
-- from Epic, a light pillar and orbiting stars from Legendary, a spike crown, confetti rain
-- and a dimmed world from Mythic. Meshes are ours (art/blender/hatch_vfx.py, HatchFx). Far from your base the
-- same show plays in a window. Click or tap to skip ahead.
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
local HatchFx = require(Client.HatchFx)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AlienModel = require(Shared.AlienModel)
local AssetLibrary = require(Shared.AssetLibrary)
local EggModel = require(Shared.EggModel)
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
local newBadge: GuiObject
local hintLabel: TextLabel
local confetti: Frame
local confettiTemplate: ImageLabel
local queue = {}
local playing = false
-- Eggs opened while another show plays: the server takes them out of the park right away,
-- so a stand-in egg keeps sitting (and wobbling) on the spot until its own show starts.
local waiting: { [any]: Model } = {}
local skipRequested = false
-- Undo steps for the show that's playing, so a show that errors halfway doesn't leave the
-- camera rig, the dimmed world or its effects behind.
local cleanups: { () -> () } = {}

local function cleanUp()
	for i = #cleanups, 1, -1 do
		pcall(cleanups[i])
	end
	table.clear(cleanups)
end

-- Windows that would hide the show (the Eggs panel's Open button opens eggs from inside one).
local CLOSE_ON_HATCH = { "EggsPanel", "PetsPanel", "Inventory", "Index", "Shop", "Upgrades", "Garage", "Rebirth", "Daily", "Playtime", "Events", "Settings" }

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
	-- Any egg can hatch any rarity: a pet above its egg gets a LUCKY! tag.
	local lucky = info.EggRarity and Eggs.order(info.Rarity) > Eggs.order(info.EggRarity)
	rarityLabel.Text = (if lucky then "LUCKY! " else "") .. string.upper((if info.Huge then "Huge " else "") .. info.Rarity)
	rarityLabel.TextColor3 = rarity.Color
	nameLabel.Text = "Hatched " .. (if info.Huge then "HUGE " else "") .. AlienModel.displayName(info.AlienId, info.Mutation) .. "!"
	nameLabel.TextColor3 = rarity.Color
	local def = Aliens.ById[info.AlienId]
	local income = info.Income or (def and def.Income or 0)
	local hex = class.Color:ToHex()
	infoLabel.Text = `<font color="#{hex}">{Weights.format(weight)} ({class.Name})</font>   +{Format.cash(income)}/s`
	newBadge.Visible = info.IsNew == true
	hintLabel.Text = if Ui.gamepad() then "Press A to skip" elseif UserInputService.TouchEnabled then "Tap to skip" else "Click to skip"
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

-- Into the park when there's a free slot, otherwise into the bag. No question asked.
local function autoPlace(info): string
	if info.FreeSlot and info.Uid then
		local ok, message = Net.func("Inventory"):InvokeServer("PlacePet", info.Uid)
		if ok then
			return "Place"
		end
		if message then
			C.HudController:Toast(message, "Bad")
		end
	end
	C.HudController:Toast("Added to your bag (press 3 or B).", "Info")
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

-- Case-opening roll in 3D: pets of the egg's rarity (plus a few teasers from the rarities
-- around it) pop in and out where the egg opened, each a bit longer than the last, with a
-- tick. A click jumps to the end. The real pet comes right after.
local function rollPick(rarity: string): string?
	local order = Eggs.order(rarity)
	local r = math.random()
	local target = rarity
	if r < 0.2 and Eggs.Rarities[order + 1] then
		target = Eggs.Rarities[order + 1].Name
	elseif r < 0.35 and Eggs.Rarities[order - 1] then
		target = Eggs.Rarities[order - 1].Name
	end
	local bucket = Aliens.ByRarity[target] or Aliens.ByRarity[rarity]
	if not bucket or #bucket == 0 then
		return nil
	end
	return bucket[math.random(1, #bucket)].Id
end

local function rollPets(scene: Scene, info, face: CFrame, petScale: number, count: number, onPet: ((Color3) -> ())?)
	local light = Instance.new("Part")
	light.Anchored = true
	light.CanCollide = false
	light.CanQuery = false
	light.Transparency = 1
	light.Size = Vector3.new(0.2, 0.2, 0.2)
	light.CFrame = face * CFrame.new(0, 2, 0)
	light.Parent = scene.parent
	local glowLight = Instance.new("PointLight")
	glowLight.Brightness = 4
	glowLight.Range = 12
	glowLight.Parent = light
	local last: string? = nil
	for k = 1, count do
		if skipRequested then
			break
		end
		local id = rollPick(info.Rarity) or info.AlienId
		if id == last then
			id = rollPick(info.Rarity) or id
		end
		last = id
		local def = Aliens.ById[id]
		local color = rarityOf(if def then def.Rarity else info.Rarity).Color
		glowLight.Color = color
		if onPet then
			onPet(color)
		end
		local pet = AssetLibrary.alien(id, info.EggMutation) -- a mutated egg only rolls mutated pets
		for _, d in pet:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		local h = Instance.new("Highlight")
		h.FillTransparency = 1
		h.OutlineColor = color
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = pet
		local turn = CFrame.Angles(0, math.rad(math.random(-25, 25)), 0)
		pet:PivotTo(face * turn)
		pet.Parent = scene.parent
		Ui.sound("Click", 0.85 + k / count * 0.6)
		-- Each pet stays a little longer than the one before (fast flicker, then slow).
		local hold = 0.06 + 0.3 * (k / count) ^ 2.2
		local pop = math.min(0.08, hold * 0.5)
		animate(pop, function(t)
			pet:ScaleTo(math.max(0.05, petScale * (0.6 + 0.4 * backOut(t))))
		end, true)
		waitOrSkip(hold - pop)
		pet:Destroy()
	end
	light:Destroy()
end

-- How big a show each pet rarity gets (Eggs order 1-7). Huge pets and mutations get one more.
type Tier = {
	wobbles: number, -- shakes before the burst (the rarity climb steps through them)
	shards: number, -- bricks the egg bursts into
	rings: number, -- shockwaves at the burst
	swirl: boolean, -- energy ribbon around the egg
	star: boolean, -- star flash at the burst
	pillar: boolean, -- light pillar to the sky
	crown: boolean, -- spike crown out of the ground
	darken: boolean, -- the world goes dim while it charges
	stars: number, -- stars orbiting the revealed pet
	rain: boolean, -- confetti rain over the pet
	charge: number, -- seconds of charging
}
-- Dev (2026-10-29): the first version had too much going on, so it's toned down: fewer
-- bricks and rings, swirl from Epic, star flash from Rare, crown/darken/rain only for Mythic+.
local TIERS: { Tier } = {
	{ wobbles = 3, shards = 8, rings = 1, swirl = false, star = false, pillar = false, crown = false, darken = false, stars = 0, rain = false, charge = 0.5 },
	{ wobbles = 3, shards = 9, rings = 1, swirl = false, star = false, pillar = false, crown = false, darken = false, stars = 0, rain = false, charge = 0.55 },
	{ wobbles = 3, shards = 11, rings = 1, swirl = false, star = true, pillar = false, crown = false, darken = false, stars = 0, rain = false, charge = 0.65 },
	{ wobbles = 4, shards = 13, rings = 2, swirl = true, star = true, pillar = false, crown = false, darken = false, stars = 0, rain = false, charge = 0.75 },
	{ wobbles = 4, shards = 15, rings = 2, swirl = true, star = true, pillar = true, crown = false, darken = false, stars = 3, rain = false, charge = 0.9 },
	{ wobbles = 5, shards = 17, rings = 2, swirl = true, star = true, pillar = true, crown = true, darken = true, stars = 4, rain = true, charge = 1.05 },
	{ wobbles = 5, shards = 19, rings = 3, swirl = true, star = true, pillar = true, crown = true, darken = true, stars = 5, rain = true, charge = 1.2 },
}

-- A rarity name floating over the egg that climbs up the rarities while it shakes.
local function climbLabel(scene: Scene, at: Vector3, width: number): (Part, TextLabel)
	local anchor = Instance.new("Part")
	anchor.Name = "ClimbAnchor"
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CFrame = CFrame.new(at)
	anchor.Parent = scene.parent
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromScale(width, width * 0.22)
	board.LightInfluence = 0
	board.AlwaysOnTop = true
	board.Adornee = anchor
	board.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
	label.TextScaled = true
	label.Text = ""
	label.TextColor3 = WHITE
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label
	label.Parent = board
	return anchor, label
end

local function play(info)
	playing = true
	for _, name in CLOSE_ON_HATCH do
		Ui.close(name)
	end
	local standIn = waiting[info]
	if standIn then
		waiting[info] = nil
		standIn:Destroy()
	end
	skipRequested = false
	local rarity = rarityOf(info.Rarity)
	local eggRarity = info.EggRarity or info.Rarity
	local order = Eggs.order(info.Rarity)
	local special = info.Huge == true or info.Mutation ~= nil
	local power = math.clamp(order + (if special then 1 else 0), 1, #TIERS)
	local tier = TIERS[power]
	local big = special or order >= Eggs.order("Epic")
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
		table.insert(cleanups, function()
			fx:Destroy()
		end)
		local eggScale = Weights.visualScale(Weights.eggMult(eggRarity, info.EggWeight)) * 1.25
		scene = {
			world = true,
			parent = fx,
			camera = camera,
			origin = spot :: CFrame,
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

	-- 1. The egg (a local copy where the real one sat). Hide the real one if
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
	AssetLibrary.applyMutation(egg, info.EggMutation)
	local eggLooks = looks(egg)
	egg:ScaleTo(scene.eggScale)
	egg:PivotTo(scene.origin)
	egg.Parent = scene.parent
	local _, eggSize = egg:GetBoundingBox()
	local eggHeight = math.max(eggSize.Y, 1.5)
	local eggWidth = math.max(eggSize.X, eggSize.Z, 1)
	local hover = eggHeight * 0.22 -- the egg floats up this far before it bursts
	local lifted = scene.origin * CFrame.new(0, hover, 0)
	local focus = scene.origin.Position + Vector3.new(0, hover + eggHeight * 0.5, 0)
	local floorY = scene.origin.Position.Y
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

	-- The camera stays yours (Dev didn't want it to focus on the egg); it only shakes a little.
	local rig: HatchFx.Rig? = nil
	if scene.world and not Ui.reducedMotion() then
		local ignore: { Instance } = { scene.parent }
		if character then
			table.insert(ignore, character)
		end
		rig = HatchFx.cameraRig(focus, math.clamp(eggHeight * 3.1, 9, 22), ignore)
		table.insert(cleanups, (rig :: HatchFx.Rig).stop)
		local r = rig :: HatchFx.Rig
		r.weight(0, 0.01)
	else
		scene.camera.CFrame = CFrame.lookAt(Vector3.new(0, eggHeight * 0.85, -eggHeight * 2.9), Vector3.new(0, eggHeight * 0.6, 0))
		Ui.popIn(gui)
	end

	-- 2. Lift off: dust, a glowing ring on the ground, the egg floats up.
	local groundRing = HatchFx.mesh("VfxHatchRing")
	if groundRing then
		groundRing.Material = Enum.Material.Neon
		groundRing.Color = rarityOf("Common").Color
		groundRing.Transparency = 1
		groundRing.Parent = scene.parent
	end
	local ringColor = rarityOf("Common").Color
	local ringSpin = 0
	local ringPulse = 0
	local ringFade = 0
	HatchFx.run(function(dt)
		if not groundRing or not groundRing.Parent then
			return false
		end
		ringSpin += dt * 1.5
		ringPulse = math.max(0, ringPulse - dt * 3)
		local r = eggWidth * (0.85 + 0.25 * ringPulse)
		groundRing.Size = Vector3.new(r * 2, 0.35, r * 2)
		groundRing.CFrame = scene.origin * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, ringSpin, 0)
		groundRing.Color = ringColor
		groundRing.Transparency = 0.15 + 0.85 * ringFade
		return true
	end)
	if scene.world then
		HatchFx.dust(scene.parent, scene.origin.Position + Vector3.new(0, 0.2, 0), eggWidth * 0.6, 10)
	end
	Ui.sound("HatchLift")
	animate(0.45 * tempo, function(t)
		local up = backOut(t)
		egg:PivotTo(scene.origin * CFrame.new(0, hover * up, 0) * CFrame.Angles(0, t * math.pi * 0.5, 0))
	end, true)
	egg:PivotTo(lifted)

	-- 3. Wobbles, each harder than the last. Bricks chip off and the glow climbs up the
	-- rarities, one step per wobble, until it reaches what's inside.
	local setLeak, removeLeak = HatchFx.lightLeak(scene.parent, focus, eggHeight * 0.75)
	local setSwirl: ((number, number, Color3) -> ())? = nil
	local removeSwirl: (() -> ())? = nil
	local climbAnchor: Part? = nil
	local climbText: TextLabel? = nil
	if scene.world then
		climbAnchor, climbText = climbLabel(scene, focus + Vector3.new(0, eggHeight * 0.85, 0), math.max(6, eggWidth * 2.6))
	end
	local wobbles = if quick then 2 else tier.wobbles
	local climbColor = rarityOf("Common").Color
	for i = 1, wobbles do
		if skipRequested then
			break
		end
		local step = math.max(1, math.ceil(i / wobbles * order))
		local stepDef = Eggs.Rarities[step] or rarity
		climbColor = stepDef.Color
		ringColor = climbColor
		ringPulse = 1
		light.Color = climbColor
		light.Brightness = 1 + 4 * i / wobbles
		if climbText then
			local label = climbText :: TextLabel
			label.Text = string.upper(stepDef.Name) .. (if i < wobbles then "?" else "!")
			label.TextColor3 = climbColor
			label.TextTransparency = 0
			label.Rotation = math.random(-6, 6)
			label.Size = UDim2.fromScale(1.35, 1.35)
			TweenService:Create(label, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 1) }):Play()
		end
		Ui.sound("Wobble", 0.9 + i * 0.1)
		Ui.sound("HatchTier", 0.75 + step * 0.12)
		Ui.sound("HatchChip", 0.9 + math.random() * 0.3)
		HatchFx.shockwave(scene.parent, scene.origin, climbColor, eggWidth * (1.1 + i * 0.12), 0.4, 0.25)
		HatchFx.shards(scene.parent, focus, floorY, eggRarity, if i >= 2 then 1 else 0, 12 + i * 2, scene.eggScale * 0.8)
		if tier.swirl and i == 2 then
			setSwirl, removeSwirl = HatchFx.swirl(scene.parent, scene.origin, eggWidth * 0.95, eggHeight * 1.5)
		end
		if setSwirl then
			setSwirl(2 + i * 1.2, 0, climbColor)
		end
		if rig then
			rig.shake(0.02 + 0.01 * i, 0.25)
		end
		local amp = math.rad(8 + i * 5)
		local length = 0.36 * tempo
		animate(length, function(t)
			local fade = 1 - t
			local angle = math.sin(t * math.pi * 6) * amp * fade
			local hop = math.sin(t * math.pi) * eggHeight * 0.06 * i
			egg:PivotTo(lifted * CFrame.new(0, hop, 0) * CFrame.Angles(angle * 0.4, 0, angle))
		end)
		egg:PivotTo(lifted)
		waitOrSkip((0.24 - math.min(i, 5) * 0.025) * tempo)
	end
	if climbText then
		local label = climbText :: TextLabel
		label.Text = (if order > Eggs.order(eggRarity) then "LUCKY " else "") .. string.upper(rarity.Name) .. "!"
		label.TextColor3 = rarity.Color
		label.TextTransparency = 0
	end
	climbColor = rarity.Color
	ringColor = climbColor

	-- 4. Charge: swells up, shakes, turns white, light pours out of the cracks, sparks get
	-- sucked in. Legendary and up: a pillar of light to the sky; Mythic and up: the world dims.
	Ui.sound("Charge")
	Ui.sound("HatchRise")
	local stopSuck: (() -> ())? = nil
	local undim: (() -> ())? = nil
	local endPillar: (() -> ())? = nil
	if scene.world then
		stopSuck = HatchFx.suckIn(scene.parent, focus, eggHeight * 1.4, climbColor, 12 + power * 5)
		if tier.darken and not quick then
			undim = HatchFx.darken(climbColor, tier.charge)
			table.insert(cleanups, undim :: () -> ())
		end
	end
	if tier.pillar and not quick then
		Ui.sound("HatchSuck")
		endPillar = HatchFx.pillar(scene.parent, scene.origin, eggWidth * 0.75, if scene.world then 160 else eggHeight * 4, climbColor)
	end
	if tier.crown and not quick then
		HatchFx.crown(scene.parent, scene.origin, eggWidth * 1.15, eggHeight * 0.7, climbColor)
	end
	animate(tier.charge * tempo, function(t)
		local shake = math.rad(4 + power) * t
		egg:ScaleTo(scene.eggScale * (1 + 0.38 * t * t))
		egg:PivotTo(lifted * CFrame.Angles(math.random(-100, 100) / 100 * shake, t * t * 6, math.random(-100, 100) / 100 * shake))
		whiten(eggLooks, t)
		light.Brightness = 5 + 6 * t
		setLeak(0.3 + 0.6 * t, climbColor)
		if setSwirl then
			setSwirl(6 + 14 * t, t, climbColor)
		end
		if highlight then
			highlight.FillTransparency = 1 - t * 0.9
		end
		if rig then
			rig.shake(0.03 + 0.08 * t * (power / 7), 0.2)
		end
		if not scene.world then
			glow.ImageTransparency = 1 - t * 0.7
		end
	end, true)

	-- 5. Burst! The egg blows apart into bricks: shockwaves, a star flash, sparks.
	Ui.sound("Crack")
	Ui.sound("HatchBricks")
	Ui.sound("Hatch")
	if power >= 3 then
		Ui.sound("HatchBoom")
	end
	flashScreen(if big then 0.7 else 0.45, if big then 0.7 else 0.45)
	if stopSuck then
		stopSuck()
	end
	removeLeak()
	if removeSwirl then
		removeSwirl()
	end
	if climbAnchor then
		climbAnchor:Destroy()
	end
	ringPulse = 1.5
	local screenPoint = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y * 0.45)
	if scene.world then
		local point, visible = camera:WorldToViewportPoint(focus)
		if visible then
			screenPoint = Vector2.new(point.X, point.Y)
		end
		HatchFx.burst(scene.parent, focus, rarity.Color, 14 + power * 5, 22 + power * 2)
	end
	for k = 1, tier.rings do
		local radius = math.max(8, eggHeight * 3) * (1 + (k - 1) * 0.4)
		task.delay((k - 1) * 0.09, function()
			HatchFx.shockwave(scene.parent, scene.origin, if k % 2 == 0 then WHITE else rarity.Color, radius, 0.55 + k * 0.08)
		end)
	end
	HatchFx.shards(scene.parent, focus, floorY, eggRarity, if quick then 6 else tier.shards, 18 + power * 2, scene.eggScale)
	if tier.star then
		HatchFx.starFlash(scene.parent, focus, eggHeight * (0.9 + power * 0.1), rarity.Color, scene.camera)
	end
	burstConfetti(screenPoint, rarity.Color, if big then 18 else 10)
	if rig then
		rig.shake(0.12 + power * 0.03, 0.35)
	end
	egg:Destroy()

	local petScale = Weights.visualScale(Weights.incomeMult(info.Rarity, info.Weight)) * (if info.Huge then Aliens.HugeScale else 1)
	local face: CFrame
	if scene.world then
		local look = Vector3.new(camera.CFrame.Position.X, scene.origin.Position.Y, camera.CFrame.Position.Z)
		face = CFrame.lookAt(scene.origin.Position, look)
	else
		face = CFrame.new() -- the window camera looks at the pet's front
	end

	-- 5b. The roll: pets flick through where the egg was, slowing down, then the real one.
	if not quick and not Ui.reducedMotion() then
		rollPets(scene, info, face, petScale, if big then 18 else 13, function(color: Color3)
			ringColor = color
			ringPulse = 0.8
		end)
	end

	-- 6. The pet pops out, faces you and dances.
	ringColor = rarity.Color
	ringPulse = 1.2
	local model = AssetLibrary.alien(info.AlienId, info.Mutation)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
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
	HatchFx.shockwave(scene.parent, scene.origin, rarity.Color, math.max(5, eggHeight * 1.8), 0.4, 0.25)
	animate(0.42, function(t)
		model:ScaleTo(math.max(0.05, petScale * backOut(t)))
		model:PivotTo(face * CFrame.new(0, math.sin(t * math.pi) * 1.2, 0))
	end, true)
	model:PivotTo(face)
	local finalSize = size3 / 0.05 * petScale
	local petSize = math.max(finalSize.X, finalSize.Y, finalSize.Z, 1.5)
	Ui.sound(if big then "RareReveal" else "Reveal")
	Ui.sound("Sparkle")
	if power >= 4 then
		Ui.sound("HatchShimmer")
	end
	if power >= 6 then
		Ui.sound("HatchGong")
	end

	-- Rays behind the pet; stars around it and confetti for the rare ones.
	local raysImage: ImageLabel
	local glowImage: ImageLabel
	local petCenter = scene.origin.Position + Vector3.new(0, petSize * 0.45, 0)
	if scene.world then
		local _, r, g = worldRays(scene, petCenter, petSize, rarity.Color)
		raysImage, glowImage = r, g
		if tier.rain and not quick then
			HatchFx.confettiRain(scene.parent, petCenter + Vector3.new(0, petSize * 2.5 + 6, 0), petSize * 1.4, { rarity.Color, WHITE, Color3.fromRGB(255, 214, 90) }, REVEAL_SECONDS)
		end
	else
		raysImage, glowImage = rays, glow
		scene.camera.CFrame = CFrame.lookAt(Vector3.new(petSize * 0.35, petSize * 0.7, -petSize * 2.4), Vector3.new(0, petSize * 0.42, 0))
	end
	local endStars: (() -> ())? = nil
	if tier.stars > 0 then
		endStars = HatchFx.orbitStars(scene.parent, petCenter, petSize * 0.85, rarity.Color, if quick then 3 else tier.stars)
	end
	TweenService:Create(raysImage, TweenInfo.new(0.3), { ImageTransparency = if big then 0.15 else 0.35 }):Play()
	TweenService:Create(glowImage, TweenInfo.new(0.3), { ImageTransparency = 0.3 }):Play()
	local spin = RunService.RenderStepped:Connect(function(dt)
		raysImage.Rotation = (raysImage.Rotation + dt * 25) % 360
	end)

	skipRequested = false
	showCard(info)
	waitOrSkip(REVEAL_SECONDS * tempo)
	local placed = if info.Test then "Test" else autoPlace(info)

	-- 7. Wrap up: the pet hops off (to the park or your bag), the camera comes back.
	TweenService:Create(raysImage, TweenInfo.new(0.3), { ImageTransparency = 1 }):Play()
	TweenService:Create(glowImage, TweenInfo.new(0.3), { ImageTransparency = 1 }):Play()
	if endStars then
		endStars()
	end
	if endPillar then
		endPillar()
	end
	if undim then
		undim()
	end
	if rig then
		rig.orbit(0)
		rig.weight(0, 0.45)
	end
	HatchFx.over(0.4, function(a)
		ringFade = a
	end, function()
		if groundRing then
			groundRing:Destroy()
		end
	end)
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
	if rig then
		local r = rig :: HatchFx.Rig
		task.delay(0.3, function()
			r.stop()
		end)
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
			if waiting[info] then
				waiting[info]:Destroy()
				waiting[info] = nil
			end
			if ok then
				table.clear(cleanups)
			else
				cleanUp()
				worldModel:ClearAllChildren()
				stage.Visible = false
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
	label: BillboardGui?,
	fill: Frame?,
}
local growing: { [Model]: Growing } = {}

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
			EggModel.retile(egg)
		end
		local ready = progress >= 1
		-- Wobble now and then: a little more often and harder as it gets close.
		if clock >= g.nextWobble then
			g.wobbleAt = clock
			-- Dev: wobbling every second was too much; about every 10 s once ready.
			local gap = if ready then 10 else 16 - 6 * progress
			g.nextWobble = clock + gap * (0.7 + math.random() * 0.6)
		end
		local w = clock - g.wobbleAt
		local offset = CFrame.new()
		if w < 0.5 then
			local amp = math.rad(if ready then 14 else 3 + 9 * progress)
			local angle = math.sin(w / 0.5 * math.pi * 4) * amp * (1 - w / 0.5)
			offset = CFrame.Angles(angle * 0.4, 0, angle)
		end
		egg:PivotTo(g.base * offset)
	end
end

------------------------------------------------------------------ timers and prompts

-- Egg timers only show when you're close to the egg; ready eggs turn green.
local TIMER_RANGE = 22
local READY_COLOR = Color3.fromRGB(110, 255, 120)

local function updateTimers()
	local now = State.now()
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	for _, label in CollectionService:GetTagged("HatchTimer") do
		if label:IsA("TextLabel") then
			local endsAt = label:GetAttribute("EndsAt") or 0
			local left = endsAt - now
			label.Text = if left > 0 then Format.time(left) else "READY!"
			label.TextColor3 = if left > 0 then Color3.new(1, 1, 1) else READY_COLOR
			local board = label:FindFirstAncestorWhichIsA("BillboardGui")
			local part = board and board.Parent
			if board and part and part:IsA("BasePart") then
				local near = root ~= nil and (root.Position - part.Position).Magnitude < TIMER_RANGE + part.Size.X / 2
				board.Enabled = near
			end
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
local EGG_PROMPT_RANGE = 6 -- studs from the egg's side
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
			p.RequiresLineOfSight = false
			p.HoldDuration = 0 -- press, no hold (Dev, 2026-10-31)
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
		-- Set every update: growing the egg (Model:ScaleTo) scales the prompt's range too,
		-- which made Skip Hatch show up from far away on big eggs.
		p.MaxActivationDistance = EGG_PROMPT_RANGE + math.max(root.Size.X, root.Size.Z) / 2
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

-- True while a hatch show is playing or more eggs are waiting for theirs.
function HatchController:IsBusy(): boolean
	return playing or #queue > 0
end

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
	confetti = Ui.find(gui, "Confetti")
	confettiTemplate = Ui.find(confetti, "Template")
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

-- Someone else's hatch (Dev, 2026-10-30: everyone should see hatches). A short, light
-- version at their base: the egg shakes and rises, bursts with a few shards and a ring
-- (a light pillar for Legendary+), and the pet pops out with its name for a moment.
-- Only near you, and at most a few at once, so it stays easy on phones.
local OTHER_RANGE = 70 -- studs from you (Dev, 2026-10-30: others' hatches showed from far away)
local OTHER_MAX = 3
local othersPlaying = 0

local function playOther(info)
	local owner = Players:GetPlayerByUserId(info.UserId)
	local camera = Workspace.CurrentCamera
	if not owner or owner == Players.LocalPlayer or not camera or not info.X or not info.Z or othersPlaying >= OTHER_MAX then
		return
	end
	local index = owner:GetAttribute("BaseIndex")
	if type(index) ~= "number" or index < 1 then
		return
	end
	local spot = World.baseCFrame(index) * CFrame.new(info.X, 0.2, info.Z)
	local me = Players.LocalPlayer.Character
	local myRoot = me and me:FindFirstChild("HumanoidRootPart") :: BasePart?
	local from = if myRoot then myRoot.Position else camera.CFrame.Position
	if (from - spot.Position).Magnitude > OTHER_RANGE then
		return
	end
	othersPlaying += 1
	local fx = Instance.new("Folder")
	fx.Name = "OtherHatch"
	fx.Parent = Workspace
	local ok, err = pcall(function()
		local rarity = rarityOf(info.Rarity)
		local special = info.Huge == true or info.Mutation ~= nil
		local power = math.clamp(Eggs.order(info.Rarity) + (if special then 1 else 0), 1, #TIERS)
		local tier = TIERS[power]
		local eggRarity = info.EggRarity or info.Rarity
		local eggScale = Weights.visualScale(Weights.eggMult(eggRarity, info.EggWeight)) * 1.25
		local egg = AssetLibrary.egg(eggRarity)
		AssetLibrary.applyMutation(egg, info.EggMutation)
		looks(egg)
		egg:ScaleTo(eggScale)
		egg:PivotTo(spot)
		egg.Parent = fx
		local eggHeight = egg:GetExtentsSize().Y
		-- Shake and rise.
		animate(0.5 + 0.12 * power, function(t)
			local angle = math.sin(t * math.pi * 6) * math.rad(12) * (0.4 + 0.6 * t)
			egg:PivotTo(spot * CFrame.new(0, t * 1.2, 0) * CFrame.Angles(angle * 0.4, 0, angle))
		end, true)
		local focus = spot.Position + Vector3.new(0, 1.2 + eggHeight / 2, 0)
		egg:Destroy()
		-- Burst.
		HatchFx.burst(fx, focus, rarity.Color, 8 + power * 2, 18)
		HatchFx.shockwave(fx, spot, rarity.Color, math.max(6, eggHeight * 2.5), 0.5)
		HatchFx.shards(fx, focus, spot.Position.Y, eggRarity, math.ceil(tier.shards / 2), 16, eggScale)
		local endPillar = if tier.pillar then HatchFx.pillar(fx, spot, eggHeight * 0.6, 60, rarity.Color) else nil
		-- The pet pops out facing the camera, with its name over it.
		local face = CFrame.lookAt(spot.Position, Vector3.new(camera.CFrame.Position.X, spot.Position.Y, camera.CFrame.Position.Z))
		local petScale = Weights.visualScale(Weights.incomeMult(info.Rarity, info.Weight)) * (if info.Huge then Aliens.HugeScale else 1)
		local model = AssetLibrary.alien(info.AlienId, info.Mutation)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		model:PivotTo(face)
		model.Parent = fx
		model:ScaleTo(0.05)
		animate(0.35, function(t)
			model:ScaleTo(math.max(0.05, petScale * backOut(t)))
		end, true)
		local _, size = model:GetBoundingBox()
		local board = Instance.new("BillboardGui")
		-- Sized in studs, so it's small from afar instead of a fixed big label.
		board.Size = UDim2.fromScale(7, 1.4)
		board.StudsOffsetWorldSpace = Vector3.new(0, size.Y + 1.2, 0)
		board.AlwaysOnTop = false
		board.LightInfluence = 0
		board.MaxDistance = OTHER_RANGE
		board.Adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
		label.TextScaled = true
		label.TextColor3 = rarity.Color
		label.Text = (if info.Huge then "HUGE " else "") .. AlienModel.displayName(info.AlienId, info.Mutation)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Parent = label
		label.Parent = board
		board.Parent = fx
		task.wait(2.2)
		if endPillar then
			endPillar()
		end
		animate(0.3, function(t)
			model:ScaleTo(math.max(0.05, petScale * (1 - t)))
			label.TextTransparency = t
		end, true)
	end)
	if not ok then
		warn("[HatchController] other hatch: " .. tostring(err))
	end
	task.delay(1, function()
		fx:Destroy()
	end)
	othersPlaying -= 1
end

function HatchController:Start()
	Net.event("HatchShown").OnClientEvent:Connect(function(info)
		if type(info) == "table" then
			task.spawn(playOther, info)
		end
	end)
	Net.event("HatchCompleted").OnClientEvent:Connect(function(info)
		if playing or #queue > 0 then
			-- Keep this egg visible where it sat until its turn comes.
			local spot = eggSpot(info)
			if spot then
				local eggRarity = info.EggRarity or info.Rarity
				local egg = AssetLibrary.egg(eggRarity)
				egg.Name = "WaitingEgg"
				AssetLibrary.applyMutation(egg, info.EggMutation)
				for _, d in egg:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
					end
				end
				egg:ScaleTo(Weights.visualScale(Weights.eggMult(eggRarity, info.EggWeight)) * 1.25)
				egg:PivotTo(spot)
				egg.Parent = Workspace
				waiting[info] = egg
				-- An impatient little wobble while it waits.
				task.spawn(function()
					while waiting[info] == egg and egg.Parent do
						local start = os.clock()
						while os.clock() - start < 0.35 and egg.Parent do
							local t = (os.clock() - start) / 0.35
							local angle = math.sin(t * math.pi * 4) * math.rad(7) * (1 - t)
							egg:PivotTo(spot * CFrame.Angles(angle * 0.4, 0, angle))
							RunService.RenderStepped:Wait()
						end
						if egg.Parent then
							egg:PivotTo(spot)
						end
						task.wait(0.8 + math.random() * 0.6)
					end
				end)
			end
		end
		table.insert(queue, info)
		pump()
	end)
	UserInputService.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		local pad = input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.ButtonR2
		if playing and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch or pad) then
			skipRequested = true
		end
	end)
	-- The "Hatched ..." text sits just above the hotbar.
	Ui.onScale(function(sc: number)
		card.Position = UDim2.new(0.5, 0, 1, -(14 + math.ceil(100 * sc)))
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
