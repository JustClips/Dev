--!strict
-- The upgrade tree (Slime RNG style): a honeycomb of hexagon nodes bought with cash at the
-- Upgrade Station (or from the HUD). It starts from one node in the middle; buying a node
-- (level 1+) opens its neighbours. The outer nodes need rebirths, so every rebirth reveals
-- more. "Lab" hexes on the main board open their own sub-trees (Trees below). Levels reset
-- on rebirth, like cash and tools.
--
-- Since the 2026-10-31 rebuild (Dev: "make exact replica of what Slime RNG has") every hex
-- is its own unlock with a few levels, and buying one reveals the hexes around it. A stat
-- can be raised by several hexes in different branches; their bonuses add up. (The tier
-- helpers below are still there: every hex is one tier now.)
--
-- Each node raises one stat (Stats below). Other services read stats through
-- Upgrades.multiplier / Upgrades.stat.
--
-- Hex = axial coordinates {q, r}; the window draws them flat-top like Slime RNG ({0,-1} is
-- straight up). A node's Parent must be a direct neighbour,
-- so every link in the tree is one short line. Cost of a level inside a tier =
-- BaseCost * CostGrowth ^ (levels already bought in that tier).
local Types = require(script.Parent.Parent.Types)

type UpgradeDef = Types.UpgradeDef
type UpgradeTier = Types.UpgradeTier

export type StatDef = {
	Name: string,
	Icon: string,
	Format: string, -- "percent" (+25%), "plus" (+4), "x" (+0.5x), "seconds" (+0.6s), "hours" (+1h)
}

-- What each stat does in the game (where it is applied).
local Stats: { [string]: StatDef } = {
	Power = { Name = "Leaves per Pile", Icon = "Icon_Tool_Broom", Format = "percent" }, -- ToolService: leaves from each pile, and tough piles take fewer swipes
	Backpack = { Name = "Backpack", Icon = "Icon_Backpack", Format = "percent" }, -- ToolService
	Speed = { Name = "Walk Speed", Icon = "Icon_Speed", Format = "plus" }, -- walkSpeed
	Luck = { Name = "Egg Luck", Icon = "Icon_Luck", Format = "percent" }, -- EggService
	DustValue = { Name = "Leaf Value", Icon = "Icon_Dust", Format = "percent" }, -- BackpackService
	Radius = { Name = "Sweep Size", Icon = "Icon_Tool_LeafBlower", Format = "percent" }, -- ToolService
	Cash = { Name = "All Cash", Icon = "Icon_Cash", Format = "percent" }, -- BoostService (+ coin magnet range, CoinService)
	PetIncome = { Name = "Pet Income", Icon = "Icon_Alien", Format = "percent" }, -- AlienService
	Offline = { Name = "Offline Cash", Icon = "Icon_Daily", Format = "percent" }, -- AlienService
	ComboTime = { Name = "Combo Time", Icon = "Icon_Timer", Format = "seconds" }, -- SweepService (pet passives only)
	Crit = { Name = "Lucky Sweep", Icon = "Icon_Star", Format = "percent" }, -- SweepService
	CritMult = { Name = "Lucky Payout", Icon = "Icon_Meteor", Format = "x" }, -- SweepService
	Golden = { Name = "Golden Piles", Icon = "Icon_Sell", Format = "percent" }, -- SweepService
	Bunny = { Name = "Bunny Rewards", Icon = "Icon_Gift", Format = "percent" }, -- EnemyService
	HatchSpeed = { Name = "Hatch Speed", Icon = "Icon_PotionHatch", Format = "percent" }, -- HatchService
	Incubators = { Name = "Eggs at Once", Icon = "Icon_Egg", Format = "plus" }, -- HatchService
	Portal = { Name = "Lab", Icon = "Icon_Upgrade", Format = "plus" }, -- opens a sub-tree
	-- Added 2026-10-30 with the remake (one hex each):
	DumpSpeed = { Name = "Dump Speed", Icon = "Icon_Sell", Format = "percent" }, -- BackpackService: the bag pours faster
	ItemFind = { Name = "Leaf Drops", Icon = "Icon_Gift", Format = "percent" }, -- SweepService: more items drop from leaves
	PotionTime = { Name = "Potion Time", Icon = "Icon_Timer", Format = "percent" }, -- InventoryService: boosts last longer
	MerchantDiscount = { Name = "Merchant Discount", Icon = "Icon_Merchant", Format = "percent" }, -- MerchantService
	MerchantSlots = { Name = "Merchant Items", Icon = "Icon_Merchant", Format = "plus" }, -- MerchantService
	Regrow = { Name = "Regrow Speed", Icon = "Icon_PotionLeaf", Format = "percent" }, -- DustService: your leaves grow back faster
	Huge = { Name = "Huge Chance", Icon = "Icon_HugeCharm", Format = "percent" }, -- HatchService
	MutChance = { Name = "Mutation Chance", Icon = "Icon_MutationSpray", Format = "percent" }, -- HatchService: Golden/Rainbow/Sparkly
	WeatherMut = { Name = "Weather Mutations", Icon = "Icon_Weather_Rain", Format = "percent" }, -- WeatherService: growing eggs
	EggFind = { Name = "Eggs Found", Icon = "Icon_Egg", Format = "percent" }, -- EggService: eggs in the leaves
	BunnyReach = { Name = "Bunny Reach", Icon = "Icon_Gift", Format = "percent" }, -- EnemyService
	PetSell = { Name = "Pet Sell Price", Icon = "Icon_Cash", Format = "percent" }, -- InventoryService
	PassivePower = { Name = "Pet Passives", Icon = "Icon_Alien", Format = "percent" }, -- PetPassives
	OfflineCap = { Name = "Offline Time", Icon = "Icon_Daily", Format = "hours" }, -- AlienService
	-- Pet combat (2026-10-31): nothing raises these yet; hexes or pet passives can.
	PetDamage = { Name = "Pet Damage", Icon = "Icon_Alien", Format = "percent" }, -- shared/Combat
	PetHealth = { Name = "Pet Health", Icon = "Icon_Alien", Format = "percent" }, -- shared/Combat
}

