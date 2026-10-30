--!strict
-- Codes that ship with the game (post them on socials). Lives on the server so players
-- can't read codes that aren't out yet. Admins can add more in-game (admin panel, Codes
-- tab); those are kept in a DataStore and work in every server (CodeService).
--
-- Code: what players type (any case, spaces ignored). Rewards: same shape as
-- Config/Rewards (Cash = Seconds of the player's earnings with a Floor, Item, Egg).
-- ExpiresAt: unix time (UTC) or nil for never. Each player can use each code once.
local Rewards = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config.Rewards)

export type CodeDef = {
	Code: string,
	Rewards: { Rewards.Reward },
	ExpiresAt: number?,
}

return {
	{
		Code = "RELEASE",
		Rewards = {
			{ Kind = "Cash", Seconds = 600, Floor = 0.5 },
			{ Kind = "Item", Item = "LuckPotion", Amount = 2 },
		},
	},
	{
		Code = "SWEEP",
		Rewards = {
			{ Kind = "Item", Item = "CashPotion", Amount = 1 },
			{ Kind = "Item", Item = "SpeedPotion", Amount = 1 },
		},
	},
	{
		Code = "HALLOWEEN",
		Rewards = {
			{ Kind = "Egg", Rarity = "Epic" },
		},
		ExpiresAt = 1794009600, -- 7 Nov 2026 00:00 UTC
	},
} :: { CodeDef }
