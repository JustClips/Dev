--!strict
-- Draws the live weather (Config/Weather) and the Egg Rain on this client: the sky
-- (lighting, atmosphere, colour grade, clouds), particles around the camera, things in the
-- sky (rainbow, aurora, disco ball), lightning, looping sounds and the weather banner.
-- Also draws every Egg Rain egg falling out of the sky to its landing mark.
-- Everything here is local to this client; the server only sends the state
-- (ServerState Weather / WeatherEndsAt / EventState) and the EggDrop / WeatherStrike events.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Eggs = require(Shared.Config.Eggs)
local Net = require(Shared.Net)
local Sounds = require(Shared.Config.Sounds)
local Weather = require(Shared.Config.Weather)

local WeatherController = {}

local C: any
local player = Players.LocalPlayer
local rng = Random.new()

local SKY_TWEEN = TweenInfo.new(4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local WIND = Vector3.new(1, 0, 0.35).Unit
local FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold)
local FONT_SEMI = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.SemiBold)

local folder: Folder -- every 3D thing this controller makes
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function img(name: string): string
	return AssetLibrary.image(name)
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Sky presets -------------------------------------------------------------------------
-- Each preset only lists what it changes; everything else goes back to the map's own
-- values (captured at start). Sky values are set at once (they can't tween).

type Preset = { [string]: { [string]: any } }

local PRESETS: { [string]: Preset } = {
	Rain = {
		Lighting = { Brightness = 1.4, Ambient = rgb(90, 95, 110), OutdoorAmbient = rgb(110, 115, 130), ColorShift_Top = rgb(200, 210, 225) },
		Atmosphere = { Density = 0.42, Color = rgb(170, 180, 195), Decay = rgb(110, 120, 140), Haze = 2.2, Glare = 0 },
		Grade = { Saturation = -0.08, TintColor = rgb(215, 225, 240), Brightness = -0.02 },
		Clouds = { Cover = 0.9, Density = 0.85, Color = rgb(150, 155, 165) },
	},
	Thunderstorm = {
		Lighting = { Brightness = 0.8, Ambient = rgb(60, 65, 85), OutdoorAmbient = rgb(75, 80, 100), ColorShift_Top = rgb(160, 170, 200) },
		Atmosphere = { Density = 0.5, Color = rgb(120, 125, 145), Decay = rgb(70, 75, 95), Haze = 2.6, Glare = 0 },
		Grade = { Saturation = -0.2, TintColor = rgb(190, 200, 225), Brightness = -0.05, Contrast = 0.12 },
		Clouds = { Cover = 0.97, Density = 1, Color = rgb(90, 92, 105) },
	},
	Snow = {
		Lighting = { Brightness = 2, Ambient = rgb(150, 160, 180), OutdoorAmbient = rgb(170, 180, 200), ColorShift_Top = rgb(220, 235, 255) },
		Atmosphere = { Density = 0.5, Color = rgb(220, 230, 245), Decay = rgb(180, 195, 220), Haze = 2.5, Glare = 0 },
		Grade = { Saturation = -0.1, TintColor = rgb(225, 238, 255), Brightness = 0.04 },
		Clouds = { Cover = 0.85, Density = 0.7, Color = rgb(235, 240, 250) },
	},
	Windy = {
		Lighting = { Brightness = 2.4, ColorShift_Top = rgb(255, 225, 190) },
		Atmosphere = { Density = 0.34, Color = rgb(230, 215, 190), Decay = rgb(170, 150, 120), Haze = 1.6 },
		Grade = { Saturation = 0.25, TintColor = rgb(255, 240, 215) },
		Clouds = { Cover = 0.72, Density = 0.55 },
	},
	Rainbow = {
		Lighting = { Brightness = 3 },
		Atmosphere = { Density = 0.22, Haze = 0.6 },
		Grade = { Saturation = 0.4, Brightness = 0.04, TintColor = rgb(255, 250, 255) },
		Clouds = { Cover = 0.45, Density = 0.4 },
	},
	GoldenHour = {
		Lighting = { ClockTime = 17.6, Brightness = 2.6, ColorShift_Top = rgb(255, 180, 90), Ambient = rgb(140, 110, 90), OutdoorAmbient = rgb(170, 130, 100) },
		Atmosphere = { Density = 0.35, Color = rgb(255, 200, 140), Decay = rgb(200, 120, 80), Glare = 0.6, Haze = 1.5 },
		Grade = { Saturation = 0.3, TintColor = rgb(255, 225, 180) },
		Clouds = { Color = rgb(255, 210, 160), Cover = 0.6 },
		Bloom = { Intensity = 0.7, Threshold = 1.4 },
		SunRays = { Intensity = 0.2, Spread = 0.7 },
	},
	BloodMoon = {
		Lighting = { ClockTime = 22, Brightness = 1.2, Ambient = rgb(120, 30, 35), OutdoorAmbient = rgb(150, 40, 45), ColorShift_Top = rgb(255, 60, 60) },
		Atmosphere = { Density = 0.45, Color = rgb(120, 20, 30), Decay = rgb(60, 0, 10), Haze = 1.5, Glare = 0.3 },
		Grade = { Saturation = 0.1, TintColor = rgb(255, 170, 170), Contrast = 0.15 },
		Clouds = { Color = rgb(90, 20, 25), Cover = 0.5 },
		Sky = { MoonTextureId = "Vfx_BloodMoon", MoonAngularSize = 24, StarCount = 1500 },
	},
	Aurora = {
		Lighting = { ClockTime = 22, Brightness = 1.4, Ambient = rgb(60, 90, 110), OutdoorAmbient = rgb(80, 120, 140), ColorShift_Top = rgb(150, 255, 220) },
		Atmosphere = { Density = 0.3, Color = rgb(60, 110, 120), Decay = rgb(20, 40, 70), Haze = 1 },
		Grade = { Saturation = 0.25, TintColor = rgb(205, 255, 240) },
		Clouds = { Cover = 0.25, Color = rgb(80, 120, 140) },
		Sky = { StarCount = 3000 },
	},
	Disco = {
		Lighting = { ClockTime = 21, Brightness = 1.2, Ambient = rgb(110, 70, 150), OutdoorAmbient = rgb(130, 80, 170) },
		Atmosphere = { Density = 0.35, Color = rgb(80, 40, 120), Decay = rgb(40, 10, 70), Haze = 1.2 },
		Grade = { Saturation = 0.35, Contrast = 0.1 },
		Clouds = { Cover = 0.3, Color = rgb(120, 70, 160) },
		Sky = { StarCount = 2500 },
		Bloom = { Intensity = 0.9, Threshold = 1.2 },
	},
	EggRain = {
		Lighting = { Brightness = 2, ColorShift_Top = rgb(255, 140, 90), Ambient = rgb(150, 110, 130), OutdoorAmbient = rgb(170, 120, 140) },
		Atmosphere = { Density = 0.35, Color = rgb(255, 190, 200), Decay = rgb(190, 110, 150), Haze = 1.8 },
		Grade = { Saturation = 0.25, TintColor = rgb(255, 225, 235) },
		Clouds = { Cover = 0.7, Color = rgb(255, 200, 215) },
		Bloom = { Intensity = 0.6, Threshold = 1.5 },
	},
}

local PROPS: { [string]: { string } } = {
	Lighting = { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ColorShift_Top", "ExposureCompensation" },
	Atmosphere = { "Density", "Color", "Decay", "Haze", "Glare" },
	Grade = { "Saturation", "TintColor", "Brightness", "Contrast" },
	Clouds = { "Cover", "Density", "Color" },
	Bloom = { "Intensity", "Threshold" },
	SunRays = { "Intensity", "Spread" },
	Sky = { "MoonTextureId", "MoonAngularSize", "StarCount" },
}

local targets: { [string]: any } = {}
local baseline: { [string]: { [string]: any } } = {}

local function capture()
	targets.Lighting = Lighting
	targets.Atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	targets.Grade = Lighting:FindFirstChild("WorldGrade") or Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	targets.Clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
	targets.Bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	targets.SunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	targets.Sky = Lighting:FindFirstChildOfClass("Sky")
	for group, props in PROPS do
		local target = targets[group] :: any
		if target then
			baseline[group] = {}
			for _, prop in props do
				baseline[group][prop] = target[prop]
			end
		end
	end
end

local function applySky(preset: Preset?)
	for group, props in PROPS do
		local target = targets[group] :: any
		local base = baseline[group]
		if not target or not base or not target.Parent then
			continue
		end
		local wanted = preset and preset[group] or {}
		if group == "Sky" then
			for _, prop in props do
				local value = wanted[prop]
				if prop == "MoonTextureId" and value then
					value = img(value)
				end
				target[prop] = if value ~= nil then value else base[prop]
			end
			continue
		end
		local goal = {}
		for _, prop in props do
			goal[prop] = if wanted[prop] ~= nil then wanted[prop] else base[prop]
		end
		TweenService:Create(target, SKY_TWEEN, goal):Play()
	end
end

-- Helpers --------------------------------------------------------------------------------

local function part(name: string, size: Vector3, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Parent = parent or folder
	return p
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0.3
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

local function seq(a: number, b: number?): NumberSequence
	return if b then NumberSequence.new(a, b) else NumberSequence.new(a)
end

local function fadeSeq(peak: number): NumberSequence
	-- Fades in and out so particles never pop.
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, peak),
		NumberSequenceKeypoint.new(0.8, peak),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, rgb(255, 90, 90)),
	ColorSequenceKeypoint.new(0.2, rgb(255, 170, 60)),
	ColorSequenceKeypoint.new(0.4, rgb(255, 235, 80)),
	ColorSequenceKeypoint.new(0.6, rgb(100, 230, 120)),
	ColorSequenceKeypoint.new(0.8, rgb(80, 170, 255)),
	ColorSequenceKeypoint.new(1, rgb(190, 100, 255)),
})

