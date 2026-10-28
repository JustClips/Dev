--!strict
-- Placeholder sounds (files that ship with Roblox). Swap for real SFX later.
-- An empty string disables that sound.
return {
	Sweep = "rbxasset://sounds/clickfast.wav",
	Sell = "rbxasset://sounds/electronicpingshort.wav",
	Egg = "rbxasset://sounds/electronicpingshort.wav",
	Hatch = "rbxasset://sounds/electronicpingshort.wav",
	Click = "rbxasset://sounds/clickfast.wav",
	Error = "",
	Announce = "rbxasset://sounds/electronicpingshort.wav",
	Volumes = {
		Sweep = 0.15,
		Sell = 0.5,
		Egg = 0.5,
		Hatch = 0.7,
		Click = 0.3,
		Announce = 0.35,
	} :: { [string]: number },
}
