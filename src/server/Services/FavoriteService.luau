--!strict
-- Asks the player to favorite the game right after a high moment (a Rare+ / Huge / mutated
-- hatch, or a rebirth). The prompt itself is client-only (FavoriteController), so the server
-- only says "now is a good time". Asked at most once per session; once the player answers
-- (favorites or cancels) or already has it favorited, Flags.FavoriteAsked is saved and the
-- prompt never comes back.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local FavoriteService = {}

local S: any
local askedThisSession: { [Player]: boolean } = {}

local ANSWERS = { Favorited = true, Declined = true, AlreadyFavorite = true }

function FavoriteService:Moment(player: Player)
	local data = S.DataService:GetData(player)
	if not data or data.Flags.FavoriteAsked or askedThisSession[player] then
		return
	end
	-- Never during the tutorial (Dev, 2026-10-31): a later high moment asks instead.
	if not data.Flags.TutorialDone then
		return
	end
	askedThisSession[player] = true
	Net.fire("AskFavorite", player)
end

function FavoriteService:Init(services)
	S = services
	Net.onEvent("FavoriteDone", function(player, result)
		if type(result) ~= "string" or not ANSWERS[result] then
			return -- "Failed" (e.g. Studio) is not saved, so a later session can try again
		end
		local data = S.DataService:GetData(player)
		if data then
			data.Flags.FavoriteAsked = true
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		askedThisSession[player] = nil
	end)
end

return FavoriteService
