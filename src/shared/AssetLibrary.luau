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
local LimitedEgg = require(script.Parent.Config.LimitedEgg)

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

-- Milestones while the server loads models (AssetService): "EggsReady" (egg models in),
-- "CoreReady" (eggs and pets in), "Ready" (everything). Waits up to timeout seconds.
function AssetLibrary.waitFor(milestone: string, timeout: number?): boolean
	local f = folder() or ReplicatedStorage:WaitForChild(FOLDER_NAME, timeout or 30)
	if not f then
		return false
	end
	local deadline = os.clock() + (timeout or 30)
	while f:GetAttribute(milestone) ~= true and f:GetAttribute("Ready") ~= true and os.clock() < deadline do
		task.wait(0.2)
	end
	return f:GetAttribute(milestone) == true or f:GetAttribute("Ready") == true
end

-- Runs fn once the egg and pet models are in (right away if they already are), so views
-- built from placeholders can redraw.
function AssetLibrary.onCoreReady(fn: () -> ())
	task.spawn(function()
		if AssetLibrary.waitFor("CoreReady", 300) then
			fn()
		end
	end)
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

-- Voxel pets (art/blender/voxpets.py) don't get a coat: a mutation repaints the pet cube
-- by cube with its own palette skin (tools/pet_skins.py, images PetSkin_<Pet>_<Mutation>),
-- keeping the pixel shading and the eyes, plus square "pixel" particles that suit the
-- blocky look. Rainbow and Disco skins have 4 frames that PetController cycles.
type PixelFx = {
	texture: string?, -- Assets.Images name, default Vfx_Pixel
	colors: { Color3 },
	size: number,
	rate: number,
	speed: number,
	life: number?,
	accel: Vector3?,
	glow: number?,
	spin: boolean?,
}
type VoxelLook = { frames: number?, reflect: number?, fx: PixelFx }
local RAINBOW = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 200, 70),
	Color3.fromRGB(110, 240, 110),
	Color3.fromRGB(90, 180, 255),
	Color3.fromRGB(200, 110, 255),
}
local VOXEL_LOOKS: { [string]: VoxelLook } = {
	Golden = { reflect = 0.25, fx = { colors = { Color3.fromRGB(255, 236, 140), Color3.fromRGB(255, 200, 60) }, size = 0.14, rate = 5, speed = 0.5, accel = Vector3.new(0, 0.8, 0), glow = 1 } },
	MoonDusted = { reflect = 0.1, fx = { colors = { Color3.new(1, 1, 1), Color3.fromRGB(210, 205, 255) }, size = 0.12, rate = 9, speed = 0.3, glow = 1 } },
	Rainbow = { frames = 4, fx = { colors = RAINBOW, size = 0.13, rate = 7, speed = 0.6, accel = Vector3.new(0, 1, 0), glow = 0.8 } },
	Disco = { frames = 4, fx = { texture = "Vfx_Note", colors = RAINBOW, size = 0.45, rate = 3, speed = 1.5, accel = Vector3.new(0, 1.5, 0), glow = 0.5, spin = true } },
	Wet = { reflect = 0.3, fx = { colors = { Color3.fromRGB(130, 190, 255) }, size = 0.09, rate = 6, speed = 0, life = 0.5, accel = Vector3.new(0, -14, 0), glow = 0.2 } },
	Frozen = { reflect = 0.2, fx = { colors = { Color3.new(1, 1, 1), Color3.fromRGB(200, 235, 255) }, size = 0.1, rate = 6, speed = 0.3, accel = Vector3.new(0, -1.5, 0), glow = 0.4 } },
	Shocked = { fx = { colors = { Color3.fromRGB(255, 243, 110), Color3.fromRGB(170, 150, 255) }, size = 0.09, rate = 16, speed = 5, life = 0.18, glow = 1 } },
	Windswept = { fx = { texture = "Vfx_Leaf", colors = { Color3.fromRGB(255, 150, 60), Color3.fromRGB(230, 90, 40) }, size = 0.3, rate = 3, speed = 2.5, accel = Vector3.new(-4, -1, 0), glow = 0, spin = true } },
	Bloodlit = { fx = { colors = { Color3.fromRGB(255, 74, 72), Color3.fromRGB(150, 10, 20) }, size = 0.12, rate = 7, speed = 0.4, accel = Vector3.new(0, 2, 0), glow = 1 } },
	Starlit = { fx = { colors = { Color3.fromRGB(184, 255, 240), Color3.new(1, 1, 1) }, size = 0.12, rate = 8, speed = 0.15, glow = 1 } },
	Starstruck = { fx = { colors = { Color3.fromRGB(255, 244, 196), Color3.fromRGB(255, 210, 90) }, size = 0.14, rate = 8, speed = 0.9, glow = 1 } },
}

