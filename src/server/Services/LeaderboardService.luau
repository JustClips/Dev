--!strict
-- leaderstats (Cash as a formatted string, Rebirths) and an overhead tag with
-- rebirths and the rarest alien.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AlienModel = require(Shared.AlienModel)
local Aliens = require(Shared.Config.Aliens)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)

local REFRESH_SECONDS = 1

local LeaderboardService = {}

local S: any

local function rarest(data): (string?, Color3)
	local best, bestOrder, bestMutation = nil, 0, nil
	for _, alien in data.Pets do
		local def = Aliens.ById[alien.Id]
		local order = def and Eggs.order(def.Rarity) or 0
		if order > bestOrder or (order == bestOrder and alien.Mutation and not bestMutation) then
			best, bestOrder, bestMutation = alien, order, alien.Mutation
		end
	end
	if not best then
		return nil, Color3.new(1, 1, 1)
	end
	local def = Aliens.ById[best.Id]
	return (if best.Huge then "Huge " else "") .. AlienModel.displayName(best.Id, best.Mutation), Eggs.ByName[def.Rarity].Color
end

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

local function overhead(character: Model)
	local head = character:WaitForChild("Head", 10) :: BasePart?
	if not head then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "OverheadTag"
	billboard.Size = UDim2.fromOffset(200, 46)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.MaxDistance = 80
	billboard.LightInfluence = 0
	local top = Instance.new("TextLabel")
	top.Name = "Top"
	top.Size = UDim2.fromScale(1, 0.5)
	top.BackgroundTransparency = 1
	top.TextScaled = true
	top.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold)
	top.TextColor3 = Color3.fromRGB(255, 220, 90)
	top.TextStrokeTransparency = 0.3
	top.Parent = billboard
	local bottom = top:Clone()
	bottom.Name = "Bottom"
	bottom.Position = UDim2.fromScale(0, 0.5)
	bottom.TextColor3 = Color3.new(1, 1, 1)
	bottom.Parent = billboard
	billboard.Parent = head
end

local function refresh(player: Player, data)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		(stats:FindFirstChild("Cash") :: StringValue).Value = Format.cash(data.Cash);
		(stats:FindFirstChild("Rebirths") :: IntValue).Value = data.Rebirths
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("OverheadTag")
	if tag then
		local vip = if data.Gamepasses.VIP then "VIP · " else ""
		local top = tag:FindFirstChild("Top") :: TextLabel
		local bottom = tag:FindFirstChild("Bottom") :: TextLabel
		top.Text = `{vip}Rebirth {data.Rebirths}`
		local name, color = rarest(data)
		bottom.Text = name or ""
		bottom.TextColor3 = color
	end
end

function LeaderboardService:Init(services)
	S = services
	S.DataService.ProfileLoaded:Connect(function(player)
		ensureStats(player)
	end)
	S.BaseService.CharacterReady:Connect(function(_player, character)
		overhead(character)
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
