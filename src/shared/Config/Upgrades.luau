--!strict
-- The upgrade tree (Slime RNG style): a honeycomb of hexagon nodes bought with cash at the
-- Upgrade Station (or from the HUD). It starts from one node in the middle; buying a node
-- (level 1+) opens its neighbours further out. The outer rings need rebirths, so every
-- rebirth reveals more of the tree. Levels reset on rebirth, like cash and tools.
--
-- Each node raises one stat (Stats below). Several nodes can raise the same stat; their
-- bonuses add up. Other services read stats through Upgrades.multiplier / Upgrades.stat.
--
-- Hex = axial coordinates {q, r} (pointy-top). A node's Parent must be a direct neighbour,
-- so every link in the tree is one short line. Cost of the next level =
-- BaseCost * CostGrowth ^ level.
local Types = require(script.Parent.Parent.Types)

type UpgradeDef = Types.UpgradeDef

export type StatDef = {
	Name: string,
	Icon: string,
	Format: string, -- "percent" (+25%), "plus" (+4), "x" (+0.5x), "seconds" (+0.6s)
}

-- What each stat does in the game (where it is applied).
local Stats: { [string]: StatDef } = {
	Power = { Name = "Sweep Power", Icon = "Icon_Tool_Broom", Format = "percent" }, -- ToolService
	Backpack = { Name = "Backpack", Icon = "Icon_Backpack", Format = "percent" }, -- ToolService
	Speed = { Name = "Walk Speed", Icon = "Icon_Speed", Format = "plus" }, -- walkSpeed
	Luck = { Name = "Egg Luck", Icon = "Icon_Luck", Format = "percent" }, -- EggService
	DustValue = { Name = "Leaf Value", Icon = "Icon_Dust", Format = "percent" }, -- BackpackService
	Radius = { Name = "Sweep Size", Icon = "Icon_Tool_LeafBlower", Format = "percent" }, -- ToolService
	Cash = { Name = "All Cash", Icon = "Icon_Cash", Format = "percent" }, -- BoostService
	PetIncome = { Name = "Pet Income", Icon = "Icon_Alien", Format = "percent" }, -- AlienService
	Offline = { Name = "Offline Cash", Icon = "Icon_Daily", Format = "percent" }, -- AlienService
	ComboMax = { Name = "Max Combo", Icon = "Icon_Boost", Format = "x" }, -- SweepService
	ComboTime = { Name = "Combo Time", Icon = "Icon_Timer", Format = "seconds" }, -- SweepService
	Crit = { Name = "Lucky Sweep", Icon = "Icon_Star", Format = "percent" }, -- SweepService
	CritMult = { Name = "Lucky Payout", Icon = "Icon_Meteor", Format = "x" }, -- SweepService
	Golden = { Name = "Golden Piles", Icon = "Icon_Sell", Format = "percent" }, -- SweepService
	Bunny = { Name = "Bunny Rewards", Icon = "Icon_Gift", Format = "percent" }, -- DustBunnyService
	HatchSpeed = { Name = "Hatch Speed", Icon = "Icon_PotionHatch", Format = "percent" }, -- HatchService
	Incubators = { Name = "Eggs at Once", Icon = "Icon_Egg", Format = "plus" }, -- HatchService
}

-- A lucky sweep pays this many times a normal tile (plus CritMult from the tree).
local CRIT_BASE_MULT = 5

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
	return {
		Id = id,
		Hex = { q = q, r = r },
		Parent = parent,
		Stat = stat,
		Name = name,
		Description = desc,
		Icon = Stats[stat].Icon,
		Format = Stats[stat].Format,
		MaxLevel = maxLevel,
		PerLevel = perLevel,
		BaseCost = baseCost,
		CostGrowth = growth,
		RequiredRebirths = rebirths or 0,
	}
end

