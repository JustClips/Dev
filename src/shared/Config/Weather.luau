--!strict
-- Live weather, picked the way Grow a Garden 2 does it:
--   * Every server runs a 10 minute day/night cycle: 7:30 day, 0:30 sunset, 2:00 night.
--   * Once per day one weather is rolled from Weather.List by weight (Clear = nothing).
--     It starts at a random moment of the day and ends before sunset.
--   * At the start of each night a moon is rolled from Weather.Moons (mostly Normal).
-- Everyone on the server sees the same sky (client WeatherController) and gets the same
-- bonuses (server WeatherService).
--
-- Like crops in Grow a Garden, unopened eggs growing in your park get upgraded by the
-- weather: while it runs every growing egg has EggChance (per EggTick seconds) to gain the
-- weather's mutation, and the pet that hatches from it keeps it. Strikes = lightning or
-- falling stars hit random eggs (and the field) and give StrikeMutation.
--
-- Other bonuses: CashMult (sweeping cash), LuckMult (server luck), GoldenMult (golden
-- piles), HugeMult (Huge chance), GrowMult (eggs grow this much faster), RegrowMult
-- (leaves grow back in this share of the time), DropEggs (eggs fall on the field now and
-- then, all over the map).

export type WeatherDef = {
	Id: string,
	Name: string,
	Kind: "Weather" | "Moon",
	Weight: number,
	Duration: number, -- seconds (moons last the whole night)
	Color: Color3,
	Blurb: string, -- one short line under the name in the banner
	Mutation: string?,
	EggChance: number?, -- per growing egg per EggTick
	Strikes: string?, -- "Lightning" | "Star"
	StrikeMutation: string?,
	CashMult: number?,
	LuckMult: number?,
	GoldenMult: number?,
	HugeMult: number?,
	GrowMult: number?,
	RegrowMult: number?,
	DropEggs: boolean?,
}

local Weather = {}

Weather.DaySeconds = 450
Weather.SunsetSeconds = 30
Weather.NightSeconds = 120
Weather.CycleSeconds = Weather.DaySeconds + Weather.SunsetSeconds + Weather.NightSeconds
-- Weight of "no weather today" in the day roll.
Weather.ClearWeight = 1
-- Seconds between egg mutation rolls.
Weather.EggTick = 10

Weather.List = {
	{
		Id = "Rain",
		Name = "Rain",
		Kind = "Weather",
		Weight = 4,
		Duration = 300,
		Color = Color3.fromRGB(90, 160, 255),
		Blurb = "Eggs grow 2x faster. Eggs can turn Wet!",
		Mutation = "Wet",
		EggChance = 0.04,
		GrowMult = 2,
	},
	{
		Id = "Thunderstorm",
		Name = "Thunderstorm",
		Kind = "Weather",
		Weight = 3,
		Duration = 150,
		Color = Color3.fromRGB(255, 225, 70),
		Blurb = "Lightning strikes eggs and makes them Charged!",
		Strikes = "Lightning",
		StrikeMutation = "Shocked",
		GrowMult = 1.5,
	},
	{
		Id = "Rainbow",
		Name = "Rainbow",
		Kind = "Weather",
		Weight = 2,
		Duration = 300,
		Color = Color3.fromRGB(255, 120, 230),
		Blurb = "2x server luck. Eggs can turn Rainbow!",
		Mutation = "Rainbow",
		EggChance = 0.015,
		LuckMult = 2,
	},
	{
		Id = "Snow",
		Name = "Snowfall",
		Kind = "Weather",
		Weight = 1,
		Duration = 150,
		Color = Color3.fromRGB(190, 230, 255),
		Blurb = "Eggs can turn Frozen!",
		Mutation = "Frozen",
		EggChance = 0.06,
	},
	{
		Id = "Starfall",
		Name = "Starfall",
		Kind = "Weather",
		Weight = 1,
		Duration = 120,
		Color = Color3.fromRGB(255, 235, 140),
		Blurb = "Falling stars hit eggs and make them Starstruck!",
		Strikes = "Star",
		StrikeMutation = "Starstruck",
		LuckMult = 1.5,
	},
	{
		Id = "Aurora",
		Name = "Aurora",
		Kind = "Weather",
		Weight = 1,
		Duration = 120,
		Color = Color3.fromRGB(110, 255, 200),
		Blurb = "Eggs can turn Starlit!",
		Mutation = "Starlit",
		EggChance = 0.05,
	},
	{
		Id = "GoldenHour",
		Name = "Golden Hour",
		Kind = "Weather",
		Weight = 1,
		Duration = 240,
		Color = Color3.fromRGB(255, 200, 60),
		Blurb = "3x golden piles. Eggs can turn Golden!",
		Mutation = "Golden",
		EggChance = 0.025,
		GoldenMult = 3,
	},
	{
		Id = "Windy",
		Name = "Leaf Storm",
		Kind = "Weather",
		Weight = 1,
		Duration = 150,
		Color = Color3.fromRGB(255, 160, 60),
		Blurb = "Leaves blow back 4x faster. Eggs can turn Windswept!",
		Mutation = "Windswept",
		EggChance = 0.05,
		RegrowMult = 0.25,
		CashMult = 1.25,
	},
	{
		Id = "Disco",
		Name = "Disco",
		Kind = "Weather",
		Weight = 1,
		Duration = 120,
		Color = Color3.fromRGB(200, 90, 255),
		Blurb = "1.5x cash from sweeping. Eggs can turn Disco!",
		Mutation = "Disco",
		EggChance = 0.06,
		CashMult = 1.5,
	},
} :: { WeatherDef }

