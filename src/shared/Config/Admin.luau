--!strict
-- Who gets the admin panel (AdminService on the server checks every call; AdminController
-- only builds the panel for these players). Dev's list, 2026-10-29.
local Admin = {}

Admin.Users = { 347852675, 822623546 }

function Admin.isAdmin(userId: number): boolean
	return table.find(Admin.Users, userId) ~= nil
end

-- Limits so a typo can't wreck a save.
Admin.MaxEggs = 100
Admin.MaxPets = 50
Admin.MaxItems = 1000
Admin.MaxBoostMinutes = 24 * 60
Admin.MaxMessage = 200
Admin.MaxPollSeconds = 600

Admin.MaxEventMinutes = 24 * 60

-- Timed events (AdminService). Unit "x" = multiplier, "+" = added amount, nil = no value.
-- Several can run at once; the same kind twice uses the bigger value.
export type EventDef = {
	Name: string,
	Icon: string,
	Unit: string?,
	Default: number,
	Min: number,
	Max: number,
	Minutes: number,
	Blurb: string,
	Order: number,
}
Admin.Events = {
	Luck = { Name = "Egg Luck", Icon = "Icon_Luck", Unit = "x", Default = 10, Min = 1, Max = 1000, Minutes = 15, Order = 1,
		Blurb = "Rarer eggs, mutations and Huge pets" },
	Cash = { Name = "Cash", Icon = "Icon_Cash", Unit = "x", Default = 5, Min = 1, Max = 1000, Minutes = 15, Order = 2,
		Blurb = "Selling and pets earn more" },
	Huge = { Name = "Huge Chance", Icon = "Icon_Star", Unit = "x", Default = 10, Min = 1, Max = 10000, Minutes = 15, Order = 3,
		Blurb = "Huge pets hatch more often" },
	Hatch = { Name = "Hatch Speed", Icon = "Icon_Timer", Unit = "x", Default = 5, Min = 1, Max = 1000, Minutes = 15, Order = 4,
		Blurb = "Eggs planted now grow faster" },
	Speed = { Name = "Walk Speed", Icon = "Icon_Speed", Unit = "+", Default = 20, Min = 1, Max = 200, Minutes = 15, Order = 5,
		Blurb = "Everyone runs faster" },
	Weather = { Name = "Weather", Icon = "Icon_Event", Default = 0, Min = 0, Max = 0, Minutes = 10, Order = 6,
		Blurb = "Any weather or moon" },
	EggRain = { Name = "Egg Rain", Icon = "Icon_Meteor", Default = 0, Min = 0, Max = 0, Minutes = 2, Order = 7,
		Blurb = "Rare eggs fall from the sky" },
	Drops = { Name = "Egg Drops", Icon = "Icon_Egg", Default = 0, Min = 0, Max = 0, Minutes = 5, Order = 8,
		Blurb = "Eggs of one rarity fall all over the map" },
} :: { [string]: EventDef }

-- Personal boosts the panel can give (data.Boosts keys).
Admin.Boosts = { "Luck2x", "Cash2x", "Speed" }

return Admin
