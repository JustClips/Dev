--!strict
-- Free reward window (screen "GroupReward"), opened from the Free tile in the More menu: the
-- reward and a Claim button (Dev, 2026-10-31). Claim gives 2 Luck Potions + cash once; when
-- you're not in the group yet it brings up Roblox's join prompt first and claims after.
-- Only group membership is rewarded (Roblox doesn't allow rewards for likes/favorites).
-- Hidden while Config/Rewards Group.Id is 0, and the pill goes away once claimed.
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
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
	-- Hidden during the tutorial (HudController shows only what the tutorial needs).
	local data = State.data
	local inTutorial = data ~= nil and data.TutorialStep ~= "Done" and (data.Rebirths or 0) == 0
	local show = on and not info.GroupClaimed and not inTutorial
	pill.Visible = show
	Ui.setBadge(pill:FindFirstChild("Badge") :: GuiObject, if show then 1 else nil)
	if show ~= lastShown then
		lastShown = show
		C.HudController:Relayout()
	end
	local claim = Ui.find(gui, "Window.Claim") :: GuiButton
	Ui.setText(claim, if info.GroupClaimed then "Claimed" else "Claim")
	claim.BackgroundColor3 = if info.GroupClaimed then GREY else GREEN
end

function GroupRewardController:Open()
	Ui.open("GroupReward")
	render()
end

function GroupRewardController:Init(controllers)
	C = controllers
	gui = Ui.screen("GroupReward")
	-- Studio places synced before the 2026-10-31 slim-down still hold the old parts.
	local window = gui:FindFirstChild("Window")
	for _, name in { "Join", "Support", "Note" } do
		local stale = window and window:FindFirstChild(name)
		if stale then
			stale:Destroy()
		end
	end
end

function GroupRewardController:Start()
	pill = Ui.find(Ui.screen("Hud"), "MoreMenu.Items.FreeButton")
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
	-- Claim: in the group already -> claimed. Not yet -> Roblox's join prompt, then claim.
	local busy = false
	Ui.button(Ui.find(gui, "Window.Claim"), function()
		local info = State.data and State.data.Rewards
		if busy or Rewards.Group.Id == 0 or (info and info.GroupClaimed) then
			return
		end
		busy = true
		task.spawn(function()
			local inGroup = false
			pcall(function()
				inGroup = Players.LocalPlayer:IsInGroup(Rewards.Group.Id)
			end)
			if not inGroup then
				local ok, status = pcall(function()
					return GroupService:PromptJoinAsync(Rewards.Group.Id)
				end)
				inGroup = ok and (status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember)
				if ok and status == Enum.GroupMembershipStatus.JoinRequestPending then
					C.HudController:Toast("Join request sent! Claim once you're in.", "Good")
				end
			end
			if inGroup then
				act("ClaimGroup")
			end
			busy = false
		end)
	end)
	State.Changed:Connect(render)
	render()
end

return GroupRewardController