local function camera(): Camera?
	return Workspace.CurrentCamera
end

local function focus(): Vector3
	local cam = camera()
	return if cam then cam.Focus.Position else Vector3.zero
end

-- Ground height under a point (or the point itself when nothing is below).
local function groundAt(position: Vector3): Vector3
	local character = player.Character
	rayParams.FilterDescendantsInstances = if character then { folder, character } else { folder }
	local hit = Workspace:Raycast(position + Vector3.new(0, 80, 0), Vector3.new(0, -300, 0), rayParams)
	return if hit then hit.Position else position
end

-- A one-shot 3D sound at a spot.
local function soundAt(name: string, position: Vector3, volumeMult: number?, speed: number?)
	local def = Sounds.Sfx[name]
	if not def or def.Id == "" then
		return
	end
	local holder = Instance.new("Attachment")
	holder.WorldPosition = position
	holder.Parent = Workspace.Terrain
	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Volume = def.Volume * (volumeMult or 1)
	sound.PlaybackSpeed = speed or 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 30
	sound.RollOffMaxDistance = 600
	sound.SoundGroup = Ui.soundGroup("SFX")
	sound.Parent = holder
	sound:Play()
	task.delay(10, function()
		holder:Destroy()
	end)
end

-- Short camera shake (skipped with reduced motion).
local shakeUntil, shakePower = 0, 0
local function shake(power: number, seconds: number)
	if Ui.reducedMotion() then
		return
	end
	shakePower = math.max(if os.clock() < shakeUntil then shakePower else 0, power)
	shakeUntil = math.max(shakeUntil, os.clock() + seconds)