-- A lucky sweep pays this many times a normal tile (plus CritMult from the tree).
local CRIT_BASE_MULT = 5

-- One tier of a hex: name, description, levels, bonus per level, first price, price growth,
-- rebirths needed.
local function tier(
	name: string,
	desc: string,
	levels: number,
	perLevel: number,
	baseCost: number,
	growth: number,
	rebirths: number?
): UpgradeTier
	return {
		Name = name,
		Description = desc,
		Levels = levels,
		PerLevel = perLevel,
		BaseCost = baseCost,
		CostGrowth = growth,
		RequiredRebirths = rebirths or 0,
		First = 0,
	}
end

-- An evolving hex (several tiers).
local function t(id: string, q: number, r: number, parent: string?, stat: string, tiers: { UpgradeTier }): UpgradeDef
	local first = 0
	for _, tr in tiers do
		tr.First = first
		first += tr.Levels
	end
	local one = tiers[1]
	return {
		Id = id,
		Tree = "Main",
		Hex = { q = q, r = r },
		Parent = parent,
		Stat = stat,
		Name = one.Name,
		Description = one.Description,
		Icon = Stats[stat].Icon,
		Format = Stats[stat].Format,
		MaxLevel = first,
		PerLevel = one.PerLevel,
		BaseCost = one.BaseCost,
		CostGrowth = one.CostGrowth,
		RequiredRebirths = one.RequiredRebirths,
		Tiers = tiers,
	}
end

-- A simple hex (one tier).
local function n(
	id: string,
	q: number,
	r: number,
	parent: string?,
	stat: string,
	name: string,
	desc: string,
	maxLevel: number,
	perLevel: number,
	baseCost: number,
	growth: number,
	rebirths: number?
): UpgradeDef
	return t(id, q, r, parent, stat, { tier(name, desc, maxLevel, perLevel, baseCost, growth, rebirths) })
end

-- Sub-trees (Slime RNG style): a "Lab" hex costs cash once, then tapping it opens that
-- lab's own honeycomb (its hexes fly out from the middle). Each sub-tree starts from its Root.
export type TreeDef = { Id: string, Name: string, Root: string, Portal: string? }
local Trees: { [string]: TreeDef } = {
	Main = { Id = "Main", Name = "Upgrades", Root = "Power" },
	Eggs = { Id = "Eggs", Name = "Egg Lab", Root = "Luck", Portal = "EggLab" },
	Lucky = { Id = "Lucky", Name = "Lucky Lab", Root = "Golden", Portal = "LuckyLab" },
	Pets = { Id = "Pets", Name = "Pet Lab", Root = "PetIncome", Portal = "PetLab" },
}

local function lab(
	id: string,
	q: number,
	r: number,
	parent: string,
	tree: string,
	name: string,
	desc: string,
	icon: string,
	cost: number
): UpgradeDef
	local def = n(id, q, r, parent, "Portal", name, desc, 1, 0, cost, 1)
	def.Opens = tree
	def.Icon = icon
	return def
end

local function inTree(tree: string, defs: { UpgradeDef }): { UpgradeDef }
	for _, def in defs do
		def.Tree = tree
	end
	return defs
end

