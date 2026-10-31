--!strict
-- Every sound in the game. All of these are free to use in any experience: Roblox's own UI
-- sounds, ProSoundEffects (SFX) and APM Music, the licensed libraries in the Creator Store.
-- Sound effects play through the "SFX" sound group and music through "Music", so the
-- settings sliders (AudioController) control each one. An empty Id turns a sound off.

export type SoundDef = { Id: string, Volume: number, Speed: number? }

local function id(n: number): string
	return "rbxassetid://" .. n
end

local Sounds = {}

Sounds.Sfx = {
	-- UI
	Click = { Id = id(15675032796), Volume = 0.45 }, -- Roblox_UI_Small_Click
	Open = { Id = id(15675024286), Volume = 0.35 }, -- Roblox_UI_Whoosh_01
	Pop = { Id = id(15675055424), Volume = 0.55 }, -- Roblox_UI_Cute_Pop
	Notify = { Id = id(15675085146), Volume = 0.4 }, -- Roblox_UI_Indicator
	Error = { Id = id(15675062723), Volume = 0.45 }, -- Roblox_UI_Whistle_Low
	Attention = { Id = id(17208361335), Volume = 0.8 }, -- Roblox GUI - Notification High (Roblox menu opened)
	Tutorial = { Id = id(15675043410), Volume = 0.5 }, -- Roblox_UI_Tonal_Stinger
	Announce = { Id = id(15675085146), Volume = 0.35 },
	-- Sweeping and selling
	Sweep = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.12 },
	Combo = { Id = id(9126073001), Volume = 0.35 }, -- Synth Sparkle Bell Ding (pitch rises with the combo)
	Sell = { Id = id(9113728042), Volume = 0.5 }, -- Cash Register 1
	Coin = { Id = id(9113849651), Volume = 0.4 }, -- Coin Throws 3
	Egg = { Id = id(15675055424), Volume = 0.55 }, -- picked up / placed an egg
	-- Hatching
	Wobble = { Id = id(9120918417), Volume = 0.5 }, -- Wood Knock On Wooden Door 3
	Charge = { Id = id(9116421342), Volume = 0.55 }, -- Magic Transformation 5
	Crack = { Id = id(9113959751), Volume = 0.6 }, -- Crack Egg Crunchy 16
	Hatch = { Id = id(9117841338), Volume = 0.8 }, -- Pop Airy 1
	Sparkle = { Id = id(9116395085), Volume = 0.45 }, -- Magic Glows Chiming Hits 5
	Reveal = { Id = id(9040193100), Volume = 0.5 }, -- Have a Little Fun (sting a)
	RareReveal = { Id = id(1836860398), Volume = 0.55 }, -- Winning Spirit (sting)
	HatchLift = { Id = id(15674975792), Volume = 0.45 }, -- Roblox_UI_Whoosh_03 (egg floats up)
	HatchTier = { Id = id(9126073318), Volume = 0.4 }, -- Synth Sparkle Bell Ding 2 (rarity climb, pitch rises)
	HatchChip = { Id = id(9117458008), Volume = 0.45 }, -- Plastic Crack 2 (bricks pop off a wobble)
	HatchRise = { Id = id(9125805781), Volume = 0.5 }, -- Rising Whoosh Hissing Build Up 2
	HatchSuck = { Id = id(9126102694), Volume = 0.55 }, -- Time Warp Searing Build Up Large Suck Rumble (Legendary+)
	HatchBricks = { Id = id(9117447650), Volume = 0.6 }, -- Plastic Break 1 (the egg bursts into bricks)
	HatchBoom = { Id = id(9120769331), Volume = 0.55 }, -- Wind Whoosh Sonic Boom Low End Impact 1 (Rare+)
	HatchShimmer = { Id = id(9120297092), Volume = 0.45 }, -- Twiddly Power Ons Glittery Metallic 1 (Epic+ reveal)
	HatchGong = { Id = id(9125585534), Volume = 0.4 }, -- Gong Chinese Style Single Hit (Mythic+)
	-- Live events
	Meteor = { Id = id(9118614718), Volume = 0.6 }, -- Rock Impact 1
	RockBreak = { Id = id(9118587698), Volume = 0.55 }, -- Rock Drop Breaks 3
	Gift = { Id = id(1840890621), Volume = 0.45 }, -- Twinkle Sting
	-- Egg Rain and weather
	EggFall = { Id = id(9116418234), Volume = 0.5 }, -- Magic Tone Falling Shimmer Flanged 1
	EggLand = { Id = id(9114109952), Volume = 0.7 }, -- Dirt Impacts 2
	Thunder1 = { Id = id(9116282544), Volume = 0.7 }, -- Lightning Strike Sharp Hissing Crack 1
	Thunder2 = { Id = id(9116282646), Volume = 0.7 }, -- Lightning Strike Sharp Hissing Crack 3
	Thunder3 = { Id = id(9116282791), Volume = 0.7 }, -- Lightning Strike Sharp Hissing Crack 4
	WeatherStart = { Id = id(9119447936), Volume = 0.45 }, -- Sparkle Bell Tree Wind Chimes 1
	BloodMoonStart = { Id = id(9125637399), Volume = 0.5 }, -- Magic Growl Eerie Tonal Swells
} :: { [string]: SoundDef }

