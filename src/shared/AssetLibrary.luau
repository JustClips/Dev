--!strict
-- The Blender models (Config/Assets, uploaded by tools/upload_assets.py).
-- The server loads every model once (AssetService) and puts a cleaned-up copy in
-- ReplicatedStorage.Assets. Server and client code then clone from there.
-- When a model isn't loaded (no API access, offline Studio) callers get a part-built
-- placeholder, so the game still runs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(script.Parent.Config.Assets)
local AlienModel = require(script.Parent.AlienModel)
local EggModel = require(script.Parent.EggModel)

local AssetLibrary = {}

local FOLDER_NAME = "Assets"
local GOLD = Color3.fromRGB(255, 200, 50)
local GLASS = Color3.fromRGB(190, 230, 255)

local function folder(): Folder?
	return ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder?
end

local function hex(s: string): Color3
	return Color3.fromHex(s)
end

-- Builds a Motor6D rig: RootPart -> Body -> limbs, joints at the Blender pivots.
-- Parts without a joint (glow bits, glass) are held rigid by a Motor6D at their own CFrame.
local function rig(model: Model, meta, parts: { [string]: BasePart })
	local root = Instance.new("Part")
	root.Name = "RootPart"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Anchored = true
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root
	for name, part in parts do
		part.Anchored = false
		part.Massless = true
		local pm = meta.parts[name]
		local parent = (pm and pm.parent and parts[pm.parent]) or root
		local jointCf = if pm and pm.joint then CFrame.new(pm.joint) else part.CFrame
		if name == "Body" then
			jointCf = part.CFrame
		end
		local joint = Instance.new("Motor6D")
		joint.Name = name
		joint.Part0 = parent
		joint.Part1 = part
		joint.C0 = parent.CFrame:Inverse() * jointCf
		joint.C1 = part.CFrame:Inverse() * jointCf
		joint.Parent = parent
	end
	local controller = Instance.new("AnimationController")
	controller.Parent = model
	Instance.new("Animator").Parent = controller
end

-- Turns a freshly loaded asset into a clean Model: every MeshPart directly under it,
-- pivot at the Blender origin, glow/glass materials applied, rigged if it's an alien.
function AssetLibrary.prepare(name: string, raw: Instance): Model
	local meta = Assets.Models[name]
	local model = Instance.new("Model")
	model.Name = name
	local parts: { [string]: BasePart } = {}
	for _, d in raw:GetDescendants() do
		if d:IsA("MeshPart") and not parts[d.Name] then
			parts[d.Name] = d
		end
	end
	for partName, part in parts do
		part.Parent = model
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		local pm = meta and meta.parts[partName]
		if pm and pm.glow then
			local mesh = part :: MeshPart
			mesh.TextureID = ""
			mesh.Material = Enum.Material.Neon
			mesh.Color = hex(pm.glow)
			mesh.CastShadow = false
			mesh:SetAttribute("Glow", true)
		elseif pm and pm.material == "Glass" then
			local mesh = part :: MeshPart
			mesh.TextureID = ""
			mesh.Material = Enum.Material.Glass
			mesh.Color = GLASS
			mesh.Transparency = 0.6
			mesh.CastShadow = false
			mesh:SetAttribute("Glow", true)
		else
			part.Material = Enum.Material.SmoothPlastic
		end
		if pm and pm.collide then
			part.CanCollide = true
			part.CanQuery = true
		end
	end
	raw:Destroy()
	if meta and (meta.kind == "alien" or (meta :: any).rig) then
		rig(model, meta, parts)
	else
		local primary = parts.Body or parts.Handle
		if not primary then
			for _, p in parts do
				primary = p
				break
			end
		end
		if primary then
			model.PrimaryPart = primary
			primary.PivotOffset = primary.CFrame:Inverse() -- pivot at the Blender origin
		end
	end
	model:SetAttribute("Kind", if meta then meta.kind else "unknown")
	return model
end

function AssetLibrary.isReady(): boolean
	local f = folder()
	return f ~= nil and f:GetAttribute("Ready") == true
end