-- Every hex is its own thing with a few levels (Slime RNG style, Dev 2026-10-31: "instead
-- of upgrading the same stuff 3-4 tiers"). Buying a hex opens the hexes next to it, and the
-- outer ones need rebirths. A stat can be raised by a few hexes in different branches.
-- A sub-tree's root has no Parent: it needs its lab instead.
-- n(id, q, r, parent, stat, name, description, levels, per level, first price, price growth, rebirths)
-- stylua: ignore
local Main = {
	n("Power",          0,  0, nil,           "Power",            "Sweep Power",     "Every pile gives more leaves",                 5, 0.25, 150,             1.9),
	-- ring 1
	n("Backpack",       0, -1, "Power",       "Backpack",         "Backpack",        "Carry more leaves per trip",                   5, 0.30, 300,             2.2),
	n("Speed",         -1,  1, "Power",       "Speed",            "Running Shoes",   "Walk faster",                                  5, 2,    400,             2.0),
	n("LeafValue",      1,  0, "Power",       "DustValue",        "Leaf Value",      "Every leaf sells for more",                    5, 0.15, 800,             2.2),
	lab("PetLab",       0,  1, "Power",  "Pets",  "Pet Lab",   "Pet income, pet fights and offline cash",     "Icon_Alien", 1_500),
	n("WorkGloves",     1, -1, "Backpack",    "Power",            "Work Gloves",     "Grab more leaves from every pile",             5, 0.25, 3_000,           2.0),
	n("QuickDump",     -1,  0, "Backpack",    "DumpSpeed",        "Quick Dump",      "Your bag pours into the dump faster",          5, 0.20, 5_000,           8.1),
	-- ring 2+
	lab("EggLab",       1, -2, "WorkGloves", "Eggs",  "Egg Lab",   "Egg luck, Huge pets, mutations and hatching", "Icon_Egg",   2_000),
	lab("LuckyLab",    -1, -1, "QuickDump",  "Lucky", "Lucky Lab", "Lucky sweeps, golden piles and bunnies",      "Icon_Star",  5_000),
	n("BigPockets",     0, -2, "Backpack",    "Backpack",         "Big Pockets",     "Even more room in your bag",                   5, 0.30, 8_000,           4.9),
	n("GiantSack",     -1, -2, "BigPockets",  "Backpack",         "Giant Sack",      "Carry a huge sack of leaves",                  5, 0.40, 150_000,         5.3),
	n("LeafTruck",      0, -3, "BigPockets",  "Backpack",         "Leaf Truck",      "Carry way more leaves",                        5, 0.40, 3_000_000_000,   4.9, 1),
	n("LeafTrailer",   -1, -3, "GiantSack",   "Backpack",         "Leaf Trailer",    "Hook a whole trailer of leaves to your bag",   5, 0.20, 60_000_000_000,  4.9, 2),
	n("WideSweep",      2, -1, "WorkGloves",  "Radius",           "Wide Sweep",      "Sweep a bigger area at once",                  5, 0.05, 25_000,          6.1),
	n("IronGrip",       2, -2, "WorkGloves",  "Power",            "Iron Grip",       "Tough piles break in fewer swipes",            5, 0.30, 40_000,          5.7),
	n("MegaSweep",      3, -2, "WideSweep",   "Radius",           "Mega Sweep",      "Sweep an even bigger area",                    5, 0.05, 3_000_000_000,   6.1, 1),
	n("Tornado",        4, -3, "MegaSweep",   "Radius",           "Tornado",         "Sweep a huge area at once",                    5, 0.06, 200_000_000_000, 7.1, 3),
	n("MuscleUp",       3, -3, "IronGrip",    "Power",            "Muscle Up",       "Much more leaves from every pile",             5, 0.40, 2_000_000_000,   4.9, 1),
	n("TitanStrength",  2, -3, "IronGrip",    "Power",            "Titan Strength",  "Huge leaf hauls from every pile",              5, 0.60, 30_000_000_000,  4.9, 2),
	n("LuckyFinds",    -2,  1, "Speed",       "ItemFind",         "Lucky Finds",     "Items drop from the leaves more often",        5, 0.05, 3_000,           2.8),
	n("LongBrew",      -2,  2, "Speed",       "PotionTime",       "Long Brew",       "Potions last longer",                          5, 0.10, 8_000,           8.1),
	n("SpringShoes",   -2,  0, "QuickDump",   "Speed",            "Spring Shoes",    "Bounce along even faster",                     3, 2,    200_000,         5.7),
	n("TreasureHunter",-3,  1, "LuckyFinds",  "ItemFind",         "Treasure Hunter", "Items drop from the leaves way more often",    5, 0.05, 4_000_000_000,   7.1, 1),
	n("RocketShoes",   -3,  2, "LuckyFinds",  "Speed",            "Rocket Shoes",    "Zoom around with rocket power",                5, 2,    3_000_000_000,   5.7, 1),
	n("MoneyMagnet",    2,  0, "LeafValue",   "Cash",             "Money Magnet",    "Grab coins from further away, plus more cash", 5, 0.10, 50_000,          5.7),
	n("FancyLeaves",    1,  1, "LeafValue",   "DustValue",        "Fancy Leaves",    "Every leaf sells for even more",               5, 0.30, 60_000,          5.3),
	n("Haggler",        2,  1, "MoneyMagnet", "MerchantDiscount", "Haggler",         "The Traveling Merchant gives you a discount",  4, 0.05, 100_000,         8.1),
	n("BiggerCart",     3,  0, "Haggler",     "MerchantSlots",    "Bigger Cart",     "The Traveling Merchant shows one more item",   2, 1,    5_000_000_000,   20, 1),
	n("RichSweeper",    3, -1, "MoneyMagnet", "Cash",             "Rich Sweeper",    "Bigger coin magnet, plus more cash",           5, 0.10, 5_000_000_000,   5.7, 1),
	n("GoldenBroom",    4, -2, "RichSweeper", "Cash",             "Golden Broom",    "Huge coin magnet, plus more cash",             5, 0.10, 250_000_000_000, 5.7, 3),
	n("Fertilizer",     1,  2, "FancyLeaves", "Regrow",           "Fertilizer",      "Your leaves grow back faster",                 4, 0.03, 3_000_000_000,   8.1, 1),
	n("DiamondLeaves",  0,  2, "FancyLeaves", "DustValue",        "Diamond Leaves",  "Every leaf sells for way more",                5, 0.45, 45_000_000_000,  5.3, 2),
}

-- stylua: ignore
local Eggs = inTree("Eggs", {
	n("Luck",           0,  0, nil,           "Luck",       "Egg Luck",         "Find more and rarer eggs",                     5, 0.10, 1_000,           2.5),
	n("HatchSpeed",     0, -1, "Luck",        "HatchSpeed", "Quick Hatch",      "Eggs grow faster",                             5, 0.10, 30_000,          6.6),
	n("EggSniffer",     1,  0, "Luck",        "EggFind",    "Egg Sniffer",      "Find eggs in the leaves more often",           5, 0.05, 15_000,          7.1),
	n("HugeHunter",     1, -1, "Luck",        "Huge",       "Huge Hunter",      "Pets hatch Huge more often",                   5, 0.20, 50_000,          8.1),
	n("Incubator",     -1,  0, "Luck",        "Incubators", "Bigger Nest",      "Grow one more egg at once",                    1, 1,    150_000,         1),
	n("LuckyCharm",     0,  1, "Luck",        "Luck",       "Lucky Charm",      "Find even rarer eggs",                         5, 0.10, 400_000,         5.7),
	n("StormChaser",   -1,  1, "Luck",        "WeatherMut", "Storm Chaser",     "Weather mutates your growing eggs more often", 5, 0.20, 80_000,          7.1),
	n("HatchHurry",     0, -2, "HatchSpeed",  "HatchSpeed", "Hatch Hurry",      "Eggs grow even faster",                        5, 0.10, 5_000_000_000,   6.6, 1),
	n("ShinyHunter",    2, -2, "HugeHunter",  "MutChance",  "Shiny Hunter",     "Golden, Rainbow and Sparkly pets more often",  5, 0.20, 3_000_000_000,   7.1, 1),
	n("HugeMagnet",     1, -2, "HugeHunter",  "Huge",       "Huge Magnet",      "Pets hatch Huge way more often",               5, 0.20, 8_000_000_000,   7.1, 2),
	n("EggRadar",       2, -1, "EggSniffer",  "EggFind",    "Egg Radar",        "Find eggs in the leaves way more often",       5, 0.05, 4_000_000_000,   7.1, 1),
	n("EggNursery",    -2,  0, "Incubator",   "Incubators", "Egg Nursery",      "Grow another egg at once",                     1, 1,    25_000_000_000,  1,   1),
	n("FourLeaf",       0,  2, "LuckyCharm",  "Luck",       "Four-Leaf Clover", "Find way rarer eggs",                          5, 0.10, 2_500_000_000,   6.1, 1),
	n("RainbowLuck",    1,  1, "LuckyCharm",  "Luck",       "Rainbow Luck",     "Rainbow-level egg luck",                       5, 0.10, 6_000_000_000,   7.1, 2),
	n("Horseshoe",      0,  3, "FourLeaf",    "Luck",       "Golden Horseshoe", "The best egg luck there is",                   5, 0.10, 250_000_000_000, 8.1, 3),
})

-- stylua: ignore
local Lucky = inTree("Lucky", {
	n("Golden",         0,  0, nil,           "Golden",     "Golden Touch",     "Golden piles pay more",                        5, 0.20, 40_000,          7.1),
	n("Crit",           0, -1, "Golden",      "Crit",       "Lucky Sweep",      "Chance a leaf pays 5x",                        5, 0.01, 50_000,          7.1),
	n("Bunny",          1,  0, "Golden",      "Bunny",      "Bunny Hunter",     "Dust bunnies drop more cash",                  5, 0.25, 20_000,          5.7),
	n("LuckyPaw",      -1,  1, "Golden",      "Crit",       "Lucky Paw",        "A few more lucky leaves",                      3, 0.01, 600_000,         7.1),
	n("GoldDigger",     0,  1, "Golden",      "Golden",     "Gold Digger",      "Golden piles pay a bit more",                  3, 0.15, 500_000,         6.1),
	n("BunnyNet",       2, -1, "Bunny",       "BunnyReach", "Bunny Net",        "Catch dust bunnies from further away",         4, 0.25, 60_000,          7.1),
	n("GoldRush",      -1,  0, "Golden",      "Golden",     "Gold Rush",        "Golden piles pay even more",                   5, 0.25, 4_000_000_000,   6.6, 1),
	n("LuckyStreak",    0, -2, "Crit",        "Crit",       "Lucky Streak",     "Even more lucky leaves",                       5, 0.01, 4_000_000_000,   7.1, 1),
	n("Jackpot",        1, -1, "Crit",        "CritMult",   "Jackpot",          "Lucky sweeps pay more",                        5, 1,    5_000_000_000,   6.6, 1),
	n("BunnyBoss",      2,  0, "Bunny",       "Bunny",      "Bunny Boss",       "Dust bunnies drop way more cash",              5, 0.50, 2_000_000_000,   5.7, 1),
	n("Midas",         -2,  0, "GoldRush",    "Golden",     "Midas",            "Golden piles pay way more",                    5, 0.50, 45_000_000_000,  7.1, 2),
	n("MegaJackpot",    1, -2, "Jackpot",     "CritMult",   "Mega Jackpot",     "Lucky sweeps pay way more",                    3, 2,    150_000_000_000, 8.1, 3),
})

-- stylua: ignore
local Pets = inTree("Pets", {
	n("PetIncome",      0,  0, nil,           "PetIncome",    "Happy Pets",     "Pets in your park earn more",                  5, 0.20, 1_500,           2.3),
	n("PetTreats",      0, -1, "PetIncome",   "PetIncome",    "Pet Treats",     "Pets in your park earn even more",             5, 0.30, 30_000,          5.3),
	n("Offline",        1,  0, "PetIncome",   "Offline",      "Night Shift",    "Earn more while you're away",                  5, 0.20, 25_000,          5.7),
	n("GoodDeals",     -1,  1, "PetIncome",   "PetSell",      "Good Deals",     "The Pet Trader pays more for your pets",       5, 0.15, 10_000,          6.1),
	n("SharpClaws",    -1,  0, "PetIncome",   "PetDamage",    "Sharp Claws",    "Your pets hit harder",                         5, 0.20, 8_000,           5.7),
	n("ThickFur",       0,  1, "PetIncome",   "PetHealth",    "Thick Fur",      "Your pets can take more hits",                 5, 0.20, 8_000,           5.7),
	n("BestFriends",    1, -1, "PetTreats",   "PassivePower", "Best Friends",   "Your pets' passive powers get stronger",       5, 0.06, 500_000,         7.1),
	n("PetParty",       0, -2, "PetTreats",   "PetIncome",    "Pet Party",      "Pets in your park earn a lot more",            5, 0.40, 4_000_000_000,   5.3, 1),
	n("PetParadise",    0, -3, "PetParty",    "PetIncome",    "Pet Paradise",   "Pets in your park earn way more",              5, 0.50, 60_000_000_000,  5.3, 2),
	n("SleepPay",       2, -1, "Offline",     "Offline",      "Sleep Pay",      "Earn even more while you're away",             5, 0.25, 3_000_000_000,   5.7, 1),
	n("LongNap",        2,  0, "Offline",     "OfflineCap",   "Long Nap",       "Earn offline for longer",                      4, 0.5,  2_000_000_000,   5.7, 1),
	n("BattleTraining",-2,  0, "SharpClaws",  "PetDamage",    "Battle Training","Your pets hit way harder",                     5, 0.30, 3_000_000_000,   5.7, 1),
	n("PetArmor",      -1,  2, "ThickFur",    "PetHealth",    "Pet Armor",      "Your pets can take way more hits",             5, 0.30, 3_000_000_000,   5.7, 1),
})

-- Hex pictures: the stat's icon unless a hex has its own here (hand-drawn sticker icons,
-- art/flat_icons.py). A name that isn't uploaded yet falls back to the stat's icon.
-- stylua: ignore
local Icons: { [string]: string } = {
	WorkGloves = "Icon_UpGloves", IronGrip = "Icon_UpGloves", MuscleUp = "Icon_UpDumbbell", TitanStrength = "Icon_UpDumbbell",
	BigPockets = "Icon_UpSack", GiantSack = "Icon_UpSack", LeafTruck = "Icon_Car_DustTruck", LeafTrailer = "Icon_Car_DustTruck",
	Tornado = "Icon_Tool_TornadoVac", MoneyMagnet = "Icon_UpMagnet", RichSweeper = "Icon_UpMagnet",
	GoldenBroom = "Icon_Tool_GoldenBroom", Fertilizer = "Icon_UpSprout", FancyLeaves = "Icon_UpGem", DiamondLeaves = "Icon_UpGem",
	LuckyFinds = "Icon_UpMagnifier", TreasureHunter = "Icon_TreasureMap", LongBrew = "Icon_Potion", SpringShoes = "Icon_Speed",
	EggSniffer = "Icon_UpMagnifier", EggRadar = "Icon_UpMagnifier", Incubator = "Icon_UpNest", EggNursery = "Icon_UpNest",
	LuckyCharm = "Icon_LuckyClover", FourLeaf = "Icon_LuckyClover", RainbowLuck = "Icon_Weather_Rainbow", Horseshoe = "Icon_UpHorseshoe",
	HugeMagnet = "Icon_HugeCharm", StormChaser = "Icon_Weather_Thunderstorm", HatchHurry = "Icon_PotionHatch",
	LuckyPaw = "Icon_LuckyCat", GoldDigger = "Icon_UpGem", MegaJackpot = "Icon_Cash", Jackpot = "Icon_Cash",
	PetIncome = "Icon_UpHeart", PetTreats = "Icon_UpBone", PetParty = "Icon_UpBone", PetParadise = "Icon_UpHeart",
	BestFriends = "Icon_UpHeart", Offline = "Icon_UpMoon", SleepPay = "Icon_UpMoon", LongNap = "Icon_UpMoon",
	SharpClaws = "Icon_Sword", BattleTraining = "Icon_Sword", ThickFur = "Icon_UpShield", PetArmor = "Icon_UpShield",
}

