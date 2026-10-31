--!strict
-- Draws the live weather (Config/Weather) on this client:
--   * the day/night cycle (ClockTime follows ServerState.CycleStart),
--   * the sky for the current weather / moon / Egg Rain (lighting, atmosphere, grade, clouds),
--   * each weather's scene: particles around the camera, things in the sky (rainbow over the
--     map, aurora, disco ball and lights), lightning and falling stars, looping sounds,
--   * the banner when a weather or moon starts,
--   * Egg Rain / Mega Moon eggs falling out of the sky, and eggs being upgraded.
-- Everything here is local; the server only sends state (ServerState attributes) and the
-- EggDrop / WeatherStrike / EggUpgraded events.
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
local Grid = require(Shared.Grid)
local Net = require(Shared.Net)
local SkyLooks = require(Shared.Config.SkyLooks)
local Sounds = require(Shared.Config.Sounds)
local Weather = require(Shared.Config.Weather)
local Zones = require(Shared.Config.Zones)

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

-- The whole map (every zone), for things that should span it.
local MAP_MIN, MAP_MAX = Vector2.new(math.huge, math.huge), Vector2.new(-math.huge, -math.huge)
for _, zone in Zones.List do
	MAP_MIN = Vector2.new(math.min(MAP_MIN.X, zone.Min.X), math.min(MAP_MIN.Y, zone.Min.Y))
	MAP_MAX = Vector2.new(math.max(MAP_MAX.X, zone.Max.X), math.max(MAP_MAX.Y, zone.Max.Y))
end

