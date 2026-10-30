--!strict
-- Economy and tuning numbers. Everything balance-related lives here or in the other configs.
local Economy = {
	-- Rebirth (GAME_PLAN §5.7). Price of rebirth 1, 2, 3...; past the end of the list each
	-- rebirth costs RebirthCostGrowth x the one before. Use Economy.rebirthCost(rebirths).
	-- Fitted with tools/balance/fit.py (targets there; check with tools/balance/sim.py).
	RebirthCosts = {
		12_000_000_000,
		270_000_000_000,
		1_800_000_000_000,
		69_000_000_000_000,
		1_300_000_000_000_000,
		8_700_000_000_000_000,
		16_000_000_000_000_000,
		24_000_000_000_000_000,
		37_000_000_000_000_000,
		54_000_000_000_000_000,
	},
	-- Robux shortcuts that speed you up without skipping the game:
	SkipRebirthMinShare = 0.3, -- Skip Rebirth needs 30% of the rebirth cost saved up
	CarRobuxMinTier = 4, -- Robux cars (unlock or rent) need the Leaf Blower first
	RebirthCostGrowth = 1.6,
	RebirthCashBonus = 0.5, -- +50% cash per rebirth
	RebirthsPerExtraSlot = 2,

	-- Base slots (GAME_PLAN §5.4): how many pets can be placed in your pet park.
	BaseSlots = 6,
	GamepassSlots = 3,
	-- Pet slots you can also buy with cash, one at a time (Pets panel). Price of the 1st, 2nd...
	SlotCashPrices = { 10_000, 75_000, 500_000 },
	MaxSlots = 18,

	-- Inventory (Steal an Egg style): eggs and pets wait here until you place them.
	PetBagSize = 60,
	EggBagSize = 40,
	PetSellSeconds = 60, -- selling a pet pays this many seconds of its income
	-- Incubators on the hatchery pad: how many eggs can hatch at once.
	Incubators = 4,
	RebirthsPerIncubator = 2, -- one more every 2 rebirths
	MaxIncubators = 8,

	-- Offline income
	OfflineIncomeRate = 0.5,
	OfflineCapSeconds = 2 * 3600,
	OfflineCapSecondsVIP = 4 * 3600,
	OfflineMinSeconds = 60, -- below this, no welcome back screen

	-- Cash multipliers
	VIPCashBonus = 0.2,
	Cash2xPassMult = 2,
	Cash2xBoostMult = 2,

	-- Sweeping (server validation)
	SweepMaxPerSecond = 10,
	SweepDistanceSlack = 6,
	SweepForwardOffset = 2.5,
	SellCooldown = 1,
	-- Leaf dumps: a full bag pours in over DumpSeconds, a small one over DumpMinSeconds.
	DumpSeconds = 4,
	DumpMinSeconds = 1.2,

	-- Eggs (GAME_PLAN §4, §5.3)
	TutorialEggTile = 5, -- guaranteed first egg on this tile cleared (must be <= 25)
	-- Coins from selling (CoinService): pick them up by walking near. Money Magnet upgrades
	-- (MagnetUpgrades) add pickup range; leftovers fly to you after AutoCollectSeconds.
	Coins = {
		MagnetBase = 7, -- studs
		MagnetPerLevel = 1.5, -- studs per Money Magnet / Rich Sweeper / Golden Broom level
		MagnetUpgrades = { "Cash" }, -- every level of the evolving Money Magnet hex
		AutoCollectSeconds = 20,
		DumpEvery = 0.6, -- seconds between coin bursts while pouring into a dump
		FullBagCoins = 60, -- coins a full bag turns into; a part of a bag gives its share
		MinBurst = 2, -- fewest coins in one dump burst
		MinSellAll = 8, -- Sell Anywhere: fewest coins in its one burst around you
	},
	EggDespawnSeconds = 60, -- eggs you found (only you see and can pick them up)
	EggRainDespawnSeconds = 45, -- Egg Rain eggs (shared)
	MaxGroundEggs = 40, -- eggs lying around a server at once; the oldest go first
	MaxGroundEggsPerPlayer = 5, -- found eggs per player on the ground
	CarryLimit = 1,
	CarryLimitPass = 3,

	-- Products
	-- On sale for Hours after you first see it (a "Leaves in" timer shows), and never once
	-- you reach tool HideAtToolTier or rebirth.
	StarterPack = { Cash = 500, EggRarity = "Uncommon", Cash2xMinutes = 10, Hours = 2, HideAtToolTier = 5 },
	ServerLuckMinutes = 15,

	-- Meteor Shower (GAME_PLAN §5.8)
	Shower = {
		-- Bar fills when this many Moon tiles have been cleared since the last shower,
		-- as a fraction of all Moon tiles. Tune for ~10-15 min with 8 players.
		FillFraction = 1.0,
		CountdownSeconds = 10,
		DurationSeconds = 60,
		EggInterval = 1.4,
		ExtendSecondsWhenBought = 30,
	},

	-- Offers (GAME_PLAN §6 "When offers appear")
	Offers = {
		GlobalCooldown = 180,
		PerOfferCooldown = 600,
		BackpackFullCount = 3,
		ToolStuckSeconds = 120,
		MoonBarFraction = 0.8,
	},

	-- Sweeping extras: keep sweeping to build a combo (cash x1 -> x3), golden dust piles
	-- (much more cash) and dust bunnies that run away and drop rewards when swept.
	Combo = { Step = 0.04, Max = 3, Timeout = 1.6 },
	Golden = { PerZone = 4, Mult = 15, CheckSeconds = 6 },
	TrashMult = 5, -- a trash tile (can, bottle...) pays this many times a leaf tile
	Bunnies = {
		PerZone = 3,
		CashSeconds = 25, -- reward = this many seconds of your earnings
		MinCashPerZoneMult = 80, -- floor: zone cash mult x this
		PotionChance = 0.22,
		EggChance = 0.06,
		FleeRadius = 16,
		Speed = 11,
		RespawnSeconds = 12,
		CatchSlack = 2,
	},

	-- Server loops
	StateFlushInterval = 0.2,
	TileBatchInterval = 0.1,
	IncomeTickSeconds = 1,
	AutosaveSeconds = 60,
	SessionStaleSeconds = 100, -- a save lock not refreshed for this long is dead (autosave is every 60 s)
	FullMessageCooldown = 4,
}

-- Cash needed for the next rebirth when you have `rebirths` already.
function Economy.rebirthCost(rebirths: number): number
	local list = Economy.RebirthCosts
	local n = #list
	if rebirths < n then
		return list[rebirths + 1]
	end
	return list[n] * Economy.RebirthCostGrowth ^ (rebirths - n + 1)
end

-- Friend boost: each friend in your server adds this much egg luck (BoostService), up to
-- FriendLuckMaxFriends friends. Shown as a chip on the HUD.
Economy.FriendLuckPerFriend = 0.1
Economy.FriendLuckMaxFriends = 10

return Economy