-- Waits (up to timeout seconds) until the server finished loading models.
function AssetLibrary.waitReady(timeout: number?): boolean
	local f = folder() or ReplicatedStorage:WaitForChild(FOLDER_NAME, timeout or 30)
	if not f then
		return false
	end
	local deadline = os.clock() + (timeout or 30)
	while f:GetAttribute("Ready") ~= true and os.clock() < deadline do
		task.wait(0.2)
	end
	return f:GetAttribute("Ready") == true
end

-- A fresh copy of a loaded model, or nil if it isn't available.
function AssetLibrary.get(name: string): Model?
	local f = folder()
	local source = f and f:FindFirstChild(name)
	if source and source:IsA("Model") then
		return source:Clone()
	end
	return nil
end

-- Whether a model finished loading (so AssetLibrary.get returns the real one).
function AssetLibrary.has(name: string): boolean
	local f = folder()
	local source = f and f:FindFirstChild(name)
	return source ~= nil and source:IsA("Model")
end

function AssetLibrary.meta(name: string)
	return Assets.Models[name]
end

type WeatherLook = {
	color: Color3?, -- tint (or full repaint when repaint = true)
	repaint: boolean?,
	material: Enum.Material?,
	rainbow: boolean?, -- colour-cycling neon (Disco)
	texture: string, -- particle texture (Assets.Images name)
	fx: Color3,
	size: number?,
	rate: number?,
	speed: number?,
	accel: Vector3?,
	glow: number?,
}

local WEATHER_LOOKS: { [string]: WeatherLook } = {
	Wet = { color = Color3.fromRGB(90, 150, 255), material = Enum.Material.Glass, texture = "Vfx_Rain", fx = Color3.fromRGB(150, 200, 255), size = 0.4, rate = 8, speed = 0.5, accel = Vector3.new(0, -12, 0), glow = 0.3 },
	Shocked = { color = Color3.fromRGB(255, 235, 90), texture = "Vfx_Star", fx = Color3.fromRGB(255, 240, 120), size = 0.5, rate = 10, speed = 3, glow = 1 },
	Frozen = { color = Color3.fromRGB(185, 230, 255), repaint = true, material = Enum.Material.Ice, texture = "Vfx_Snow", fx = Color3.fromRGB(230, 245, 255), size = 0.35, rate = 5, speed = 0.6, accel = Vector3.new(0, -2, 0), glow = 0.5 },
	Windswept = { color = Color3.fromRGB(255, 175, 90), texture = "Vfx_Leaf", fx = Color3.fromRGB(255, 160, 60), size = 0.45, rate = 4, speed = 3, glow = 0 },
	Bloodlit = { color = Color3.fromRGB(170, 20, 30), repaint = true, material = Enum.Material.SmoothPlastic, texture = "Vfx_Glow", fx = Color3.fromRGB(255, 70, 60), size = 0.4, rate = 10, speed = 1, accel = Vector3.new(0, 3, 0), glow = 1 },
	Starlit = { color = Color3.fromRGB(40, 60, 140), repaint = true, material = Enum.Material.Neon, texture = "Vfx_Star", fx = Color3.fromRGB(150, 255, 220), size = 0.45, rate = 8, speed = 0.8, glow = 1 },
	Starstruck = { color = Color3.fromRGB(255, 220, 110), texture = "Vfx_Star", fx = Color3.fromRGB(255, 240, 160), size = 0.6, rate = 9, speed = 1.5, glow = 1 },
	Disco = { rainbow = true, texture = "Vfx_Note", fx = Color3.fromRGB(255, 255, 255), size = 0.5, rate = 4, speed = 2, accel = Vector3.new(0, 2, 0), glow = 0.4 },
}

