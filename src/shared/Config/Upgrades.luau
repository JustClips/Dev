--!strict
-- The upgrade tree (Slime RNG style): a honeycomb of hexagon nodes bought with cash at the
-- Upgrade Station (or from the HUD). It starts from one node in the middle; buying a node
-- (level 1+) opens its neighbours. The outer nodes need rebirths, so every rebirth reveals
-- more. "Lab" hexes on the main board open their own sub-trees (Trees below). Levels reset
-- on rebirth, like cash and tools.
--
-- Every hex does something different (Dev, 2026-10-30: the old tree repeated the same
-- upgrade over and over, like Sweep Power, Strong Arms, Mighty Sweep, Titan Sweep). A
-- stat that grows a long way is ONE evolving hex instead: its tiers (t() below) each have
-- their own name and prices, and maxing a tier evolves the hex into the next one. Later
-- tiers need rebirths, so the hex keeps growing as you rebirth.
--
-- Each node raises one stat (Stats below). Other services read stats through
-- Upgrades.multiplier / Upgrades.stat.
--
-- Hex = axial coordinates {q, r} (pointy-top). A node's Parent must be a direct neighbour,
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
	Bunny = { Name = "Bunny Rewards", Icon = "Icon_Gift", Format = "percent" }, -- DustBunnyService
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
	BunnyReach = { Name = "Bunny Reach", Icon = "Icon_Gift", Format = "percent" }, -- DustBunnyService
	PetSell = { Name = "Pet Sell Price", Icon = "Icon_Cash", Format = "percent" }, -- InventoryService
	PassivePower = { Name = "Pet Passives", Icon = "Icon_Alien", Format = "percent" }, -- PetPassives
	OfflineCap = { Name = "Offline Time", Icon = "Icon_Daily", Format = "hours" }, -- AlienService
}

-- A lucky sweep pays this many times a normal tile (plus CritMult from the tree).
local CRIT_BASE_MULT = 5

-- One tier of a hex: name, description, levels, bonus per level, first price, price growth,
-- rebirths needed.
local function tier(name: string, desc: string, levels: number, perLevel: number, baseCost: number, growth: number, rebirths: number?): UpgradeTier
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

-- Sub-trees (Slime RNG style): a "Lab" hex on the main board costs cash once, then tapping
-- it takes you to that lab's own honeycomb. Each sub-tree starts from its Root.
export type TreeDef = { Id: string, Name: string, Root: string, Portal: string? }
local Trees: { [string]: TreeDef } = {
	Main = { Id = "Main", Name = "Upgrades", Root = "Power" },
	Eggs = { Id = "Eggs", Name = "Egg Lab", Root = "Luck", Portal = "EggLab" },
	Lucky = { Id = "Lucky", Name = "Lucky Lab", Root = "Golden", Portal = "LuckyLab" },
	Pets = { Id = "Pets", Name = "Pet Lab", Root = "PetIncome", Portal = "PetLab" },
}

local function lab(id: string, q: number, r: number, tree: string, name: string, desc: string, icon: string, cost: number): UpgradeDef
	local def = n(id, q, r, "Power", "Portal", name, desc, 1, 0, cost, 1)
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