end

-- Screen flash for lightning (its own colour grade so it never fights the sky tween).
local flashGrade: ColorCorrectionEffect
local function flash(strength: number)
	flashGrade.Brightness = 0.45 * strength
	flashGrade.Contrast = 0.2 * strength
	TweenService:Create(flashGrade, TweenInfo.new(0.08), { Brightness = 0.05 * strength }):Play()
	task.delay(0.12, function()
		flashGrade.Brightness = 0.35 * strength
		TweenService:Create(flashGrade, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Brightness = 0, Contrast = 0 }):Play()
	end)
end

-- Weather scenes -------------------------------------------------------------------------
-- A scene builds its effects and returns an update(dt, focus, ground) and a cleanup.

type Scene = { update: ((number, Vector3, Vector3) -> ())?, parts: { Instance }, cleanup: { () -> () } }

local function newScene(): Scene
	return { parts = {}, cleanup = {} }
end

local function keep(scene: Scene, inst: Instance): any
	table.insert(scene.parts, inst)
	return inst
end

-- An invisible box that follows the camera focus; emitters inside it rain particles around the player.
local function follower(scene: Scene, name: string, size: Vector3): Part
	return keep(scene, part(name, size))
end

local function rain(scene: Scene, heavy: boolean)
	local sky = follower(scene, "RainSky", Vector3.new(160, 1, 160))
	emitter(sky, {
		Texture = img("Vfx_Rain"),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		EmissionDirection = Enum.NormalId.Bottom,
		Size = seq(if heavy then 2.8 else 2.4),
		Speed = NumberRange.new(if heavy then 120 else 95, if heavy then 140 else 110),
		Lifetime = NumberRange.new(0.75, 0.85),
		Rate = if heavy then 900 else 600,
		SpreadAngle = Vector2.new(4, 4),
		Acceleration = if heavy then WIND * 25 else Vector3.zero,
		Color = ColorSequence.new(rgb(205, 220, 240)),
		Transparency = seq(if heavy then 0.2 else 0.3),
		LightEmission = 0.15,
	})
	local ground = follower(scene, "RainSplash", Vector3.new(90, 0.2, 90))
	emitter(ground, {
		Texture = img("Vfx_Ring"),
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		Size = seq(0.1, 1.6),
		Speed = NumberRange.new(0.01),
		Lifetime = NumberRange.new(0.25, 0.35),
		Rate = if heavy then 220 else 150,
		Color = ColorSequence.new(rgb(220, 235, 255)),
		Transparency = seq(0.35, 1),
	})
	scene.update = function(_, at, floor)
		sky.CFrame = CFrame.new(at + Vector3.new(0, 70, 0))
		ground.CFrame = CFrame.new(floor + Vector3.new(0, 0.15, 0))
	end
end

local function lightningBolt(scene: Scene?, top: Vector3, bottom: Vector3, color: Color3)
	local bolt = Instance.new("Model")
	bolt.Name = "Bolt"
	local function segment(a: Vector3, b: Vector3, width: number)
		local p = part("Seg", Vector3.new(width, width, (b - a).Magnitude))
		p.CFrame = CFrame.lookAt((a + b) / 2, b)
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Transparency = 0
		p.Parent = bolt
	end
	local function zigzag(a: Vector3, b: Vector3, steps: number, jitter: number, width: number, branches: boolean)
		local last = a
		for i = 1, steps do
			local t = i / steps
			local point = a:Lerp(b, t)
			if i < steps then
				point += Vector3.new(rng:NextNumber(-jitter, jitter), 0, rng:NextNumber(-jitter, jitter))
			end
			segment(last, point, width)
			if branches and i > 1 and i < steps - 1 and rng:NextNumber() < 0.35 then
				local away = Vector3.new(rng:NextNumber(-1, 1), -rng:NextNumber(0.6, 1.2), rng:NextNumber(-1, 1)) * rng:NextNumber(25, 50)
				zigzag(point, point + away, 4, jitter * 0.5, width * 0.5, false)
			end
			last = point
		end
	end
	zigzag(top, bottom, 12, 9, 0.9, true)
	local glow = part("Glow", Vector3.new(1, 1, 1))
	glow.Position = bottom + Vector3.new(0, 3, 0)
	glow.Parent = bolt
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 60
	light.Brightness = 10
	light.Parent = glow
	bolt.Parent = folder
	if scene then
		keep(scene, bolt)
	end
	-- Flicker, then fade out.
	task.spawn(function()
		for _, t in { 0.06, 0.05, 0.07 } do
			task.wait(t)
			for _, p in bolt:GetChildren() do
				if p:IsA("BasePart") and p.Name == "Seg" then
					p.Transparency = if p.Transparency == 0 then 0.6 else 0
				end
			end
		end
		for _, p in bolt:GetChildren() do
			if p:IsA("BasePart") and p.Name == "Seg" then
				TweenService:Create(p, TweenInfo.new(0.35), { Transparency = 1 }):Play()
			end
		end
		TweenService:Create(light, TweenInfo.new(0.5), { Brightness = 0 }):Play()
		task.wait(0.6)
		bolt:Destroy()
	end)
end