-- Mutation looks. The pet or egg keeps its own texture; a mutation adds a see-through coat
-- (a slightly bigger copy of every mesh in one colour and material, welded on) and
-- particles. Dev disliked mutations repainting the whole pet in one material (2026-10-29).
type Coat = {
	color: Color3?,
	rainbow: boolean?, -- colour-cycling (PetController cycles RainbowOffset parts)
	material: Enum.Material,
	transparency: number,
	reflectance: number?,
}
local COATS: { [string]: Coat } = {
	Golden = { color = GOLD, material = Enum.Material.SmoothPlastic, transparency = 0.55, reflectance = 0.35 },
	Rainbow = { rainbow = true, material = Enum.Material.Neon, transparency = 0.78 },
	Wet = { color = Color3.fromRGB(90, 150, 255), material = Enum.Material.Glass, transparency = 0.6 },
	Shocked = { color = Color3.fromRGB(255, 235, 90), material = Enum.Material.ForceField, transparency = 0 },
	Frozen = { color = Color3.fromRGB(185, 230, 255), material = Enum.Material.Ice, transparency = 0.4 },
	Windswept = { color = Color3.fromRGB(255, 175, 90), material = Enum.Material.SmoothPlastic, transparency = 0.72 },
	Bloodlit = { color = Color3.fromRGB(200, 25, 35), material = Enum.Material.Neon, transparency = 0.72 },
	Starlit = { color = Color3.fromRGB(110, 140, 255), material = Enum.Material.ForceField, transparency = 0 },
	Starstruck = { color = Color3.fromRGB(255, 220, 110), material = Enum.Material.ForceField, transparency = 0 },
	Disco = { rainbow = true, material = Enum.Material.Neon, transparency = 0.7 },
}
local COAT_GROW = 1.06 -- coat size vs the mesh it covers
local COAT_PAD = 0.05 -- plus this many studs, so thin parts get a visible coat too

local function addCoat(model: Model, coat: Coat)
	local meshes = {}
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") and not d:GetAttribute("Glow") and not d:GetAttribute("Coat") and d.Transparency < 1 then
			table.insert(meshes, d)
		end
	end
	for i, part in meshes do
		local shell = part:Clone()
		for _, child in shell:GetChildren() do
			child:Destroy()
		end
		shell.Name = "MutationCoat"
		shell:SetAttribute("Coat", true)
		shell.TextureID = ""
		shell.Size = part.Size * COAT_GROW + Vector3.one * COAT_PAD
		shell.CFrame = part.CFrame
		shell.Material = coat.material
		shell.Transparency = coat.transparency
		shell.Reflectance = coat.reflectance or 0
		shell.CastShadow = false
		shell.CanCollide = false
		shell.CanQuery = false
		shell.CanTouch = false
		shell.Massless = true
		shell.Anchored = part.Anchored
		if coat.rainbow then
			shell.Color = Color3.fromHSV((i * 0.17) % 1, 0.7, 1)
			shell:SetAttribute("RainbowOffset", i * 0.17)
		elseif coat.color then
			shell.Color = coat.color
		end
		if not part.Anchored then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = shell
			weld.Parent = shell
		end
		shell.Parent = part.Parent
	end
	if coat.rainbow then
		model:AddTag("RainbowPet")
	end
end

local function sparkles(body: BasePart, look: WeatherLook?, color: Color3)
	local fx = Instance.new("ParticleEmitter")
	fx.Name = "MutationSparkles"
	fx.Texture = if look then Assets.Images[look.texture] or "rbxasset://textures/particles/sparkles_main.dds" else "rbxasset://textures/particles/sparkles_main.dds"
	fx.Color = ColorSequence.new(if look then look.fx else color)
	fx.Size = NumberSequence.new(if look then look.size or 0.35 else 0.35, 0)
	fx.Rate = if look then look.rate or 6 else 6
	fx.Lifetime = NumberRange.new(0.8, 1.4)
	local speed = if look then look.speed or 1 else 1
	fx.Speed = NumberRange.new(speed * 0.5, speed * 1.6)
	fx.SpreadAngle = Vector2.new(180, 180)
	fx.Acceleration = if look then look.accel or Vector3.zero else Vector3.zero
	fx.Rotation = NumberRange.new(0, 360)
	fx.RotSpeed = NumberRange.new(-90, 90)
	fx.LightEmission = if look then look.glow or 0.6 else 1
	fx.Parent = body
end