-- Ids are kept from the old tree where the hex is the same thing (saved levels carry
-- over); hexes that went away are in Retired below and are refunded.
-- A sub-tree's root has no Parent: it needs its lab instead.
-- stylua: ignore
local Main = {
	t("Power",      0,  0, nil,         "Power", {
		tier("Sweep Power",    "Every pile gives more leaves",          10, 0.25, 150,             1.9),
		tier("Strong Arms",    "Even more leaves from every pile",      10, 0.20, 20_000,          2.3),
		tier("Mighty Sweep",   "Much more leaves from every pile",      10, 0.20, 2_000_000_000,   2.3, 1),
		tier("Titan Sweep",    "Huge leaf hauls from every pile",       10, 0.25, 30_000_000_000,  2.3, 2),
	}),
	t("Backpack",   1,  0, "Power",     "Backpack", {
		tier("Backpack",       "Carry more leaves per trip",            10, 0.25, 300,             2.2),
		tier("Giant Sack",     "Carry even more leaves",                10, 0.20, 30_000,          2.3),
		tier("Leaf Truck",     "Carry way more leaves",                 10, 0.25, 3_000_000_000,   2.3, 1),
	}),
	t("LeafValue",  0,  1, "Power",     "DustValue", {
		tier("Leaf Value",     "Every leaf sells for more",             10, 0.10, 800,             2.2),
		tier("Fancy Leaves",   "Every leaf sells for even more",        10, 0.15, 60_000,          2.4),
		tier("Diamond Leaves", "Every leaf sells for way more",         10, 0.20, 45_000_000_000,  2.4, 2),
	}),
	t("Speed",     -1,  0, "Power",     "Speed", {
		tier("Running Shoes",  "Walk faster",                            8, 2,    400,             2.0),
		tier("Rocket Shoes",   "Walk even faster",                       5, 2,    3_000_000_000,   2.5, 1),
	}),
	lab("EggLab",   1, -1, "Eggs",  "Egg Lab",   "Egg luck, Huge pets, mutations and hatching", "Icon_Egg", 2_000),
	lab("LuckyLab", 0, -1, "Lucky", "Lucky Lab", "Lucky sweeps, golden piles and bunnies",      "Icon_Star", 5_000),
	lab("PetLab",  -1,  1, "Pets",  "Pet Lab",   "Pet income, passives and offline cash",       "Icon_Alien", 1_500),
	t("Radius",     2, -1, "Backpack",  "Radius", {
		tier("Wide Sweep",     "Sweep a bigger area at once",            5, 0.05, 25_000,          2.6),
		tier("Mega Sweep",     "Sweep an even bigger area",              5, 0.05, 3_000_000_000,   2.6, 1),
		tier("Tornado",        "Sweep a huge area at once",              5, 0.06, 200_000_000_000, 2.8, 3),
	}),
	t("Cash",       1,  1, "LeafValue", "Cash", {
		tier("Money Magnet",   "Grab coins from further away, plus more cash", 10, 0.05, 50_000,          2.5),
		tier("Rich Sweeper",   "Bigger coin magnet, plus more cash",           10, 0.05, 5_000_000_000,   2.5, 1),
		tier("Golden Broom",   "Huge coin magnet, plus more cash",             10, 0.05, 250_000_000_000, 2.5, 3),
	}),
	n("QuickDump",  2,  0, "Backpack",  "DumpSpeed",        "Quick Dump",   "Your bag pours into the dump faster",     5, 0.20, 5_000,   3.0),
	t("LuckyFinds",-2,  0, "Speed",     "ItemFind", {
		tier("Lucky Finds",    "Items drop from the leaves more often",  5, 0.05, 3_000,           2.8),
		tier("Treasure Hunter","Items drop from the leaves way more often", 5, 0.05, 4_000_000_000, 2.8, 1),
	}),
	n("LongBrew",  -2,  1, "Speed",     "PotionTime",       "Long Brew",    "Potions last longer",                     5, 0.10, 8_000,   3.0),
	n("Fertilizer", 0,  2, "LeafValue", "Regrow",           "Fertilizer",   "Your leaves grow back faster",            4, 0.03, 3_000_000_000, 3.0, 1),
	n("Haggler",    1,  2, "Cash",      "MerchantDiscount", "Haggler",      "The Traveling Merchant gives you a discount", 4, 0.05, 100_000, 3.0),
	n("BiggerCart", 1,  3, "Haggler",   "MerchantSlots",    "Bigger Cart",  "The Traveling Merchant shows you one more item", 2, 1, 5_000_000_000, 20, 1),
}

-- stylua: ignore
local Eggs = inTree("Eggs", {
	t("Luck",        0,  0, nil,          "Luck", {
		tier("Egg Luck",         "Find more and rarer eggs",         10, 0.10, 1_000,           2.5),
		tier("Lucky Charm",      "Find even more and rarer eggs",    10, 0.05, 2_500_000_000,   2.4, 1),
		tier("Four-Leaf Clover", "Find way more and rarer eggs",      5, 0.10, 6_000_000_000,   2.8, 2),
		tier("Rainbow Luck",     "The best egg luck there is",        5, 0.10, 250_000_000_000, 3.0, 3),
	}),
	t("HatchSpeed",  1,  0, "Luck",       "HatchSpeed", {
		tier("Quick Hatch",      "Eggs grow faster",                  5, 0.10, 30_000,          2.7),
		tier("Hatch Hurry",      "Eggs grow even faster",             5, 0.10, 5_000_000_000,   2.7, 1),
	}),
	t("Bunny",       0, -1, "Luck",       "Bunny", {
		tier("Bunny Hunter",     "Dust bunnies drop more cash",       5, 0.25, 20_000,          2.5),
		tier("Bunny Boss",       "Dust bunnies drop way more cash",   5, 0.50, 2_000_000_000,   2.5, 1),
	}),
	t("Incubator",  -1,  1, "Luck",       "Incubators", {
		tier("Bigger Nest",      "Grow one more egg at once",         1, 1,    150_000,         1),
		tier("Egg Nursery",      "Grow another egg at once",          1, 1,    25_000_000_000,  1, 1),
	}),
	n("HugeHunter",  1, -1, "Luck",       "Huge",       "Huge Hunter",  "Pets hatch Huge more often",                  5, 0.20, 50_000,        3.0),
	n("EggSniffer", -1,  0, "Luck",       "EggFind",    "Egg Sniffer",  "Find eggs in the leaves more often",          5, 0.05, 15_000,        2.8),
	n("StormChaser", 2,  0, "HatchSpeed", "WeatherMut", "Storm Chaser", "Weather mutates your growing eggs more often", 5, 0.20, 80_000,      2.8),
	n("ShinyHunter", 2, -2, "HugeHunter", "MutChance",  "Shiny Hunter", "Golden, Rainbow and Sparkly pets more often", 5, 0.20, 3_000_000_000, 2.8, 1),
})