local function sparkBurst(position: Vector3, color: Color3, count: number, texture: string?)
	local holder = part("Burst", Vector3.new(1, 1, 1))
	holder.Position = position
	local e = emitter(holder, {
		Texture = img(texture or "Vfx_Star"),
		Size = seq(1.4, 0),
		Speed = NumberRange.new(18, 40),
		Lifetime = NumberRange.new(0.4, 0.8),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -40, 0),
		Color = ColorSequence.new(color),
		LightEmission = 1,
		Rate = 0,
		Drag = 3,
	})
	e:Emit(count)
	task.delay(1.5, function()
		holder:Destroy()
	end)
end

local function smokePuff(position: Vector3, color: Color3, count: number, size: number)
	local holder = part("Puff", Vector3.new(2, 0.5, 2))
	holder.Position = position
	local e = emitter(holder, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Size = seq(size * 0.6, size * 1.6),
		Speed = NumberRange.new(8, 16),
		Lifetime = NumberRange.new(0.6, 1.1),
		SpreadAngle = Vector2.new(80, 80),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -6, 0),
		Drag = 4,
		Color = ColorSequence.new(color),
		Transparency = seq(0.35, 1),
		RotSpeed = NumberRange.new(-60, 60),
		Rotation = NumberRange.new(0, 360),
		Rate = 0,
	})
	e:Emit(count)
	task.delay(2, function()
		holder:Destroy()
	end)
end

local function shockRing(position: Vector3, color: Color3, from: number, to: number, seconds: number)
	local ring = part("Ring", Vector3.new(from, 0.05, from))
	ring.Position = position + Vector3.new(0, 0.12, 0)
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Top
	decal.Texture = img("Vfx_Ring")
	decal.Color3 = color
	decal.Parent = ring
	TweenService:Create(ring, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(to, 0.05, to) }):Play()
	TweenService:Create(decal, TweenInfo.new(seconds), { Transparency = 1 }):Play()
	task.delay(seconds + 0.1, function()
		ring:Destroy()
	end)
end

-- A lightning strike (Thunderstorm) where the server says, or a far one for the mood.
local STRIKE_COLOR = rgb(255, 250, 215)
local function strikeAt(position: Vector3, near: boolean)
	local floor = groundAt(position)
	local top = floor + Vector3.new(rng:NextNumber(-30, 30), 260, rng:NextNumber(-30, 30))
	lightningBolt(nil, top, floor, STRIKE_COLOR)
	flash(if near then 1 else 0.5)
	if near then
		sparkBurst(floor + Vector3.new(0, 1, 0), rgb(255, 230, 120), 40)
		smokePuff(floor, rgb(90, 90, 100), 14, 5)
		shockRing(floor, rgb(255, 230, 120), 4, 28, 0.6)
		local dist = (floor - focus()).Magnitude
		if dist < 120 then
			shake(0.6 * (1 - dist / 120), 0.35)
		end
	end
	soundAt("Thunder" .. rng:NextInteger(1, 3), floor, if near then 1 else 0.6, rng:NextNumber(0.85, 1.05))
end

local function snow(scene: Scene)
	local sky = follower(scene, "SnowSky", Vector3.new(170, 1, 170))
	emitter(sky, {
		Texture = img("Vfx_Snow"),
		EmissionDirection = Enum.NormalId.Bottom,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45, 0.2), NumberSequenceKeypoint.new(1, 0.45, 0.2) }),
		Speed = NumberRange.new(5, 8),
		Lifetime = NumberRange.new(8, 10),
		Rate = 260,
		SpreadAngle = Vector2.new(25, 25),
		Acceleration = WIND * 1.5,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
		Color = ColorSequence.new(rgb(255, 255, 255)),
		Transparency = fadeSeq(0.1),
		LightEmission = 0.35,
		LightInfluence = 0.2,
	})
	scene.update = function(_, at)
		sky.CFrame = CFrame.new(at + Vector3.new(0, 45, 0))
	end
end

local function windy(scene: Scene)
	-- Leaves blow across from upwind; the box faces the wind (its Right is the wind).
	local box = follower(scene, "WindLeaves", Vector3.new(40, 30, 170))
	local look = CFrame.lookAt(Vector3.zero, Vector3.new(WIND.Z, 0, -WIND.X)) -- RightVector = WIND
	for _, color in { rgb(255, 150, 50), rgb(255, 205, 60), rgb(220, 80, 40), rgb(150, 190, 70) } do
		emitter(box, {
			Texture = img("Vfx_Leaf"),
			EmissionDirection = Enum.NormalId.Right,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1, 0.4), NumberSequenceKeypoint.new(1, 1.1, 0.4) }),
			Speed = NumberRange.new(35, 55),
			Lifetime = NumberRange.new(4, 5),
			Rate = 22,
			SpreadAngle = Vector2.new(12, 25),
			Acceleration = Vector3.new(0, -3, 0),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-260, 260),
			Color = ColorSequence.new(color),
			Transparency = fadeSeq(0),
		})
	end
	emitter(box, {
		Texture = img("Vfx_Rain"),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		EmissionDirection = Enum.NormalId.Right,
		Size = seq(5),
		Speed = NumberRange.new(80, 110),
		Lifetime = NumberRange.new(1.4, 1.8),
		Rate = 28,
		SpreadAngle = Vector2.new(3, 3),
		Color = ColorSequence.new(rgb(255, 255, 255)),
		Transparency = fadeSeq(0.75),
		LightEmission = 0.3,
	})
	scene.update = function(_, at)
		box.CFrame = CFrame.new(at - WIND * 70 + Vector3.new(0, 12, 0)) * look
	end
end