-- Sky presets -------------------------------------------------------------------------------
-- Each preset only lists what it changes; everything else goes back to the map's own values
-- (captured at start). Sky values are set at once (they can't tween). ClockTime is not in
-- here: the day/night cycle drives it.

type Preset = { [string]: { [string]: any } }

local PRESETS: { [string]: Preset } = {
	Night = {
		Lighting = { Brightness = 1.2, Ambient = rgb(60, 66, 95), OutdoorAmbient = rgb(80, 90, 130), ColorShift_Top = rgb(170, 190, 255) },
		Atmosphere = { Density = 0.3, Color = rgb(70, 85, 130), Decay = rgb(30, 40, 80), Haze = 1, Glare = 0 },
		Grade = { TintColor = rgb(210, 220, 255), Saturation = 0.05 },
		Clouds = { Color = rgb(90, 100, 140), Cover = 0.45 },
		Sky = { StarCount = 3000 },
	},
	Rain = {
		Lighting = { Brightness = 1.3, Ambient = rgb(90, 95, 110), OutdoorAmbient = rgb(105, 112, 128), ColorShift_Top = rgb(195, 205, 225), EnvironmentSpecularScale = 1, EnvironmentDiffuseScale = 0.4 },
		Atmosphere = { Density = 0.45, Color = rgb(165, 175, 192), Decay = rgb(105, 115, 135), Haze = 2.4, Glare = 0 },
		Grade = { Saturation = -0.12, TintColor = rgb(212, 222, 240), Brightness = -0.03, Contrast = 0.05 },
		Clouds = { Cover = 0.92, Density = 0.9, Color = rgb(140, 146, 158) },
	},
	Thunderstorm = {
		Lighting = { Brightness = 0.7, Ambient = rgb(55, 60, 82), OutdoorAmbient = rgb(70, 76, 98), ColorShift_Top = rgb(150, 160, 200), EnvironmentSpecularScale = 1, EnvironmentDiffuseScale = 0.35 },
		Atmosphere = { Density = 0.52, Color = rgb(110, 116, 138), Decay = rgb(60, 66, 88), Haze = 2.8, Glare = 0 },
		Grade = { Saturation = -0.22, TintColor = rgb(185, 196, 228), Brightness = -0.06, Contrast = 0.15 },
		Clouds = { Cover = 0.98, Density = 1, Color = rgb(80, 82, 96) },
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
		Atmosphere = { Density = 0.18, Haze = 0.4, Glare = 0.3 },
		Grade = { Saturation = 0.4, Brightness = 0.04, TintColor = rgb(255, 250, 255) },
		Clouds = { Cover = 0.4, Density = 0.4 },
		Bloom = { Intensity = 0.6, Threshold = 1.6 },
	},
	GoldenHour = {
		Lighting = { Brightness = 2.6, ColorShift_Top = rgb(255, 180, 90), Ambient = rgb(140, 110, 90), OutdoorAmbient = rgb(170, 130, 100) },
		Atmosphere = { Density = 0.35, Color = rgb(255, 200, 140), Decay = rgb(200, 120, 80), Glare = 0.6, Haze = 1.5 },
		Grade = { Saturation = 0.3, TintColor = rgb(255, 225, 180) },
		Clouds = { Color = rgb(255, 210, 160), Cover = 0.6 },
		Bloom = { Intensity = 0.7, Threshold = 1.4 },
		SunRays = { Intensity = 0.2, Spread = 0.7 },
	},
	Starfall = {
		Lighting = { Brightness = 0.9, ExposureCompensation = -0.5, Ambient = rgb(80, 75, 110), OutdoorAmbient = rgb(100, 95, 140), ColorShift_Top = rgb(255, 230, 170) },
		Atmosphere = { Density = 0.28, Color = rgb(90, 80, 130), Decay = rgb(40, 30, 80), Haze = 0.8 },
		Grade = { Saturation = 0.2, TintColor = rgb(235, 225, 255) },
		Clouds = { Cover = 0.2, Color = rgb(120, 110, 160) },
		Sky = { StarCount = 3000 },
		Bloom = { Intensity = 0.8, Threshold = 1.3 },
	},
	Aurora = {
		Lighting = { Brightness = 0.8, ExposureCompensation = -0.6, Ambient = rgb(60, 90, 110), OutdoorAmbient = rgb(80, 120, 140), ColorShift_Top = rgb(150, 255, 220) },
		Atmosphere = { Density = 0.3, Color = rgb(60, 110, 120), Decay = rgb(20, 40, 70), Haze = 1 },
		Grade = { Saturation = 0.25, TintColor = rgb(205, 255, 240) },
		Clouds = { Cover = 0.2, Color = rgb(80, 120, 140) },
		Sky = { StarCount = 3000 },
	},
	Disco = {
		Lighting = { Brightness = 0.6, ExposureCompensation = -1, Ambient = rgb(90, 60, 130), OutdoorAmbient = rgb(110, 70, 150), ColorShift_Top = rgb(255, 120, 255) },
		Atmosphere = { Density = 0.4, Color = rgb(60, 30, 100), Decay = rgb(30, 10, 60), Haze = 1.5 },
		Grade = { Saturation = 0.4, Contrast = 0.12 },
		Clouds = { Cover = 0.3, Color = rgb(100, 60, 140) },
		Sky = { StarCount = 3000 },
		Bloom = { Intensity = 1, Threshold = 1.1, Size = 40 },
	},
	EggRain = {
		Lighting = { Brightness = 2, ColorShift_Top = rgb(255, 140, 90), Ambient = rgb(150, 110, 130), OutdoorAmbient = rgb(170, 120, 140) },
		Atmosphere = { Density = 0.35, Color = rgb(255, 190, 200), Decay = rgb(190, 110, 150), Haze = 1.8 },
		Grade = { Saturation = 0.25, TintColor = rgb(255, 225, 235) },
		Clouds = { Cover = 0.7, Color = rgb(255, 200, 215) },
		Bloom = { Intensity = 0.6, Threshold = 1.5 },
	},
	BloodMoon = {
		Lighting = { Brightness = 1.2, Ambient = rgb(120, 30, 35), OutdoorAmbient = rgb(150, 40, 45), ColorShift_Top = rgb(255, 60, 60) },
		Atmosphere = { Density = 0.45, Color = rgb(120, 20, 30), Decay = rgb(60, 0, 10), Haze = 1.5, Glare = 0.3 },
		Grade = { Saturation = 0.1, TintColor = rgb(255, 165, 165), Contrast = 0.15 },
		Clouds = { Color = rgb(90, 20, 25), Cover = 0.5 },
		Sky = { MoonAngularSize = 0, CelestialBodiesShown = false, StarCount = 1500 },
	},
	GoldMoon = {
		Lighting = { Brightness = 1.4, Ambient = rgb(110, 95, 60), OutdoorAmbient = rgb(140, 120, 70), ColorShift_Top = rgb(255, 210, 110) },
		Atmosphere = { Density = 0.32, Color = rgb(120, 100, 50), Decay = rgb(60, 45, 20), Haze = 1.2, Glare = 0.4 },
		Grade = { Saturation = 0.15, TintColor = rgb(255, 235, 190) },
		Clouds = { Color = rgb(120, 100, 60), Cover = 0.4 },
		Sky = { MoonAngularSize = 0, CelestialBodiesShown = false, StarCount = 2500 },
	},
	RainbowMoon = {
		Lighting = { Brightness = 1.4, Ambient = rgb(110, 80, 120), OutdoorAmbient = rgb(130, 100, 150), ColorShift_Top = rgb(255, 170, 240) },
		Atmosphere = { Density = 0.3, Color = rgb(110, 70, 130), Decay = rgb(50, 30, 80), Haze = 1 },
		Grade = { Saturation = 0.35, TintColor = rgb(250, 230, 255) },
		Clouds = { Color = rgb(130, 90, 150), Cover = 0.35 },
		Sky = { MoonAngularSize = 0, CelestialBodiesShown = false, StarCount = 3000 },
	},
	MegaMoon = {
		Lighting = { Brightness = 1.6, Ambient = rgb(80, 95, 130), OutdoorAmbient = rgb(110, 125, 165), ColorShift_Top = rgb(200, 225, 255) },
		Atmosphere = { Density = 0.28, Color = rgb(80, 100, 150), Decay = rgb(30, 45, 90), Haze = 1 },
		Grade = { TintColor = rgb(225, 235, 255) },
		Clouds = { Color = rgb(100, 115, 160), Cover = 0.3 },
		Sky = { MoonAngularSize = 0, CelestialBodiesShown = false, StarCount = 3000 },
	},
}

local PROPS: { [string]: { string } } = {
	Lighting = { "Brightness", "Ambient", "OutdoorAmbient", "ColorShift_Top", "ExposureCompensation", "EnvironmentSpecularScale", "EnvironmentDiffuseScale" },
	Atmosphere = { "Density", "Offset", "Color", "Decay", "Haze", "Glare" },
	Grade = { "Saturation", "TintColor", "Brightness", "Contrast" },
	Clouds = { "Cover", "Density", "Color" },
	Bloom = { "Intensity", "Threshold", "Size" },
	SunRays = { "Intensity", "Spread" },
	Sky = { "MoonTextureId", "MoonAngularSize", "SunAngularSize", "StarCount", "CelestialBodiesShown", "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" },
}

local targets: { [string]: any } = {}
local baseline: { [string]: { [string]: any } } = {}
local currentPreset: Preset? = nil
-- The clear-day look of the zone the player is in (Config/SkyLooks). It replaces the
-- map's own values as the "normal" sky that every preset fades back to.
local currentLook: SkyLooks.Look = SkyLooks.forZone(nil)
local lookSky: { [string]: any } = SkyLooks.skyProps(currentLook, img)

local function find(group: string): Instance?
	if group == "Lighting" then
		return Lighting
	elseif group == "Atmosphere" then
		return Lighting:FindFirstChildOfClass("Atmosphere")
	elseif group == "Grade" then
		return Lighting:FindFirstChild("WorldGrade") or Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	elseif group == "Clouds" then
		return Workspace.Terrain:FindFirstChildOfClass("Clouds")
	elseif group == "Bloom" then
		return Lighting:FindFirstChildOfClass("BloomEffect")
	elseif group == "SunRays" then
		return Lighting:FindFirstChildOfClass("SunRaysEffect")
	end
	return Lighting:FindFirstChild("WorldSky") or Lighting:FindFirstChildOfClass("Sky")
end

-- Finds the sky objects and remembers the map's own values. Safe to call again: anything
-- the server hadn't built yet (it builds the sky while the client is starting) is picked
-- up the next time.
local function capture()
	for group, props in PROPS do
		local target = targets[group]
		if target and target.Parent then
			continue
		end
		local found = find(group) :: any
		if found and (found:IsA("ColorCorrectionEffect") == false or found.Name ~= "WeatherFlash") then
			targets[group] = found
			baseline[group] = {}
			for _, prop in props do
				baseline[group][prop] = found[prop]
			end
		end
	end
end

-- Writes the zone's look over the captured values (only for objects that exist).
local function overlayLook()
	for group, props in PROPS do
		local base = baseline[group]
		local look = if group == "Sky" then lookSky else (currentLook :: any)[group]
		if base and look then
			for _, prop in props do
				if look[prop] ~= nil then
					base[prop] = look[prop]
				end
			end
		end
	end
end

-- The value a sky property should have now (preset, else the zone's look / the map's own).
local function skyValue(group: string, prop: string): any
	local wanted = currentPreset and currentPreset[group]
	if wanted and wanted[prop] ~= nil then
		return wanted[prop]
	end
	return baseline[group] and baseline[group][prop]
end

-- Cartoon cloud meshes drifting over the map (built once the models load, see below).
local skyClouds: { MeshPart } = {}

-- Mesh clouds take the sky's cloud colour, lightened, since Roblox lighting shades them too.
local function tintSkyClouds(instant: boolean?)
	local wanted = skyValue("Clouds", "Color")
	local color = if typeof(wanted) == "Color3" then Color3.new(1, 1, 1):Lerp(wanted, 0.65) else Color3.new(1, 1, 1)
	for _, cloud in skyClouds do
		if instant then
			cloud.Color = color
		else
			TweenService:Create(cloud, SKY_TWEEN, { Color = color }):Play()
		end
	end
end

local function applySky(preset: Preset?)
	capture()
	overlayLook()
	currentPreset = preset
	for group, props in PROPS do
		local target = targets[group]
		if not target or not baseline[group] or not target.Parent then
			continue
		end
		if group == "Sky" then
			for _, prop in props do
				local value = skyValue(group, prop)
				if prop == "MoonTextureId" and preset and preset.Sky and preset.Sky.MoonTextureId then
					value = img(value)
				end
				-- Every Sky in Lighting, in case the place has its own besides WorldSky.
				for _, sky in Lighting:GetChildren() do
					if sky:IsA("Sky") then
						local anySky = sky :: any
						anySky[prop] = value
					end
				end
			end
			continue
		end
		local goal = {}
		for _, prop in props do
			goal[prop] = skyValue(group, prop)
		end
		TweenService:Create(target, SKY_TWEEN, goal):Play()
	end
	tintSkyClouds()
end

-- Drifting cartoon clouds -----------------------------------------------------------------
-- Cloud1..Cloud5 (art/blender/clouds.py). A wrapping field of clouds centred on the camera:
-- each cloud drifts with the wind, and fades by distance (solid nearby, gone by
-- CLOUD_FADE_TO), so clouds always slide in and out of view smoothly and only ever wrap
-- around while invisible. Positions come from a smoothed server clock, so everyone sees
-- the same clouds, moved every frame (smoother than tweens, which also step per frame).
-- Rain and storms (cloudStorm 0..1) roll in more, darker, lower clouds that rain, and
-- thunderstorm lightning comes out of the cloud above the strike.

local CLOUD_COUNT = 90
local CLOUD_CLEAR_COUNT = 55 -- clouds shown on a clear day; storms bring in the rest
local CLOUD_TILE = 1500 -- the field wraps every this many studs around the camera
local CLOUD_FADE_FROM, CLOUD_FADE_TO = 420, 680
local CLOUD_ALTITUDE = NumberRange.new(150, 270)
local CLOUD_STORM_DROP = 45 -- storm clouds hang this much lower
type SkyCloud = {
	part: MeshPart,
	rainEmitter: ParticleEmitter,
	start: Vector2,
	speed: number,
	y: number,
	yaw: number,
	index: number,
	pos: Vector3, -- where it is now (world)
	flash: number,
}
local cloudList: { SkyCloud } = {}
local cloudStorm, cloudStormTarget = 0, 0
local clockOffset: number? = nil

-- Server time without the small jumps GetServerTimeNow makes when it re-syncs.
local function smoothServerTime(dt: number): number
	local server = Workspace:GetServerTimeNow()
	local offset = server - os.clock()
	if not clockOffset or math.abs(offset - clockOffset) > 2 then
		clockOffset = offset
	else
		clockOffset += (offset - clockOffset) * math.min(1, dt * 0.2)
	end
	return os.clock() + (clockOffset :: number)
end

local function buildSkyClouds(): boolean
	for i = 1, 5 do
		if not AssetLibrary.has("Cloud" .. i) then
			return false
		end
	end
	local terrainClouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
	if terrainClouds then
		terrainClouds.Enabled = false -- Roblox's own clouds never show (Dev, 2026-10-31)
	end
	local cloudFolder = Instance.new("Folder")
	cloudFolder.Name = "SkyClouds"
	cloudFolder.Parent = Workspace
	local seeded = Random.new(20261031)
	for i = 1, CLOUD_COUNT do
		local model = AssetLibrary.get("Cloud" .. seeded:NextInteger(1, 5))
		local part = model and model:FindFirstChildWhichIsA("MeshPart")
		if not (model and part) then
			continue
		end
		part.Parent = nil
		model:Destroy()
		part.Size *= seeded:NextNumber(6, 15)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.TextureID = ""
		part.Transparency = 1
		part.Name = "SkyCloud" .. i
		-- Rain falling out of the cloud's underside (only while it rains).
		local rainEmitter = Instance.new("ParticleEmitter")
		rainEmitter.Texture = img("Vfx_Rain")
		rainEmitter.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
		rainEmitter.EmissionDirection = Enum.NormalId.Bottom
		rainEmitter.Shape = Enum.ParticleEmitterShape.Box
		rainEmitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		rainEmitter.SpreadAngle = Vector2.zero
		rainEmitter.Speed = NumberRange.new(150, 170)
		rainEmitter.Lifetime = NumberRange.new(1.4, 1.8)
		rainEmitter.Size = NumberSequence.new(7)
		rainEmitter.Acceleration = WIND * 10
		rainEmitter.Color = ColorSequence.new(rgb(190, 200, 225))
		rainEmitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, 0.55),
			NumberSequenceKeypoint.new(0.85, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		rainEmitter.LightEmission = 0.2
		rainEmitter.LightInfluence = 0.5
		rainEmitter.Rate = 0
		rainEmitter.Parent = part
		part.Parent = cloudFolder
		table.insert(skyClouds, part)
		table.insert(cloudList, {
			part = part,
			rainEmitter = rainEmitter,
			start = Vector2.new(seeded:NextNumber(0, CLOUD_TILE), seeded:NextNumber(0, CLOUD_TILE)),
			speed = seeded:NextNumber(4.5, 7.5),
			y = seeded:NextNumber(CLOUD_ALTITUDE.Min, CLOUD_ALTITUDE.Max),
			yaw = seeded:NextNumber(-0.5, 0.5),
			index = i,
			pos = Vector3.zero,
			flash = 0,
		})
	end
	tintSkyClouds(true)
	return true
end

local function smoothstep(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local cloudParts: { BasePart } = {}
local cloudFrames: { CFrame } = {}
local function updateSkyClouds(dt: number)
	if #cloudList == 0 then
		return
	end
	cloudStorm += (cloudStormTarget - cloudStorm) * math.min(1, dt / 4)
	local now = smoothServerTime(dt)
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local eye = cam.CFrame.Position
	local half = CLOUD_TILE / 2
	table.clear(cloudParts)
	table.clear(cloudFrames)
	for _, c in cloudList do
		-- Clouds past the clear-day count fade in as a storm rolls in.
		local extra = if c.index > CLOUD_CLEAR_COUNT
			then smoothstep(0, 1, cloudStorm * 1.6 - (c.index - CLOUD_CLEAR_COUNT) / (CLOUD_COUNT - CLOUD_CLEAR_COUNT) * 0.6)
			else 1
		local travel = c.start.X + WIND.X * c.speed * now
		local side = c.start.Y + WIND.Z * c.speed * now
		local x = (travel - eye.X + half) % CLOUD_TILE - half + eye.X
		local z = (side - eye.Z + half) % CLOUD_TILE - half + eye.Z
		local y = c.y - CLOUD_STORM_DROP * cloudStorm
		c.pos = Vector3.new(x, y, z)
		local dist = Vector2.new(x - eye.X, z - eye.Z).Magnitude
		local seen = (1 - smoothstep(CLOUD_FADE_FROM, CLOUD_FADE_TO, dist)) * extra
		local transparency = 1 - seen
		if math.abs(c.part.Transparency - transparency) > 0.004 then
			c.part.Transparency = transparency
		end
		local rate = if seen > 0.3 then math.floor(cloudStorm * 30 * seen) else 0
		if c.rainEmitter.Rate ~= rate then
			c.rainEmitter.Rate = rate
		end
		table.insert(cloudParts, c.part)
		table.insert(cloudFrames, CFrame.new(x, y, z) * CFrame.Angles(0, c.yaw, 0))
	end
	Workspace:BulkMoveTo(cloudParts, cloudFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- The visible cloud closest (sideways) to a point, for lightning to come out of.
local function cloudAbove(position: Vector3): SkyCloud?
	local best, bestDist = nil, math.huge
	for _, c in cloudList do
		if c.part.Transparency < 0.5 then
			local d = Vector2.new(c.pos.X - position.X, c.pos.Z - position.Z).Magnitude
			if d < bestDist then
				best, bestDist = c, d
			end
		end
	end
	return best
end

-- Lights a cloud up from inside for a lightning strike.
local function flashCloud(c: SkyCloud)
	local light = Instance.new("PointLight")
	light.Color = rgb(190, 215, 255)
	light.Range = 60
	light.Brightness = 10
	light.Parent = c.part
	local base = c.part.Color
	c.part.Color = rgb(235, 242, 255)
	c.part.Material = Enum.Material.Neon
	task.delay(0.08, function()
		c.part.Material = Enum.Material.SmoothPlastic
		task.wait(0.06)
		c.part.Material = Enum.Material.Neon
		task.wait(0.1)
		c.part.Material = Enum.Material.SmoothPlastic
		TweenService:Create(c.part, TweenInfo.new(0.5), { Color = base }):Play()
		TweenService:Create(light, TweenInfo.new(0.5), { Brightness = 0 }):Play()
		task.wait(0.6)
		light:Destroy()
	end)
end

-- Helpers ------------------------------------------------------------------------------------

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
	local anyE = e :: any
	for key, value in props do
		anyE[key] = value
	end
	e.Parent = parent
	return e
end

local function seq(a: number, b: number?): NumberSequence
	return if b then NumberSequence.new(a, b) else NumberSequence.new(a)
end

-- Fades in and out so particles never pop.
local function fadeSeq(peak: number): NumberSequence
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
local BANDS = { rgb(255, 70, 70), rgb(255, 150, 50), rgb(255, 225, 60), rgb(80, 215, 90), rgb(60, 165, 255), rgb(100, 90, 255), rgb(185, 90, 255) }

local function camera(): Camera?
	return Workspace.CurrentCamera
end

local function focus(): Vector3
	local cam = camera()
	return if cam then cam.Focus.Position else Vector3.zero
end

local function cameraPosition(): Vector3
	local cam = camera()
	return if cam then cam.CFrame.Position else Vector3.zero
end

-- Ground height under a point (or the point itself when nothing is below).
local function groundAt(position: Vector3): Vector3
	local character = player.Character
	rayParams.FilterDescendantsInstances = if character then { folder, character } else { folder }
	local hit = Workspace:Raycast(position + Vector3.new(0, 80, 0), Vector3.new(0, -300, 0), rayParams)
	return if hit then hit.Position else position
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

-- A one-shot 3D sound at a spot.
local function soundAt(name: string, position: Vector3, volumeMult: number?, speed: number?, delay: number?)
	local def = Sounds.Sfx[name]
	if not def or def.Id == "" then
		return
	end
	task.delay(delay or 0, function()
		local holder = Instance.new("Attachment")
		holder.WorldPosition = position
		holder.Parent = Workspace.Terrain
		local sound = Instance.new("Sound")
		sound.SoundId = def.Id
		sound.Volume = def.Volume * (volumeMult or 1)
		sound.PlaybackSpeed = speed or 1
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = 40
		sound.RollOffMaxDistance = 900
		sound.SoundGroup = Ui.soundGroup("SFX")
		sound.Parent = holder
		sound:Play()
		task.delay(10, function()
			holder:Destroy()
		end)
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

-- Lightning flash: its own colour grade (never fights the sky tween) plus the clouds
-- lighting up from inside.
local flashGrade: ColorCorrectionEffect
local function flash(strength: number)
	flashGrade.Brightness = 0.5 * strength
	flashGrade.Contrast = 0.25 * strength
	flashGrade.TintColor = rgb(225, 235, 255)
	TweenService:Create(flashGrade, TweenInfo.new(0.07), { Brightness = 0.08 * strength }):Play()
	local clouds = targets.Clouds
	if clouds and clouds.Parent then
		clouds.Color = rgb(235, 240, 255)
	end
	task.delay(0.11, function()
		flashGrade.Brightness = 0.38 * strength
		TweenService:Create(flashGrade, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Brightness = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) }):Play()
		if clouds and clouds.Parent then
			TweenService:Create(clouds, TweenInfo.new(0.6), { Color = skyValue("Clouds", "Color") }):Play()
		end
	end)
end

local function decalOnGround(texture: string, position: Vector3, size: number, color: Color3, transparency: number, life: number)
	local holder = part("GroundMark", Vector3.new(size, 0.05, size))
	holder.Position = position + Vector3.new(0, 0.08, 0)
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Top
	decal.Texture = img(texture)
	decal.Color3 = color
	decal.Transparency = transparency
	decal.Parent = holder
	TweenService:Create(decal, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	task.delay(life + 0.1, function()
		holder:Destroy()
	end)
end

local function sparkBurst(position: Vector3, color: Color3, count: number, texture: string?, speed: number?)
	local holder = part("Burst", Vector3.new(1, 1, 1))
	holder.Position = position
	local e = emitter(holder, {
		Texture = img(texture or "Vfx_Star"),
		Size = seq(1.4, 0),
		Speed = NumberRange.new((speed or 1) * 18, (speed or 1) * 40),
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
		Lifetime = NumberRange.new(0.6, 1.2),
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

-- Crackling sparks on a spot for a while (a struck egg).
local function crackle(position: Vector3, color: Color3, seconds: number)
	local holder = part("Crackle", Vector3.new(3, 3, 3))
	holder.Position = position + Vector3.new(0, 1.8, 0)
	local e = emitter(holder, {
		Texture = img("Vfx_Star"),
		Size = seq(0.8, 0),
		Speed = NumberRange.new(4, 10),
		Lifetime = NumberRange.new(0.15, 0.35),
		SpreadAngle = Vector2.new(180, 180),
		Color = ColorSequence.new(color),
		LightEmission = 1,
		Rate = 40,
	})
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 4
	light.Parent = holder
	task.delay(seconds, function()
		e.Enabled = false
		TweenService:Create(light, TweenInfo.new(0.5), { Brightness = 0 }):Play()
		task.wait(0.6)
		holder:Destroy()
	end)
end

-- Lightning ------------------------------------------------------------------------------------

local BOLT_CORE = rgb(255, 255, 250)
local BOLT_GLOW = rgb(150, 190, 255)

-- A jagged bolt: a thin white core inside a wide blue glow, with forks. Flickers, then fades.
local function lightningBolt(top: Vector3, bottom: Vector3)
	local bolt = Instance.new("Model")
	bolt.Name = "Bolt"
	local function segment(a: Vector3, b: Vector3, width: number)
		local len = (b - a).Magnitude
		local core = part("Core", Vector3.new(width, width, len + width))
		core.CFrame = CFrame.lookAt((a + b) / 2, b)
		core.Material = Enum.Material.Neon
		core.Color = BOLT_CORE
		core.Transparency = 0
		core.Parent = bolt
		local glow = part("Glow", Vector3.new(width * 4, width * 4, len + width * 2))
		glow.CFrame = core.CFrame
		glow.Material = Enum.Material.Neon
		glow.Color = BOLT_GLOW
		glow.Transparency = 0.75
		glow.Parent = bolt
	end
	local function zigzag(a: Vector3, b: Vector3, steps: number, jitter: number, width: number, depth: number)
		local last = a
		for i = 1, steps do
			local point = a:Lerp(b, i / steps)
			if i < steps then
				point += Vector3.new(rng:NextNumber(-jitter, jitter), rng:NextNumber(-jitter, jitter) * 0.3, rng:NextNumber(-jitter, jitter))
			end
			segment(last, point, width)
			if depth > 0 and i > 1 and i < steps - 1 and rng:NextNumber() < 0.4 then
				local away = Vector3.new(rng:NextNumber(-1, 1), -rng:NextNumber(0.5, 1.2), rng:NextNumber(-1, 1)) * rng:NextNumber(20, 55)
				zigzag(point, point + away, 5, jitter * 0.5, width * 0.55, depth - 1)
			end
			last = point
		end
	end
	zigzag(top, bottom, 14, 10, 0.7, 2)
	local glow = part("Light", Vector3.new(1, 1, 1))
	glow.Position = bottom + Vector3.new(0, 4, 0)
	glow.Parent = bolt
	local light = Instance.new("PointLight")
	light.Color = BOLT_GLOW
	light.Range = 60
	light.Brightness = 12
	light.Parent = glow
	bolt.Parent = folder
	task.spawn(function()
		for _, t in { 0.05, 0.04, 0.06, 0.05 } do
			task.wait(t)
			for _, p in bolt:GetChildren() do
				if p:IsA("BasePart") and p.Name == "Core" then
					p.Transparency = if p.Transparency == 0 then 0.7 else 0
				end
			end
		end
		for _, p in bolt:GetChildren() do
			if p:IsA("BasePart") and p.Name ~= "Light" then
				TweenService:Create(p, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			end
		end
		TweenService:Create(light, TweenInfo.new(0.6), { Brightness = 0 }):Play()
		task.wait(0.7)
		bolt:Destroy()
	end)
end

local function lightningAt(position: Vector3, hitEgg: boolean, near: boolean)
	local floor = if hitEgg then position else groundAt(position)
	-- Out of the cloud above the strike (its underside), else from high up.
	local top = floor + Vector3.new(rng:NextNumber(-40, 40), 300, rng:NextNumber(-40, 40))
	local cloud = cloudAbove(floor)
	if cloud and Vector2.new(cloud.pos.X - floor.X, cloud.pos.Z - floor.Z).Magnitude < 260 then
		local size = cloud.part.Size
		top = cloud.pos + Vector3.new(rng:NextNumber(-0.25, 0.25) * size.X, -size.Y * 0.25, rng:NextNumber(-0.25, 0.25) * size.Z)
		flashCloud(cloud)
	end
	lightningBolt(top, floor)
	local dist = (floor - cameraPosition()).Magnitude
	flash(if near then math.clamp(1.2 - dist / 600, 0.35, 1) else 0.3)
	if near then
		sparkBurst(floor + Vector3.new(0, 1, 0), rgb(200, 225, 255), 45, nil, 1.2)
		smokePuff(floor, rgb(80, 80, 90), 14, 5)
		shockRing(floor, rgb(170, 210, 255), 4, 32, 0.6)
		decalOnGround("Vfx_Scorch", floor, 14, Color3.new(1, 1, 1), 0.1, 7)
		decalOnGround("Vfx_Spot", floor, 26, rgb(170, 210, 255), 0.3, 1.2)
		if hitEgg then
			crackle(floor, rgb(255, 235, 110), 2.5)
		end
		if dist < 140 then
			shake(0.7 * (1 - dist / 140), 0.4)
		end
	end
	-- Thunder arrives a moment later the further away it is.
	soundAt("Thunder" .. rng:NextInteger(1, 3), floor, if near then 1 else 0.55, rng:NextNumber(0.8, 1.05), math.min(1.8, dist / 500))
end

-- Falling star (Starfall): a bright star with a long trail that lands at a spot.
local STAR = rgb(255, 230, 140)
local function fallingStar(target: Vector3, seconds: number, onLand: (() -> ())?)
	-- Always comes in at a slant (about 45 degrees), never straight down (Dev).
	local heading = rng:NextNumber(0, math.pi * 2)
	local across = rng:NextNumber(190, 260)
	local from = target + Vector3.new(math.cos(heading) * across, rng:NextNumber(200, 240), math.sin(heading) * across)
	local star = part("Star", Vector3.new(3, 3, 3))
	star.Shape = Enum.PartType.Ball
	star.Material = Enum.Material.Neon
	star.Color = STAR
	star.Transparency = 0
	star.Position = from
	local t0 = attachment(star, Vector3.new(0, 1.1, 0))
	local t1 = attachment(star, Vector3.new(0, -1.1, 0))
	local trail = Instance.new("Trail")
	trail.Attachment0 = t0
	trail.Attachment1 = t1
	trail.Lifetime = 0.5
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.WidthScale = NumberSequence.new(1.6, 0)
	trail.Transparency = NumberSequence.new(0, 1)
	trail.Color = ColorSequence.new(rgb(255, 255, 230), rgb(255, 170, 80))
	trail.Parent = star
	emitter(star, {
		Texture = img("Vfx_Star"),
		Size = seq(1.6, 0),
		Speed = NumberRange.new(1, 4),
		Lifetime = NumberRange.new(0.3, 0.6),
		SpreadAngle = Vector2.new(180, 180),
		Color = ColorSequence.new(STAR),
		LightEmission = 1,
		Rate = 50,
		Shape = Enum.ParticleEmitterShape.Sphere,
	})
	local light = Instance.new("PointLight")
	light.Color = STAR
	light.Range = 24
	light.Brightness = 4
	light.Parent = star
	local tween = TweenService:Create(star, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = target + Vector3.new(0, 1, 0) })
	tween:Play()
	tween.Completed:Once(function()
		star:Destroy()
		if onLand then
			onLand()
		end
	end)
end

-- Star impact: a white-gold flash and a column of light, two shockwaves and a glowing
-- crater mark on the ground, sparks and embers, a dust ring, leaf bits thrown out, and the
-- real leaves around it blown outward (LeafController:Blast). Close by, a small shake.
local function starImpact(floor: Vector3, hitEgg: boolean)
	local up = Vector3.new(0, 1, 0)
	-- Flash: a neon ball that swells and fades, with a burst of light.
	local orb = part("StarFlash", Vector3.new(3, 3, 3))
	orb.Shape = Enum.PartType.Ball
	orb.Material = Enum.Material.Neon
	orb.Color = rgb(255, 250, 225)
	orb.Transparency = 0
	orb.Position = floor + up * 1.2
	TweenService:Create(orb, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(15, 15, 15), Transparency = 1 }):Play()
	local light = Instance.new("PointLight")
	light.Color = STAR
	light.Range = 45
	light.Brightness = 9
	light.Parent = orb
	TweenService:Create(light, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { Brightness = 0, Range = 20 }):Play()
	-- A column of light that shoots up and thins out.
	local pillar = part("StarPillar", Vector3.new(10, 2.6, 2.6)) -- a cylinder runs along X
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Material = Enum.Material.Neon
	pillar.Color = STAR
	pillar.Transparency = 0.15
	pillar.CFrame = CFrame.new(floor + up * 5) * CFrame.Angles(0, 0, math.pi / 2)
	TweenService:Create(pillar, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(70, 0.4, 0.4),
		CFrame = CFrame.new(floor + up * 35) * CFrame.Angles(0, 0, math.pi / 2),
		Transparency = 1,
	}):Play()
	task.delay(1, function()
		orb:Destroy()
		pillar:Destroy()
	end)
	-- Ground: a fast thin wave, a slower wide one, a glowing crater that fades.
	shockRing(floor, rgb(255, 245, 200), 4, 48, 0.5)
	task.delay(0.08, function()
		shockRing(floor, STAR, 3, 30, 0.9)
	end)
	decalOnGround("Vfx_Spot", floor, 22, STAR, 0.05, 2.5)
	decalOnGround("Vfx_Scorch", floor, 9, rgb(255, 200, 90), 0.3, 4)
	-- Sparks out in every direction, then embers drifting up for a moment.
	sparkBurst(floor + up * 1.5, STAR, 45, nil, 1.2)
	sparkBurst(floor + up * 1, rgb(255, 255, 240), 20, "Vfx_Sparkle", 0.7)
	local embers = part("StarEmbers", Vector3.new(6, 1, 6))
	embers.Position = floor + up
	local ember = emitter(embers, {
		Texture = img("Vfx_Sparkle"),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.9), NumberSequenceKeypoint.new(1, 0) }),
		Speed = NumberRange.new(3, 8),
		Lifetime = NumberRange.new(0.8, 1.6),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(30, 30),
		Color = ColorSequence.new(rgb(255, 245, 190), rgb(255, 170, 70)),
		LightEmission = 1,
		LightInfluence = 0,
		Rate = 45,
	})
	task.delay(0.8, function()
		ember.Enabled = false
	end)
	task.delay(2.6, function()
		embers:Destroy()
	end)
	-- Dust kicked up in a ring, and bits of leaf thrown out.
	smokePuff(floor, rgb(205, 180, 140), 14, 5)
	local debris = part("StarDebris", Vector3.new(4, 0.5, 4))
	debris.Position = floor + up * 0.5
	local bits = emitter(debris, {
		Texture = img("Vfx_LeafMaple"),
		Size = seq(1.1, 0.8),
		Speed = NumberRange.new(22, 42),
		Lifetime = NumberRange.new(0.9, 1.5),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(65, 65),
		Acceleration = Vector3.new(0, -45, 0),
		Drag = 1.6,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-500, 500),
		Color = ColorSequence.new(rgb(255, 160, 60), rgb(220, 70, 40)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0), NumberSequenceKeypoint.new(1, 1) }),
		LightInfluence = 0.8,
		Rate = 0,
	})
	bits:Emit(36)
	task.delay(2, function()
		debris:Destroy()
	end)
	if C and C.LeafController and C.LeafController.Blast then
		C.LeafController:Blast(floor, 13)
	end
	soundAt("EggLand", floor, 1.4, 0.7)
	soundAt("Sparkle", floor, 1.2)
	if hitEgg then
		crackle(floor, STAR, 2)
	end
	-- Only a small shake, and only when it lands close to you.
	local dist = (floor - focus()).Magnitude
	if dist < 45 then
		shake(0.12 + 0.3 * (1 - dist / 45), 0.3)
	end
