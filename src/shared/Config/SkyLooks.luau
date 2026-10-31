--!strict
-- How the sky looks on a clear day, per zone: lighting, atmosphere, colour grade and a
-- sky gradient skybox (art/sky/skybox.py -> Sky_<Skybox>_<Face>). The clouds are cartoon
-- meshes drifting over the map (WeatherController, tinted by Clouds.Color); Roblox's own
-- Terrain.Clouds stay off (Cover 0) on clear days and only come in with rain and storms.
--
-- The server sets SkyLooks.Default (MapBuilder.setupLighting). Each client then fades to
-- the look of the zone its player is in (WeatherController), and every weather, moon and
-- event preset is drawn on top of that look and fades back to it when it ends.
--
-- Groups match WeatherController's presets: Lighting, Atmosphere, Grade
-- (Lighting.WorldGrade), Bloom, SunRays, Clouds (Terrain.Clouds), Sky.

export type Look = {
	Name: string,
	Skybox: string,
	Lighting: { [string]: any },
	Atmosphere: { [string]: any },
	Grade: { [string]: any },
	Bloom: { [string]: any },
	SunRays: { [string]: any },
	Clouds: { [string]: any },
	Sky: { [string]: any },
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local SKY = { StarCount = 0, CelestialBodiesShown = true, SunAngularSize = 14, MoonAngularSize = 8 }

local SkyLooks = {}

-- Bases, the plaza and anywhere outside a zone.
SkyLooks.Default = "Clear"

-- Zone id (Config/Zones) -> look id. Zones not listed use the default.
SkyLooks.ByZone = {
	Landing = "Backyard",
	Crater = "Clear", -- Park
	DarkSide = "Beach",
	Mars = "City",
	Europa = "Snow",
} :: { [string]: string }

SkyLooks.ById = {
	-- Clear blue sky with white clouds.
	Clear = {
		Name = "Clear",
		Skybox = "Clear",
		Lighting = {
			Brightness = 2.5,
			Ambient = rgb(115, 118, 128),
			OutdoorAmbient = rgb(155, 158, 170),
			ColorShift_Top = rgb(255, 246, 230),
			ExposureCompensation = 0,
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.35,
		},
		Atmosphere = { Density = 0.24, Offset = 0.25, Color = rgb(190, 214, 240), Decay = rgb(92, 128, 176), Glare = 0.05, Haze = 0.5 },
		Grade = { Saturation = 0.15, Contrast = 0.08, Brightness = 0, TintColor = rgb(255, 253, 250) },
		Bloom = { Intensity = 0.2, Size = 24, Threshold = 2.4 },
		SunRays = { Intensity = 0.06, Spread = 0.6 },
		Clouds = { Cover = 0, Density = 0.55, Color = rgb(255, 255, 255) },
		Sky = SKY,
	},
	-- Backyard (autumn leaves): blue sky, slightly warm horizon and light.
	Backyard = {
		Name = "Backyard",
		Skybox = "CozyAutumn",
		Lighting = {
			Brightness = 2.45,
			Ambient = rgb(122, 114, 110),
			OutdoorAmbient = rgb(162, 150, 140),
			ColorShift_Top = rgb(255, 232, 200),
			ExposureCompensation = 0,
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.35,
		},
		Atmosphere = { Density = 0.25, Offset = 0.25, Color = rgb(222, 214, 210), Decay = rgb(120, 122, 150), Glare = 0.08, Haze = 0.6 },
		Grade = { Saturation = 0.16, Contrast = 0.08, Brightness = 0, TintColor = rgb(255, 249, 240) },
		Bloom = { Intensity = 0.2, Size = 24, Threshold = 2.4 },
		SunRays = { Intensity = 0.08, Spread = 0.6 },
		Clouds = { Cover = 0, Density = 0.55, Color = rgb(255, 250, 244) },
		Sky = SKY,
	},
	-- Beach: deep tropical blue, aqua horizon, crisp bright light.
	Beach = {
		Name = "Beach",
		Skybox = "Tropical",
		Lighting = {
			Brightness = 2.8,
			Ambient = rgb(110, 122, 130),
			OutdoorAmbient = rgb(150, 168, 178),
			ColorShift_Top = rgb(255, 248, 232),
			ExposureCompensation = 0,
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.45,
		},
		Atmosphere = { Density = 0.22, Offset = 0.25, Color = rgb(176, 220, 240), Decay = rgb(80, 140, 180), Glare = 0.08, Haze = 0.4 },
		Grade = { Saturation = 0.2, Contrast = 0.08, Brightness = 0.01, TintColor = rgb(250, 255, 255) },
		Bloom = { Intensity = 0.22, Size = 24, Threshold = 2.3 },
		SunRays = { Intensity = 0.08, Spread = 0.6 },
		Clouds = { Cover = 0, Density = 0.55, Color = rgb(255, 255, 255) },
		Sky = { StarCount = 0, CelestialBodiesShown = true, SunAngularSize = 16, MoonAngularSize = 8 },
	},
	-- City: late-afternoon gold horizon, warm clouds.
	City = {
		Name = "City",
		Skybox = "GoldenHour",
		Lighting = {
			Brightness = 2.3,
			Ambient = rgb(132, 112, 100),
			OutdoorAmbient = rgb(172, 142, 120),
			ColorShift_Top = rgb(255, 210, 160),
			ExposureCompensation = 0,
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.4,
		},
		Atmosphere = { Density = 0.28, Offset = 0.25, Color = rgb(232, 200, 172), Decay = rgb(140, 110, 120), Glare = 0.15, Haze = 0.8 },
		Grade = { Saturation = 0.15, Contrast = 0.09, Brightness = 0, TintColor = rgb(255, 240, 222) },
		Bloom = { Intensity = 0.28, Size = 26, Threshold = 2.2 },
		SunRays = { Intensity = 0.12, Spread = 0.7 },
		Clouds = { Cover = 0, Density = 0.55, Color = rgb(255, 228, 200) },
		Sky = { StarCount = 0, CelestialBodiesShown = true, SunAngularSize = 16, MoonAngularSize = 8 },
	},
	-- Snowy Peaks: crisp cool blue.
	Snow = {
		Name = "Snowy Peaks",
		Skybox = "Frosty",
		Lighting = {
			Brightness = 2.6,
			Ambient = rgb(120, 126, 142),
			OutdoorAmbient = rgb(160, 168, 188),
			ColorShift_Top = rgb(236, 242, 255),
			ExposureCompensation = 0,
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.5,
		},
		Atmosphere = { Density = 0.27, Offset = 0.25, Color = rgb(206, 220, 240), Decay = rgb(110, 128, 170), Glare = 0.05, Haze = 0.7 },
		Grade = { Saturation = 0.08, Contrast = 0.07, Brightness = 0, TintColor = rgb(244, 248, 255) },
		Bloom = { Intensity = 0.22, Size = 24, Threshold = 2.3 },
		SunRays = { Intensity = 0.06, Spread = 0.6 },
		Clouds = { Cover = 0, Density = 0.55, Color = rgb(248, 250, 255) },
		Sky = SKY,
	},
} :: { [string]: Look }

local FACES = { "Bk", "Dn", "Ft", "Lf", "Rt", "Up" }

function SkyLooks.forZone(zoneId: string?): Look
	local id = zoneId and SkyLooks.ByZone[zoneId] or SkyLooks.Default
	return SkyLooks.ById[id] or SkyLooks.ById[SkyLooks.Default]
end

-- The look's Sky values plus its six skybox textures (SkyboxBk = "rbxassetid://...").
function SkyLooks.skyProps(look: Look, image: (string) -> string): { [string]: any }
	local props = table.clone(look.Sky)
	for _, face in FACES do
		local id = image(`Sky_{look.Skybox}_{face}`)
		if id ~= "" then
			props["Skybox" .. face] = id
		end
	end
	return props
end

return SkyLooks
