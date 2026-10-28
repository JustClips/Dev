--!strict
-- Potions and other items kept in the inventory (Items tab). Players get them from dust
-- bunnies, daily rewards, playtime gifts and events, and use them from the inventory.
-- Boost potions add time to a personal boost (data.Boosts[Boost] = expiry), so using two
-- in a row stacks the time.

export type ItemDef = {
	Id: string,
	Name: string,
	Description: string,
	Icon: string, -- AssetLibrary image name
	Color: Color3,
	Boost: string?, -- personal boost key it extends
	Minutes: number?,
	HatchSeconds: number?, -- Hatch potion: takes this much off every egg in your incubators
}

local List: { ItemDef } = {
	{
		Id = "LuckPotion",
		Name = "Luck Potion",
		Description = "2x egg luck for 10 min",
		Icon = "Icon_PotionLuck",
		Color = Color3.fromRGB(61, 220, 90),
		Boost = "Luck2x",
		Minutes = 10,
	},
	{
		Id = "CashPotion",
		Name = "Cash Potion",
		Description = "2x cash for 10 min",
		Icon = "Icon_PotionCash",
		Color = Color3.fromRGB(255, 200, 60),
		Boost = "Cash2x",
		Minutes = 10,
	},
	{
		Id = "SpeedPotion",
		Name = "Speed Potion",
		Description = "Run much faster for 10 min",
		Icon = "Icon_PotionSpeed",
		Color = Color3.fromRGB(76, 195, 255),
		Boost = "Speed",
		Minutes = 10,
	},
	{
		Id = "HatchPotion",
		Name = "Hatch Potion",
		Description = "Eggs in your incubators hatch 5 min sooner",
		Icon = "Icon_PotionHatch",
		Color = Color3.fromRGB(255, 120, 230),
		HatchSeconds = 300,
	},
}

local Items = {
	List = List,
	ById = {} :: { [string]: ItemDef },
	-- Speed potion: added to walk speed while active.
	SpeedBonus = 10,
	-- Luck potion multiplier on egg luck.
	LuckMult = 2,
}

for _, def in List do
	Items.ById[def.Id] = def
end

return Items