local function pixelSparkles(body: BasePart, fx: PixelFx)
	local e = Instance.new("ParticleEmitter")
	e.Name = "MutationSparkles"
	e.Texture = Assets.Images[fx.texture or "Vfx_Pixel"] or "rbxasset://textures/particles/sparkles_main.dds"
	local keys = {}
	for i, c in fx.colors do
		table.insert(keys, ColorSequenceKeypoint.new(if #fx.colors == 1 then 0 else (i - 1) / (#fx.colors - 1), c))
	end
	if #keys == 1 then
		table.insert(keys, ColorSequenceKeypoint.new(1, fx.colors[1]))
	end
	e.Color = ColorSequence.new(keys)
	-- Pixels hold their size, then blink out (no soft shrink).
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, fx.size),
		NumberSequenceKeypoint.new(0.85, fx.size),
		NumberSequenceKeypoint.new(1, 0),
	})
	local life = fx.life or 1.2
	e.Lifetime = NumberRange.new(life * 0.7, life * 1.3)
	e.Rate = fx.rate
	e.Speed = NumberRange.new(fx.speed * 0.5, fx.speed * 1.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = fx.accel or Vector3.zero
	e.LightEmission = fx.glow or 0.6
	if fx.spin then
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-90, 90)
	end
	e.Parent = body
end

-- Always-on auras for the top pets (meta.aura from voxpets.py), in the same pixel style.
local AURAS: { [string]: PixelFx } = {
	Embers = { colors = { Color3.fromRGB(255, 190, 70), Color3.fromRGB(230, 60, 30) }, size = 0.11, rate = 6, speed = 0.6, accel = Vector3.new(0, 2.5, 0), glow = 1 },
	PhoenixFlame = { colors = { Color3.fromRGB(255, 240, 140), Color3.fromRGB(255, 120, 30), Color3.fromRGB(220, 40, 20) }, size = 0.14, rate = 14, speed = 0.8, life = 0.9, accel = Vector3.new(0, 4, 0), glow = 1 },
	FoxFire = { colors = { Color3.fromRGB(150, 230, 255), Color3.fromRGB(90, 140, 255) }, size = 0.13, rate = 5, speed = 0.3, life = 1.6, accel = Vector3.new(0, 0.6, 0), glow = 1 },
	Bubbles = { colors = { Color3.fromRGB(190, 240, 255), Color3.fromRGB(120, 210, 230) }, size = 0.13, rate = 6, speed = 0.3, life = 1.8, accel = Vector3.new(0, 1.5, 0), glow = 0.5 },
	Gloom = { colors = { Color3.fromRGB(120, 96, 160), Color3.fromRGB(60, 52, 84) }, size = 0.16, rate = 6, speed = 0.25, life = 1.8, accel = Vector3.new(0, -0.5, 0), glow = 0.4 },
	Frost = { colors = { Color3.fromRGB(200, 244, 255), Color3.fromRGB(120, 200, 255) }, size = 0.12, rate = 8, speed = 0.5, life = 1.2, accel = Vector3.new(0, -1, 0), glow = 0.8 },
	Snowfall = { colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(214, 232, 255) }, size = 0.15, rate = 9, speed = 0.3, life = 2.4, accel = Vector3.new(0, -1.4, 0), glow = 0.2 },
	Petals = { texture = "Vfx_Leaf", colors = { Color3.fromRGB(255, 150, 210), Color3.fromRGB(255, 200, 235), Color3.fromRGB(190, 140, 255) }, size = 0.3, rate = 5, speed = 0.4, life = 2.2, accel = Vector3.new(0, -1, 0), glow = 0.3, spin = true },
	Sparks = { colors = { Color3.fromRGB(255, 80, 220), Color3.fromRGB(90, 240, 255) }, size = 0.1, rate = 8, speed = 1.2, life = 0.5, accel = Vector3.new(0, -6, 0), glow = 1 },
	Aurora = { colors = { Color3.fromRGB(90, 255, 176), Color3.fromRGB(79, 216, 255), Color3.fromRGB(176, 122, 255) }, size = 0.16, rate = 8, speed = 0.3, life = 2, accel = Vector3.new(0, 0.8, 0), glow = 1 },
	Spores = { colors = { Color3.fromRGB(170, 255, 120), Color3.fromRGB(110, 210, 90), Color3.fromRGB(255, 160, 220) }, size = 0.13, rate = 6, speed = 0.3, life = 2, accel = Vector3.new(0, 0.7, 0), glow = 0.7 },
	GoldDust = { colors = { Color3.fromRGB(255, 226, 120), Color3.fromRGB(255, 255, 230) }, size = 0.12, rate = 7, speed = 0.4, life = 1.4, accel = Vector3.new(0, -0.6, 0), glow = 1 },
	Leaves = { texture = "Vfx_Leaf", colors = { Color3.fromRGB(255, 170, 50), Color3.fromRGB(220, 80, 40), Color3.fromRGB(250, 210, 80) }, size = 0.35, rate = 4, speed = 0.4, life = 2.2, accel = Vector3.new(0, -1.2, 0), glow = 0.3, spin = true },
}