-- Hexes removed in the 2026-10-30 remake: their levels are refunded (what they cost) the
-- next time the player loads in (UpgradeService). BaseCost and CostGrowth as they were.
-- stylua: ignore
export type RetiredDef = {
	BaseCost: number,
	CostGrowth: number,
	-- Evolving hexes: each tier's levels, first price and growth (BaseCost is ignored).
	Tiers: { { Levels: number, BaseCost: number, CostGrowth: number } }?,
}
local Retired: { [string]: RetiredDef } = {
	Backpack2 = { BaseCost = 30_000, CostGrowth = 2.3 },
	Backpack3 = { BaseCost = 3_000_000_000, CostGrowth = 2.3 },
	Radius2 = { BaseCost = 3_000_000_000, CostGrowth = 2.6 },
	Radius3 = { BaseCost = 200_000_000_000, CostGrowth = 2.8 },
	Cash2 = { BaseCost = 5_000_000_000, CostGrowth = 2.5 },
	Cash3 = { BaseCost = 250_000_000_000, CostGrowth = 2.5 },
	LeafValue2 = { BaseCost = 60_000, CostGrowth = 2.4 },
	LeafValue3 = { BaseCost = 45_000_000_000, CostGrowth = 2.4 },
	Power2 = { BaseCost = 20_000, CostGrowth = 2.3 },
	Power3 = { BaseCost = 2_000_000_000, CostGrowth = 2.3 },
	Power4 = { BaseCost = 30_000_000_000, CostGrowth = 2.3 },
	Speed2 = { BaseCost = 3_000_000_000, CostGrowth = 2.5 },
	Luck2 = { BaseCost = 2_500_000_000, CostGrowth = 2.4 },
	Luck3 = { BaseCost = 6_000_000_000, CostGrowth = 2.8 },
	Luck4 = { BaseCost = 250_000_000_000, CostGrowth = 3.0 },
	HatchSpeed2 = { BaseCost = 5_000_000_000, CostGrowth = 2.7 },
	Bunny2 = { BaseCost = 2_000_000_000, CostGrowth = 2.5 },
	Incubator2 = { BaseCost = 25_000_000_000, CostGrowth = 1 },
	Combo2 = { BaseCost = 3_000_000_000, CostGrowth = 3.0 },
	ComboTime2 = { BaseCost = 3_500_000_000, CostGrowth = 2.6 },
	Golden2 = { BaseCost = 4_000_000_000, CostGrowth = 2.7 },
	Golden3 = { BaseCost = 45_000_000_000, CostGrowth = 2.8 },
	Crit2 = { BaseCost = 4_000_000_000, CostGrowth = 2.8 },
	Combo3 = { BaseCost = 300_000_000_000, CostGrowth = 4.0 },
	CritMult2 = { BaseCost = 150_000_000_000, CostGrowth = 3.0 },
	PetIncome2 = { BaseCost = 60_000, CostGrowth = 2.4 },
	PetIncome3 = { BaseCost = 4_000_000_000, CostGrowth = 2.4 },
	PetIncome4 = { BaseCost = 60_000_000_000, CostGrowth = 2.4 },
	Offline2 = { BaseCost = 3_000_000_000, CostGrowth = 2.5 },
	-- The combo hexes (2026-10-31: the combo has no cap or upgrades any more).
	Combo = {
		BaseCost = 2_000,
		CostGrowth = 3.0,
		Tiers = {
			{ Levels = 4, BaseCost = 2_000, CostGrowth = 3.0 },
			{ Levels = 4, BaseCost = 3_000_000_000, CostGrowth = 3.0 },
			{ Levels = 2, BaseCost = 300_000_000_000, CostGrowth = 4.0 },
		},
	},
	ComboTime = {
		BaseCost = 35_000,
		CostGrowth = 2.6,
		Tiers = {
			{ Levels = 5, BaseCost = 35_000, CostGrowth = 2.6 },
			{ Levels = 5, BaseCost = 3_500_000_000, CostGrowth = 2.6 },
		},
	},
	SecondWind = { BaseCost = 20_000, CostGrowth = 2.8 },
	GoldenCombo = { BaseCost = 3_000_000_000, CostGrowth = 3.0 },
}

