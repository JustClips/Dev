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

-- Personal boosts the panel can give (data.Boosts keys).
Admin.Boosts = { "Luck2x", "Cash2x", "Speed" }

return Admin
