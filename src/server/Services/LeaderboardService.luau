--!strict
-- leaderstats (Cash as a formatted string, Rebirths). No overhead tag (Dev: clutter).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)

local REFRESH_SECONDS = 1

local LeaderboardService = {}

local S: any

local function ensureStats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Value = "$0"
	cash.Parent = stats
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = stats
	stats.Parent = player
end

local function refresh(player: Player, data)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		(stats:FindFirstChild("Cash") :: StringValue).Value = Format.cash(data.Cash);
		(stats:FindFirstChild("Rebirths") :: IntValue).Value = data.Rebirths
	end
end

function LeaderboardService:Init(services)
	S = services
	S.DataService.ProfileLoaded:Connect(function(player)
		ensureStats(player)
	end)
end

function LeaderboardService:Start()
	task.spawn(function()
		while true do
			task.wait(REFRESH_SECONDS)
			for player, session in S.DataService:GetSessions() do
				refresh(player, session.Data)
			end
		end
	end)
end

return LeaderboardService
