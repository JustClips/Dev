--!strict
-- Economy and tuning numbers. Everything balance-related lives here or in the other configs.
local Economy = {
	-- Rebirth (GAME_PLAN §5.7)
	-- Tuned with tools/balance/sim.py: first rebirth ~2 h, rebirth 5 ~18 h, rebirth 7 ~40 h.
	RebirthBaseCost = 150_000_000,
	RebirthCostGrowth = 7,
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
	TutorialEggTile = 12, -- guaranteed first egg on this tile cleared (must be <= 25)
	EggOwnerSeconds = 15,
	EggDespawnSeconds = 120,
	CarryLimit = 1,
	CarryLimitPass = 3,

	-- Products
	StarterPack = { Cash = 500, EggRarity = "Uncommon", Cash2xMinutes = 10 },
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
	SessionStaleSeconds = 30 * 60,
	FullMessageCooldown = 4,
}

return Economy