end

local function starAt(position: Vector3, hitEgg: boolean)
	local floor = if hitEgg then position else groundAt(position)
	if (floor - focus()).Magnitude > 900 then
		return
	end
	soundAt("EggFall", floor, 0.7, 1.2)
	-- Where it will land glows brighter as it falls.
	local mark = part("StarMark", Vector3.new(4, 0.05, 4))
	mark.Position = floor + Vector3.new(0, 0.1, 0)
	local markDecal = Instance.new("Decal")
	markDecal.Face = Enum.NormalId.Top
	markDecal.Texture = img("Vfx_Ring")
	markDecal.Color3 = STAR
	markDecal.Transparency = 0.9
	markDecal.Parent = mark
	TweenService:Create(mark, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(12, 0.05, 12) }):Play()
	TweenService:Create(markDecal, TweenInfo.new(1.1), { Transparency = 0.25 }):Play()
	fallingStar(floor, 1.1, function()
		mark:Destroy()
		starImpact(floor, hitEgg)
	end)
end

-- Scenes ----------------------------------------------------------------------------------------
-- A scene builds its effects and gets update(dt, focus, ground) every frame, plus cleanups.

type Scene = { update: ((number, Vector3, Vector3) -> ())?, parts: { Instance }, cleanup: { () -> () } }