local function motes(scene: Scene, texture: string, color: ColorSequence, rate: number, size: number, rise: number, boxSize: Vector3?)
	local box = follower(scene, "Motes", boxSize or Vector3.new(110, 24, 110))
	emitter(box, {
		Texture = img(texture),
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, size), NumberSequenceKeypoint.new(1, 0) }),
		Speed = NumberRange.new(rise * 0.5, rise),
		Lifetime = NumberRange.new(3, 5),
		Rate = rate,
		SpreadAngle = Vector2.new(30, 30),
		Acceleration = WIND * 0.6,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-40, 40),
		Color = color,
		LightEmission = 1,
		LightInfluence = 0,
	})
	return box
end

-- Things that hang in the sky far away and move with the camera (like a skybox).
local function skyAnchor(scene: Scene): Part
	return keep(scene, part("SkyAnchor", Vector3.new(1, 1, 1)))
end

local function attachment(parent: Instance, position: Vector3, axis: Vector3?): Attachment
	local a = Instance.new("Attachment")
	a.Position = position
	if axis then
		-- Beam curves bend along each attachment's X axis.
		local side = if math.abs(axis.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
		a.CFrame = CFrame.fromMatrix(position, axis, axis:Cross(side).Unit)
	end
	a.Parent = parent
	return a
end

local function rainbowArc(anchor: Part, distance: number, halfWidth: number, height: number, width: number, transparency: number)
	local dir = Vector3.new(-0.6, 0, -0.8).Unit
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local a0 = attachment(anchor, dir * distance - side * halfWidth, Vector3.yAxis)
	local a1 = attachment(anchor, dir * distance + side * halfWidth, Vector3.yAxis)
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.CurveSize0 = height
	beam.CurveSize1 = -height
	beam.Width0 = width
	beam.Width1 = width
	beam.Segments = 60
	beam.FaceCamera = true
	beam.Texture = img("Vfx_Rainbow")
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.TextureLength = 1
	beam.LightEmission = 0.5
	beam.LightInfluence = 0
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.12, transparency),
		NumberSequenceKeypoint.new(0.88, transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Parent = anchor
end

local function rainbow(scene: Scene)
	local anchor = skyAnchor(scene)
	rainbowArc(anchor, 520, 380, 560, 55, 0.25)
	rainbowArc(anchor, 560, 470, 700, 34, 0.7)
	local m = motes(scene, "Vfx_Star", RAINBOW, 30, 0.7, 2)
	scene.update = function(_, at, floor)
		anchor.CFrame = CFrame.new(Vector3.new(at.X, floor.Y - 40, at.Z))
		m.CFrame = CFrame.new(floor + Vector3.new(0, 8, 0))
	end
end

local function goldenHour(scene: Scene)
	local m1 = motes(scene, "Vfx_Glow", ColorSequence.new(rgb(255, 210, 110)), 45, 0.5, 1.5)
	local m2 = motes(scene, "Vfx_Star", ColorSequence.new(rgb(255, 230, 150)), 12, 0.8, 1)
	scene.update = function(_, _, floor)
		m1.CFrame = CFrame.new(floor + Vector3.new(0, 8, 0))
		m2.CFrame = CFrame.new(floor + Vector3.new(0, 8, 0))
	end
end

local function bloodMoon(scene: Scene)
	local embers = motes(scene, "Vfx_Glow", ColorSequence.new(rgb(255, 120, 60), rgb(160, 0, 0)), 70, 0.35, 3)
	scene.update = function(_, _, floor)
		embers.CFrame = CFrame.new(floor + Vector3.new(0, 6, 0))
	end
end

local function aurora(scene: Scene)
	local anchor = skyAnchor(scene)
	local colors = {
		ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(80, 255, 170)), ColorSequenceKeypoint.new(0.5, rgb(80, 220, 255)), ColorSequenceKeypoint.new(1, rgb(170, 100, 255)) }),
		ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(170, 100, 255)), ColorSequenceKeypoint.new(0.5, rgb(80, 255, 170)), ColorSequenceKeypoint.new(1, rgb(80, 220, 255)) }),
		ColorSequence.new(rgb(90, 255, 190)),
	}
	for i, color in colors do
		local z = -380 - i * 60
		local y = 170 + i * 25
		local a0 = attachment(anchor, Vector3.new(-560, y, z), Vector3.zAxis)
		local a1 = attachment(anchor, Vector3.new(560, y + 20, z), Vector3.zAxis)
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.CurveSize0 = 260 * (if i % 2 == 0 then -1 else 1)
		beam.CurveSize1 = 260 * (if i % 2 == 0 then -1 else 1)
		beam.Width0 = 170
		beam.Width1 = 140
		beam.Segments = 60
		beam.FaceCamera = true
		beam.Texture = img("Vfx_Aurora")
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = 260
		beam.TextureSpeed = 0.06 * i
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = color
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.35),
			NumberSequenceKeypoint.new(0.8, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Parent = anchor
	end
	local twinkles = motes(scene, "Vfx_Star", ColorSequence.new(rgb(180, 255, 230)), 14, 0.6, 1)
	local nextStar = 0
	scene.update = function(_, at, floor)
		anchor.CFrame = CFrame.new(Vector3.new(at.X, floor.Y, at.Z))
		twinkles.CFrame = CFrame.new(floor + Vector3.new(0, 10, 0))
		if os.clock() > nextStar then
			-- A shooting star across the sky.
			nextStar = os.clock() + rng:NextNumber(0.8, 2.2)
			local start = Vector3.new(at.X + rng:NextNumber(-300, 300), floor.Y + rng:NextNumber(200, 280), at.Z - rng:NextNumber(250, 450))
			local travel = Vector3.new(rng:NextNumber(-1, 1) * 260, -rng:NextNumber(60, 120), rng:NextNumber(-40, 40))
			local star = part("ShootingStar", Vector3.new(1.2, 1.2, 1.2))
			star.Shape = Enum.PartType.Ball
			star.Material = Enum.Material.Neon
			star.Color = rgb(220, 255, 245)
			star.Transparency = 0
			star.Position = start
			local t0 = attachment(star, Vector3.new(0, 0.5, 0))
			local t1 = attachment(star, Vector3.new(0, -0.5, 0))
			local trail = Instance.new("Trail")
			trail.Attachment0 = t0
			trail.Attachment1 = t1
			trail.Lifetime = 0.45
			trail.FaceCamera = true
			trail.LightEmission = 1
			trail.WidthScale = NumberSequence.new(1, 0)
			trail.Transparency = NumberSequence.new(0, 1)
			trail.Color = ColorSequence.new(rgb(200, 255, 240))
			trail.Parent = star
			local tween = TweenService:Create(star, TweenInfo.new(0.9, Enum.EasingStyle.Linear), { Position = start + travel })
			tween:Play()
			tween.Completed:Once(function()
				star:Destroy()
			end)
		end
	end
end

local function disco(scene: Scene)
	local ball = keep(scene, part("DiscoBall", Vector3.new(9, 9, 9)))
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Foil
	ball.Color = rgb(225, 225, 235)
	ball.Reflectance = 0.4
	ball.Transparency = 0
	local light = Instance.new("PointLight")
	light.Range = 40
	light.Brightness = 3
	light.Parent = ball
	local center = attachment(ball, Vector3.zero)
	local ground = keep(scene, part("DiscoFloor", Vector3.new(1, 1, 1)))
	local spots: { Attachment } = {}
	local beams: { Beam } = {}
	for i = 1, 8 do
		local spot = attachment(ground, Vector3.zero)
		table.insert(spots, spot)
		local beam = Instance.new("Beam")
		beam.Attachment0 = center
		beam.Attachment1 = spot
		beam.Width0 = 0.6
		beam.Width1 = 12
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new(0.45, 0.75)
		beam.Color = ColorSequence.new(Color3.fromHSV(i / 8, 0.8, 1))
		beam.Parent = ball
		table.insert(beams, beam)
	end
	local notes = motes(scene, "Vfx_Note", RAINBOW, 14, 1.1, 3, Vector3.new(60, 10, 60))
	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "WeatherDisco"
	tint.Parent = Lighting
	table.insert(scene.cleanup, function()
		tint:Destroy()
	end)
	scene.update = function(_, at, floor)
		local t = os.clock()
		ball.CFrame = CFrame.new(floor + Vector3.new(0, 38, 0)) * CFrame.Angles(0, t * 1.2, 0)
		ground.CFrame = CFrame.new(floor + Vector3.new(0, 0.2, 0))
		for i, spot in spots do
			local a = t * 0.9 + i * (math.pi * 2 / 8)
			local r = 18 + math.sin(t * 1.7 + i) * 12
			spot.Position = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			beams[i].Color = ColorSequence.new(Color3.fromHSV((i / 8 + t * 0.15) % 1, 0.8, 1))
		end
		light.Color = Color3.fromHSV((t * 0.4) % 1, 0.7, 1)
		tint.TintColor = Color3.fromHSV((t * 0.25) % 1, 0.18, 1)
		notes.CFrame = CFrame.new(at + Vector3.new(0, 2, 0))
	end
end

local function eggRainSky(scene: Scene)
	local sparkle = motes(scene, "Vfx_Star", ColorSequence.new(rgb(255, 200, 230), rgb(255, 240, 170)), 26, 0.7, 1.5)
	scene.update = function(_, _, floor)
		sparkle.CFrame = CFrame.new(floor + Vector3.new(0, 10, 0))
	end
end

local BUILDERS: { [string]: (Scene) -> () } = {
	Rain = function(scene)
		rain(scene, false)
	end,
	Thunderstorm = function(scene)
		rain(scene, true)
		local base = scene.update
		local nextFlash = os.clock() + 3
		scene.update = function(dt, at, floor)
			if base then
				base(dt, at, floor)
			end
			if os.clock() > nextFlash then
				-- Far-off lightning for the mood (the real strikes come from the server).
				nextFlash = os.clock() + rng:NextNumber(4, 9)
				local away = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit * rng:NextNumber(250, 420)
				strikeAt(Vector3.new(at.X, floor.Y, at.Z) + away, false)
			end
		end
	end,
	Snow = snow,
	Windy = windy,
	Rainbow = rainbow,
	GoldenHour = goldenHour,
	BloodMoon = bloodMoon,
	Aurora = aurora,
	Disco = disco,
	EggRain = eggRainSky,
}

-- Looping sound beds ----------------------------------------------------------------------

local function loopSound(scene: Scene, id: string)
	local def = Sounds.Weather[id]
	if not def then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "Weather_" .. id
	sound.SoundId = def.Id
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = Ui.soundGroup(if def.Music then "Music" else "SFX")
	sound.Parent = SoundService
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(3), { Volume = def.Volume }):Play()
	if def.Music and C.AudioController.SetMusicDuck then
		C.AudioController:SetMusicDuck(0)
	end
	table.insert(scene.cleanup, function()
		TweenService:Create(sound, TweenInfo.new(2.5), { Volume = 0 }):Play()
		task.delay(2.6, function()
			sound:Destroy()
		end)
		if def.Music and C.AudioController.SetMusicDuck then
			C.AudioController:SetMusicDuck(1)
		end
	end)