-- The tree before the 2026-10-31 rebuild (one evolving hex per stat). Saves from before
-- the rebuild (Flags.UpgradeTreeV < Version) get back what they paid for these levels and
-- start the new tree fresh (UpgradeService). Per hex: { levels, first price, growth } per tier.
-- stylua: ignore
local OldTree: { [string]: { { number } } } = {
	Power = { { 10, 150, 1.9 }, { 10, 20_000, 2.3 }, { 10, 2_000_000_000, 2.3 }, { 10, 30_000_000_000, 2.3 } },
	Backpack = { { 10, 300, 2.2 }, { 10, 30_000, 2.3 }, { 10, 3_000_000_000, 2.3 } },
	LeafValue = { { 10, 800, 2.2 }, { 10, 60_000, 2.4 }, { 10, 45_000_000_000, 2.4 } },
	Speed = { { 8, 400, 2 }, { 5, 3_000_000_000, 2.5 } },
	EggLab = { { 1, 2_000, 1 } },
	LuckyLab = { { 1, 5_000, 1 } },
	PetLab = { { 1, 1_500, 1 } },
	Radius = { { 5, 25_000, 2.6 }, { 5, 3_000_000_000, 2.6 }, { 5, 200_000_000_000, 2.8 } },
	Cash = { { 10, 50_000, 2.5 }, { 10, 5_000_000_000, 2.5 }, { 10, 250_000_000_000, 2.5 } },
	QuickDump = { { 5, 5_000, 3 } },
	LuckyFinds = { { 5, 3_000, 2.8 }, { 5, 4_000_000_000, 2.8 } },
	LongBrew = { { 5, 8_000, 3 } },
	Fertilizer = { { 4, 3_000_000_000, 3 } },
	Haggler = { { 4, 100_000, 3 } },
	BiggerCart = { { 2, 5_000_000_000, 20 } },
	Luck = { { 10, 1_000, 2.5 }, { 10, 2_500_000_000, 2.4 }, { 5, 6_000_000_000, 2.8 }, { 5, 250_000_000_000, 3 } },
	HatchSpeed = { { 5, 30_000, 2.7 }, { 5, 5_000_000_000, 2.7 } },
	Bunny = { { 5, 20_000, 2.5 }, { 5, 2_000_000_000, 2.5 } },
	Incubator = { { 1, 150_000, 1 }, { 1, 25_000_000_000, 1 } },
	HugeHunter = { { 5, 50_000, 3 } },
	EggSniffer = { { 5, 15_000, 2.8 } },
	StormChaser = { { 5, 80_000, 2.8 } },
	ShinyHunter = { { 5, 3_000_000_000, 2.8 } },
	Golden = { { 5, 40_000, 2.8 }, { 5, 4_000_000_000, 2.7 }, { 5, 45_000_000_000, 2.8 } },
	Crit = { { 5, 50_000, 2.8 }, { 5, 4_000_000_000, 2.8 } },
	CritMult = { { 5, 5_000_000_000, 2.7 }, { 3, 150_000_000_000, 3 } },
	BunnyNet = { { 4, 60_000, 2.8 } },
	PetIncome = { { 10, 1_500, 2.3 }, { 10, 60_000, 2.4 }, { 10, 4_000_000_000, 2.4 }, { 10, 60_000_000_000, 2.4 } },
	Offline = { { 5, 25_000, 2.5 }, { 5, 3_000_000_000, 2.5 } },
	GoodDeals = { { 5, 10_000, 2.6 } },
	BestFriends = { { 5, 500_000, 2.8 } },
	LongNap = { { 4, 2_000_000_000, 2.5 } },
}

