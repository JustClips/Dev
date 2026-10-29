--!strict
-- Gives each player one of the 8 base plots and spawns their character there.
-- Characters only load after the profile loaded (DataService turns off CharacterAutoLoads).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Signal = require(Shared.Signal)
local Avatar = require(script.Parent.Parent.Lib.Avatar)

local BaseService = {
	CharacterReady = Signal.new() :: Signal.Signal<Player, Model>,
}

local S: any
local owners: { [number]: Player } = {}

local function freeIndex(): number?
	for i = 1, Zones.BaseCount do
		if not owners[i] then
			return i
		end
	end
	return nil
end

function BaseService:GetBaseIndex(player: Player): number?
	local session = S.DataService:GetSession(player)
	return if session then session.Runtime.BaseIndex else nil
end

function BaseService:GetOwner(index: number): Player?
	return owners[index]
end

local function onCharacter(player: Player, character: Model)
	Avatar.setGroup(character, Avatar.PlayerGroup)
	local index = BaseService:GetBaseIndex(player)
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if index and root then
		task.defer(function()
			character:PivotTo(S.WorldService:GetSpawnCFrame(index))
		end)
	end
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		Avatar.noToolsWhileDriving(character, humanoid)
		humanoid.Died:Connect(function()
			task.wait(Players.RespawnTime)
			if player.Parent and S.DataService:GetSession(player) then
				Avatar.loadCharacter(player)
			end
		end)
	end
	BaseService.CharacterReady:Fire(player, character)
end

function BaseService:Init(services)
	S = services
	Avatar.setupGroups()
	Players.PlayerAdded:Connect(Avatar.prefetch)
	for _, player in Players:GetPlayers() do
		Avatar.prefetch(player)
	end
	S.DataService.ProfileLoaded:Connect(function(player: Player, session)
		local index = freeIndex()
		if not index then
			-- Server size is 8, so this should never happen.
			player:Kick("This server is full. Please join another one!")
			return
		end
		owners[index] = player
		session.Runtime.BaseIndex = index
		player:SetAttribute("BaseIndex", index)
		S.WorldService:SetOwnerName(index, player.DisplayName, player.UserId)

		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		Avatar.loadCharacter(player)
	end)
	S.DataService.ProfileReleasing:Connect(function(player: Player, session)
		local index = session.Runtime.BaseIndex
		if index and owners[index] == player then
			owners[index] = nil
			S.WorldService:SetOwnerName(index, nil)
		end
	end)
	-- Safety net: whatever happened to the save, a player who left never keeps a base.
	Players.PlayerRemoving:Connect(function(player: Player)
		task.defer(function()
			for index, owner in owners do
				if owner == player then
					owners[index] = nil
					S.WorldService:SetOwnerName(index, nil)
				end
			end
		end)
	end)
end

return BaseService
