--!strict
-- Free reward window (screen "GroupReward"), opened from the Free pill at the top. Join
-- the group (Roblox's in-game join prompt) and claim 2 Luck Potions + cash, once. A
-- separate strip asks players to like and favorite the game; that part gives nothing
-- (Roblox doesn't allow rewards for likes/favorites, or wording that hints at one).
-- Hidden while Config/Rewards Group.Id is 0, and the pill goes away once claimed.
local AvatarEditorService = game:GetService("AvatarEditorService")
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Rewards = require(Shared.Config.Rewards)

local GroupRewardController = {}

local GREEN = Color3.fromRGB(61, 220, 90)
local GREY = Color3.fromRGB(166, 174, 194)

local C: any
local gui: ScreenGui
local pill: GuiButton
local lastShown: boolean? = nil

local function act(action: string): boolean
	local ok, message = Net.func("Rewards"):InvokeServer(action)
	if message and message ~= "" then
		C.HudController:Toast(message, if ok then "Good" else "Bad")
	end
	return ok
end

local function render()
	local info = State.data and State.data.Rewards
	if not info then
		return
	end
	local on = info.GroupId ~= 0
	local show = on and not info.GroupClaimed
	pill.Visible = show
	Ui.setBadge(pill:FindFirstChild("Badge") :: GuiObject, if show then 1 else nil)
	if show ~= lastShown then
		lastShown = show
		C.HudController:Relayout()
	end
	local claim = Ui.find(gui, "Window.Join.Claim") :: GuiButton
	Ui.setText(claim, if info.GroupClaimed then "Claimed" else "Claim")
	claim.BackgroundColor3 = if info.GroupClaimed then GREY else GREEN
	;(Ui.find(gui, "Window.Note") :: TextLabel).Text = if info.GroupClaimed
		then "Thanks for being in the group!"
		else "Already in the group? Just press Claim."
end

function GroupRewardController:Open()
	Ui.open("GroupReward")
	render()
end

function GroupRewardController:Init(controllers)
	C = controllers
	gui = Ui.screen("GroupReward")
end

function GroupRewardController:Start()
	pill = Ui.find(Ui.screen("Hud"), "Pills.FreeButton")
	Ui.button(pill, function()
		if Ui.isOpen(gui) then
			Ui.close("GroupReward")
		else
			GroupRewardController:Open()
		end
	end)
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("GroupReward")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("GroupReward")
	end)
	Ui.button(Ui.find(gui, "Window.Join.Claim"), function()
		act("ClaimGroup")
	end)
	Ui.button(Ui.find(gui, "Window.Join.JoinButton"), function()
		if Rewards.Group.Id == 0 then
			return
		end
		-- Roblox's own join prompt; claim right away if they joined.
		task.spawn(function()
			local ok, status = pcall(function()
				return GroupService:PromptJoinAsync(Rewards.Group.Id)
			end)
			if ok and (status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember) then
				act("ClaimGroup")
			elseif ok and status == Enum.GroupMembershipStatus.JoinRequestPending then
				C.HudController:Toast("Join request sent! Claim once you're in.", "Good")
			end
		end)
	end)
	Ui.button(Ui.find(gui, "Window.Support.Favorite"), function()
		pcall(function()
			AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
		end)
	end)
	State.Changed:Connect(render)
	render()
end

return GroupRewardController