local List: { UpgradeDef } = {}
for _, group in { Main, Eggs, Lucky, Pets } do
	for _, def in group do
		table.insert(List, def)
	end
end

local Upgrades = {
	-- Extra stat bonuses for a player's levels table (pet passives). Set by the server.
	extra = nil :: ((levels: { [string]: number }) -> { [string]: number }?)?,
	List = List,
	ById = {} :: { [string]: UpgradeDef },
	Stats = Stats,
	Trees = Trees,
	Retired = Retired,
	OldTree = OldTree,
	-- Bump when the tree is rebuilt: older saves are refunded (OldTree) and start fresh.
	Version = 3,
	-- Children of each node (drawn as links, opened when the node is bought).
	Children = {} :: { [string]: { UpgradeDef } },
	-- Nodes that raise each stat.
	ByStat = {} :: { [string]: { UpgradeDef } },
	Root = "Power",
	BaseWalkSpeed = 16,
	CritBaseMult = CRIT_BASE_MULT,
}

for _, def in List do
	def.Icon = Icons[def.Id] or def.Icon
	assert(not Upgrades.ById[def.Id], `duplicate upgrade {def.Id}`)
	assert(not Retired[def.Id], `{def.Id} is both live and retired`)
	assert(Trees[def.Tree], `{def.Id}: unknown tree {def.Tree}`)
	assert(Stats[def.Stat], `{def.Id}: unknown stat {def.Stat}`)
	Upgrades.ById[def.Id] = def
	Upgrades.Children[def.Id] = {}
	Upgrades.ByStat[def.Stat] = Upgrades.ByStat[def.Stat] or {}
	table.insert(Upgrades.ByStat[def.Stat], def)
