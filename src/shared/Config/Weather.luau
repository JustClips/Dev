--!strict
-- Live weather events (Grow a Garden style). The server rolls one every few minutes;
-- everyone on the server sees the same sky, VFX and sounds (client WeatherController)
-- and gets the same bonus while it lasts (server WeatherService).
--
-- Bonuses a weather can give:
--   Mutation / MutationChance: pets hatched during it can come out with this mutation.
--   CashMult: sweeping cash multiplier.
--   LuckMult: multiplies the server's luck (egg rarity, mutations, Huge).
--   GoldenMult: more golden dust piles per zone.
--   HugeMult: multiplies the Huge pet chance.
--   Strikes: lightning hits the field now and then and turns piles golden.

export type WeatherDef = {
	Id: string,
	Name: string,
	Weight: number, -- how often it is picked (0 = only by command/product)
	Duration: number, -- seconds
	Color: Color3, -- banner / HUD colour
	Blurb: string, -- one short line under the name in the banner
	Mutation: string?,
	MutationChance: number?, -- 0-1 per hatch
	CashMult: number?,
	LuckMult: number?,
	GoldenMult: number?,
	HugeMult: number?,
	Strikes: boolean?,
}

local Weather = {}

Weather.List = {
	{
		Id = "Rain",
		Name = "Rain",
		Weight = 30,
		Duration = 150,
		Color = Color3.fromRGB(90, 160, 255),
		Blurb = "Wet leaves sell for 1.5x. Pets can hatch Wet!",
		Mutation = "Wet",
		MutationChance = 0.25,
		CashMult = 1.5,
	},
	{
		Id = "Thunderstorm",
		Name = "Thunderstorm",
		Weight = 14,
		Duration = 120,
		Color = Color3.fromRGB(255, 225, 70),
		Blurb = "Lightning turns piles golden. Pets can hatch Shocked!",
		Mutation = "Shocked",
		MutationChance = 0.2,
		Strikes = true,
	},
	{
		Id = "Snow",
		Name = "Snowfall",
		Weight = 18,
		Duration = 150,
		Color = Color3.fromRGB(190, 230, 255),
		Blurb = "Pets can hatch Frozen!",
		Mutation = "Frozen",
		MutationChance = 0.25,
	},
	{
		Id = "Windy",
		Name = "Leaf Storm",
		Weight = 20,
		Duration = 120,
		Color = Color3.fromRGB(255, 160, 60),
		Blurb = "Leaves everywhere! Sweeping pays 2x. Pets can hatch Windswept!",
		Mutation = "Windswept",
		MutationChance = 0.2,
		CashMult = 2,
	},
	{
		Id = "Rainbow",
		Name = "Rainbow",
		Weight = 10,
		Duration = 120,
		Color = Color3.fromRGB(255, 120, 230),
		Blurb = "2x server luck. Rainbow pets are 5x more common!",
		Mutation = "Rainbow",
		MutationChance = 0.05,
		LuckMult = 2,
	},
	{
		Id = "GoldenHour",
		Name = "Golden Hour",
		Weight = 12,
		Duration = 120,
		Color = Color3.fromRGB(255, 200, 60),
		Blurb = "3x golden piles. Golden pets more common!",
		Mutation = "Golden",
		MutationChance = 0.12,
		GoldenMult = 3,
	},
	{
		Id = "BloodMoon",
		Name = "Blood Moon",
		Weight = 6,
		Duration = 180,
		Color = Color3.fromRGB(255, 60, 70),
		Blurb = "3x Huge chance. Pets can hatch Bloodlit!",
		Mutation = "Bloodlit",
		MutationChance = 0.15,
		HugeMult = 3,
	},
	{
		Id = "Aurora",
		Name = "Aurora Night",
		Weight = 7,
		Duration = 180,
		Color = Color3.fromRGB(110, 255, 200),
		Blurb = "1.5x server luck. Pets can hatch Starlit!",
		Mutation = "Starlit",
		MutationChance = 0.15,
		LuckMult = 1.5,
	},
	{
		Id = "Disco",
		Name = "Disco Party",
		Weight = 3,
		Duration = 90,
		Color = Color3.fromRGB(200, 90, 255),
		Blurb = "Everybody dance! Pets can hatch Disco!",
		Mutation = "Disco",
		MutationChance = 0.3,
		CashMult = 1.5,
	},
} :: { WeatherDef }

Weather.ById = {} :: { [string]: WeatherDef }
for _, def in Weather.List do
	Weather.ById[def.Id] = def
end

-- Quiet time between two weathers (seconds).
Weather.GapMin = 150
Weather.GapMax = 270
-- First weather after a server starts.
Weather.FirstDelay = 60
-- Thunderstorm: seconds between strikes, and how many piles around a strike turn golden.
Weather.StrikeEvery = { 2.5, 6 }
Weather.StrikeGolden = 4
-- Roblox user ids allowed to use the "/weather <id>" and "/eggrain" chat commands
-- (anyone can in Studio). Dev's main and alt accounts.
Weather.Admins = { 822623546, 347852675 }

-- Short label for the HUD chip ("1.5x"), empty when the weather only gives a mutation.
function Weather.chipLabel(def: WeatherDef): string
	local mult = def.CashMult or def.LuckMult or def.GoldenMult or def.HugeMult
	return if mult then `{mult}x` else ""
end

function Weather.pick(rng: Random, except: string?): WeatherDef
	local total = 0
	for _, def in Weather.List do
		if def.Id ~= except then
			total += def.Weight
		end
	end
	local roll = rng:NextNumber() * total
	for _, def in Weather.List do
		if def.Id ~= except then
			roll -= def.Weight
			if roll <= 0 then
				return def
			end
		end
	end
	return Weather.List[1]
end

return Weather