end

-- Banner: name + one line, no box, fades in and out at the top of the screen ------------

local bannerGui: ScreenGui
local bannerToken = 0

local function makeBanner()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WeatherBanner"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Enabled = false
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.fromScale(0.5, 0.15)
	holder.Size = UDim2.fromOffset(640, 130)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = holder
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.fromScale(0.5, 0)
	icon.Size = UDim2.fromOffset(56, 56)
	icon.BackgroundTransparency = 1
	icon.Parent = holder
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, 58)
	title.Size = UDim2.new(1, 0, 0, 44)
	title.BackgroundTransparency = 1
	title.FontFace = FONT
	title.TextSize = 40
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Parent = holder
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = rgb(21, 21, 28)
	stroke.Parent = title
	local line = Instance.new("TextLabel")
	line.Name = "Line"
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.new(0.5, 0, 0, 100)
	line.Size = UDim2.new(1, 0, 0, 24)
	line.BackgroundTransparency = 1
	line.FontFace = FONT_SEMI
	line.TextSize = 18
	line.TextColor3 = Color3.new(1, 1, 1)
	line.TextWrapped = true
	line.Parent = holder
	local stroke2 = Instance.new("UIStroke")
	stroke2.Thickness = 2
	stroke2.Color = rgb(21, 21, 28)
	stroke2.Parent = line
	gui.Parent = player:WaitForChild("PlayerGui")
	bannerGui = gui
