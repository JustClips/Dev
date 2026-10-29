--!strict
-- Player avatars and cars in the world:
--   * Avatars spawn no bigger than the default Roblox size (height, width, depth and head
--     scale at most 100%, classic proportions), so cars, roofs and tool animations, which
--     are all made for that size, fit everyone.
--   * Players and cars never collide with other players or cars (collision groups); they
--     still collide with the map.
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local Avatar = {}

Avatar.PlayerGroup = "Players"
Avatar.VehicleGroup = "Vehicles"

-- Largest value allowed for each HumanoidDescription scale.
local MAX_SCALE = {
	HeightScale = 1,
	WidthScale = 1,
	DepthScale = 1,
	HeadScale = 1,
	BodyTypeScale = 0, -- Rthro bodies are taller; 0 keeps classic proportions
	ProportionScale = 0,
}

function Avatar.setupGroups()
	pcall(function()
		for _, group in { Avatar.PlayerGroup, Avatar.VehicleGroup } do
			if not PhysicsService:IsCollisionGroupRegistered(group) then
				PhysicsService:RegisterCollisionGroup(group)
			end
		end
		PhysicsService:CollisionGroupSetCollidable(Avatar.PlayerGroup, Avatar.PlayerGroup, false)
		PhysicsService:CollisionGroupSetCollidable(Avatar.PlayerGroup, Avatar.VehicleGroup, false)
		PhysicsService:CollisionGroupSetCollidable(Avatar.VehicleGroup, Avatar.VehicleGroup, false)
	end)
end

-- Puts every part of a model (and parts added later, like accessories) in a group.
function Avatar.setGroup(model: Instance, group: string)
	local function apply(d: Instance)
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
	for _, d in model:GetDescendants() do
		apply(d)
	end
	model.DescendantAdded:Connect(apply)
end

local function clamp(description: HumanoidDescription)
	for key, max in MAX_SCALE do
		local value = (description :: any)[key] :: number
		if value > max then
			(description :: any)[key] = max
		end
	end
end

local cache: { [Player]: HumanoidDescription } = setmetatable({}, { __mode = "k" }) :: any
local fetching: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local FETCH_WAIT = 4 -- seconds a spawn waits for the avatar before using the plain one

-- Fetches the player's avatar in the background (called on join, while the save loads), so
-- spawning doesn't wait on the web request.
function Avatar.prefetch(player: Player)
	if cache[player] or fetching[player] then
		return
	end
	fetching[player] = true
	task.spawn(function()
		local ok, fetched = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(player.UserId)
		end)
		if ok and fetched then
			clamp(fetched)
			cache[player] = fetched
		end
		fetching[player] = nil
	end)
end

-- Spawns the player's character with their avatar clamped to the default size. Falls back
-- to a plain LoadCharacter when the avatar can't be fetched (Studio test players, outages).
function Avatar.loadCharacter(player: Player)
	Avatar.prefetch(player)
	local deadline = os.clock() + FETCH_WAIT
	while fetching[player] and os.clock() < deadline do
		task.wait(0.1)
	end
	if player.Parent == nil then
		return
	end
	local description = cache[player]
	if description then
		local loaded = pcall(function()
			player:LoadCharacterWithHumanoidDescription(description:Clone())
		end)
		if loaded then
			return
		end
	end
	player:LoadCharacter()
end

return Avatar