-- stylua: ignore
local Lucky = inTree("Lucky", {
	-- The combo hexes went 2026-10-31 (Dev: the combo has no cap now); Golden is the root.
	t("Golden",      0,  0, nil,         "Golden", {
		tier("Golden Touch",  "Golden piles pay more",                  5, 0.20, 40_000,          2.8),
		tier("Gold Rush",     "Golden piles pay even more",             5, 0.25, 4_000_000_000,   2.7, 1),
		tier("Midas",         "Golden piles pay way more",              5, 0.50, 45_000_000_000,  2.8, 2),
	}),
	t("Crit",       -1,  1, "Golden",    "Crit", {
		tier("Lucky Sweep",   "Chance a leaf pays 5x",                  5, 0.01, 50_000,          2.8),
		tier("Lucky Streak",  "Even more lucky leaves",                 5, 0.01, 4_000_000_000,   2.8, 1),
	}),
	t("CritMult",   -1,  0, "Crit",      "CritMult", {
		tier("Jackpot",       "Lucky sweeps pay more",                  5, 1,    5_000_000_000,   2.7, 1),
		tier("Mega Jackpot",  "Lucky sweeps pay way more",              3, 2,    150_000_000_000, 3.0, 3),
	}),
	n("BunnyNet",   -2,  2, "Crit",      "BunnyReach",  "Bunny Net",    "Catch dust bunnies from further away",    4, 0.25, 60_000,        2.8),
})

