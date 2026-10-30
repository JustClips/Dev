--!strict
-- The "favorite this game?" prompt. The server sends AskFavorite right after a high moment
-- (FavoriteService). We wait for the hatch show and any open window to finish, give the player
-- a second to enjoy the pet, then show Roblox's favorite prompt. Whatever they answer is sent
-- back once and saved, so it never shows again.
local AvatarEditorService = game:GetService("AvatarEditorService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local WAIT_LIMIT = 60 -- give up on this moment if the screen stays busy this long
local BREATHER = 1.2 -- seconds after the reveal before the prompt

local FavoriteController = {}

local C: any
local asking = false

local function screenBusy(): boolean
	return C.HatchController:IsBusy() or Ui.anyWindowOpen() or Ui.screen("Hatch").Enabled
end

local function ask()
	if asking or game.PlaceId == 0 then
		return
	end
	asking = true
	local started = os.clock()
	repeat
		task.wait(0.5)
		if os.clock() - started > WAIT_LIMIT then
			asking = false
			return
		end
	until not screenBusy()
	task.wait(BREATHER)

	local okFav, isFavorite = pcall(function()
		return AvatarEditorService:GetFavorite(game.PlaceId, Enum.AvatarItemType.Asset)
	end)
	if okFav and isFavorite then
		Net.event("FavoriteDone"):FireServer("AlreadyFavorite")
		return
	end

	local connection: RBXScriptConnection = nil :: any
	connection = AvatarEditorService.PromptSetFavoriteCompleted:Connect(function(result)
		connection:Disconnect()
		local answer = if result == Enum.AvatarPromptResult.Success
			then "Favorited"
			elseif result == Enum.AvatarPromptResult.PermissionDenied then "Declined"
			else "Failed"
		Net.event("FavoriteDone"):FireServer(answer)
		if answer == "Favorited" then
			C.HudController:Toast("Thanks for the favorite!", "Good")
		end
	end)
	local ok = pcall(function()
		AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
	end)
	if not ok then
		connection:Disconnect()
	end
end

function FavoriteController:Init(controllers)
	C = controllers
end

function FavoriteController:Start()
	Net.event("AskFavorite").OnClientEvent:Connect(function()
		task.spawn(ask)
	end)
end

return FavoriteController