-- Ids Power, Backpack, Speed and Luck are the old flat upgrades, so saved levels carry over.
-- stylua: ignore
local List: { UpgradeDef } = {
	-- Centre
	n("Power",      0,  0, nil,          "Power",      "Sweep Power",    "Clear leaves faster",                        10, 0.15, 150,     1.9),

	-- Ring 1: one branch per direction
	n("Backpack",   1,  0, "Power",      "Backpack",   "Bigger Backpack", "Carry more leaves per trip",                10, 0.25, 300,     2.2),
	n("Luck",       1, -1, "Power",      "Luck",       "Egg Luck",       "Find more and rarer eggs",                   10, 0.10, 1_000,   2.5),
	n("Combo",      0, -1, "Power",      "ComboMax",   "Combo Master",   "Your sweep combo goes higher",                4, 0.25, 2_000,   3.0),
	n("Speed",     -1,  0, "Power",      "Speed",      "Running Shoes",  "Walk faster",                                 8, 2,    400,     2.0),
	n("PetIncome", -1,  1, "Power",      "PetIncome",  "Happy Pets",     "Pets in your park earn more",                10, 0.10, 1_500,   2.3),
	n("LeafValue",  0,  1, "Power",      "DustValue",  "Leaf Value",     "Every leaf sells for more",                  10, 0.10, 800,     2.2),

	-- Ring 2: fills the honeycomb around the centre
	n("Radius",     2,  0, "Backpack",   "Radius",     "Wide Sweep",     "Sweep a bigger area at once",                 5, 0.05, 25_000,  2.6),
	n("Golden",     2, -1, "Backpack",   "Golden",     "Golden Touch",   "Golden piles pay even more",                  5, 0.20, 40_000,  2.8),
	n("HatchSpeed", 2, -2, "Luck",       "HatchSpeed", "Quick Hatch",    "Eggs grow faster",                            5, 0.10, 30_000,  2.7),
	n("Bunny",      1, -2, "Luck",       "Bunny",      "Bunny Hunter",   "Dust bunnies drop more cash",                 5, 0.25, 20_000,  2.5),
	n("ComboTime",  0, -2, "Combo",      "ComboTime",  "Steady Hands",   "Your combo lasts longer between sweeps",      5, 0.3,  35_000,  2.6),
	n("Crit",      -1, -1, "Combo",      "Crit",       "Lucky Sweep",    "Chance a leaf pays 5x",                       5, 0.01, 50_000,  2.8),
	n("Power2",    -2,  0, "Speed",      "Power",      "Strong Arms",    "Clear leaves even faster",                   10, 0.15, 20_000,  2.3),
	n("Offline",   -2,  1, "Speed",      "Offline",    "Night Shift",    "Earn more while you're away",                 5, 0.20, 25_000,  2.5),
	n("PetIncome2",-2,  2, "PetIncome",  "PetIncome",  "Pet Treats",     "Pets in your park earn more",                10, 0.15, 60_000,  2.4),
	n("Incubator", -1,  2, "PetIncome",  "Incubators", "Bigger Nest",    "Grow one more egg at once",                   1, 1,    150_000, 1),
	n("Backpack2",  0,  2, "LeafValue",  "Backpack",   "Giant Sack",     "Carry even more leaves",                     10, 0.20, 30_000,  2.3),
	n("Cash",       1,  1, "LeafValue",  "Cash",       "Money Magnet",   "More cash from everything",                  10, 0.05, 50_000,  2.5),

	-- Ring 3: needs 1 rebirth (Clover needs 2)
	n("Radius2",    3,  0, "Radius",     "Radius",     "Mega Sweep",     "Sweep a bigger area at once",                 5, 0.05, 3_000_000,  2.6, 1),
	n("Golden2",    3, -1, "Golden",     "Golden",     "Gold Rush",      "Golden piles pay even more",                  5, 0.25, 4_000_000,  2.7, 1),
	n("Luck2",      3, -2, "HatchSpeed", "Luck",       "Lucky Charm",    "Find more and rarer eggs",                   10, 0.05, 2_500_000,  2.4, 1),
	n("HatchSpeed2",3, -3, "HatchSpeed", "HatchSpeed", "Hatch Hurry",    "Eggs grow faster",                            5, 0.10, 5_000_000,  2.7, 1),
	n("Bunny2",     2, -3, "Bunny",      "Bunny",      "Bunny Boss",     "Dust bunnies drop more cash",                 5, 0.50, 2_000_000,  2.5, 1),
	n("Luck3",      1, -3, "Bunny",      "Luck",       "Four-Leaf Clover", "Find more and rarer eggs",                  5, 0.10, 20_000_000, 2.8, 2),
	n("Combo2",     0, -3, "ComboTime",  "ComboMax",   "Combo King",     "Your sweep combo goes higher",                4, 0.25, 3_000_000,  3.0, 1),
	n("ComboTime2",-1, -2, "ComboTime",  "ComboTime",  "Zen Focus",      "Your combo lasts longer between sweeps",      5, 0.3,  3_500_000,  2.6, 1),
	n("CritMult",  -2, -1, "Crit",       "CritMult",   "Jackpot",        "Lucky sweeps pay more",                       5, 1,    5_000_000,  2.7, 1),
	n("Power3",    -3,  0, "Power2",     "Power",      "Mighty Sweep",   "Clear leaves much faster",                   10, 0.20, 2_000_000,  2.3, 1),
	n("Speed2",    -3,  1, "Power2",     "Speed",      "Rocket Shoes",   "Walk even faster",                            5, 2,    3_000_000,  2.5, 1),
	n("Offline2",  -3,  2, "Offline",    "Offline",    "Sleep Pay",      "Earn more while you're away",                 5, 0.25, 3_000_000,  2.5, 1),
	n("PetIncome3",-3,  3, "PetIncome2", "PetIncome",  "Pet Party",      "Pets in your park earn more",                10, 0.20, 4_000_000,  2.4, 1),
	n("Incubator2",-2,  3, "PetIncome2", "Incubators", "Egg Nursery",    "Grow one more egg at once",                   1, 1,    25_000_000, 1,   1),
	n("LeafValue2",-1,  3, "Incubator",  "DustValue",  "Fancy Leaves",   "Every leaf sells for more",                  10, 0.15, 2_500_000,  2.4, 1),
	n("Backpack3",  0,  3, "Backpack2",  "Backpack",   "Leaf Truck",     "Carry way more leaves",                      10, 0.25, 3_000_000,  2.3, 1),
	n("Cash2",      1,  2, "Cash",       "Cash",       "Rich Sweeper",   "More cash from everything",                  10, 0.05, 5_000_000,  2.5, 1),
	n("Crit2",      2,  1, "Cash",       "Crit",       "Lucky Streak",   "Chance a leaf pays 5x",                       5, 0.01, 4_000_000,  2.8, 1),

	-- Ring 4: big late nodes (2-3 rebirths)
	n("Radius3",    4,  0, "Radius2",    "Radius",     "Tornado",        "Sweep a huge area at once",                   5, 0.06, 400_000_000,   2.8, 3),
	n("Golden3",    4, -2, "Luck2",      "Golden",     "Midas",          "Golden piles pay way more",                   5, 0.50, 150_000_000,   2.8, 2),
	n("Luck4",      4, -4, "HatchSpeed2","Luck",       "Rainbow Luck",   "Find more and rarer eggs",                    5, 0.10, 500_000_000,   3.0, 3),
	n("Combo3",     0, -4, "Combo2",     "ComboMax",   "Combo God",      "Your sweep combo goes way higher",            2, 0.5,  600_000_000,   4.0, 3),
	n("CritMult2", -2, -2, "CritMult",   "CritMult",   "Mega Jackpot",   "Lucky sweeps pay way more",                   3, 2,    300_000_000,   3.0, 3),
	n("Power4",    -4,  0, "Power3",     "Power",      "Titan Sweep",    "Clear leaves insanely fast",                 10, 0.25, 100_000_000,   2.3, 2),
	n("PetIncome4",-4,  4, "PetIncome3", "PetIncome",  "Pet Paradise",   "Pets in your park earn way more",            10, 0.25, 200_000_000,   2.4, 2),
	n("LeafValue3", 2,  2, "Crit2",      "DustValue",  "Diamond Leaves", "Every leaf sells for way more",              10, 0.20, 150_000_000,   2.4, 2),
	n("Cash3",      0,  4, "Backpack3",  "Cash",       "Golden Broom",   "More cash from everything",                  10, 0.05, 500_000_000,   2.5, 3),
}

