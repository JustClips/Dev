--!strict
-- Potions and other items kept in the inventory (Items tab). Players get them from leaf
-- drops (sweeping, Config/Items Drops below), dust bunnies, the Traveling Merchant, daily
-- rewards, playtime gifts and events, and use them from the bag.
--
-- Kinds (what using one does, InventoryService:UseItem):
--   Boost  - adds time to a personal boost (data.Boosts[Boost] = expiry), so two in a row
--            stack the time. The Long Brew upgrade makes them last longer.
--   Hatch  - takes HatchSeconds off every egg in your park.
--   Charm  - your next hatch gets a bonus (data.Flags.Charms[Charm] counts them).
--   Spray  - one growing egg in your park gets a random weather mutation.
--   Bomb   - clears every leaf within Radius studs of you at once.
--   Map    - marks a buried chest in your field (dig it up by sweeping there).
--   Totem  - starts a random weather for the whole server for Minutes.

export type ItemDef = {
	Id: string,
	Name: string,
	Description: string,
	Icon: string, -- AssetLibrary image name
	Color: Color3,
	Kind: string,
	Rarity: string, -- Common .. Legendary: drop colour/beam and how rare it is
	Boost: string?, -- Boost: personal boost key it extends
	Minutes: number?,
	HatchSeconds: number?, -- Hatch: takes this much off every egg in your park
	Charm: string?, -- Charm: "Huge" | "Clover"
	Radius: number?, -- Bomb
}

local List: { ItemDef } = {
	{
		Id = "LuckPotion",
		Name = "Luck Potion",
		Description = "2x egg luck for 10 min",
		Icon = "Icon_PotionLuck",
		Color = Color3.fromRGB(61, 220, 90),
		Kind = "Boost",
		Rarity = "Common",
		Boost = "Luck2x",
		Minutes = 10,
	},
	{
		Id = "CashPotion",
		Name = "Cash Potion",
		Description = "2x cash for 10 min",
		Icon = "Icon_PotionCash",
		Color = Color3.fromRGB(255, 200, 60),
		Kind = "Boost",
		Rarity = "Common",
		Boost = "Cash2x",
		Minutes = 10,
	},
	{
		Id = "SpeedPotion",
		Name = "Speed Potion",
		Description = "Run much faster for 10 min",
		Icon = "Icon_PotionSpeed",
		Color = Color3.fromRGB(76, 195, 255),
		Kind = "Boost",
		Rarity = "Common",
		Boost = "Speed",
		Minutes = 10,
	},
	{
		Id = "HatchPotion",
		Name = "Hatch Potion",
		Description = "Eggs in your park hatch 5 min sooner",
		Icon = "Icon_PotionHatch",
		Color = Color3.fromRGB(255, 120, 230),
		Kind = "Hatch",
		Rarity = "Uncommon",
		HatchSeconds = 300,
	},
	{
		Id = "MagnetPotion",
		Name = "Magnet Potion",
		Description = "Grab coins from much further away for 10 min",
		Icon = "Icon_PotionMagnet",
		Color = Color3.fromRGB(255, 90, 90),
		Kind = "Boost",
		Rarity = "Common",
		Boost = "Magnet",
		Minutes = 10,
	},
	{
		Id = "LeafPotion",
		Name = "Leaf Potion",
		Description = "2x leaves from every pile for 10 min",
		Icon = "Icon_PotionLeaf",
		Color = Color3.fromRGB(139, 224, 78),
		Kind = "Boost",
		Rarity = "Uncommon",
		Boost = "Leaf2x",
		Minutes = 10,
	},
	{
		Id = "BigBagPotion",
		Name = "Big Bag Potion",
		Description = "+50% bag space for 15 min",
		Icon = "Icon_PotionBag",
		Color = Color3.fromRGB(255, 154, 60),
		Kind = "Boost",
		Rarity = "Uncommon",
		Boost = "BigBag",
		Minutes = 15,
	},
	{
		Id = "SuperLuckPotion",
		Name = "Super Luck Potion",
		Description = "3x egg luck for 15 min",
		Icon = "Icon_PotionSuperLuck",
		Color = Color3.fromRGB(40, 200, 160),
		Kind = "Boost",
		Rarity = "Rare",
		Boost = "Luck3x",
		Minutes = 15,
	},
	{
		Id = "MegaCashPotion",
		Name = "Mega Cash Potion",
		Description = "3x cash for 15 min",
		Icon = "Icon_PotionMegaCash",
		Color = Color3.fromRGB(255, 176, 32),
		Kind = "Boost",
		Rarity = "Rare",
		Boost = "Cash3x",
		Minutes = 15,
	},
	{
		Id = "LeafBomb",
		Name = "Leaf Bomb",
		Description = "Clears every leaf around you at once",
		Icon = "Icon_LeafBomb",
		Color = Color3.fromRGB(255, 77, 94),
		Kind = "Bomb",
		Rarity = "Rare",
		Radius = 26,
	},
	{
		Id = "TreasureMap",
		Name = "Treasure Map",
		Description = "Marks a buried chest in your field. Sweep there to dig it up!",
		Icon = "Icon_TreasureMap",
		Color = Color3.fromRGB(242, 196, 141),
		Kind = "Map",
		Rarity = "Rare",
	},
	{
		Id = "LuckyClover",
		Name = "Lucky Clover",
		Description = "Your next hatch is 3x more likely to go up a rarity",
		Icon = "Icon_LuckyClover",
		Color = Color3.fromRGB(47, 168, 79),
		Kind = "Charm",
		Rarity = "Epic",
		Charm = "Clover",
	},
	{
		Id = "MutationSpray",
		Name = "Mutation Spray",
		Description = "Gives one growing egg in your park a random weather mutation",
		Icon = "Icon_MutationSpray",
		Color = Color3.fromRGB(170, 90, 255),
		Kind = "Spray",
		Rarity = "Epic",
	},
	{
		Id = "HugeCharm",
		Name = "Huge Charm",
		Description = "Your next hatch is 10x more likely to be Huge",
		Icon = "Icon_HugeCharm",
		Color = Color3.fromRGB(255, 200, 40),
		Kind = "Charm",
		Rarity = "Legendary",
		Charm = "Huge",
	},
	{
		Id = "WeatherTotem",
		Name = "Weather Totem",
		Description = "Calls a lucky weather for the whole server for 5 min",
		Icon = "Icon_WeatherTotem",
		Color = Color3.fromRGB(76, 141, 255),
		Kind = "Totem",
		Rarity = "Legendary",
		Minutes = 5,
	},
}