local function newScene(): Scene
	return { parts = {}, cleanup = {} }
end

local function keep(scene: Scene, inst: Instance): any
	table.insert(scene.parts, inst)
	return inst
end

local function addUpdate(scene: Scene, fn: (number, Vector3, Vector3) -> ())
	local before = scene.update
	scene.update = function(dt, at, floor)
		if before then
			before(dt, at, floor)
		end
		fn(dt, at, floor)
	end
end

-- An invisible box that follows the camera; emitters in it fill the air around the player.
local function follower(scene: Scene, name: string, size: Vector3): Part
	return keep(scene, part(name, size))
end

local function motes(scene: Scene, texture: string, color: ColorSequence, rate: number, size: number, rise: number, boxSize: Vector3?): Part
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
	addUpdate(scene, function(_, _, floor)
		box.CFrame = CFrame.new(floor + Vector3.new(0, 8, 0))
	end)
	return box
end

-- Mesh splashes: real 3D water crowns and ripples (art/blender/vfx_meshes.py) popping up
-- where raindrops hit whatever is under them (ground, roofs, paths), pooled.
local function meshSplashes(scene: Scene, perSecond: number)
	-- The meshes load with the other models; until they're in, only particles splash.
	local function meshOf(name: string): MeshPart?
		local model = AssetLibrary.get(name)
		return if model then model:FindFirstChildWhichIsA("MeshPart") else nil
	end
	local sources: { [string]: MeshPart? } = {}
	local nextLook = 0
	local function ready(): boolean
		if sources.crown and sources.ripple then
			return true
		end
		if os.clock() < nextLook then
			return false
		end
		nextLook = os.clock() + 2
		sources.crown = sources.crown or meshOf("VfxSplashCrown")
		sources.ripple = sources.ripple or meshOf("VfxRipple")
		sources.sheet = sources.sheet or meshOf("VfxSplashSheet")
		return sources.crown ~= nil and sources.ripple ~= nil
	end
	local pools: { [string]: { MeshPart } } = { crown = {}, ripple = {}, sheet = {} }
	local function take(kind: string): MeshPart?
		local pool = pools[kind]
		local mesh = table.remove(pool)
		if mesh then
			return mesh
		end
		local src = sources[kind]
		if not src then
			return nil
		end
		local m = src:Clone()
		m.Anchored = true
		m.CanCollide = false
		m.CanQuery = false
		m.CanTouch = false
		m.CastShadow = false
		m.TextureID = ""
		m.Material = Enum.Material.SmoothPlastic
		m.Reflectance = 0.25
		m.Color = rgb(215, 232, 255)
		m.Parent = folder
		keep(scene, m)
		return m
	end
	local function give(kind: string, mesh: MeshPart)
		mesh.Transparency = 1
		table.insert(pools[kind], mesh)
	end
	local function pop(kind: string, at: CFrame, from: Vector3, to: Vector3, life: number, alpha: number)
		local mesh = take(kind)
		if not mesh then
			return
		end
		mesh.Size = from
		mesh.CFrame = at * CFrame.new(0, from.Y / 2, 0)
		mesh.Transparency = alpha
		local info = TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(mesh, info, { Size = to, Transparency = 1, CFrame = at * CFrame.new(0, to.Y / 2, 0) })
		tween:Play()
		tween.Completed:Once(function()
			give(kind, mesh)
		end)
	end
	local carry = 0
	addUpdate(scene, function(dt)
		if not ready() then
			return
		end
		carry += perSecond * dt
		local eye = cameraPosition()
		while carry >= 1 do
			carry -= 1
			local r = math.sqrt(rng:NextNumber()) * 55
			local a = rng:NextNumber() * math.pi * 2
			local top = Vector3.new(eye.X + math.cos(a) * r, eye.Y + 60, eye.Z + math.sin(a) * r)
			local character = player.Character
			rayParams.FilterDescendantsInstances = if character then { folder, character } else { folder }
			local hit = Workspace:Raycast(top, Vector3.new(0, -200, 0), rayParams)
			if not hit or hit.Normal.Y < 0.6 then
				continue
			end
			local k = rng:NextNumber(0.7, 1.3)
			local spin = CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
			local at = CFrame.new(hit.Position + Vector3.new(0, 0.02, 0)) * spin
			pop("ripple", at, Vector3.new(0.3, 0.02, 0.3) * k, Vector3.new(2.6, 0.02, 2.6) * k, 0.7, 0.45)
			if rng:NextNumber() < 0.75 then
				pop("crown", at, Vector3.new(0.25, 0.15, 0.25) * k, Vector3.new(0.9, 0.65, 0.9) * k, 0.28, 0.25)
			elseif sources.sheet then
				pop("sheet", at, Vector3.new(0.3, 0.1, 0.3) * k, Vector3.new(1.4, 0.35, 1.4) * k, 0.3, 0.3)
			end
		end
	end)
