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

-- Every upgrade step is its own hex you buy once (Slime RNG, Dev 2026-10-31: "expand as
-- upgrades instead of one upgrade having multiple levels"). A step's next one sits next to
-- it, so the tree grows outwards as you buy, and the outer ones need rebirths. Names say
-- what a hex gives ("+50% Leaves", "+1 Egg Slot").
-- A sub-tree's root has no Parent: it needs its lab instead.
-- n(id, q, r, parent, stat, name, description, levels, bonus, price, growth, rebirths)
-- BEGIN GENERATED TREE (tools/gen_upgrade_tree.py; edit the spec there, not here)
-- stylua: ignore
local Main = {
	n("Power", 0, 0, nil, "Power", "+50% Leaves", "Every pile gives more leaves", 1, 0.5, 435, 1),
	n("Power_2", 0, -1, "Power", "Power", "+50% Leaves", "Every pile gives more leaves", 1, 0.5, 1_570, 1),
	n("Power_3", 0, -2, "Power_2", "Power", "+25% Leaves", "Every pile gives more leaves", 1, 0.25, 1_950, 1),
	n("Backpack", 1, -1, "Power", "Backpack", "+60% Bag Space", "Carry more leaves per trip", 1, 0.6, 960, 1),
	n("Backpack_2", 2, -2, "Backpack", "Backpack", "+60% Bag Space", "Carry more leaves per trip", 1, 0.6, 4_650, 1),
	n("Backpack_3", 3, -3, "Backpack_2", "Backpack", "+30% Bag Space", "Carry more leaves per trip", 1, 0.3, 7_030, 1),
	n("Speed", -1, 0, "Power", "Speed", "+4 Speed", "Walk faster", 1, 4, 1_200, 1),
	n("Speed_2", -2, 0, "Speed", "Speed", "+4 Speed", "Walk faster", 1, 4, 4_800, 1),
	n("Speed_3", -3, 0, "Speed_2", "Speed", "+2 Speed", "Walk faster", 1, 2, 6_400, 1),
	n("LeafValue", 1, 0, "Power", "DustValue", "+30% Leaf Price", "Every leaf sells for more", 1, 0.3, 2_560, 1),
	n("LeafValue_2", 2, 0, "LeafValue", "DustValue", "+30% Leaf Price", "Every leaf sells for more", 1, 0.3, 12_400, 1),
	n("LeafValue_3", 3, 0, "LeafValue_2", "DustValue", "+15% Leaf Price", "Every leaf sells for more", 1, 0.15, 18_700, 1),
	lab("PetLab", -1, 1, "Power", "Pets", "Pet Lab", "Pet income, pet fights and offline cash", "Icon_Alien", 1_500),
	n("WorkGloves", 1, -2, "Backpack", "Power", "+50% Leaves", "Grab more leaves from every pile", 1, 0.5, 9_000, 1),
	n("WorkGloves_2", 1, -3, "WorkGloves", "Power", "+50% Leaves", "Grab more leaves from every pile", 1, 0.5, 36_000, 1),
	n("WorkGloves_3", 1, -4, "WorkGloves_2", "Power", "+25% Leaves", "Grab more leaves from every pile", 1, 0.25, 48_000, 1),
	n("QuickDump", 2, -1, "Backpack", "DumpSpeed", "+40% Dump Speed", "Your bag pours into the dump faster", 1, 0.4, 45_500, 1),
	n("QuickDump_2", 3, -1, "QuickDump", "DumpSpeed", "+40% Dump Speed", "Your bag pours into the dump faster", 1, 0.4, 2_990_000, 1),
	n("QuickDump_3", 4, -1, "QuickDump_2", "DumpSpeed", "+20% Dump Speed", "Your bag pours into the dump faster", 1, 0.2, 21_500_000, 1),
	lab("EggLab", 2, -3, "WorkGloves", "Eggs", "Egg Lab", "Egg luck, Huge pets, mutations and hatching", "Icon_Egg", 2_000),
	lab("LuckyLab", 3, -2, "QuickDump", "Lucky", "Lucky Lab", "Lucky sweeps, golden piles and bunnies", "Icon_Star", 5_000),
	n("BigPockets", 4, -4, "Backpack_3", "Backpack", "+60% Bag Space", "Even more room in your bag", 1, 0.6, 47_200, 1),
	n("BigPockets_2", 5, -5, "BigPockets", "Backpack", "+60% Bag Space", "Even more room in your bag", 1, 0.6, 1_130_000, 1),
	n("BigPockets_3", 6, -6, "BigPockets_2", "Backpack", "+30% Bag Space", "Even more room in your bag", 1, 0.3, 4_610_000, 1),
	n("GiantSack", 4, -5, "BigPockets", "Backpack", "+80% Bag Space", "Carry a huge sack of leaves", 1, 0.8, 945_000, 1),
	n("GiantSack_2", 4, -6, "GiantSack", "Backpack", "+80% Bag Space", "Carry a huge sack of leaves", 1, 0.8, 26_500_000, 1),
	n("GiantSack_3", 4, -7, "GiantSack_2", "Backpack", "+40% Bag Space", "Carry a huge sack of leaves", 1, 0.4, 118_000_000, 1),
	n("LeafTruck", 5, -4, "BigPockets", "Backpack", "+80% Bag Space", "Carry way more leaves", 1, 0.8, 17_700_000_000, 1, 1),
	n("LeafTruck_2", 6, -4, "LeafTruck", "Backpack", "+80% Bag Space", "Carry way more leaves", 1, 0.8, 425_000_000_000, 1, 1),
	n("LeafTruck_3", 7, -4, "LeafTruck_2", "Backpack", "+40% Bag Space", "Carry way more leaves", 1, 0.4, 1_730_000_000_000, 1, 1),
	n("LeafTrailer", 5, -6, "GiantSack", "Backpack", "+40% Bag Space", "Hook a whole trailer of leaves to your bag", 1, 0.4, 354_000_000_000, 1, 2),
	n("LeafTrailer_2", 6, -7, "LeafTrailer", "Backpack", "+40% Bag Space", "Hook a whole trailer of leaves to your bag", 1, 0.4, 8_500_000_000_000, 1, 2),
	n("LeafTrailer_3", 7, -8, "LeafTrailer_2", "Backpack", "+20% Bag Space", "Hook a whole trailer of leaves to your bag", 1, 0.2, 34_600_000_000_000, 1, 2),
	n("WideSweep", 2, -4, "WorkGloves_2", "Radius", "+10% Sweep Size", "Sweep a bigger area at once", 1, 0.1, 178_000, 1),
	n("WideSweep_2", 3, -5, "WideSweep", "Radius", "+10% Sweep Size", "Sweep a bigger area at once", 1, 0.1, 6_600_000, 1),
	n("WideSweep_3", 3, -6, "WideSweep_2", "Radius", "+5% Sweep Size", "Sweep a bigger area at once", 1, 0.05, 34_600_000, 1),
	n("IronGrip", 0, -3, "WorkGloves_2", "Power", "+60% Leaves", "Tough piles break in fewer swipes", 1, 0.6, 268_000, 1),
	n("IronGrip_2", -1, -3, "IronGrip", "Power", "+60% Leaves", "Tough piles break in fewer swipes", 1, 0.6, 8_710_000, 1),
	n("IronGrip_3", -2, -3, "IronGrip_2", "Power", "+30% Leaves", "Tough piles break in fewer swipes", 1, 0.3, 42_200_000, 1),
	n("MegaSweep", 2, -5, "WideSweep", "Radius", "+10% Sweep Size", "Sweep an even bigger area", 1, 0.1, 21_300_000_000, 1, 1),
	n("MegaSweep_2", 2, -6, "MegaSweep", "Radius", "+10% Sweep Size", "Sweep an even bigger area", 1, 0.1, 793_000_000_000, 1, 1),
	n("MegaSweep_3", 2, -7, "MegaSweep_2", "Radius", "+5% Sweep Size", "Sweep an even bigger area", 1, 0.05, 4_150_000_000_000, 1, 1),
	n("Tornado", 1, -5, "MegaSweep", "Radius", "+12% Sweep Size", "Sweep a huge area at once", 1, 0.12, 1_620_000_000_000, 1, 3),
	n("Tornado_2", 1, -6, "Tornado", "Radius", "+12% Sweep Size", "Sweep a huge area at once", 1, 0.12, 81_700_000_000_000, 1, 3),
	n("Tornado_3", 1, -7, "Tornado_2", "Radius", "+6% Sweep Size", "Sweep a huge area at once", 1, 0.06, 508_000_000_000_000, 1, 3),
	n("MuscleUp", 0, -4, "IronGrip", "Power", "+80% Leaves", "Much more leaves from every pile", 1, 0.8, 11_800_000_000, 1, 1),
	n("MuscleUp_2", 0, -5, "MuscleUp", "Power", "+80% Leaves", "Much more leaves from every pile", 1, 0.8, 283_000_000_000, 1, 1),
	n("MuscleUp_3", 0, -6, "MuscleUp_2", "Power", "+40% Leaves", "Much more leaves from every pile", 1, 0.4, 1_150_000_000_000, 1, 1),
	n("TitanStrength", -1, -2, "IronGrip", "Power", "+120% Leaves", "Huge leaf hauls from every pile", 1, 1.2, 177_000_000_000, 1, 2),
	n("TitanStrength_2", -2, -2, "TitanStrength", "Power", "+120% Leaves", "Huge leaf hauls from every pile", 1, 1.2, 4_250_000_000_000, 1, 2),
	n("TitanStrength_3", -3, -2, "TitanStrength_2", "Power", "+60% Leaves", "Huge leaf hauls from every pile", 1, 0.6, 17_300_000_000_000, 1, 2),
	n("LuckyFinds", -1, -1, "Speed", "ItemFind", "+10% Item Drops", "Items drop from the leaves more often", 1, 0.1, 11_400, 1),
	n("LuckyFinds_2", -2, -1, "LuckyFinds", "ItemFind", "+10% Item Drops", "Items drop from the leaves more often", 1, 0.1, 89_400, 1),
	n("LuckyFinds_3", -3, -1, "LuckyFinds_2", "ItemFind", "+5% Item Drops", "Items drop from the leaves more often", 1, 0.05, 184_000, 1),
	n("LongBrew", -2, 1, "Speed", "PotionTime", "+20% Potion Time", "Potions last longer", 1, 0.2, 72_800, 1),
	n("LongBrew_2", -3, 2, "LongBrew", "PotionTime", "+20% Potion Time", "Potions last longer", 1, 0.2, 4_780_000, 1),
	n("LongBrew_3", -4, 3, "LongBrew_2", "PotionTime", "+10% Potion Time", "Potions last longer", 1, 0.1, 34_400_000, 1),
	n("SpringShoes", 4, -2, "QuickDump_2", "Speed", "+2 Speed", "Bounce along even faster", 1, 2, 200_000, 1),
	n("SpringShoes_2", 5, -3, "SpringShoes", "Speed", "+2 Speed", "Bounce along even faster", 1, 2, 1_140_000, 1),
	n("SpringShoes_3", 6, -3, "SpringShoes_2", "Speed", "+2 Speed", "Bounce along even faster", 1, 2, 6_500_000, 1),
	n("TreasureHunter", -4, -1, "LuckyFinds_3", "ItemFind", "+10% Item Drops", "Items drop from the leaves way more often", 1, 0.1, 32_400_000_000, 1, 1),
	n("TreasureHunter_2", -5, -1, "TreasureHunter", "ItemFind", "+10% Item Drops", "Items drop from the leaves way more often", 1, 0.1, 1_630_000_000_000, 1, 1),
	n("TreasureHunter_3", -6, -1, "TreasureHunter_2", "ItemFind", "+5% Item Drops", "Items drop from the leaves way more often", 1, 0.05, 10_200_000_000_000, 1, 1),
	n("RocketShoes", -4, 0, "LuckyFinds_3", "Speed", "+4 Speed", "Zoom around with rocket power", 1, 4, 20_100_000_000, 1, 1),
	n("RocketShoes_2", -5, 1, "RocketShoes", "Speed", "+4 Speed", "Zoom around with rocket power", 1, 4, 653_000_000_000, 1, 1),
	n("RocketShoes_3", -6, 2, "RocketShoes_2", "Speed", "+2 Speed", "Zoom around with rocket power", 1, 2, 3_170_000_000_000, 1, 1),
	n("MoneyMagnet", 1, 1, "LeafValue", "Cash", "+20% Cash + Magnet", "Grab coins from further away, plus more cash", 1, 0.2, 335_000, 1),
	n("MoneyMagnet_2", 1, 2, "MoneyMagnet", "Cash", "+20% Cash + Magnet", "Grab coins from further away, plus more cash", 1, 0.2, 10_900_000, 1),
	n("MoneyMagnet_3", 1, 3, "MoneyMagnet_2", "Cash", "+10% Cash + Magnet", "Grab coins from further away, plus more cash", 1, 0.1, 52_800_000, 1),
	n("FancyLeaves", 0, 1, "LeafValue", "DustValue", "+60% Leaf Price", "Every leaf sells for even more", 1, 0.6, 378_000, 1),
	n("FancyLeaves_2", -1, 2, "FancyLeaves", "DustValue", "+60% Leaf Price", "Every leaf sells for even more", 1, 0.6, 10_600_000, 1),
	n("FancyLeaves_3", -2, 3, "FancyLeaves_2", "DustValue", "+30% Leaf Price", "Every leaf sells for even more", 1, 0.3, 47_300_000, 1),
	n("Haggler", 2, 1, "MoneyMagnet", "MerchantDiscount", "+10% Merchant Sale", "The Traveling Merchant gives you a discount", 1, 0.1, 910_000, 1),
	n("Haggler_2", 3, 1, "Haggler", "MerchantDiscount", "+5% Merchant Sale", "The Traveling Merchant gives you a discount", 1, 0.05, 6_560_000, 1),
	n("Haggler_3", 4, 1, "Haggler_2", "MerchantDiscount", "+5% Merchant Sale", "The Traveling Merchant gives you a discount", 1, 0.05, 53_100_000, 1),
	n("BiggerCart", 2, 2, "Haggler", "MerchantSlots", "+1 Merchant Item", "The Traveling Merchant shows one more item", 1, 1, 5_000_000_000, 1, 1),
	n("BiggerCart_2", 2, 3, "BiggerCart", "MerchantSlots", "+1 Merchant Item", "The Traveling Merchant shows one more item", 1, 1, 100_000_000_000, 1, 1),
	n("RichSweeper", 0, 2, "MoneyMagnet", "Cash", "+20% Cash + Magnet", "Bigger coin magnet, plus more cash", 1, 0.2, 33_500_000_000, 1, 1),
	n("RichSweeper_2", -1, 3, "RichSweeper", "Cash", "+20% Cash + Magnet", "Bigger coin magnet, plus more cash", 1, 0.2, 1_090_000_000_000, 1, 1),
	n("RichSweeper_3", -2, 4, "RichSweeper_2", "Cash", "+10% Cash + Magnet", "Bigger coin magnet, plus more cash", 1, 0.1, 5_280_000_000_000, 1, 1),
	n("GoldenBroom", 0, 3, "RichSweeper", "Cash", "+20% Cash + Magnet", "Huge coin magnet, plus more cash", 1, 0.2, 1_680_000_000_000, 1, 3),
	n("GoldenBroom_2", 0, 4, "GoldenBroom", "Cash", "+20% Cash + Magnet", "Huge coin magnet, plus more cash", 1, 0.2, 54_400_000_000_000, 1, 3),
	n("GoldenBroom_3", 0, 5, "GoldenBroom_2", "Cash", "+10% Cash + Magnet", "Huge coin magnet, plus more cash", 1, 0.1, 264_000_000_000_000, 1, 3),
	n("Fertilizer", -2, 2, "FancyLeaves_2", "Regrow", "+6% Regrow Speed", "Your leaves grow back faster", 1, 0.06, 27_300_000_000, 1, 1),
	n("Fertilizer_2", -3, 3, "Fertilizer", "Regrow", "+3% Regrow Speed", "Your leaves grow back faster", 1, 0.03, 197_000_000_000, 1, 1),
	n("Fertilizer_3", -4, 4, "Fertilizer_2", "Regrow", "+3% Regrow Speed", "Your leaves grow back faster", 1, 0.03, 1_590_000_000_000, 1, 1),
	n("DiamondLeaves", -3, 4, "FancyLeaves_3", "DustValue", "+90% Leaf Price", "Every leaf sells for way more", 1, 0.9, 284_000_000_000, 1, 2),
	n("DiamondLeaves_2", -4, 5, "DiamondLeaves", "DustValue", "+90% Leaf Price", "Every leaf sells for way more", 1, 0.9, 7_960_000_000_000, 1, 2),
	n("DiamondLeaves_3", -5, 6, "DiamondLeaves_2", "DustValue", "+45% Leaf Price", "Every leaf sells for way more", 1, 0.45, 35_500_000_000_000, 1, 2),
}

-- stylua: ignore
local Eggs = inTree("Eggs", {
	n("Luck", 0, -1, nil, "Luck", "+20% Egg Luck", "Find more and rarer eggs", 1, 0.2, 3_500, 1),
	n("Luck_2", 0, -2, "Luck", "Luck", "+20% Egg Luck", "Find more and rarer eggs", 1, 0.2, 21_900, 1),
	n("Luck_3", 0, -3, "Luck_2", "Luck", "+10% Egg Luck", "Find more and rarer eggs", 1, 0.1, 39_100, 1),
	n("HatchSpeed", 1, -2, "Luck", "HatchSpeed", "+20% Hatch Speed", "Eggs grow faster", 1, 0.2, 228_000, 1),
	n("HatchSpeed_2", 2, -3, "HatchSpeed", "HatchSpeed", "+20% Hatch Speed", "Eggs grow faster", 1, 0.2, 9_930_000, 1),
	n("HatchSpeed_3", 3, -4, "HatchSpeed_2", "HatchSpeed", "+10% Hatch Speed", "Eggs grow faster", 1, 0.1, 56_900_000, 1),
	n("EggSniffer", -1, -1, "Luck", "EggFind", "+10% Eggs Found", "Find eggs in the leaves more often", 1, 0.1, 122_000, 1),
	n("EggSniffer_2", -2, -1, "EggSniffer", "EggFind", "+10% Eggs Found", "Find eggs in the leaves more often", 1, 0.1, 6_120_000, 1),
	n("EggSniffer_3", -3, -1, "EggSniffer_2", "EggFind", "+5% Eggs Found", "Find eggs in the leaves more often", 1, 0.05, 38_100_000, 1),
	n("HugeHunter", 1, -1, "Luck", "Huge", "+40% Huge Chance", "Pets hatch Huge more often", 1, 0.4, 455_000, 1),
	n("HugeHunter_2", 2, -1, "HugeHunter", "Huge", "+40% Huge Chance", "Pets hatch Huge more often", 1, 0.4, 29_900_000, 1),
	n("HugeHunter_3", 3, -1, "HugeHunter_2", "Huge", "+20% Huge Chance", "Pets hatch Huge more often", 1, 0.2, 215_000_000, 1),
	n("Incubator", -1, 0, "Luck", "Incubators", "+1 Egg Slot", "Grow one more egg at once", 1, 1, 150_000, 1),
	n("LuckyCharm", 1, -3, "Luck_2", "Luck", "+20% Egg Luck", "Find even rarer eggs", 1, 0.2, 2_680_000, 1),
	n("LuckyCharm_2", 2, -4, "LuckyCharm", "Luck", "+20% Egg Luck", "Find even rarer eggs", 1, 0.2, 87_100_000, 1),
	n("LuckyCharm_3", 3, -5, "LuckyCharm_2", "Luck", "+10% Egg Luck", "Find even rarer eggs", 1, 0.1, 422_000_000, 1),
	n("StormChaser", -1, -2, "Luck_2", "WeatherMut", "+40% Weather Mutation", "Weather mutates your growing eggs more often", 1, 0.4, 648_000, 1),
	n("StormChaser_2", -2, -2, "StormChaser", "WeatherMut", "+40% Weather Mutation", "Weather mutates your growing eggs more often", 1, 0.4, 32_700_000, 1),
	n("StormChaser_3", -3, -2, "StormChaser_2", "WeatherMut", "+20% Weather Mutation", "Weather mutates your growing eggs more often", 1, 0.2, 203_000_000, 1),
	n("HatchHurry", 2, -2, "HatchSpeed", "HatchSpeed", "+20% Hatch Speed", "Eggs grow even faster", 1, 0.2, 38_000_000_000, 1, 1),
	n("HatchHurry_2", 3, -2, "HatchHurry", "HatchSpeed", "+20% Hatch Speed", "Eggs grow even faster", 1, 0.2, 1_660_000_000_000, 1, 1),
	n("HatchHurry_3", 4, -2, "HatchHurry_2", "HatchSpeed", "+10% Hatch Speed", "Eggs grow even faster", 1, 0.1, 9_490_000_000_000, 1, 1),
	n("ShinyHunter", 1, 0, "HugeHunter", "MutChance", "+40% Mutation Chance", "Golden, Rainbow and Sparkly pets more often", 1, 0.4, 24_300_000_000, 1, 1),
	n("ShinyHunter_2", 1, 1, "ShinyHunter", "MutChance", "+40% Mutation Chance", "Golden, Rainbow and Sparkly pets more often", 1, 0.4, 1_220_000_000_000, 1, 1),
	n("ShinyHunter_3", 1, 2, "ShinyHunter_2", "MutChance", "+20% Mutation Chance", "Golden, Rainbow and Sparkly pets more often", 1, 0.2, 7_620_000_000_000, 1, 1),
	n("HugeMagnet", 2, 0, "HugeHunter_2", "Huge", "+40% Huge Chance", "Pets hatch Huge way more often", 1, 0.4, 64_800_000_000, 1, 2),
	n("HugeMagnet_2", 2, 1, "HugeMagnet", "Huge", "+40% Huge Chance", "Pets hatch Huge way more often", 1, 0.4, 3_270_000_000_000, 1, 2),
	n("HugeMagnet_3", 2, 2, "HugeMagnet_2", "Huge", "+20% Huge Chance", "Pets hatch Huge way more often", 1, 0.2, 20_300_000_000_000, 1, 2),
	n("EggRadar", -2, 0, "EggSniffer", "EggFind", "+10% Eggs Found", "Find eggs in the leaves way more often", 1, 0.1, 32_400_000_000, 1, 1),
	n("EggRadar_2", -3, 1, "EggRadar", "EggFind", "+10% Eggs Found", "Find eggs in the leaves way more often", 1, 0.1, 1_630_000_000_000, 1, 1),
	n("EggRadar_3", -4, 2, "EggRadar_2", "EggFind", "+5% Eggs Found", "Find eggs in the leaves way more often", 1, 0.05, 10_200_000_000_000, 1, 1),
	n("EggNursery", -2, 1, "Incubator", "Incubators", "+1 Egg Slot", "Grow another egg at once", 1, 1, 25_000_000_000, 1, 1),
	n("FourLeaf", 1, -4, "LuckyCharm", "Luck", "+20% Egg Luck", "Find way rarer eggs", 1, 0.2, 17_800_000_000, 1, 1),
	n("FourLeaf_2", 1, -5, "FourLeaf", "Luck", "+20% Egg Luck", "Find way rarer eggs", 1, 0.2, 660_000_000_000, 1, 1),
	n("FourLeaf_3", 1, -6, "FourLeaf_2", "Luck", "+10% Egg Luck", "Find way rarer eggs", 1, 0.1, 3_460_000_000_000, 1, 1),
	n("RainbowLuck", 2, -5, "LuckyCharm_2", "Luck", "+20% Egg Luck", "Rainbow-level egg luck", 1, 0.2, 48_600_000_000, 1, 2),
	n("RainbowLuck_2", 2, -6, "RainbowLuck", "Luck", "+20% Egg Luck", "Rainbow-level egg luck", 1, 0.2, 2_450_000_000_000, 1, 2),
	n("RainbowLuck_3", 2, -7, "RainbowLuck_2", "Luck", "+10% Egg Luck", "Rainbow-level egg luck", 1, 0.1, 15_200_000_000_000, 1, 2),
	n("Horseshoe", 0, -4, "FourLeaf", "Luck", "+20% Egg Luck", "The best egg luck there is", 1, 0.2, 2_280_000_000_000, 1, 3),
	n("Horseshoe_2", -1, -4, "Horseshoe", "Luck", "+20% Egg Luck", "The best egg luck there is", 1, 0.2, 149_000_000_000_000, 1, 3),
	n("Horseshoe_3", -2, -4, "Horseshoe_2", "Luck", "+10% Egg Luck", "The best egg luck there is", 1, 0.1, 1_080_000_000_000_000, 1, 3),
})

-- stylua: ignore
local Lucky = inTree("Lucky", {
	n("Golden", 0, -1, nil, "Golden", "+40% Golden Pile Cash", "Golden piles pay more", 1, 0.4, 324_000, 1),
	n("Golden_2", 0, -2, "Golden", "Golden", "+40% Golden Pile Cash", "Golden piles pay more", 1, 0.4, 16_300_000, 1),
	n("Golden_3", 0, -3, "Golden_2", "Golden", "+20% Golden Pile Cash", "Golden piles pay more", 1, 0.2, 102_000_000, 1),
	n("Crit", 1, -2, "Golden", "Crit", "+2% Lucky Leaves", "Chance a leaf pays 5x", 1, 0.02, 405_000, 1),
	n("Crit_2", 2, -3, "Crit", "Crit", "+2% Lucky Leaves", "Chance a leaf pays 5x", 1, 0.02, 20_400_000, 1),
	n("Crit_3", 3, -4, "Crit_2", "Crit", "+1% Lucky Leaves", "Chance a leaf pays 5x", 1, 0.01, 127_000_000, 1),
	n("Bunny", -1, -1, "Golden", "Bunny", "+50% Bunny Cash", "Dust bunnies drop more cash", 1, 0.5, 134_000, 1),
	n("Bunny_2", -2, -1, "Bunny", "Bunny", "+50% Bunny Cash", "Dust bunnies drop more cash", 1, 0.5, 4_350_000, 1),
	n("Bunny_3", -3, -1, "Bunny_2", "Bunny", "+25% Bunny Cash", "Dust bunnies drop more cash", 1, 0.25, 21_100_000, 1),
	n("LuckyPaw", 1, -1, "Golden", "Crit", "+1% Lucky Leaves", "A few more lucky leaves", 1, 0.01, 600_000, 1),
	n("LuckyPaw_2", 2, -1, "LuckyPaw", "Crit", "+1% Lucky Leaves", "A few more lucky leaves", 1, 0.01, 4_260_000, 1),
	n("LuckyPaw_3", 3, -1, "LuckyPaw_2", "Crit", "+1% Lucky Leaves", "A few more lucky leaves", 1, 0.01, 30_200_000, 1),
	n("GoldDigger", -1, 0, "Golden", "Golden", "+15% Golden Pile Cash", "Golden piles pay a bit more", 1, 0.15, 500_000, 1),
	n("GoldDigger_2", -2, 1, "GoldDigger", "Golden", "+15% Golden Pile Cash", "Golden piles pay a bit more", 1, 0.15, 3_050_000, 1),
	n("GoldDigger_3", -3, 2, "GoldDigger_2", "Golden", "+15% Golden Pile Cash", "Golden piles pay a bit more", 1, 0.15, 18_600_000, 1),
	n("BunnyNet", -1, -2, "Bunny", "BunnyReach", "+50% Bunny Range", "Catch dust bunnies from further away", 1, 0.5, 486_000, 1),
	n("BunnyNet_2", -1, -3, "BunnyNet", "BunnyReach", "+25% Bunny Range", "Catch dust bunnies from further away", 1, 0.25, 3_020_000, 1),
	n("BunnyNet_3", -1, -4, "BunnyNet_2", "BunnyReach", "+25% Bunny Range", "Catch dust bunnies from further away", 1, 0.25, 21_500_000, 1),
	n("GoldRush", 1, -3, "Golden_2", "Golden", "+50% Golden Pile Cash", "Golden piles pay even more", 1, 0.5, 30_400_000_000, 1, 1),
	n("GoldRush_2", 2, -4, "GoldRush", "Golden", "+50% Golden Pile Cash", "Golden piles pay even more", 1, 0.5, 1_320_000_000_000, 1, 1),
	n("GoldRush_3", 3, -5, "GoldRush_2", "Golden", "+25% Golden Pile Cash", "Golden piles pay even more", 1, 0.25, 7_590_000_000_000, 1, 1),
	n("LuckyStreak", 2, -2, "Crit", "Crit", "+2% Lucky Leaves", "Even more lucky leaves", 1, 0.02, 32_400_000_000, 1, 1),
	n("LuckyStreak_2", 3, -2, "LuckyStreak", "Crit", "+2% Lucky Leaves", "Even more lucky leaves", 1, 0.02, 1_630_000_000_000, 1, 1),
	n("LuckyStreak_3", 4, -2, "LuckyStreak_2", "Crit", "+1% Lucky Leaves", "Even more lucky leaves", 1, 0.01, 10_200_000_000_000, 1, 1),
	n("Jackpot", 3, -3, "Crit_2", "CritMult", "+2x Lucky Payout", "Lucky sweeps pay more", 1, 2, 38_000_000_000, 1, 1),
	n("Jackpot_2", 4, -3, "Jackpot", "CritMult", "+2x Lucky Payout", "Lucky sweeps pay more", 1, 2, 1_660_000_000_000, 1, 1),
	n("Jackpot_3", 5, -3, "Jackpot_2", "CritMult", "+1x Lucky Payout", "Lucky sweeps pay more", 1, 1, 9_490_000_000_000, 1, 1),
	n("BunnyBoss", -2, 0, "Bunny", "Bunny", "+100% Bunny Cash", "Dust bunnies drop way more cash", 1, 1, 13_400_000_000, 1, 1),
	n("BunnyBoss_2", -3, 1, "BunnyBoss", "Bunny", "+100% Bunny Cash", "Dust bunnies drop way more cash", 1, 1, 435_000_000_000, 1, 1),
	n("BunnyBoss_3", -4, 2, "BunnyBoss_2", "Bunny", "+50% Bunny Cash", "Dust bunnies drop way more cash", 1, 0.5, 2_110_000_000_000, 1, 1),
	n("Midas", 1, -4, "GoldRush", "Golden", "+100% Golden Pile Cash", "Golden piles pay way more", 1, 1, 364_000_000_000, 1, 2),
	n("Midas_2", 1, -5, "Midas", "Golden", "+100% Golden Pile Cash", "Golden piles pay way more", 1, 1, 18_400_000_000_000, 1, 2),
	n("Midas_3", 1, -6, "Midas_2", "Golden", "+50% Golden Pile Cash", "Golden piles pay way more", 1, 0.5, 114_000_000_000_000, 1, 2),
	n("MegaJackpot", 4, -4, "Jackpot", "CritMult", "+2x Lucky Payout", "Lucky sweeps pay way more", 1, 2, 150_000_000_000, 1, 3),
	n("MegaJackpot_2", 5, -5, "MegaJackpot", "CritMult", "+2x Lucky Payout", "Lucky sweeps pay way more", 1, 2, 1_220_000_000_000, 1, 3),
	n("MegaJackpot_3", 6, -6, "MegaJackpot_2", "CritMult", "+2x Lucky Payout", "Lucky sweeps pay way more", 1, 2, 9_840_000_000_000, 1, 3),
})

-- stylua: ignore
local Pets = inTree("Pets", {
	n("PetIncome", 0, -1, nil, "PetIncome", "+40% Pet Income", "Pets in your park earn more", 1, 0.4, 4_950, 1),
	n("PetIncome_2", 0, -2, "PetIncome", "PetIncome", "+40% Pet Income", "Pets in your park earn more", 1, 0.4, 26_200, 1),
	n("PetIncome_3", 0, -3, "PetIncome_2", "PetIncome", "+20% Pet Income", "Pets in your park earn more", 1, 0.2, 42_000, 1),
	n("PetTreats", 1, -2, "PetIncome", "PetIncome", "+60% Pet Income", "Pets in your park earn even more", 1, 0.6, 189_000, 1),
	n("PetTreats_2", 2, -3, "PetTreats", "PetIncome", "+60% Pet Income", "Pets in your park earn even more", 1, 0.6, 5_310_000, 1),
	n("PetTreats_3", 3, -4, "PetTreats_2", "PetIncome", "+30% Pet Income", "Pets in your park earn even more", 1, 0.3, 23_700_000, 1),
	n("Offline", -1, -1, "PetIncome", "Offline", "+40% Offline Cash", "Earn more while you're away", 1, 0.4, 168_000, 1),
	n("Offline_2", -2, -1, "Offline", "Offline", "+40% Offline Cash", "Earn more while you're away", 1, 0.4, 5_440_000, 1),
	n("Offline_3", -3, -1, "Offline_2", "Offline", "+20% Offline Cash", "Earn more while you're away", 1, 0.2, 26_400_000, 1),
	n("GoodDeals", 1, -1, "PetIncome", "PetSell", "+30% Pet Sell Price", "The Pet Trader pays more for your pets", 1, 0.3, 71_000, 1),
	n("GoodDeals_2", 2, -1, "GoodDeals", "PetSell", "+30% Pet Sell Price", "The Pet Trader pays more for your pets", 1, 0.3, 2_640_000, 1),
	n("GoodDeals_3", 3, -1, "GoodDeals_2", "PetSell", "+15% Pet Sell Price", "The Pet Trader pays more for your pets", 1, 0.15, 13_800_000, 1),
	n("SharpClaws", -1, 0, "PetIncome", "PetDamage", "+40% Pet Damage", "Your pets hit harder", 1, 0.4, 53_600, 1),
	n("SharpClaws_2", -2, 1, "SharpClaws", "PetDamage", "+40% Pet Damage", "Your pets hit harder", 1, 0.4, 1_740_000, 1),
	n("SharpClaws_3", -3, 2, "SharpClaws_2", "PetDamage", "+20% Pet Damage", "Your pets hit harder", 1, 0.2, 8_440_000, 1),
	n("ThickFur", 1, -3, "PetIncome_2", "PetHealth", "+40% Pet Health", "Your pets can take more hits", 1, 0.4, 53_600, 1),
	n("ThickFur_2", 2, -4, "ThickFur", "PetHealth", "+40% Pet Health", "Your pets can take more hits", 1, 0.4, 1_740_000, 1),
	n("ThickFur_3", 3, -5, "ThickFur_2", "PetHealth", "+20% Pet Health", "Your pets can take more hits", 1, 0.2, 8_440_000, 1),
	n("BestFriends", 2, -2, "PetTreats", "PassivePower", "+12% Pet Passives", "Your pets' passive powers get stronger", 1, 0.12, 4_050_000, 1),
	n("BestFriends_2", 3, -2, "BestFriends", "PassivePower", "+12% Pet Passives", "Your pets' passive powers get stronger", 1, 0.12, 204_000_000, 1),
	n("BestFriends_3", 4, -2, "BestFriends_2", "PassivePower", "+6% Pet Passives", "Your pets' passive powers get stronger", 1, 0.06, 1_270_000_000, 1),
	n("PetParty", 3, -3, "PetTreats_2", "PetIncome", "+80% Pet Income", "Pets in your park earn a lot more", 1, 0.8, 25_200_000_000, 1, 1),
	n("PetParty_2", 4, -3, "PetParty", "PetIncome", "+80% Pet Income", "Pets in your park earn a lot more", 1, 0.8, 708_000_000_000, 1, 1),
	n("PetParty_3", 5, -3, "PetParty_2", "PetIncome", "+40% Pet Income", "Pets in your park earn a lot more", 1, 0.4, 3_160_000_000_000, 1, 1),
	n("PetParadise", 4, -4, "PetParty", "PetIncome", "+100% Pet Income", "Pets in your park earn way more", 1, 1, 378_000_000_000, 1, 2),
	n("PetParadise_2", 5, -5, "PetParadise", "PetIncome", "+100% Pet Income", "Pets in your park earn way more", 1, 1, 10_600_000_000_000, 1, 2),
	n("PetParadise_3", 6, -6, "PetParadise_2", "PetIncome", "+50% Pet Income", "Pets in your park earn way more", 1, 0.5, 47_300_000_000_000, 1, 2),
	n("SleepPay", -1, -2, "Offline", "Offline", "+50% Offline Cash", "Earn even more while you're away", 1, 0.5, 20_100_000_000, 1, 1),
	n("SleepPay_2", -1, -3, "SleepPay", "Offline", "+50% Offline Cash", "Earn even more while you're away", 1, 0.5, 653_000_000_000, 1, 1),
	n("SleepPay_3", -1, -4, "SleepPay_2", "Offline", "+25% Offline Cash", "Earn even more while you're away", 1, 0.25, 3_170_000_000_000, 1, 1),
	n("LongNap", -2, 0, "Offline", "OfflineCap", "+1h Offline Time", "Earn offline for longer", 1, 1, 13_400_000_000, 1, 1),
	n("LongNap_2", -3, 1, "LongNap", "OfflineCap", "+0.5h Offline Time", "Earn offline for longer", 1, 0.5, 65_000_000_000, 1, 1),
	n("LongNap_3", -4, 2, "LongNap_2", "OfflineCap", "+0.5h Offline Time", "Earn offline for longer", 1, 0.5, 370_000_000_000, 1, 1),
	n("BattleTraining", -1, 1, "SharpClaws", "PetDamage", "+60% Pet Damage", "Your pets hit way harder", 1, 0.6, 20_100_000_000, 1, 1),
	n("BattleTraining_2", -1, 2, "BattleTraining", "PetDamage", "+60% Pet Damage", "Your pets hit way harder", 1, 0.6, 653_000_000_000, 1, 1),
	n("BattleTraining_3", -1, 3, "BattleTraining_2", "PetDamage", "+30% Pet Damage", "Your pets hit way harder", 1, 0.3, 3_170_000_000_000, 1, 1),
	n("PetArmor", 1, -4, "ThickFur", "PetHealth", "+60% Pet Health", "Your pets can take way more hits", 1, 0.6, 20_100_000_000, 1, 1),
	n("PetArmor_2", 1, -5, "PetArmor", "PetHealth", "+60% Pet Health", "Your pets can take way more hits", 1, 0.6, 653_000_000_000, 1, 1),
	n("PetArmor_3", 1, -6, "PetArmor_2", "PetHealth", "+30% Pet Health", "Your pets can take way more hits", 1, 0.3, 3_170_000_000_000, 1, 1),
})

-- Hex pictures: the stat's icon unless a hex has its own here (hand-drawn sticker icons,
-- art/flat_icons.py). A name that isn't uploaded yet falls back to the stat's icon.
-- stylua: ignore
local Icons: { [string]: string } = {
	["WorkGloves"] = "Icon_UpGloves",
	["WorkGloves_2"] = "Icon_UpGloves",
	["WorkGloves_3"] = "Icon_UpGloves",
	["BigPockets"] = "Icon_UpSack",
	["BigPockets_2"] = "Icon_UpSack",
	["BigPockets_3"] = "Icon_UpSack",
	["GiantSack"] = "Icon_UpSack",
	["GiantSack_2"] = "Icon_UpSack",
	["GiantSack_3"] = "Icon_UpSack",
	["LeafTruck"] = "Icon_Car_DustTruck",
	["LeafTruck_2"] = "Icon_Car_DustTruck",
	["LeafTruck_3"] = "Icon_Car_DustTruck",
	["LeafTrailer"] = "Icon_Car_DustTruck",
	["LeafTrailer_2"] = "Icon_Car_DustTruck",
	["LeafTrailer_3"] = "Icon_Car_DustTruck",
	["IronGrip"] = "Icon_UpGloves",
	["IronGrip_2"] = "Icon_UpGloves",
	["IronGrip_3"] = "Icon_UpGloves",
	["Tornado"] = "Icon_Tool_TornadoVac",
	["Tornado_2"] = "Icon_Tool_TornadoVac",
	["Tornado_3"] = "Icon_Tool_TornadoVac",
	["MuscleUp"] = "Icon_UpDumbbell",
	["MuscleUp_2"] = "Icon_UpDumbbell",
	["MuscleUp_3"] = "Icon_UpDumbbell",
	["TitanStrength"] = "Icon_UpDumbbell",
	["TitanStrength_2"] = "Icon_UpDumbbell",
	["TitanStrength_3"] = "Icon_UpDumbbell",
	["LuckyFinds"] = "Icon_UpMagnifier",
	["LuckyFinds_2"] = "Icon_UpMagnifier",
	["LuckyFinds_3"] = "Icon_UpMagnifier",
	["LongBrew"] = "Icon_Potion",
	["LongBrew_2"] = "Icon_Potion",
	["LongBrew_3"] = "Icon_Potion",
	["SpringShoes"] = "Icon_Speed",
	["SpringShoes_2"] = "Icon_Speed",
	["SpringShoes_3"] = "Icon_Speed",
	["TreasureHunter"] = "Icon_TreasureMap",
	["TreasureHunter_2"] = "Icon_TreasureMap",
	["TreasureHunter_3"] = "Icon_TreasureMap",
	["MoneyMagnet"] = "Icon_UpMagnet",
	["MoneyMagnet_2"] = "Icon_UpMagnet",
	["MoneyMagnet_3"] = "Icon_UpMagnet",
	["FancyLeaves"] = "Icon_UpGem",
	["FancyLeaves_2"] = "Icon_UpGem",
	["FancyLeaves_3"] = "Icon_UpGem",
	["RichSweeper"] = "Icon_UpMagnet",
	["RichSweeper_2"] = "Icon_UpMagnet",
	["RichSweeper_3"] = "Icon_UpMagnet",
	["GoldenBroom"] = "Icon_Tool_GoldenBroom",
	["GoldenBroom_2"] = "Icon_Tool_GoldenBroom",
	["GoldenBroom_3"] = "Icon_Tool_GoldenBroom",
	["Fertilizer"] = "Icon_UpSprout",
	["Fertilizer_2"] = "Icon_UpSprout",
	["Fertilizer_3"] = "Icon_UpSprout",
	["DiamondLeaves"] = "Icon_UpGem",
	["DiamondLeaves_2"] = "Icon_UpGem",
	["DiamondLeaves_3"] = "Icon_UpGem",
	["EggSniffer"] = "Icon_UpMagnifier",
	["EggSniffer_2"] = "Icon_UpMagnifier",
	["EggSniffer_3"] = "Icon_UpMagnifier",
	["Incubator"] = "Icon_UpNest",
	["LuckyCharm"] = "Icon_LuckyClover",
	["LuckyCharm_2"] = "Icon_LuckyClover",
	["LuckyCharm_3"] = "Icon_LuckyClover",
	["StormChaser"] = "Icon_Weather_Thunderstorm",
	["StormChaser_2"] = "Icon_Weather_Thunderstorm",
	["StormChaser_3"] = "Icon_Weather_Thunderstorm",
	["HatchHurry"] = "Icon_PotionHatch",
	["HatchHurry_2"] = "Icon_PotionHatch",
	["HatchHurry_3"] = "Icon_PotionHatch",
	["HugeMagnet"] = "Icon_HugeCharm",
	["HugeMagnet_2"] = "Icon_HugeCharm",
	["HugeMagnet_3"] = "Icon_HugeCharm",
	["EggRadar"] = "Icon_UpMagnifier",
	["EggRadar_2"] = "Icon_UpMagnifier",
	["EggRadar_3"] = "Icon_UpMagnifier",
	["EggNursery"] = "Icon_UpNest",
	["FourLeaf"] = "Icon_LuckyClover",
	["FourLeaf_2"] = "Icon_LuckyClover",
	["FourLeaf_3"] = "Icon_LuckyClover",
	["RainbowLuck"] = "Icon_Weather_Rainbow",
	["RainbowLuck_2"] = "Icon_Weather_Rainbow",
	["RainbowLuck_3"] = "Icon_Weather_Rainbow",
	["Horseshoe"] = "Icon_UpHorseshoe",
	["Horseshoe_2"] = "Icon_UpHorseshoe",
	["Horseshoe_3"] = "Icon_UpHorseshoe",
	["LuckyPaw"] = "Icon_LuckyCat",
	["LuckyPaw_2"] = "Icon_LuckyCat",
	["LuckyPaw_3"] = "Icon_LuckyCat",
	["GoldDigger"] = "Icon_UpGem",
	["GoldDigger_2"] = "Icon_UpGem",
	["GoldDigger_3"] = "Icon_UpGem",
	["Jackpot"] = "Icon_Cash",
	["Jackpot_2"] = "Icon_Cash",
	["Jackpot_3"] = "Icon_Cash",
	["MegaJackpot"] = "Icon_Cash",
	["MegaJackpot_2"] = "Icon_Cash",
	["MegaJackpot_3"] = "Icon_Cash",
	["PetIncome"] = "Icon_UpHeart",
	["PetIncome_2"] = "Icon_UpHeart",
	["PetIncome_3"] = "Icon_UpHeart",
	["PetTreats"] = "Icon_UpBone",
	["PetTreats_2"] = "Icon_UpBone",
	["PetTreats_3"] = "Icon_UpBone",
	["Offline"] = "Icon_UpMoon",
	["Offline_2"] = "Icon_UpMoon",
	["Offline_3"] = "Icon_UpMoon",
	["SharpClaws"] = "Icon_Sword",
	["SharpClaws_2"] = "Icon_Sword",
	["SharpClaws_3"] = "Icon_Sword",
	["ThickFur"] = "Icon_UpShield",
	["ThickFur_2"] = "Icon_UpShield",
	["ThickFur_3"] = "Icon_UpShield",
	["BestFriends"] = "Icon_UpHeart",
	["BestFriends_2"] = "Icon_UpHeart",
	["BestFriends_3"] = "Icon_UpHeart",
	["PetParty"] = "Icon_UpBone",
	["PetParty_2"] = "Icon_UpBone",
	["PetParty_3"] = "Icon_UpBone",
	["PetParadise"] = "Icon_UpHeart",
	["PetParadise_2"] = "Icon_UpHeart",
	["PetParadise_3"] = "Icon_UpHeart",
	["SleepPay"] = "Icon_UpMoon",
	["SleepPay_2"] = "Icon_UpMoon",
	["SleepPay_3"] = "Icon_UpMoon",
	["LongNap"] = "Icon_UpMoon",
	["LongNap_2"] = "Icon_UpMoon",
	["LongNap_3"] = "Icon_UpMoon",
	["BattleTraining"] = "Icon_Sword",
	["BattleTraining_2"] = "Icon_Sword",
	["BattleTraining_3"] = "Icon_Sword",
	["PetArmor"] = "Icon_UpShield",
	["PetArmor_2"] = "Icon_UpShield",
	["PetArmor_3"] = "Icon_UpShield",
}
-- END GENERATED TREE

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