end

local function showBanner(name: string, line: string, color: Color3, icon: string)
	bannerToken += 1
	local token = bannerToken
	local holder = bannerGui:FindFirstChild("Holder") :: Frame
	local title = holder:FindFirstChild("Title") :: TextLabel
	local sub = holder:FindFirstChild("Line") :: TextLabel
	local image = holder:FindFirstChild("Icon") :: ImageLabel
	local scale = holder:FindFirstChild("Scale") :: UIScale
	title.Text = string.upper(name)
	title.TextColor3 = color
	sub.Text = line
	image.Image = img(icon)
	local fadeIn = TweenInfo.new(0.35)
	for _, label in { title, sub } do
		label.TextTransparency = 1
		TweenService:Create(label, fadeIn, { TextTransparency = 0 }):Play()
		local s = label:FindFirstChildOfClass("UIStroke") :: UIStroke
		s.Transparency = 1
		TweenService:Create(s, fadeIn, { Transparency = 0 }):Play()
	end
	image.ImageTransparency = 1
	TweenService:Create(image, fadeIn, { ImageTransparency = 0 }):Play()
	local base = Ui.scale()
	scale.Scale = base * (if Ui.reducedMotion() then 1 else 0.7)
	TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = base }):Play()
	bannerGui.Enabled = true
	task.delay(4.5, function()
		if token ~= bannerToken then
			return
		end
		local fadeOut = TweenInfo.new(0.6)
		for _, label in { title, sub } do
			TweenService:Create(label, fadeOut, { TextTransparency = 1 }):Play()
			TweenService:Create(label:FindFirstChildOfClass("UIStroke") :: UIStroke, fadeOut, { Transparency = 1 }):Play()
		end
		TweenService:Create(image, fadeOut, { ImageTransparency = 1 }):Play()
		task.wait(0.65)
		if token == bannerToken then
			bannerGui.Enabled = false
		end
	end)
end

-- Mode switching --------------------------------------------------------------------------

local mode = ""
local scene: Scene? = nil

local function endScene()
	local old = scene
	scene = nil
	if not old then
		return
	end
	for _, fn in old.cleanup do
		task.spawn(fn)
	end
	-- Let particles stop and fade instead of vanishing.
	for _, inst in old.parts do
		for _, d in inst:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				d.Enabled = false
			elseif d:IsA("Beam") then
				TweenService:Create(d, TweenInfo.new(2), { Width0 = 0, Width1 = 0 }):Play()
			end
		end
	end
	task.delay(3, function()
		for _, inst in old.parts do
			inst:Destroy()
		end
	end)
end

local function currentMode(): string
	local event = State.server("EventState")
	if event == "Shower" or event == "Countdown" then
		return "EggRain"
	end
	local weather = State.server("Weather")
	return if type(weather) == "string" then weather else ""
end

local function refresh(announce: boolean)
	local wanted = currentMode()
	if wanted == mode then
		return
	end
	mode = wanted
	endScene()
	applySky(PRESETS[wanted])
	local builder = BUILDERS[wanted]
	if builder then
		local s = newScene()
		builder(s)
		loopSound(s, wanted)
		scene = s
	end
	local def = Weather.ById[wanted]
	if announce and def then
		showBanner(def.Name, def.Blurb, def.Color, "Icon_Weather_" .. def.Id)
		Ui.sound(if def.Id == "BloodMoon" then "BloodMoonStart" else "WeatherStart")
	end
end

-- Egg Rain: eggs fall out of the sky --------------------------------------------------------