end

-- Rain: thin streaks that always stand upright on screen (FacingCameraWorldUp), a wide
-- layer around the camera plus a close layer that rushes past, splash crowns and ripples
-- where drops land (meshes + a flipbook splash), and rain sheets in the distance all around
-- so it rains over the whole map.
local MIST = "rbxasset://textures/particles/smoke_main.dds"

local function rain(scene: Scene, storm: boolean)
	local slant = WIND * (if storm then 14 else 5)
	-- More, darker, lower clouds roll in and rain falls out of them.
	cloudStormTarget = if storm then 1 else 0.7
	table.insert(scene.cleanup, function()
		cloudStormTarget = 0
	end)
	-- Mist: a grey layer drifting at cloud height, and low fog over the ground.
	local high = follower(scene, "CloudMist", Vector3.new(700, 60, 700))
	emitter(high, {
		Texture = MIST,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 60), NumberSequenceKeypoint.new(1, 95) }),
		Speed = NumberRange.new(1, 3),
		Lifetime = NumberRange.new(9, 13),
		Rate = if storm then 26 else 18,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-4, 4),
		Acceleration = WIND * 3,
		Color = ColorSequence.new(if storm then rgb(120, 126, 140) else rgb(170, 176, 190)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, if storm then 0.55 else 0.65),
			NumberSequenceKeypoint.new(0.7, if storm then 0.55 else 0.65),
			NumberSequenceKeypoint.new(1, 1),
		}),
		LightEmission = 0,
		LightInfluence = 1,
	})
	local low = follower(scene, "GroundMist", Vector3.new(320, 8, 320))
	emitter(low, {
		Texture = MIST,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 26), NumberSequenceKeypoint.new(1, 40) }),
		Speed = NumberRange.new(0.5, 2),
		Lifetime = NumberRange.new(6, 9),
		Rate = if storm then 30 else 22,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-6, 6),
		Acceleration = WIND * 2,
		Color = ColorSequence.new(if storm then rgb(150, 156, 170) else rgb(195, 202, 214)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.8),
			NumberSequenceKeypoint.new(0.7, 0.8),
			NumberSequenceKeypoint.new(1, 1),
		}),
		LightEmission = 0,
		LightInfluence = 1,
	})
	local streak = {
		Texture = img("Vfx_Rain"),
		Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
		EmissionDirection = Enum.NormalId.Bottom,
		SpreadAngle = Vector2.new(0, 0),
		Acceleration = slant,
		LightEmission = 0.4,
		LightInfluence = 0.3,
	}
	local sky = follower(scene, "RainSky", Vector3.new(200, 1, 200))
	local far = table.clone(streak)
	far.Size = seq(if storm then 4.6 else 4)
	far.Speed = NumberRange.new(if storm then 120 else 100, if storm then 135 else 112)
	far.Lifetime = NumberRange.new(0.85, 0.95)
	far.Rate = if storm then 2200 else 1500
	far.Color = ColorSequence.new(rgb(200, 215, 240))
	far.Transparency = seq(0.35)
	emitter(sky, far)
	local near = follower(scene, "RainNear", Vector3.new(40, 1, 40))
	local close = table.clone(streak)
	close.Size = seq(2.6)
	close.Speed = NumberRange.new(130, 145)
	close.Lifetime = NumberRange.new(0.38, 0.42)
	close.Rate = if storm then 500 else 320
	close.Color = ColorSequence.new(rgb(230, 238, 255))
	close.Transparency = seq(0.45)
	emitter(near, close)
	local ground = follower(scene, "RainGround", Vector3.new(80, 0.2, 80))
	emitter(ground, {
		Texture = img("Vfx_Splash"),
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2, 0.3), NumberSequenceKeypoint.new(1, 1.2, 0.3) }),
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.35, 0.45),
		Rate = if storm then 380 else 260,
		Color = ColorSequence.new(rgb(225, 238, 255)),
		Transparency = seq(0.15),
		LightEmission = 0.3,
		LightInfluence = 0.4,
	})
	meshSplashes(scene, if storm then 45 else 30)
	-- Distant rain curtains: tall scrolling sheets in a ring around the camera.
	local ring = keep(scene, part("RainCurtains", Vector3.new(1, 1, 1)))
	for i = 1, 8 do
		local angle = i / 8 * math.pi * 2
		local radius = 150 + (i % 2) * 70
		local center = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local low = attachment(ring, center + Vector3.new(0, -10, 0))
		local high = attachment(ring, center + Vector3.new(0, 220, 0))
		local beam = Instance.new("Beam")
		beam.Attachment0 = high
		beam.Attachment1 = low
		beam.Width0 = 240
		beam.Width1 = 240
		beam.FaceCamera = true
		beam.Texture = img("Vfx_RainSheet")
		beam.TextureMode = Enum.TextureMode.Static
		beam.TextureLength = 60
		beam.TextureSpeed = if storm then 2.2 else 1.6
		beam.LightEmission = 0.1
		beam.LightInfluence = 0.6
		beam.Color = ColorSequence.new(if storm then rgb(170, 180, 205) else rgb(205, 215, 235))
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, if storm then 0.55 else 0.65),
			NumberSequenceKeypoint.new(1, if storm then 0.5 else 0.6),
		})
		beam.Parent = ring
	end
	addUpdate(scene, function(_, at, floor)
		local eye = cameraPosition()
		sky.CFrame = CFrame.new(Vector3.new(eye.X, floor.Y + 80, eye.Z) - slant * 0.4)
		near.CFrame = CFrame.new(Vector3.new(eye.X, floor.Y + 55, eye.Z) - slant * 0.2)
		ground.CFrame = CFrame.new(floor + Vector3.new(0, 0.15, 0))
		ring.CFrame = CFrame.new(Vector3.new(at.X, floor.Y, at.Z))
		high.CFrame = CFrame.new(Vector3.new(eye.X, floor.Y + CLOUD_ALTITUDE.Min - CLOUD_STORM_DROP + 10, eye.Z))
		low.CFrame = CFrame.new(Vector3.new(eye.X, floor.Y + 7, eye.Z))
	end)
end

local function snow(scene: Scene)
	local sky = follower(scene, "SnowSky", Vector3.new(170, 1, 170))
	emitter(sky, {
		Texture = img("Vfx_Snow"),
		EmissionDirection = Enum.NormalId.Bottom,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35, 0.15), NumberSequenceKeypoint.new(1, 0.35, 0.15) }),
		Speed = NumberRange.new(5, 8),
		Lifetime = NumberRange.new(8, 10),
		Rate = 320,
		SpreadAngle = Vector2.new(25, 25),
		Acceleration = WIND * 1.5,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
		Color = ColorSequence.new(rgb(255, 255, 255)),
		Transparency = fadeSeq(0.1),
		LightEmission = 0.35,
		LightInfluence = 0.2,
	})
	emitter(sky, {
		Texture = img("Vfx_Snow"),
		EmissionDirection = Enum.NormalId.Bottom,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8, 0.25), NumberSequenceKeypoint.new(1, 0.8, 0.25) }),
		Speed = NumberRange.new(4, 6),
		Lifetime = NumberRange.new(9, 11),
		Rate = 60,
		SpreadAngle = Vector2.new(30, 30),
		Acceleration = WIND * 2,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-40, 40),
		Color = ColorSequence.new(rgb(255, 255, 255)),
		Transparency = fadeSeq(0.05),
		LightEmission = 0.4,
	})
	-- A few big soft flakes right in front of the camera, out of focus.
	local close = follower(scene, "SnowClose", Vector3.new(30, 1, 30))
	emitter(close, {
		Texture = img("Vfx_Bokeh"),
		EmissionDirection = Enum.NormalId.Bottom,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9, 0.4), NumberSequenceKeypoint.new(1, 0.9, 0.4) }),
		Speed = NumberRange.new(3, 5),
		Lifetime = NumberRange.new(4, 6),
		Rate = 22,
		SpreadAngle = Vector2.new(30, 30),
		Acceleration = WIND * 2,
		Color = ColorSequence.new(rgb(255, 255, 255)),
		Transparency = fadeSeq(0.35),
		LightEmission = 0.5,
		LightInfluence = 0.2,
	})
	addUpdate(scene, function(_, at)
		sky.CFrame = CFrame.new(at + Vector3.new(0, 45, 0))
		local eye = cameraPosition()
		close.CFrame = CFrame.new(eye + Vector3.new(0, 12, 0))
	end)
end