function AssetLibrary.applyMutation(model: Model, mutation: string?)
	if not mutation or model:GetAttribute("CoatFor") == mutation then
		return
	end
	model:SetAttribute("Mutation", mutation)
	model:SetAttribute("CoatFor", mutation)
	-- Pets sparkle from their Body; eggs (no Body) from their main part.
	local body = (model:FindFirstChild("Body") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")) :: BasePart?
	local coat = COATS[mutation]
	if coat then
		addCoat(model, coat)
	end
	local look = WEATHER_LOOKS[mutation]
	if body and (look or mutation == "MoonDusted" or mutation == "Golden" or mutation == "Rainbow") then
		local color = if mutation == "Golden" then GOLD elseif mutation == "Rainbow" then Color3.fromRGB(255, 160, 240) else Color3.fromRGB(220, 235, 255)
		sparkles(body, look, color)
	end
end

-- A rigged alien ready to animate (RootPart is anchored; move it with PivotTo).
-- Falls back to the part-built placeholder.
function AssetLibrary.alien(alienId: string, mutation: string?): Model
	local model = AssetLibrary.get("Alien_" .. alienId)
	if not model then
		local placeholder = AlienModel.build(alienId, mutation)
		placeholder:SetAttribute("Placeholder", true)
		return placeholder
	end
	model.Name = alienId
	model:SetAttribute("AlienId", alienId)
	AssetLibrary.applyMutation(model, mutation)
	return model
end

-- An egg model with its pivot at the bottom. Anchored, no collisions. The round Blender
-- eggs (art/blender/eggs.py) are used once loaded; EggModel's part-built egg is only a
-- stand-in until then.
function AssetLibrary.egg(rarity: string): Model
	local model = AssetLibrary.get("Egg_" .. rarity)
	if model then
		model.Name = rarity .. "Egg"
		AssetLibrary.eggExtras(model, rarity)
		return model
	end
	local placeholder = EggModel.build(rarity)
	placeholder:SetAttribute("Placeholder", true)
	return placeholder
end

-- Glow and particles per rarity, added to the egg's Body (they scale with Model:ScaleTo).
-- Common and Uncommon get none: the better the egg, the more it shines.
type EggFx = {
	light: Color3?,
	brightness: number?,
	colors: { Color3 },
	rate: number,
	texture: string?,
	embers: boolean?, -- rise up and fade (Mythic) instead of twinkling around
	size: number?,
}
local EGG_FX: { [string]: EggFx } = {
	Rare = { colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 205, 255) }, rate = 2, size = 0.4 },
	Epic = {
		light = Color3.fromRGB(210, 140, 255),
		brightness = 0.8,
		colors = { Color3.fromRGB(255, 220, 255), Color3.fromRGB(200, 120, 255) },
		rate = 4,
		size = 0.45,
	},
	Legendary = {
		light = Color3.fromRGB(255, 210, 90),
		brightness = 1,
		colors = { Color3.fromRGB(255, 255, 230), Color3.fromRGB(255, 200, 60) },
		rate = 6,
		size = 0.5,
	},
	Mythic = {
		light = Color3.fromRGB(255, 110, 50),
		brightness = 1.2,
		colors = { Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 110, 40), Color3.fromRGB(200, 40, 20) },
		rate = 10,
		texture = "Vfx_Glow",
		embers = true,
		size = 0.35,
	},
	Cosmic = {
		light = Color3.fromRGB(120, 240, 255),
		brightness = 1.2,
		colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(110, 245, 225), Color3.fromRGB(255, 150, 235) },
		rate = 7,
		size = 0.55,
	},
}