-- Looping weather beds (WeatherController), faded in and out with the weather.
-- Music = true plays through the music slider and quietens the playlist meanwhile.
Sounds.Weather = {
	Rain = { Id = id(9112853287), Volume = 0.35 }, -- Rain Heavy 1
	Thunderstorm = { Id = id(9120020741), Volume = 0.5 }, -- Thunder Light Rain 1
	Snow = { Id = id(9113286969), Volume = 0.25 }, -- Barstow Wind Light Blustery Low Howl 2
	Windy = { Id = id(9114057128), Volume = 0.4 }, -- Desert Wind Whistley Light Gusts 2
	BloodMoon = { Id = id(140269757258221), Volume = 0.35 }, -- Eerie Drone (APM)
	Aurora = { Id = id(9112835862), Volume = 0.3 }, -- Night Ambience 1
	Disco = { Id = id(9038367768), Volume = 0.5, Music = true }, -- Funky Disco Beats (APM)
	Starfall = { Id = id(9112835862), Volume = 0.25 }, -- Night Ambience 1
	MegaMoon = { Id = id(9112836038), Volume = 0.25 }, -- Night Ambience 2
	-- Leaves underfoot (LeafController plays them where the leaves are, cut short)
	Rustle = { Id = id(9114515722), Volume = 0.35 }, -- Foliage Crunchy Rustle 10
	RustleBig = { Id = id(9114576220), Volume = 0.4 }, -- Giant Leaves 1
	RustleSeaweed = { Id = id(9116146385), Volume = 0.35 }, -- Kelp Movement 101
	RustlePaper = { Id = id(9117076285), Volume = 0.3 }, -- Newspaper Flutter 20
	RustleSnow = { Id = id(9113480004), Volume = 0.3 }, -- Body Fall Snow 2
	Gust = { Id = id(9114057128), Volume = 0.22 }, -- Desert Wind Whistley Light Gusts 2
} :: { [string]: { Id: string, Volume: number, Music: boolean? } }

-- Background music, shuffled. Cute and calm so it never gets annoying.
Sounds.Music = {
	{ Id = id(120231070741138), Name = "Curious Creatures" },
	{ Id = id(9038721261), Name = "Hide And Seek" },
	{ Id = id(9038721950), Name = "The Feel Good Song" },
	{ Id = id(1839768828), Name = "Simply Cute" },
	{ Id = id(1839737641), Name = "Happy Walk" },
	{ Id = id(9043887091), Name = "Lo-fi Chill A" },
} :: { { Id: string, Name: string } }

Sounds.MusicVolume = 0.35 -- music track volume at slider 100%
Sounds.DefaultMusic = 0.6 -- slider defaults (0-1)
Sounds.DefaultSfx = 0.8

return Sounds