-- Leaf drops (SweepService): each leaf pile you clear has DropChance (plus the Lucky Finds
-- upgrades) to drop something on the ground, Slime RNG style. Walk over it to pick it up.
-- About 6 piles a second on a phone, so a drop every ~3.5 min with no upgrades. Most
-- drops are coin pouches (Seconds of your earnings) and helper potions. Potions that
-- multiply your cash (Cash, Mega Cash, Leaf, Big Bag) never drop: they come from the
-- merchant, rewards and the wheel, so they stay a treat (Dev, 2026-10-30: balanced, not a
-- permanent 2x). At most one drop every DropGap seconds, so big tools that clear hundreds
-- of piles don't rain potions.
export type Drop = { Item: string?, Cash: number?, Weight: number }
local Drops: { Drop } = {
	{ Cash = 10, Weight = 600 }, -- coin pouch: 10 s of your earnings
	{ Item = "LuckPotion", Weight = 25 },
	{ Item = "SpeedPotion", Weight = 30 },
	{ Item = "MagnetPotion", Weight = 30 },
	{ Item = "HatchPotion", Weight = 15 },
	{ Item = "SuperLuckPotion", Weight = 3 },
	{ Item = "LeafBomb", Weight = 20 },
	{ Item = "TreasureMap", Weight = 15 },
	{ Item = "LuckyClover", Weight = 6 },
	{ Item = "MutationSpray", Weight = 6 },
	{ Item = "HugeCharm", Weight = 1.5 },
	{ Item = "WeatherTotem", Weight = 1.5 },
}

-- Colours per rarity (same as the egg rarities), for drops, cards and toasts.
local RarityColors: { [string]: Color3 } = {
	Common = Color3.fromRGB(190, 190, 190),
	Uncommon = Color3.fromRGB(90, 220, 110),
	Rare = Color3.fromRGB(70, 150, 255),
	Epic = Color3.fromRGB(170, 90, 255),
	Legendary = Color3.fromRGB(255, 200, 40),
}

local Items = {
	List = List,
	ById = {} :: { [string]: ItemDef },
	Drops = Drops,
	RarityColors = RarityColors,
	DropChance = 1 / 1200, -- per leaf pile cleared, before the Lucky Finds upgrades
	DropSeconds = 45, -- a drop left on the ground this long is picked up for you
	DropGap = 15, -- seconds between two drops for one player, at least
	-- Boost strengths.
	SpeedBonus = 10, -- Speed potion: added to walk speed
	LuckMult = 2, -- Luck2x
	SuperLuckMult = 3, -- Luck3x
	MegaCashMult = 3, -- Cash3x (Cash2x is Economy.Cash2xBoostMult)
	LeafMult = 2, -- Leaf2x: leaves per pile
	BigBagMult = 1.5, -- BigBag: bag space
	MagnetBonus = 14, -- Magnet: extra coin pickup range, studs
	HugeCharmMult = 10,
	CloverLuck = 9, -- luck on the rarity roll (step-up odds grow with its square root: 3x)
	-- Weathers a Weather Totem can call (all with a luck or cash bonus).
	TotemWeathers = { "Rainbow", "GoldenHour", "Aurora", "Starfall", "Disco" },
}

for _, def in List do
	Items.ById[def.Id] = def
end

local dropTotal = 0
for _, drop in Drops do
	assert(drop.Cash or Items.ById[drop.Item or ""], `bad drop {drop.Item}`)
	dropTotal += drop.Weight
end

-- Picks one leaf drop.
function Items.rollDrop(rng: Random): Drop
	local roll = rng:NextNumber() * dropTotal
	for _, drop in Drops do
		roll -= drop.Weight
		if roll <= 0 then
			return drop
		end
	end
	return Drops[1]
end

-- Picks a random item (no coin pouches), with the drop weights. maxRarity limits it.
function Items.rollItem(rng: Random, maxRarity: string?): ItemDef
	local order = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }
	local cap = order[maxRarity or "Legendary"] or 5
	local pool, total = {}, 0
	for _, drop in Drops do
		local def = drop.Item and Items.ById[drop.Item]
		if def and (order[def.Rarity] or 1) <= cap then
			table.insert(pool, { def = def, weight = drop.Weight })
			total += drop.Weight
		end
	end
	local roll = rng:NextNumber() * total
	for _, entry in pool do
		roll -= entry.weight
		if roll <= 0 then
			return entry.def
		end
	end
	return pool[1].def
end

return Items