end
local taken: { [string]: string } = {}
for _, def in List do
	-- Two hexes can't sit on the same spot of a board.
	local spot = `{def.Tree} {def.Hex.q},{def.Hex.r}`
	assert(not taken[spot], `{def.Id} sits on {taken[spot]}`)
	taken[spot] = def.Id
	if def.Parent then
		local parent = Upgrades.ById[def.Parent]
		assert(parent, `{def.Id}: unknown parent {def.Parent}`)
		assert(parent.Tree == def.Tree, `{def.Id}: parent {def.Parent} is in another tree`)
		-- Neighbours in axial coordinates differ by one of the six directions.
		local dq, dr = def.Hex.q - parent.Hex.q, def.Hex.r - parent.Hex.r
		assert(math.max(math.abs(dq), math.abs(dr), math.abs(dq + dr)) == 1, `{def.Id} is not next to {def.Parent}`)
		table.insert(Upgrades.Children[def.Parent], def)
	end
end

-- The tier that holds level `level` (1-based; 0 counts as the first tier). Returns the
-- tier and its index.
function Upgrades.tierFor(def: UpgradeDef, level: number): (UpgradeTier, number)
	for i, tr in def.Tiers do
		if level <= tr.First + tr.Levels then
			return tr, i
		end
	end
	return def.Tiers[#def.Tiers], #def.Tiers
end

-- The tier the hex shows now: the one the next level is in (the last one when maxed).
function Upgrades.currentTier(def: UpgradeDef, level: number): (UpgradeTier, number)
	return Upgrades.tierFor(def, math.min(level + 1, def.MaxLevel))
end

-- Name and description the hex shows at a level (it evolves as tiers are maxed).
function Upgrades.name(def: UpgradeDef, level: number): string
	return (Upgrades.currentTier(def, level)).Name
end

function Upgrades.description(def: UpgradeDef, level: number): string
	return (Upgrades.currentTier(def, level)).Description
end

-- Rebirths needed for the next level.
function Upgrades.requiredRebirths(def: UpgradeDef, level: number): number
	return (Upgrades.currentTier(def, level)).RequiredRebirths
end

-- Price of going from `level` to `level + 1`.
function Upgrades.cost(def: UpgradeDef, level: number): number
	local tr = Upgrades.tierFor(def, level + 1)
	return math.floor(tr.BaseCost * tr.CostGrowth ^ math.max(0, level - tr.First))
end

-- Total price of the next `count` levels from `level`.
function Upgrades.costFor(def: UpgradeDef, level: number, count: number): number
	local total = 0
	for i = 0, count - 1 do
		total += Upgrades.cost(def, level + i)
	end
	return total
end

-- The bonus a node gives at a level (every tier's levels add up).
function Upgrades.bonus(def: UpgradeDef, level: number): number
	local total = 0
	for _, tr in def.Tiers do
		total += tr.PerLevel * math.clamp(level - tr.First, 0, tr.Levels)
	end
	return total
end

-- What `level` levels of a hex from the tree before the 2026-10-31 rebuild cost.
function Upgrades.oldTreeRefund(id: string, level: number): number
	local tiers = OldTree[id]
	if not tiers then
		return 0
	end
	local total, first = 0, 0
	for _, tr in tiers do
		for i = 0, math.min(level - first, tr[1]) - 1 do
			total += math.floor(tr[2] * tr[3] ^ i)
		end
		first += tr[1]
	end
	return total
end

-- What a retired hex's levels cost (refund).
function Upgrades.retiredRefund(id: string, level: number): number
	local old = Retired[id]
	if not old then
		return 0
	end
	local total = 0
	if old.Tiers then
		local first = 0
		for _, tr in old.Tiers do
			for i = 0, math.min(level - first, tr.Levels) - 1 do
				total += math.floor(tr.BaseCost * tr.CostGrowth ^ i)
			end
			first += tr.Levels
		end
		return total
	end
	for i = 0, level - 1 do
		total += math.floor(old.BaseCost * old.CostGrowth ^ i)
	end
	return total
end

local function formatValue(format: string, b: number): string
	if format == "percent" then
		local pct = b * 100
		if pct < 10 and pct ~= math.floor(pct) then
			return `+{math.floor(pct * 10 + 0.5) / 10}%`
		end
		return `+{math.floor(pct + 0.5)}%`
	elseif format == "x" then
		return `+{math.floor(b * 100 + 0.5) / 100}x`
	elseif format == "seconds" then
		return `+{math.floor(b * 10 + 0.5) / 10}s`
	elseif format == "hours" then
		return `+{math.floor(b * 10 + 0.5) / 10}h`
	end
	return `+{b}`
end

-- Short text for a node's bonus at a level, e.g. "+50%", "+4", "+0.5x".
function Upgrades.describe(def: UpgradeDef, level: number): string
	return formatValue(def.Format, Upgrades.bonus(def, level))
end

-- Short text for a whole stat, e.g. "+75%".
function Upgrades.describeStat(stat: string, value: number): string
	return formatValue(Stats[stat].Format, value)
end

-- Sum of the tree's bonuses for a stat (no pet passives).
function Upgrades.treeStat(levels: { [string]: number }?, stat: string): number
	if not levels then
		return 0
	end
	local total = 0
	for _, def in Upgrades.ByStat[stat] or {} do
		local level = levels[def.Id]
		if level and level > 0 then
			total += Upgrades.bonus(def, level)
		end
	end
	return total
end

-- Sum of all bonuses for a stat from a player's levels (missing levels count as 0), plus
-- their pets' passives.
function Upgrades.stat(levels: { [string]: number }?, stat: string): number
	if not levels then
		return 0
	end
	local total = Upgrades.treeStat(levels, stat)
	-- Pet passives (shared/PetPassives) add to the same stats; the server sets this hook.
	local extra = Upgrades.extra
	if extra then
		local bonus = extra(levels)
		if bonus and bonus[stat] then
			total += bonus[stat]
		end
	end
	return total
end

-- 1 + the stat (for percent stats).
function Upgrades.multiplier(levels: { [string]: number }?, stat: string): number
	return 1 + Upgrades.stat(levels, stat)
end

function Upgrades.walkSpeed(levels: { [string]: number }?): number
	return Upgrades.BaseWalkSpeed + Upgrades.stat(levels, "Speed")
end

-- The node that must be bought first: its parent, or for a sub-tree's root, the lab.
function Upgrades.requires(def: UpgradeDef): string?
	if def.Parent then
		return def.Parent
	end
	return Trees[def.Tree].Portal
end

-- Why a node can't be bought right now (nil = it can). Doesn't check cash.
function Upgrades.blocked(def: UpgradeDef, levels: { [string]: number }, rebirths: number): string?
	local level = levels[def.Id] or 0
	if level >= def.MaxLevel then
		return "Maxed"
	end
	local need = Upgrades.requires(def)
	if need and (levels[need] or 0) < 1 then
		return `Buy {Upgrades.ById[need].Name} first`
	end
	local tr = Upgrades.tierFor(def, level + 1)
	if rebirths < tr.RequiredRebirths then
		if level > 0 and level == tr.First then
			return `Evolves into {tr.Name} at Rebirth {tr.RequiredRebirths}`
		end
		return `Needs Rebirth {tr.RequiredRebirths}`
	end
	return nil
end

return Upgrades
