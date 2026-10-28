--!strict
-- Cash upgrades bought at the Upgrade Station (or from the HUD). Levels reset on rebirth,
-- like cash and tools. Cost of the next level = BaseCost * CostGrowth ^ level.
local Types = require(script.Parent.Parent.Types)

type UpgradeDef = Types.UpgradeDef

local List: { UpgradeDef } = {
	{
		Id = "Backpack",
		Name = "Bigger Backpack",
		Icon = "Icon_Backpack",
		MaxLevel = 10,
		BaseCost = 300,
		CostGrowth = 2.2,
		PerLevel = 0.25,
		Format = "percent",
		Description = "Carry more leaves per trip",
	},
	{
		Id = "Power",
		Name = "Sweep Power",
		Icon = "Icon_Tool",
		MaxLevel = 10,
		BaseCost = 500,
		CostGrowth = 2.3,
		PerLevel = 0.2,
		Format = "percent",
		Description = "Clear leaves faster",
	},
	{
		Id = "Speed",
		Name = "Running Shoes",
		Icon = "Icon_Speed",
		MaxLevel = 8,
		BaseCost = 400,
		CostGrowth = 2.0,
		PerLevel = 2,
		Format = "plus",
		Description = "Walk faster",
	},
	{
		Id = "Luck",
		Name = "Egg Luck",
		Icon = "Icon_Luck",
		MaxLevel = 10,
		BaseCost = 1_000,
		CostGrowth = 2.5,
		PerLevel = 0.1,
		Format = "percent",
		Description = "Find more and rarer eggs",
	},
}

local Upgrades = {
	List = List,
	ById = {} :: { [string]: UpgradeDef },
	BaseWalkSpeed = 16,
}

for _, def in List do
	Upgrades.ById[def.Id] = def
end

-- Price of going from `level` to `level + 1`.
function Upgrades.cost(def: UpgradeDef, level: number): number
	return math.floor(def.BaseCost * def.CostGrowth ^ level)
end

-- The bonus at a level: a fraction (0.25 = +25%) or a flat amount (walk speed).
function Upgrades.bonus(def: UpgradeDef, level: number): number
	return def.PerLevel * level
end

-- Short text for a bonus, e.g. "+50%" or "+4".
function Upgrades.describe(def: UpgradeDef, level: number): string
	local b = Upgrades.bonus(def, level)
	if def.Format == "percent" then
		return `+{math.floor(b * 100 + 0.5)}%`
	end
	return `+{b}`
end

-- Multipliers from a player's levels (missing levels count as 0).
function Upgrades.multiplier(levels: { [string]: number }?, id: string): number
	local def = Upgrades.ById[id]
	return 1 + Upgrades.bonus(def, (levels and levels[id]) or 0)
end

function Upgrades.walkSpeed(levels: { [string]: number }?): number
	return Upgrades.BaseWalkSpeed + Upgrades.bonus(Upgrades.ById.Speed, (levels and levels.Speed) or 0)
end

return Upgrades