local Upgrades = {
	List = List,
	ById = {} :: { [string]: UpgradeDef },
	Stats = Stats,
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
	Upgrades.ById[def.Id] = def
	Upgrades.Children[def.Id] = {}
	Upgrades.ByStat[def.Stat] = Upgrades.ByStat[def.Stat] or {}
	table.insert(Upgrades.ByStat[def.Stat], def)
end
for _, def in List do
	if def.Parent then
		local parent = Upgrades.ById[def.Parent]
		assert(parent, `{def.Id}: unknown parent {def.Parent}`)
		-- Neighbours in axial coordinates differ by one of the six directions.
		local dq, dr = def.Hex.q - parent.Hex.q, def.Hex.r - parent.Hex.r
		assert(math.max(math.abs(dq), math.abs(dr), math.abs(dq + dr)) == 1, `{def.Id} is not next to {def.Parent}`)
		table.insert(Upgrades.Children[def.Parent], def)
	end
end

-- Price of going from `level` to `level + 1`.
function Upgrades.cost(def: UpgradeDef, level: number): number
	return math.floor(def.BaseCost * def.CostGrowth ^ level)
end

-- Total price of the next `count` levels from `level`.
function Upgrades.costFor(def: UpgradeDef, level: number, count: number): number
	local total = 0
	for i = 0, count - 1 do
		total += Upgrades.cost(def, level + i)
	end
	return total
end

-- The bonus a node gives at a level.
function Upgrades.bonus(def: UpgradeDef, level: number): number
	return def.PerLevel * level
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

-- Sum of all bonuses for a stat from a player's levels (missing levels count as 0).
function Upgrades.stat(levels: { [string]: number }?, stat: string): number
	if not levels then
		return 0
	end
	local total = 0
	for _, def in Upgrades.ByStat[stat] or {} do
		local level = levels[def.Id]
		if level and level > 0 then
			total += def.PerLevel * math.min(level, def.MaxLevel)
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

-- Why a node can't be bought right now (nil = it can). Doesn't check cash.
function Upgrades.blocked(def: UpgradeDef, levels: { [string]: number }, rebirths: number): string?
	local level = levels[def.Id] or 0
	if level >= def.MaxLevel then
		return "Maxed"
	end
	if def.Parent and (levels[def.Parent] or 0) < 1 then
		return `Buy {Upgrades.ById[def.Parent].Name} first`
	end
	if rebirths < def.RequiredRebirths then
		return `Needs Rebirth {def.RequiredRebirths}`
	end
	return nil
end

return Upgrades
