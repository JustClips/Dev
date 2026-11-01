--!strict
-- Base skins (Shop > Bases). A skin swaps the look of a player's whole base: deck, walls,
-- corner pillars, arch, egg pad, incubators, lamps, pet house, park fence and decor.
-- Skins are visual only: the classic base stays in place (invisible) for every collision,
-- so gameplay positions never move. Models: art/blender/base_skins.py -> Skin_<Id>.glb.
--
-- Unlocks are free once the requirements are met (no cash or Robux price):
--   Rebirths    rebirths done
--   Pets        pet ids that must be in your Index (hatched at least once)
--   IndexCount  how many pets your Index must hold in total
--   AnyCosmic   at least one Cosmic pet in your Index

export type Requirements = {
	Rebirths: number,
	Pets: { string },
	IndexCount: number,
	AnyCosmic: boolean?,
}

export type SkinDef = {
	Id: string,
	Name: string,
	Desc: string,
	Asset: string?, -- nil = the classic base (no model)
	Color: Color3, -- card colour and Pet Trader awning
	SignLift: number, -- extra height for the name sign over this skin's arch
	Image: string?, -- Assets.Images name for the shop card
	Requires: Requirements,
}

local List: { SkinDef } = {
	{
		Id = "Classic",
		Name = "Classic",
		Desc = "The cosy wooden base every player starts with.",
		Color = Color3.fromRGB(196, 142, 92),
		SignLift = 0,
		Image = "BaseSkin_Classic",
		Requires = { Rebirths = 0, Pets = {}, IndexCount = 0 },
	},
	{
		Id = "Autumn",
		Name = "Autumn Harvest",
		Desc = "Red barn, maple trees, pumpkin lanterns and leaf piles everywhere.",
		Asset = "Skin_Autumn",
		Color = Color3.fromRGB(242, 140, 40),
		SignLift = 1.2,
		Image = "BaseSkin_Autumn",
		Requires = { Rebirths = 1, Pets = { "Squirrel", "Raccoon", "Fox" }, IndexCount = 10 },
	},
	{
		Id = "Tiki",
		Name = "Tiki Beach",
		Desc = "Tiki totem arch, stilt hut, bamboo walls, torches and palm trees.",
		Asset = "Skin_Tiki",
		Color = Color3.fromRGB(46, 196, 201),
		SignLift = 2.2,
		Image = "BaseSkin_Tiki",
		Requires = { Rebirths = 2, Pets = { "Crab", "Seagull", "Dolphin" }, IndexCount = 18 },
	},
	{
		Id = "Halloween",
		Name = "Halloween Night",
		Desc = "Haunted house, glowing cauldrons, graveyard, ghosts and jack-o-lanterns.",
		Asset = "Skin_Halloween",
		Color = Color3.fromRGB(142, 68, 217),
		SignLift = 4.0,
		Image = "BaseSkin_Halloween",
		Requires = { Rebirths = 3, Pets = { "Raccoon", "Owl", "Rat" }, IndexCount = 22 },
	},
	{
		Id = "Winter",
		Name = "Winter Lodge",
		Desc = "Snowy log cabin, icicle arch, frozen pond and snowmen with lanterns.",
		Asset = "Skin_Winter",
		Color = Color3.fromRGB(110, 170, 230),
		SignLift = 2.0,
		Image = "BaseSkin_Winter",
		Requires = { Rebirths = 4, Pets = { "Penguin", "Owl", "ArcticWolf", "SnowLeopard" }, IndexCount = 26 },
	},
	{
		Id = "Candy",
		Name = "Candy Kingdom",
		Desc = "Candy-cane arch, cake egg pad, cupcake incubators and a gingerbread house.",
		Asset = "Skin_Candy",
		Color = Color3.fromRGB(255, 92, 158),
		SignLift = 2.2,
		Image = "BaseSkin_Candy",
		Requires = { Rebirths = 6, Pets = { "Bunny", "Unicorn", "Kitsune", "Peacock" }, IndexCount = 34 },
	},
	{
		Id = "Castle",
		Name = "Castle Keep",
		Desc = "A gatehouse with towers, a royal egg dais, a round keep and a fountain.",
		Asset = "Skin_Castle",
		Color = Color3.fromRGB(58, 91, 217),
		SignLift = 7.5,
		Image = "BaseSkin_Castle",
		Requires = { Rebirths = 8, Pets = { "Dragon", "Griffin", "Gargoyle" }, IndexCount = 40, AnyCosmic = true },
	},
}

local BaseSkins = {
	List = List,
	ById = {} :: { [string]: SkinDef },
	Default = "Classic",
}

for _, skin in List do
	BaseSkins.ById[skin.Id] = skin
end

export type Progress = {
	Met: boolean,
	Rebirths: number,
	IndexCount: number,
	Pets: { [string]: boolean },
	HasCosmic: boolean,
}

-- How far a player is toward a skin. `rarityOf` maps a pet id to its rarity (Config/Aliens),
-- passed in so this module stays free of requires (client and server both use it).
function BaseSkins.progress(def: SkinDef, rebirths: number, index: { [string]: boolean }, rarityOf: (string) -> string?): Progress
	local count, cosmic = 0, false
	for id, found in index do
		if found then
			count += 1
			if rarityOf(id) == "Cosmic" then
				cosmic = true
			end
		end
	end
	local req = def.Requires
	local pets = {}
	local met = rebirths >= req.Rebirths and count >= req.IndexCount and (not req.AnyCosmic or cosmic)
	for _, id in req.Pets do
		pets[id] = index[id] == true
		if not pets[id] then
			met = false
		end
	end
	return { Met = met, Rebirths = rebirths, IndexCount = count, Pets = pets, HasCosmic = cosmic }
end

return BaseSkins
