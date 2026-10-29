--!strict
-- NPC talk window in the game's own style (instead of Roblox's Dialog bubbles): the
-- speaker's name on a tab, their line typed out letter by letter (tap to skip), and up to
-- four answers as big buttons. Walking away closes it.
--   DialogController:Open("Pet Trader", npcRootPart)
--   DialogController:Say("Hey! Want to sell?", { { text = "Yes", color = GREEN, pick = fn }, ... })
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local Ui = require(Client.Ui)

local DialogController = {}

export type Option = { text: string, color: Color3?, pick: () -> () }

local WALK_AWAY = 16 -- studs from the speaker that close the window
local LETTERS_PER_SECOND = 70
local DEFAULT_COLOR = Color3.fromRGB(39, 43, 52)

local gui: ScreenGui
local nameLabel: TextLabel
local textLabel: TextLabel
local options: Frame
local template: TextButton
local speaker: BasePart? = nil
local typing: Tween? = nil
local token = 0

local function clearOptions()
	for _, child in options:GetChildren() do
		if child:IsA("TextButton") and child ~= template then
			child:Destroy()
		end
	end
end

function DialogController:IsOpen(): boolean
	return gui ~= nil and Ui.isOpen(gui)
end

function DialogController:Open(name: string, at: BasePart?)
	speaker = at
	nameLabel.Text = name
	if not Ui.isOpen(gui) then
		Ui.open("Dialog")
	end
end

function DialogController:Close()
	token += 1
	speaker = nil
	if typing then
		typing:Cancel()
		typing = nil
	end
	clearOptions()
	if Ui.isOpen(gui) then
		Ui.close("Dialog")
	end
end

-- Shows a line and its answers. Answers appear once the line is typed out.
function DialogController:Say(line: string, answers: { Option }?)
	token += 1
	local mine = token
	clearOptions()
	if typing then
		typing:Cancel()
	end
	textLabel.Text = line
	textLabel.MaxVisibleGraphemes = 0
	local length = utf8.len(line) or #line
	local tween = TweenService:Create(textLabel, TweenInfo.new(length / LETTERS_PER_SECOND, Enum.EasingStyle.Linear), { MaxVisibleGraphemes = length })
	typing = tween
	tween:Play()
	Ui.sound("Pop", 1.15)
	for i, answer in answers or {} do
		local button = template:Clone()
		button.Name = "Option" .. i
		button.LayoutOrder = i
		button.BackgroundColor3 = answer.color or DEFAULT_COLOR
		Ui.setText(button, answer.text)
		button.Visible = true
		button.Parent = options
		Ui.button(button, function()
			if token == mine then
				answer.pick()
			end
		end)
	end
end

function DialogController:Init()
	gui = Ui.screen("Dialog")
	nameLabel = Ui.find(gui, "Window.NameTab.Label")
	textLabel = Ui.find(gui, "Window.Text")
	options = Ui.find(gui, "Window.Options")
	template = Ui.find(gui, "Window.Options.Template")
end

function DialogController:Start()
	-- Tap the text to show it all at once.
	Ui.find(gui, "Window.Skip").Activated:Connect(function()
		if typing then
			typing:Cancel()
			typing = nil
			textLabel.MaxVisibleGraphemes = -1
		end
	end)
	RunService.Heartbeat:Connect(function()
		local at = speaker
		if not at or not Ui.isOpen(gui) then
			return
		end
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not at.Parent or (root and (root.Position - at.Position).Magnitude > WALK_AWAY) then
			DialogController:Close()
		end
	end)
end

return DialogController