local function skinId(alienId: string, name: string): string?
	return Assets.Images[`PetSkin_{alienId}_{name}`]
end

-- Repaints a voxel pet for a mutation. False when it has no skin for it (then the
-- coat is used).
local function applyVoxelSkin(model: Model, mutation: string): boolean
	local alienId = model:GetAttribute("AlienId")
	local look = VOXEL_LOOKS[mutation]
	local meta = type(alienId) == "string" and Assets.Models["Alien_" .. alienId]
	if not (look and meta and (meta :: any).voxel) then
		return false
	end
	local frames = {}
	for f = 0, (look.frames or 1) - 1 do
		local id = skinId(alienId :: string, if look.frames then `{mutation}_{f}` else mutation)
		if not id then
			return false
		end
		table.insert(frames, id)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") and not d:GetAttribute("Glow") and d.TextureID ~= "" then
			d.TextureID = frames[1]
			d.Reflectance = look.reflect or 0
			d:SetAttribute("VoxelSkin", true)
		end
	end
	if #frames > 1 then
		model:SetAttribute("SkinFrames", table.concat(frames, ","))
		model:AddTag("SkinCyclePet")
	end
	local body = (model:FindFirstChild("Body") or model.PrimaryPart) :: BasePart?
	if body then
		pixelSparkles(body, look.fx)
	end
	return true
end

-- Weather-upgraded eggs: the bricks get the mutation's own paint job (tools/egg_skins.py)
-- and its 3D add-on (art/blender/egg_mutations.py: snow cap and icicles, puddle and drips,
-- lightning bolts, leaf ring, blood moon, stars, a star stuck in the top, gold coins, a
-- rainbow, a disco ball). Dev found the see-through coat on eggs ugly (2026-10-29).
type EggAddPart = { material: Enum.Material?, transparency: number?, reflectance: number?, onTop: boolean? }
local EGG_ADD_PARTS: { [string]: EggAddPart } = {
	Ice = { material = Enum.Material.Ice, transparency = 0.15 },
	Snow = { material = Enum.Material.Sand },
	Water = { material = Enum.Material.Glass, transparency = 0.35, reflectance = 0.15 },
	Gold = { reflectance = 0.3 },
	Ball = { reflectance = 0.45, onTop = true },
	Moon = { onTop = true },
	Star = { reflectance = 0.15, onTop = true },
}
local EGG_TOP = 3.2 -- top of a plain egg at scale 1; toppers (sprout, crown...) go above

local function applyEggMutation(model: Model, mutation: string): boolean
	if model:GetAttribute("Kind") ~= "egg" then
		return false
	end
	local rarity = model:GetAttribute("EggRarity") or model:GetAttribute("Rarity")
	local skin = if type(rarity) == "string" then Assets.Images[`EggSkin_{rarity}_{mutation}`] else nil
	if not skin then
		return false
	end
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") and d.TextureID ~= "" and not d:GetAttribute("Glow") then
			d.TextureID = skin
		end
	end
	local add = AssetLibrary.get("EggMut_" .. mutation)
	if add then
		local scale = model:GetScale()
		local pivot = model:GetPivot()
		-- How far the egg's own topper sticks up above a plain egg (in scale-1 studs).
		local box, size = model:GetBoundingBox()
		local top = (pivot:PointToObjectSpace(box.Position).Y + size.Y / 2) / scale
		local lift = math.max(0, top - EGG_TOP)
		add:ScaleTo(scale)
		add:PivotTo(pivot)
		local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		for _, part in add:GetChildren() do
			if not part:IsA("BasePart") then
				continue
			end
			local look = EGG_ADD_PARTS[part.Name]
			if look then
				if look.material and not part:GetAttribute("Glow") then
					part.Material = look.material
				end
				part.Transparency = look.transparency or part.Transparency
				part.Reflectance = look.reflectance or 0
				if look.onTop and lift > 0 then
					part.CFrame = pivot * CFrame.new(0, lift * scale, 0) * pivot:ToObjectSpace(part.CFrame)
				end
			end
			part.Name = "Mutation" .. part.Name
			part:SetAttribute("MutationAddOn", true)
			part.CastShadow = false
			part.CanCollide = false
			part.CanTouch = false
			part.Massless = true
			if anchor and not anchor.Anchored then
				part.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = anchor
				weld.Part1 = part
				weld.Parent = part
			else
				part.Anchored = true
			end
			part.Parent = model
		end
		add:Destroy()
	end
	return true