local function windy(scene: Scene)
	-- Leaves blow across from upwind; the box faces the wind (its Right is the wind).
	local box = follower(scene, "WindLeaves", Vector3.new(40, 30, 170))
	local low = follower(scene, "WindSkitter", Vector3.new(40, 2, 120))
	local look = CFrame.lookAt(Vector3.zero, Vector3.new(WIND.Z, 0, -WIND.X)) -- RightVector = WIND
	for _, texture in { "Vfx_LeafMaple", "Vfx_LeafOval", "Vfx_LeafGreen" } do
		emitter(box, {
			Texture = img(texture),
			EmissionDirection = Enum.NormalId.Right,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2, 0.4), NumberSequenceKeypoint.new(1, 1.2, 0.4) }),
			Speed = NumberRange.new(35, 55),
			Lifetime = NumberRange.new(4, 5),
			Rate = 34,
			SpreadAngle = Vector2.new(12, 25),
			Acceleration = Vector3.new(0, -3, 0),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-300, 300),
			Color = ColorSequence.new(Color3.new(1, 1, 1)),
			Transparency = fadeSeq(0),
			LightInfluence = 0.6,
		})
		-- Leaves tumbling along the ground.
		emitter(low, {
			Texture = img(texture),
			EmissionDirection = Enum.NormalId.Right,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8, 0.3), NumberSequenceKeypoint.new(1, 0.8, 0.3) }),
			Speed = NumberRange.new(20, 32),
			Lifetime = NumberRange.new(3, 4),
			Rate = 14,
			SpreadAngle = Vector2.new(5, 8),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-500, 500),
			Color = ColorSequence.new(Color3.new(1, 1, 1)),
			Transparency = fadeSeq(0),
			LightInfluence = 0.6,
		})
	end
	-- Curling wind lines.
	emitter(box, {
		Texture = img("Vfx_Wind"),
		Orientation = Enum.ParticleOrientation.FacingCamera,
		EmissionDirection = Enum.NormalId.Right,
		Size = seq(9),
		Speed = NumberRange.new(60, 80),
		Lifetime = NumberRange.new(1, 1.4),
		Rate = 10,
		SpreadAngle = Vector2.new(4, 4),
		Color = ColorSequence.new(rgb(255, 255, 255)),
		Transparency = fadeSeq(0.45),
		LightEmission = 0.5,
		LightInfluence = 0,
	})
	addUpdate(scene, function(_, at, floor)
		box.CFrame = CFrame.new(at - WIND * 70 + Vector3.new(0, 12, 0)) * look
		low.CFrame = CFrame.new(Vector3.new(at.X, floor.Y + 1, at.Z) - WIND * 50) * look
	end)
end

-- Rainbow: a real rainbow arching over the whole length of the map (every zone sees it),
-- standing on clouds at both ends, drawn in from one end; plus a rainbow carpet trail
-- behind every player and sparkles in the air.
local function rainbow(scene: Scene)
	local model = keep(scene, Instance.new("Model"))
	model.Name = "Rainbow"
	model.Parent = folder
	local sideX = MAP_MAX.X + 320
	local zA, zB = MAP_MAX.Y + 160, MAP_MIN.Y - 160
	local center = Vector3.new(sideX, -60, (zA + zB) / 2)
	local radius = math.abs(zA - zB) / 2
	local bandWidth = 22
	local steps = 72
	local segments: { BasePart } = {}
	for b, color in BANDS do
		local r = radius - (b - 1) * bandWidth
		local arcLen = math.pi * r / steps
		for i = 0, steps - 1 do
			local a = math.pi * (i + 0.5) / steps
			local pos = center + Vector3.new(0, math.sin(a) * r, math.cos(a) * r)
			local tangent = Vector3.new(0, math.cos(a), -math.sin(a))
			local seg = part("Band", Vector3.new(6, bandWidth + 0.5, arcLen + 1), model)
			seg.CFrame = CFrame.lookAt(pos, pos + tangent)
			seg.Material = Enum.Material.Neon
			seg.Color = color
			seg.Transparency = 1
			seg:SetAttribute("Order", i)
			table.insert(segments, seg)
		end
	end
	-- Cloud puffs where it touches down.
	for _, endZ in { zA, zB } do
		for _ = 1, 9 do
			local puff = part("Cloud", Vector3.new(1, 1, 1) * rng:NextNumber(40, 75), model)
			puff.Shape = Enum.PartType.Ball
			puff.Material = Enum.Material.SmoothPlastic
			puff.Color = Color3.new(1, 1, 1)
			puff.Position = Vector3.new(sideX + rng:NextNumber(-40, 40), rng:NextNumber(-10, 30), endZ + rng:NextNumber(-60, 60))
			puff.Transparency = 1
			TweenService:Create(puff, TweenInfo.new(2), { Transparency = 0.15 }):Play()
		end
	end
	-- Draw it in from one end to the other.
	task.spawn(function()
		for i = 0, steps - 1 do
			for _, seg in segments do
				if seg:GetAttribute("Order") == i and seg.Parent then
					TweenService:Create(seg, TweenInfo.new(0.5), { Transparency = 0.32 }):Play()
				end
			end
			task.wait(0.03)
		end
	end)
	table.insert(scene.cleanup, function()
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				TweenService:Create(p, TweenInfo.new(2.5), { Transparency = 1 }):Play()
			end
		end
	end)

	-- Rainbow carpet behind every player (like Grow a Garden's rainbow): a flat trail at the feet.
	local trails: { [Player]: Trail } = {}
	local function carpet(p: Player)
		local character = p.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or trails[p] then
			return
		end
		local a0 = Instance.new("Attachment")
		a0.Name = "RainbowCarpetL"
		a0.Position = Vector3.new(-1.6, -2.8, 0)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Name = "RainbowCarpetR"
		a1.Position = Vector3.new(1.6, -2.8, 0)
		a1.Parent = root
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 2.2
		trail.MinLength = 0.2
		trail.FaceCamera = false
		trail.LightEmission = 0.6
		trail.LightInfluence = 0.2
		trail.Color = RAINBOW
		trail.Transparency = NumberSequence.new(0.15, 1)
		trail.Parent = root
		trails[p] = trail
		table.insert(scene.cleanup, function()
			a0:Destroy()
			a1:Destroy()
			trail:Destroy()
		end)
	end
	local nextCheck = 0
	local sparkles = motes(scene, "Vfx_Sparkle", RAINBOW, 30, 0.7, 2)
	addUpdate(scene, function(_, _, floor)
		sparkles.CFrame = CFrame.new(floor + Vector3.new(0, 8, 0))
		if os.clock() > nextCheck then
			nextCheck = os.clock() + 1
			for _, p in Players:GetPlayers() do
				local trail = trails[p]
				if trail and not trail.Parent then
					trails[p] = nil
				end
				carpet(p)
			end
		end
	end)
end

local function goldenHour(scene: Scene)
	-- Slanted light shafts standing all over the map, fixed in the world.
	local anchor = keep(scene, part("GodRays", Vector3.new(1, 1, 1)))
	anchor.CFrame = CFrame.new()
	local sun = Vector3.new(-0.55, 1, -0.25).Unit
	local beams = {}
	for _ = 1, 26 do
		local x = rng:NextNumber(MAP_MIN.X, MAP_MAX.X)
		local z = rng:NextNumber(MAP_MIN.Y, MAP_MAX.Y)
		local foot = groundAt(Vector3.new(x, 0, z))
		local a0 = attachment(anchor, foot + sun * 260)
		local a1 = attachment(anchor, foot)
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0 = rng:NextNumber(30, 55)
		beam.Width1 = beam.Width0 * 0.6
		beam.FaceCamera = true
		beam.Texture = img("Vfx_GodRay")
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(rgb(255, 215, 130))
		beam.Transparency = NumberSequence.new(1)
		beam.Parent = anchor
		table.insert(beams, { beam = beam, phase = rng:NextNumber() * 6 })
	end
	addUpdate(scene, function()
		local t = os.clock()
		for _, b in beams do
			local v = 0.72 + math.sin(t * 0.4 + b.phase) * 0.12
			b.beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, v), NumberSequenceKeypoint.new(1, 1) })
		end
	end)
	motes(scene, "Vfx_Glow", ColorSequence.new(rgb(255, 210, 110)), 45, 0.5, 1.5)
	motes(scene, "Vfx_Sparkle", ColorSequence.new(rgb(255, 230, 150)), 12, 0.8, 1)
end

-- Aurora: curtains of light hanging along both long sides of the map, fixed in the world
-- so every player sees the same sky wherever they are.
local function aurora(scene: Scene)
	local anchor = keep(scene, part("Aurora", Vector3.new(1, 1, 1)))
	anchor.CFrame = CFrame.new()
	local colors = {
		ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(80, 255, 170)), ColorSequenceKeypoint.new(0.5, rgb(80, 220, 255)), ColorSequenceKeypoint.new(1, rgb(170, 100, 255)) }),
		ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(170, 100, 255)), ColorSequenceKeypoint.new(0.5, rgb(80, 255, 170)), ColorSequenceKeypoint.new(1, rgb(80, 220, 255)) }),
		ColorSequence.new(rgb(90, 255, 190)),
	}
	local zA, zB = MAP_MAX.Y + 250, MAP_MIN.Y - 250
	local groundY = groundAt(Vector3.new(0, 0, (MAP_MIN.Y + MAP_MAX.Y) / 2)).Y
	for side = -1, 1, 2 do
		local edge = if side < 0 then MAP_MIN.X else MAP_MAX.X
		for i, color in colors do
			local x = edge + side * (260 + i * 70)
			local y = groundY + 190 + i * 30
			-- Several pieces along the map so each one can wave on its own.
			local pieces = 3
			for k = 0, pieces - 1 do
				local z0 = zA + (zB - zA) * k / pieces
				local z1 = zA + (zB - zA) * (k + 1) / pieces
				local a0 = attachment(anchor, Vector3.new(x, y, z0), Vector3.xAxis)
				local a1 = attachment(anchor, Vector3.new(x, y + 25, z1), Vector3.xAxis)
				local beam = Instance.new("Beam")
				beam.Attachment0 = a0
				beam.Attachment1 = a1
				local bend = 200 * (if (i + k) % 2 == 0 then -1 else 1)
				beam.CurveSize0 = bend
				beam.CurveSize1 = bend
				beam.Width0 = 190
				beam.Width1 = 160
				beam.Segments = 50
				beam.FaceCamera = true
				beam.Texture = img("Vfx_Aurora")
				beam.TextureMode = Enum.TextureMode.Wrap
				beam.TextureLength = 260
				beam.TextureSpeed = 0.05 * i
				beam.LightEmission = 1
				beam.LightInfluence = 0
				beam.Color = color
				beam.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.9),
					NumberSequenceKeypoint.new(0.2, 0.3),
					NumberSequenceKeypoint.new(0.8, 0.3),
					NumberSequenceKeypoint.new(1, 0.9),
				})
				beam.Parent = anchor
			end
		end
	end
	motes(scene, "Vfx_Sparkle", ColorSequence.new(rgb(180, 255, 230)), 14, 0.6, 1)
end