local function eggDrop(position: Vector3, rarity: string, fallSeconds: number)
	local floor = groundAt(position)
	if (floor - focus()).Magnitude > 700 then
		return
	end
	local def = Eggs.ByName[rarity]
	local color = if def then def.Color else Color3.new(1, 1, 1)
	local fall = math.max(0.6, fallSeconds - 0.1)

	-- Landing mark: a ring that tightens as the egg comes down, and a light pillar.
	local mark = part("EggMark", Vector3.new(14, 0.05, 14))
	mark.Position = floor + Vector3.new(0, 0.12, 0)
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Top
	decal.Texture = img("Vfx_Ring")
	decal.Color3 = color
	decal.Transparency = 0.7
	decal.Parent = mark
	TweenService:Create(mark, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(4.5, 0.05, 4.5) }):Play()
	TweenService:Create(decal, TweenInfo.new(fall), { Transparency = 0 }):Play()
	local bottom = attachment(mark, Vector3.zero)
	local top = attachment(mark, Vector3.new(0, 160, 0))
	local pillar = Instance.new("Beam")
	pillar.Attachment0 = bottom
	pillar.Attachment1 = top
	pillar.Width0 = 3.5
	pillar.Width1 = 1
	pillar.FaceCamera = true
	pillar.LightEmission = 1
	pillar.LightInfluence = 0
	pillar.Color = ColorSequence.new(color)
	pillar.Transparency = NumberSequence.new(0.55, 1)
	pillar.Parent = mark

	-- The egg itself, spinning, with a glowing trail.
	local egg = AssetLibrary.egg(rarity)
	for _, d in egg:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local _, size = egg:GetBoundingBox()
	local carrier = part("EggCarrier", Vector3.new(1, 1, 1))
	carrier.Parent = egg
	local t0 = attachment(carrier, Vector3.new(0, size.Y * 0.35, 0))
	local t1 = attachment(carrier, Vector3.new(0, -size.Y * 0.35, 0))
	local trail = Instance.new("Trail")
	trail.Attachment0 = t0
	trail.Attachment1 = t1
	trail.Lifetime = 0.35
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Parent = carrier
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 18
	light.Brightness = 3
	light.Parent = carrier
	emitter(carrier, {
		Texture = img("Vfx_Star"),
		Size = seq(0.9, 0),
		Speed = NumberRange.new(1, 3),
		Lifetime = NumberRange.new(0.4, 0.7),
		SpreadAngle = Vector2.new(180, 180),
		Color = ColorSequence.new(color),
		LightEmission = 1,
		Rate = 30,
		Shape = Enum.ParticleEmitterShape.Sphere,
	})
	egg.Parent = folder

	local drift = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit * rng:NextNumber(25, 55)
	local start = floor + drift + Vector3.new(0, 220, 0)
	local spinAxis = Vector3.new(rng:NextNumber(-1, 1), 1, rng:NextNumber(-1, 1)).Unit
	local began = os.clock()
	local whistled = false
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - began) / fall, 0, 1)
		local eased = t * t
		local at = start:Lerp(floor, eased)
		-- Spin around the egg's middle; upright again when it lands.
		local spin = CFrame.fromAxisAngle(spinAxis, (1 - t) * 9)
		egg:PivotTo(CFrame.new(at + Vector3.new(0, size.Y / 2, 0)) * spin * CFrame.new(0, -size.Y / 2, 0))
		carrier.Position = at + Vector3.new(0, size.Y * 0.5, 0)
		if not whistled and t > 0.05 then
			whistled = true
			soundAt("EggFall", floor, 0.8)
		end
		if t >= 1 then
			conn:Disconnect()
			-- Landing: dust, a ring, sparkles; the server's egg appears right here.
			mark:Destroy()
			smokePuff(floor, rgb(205, 190, 160), 12, 3)
			shockRing(floor, color, 3, 20, 0.5)
			sparkBurst(floor + Vector3.new(0, 1.5, 0), color, 22)
			soundAt("EggLand", floor)
			soundAt("Pop", floor, 0.8)
			local dist = (floor - focus()).Magnitude
			if dist < 60 then
				shake(0.25 * (1 - dist / 60), 0.2)
			end
			egg:Destroy()
		end
	end)
end

-- Start -------------------------------------------------------------------------------------

function WeatherController:Init(controllers)
	C = controllers
	folder = Instance.new("Folder")
	folder.Name = "WeatherFx"
	folder.Parent = Workspace
	flashGrade = Instance.new("ColorCorrectionEffect")
	flashGrade.Name = "WeatherFlash"
	flashGrade.Parent = Lighting
end

function WeatherController:Start()
	makeBanner()
	-- The map's own sky is set up by the server at start; give it a moment to replicate.
	task.wait(1)
	capture()
	refresh(false)
	local state = State.serverState
	state:GetAttributeChangedSignal("Weather"):Connect(function()
		refresh(true)
	end)
	state:GetAttributeChangedSignal("EventState"):Connect(function()
		refresh(true)
	end)

	Net.event("EggDrop").OnClientEvent:Connect(function(position: Vector3, rarity: string, fallSeconds: number)
		eggDrop(position, rarity, fallSeconds)
	end)
	Net.event("WeatherStrike").OnClientEvent:Connect(function(position: Vector3)
		if (position - focus()).Magnitude < 900 then
			strikeAt(position, true)
		end
	end)

	local lastGround = Vector3.zero
	local groundCheck = 0
	RunService.RenderStepped:Connect(function(dt)
		local s = scene
		local at = focus()
		groundCheck -= dt
		if groundCheck <= 0 then
			groundCheck = 0.2
			lastGround = groundAt(at)
		end
		if s and s.update then
			s.update(dt, at, Vector3.new(at.X, lastGround.Y, at.Z))
		end
	end)
	-- Camera shake on top of whatever the camera scripts did this frame.
	RunService:BindToRenderStep("WeatherShake", Enum.RenderPriority.Camera.Value + 1, function()
		local cam = camera()
		if cam and os.clock() < shakeUntil then
			local left = (shakeUntil - os.clock())
			local p = shakePower * math.min(1, left * 4)
			cam.CFrame *= CFrame.Angles(rng:NextNumber(-p, p) * 0.03, rng:NextNumber(-p, p) * 0.03, 0)
				* CFrame.new(rng:NextNumber(-p, p), rng:NextNumber(-p, p), 0)
		end
	end)
end

return WeatherController