-- stylua: ignore
local Pets = inTree("Pets", {
	t("PetIncome",   0,  0, nil,          "PetIncome", {
		tier("Happy Pets",    "Pets in your park earn more",            10, 0.10, 1_500,           2.3),
		tier("Pet Treats",    "Pets in your park earn even more",       10, 0.15, 60_000,          2.4),
		tier("Pet Party",     "Pets in your park earn a lot more",      10, 0.20, 4_000_000_000,   2.4, 1),
		tier("Pet Paradise",  "Pets in your park earn way more",        10, 0.25, 60_000_000_000,  2.4, 2),
	}),
	t("Offline",    -1,  1, "PetIncome",  "Offline", {
		tier("Night Shift",   "Earn more while you're away",             5, 0.20, 25_000,          2.5),
		tier("Sleep Pay",     "Earn even more while you're away",        5, 0.25, 3_000_000_000,   2.5, 1),
	}),
	n("GoodDeals",   1,  0, "PetIncome",  "PetSell",      "Good Deals",   "The Pet Trader pays more for your pets", 5, 0.15, 10_000,        2.6),
	n("BestFriends", 0, -1, "PetIncome",  "PassivePower", "Best Friends", "Your pets' passive powers get stronger", 5, 0.06, 500_000,       2.8),
	n("LongNap",    -2,  2, "Offline",    "OfflineCap",   "Long Nap",     "Earn offline for longer",                4, 0.5,  2_000_000_000, 2.5, 1),
})

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
	Backpack2 = { BaseCost = 30_000, CostGrowth = 2.3 },          Backpack3 = { BaseCost = 3_000_000_000, CostGrowth = 2.3 },
	Radius2 = { BaseCost = 3_000_000_000, CostGrowth = 2.6 },     Radius3 = { BaseCost = 200_000_000_000, CostGrowth = 2.8 },
	Cash2 = { BaseCost = 5_000_000_000, CostGrowth = 2.5 },       Cash3 = { BaseCost = 250_000_000_000, CostGrowth = 2.5 },
	LeafValue2 = { BaseCost = 60_000, CostGrowth = 2.4 },         LeafValue3 = { BaseCost = 45_000_000_000, CostGrowth = 2.4 },
	Power2 = { BaseCost = 20_000, CostGrowth = 2.3 },             Power3 = { BaseCost = 2_000_000_000, CostGrowth = 2.3 },
	Power4 = { BaseCost = 30_000_000_000, CostGrowth = 2.3 },     Speed2 = { BaseCost = 3_000_000_000, CostGrowth = 2.5 },
	Luck2 = { BaseCost = 2_500_000_000, CostGrowth = 2.4 },       Luck3 = { BaseCost = 6_000_000_000, CostGrowth = 2.8 },
	Luck4 = { BaseCost = 250_000_000_000, CostGrowth = 3.0 },     HatchSpeed2 = { BaseCost = 5_000_000_000, CostGrowth = 2.7 },
	Bunny2 = { BaseCost = 2_000_000_000, CostGrowth = 2.5 },      Incubator2 = { BaseCost = 25_000_000_000, CostGrowth = 1 },
	Combo2 = { BaseCost = 3_000_000_000, CostGrowth = 3.0 },      ComboTime2 = { BaseCost = 3_500_000_000, CostGrowth = 2.6 },
	Golden2 = { BaseCost = 4_000_000_000, CostGrowth = 2.7 },     Golden3 = { BaseCost = 45_000_000_000, CostGrowth = 2.8 },
	Crit2 = { BaseCost = 4_000_000_000, CostGrowth = 2.8 },       Combo3 = { BaseCost = 300_000_000_000, CostGrowth = 4.0 },
	CritMult2 = { BaseCost = 150_000_000_000, CostGrowth = 3.0 }, PetIncome2 = { BaseCost = 60_000, CostGrowth = 2.4 },
	PetIncome3 = { BaseCost = 4_000_000_000, CostGrowth = 2.4 },  PetIncome4 = { BaseCost = 60_000_000_000, CostGrowth = 2.4 },
	Offline2 = { BaseCost = 3_000_000_000, CostGrowth = 2.5 },
	-- The combo hexes (2026-10-31: the combo has no cap or upgrades any more).
	Combo = { BaseCost = 2_000, CostGrowth = 3.0, Tiers = {
		{ Levels = 4, BaseCost = 2_000, CostGrowth = 3.0 },
		{ Levels = 4, BaseCost = 3_000_000_000, CostGrowth = 3.0 },
		{ Levels = 2, BaseCost = 300_000_000_000, CostGrowth = 4.0 },
	} },
	ComboTime = { BaseCost = 35_000, CostGrowth = 2.6, Tiers = {
		{ Levels = 5, BaseCost = 35_000, CostGrowth = 2.6 },
		{ Levels = 5, BaseCost = 3_500_000_000, CostGrowth = 2.6 },
	} },
	SecondWind = { BaseCost = 20_000, CostGrowth = 2.8 },
	GoldenCombo = { BaseCost = 3_000_000_000, CostGrowth = 3.0 },
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
	-- Children of each node (drawn as links, opened when the node is bought).
	Children = {} :: { [string]: { UpgradeDef } },
	-- Nodes that raise each stat.
	ByStat = {} :: { [string]: { UpgradeDef } },
	Root = "Power",
	BaseWalkSpeed = 16,
	CritBaseMult = CRIT_BASE_MULT,
}

for _, def in List do
	assert(not Upgrades.ById[def.Id], `duplicate upgrade {def.Id}`)
	assert(not Retired[def.Id], `{def.Id} is both live and retired`)
	assert(Trees[def.Tree], `{def.Id}: unknown tree {def.Tree}`)
	assert(Stats[def.Stat], `{def.Id}: unknown stat {def.Stat}`)
	Upgrades.ById[def.Id] = def
	Upgrades.Children[def.Id] = {}
	Upgrades.ByStat[def.Stat] = Upgrades.ByStat[def.Stat] or {}
	table.insert(Upgrades.ByStat[def.Stat], def)
end
local seenStat: { [string]: string } = {}
for _, def in List do
	-- One hex per stat (Dev: no repeats). Labs all share "Portal".
	if def.Stat ~= "Portal" then
		assert(not seenStat[def.Stat], `{def.Id} repeats {def.Stat} (already on {seenStat[def.Stat]})`)
		seenStat[def.Stat] = def.Id
	end
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