-- Starfall: shooting stars streak down all over the map's sky; the server's stars land
-- on eggs and the field (WeatherStrike).
local function starfall(scene: Scene)
	local nextStar = 0
	motes(scene, "Vfx_Sparkle", ColorSequence.new(STAR), 16, 0.7, 1)
	local groundY = groundAt(Vector3.new(0, 0, (MAP_MIN.Y + MAP_MAX.Y) / 2)).Y
	addUpdate(scene, function()
		if os.clock() < nextStar then
			return
		end
		nextStar = os.clock() + rng:NextNumber(0.6, 1.4)
		local start = Vector3.new(
			rng:NextNumber(MAP_MIN.X - 300, MAP_MAX.X + 300),
			groundY + rng:NextNumber(220, 340),
			rng:NextNumber(MAP_MIN.Y - 200, MAP_MAX.Y + 200)
		)
		local travel = Vector3.new(rng:NextNumber(-1, 1) * 120, -rng:NextNumber(140, 220), rng:NextNumber(-1, 1) * 120)
		local star = part("ShootingStar", Vector3.new(1.6, 1.6, 1.6))
		star.Shape = Enum.PartType.Ball
		star.Material = Enum.Material.Neon
		star.Color = STAR
		star.Transparency = 0
		star.Position = start
		local t0 = attachment(star, Vector3.new(0, 0.8, 0))
		local t1 = attachment(star, Vector3.new(0, -0.8, 0))
		local trail = Instance.new("Trail")
		trail.Attachment0 = t0
		trail.Attachment1 = t1
		trail.Lifetime = 0.4
		trail.FaceCamera = true
		trail.LightEmission = 1
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.Transparency = NumberSequence.new(0, 1)
		trail.Color = ColorSequence.new(rgb(255, 250, 220), rgb(255, 160, 80))
		trail.Parent = star
		emitter(star, {
			Texture = img("Vfx_Sparkle"),
			Size = seq(2.2, 0),
			Speed = NumberRange.new(0.5, 2),
			Lifetime = NumberRange.new(0.4, 0.8),
			Rate = 60,
			Rotation = NumberRange.new(0, 90),
			Color = ColorSequence.new(rgb(255, 245, 200), rgb(255, 170, 90)),
			LightEmission = 1,
			LightInfluence = 0,
		})
		local tween = TweenService:Create(star, TweenInfo.new(0.9, Enum.EasingStyle.Linear), { Position = start + travel, Transparency = 1 })
		tween:Play()
		tween.Completed:Once(function()
			star:Destroy()
		end)
	end)
end

-- Disco: the whole map is the dance floor. Every zone gets its own mirror ball, sweeping
-- coloured spotlights with light spots on the ground, laser towers at its corners and
-- confetti over it. Everything runs on server time, so every player sees the same show.
local BEAT = 60 / 118 -- Funky Disco Beats tempo
local function discoZone(scene: Scene, zone: any, index: number): (number) -> ()
	local rig = keep(scene, Instance.new("Model"))
	rig.Name = "Disco_" .. zone.Id
	rig.Parent = folder
	local size = zone.Max - zone.Min
	local mid = (zone.Min + zone.Max) / 2
	local floorY = groundAt(Vector3.new(mid.X, 0, mid.Y)).Y
	local hub = Vector3.new(mid.X, floorY, mid.Y)

	local ball = part("MirrorBall", Vector3.new(26, 26, 26), rig)
	ball.Transparency = 0
	ball.Material = Enum.Material.SmoothPlastic
	ball.Reflectance = 0.2
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.TextureId = img("Vfx_DiscoTiles")
	mesh.Parent = ball
	local ballLight = Instance.new("PointLight")
	ballLight.Range = 60
	ballLight.Brightness = 4
	ballLight.Parent = ball
	local ballPos = hub + Vector3.new(0, 80, 0)
	local chain = part("Chain", Vector3.new(0.6, 140, 0.6), rig)
	chain.Transparency = 0
	chain.Material = Enum.Material.Metal
	chain.Color = rgb(60, 60, 70)
	chain.CFrame = CFrame.new(ballPos + Vector3.new(0, 83, 0))
	emitter(ball, {
		Texture = img("Vfx_Star"),
		Size = seq(3, 0),
		Speed = NumberRange.new(0.1),
		Lifetime = NumberRange.new(0.3, 0.6),
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		LightEmission = 1,
		Rate = 25,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
	})

	local center = attachment(ball, Vector3.zero)
	local floorPart = part("DiscoFloor", Vector3.new(1, 1, 1), rig)
	floorPart.CFrame = CFrame.new(hub)
	local spots = {}
	for i = 1, 8 do
		local spotAtt = attachment(floorPart, Vector3.zero)
		local beam = Instance.new("Beam")
		beam.Attachment0 = center
		beam.Attachment1 = spotAtt
		beam.Width0 = 1.5
		beam.Width1 = 16
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Texture = img("Vfx_Glow")
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.Transparency = NumberSequence.new(0.35, 0.7)
		beam.Parent = ball
		local light = part("Spot", Vector3.new(18, 0.05, 18), rig)
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Top
		decal.Texture = img("Vfx_Spot")
		decal.Transparency = 0.15
		decal.Parent = light
		table.insert(spots, { att = spotAtt, beam = beam, decal = decal, light = light, phase = i * 0.8 + index, speed = (0.4 + (i % 4) * 0.13) * (if i % 2 == 0 then 1 else -1) })
	end

	local lasers = {}
	for corner = 1, 4 do
		local sx = if corner == 1 or corner == 2 then -1 else 1
		local sz = if corner == 1 or corner == 3 then -1 else 1
		local base = hub + Vector3.new(sx * size.X * 0.52, 0, sz * size.Y * 0.48)
		local tower = part("Tower", Vector3.new(3, 40, 3), rig)
		tower.Transparency = 0
		tower.Material = Enum.Material.Metal
		tower.Color = rgb(40, 40, 50)
		tower.CFrame = CFrame.new(base + Vector3.new(0, 20, 0))
		local head = part("Head", Vector3.new(5, 5, 5), rig)
		head.Transparency = 0
		head.Material = Enum.Material.Neon
		head.CFrame = CFrame.new(base + Vector3.new(0, 42, 0))
		local from = attachment(head, Vector3.zero)
		local beams = {}
		for _ = 1, 3 do
			local target = attachment(floorPart, Vector3.zero)
			local beam = Instance.new("Beam")
			beam.Attachment0 = from
			beam.Attachment1 = target
			beam.Width0 = 0.5
			beam.Width1 = 0.5
			beam.FaceCamera = true
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Transparency = NumberSequence.new(0.1)
			beam.Parent = head
			table.insert(beams, { beam = beam, target = target })
		end
		table.insert(lasers, { head = head, beams = beams, corner = corner })
	end

	local confetti = part("Confetti", Vector3.new(size.X, 1, size.Y), rig)
	confetti.CFrame = CFrame.new(hub + Vector3.new(0, 45, 0))
	for _, color in { rgb(255, 80, 120), rgb(255, 220, 60), rgb(80, 200, 255), rgb(140, 255, 120), rgb(200, 110, 255) } do
		emitter(confetti, {
			Texture = img("Vfx_Confetti"),
			EmissionDirection = Enum.NormalId.Bottom,
			Size = seq(0.8),
			Speed = NumberRange.new(4, 8),
			Lifetime = NumberRange.new(6, 8),
			Rate = 9,
			SpreadAngle = Vector2.new(40, 40),
			Acceleration = Vector3.new(0, -2, 0),
			Drag = 0.4,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-300, 300),
			Color = ColorSequence.new(color),
			Transparency = fadeSeq(0),
			LightEmission = 0.4,
		})
	end

	local rx, rz = size.X * 0.45, size.Y * 0.45
	return function(t: number)
		local beat = (t % BEAT) / BEAT
		local pulse = 1 - beat
		local hue = (t * 0.12 + index * 0.2) % 1
		ball.CFrame = CFrame.new(ballPos) * CFrame.Angles(0, t * 0.8, 0)
		local tintBall = Color3.fromHSV(hue, 0.3, 1)
		mesh.VertexColor = Vector3.new(tintBall.R, tintBall.G, tintBall.B)
		ballLight.Color = Color3.fromHSV(hue, 0.6, 1)
		for i, s in spots do
			local a = t * s.speed + s.phase
			local wob = math.sin(t * 0.7 + i) * 0.35 + 0.65
			local offset = Vector3.new(math.cos(a) * rx * wob, 0.1, math.sin(a * 1.3) * rz * wob)
			s.att.Position = offset
			local color = Color3.fromHSV((hue + i / #spots) % 1, 0.85, 1)
			s.beam.Color = ColorSequence.new(color)
			s.beam.Width1 = 14 + pulse * 6
			s.decal.Color3 = color
			s.light.CFrame = CFrame.new(hub + offset)
		end
		for _, l in lasers do
			local color = Color3.fromHSV((hue + l.corner * 0.25) % 1, 1, 1)
			l.head.Color = color
			for k, b in l.beams do
				local sweep = t * (0.9 + k * 0.2) + l.corner + k
				b.target.Position = Vector3.new(math.sin(sweep) * rx, 0.2, math.cos(sweep * 0.8) * rz)
				b.beam.Color = ColorSequence.new(color)
				b.beam.Width0 = 0.4 + pulse * 0.4
				b.beam.Width1 = b.beam.Width0
			end
		end
	end
end

local function disco(scene: Scene)
	local zones = {}
	for i, zone in Zones.List do
		table.insert(zones, discoZone(scene, zone, i))
	end
	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "WeatherDisco"
	tint.Parent = Lighting
	table.insert(scene.cleanup, function()
		TweenService:Create(tint, TweenInfo.new(2), { TintColor = Color3.new(1, 1, 1), Brightness = 0 }):Play()
		task.delay(2.1, function()
			tint:Destroy()
		end)
	end)
	addUpdate(scene, function()
		local t = Workspace:GetServerTimeNow()
		for _, update in zones do
			update(t)
		end
		local pulse = 1 - (t % BEAT) / BEAT
		tint.TintColor = Color3.fromHSV((t * 0.12) % 1, 0.22, 1)
		tint.Brightness = pulse * 0.06
	end)
end

local function eggRainSky(scene: Scene)
	motes(scene, "Vfx_Sparkle", ColorSequence.new(rgb(255, 200, 230), rgb(255, 240, 170)), 26, 0.7, 1.5)
end

-- Special moons: a moon image hung in the world along the moon's direction (at least 28
-- degrees up), only MOON_DISTANCE studs from the camera and sized so it looks as big as a
-- far moon. Close enough that the fog doesn't wash it out (far away it turned into a blue
-- square), and being in the world, roofs, trees and posts in front of it cover it. The
-- sky's own moon is hidden (preset CelestialBodiesShown off).
local MOON_DISTANCE = 220
local function screenMoon(scene: Scene, texture: string, degrees: number)
	local holder = keep(scene, part("Moon", Vector3.new(1, 1, 1)))
	local studs = 2 * MOON_DISTANCE * math.tan(math.rad(degrees) / 2) / 0.6 -- disc fills 60%
	local board = Instance.new("BillboardGui")
	board.Name = "Moon"
	board.Size = UDim2.fromScale(studs, studs)
	board.LightInfluence = 0
	board.Brightness = 1.4
	board.MaxDistance = math.huge
	board.AlwaysOnTop = false
	board.Parent = holder
	local image = Instance.new("ImageLabel")
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.Image = img(texture)
	image.ImageTransparency = 1
	image.Parent = board
	TweenService:Create(image, TweenInfo.new(3), { ImageTransparency = 0 }):Play()
	table.insert(scene.cleanup, function()
		TweenService:Create(image, TweenInfo.new(2), { ImageTransparency = 1 }):Play()
	end)
	local bind = "WeatherMoon_" .. texture
	RunService:BindToRenderStep(bind, Enum.RenderPriority.Camera.Value + 1, function()
		if not holder.Parent then
			RunService:UnbindFromRenderStep(bind)
			return
		end
		local cam = camera()
		if not cam then
			return
		end
		local dir = Lighting:GetMoonDirection()
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude < 0.05 then
			flat = Vector3.new(0.3, 0, -1)
		end
		local elevation = math.max(math.asin(math.clamp(dir.Y, -1, 1)), math.rad(28))
		dir = flat.Unit * math.cos(elevation) + Vector3.yAxis * math.sin(elevation)
		holder.CFrame = CFrame.new(cam.CFrame.Position + dir * MOON_DISTANCE)
	end)