-- The 2026-10-31 tree with multi-level hexes (Version 3), refunded the same way.
-- stylua: ignore
local OldTreeV3: { [string]: { { number } } } = {
	Power = { { 5, 150, 1.9 } },
	Backpack = { { 5, 300, 2.2 } },
	Speed = { { 5, 400, 2 } },
	LeafValue = { { 5, 800, 2.2 } },
	WorkGloves = { { 5, 3_000, 2 } },
	QuickDump = { { 5, 5_000, 8.1 } },
	BigPockets = { { 5, 8_000, 4.9 } },
	GiantSack = { { 5, 150_000, 5.3 } },
	LeafTruck = { { 5, 3_000_000_000, 4.9 } },
	LeafTrailer = { { 5, 60_000_000_000, 4.9 } },
	WideSweep = { { 5, 25_000, 6.1 } },
	IronGrip = { { 5, 40_000, 5.7 } },
	MegaSweep = { { 5, 3_000_000_000, 6.1 } },
	Tornado = { { 5, 200_000_000_000, 7.1 } },
	MuscleUp = { { 5, 2_000_000_000, 4.9 } },
	TitanStrength = { { 5, 30_000_000_000, 4.9 } },
	LuckyFinds = { { 5, 3_000, 2.8 } },
	LongBrew = { { 5, 8_000, 8.1 } },
	SpringShoes = { { 3, 200_000, 5.7 } },
	TreasureHunter = { { 5, 4_000_000_000, 7.1 } },
	RocketShoes = { { 5, 3_000_000_000, 5.7 } },
	MoneyMagnet = { { 5, 50_000, 5.7 } },
	FancyLeaves = { { 5, 60_000, 5.3 } },
	Haggler = { { 4, 100_000, 8.1 } },
	BiggerCart = { { 2, 5_000_000_000, 20 } },
	RichSweeper = { { 5, 5_000_000_000, 5.7 } },
	GoldenBroom = { { 5, 250_000_000_000, 5.7 } },
	Fertilizer = { { 4, 3_000_000_000, 8.1 } },
	DiamondLeaves = { { 5, 45_000_000_000, 5.3 } },
	Luck = { { 5, 1_000, 2.5 } },
	HatchSpeed = { { 5, 30_000, 6.6 } },
	EggSniffer = { { 5, 15_000, 7.1 } },
	HugeHunter = { { 5, 50_000, 8.1 } },
	Incubator = { { 1, 150_000, 1 } },
	LuckyCharm = { { 5, 400_000, 5.7 } },
	StormChaser = { { 5, 80_000, 7.1 } },
	HatchHurry = { { 5, 5_000_000_000, 6.6 } },
	ShinyHunter = { { 5, 3_000_000_000, 7.1 } },
	HugeMagnet = { { 5, 8_000_000_000, 7.1 } },
	EggRadar = { { 5, 4_000_000_000, 7.1 } },
	EggNursery = { { 1, 25_000_000_000, 1 } },
	FourLeaf = { { 5, 2_500_000_000, 6.1 } },
	RainbowLuck = { { 5, 6_000_000_000, 7.1 } },
	Horseshoe = { { 5, 250_000_000_000, 8.1 } },
	Golden = { { 5, 40_000, 7.1 } },
	Crit = { { 5, 50_000, 7.1 } },
	Bunny = { { 5, 20_000, 5.7 } },
	LuckyPaw = { { 3, 600_000, 7.1 } },
	GoldDigger = { { 3, 500_000, 6.1 } },
	BunnyNet = { { 4, 60_000, 7.1 } },
	GoldRush = { { 5, 4_000_000_000, 6.6 } },
	LuckyStreak = { { 5, 4_000_000_000, 7.1 } },
	Jackpot = { { 5, 5_000_000_000, 6.6 } },
	BunnyBoss = { { 5, 2_000_000_000, 5.7 } },
	Midas = { { 5, 45_000_000_000, 7.1 } },
	MegaJackpot = { { 3, 150_000_000_000, 8.1 } },
	PetIncome = { { 5, 1_500, 2.3 } },
	PetTreats = { { 5, 30_000, 5.3 } },
	Offline = { { 5, 25_000, 5.7 } },
	GoodDeals = { { 5, 10_000, 6.1 } },
	SharpClaws = { { 5, 8_000, 5.7 } },
	ThickFur = { { 5, 8_000, 5.7 } },
	BestFriends = { { 5, 500_000, 7.1 } },
	PetParty = { { 5, 4_000_000_000, 5.3 } },
	PetParadise = { { 5, 60_000_000_000, 5.3 } },
	SleepPay = { { 5, 3_000_000_000, 5.7 } },
	LongNap = { { 4, 2_000_000_000, 5.7 } },
	BattleTraining = { { 5, 3_000_000_000, 5.7 } },
	PetArmor = { { 5, 3_000_000_000, 5.7 } },
	PetLab = { { 1, 1_500, 1 } },
	EggLab = { { 1, 2_000, 1 } },
	LuckyLab = { { 1, 5_000, 1 } },
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
	OldTreeV3 = OldTreeV3,
	-- Bump when the tree is rebuilt: older saves are refunded (OldTree) and start fresh.
	Version = 4,
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
function Upgrades.oldTreeRefund(id: string, level: number, version: number?): number
	local tiers = if version == 3 then OldTreeV3[id] else OldTree[id]
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