end

function AssetLibrary.applyMutation(model: Model, mutation: string?)
	if not mutation or model:GetAttribute("CoatFor") == mutation then
		return
	end
	model:SetAttribute("Mutation", mutation)
	model:SetAttribute("CoatFor", mutation)
	if applyVoxelSkin(model, mutation) then
		return
	end
	local eggDone = applyEggMutation(model, mutation)
	-- Pets sparkle from their Body; eggs (no Body) from their main part.
	local body = (model:FindFirstChild("Body") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")) :: BasePart?
	local coat = COATS[mutation]
	if coat and not eggDone then
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
	local meta = Assets.Models["Alien_" .. alienId]
	local aura = meta and AURAS[(meta :: any).aura or ""]
	local body = model:FindFirstChild("Body") :: BasePart?
	if aura and body then
		pixelSparkles(body, aura)
		local fx = body:FindFirstChild("MutationSparkles")
		if fx then
			fx.Name = "Aura"
		end
	end
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
		model:SetAttribute("EggRarity", rarity)
		AssetLibrary.eggExtras(model, rarity)
		return model
	end
	local placeholder = EggModel.build(rarity)
	placeholder:SetAttribute("Placeholder", true)
	return placeholder
end

-- The model for one egg ({ Rarity, Zone?, Mutation? }: a bag egg, a hatching entry...).
-- The limited egg (Config/LimitedEgg) uses its own model "Egg_<Id>" once that is uploaded,
-- and until then the base rarity's egg in its skin, so it looks the same everywhere.
function AssetLibrary.eggOf(entry: { Rarity: string, Zone: string?, Mutation: string? }): Model
	if LimitedEgg.isEgg(entry) then
		local own = AssetLibrary.get("Egg_" .. LimitedEgg.Id)
		if own then
			own.Name = LimitedEgg.Id .. "Egg"
			own:SetAttribute("EggRarity", LimitedEgg.EggRarity)
			own:SetAttribute("LimitedEgg", LimitedEgg.Id)
			AssetLibrary.eggExtras(own, LimitedEgg.Id)
			return own
		end
		local model = AssetLibrary.egg(LimitedEgg.EggRarity)
		AssetLibrary.applyMutation(model, LimitedEgg.EggMutation)
		return model
	end
	local model = AssetLibrary.egg(entry.Rarity)
	AssetLibrary.applyMutation(model, entry.Mutation)
	return model
end

-- The asset name ModelView waits for when showing eggOf(entry).
function AssetLibrary.eggKey(entry: { Rarity: string, Zone: string? }): string
	if LimitedEgg.isEgg(entry) then
		local own = "Egg_" .. LimitedEgg.Id
		return if Assets.Models[own] then own else "Egg_" .. LimitedEgg.EggRarity
	end
	return "Egg_" .. entry.Rarity
end

-- The limited egg itself (shop banner, purchase popup).
function AssetLibrary.limitedEgg(): Model
	return AssetLibrary.eggOf({ Rarity = LimitedEgg.EggRarity, Zone = LimitedEgg.Id })
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
-- Pets with their own animations (voxel pets: meta.anims) play those instead of the
-- shared Pet_Idle / Pet_Walk.
local OWN_ANIM = { Pet_Idle = "idle", Pet_Walk = "walk" }

local function ownAnimation(model: Instance, name: string): string?
	local key = OWN_ANIM[name]
	if not key then
		return nil
	end
	local holder = if model:IsA("Model") then model else model:FindFirstAncestorOfClass("Model")
	local alienId = holder and holder:GetAttribute("AlienId")
	local meta = if type(alienId) == "string" then Assets.Models["Alien_" .. alienId] else nil
	local anims = meta and (meta :: any).anims
	return anims and anims[key]
end

function AssetLibrary.loadTrack(model: Instance, name: string): AnimationTrack?
	local own = ownAnimation(model, name)
	local anim = (own and AssetLibrary.animation(own)) or AssetLibrary.animation(name)
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
