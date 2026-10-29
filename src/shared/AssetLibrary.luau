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
	if meta and meta.kind == "alien" then
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
	Disco = { rainbow = true, texture = "Vfx_Note", fx = Color3.fromRGB(255, 255, 255), size = 0.5, rate = 4, speed = 2, accel = Vector3.new(0, 2, 0), glow = 0.4 },
}

-- Mutation looks. Golden and Rainbow repaint the pet; Moon-Dusted keeps colours and sparkles.
function AssetLibrary.applyMutation(model: Model, mutation: string?)
	if not mutation then
		return
	end
	model:SetAttribute("Mutation", mutation)
	local body = model:FindFirstChild("Body") :: BasePart?
	if mutation == "Golden" or mutation == "Rainbow" then
		local i = 0
		for _, d in model:GetDescendants() do
			if d:IsA("MeshPart") and not d:GetAttribute("Glow") then
				i += 1
				d.TextureID = ""
				if mutation == "Golden" then
					d.Color = GOLD
					d.Material = Enum.Material.Foil
				else
					d.Color = Color3.fromHSV((i * 0.13) % 1, 0.7, 1)
					d:SetAttribute("RainbowOffset", i * 0.13)
				end
			end
		end
		if mutation == "Rainbow" then
			model:AddTag("RainbowPet")
		end
	end
	-- Weather mutations (Config/Weather): a recolour and/or a particle effect.
	local look = WEATHER_LOOKS[mutation]
	if look then
		if look.color then
			for _, d in model:GetDescendants() do
				if d:IsA("MeshPart") and not d:GetAttribute("Glow") then
					if look.repaint then
						d.TextureID = ""
						d.Color = look.color
					else
						d.Color = d.Color:Lerp(look.color, 0.45)
					end
					if look.material then
						d.Material = look.material
					end
				end
			end
		end
		if look.rainbow then
			local i = 0
			for _, d in model:GetDescendants() do
				if d:IsA("MeshPart") and not d:GetAttribute("Glow") then
					i += 1
					d.TextureID = ""
					d.Material = Enum.Material.Neon
					d:SetAttribute("RainbowOffset", i * 0.21)
				end
			end
			model:AddTag("RainbowPet")
		end
		if body then
			local fx = Instance.new("ParticleEmitter")
			fx.Name = "MutationSparkles"
			fx.Texture = Assets.Images[look.texture] or "rbxasset://textures/particles/sparkles_main.dds"
			fx.Color = ColorSequence.new(look.fx)
			fx.Size = NumberSequence.new(look.size or 0.35, 0)
			fx.Rate = look.rate or 6
			fx.Lifetime = NumberRange.new(0.8, 1.4)
			fx.Speed = NumberRange.new(look.speed or 1, (look.speed or 1) * 1.6)
			fx.SpreadAngle = Vector2.new(180, 180)
			fx.Acceleration = look.accel or Vector3.zero
			fx.Rotation = NumberRange.new(0, 360)
			fx.RotSpeed = NumberRange.new(-90, 90)
			fx.LightEmission = look.glow or 0.6
			fx.Parent = body
		end
		return
	end
	if body and (mutation == "MoonDusted" or mutation == "Golden") then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "MutationSparkles"
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(if mutation == "Golden" then GOLD else Color3.fromRGB(220, 235, 255))
		sparkles.Size = NumberSequence.new(0.35, 0)
		sparkles.Rate = 6
		sparkles.Lifetime = NumberRange.new(0.8, 1.4)
		sparkles.Speed = NumberRange.new(0.5, 1.5)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.LightEmission = 1
		sparkles.Parent = body
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
		return model
	end
	return EggModel.build(rarity)
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