-- Night moons. Normal has no effect (and no banner).
Weather.Moons = {
	{ Id = "NormalMoon", Name = "Night", Kind = "Moon", Weight = 77, Duration = 0, Color = Color3.fromRGB(200, 210, 255), Blurb = "" },
	{
		Id = "GoldMoon",
		Name = "Gold Moon",
		Kind = "Moon",
		Weight = 13,
		Duration = 0,
		Color = Color3.fromRGB(255, 205, 60),
		Blurb = "4x golden piles. Eggs can turn Golden!",
		Mutation = "Golden",
		EggChance = 0.06,
		GoldenMult = 4,
	},
	{
		Id = "RainbowMoon",
		Name = "Rainbow Moon",
		Kind = "Moon",
		Weight = 6,
		Duration = 0,
		Color = Color3.fromRGB(255, 120, 230),
		Blurb = "3x server luck. Eggs can turn Rainbow!",
		Mutation = "Rainbow",
		EggChance = 0.04,
		LuckMult = 3,
	},
	{
		Id = "BloodMoon",
		Name = "Blood Moon",
		Kind = "Moon",
		Weight = 2,
		Duration = 0,
		Color = Color3.fromRGB(255, 60, 70),
		Blurb = "3x Huge chance. Eggs can turn Bloodlit!",
		Mutation = "Bloodlit",
		EggChance = 0.05,
		HugeMult = 3,
	},
	{
		Id = "MegaMoon",
		Name = "Mega Moon",
		Kind = "Moon",
		Weight = 2,
		Duration = 0,
		Color = Color3.fromRGB(150, 220, 255),
		Blurb = "Eggs fall all over the map. 2x Huge chance!",
		HugeMult = 2,
		DropEggs = true,
	},
} :: { WeatherDef }

Weather.ById = {} :: { [string]: WeatherDef }
for _, def in Weather.List do
	Weather.ById[def.Id] = def
end
for _, def in Weather.Moons do
	Weather.ById[def.Id] = def
end

-- Lightning / star strikes: seconds between strikes, and the share aimed at growing eggs.
Weather.StrikeEvery = { 2, 5 }
Weather.StrikeEggShare = 0.45
Weather.StrikeGolden = 4
-- Mega Moon: seconds between falling eggs.
Weather.DropEvery = { 4, 8 }
-- Roblox user ids allowed to use the "/weather <id>", "/night" and "/eggrain" chat
-- commands (anyone can in Studio). Dev's main and alt accounts.
Weather.Admins = { 822623546, 347852675 }

-- Day/night phase at a point of the cycle (seconds since the cycle started).
function Weather.phase(t: number): ("Day" | "Sunset" | "Night", number)
	t %= Weather.CycleSeconds
	if t < Weather.DaySeconds then
		return "Day", t / Weather.DaySeconds
	elseif t < Weather.DaySeconds + Weather.SunsetSeconds then
		return "Sunset", (t - Weather.DaySeconds) / Weather.SunsetSeconds
	end
	return "Night", (t - Weather.DaySeconds - Weather.SunsetSeconds) / Weather.NightSeconds
end

-- Lighting.ClockTime for a point of the cycle: morning to late afternoon over the day,
-- sunset, then through the night back to morning.
function Weather.clockTime(t: number): number
	local phase, k = Weather.phase(t)
	if phase == "Day" then
		return 7 + k * 10.3 -- 7:00 -> 17:18
	elseif phase == "Sunset" then
		return 17.3 + k * 1.6 -- -> 18:54
	end
	return (18.9 + k * 12.1) % 24 -- -> 7:00
end

-- Short label for the HUD chip ("2x"), empty when the weather only upgrades eggs.
function Weather.chipLabel(def: WeatherDef): string
	local mult = def.GrowMult or def.LuckMult or def.GoldenMult or def.HugeMult or def.CashMult
	return if mult then `{mult}x` else ""
end

local function roll(rng: Random, list: { WeatherDef }, clearWeight: number?): WeatherDef?
	local total = clearWeight or 0
	for _, def in list do
		total += def.Weight
	end
	local pick = rng:NextNumber() * total
	for _, def in list do
		pick -= def.Weight
		if pick <= 0 then
			return def
		end
	end
	return nil
end

-- Today's weather (nil = clear day).
function Weather.rollDay(rng: Random): WeatherDef?
	return roll(rng, Weather.List, Weather.ClearWeight)
end

function Weather.rollMoon(rng: Random): WeatherDef
	return roll(rng, Weather.Moons) or Weather.Moons[1]
end

return Weather
