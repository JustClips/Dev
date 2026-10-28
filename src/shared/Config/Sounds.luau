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
	-- Live events
	Meteor = { Id = id(9118614718), Volume = 0.6 }, -- Rock Impact 1
	RockBreak = { Id = id(9118587698), Volume = 0.55 }, -- Rock Drop Breaks 3
	Gift = { Id = id(1840890621), Volume = 0.45 }, -- Twinkle Sting
} :: { [string]: SoundDef }

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