end

local function bloodMoon(scene: Scene)
	screenMoon(scene, "Vfx_BloodMoon", 9)
	motes(scene, "Vfx_Glow", ColorSequence.new(rgb(255, 120, 60), rgb(160, 0, 0)), 70, 0.35, 3)
end

local function goldMoon(scene: Scene)
	screenMoon(scene, "Vfx_GoldMoon", 9)
	motes(scene, "Vfx_Glow", ColorSequence.new(rgb(255, 215, 90)), 50, 0.4, 1.2)
	motes(scene, "Vfx_Sparkle", ColorSequence.new(rgb(255, 230, 140)), 14, 0.7, 0.8)
end

local function rainbowMoon(scene: Scene)
	screenMoon(scene, "Vfx_RainbowMoon", 9)
	motes(scene, "Vfx_Sparkle", RAINBOW, 35, 0.7, 1.5)
end

local function megaMoon(scene: Scene)
	screenMoon(scene, "Vfx_MegaMoon", 20)
	motes(scene, "Vfx_Glow", ColorSequence.new(rgb(190, 220, 255)), 30, 0.4, 1)
end

local BUILDERS: { [string]: (Scene) -> () } = {
	Rain = function(scene)
		rain(scene, false)
	end,
	Thunderstorm = function(scene)
		rain(scene, true)
		local nextFlash = os.clock() + 2
		addUpdate(scene, function(_, at, floor)
			if os.clock() > nextFlash then
				-- Far-off lightning for the mood (the real strikes come from the server).
				-- Strikes under a cloud a good way off, so the bolt comes out of it.
				nextFlash = os.clock() + rng:NextNumber(3, 7)
				local away = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit * rng:NextNumber(220, 420)
				local spot = Vector3.new(at.X, floor.Y, at.Z) + away
				local cloud = cloudAbove(spot)
				if cloud then
					spot = Vector3.new(cloud.pos.X, floor.Y, cloud.pos.Z)
				end
				lightningAt(spot, false, false)
			end
		end)
	end,
	Snow = snow,
	Windy = windy,
	Rainbow = rainbow,
	GoldenHour = goldenHour,
	Aurora = aurora,
	Starfall = starfall,
	Disco = disco,
	EggRain = eggRainSky,
	BloodMoon = bloodMoon,
	GoldMoon = goldMoon,
	RainbowMoon = rainbowMoon,
	MegaMoon = megaMoon,
}

-- Looping sound beds -----------------------------------------------------------------------------

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

-- Banner: icon, name and one line, no box, fading in and out at the top of the screen ------

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

-- State -> scenes ----------------------------------------------------------------------------------
-- Three slots run side by side: the Egg Rain, the weather and the moon. The sky uses the
-- most important one (Egg Rain > weather > special moon > night > day).

type Slot = { id: string, scene: Scene? }
local slots: { [string]: Slot } = { event = { id = "" }, weather = { id = "" }, moon = { id = "" } }

local function endScene(scene: Scene?)
	if not scene then
		return
	end
	for _, fn in scene.cleanup do
		task.spawn(fn)
	end
	-- Let particles stop and fade instead of vanishing.
	for _, inst in scene.parts do
		for _, d in inst:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				d.Enabled = false
			elseif d:IsA("Beam") then
				TweenService:Create(d, TweenInfo.new(2), { Width0 = 0, Width1 = 0 }):Play()
			end
		end
	end
	task.delay(3, function()
		for _, inst in scene.parts do
			inst:Destroy()
		end
	end)
end

local function phaseNow(): string
	local start = State.server("CycleStart")
	if type(start) ~= "number" then
		return "Day"
	end
	local phase = Weather.phase(Workspace:GetServerTimeNow() - start)
	return phase
end

local function setSlot(key: string, id: string, announce: boolean)
	local slot = slots[key]
	if slot.id == id then
		return
	end
	endScene(slot.scene)
	slot.id = id
	slot.scene = nil
	local builder = BUILDERS[id]
	if builder then
		local scene = newScene()
		builder(scene)
		loopSound(scene, id)
		slot.scene = scene
	end
	local def = Weather.ById[id]
	if announce and def and def.Blurb ~= "" then
		showBanner(def.Name, def.Blurb, def.Color, "Icon_Weather_" .. def.Id)
		Ui.sound(if def.Id == "BloodMoon" then "BloodMoonStart" else "WeatherStart")
	end
end

local skyKey = ""
local function refreshSky()
	local key = if slots.event.id ~= "" then slots.event.id
		elseif slots.weather.id ~= "" then slots.weather.id
		elseif slots.moon.id ~= "" and slots.moon.id ~= "NormalMoon" then slots.moon.id
		elseif phaseNow() == "Night" then "Night"
		else ""
	-- A special moon keeps its moon in the sky even when rain or an Egg Rain owns the rest
	-- of the look.
	local moonId = slots.moon.id
	local moonSky = if moonId ~= "" and moonId ~= key and PRESETS[moonId] then PRESETS[moonId].Sky else nil
	local fullKey = if moonSky then key .. "+" .. moonId else key
	if fullKey ~= skyKey then
		skyKey = fullKey
		local preset = PRESETS[key]
		if moonSky then
			preset = table.clone(preset or {})
			local sky = table.clone(preset.Sky or {})
			for prop, value in moonSky do
				sky[prop] = value
			end
			preset.Sky = sky
		end
		applySky(preset)
	end
end

-- Fades to the zone's clear-day look once the player has been in that zone for a second
-- (so running along a path between zones doesn't flicker). Any weather on top stays.
local pendingLook: SkyLooks.Look? = nil
local pendingSince = 0
local function refreshLook()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local zone = Grid.zoneAt(if root then root.Position else focus())
	local look = SkyLooks.forZone(zone and zone.Id)
	if look == currentLook then
		pendingLook = nil
		return
	end
	if look ~= pendingLook then
		pendingLook = look
		pendingSince = os.clock()
		return
	end
	if os.clock() - pendingSince < 1 then
		return
	end
	pendingLook = nil
	currentLook = look
	lookSky = SkyLooks.skyProps(look, img)
	applySky(currentPreset)
end

local function refresh(announce: boolean)
	local event = State.server("EventState")
	setSlot("event", if event == "Shower" or event == "Countdown" then "EggRain" else "", announce)
	local weather = State.server("Weather")
	setSlot("weather", if type(weather) == "string" then weather else "", announce)
	local moon = State.server("Moon")
	setSlot("moon", if type(moon) == "string" then moon else "", announce)
	refreshSky()
end

-- Egg Rain / Mega Moon: eggs fall out of the sky -------------------------------------------------

local function eggDrop(position: Vector3, rarity: string, fallSeconds: number)
	local floor = groundAt(position)
	if (floor - focus()).Magnitude > 900 then
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
		local at = start:Lerp(floor, t * t)
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

-- A growing egg picked up a weather mutation: a burst in its colour.
local function eggUpgraded(position: Vector3, mutation: string)
	if (position - focus()).Magnitude > 300 then
		return
	end
	local def = Eggs.MutationByName[mutation]
	local color = if def then def.Color else Color3.new(1, 1, 1)
	sparkBurst(position + Vector3.new(0, 2, 0), color, 30, nil, 0.6)
	shockRing(position, color, 2, 14, 0.5)
	soundAt("Sparkle", position)
end

-- Start ------------------------------------------------------------------------------------------

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
	-- The map's own sky is built by the server while we start up: wait for it.
	Lighting:WaitForChild("WorldSky", 15)
	Lighting:WaitForChild("WorldAtmosphere", 5)
	Lighting:WaitForChild("WorldGrade", 5)
	task.wait(0.5)
	capture()
	refresh(false)
	local state = State.serverState
	for _, name in { "Weather", "Moon", "EventState" } do
		state:GetAttributeChangedSignal(name):Connect(function()
			refresh(true)
		end)
	end

	Net.event("EggDrop").OnClientEvent:Connect(function(position: Vector3, rarity: string, fallSeconds: number)
		eggDrop(position, rarity, fallSeconds)
	end)
	Net.event("WeatherStrike").OnClientEvent:Connect(function(position: Vector3, kind: string?, hitEgg: boolean?)
		if kind == "Star" then
			starAt(position, hitEgg == true)
		elseif (position - focus()).Magnitude < 1200 then
			lightningAt(position, hitEgg == true, true)
		end
	end)
	Net.event("EggUpgraded").OnClientEvent:Connect(eggUpgraded)

	local lastGround = Vector3.zero
	local groundCheck = 0
	local cloudsBuilt = false
	RunService.RenderStepped:Connect(function(dt)
		-- Day/night: the clock follows the server's cycle.
		local start = State.server("CycleStart")
		if type(start) == "number" then
			Lighting.ClockTime = Weather.clockTime(Workspace:GetServerTimeNow() - start)
		end
		local at = focus()
		groundCheck -= dt
		if groundCheck <= 0 then
			groundCheck = 0.2
			lastGround = groundAt(at)
			refreshLook() -- walked into another zone
			if not cloudsBuilt then
				cloudsBuilt = buildSkyClouds()
			end
			refreshSky() -- night starts / ends
		end
		updateSkyClouds(dt)
		local floor = Vector3.new(at.X, lastGround.Y, at.Z)
		for _, slot in slots do
			local scene = slot.scene
			if scene and scene.update then
				scene.update(dt, at, floor)
			end
		end
	end)
	-- Camera shake on top of whatever the camera scripts did this frame.
	RunService:BindToRenderStep("WeatherShake", Enum.RenderPriority.Camera.Value + 1, function()
		local cam = camera()
		if cam and os.clock() < shakeUntil then
			local left = shakeUntil - os.clock()
			local p = shakePower * math.min(1, left * 4)
			cam.CFrame *= CFrame.Angles(rng:NextNumber(-p, p) * 0.03, rng:NextNumber(-p, p) * 0.03, 0)
				* CFrame.new(rng:NextNumber(-p, p), rng:NextNumber(-p, p), 0)
		end
	end)
end

return WeatherController