local function addEggFx(body: BasePart, fx: EggFx)
	if fx.light then
		local light = Instance.new("PointLight")
		light.Color = fx.light
		light.Brightness = fx.brightness or 1
		light.Range = 9
		light.Shadows = false
		light.Parent = body
	end
	local keys = {}
	for i, c in fx.colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(1, #fx.colors - 1), c))
	end
	if #keys == 1 then
		table.insert(keys, ColorSequenceKeypoint.new(1, fx.colors[1]))
	end
	local size = fx.size or 0.5
	local p = Instance.new("ParticleEmitter")
	p.Name = "EggSparkles"
	p.Texture = Assets.Images[fx.texture or "Vfx_Sparkle"] or Assets.Images.Sparkle or ""
	p.Color = ColorSequence.new(keys)
	p.LightEmission = 1
	p.Rate = fx.rate
	p.Rotation = NumberRange.new(0, 360)
	p.RotSpeed = NumberRange.new(-90, 90)
	if fx.embers then
		p.Lifetime = NumberRange.new(1.2, 2.2)
		p.Speed = NumberRange.new(0.5, 1.5)
		p.SpreadAngle = Vector2.new(25, 25)
		p.EmissionDirection = Enum.NormalId.Top
		p.Acceleration = Vector3.new(0, 1.5, 0)
		p.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
	else
		p.Lifetime = NumberRange.new(0.8, 1.6)
		p.Speed = NumberRange.new(0.3, 1.2)
		p.SpreadAngle = Vector2.new(180, 180)
	end
	p.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.35, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	p.Parent = body
end

-- Rigged eggs (wings, halo, rings) play their Blender idle loop while they're in the
-- world, and get their glow and sparkles. Carried eggs are welded to the head, so they
-- stay still.
function AssetLibrary.eggExtras(model: Model, rarity: string)
	local meta = Assets.Models["Egg_" .. rarity]
	local body = model:FindFirstChild("Body") :: BasePart?
	local root = model:FindFirstChild("RootPart") :: BasePart?
	if body and root and model.PrimaryPart == root then
		-- Labels and prompts sit on the PrimaryPart, so keep it the egg's Body (the rig's
		-- root is at the very bottom), with the pivot still at the bottom centre.
		body.PivotOffset = body.CFrame:Inverse() * root.CFrame
		model.PrimaryPart = body
	end
	local fx = EGG_FX[rarity]
	if fx and body then
		addEggFx(body, fx)
	end
	local animName = meta and (meta :: any).anim
	if typeof(animName) ~= "string" or not model:FindFirstChildOfClass("AnimationController") then
		return
	end
	local playing = false
	local function try()
		if playing or not model:IsDescendantOf(workspace) or model:FindFirstAncestor("CarriedEggs") then
			return
		end
		local track = AssetLibrary.loadTrack(model, animName)
		if track then
			playing = true
			track.Looped = true
			track:Play(0)
		end
	end
	model.AncestryChanged:Connect(try)
	task.defer(try)
end

-- Animations -------------------------------------------------------------------

local animations: { [string]: Animation } = {}

-- Which account's animation ids to play: the fallback account's only when AssetService
-- had to load the models from there.
local function useFallback(): boolean
	local f = folder()
	-- Until AssetService has decided (models still loading) use the primary account, which
	-- is the one that works in the live game; a track loaded this early is kept for good.
	return f ~= nil and f:GetAttribute("UseFallback") == true
end

function AssetLibrary.animation(name: string): Animation?
	local id = Assets.Animations[name]
	local fallback = Assets.AnimationFallback[name]
	if fallback and useFallback() then
		id = fallback
	end
	if not id then
		return nil
	end
	local url = "rbxassetid://" .. tostring(id)
	local anim = animations[name]
	if not anim then
		anim = Instance.new("Animation")
		anim.Name = name
		animations[name] = anim
	end
	anim.AnimationId = url
	return anim
end

-- Loads an animation on a rigged model (AnimationController) or a Humanoid character.
function AssetLibrary.loadTrack(model: Instance, name: string): AnimationTrack?
	local anim = AssetLibrary.animation(name)
	if not anim then
		return nil
	end
	local holder = if model:IsA("Humanoid") or model:IsA("AnimationController")
		then model
		else model:FindFirstChildOfClass("AnimationController") or model:FindFirstChildOfClass("Humanoid")
	local animator = holder and holder:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	return if ok then track else nil
end

function AssetLibrary.image(name: string): string
	return Assets.Images[name] or ""
end

-- Icon for one tool / car, falling back to the generic icon.
function AssetLibrary.toolIcon(toolId: string): string
	return Assets.Images["Icon_Tool_" .. toolId] or Assets.Images.Icon_Tool or ""
end

function AssetLibrary.carIcon(carId: string): string
	return Assets.Images["Icon_Car_" .. carId] or Assets.Images.Icon_Vehicle or ""
end

return AssetLibrary
