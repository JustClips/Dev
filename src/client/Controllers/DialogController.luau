--!strict
-- NPC talk window in the game's own style (instead of Roblox's Dialog bubbles): the
-- speaker's name on a tab, their line typed out letter by letter (tap to skip), and up to
-- four answers as big buttons. Walking away closes it.
--   DialogController:Open("Pet Trader", npcRootPart)
--   DialogController:Say("Hey! Want to sell?", { { text = "Yes", color = GREEN, pick = fn }, ... })
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local Ui = require(Client.Ui)

local DialogController = {}

export type Option = { text: string, color: Color3?, pick: () -> () }

local WALK_AWAY = 16 -- studs from the speaker that close the window
local LETTERS_PER_SECOND = 70
local DEFAULT_COLOR = Color3.fromRGB(39, 43, 52)
-- Window layout (unscaled px; the window's UIScale handles screen size). The window grows
-- from its bottom edge to fit the line plus however many answer rows there are.
local PAD_TOP = 18 -- room under the name tab
local PAD_SIDE = 14
local PAD_BOTTOM = 12
local GAP = 12 -- between the line and the answers
local ROW = 36
local ROW_GAP = 8
local MIN_TEXT = 20

local gui: ScreenGui
local nameLabel: TextLabel
local textLabel: TextLabel
local options: Frame
local template: TextButton
local speaker: BasePart? = nil
local typing: Tween? = nil
local token = 0
local window: Frame
local skip: GuiButton

-- Height the line needs when wrapped to the window's width.
local function textHeight(line: string): number
	if line == "" then
		return 0
	end
	local width = window.Size.X.Offset - PAD_SIDE * 2
	local params = Instance.new("GetTextBoundsParams")
	params.Text = line
	params.Font = textLabel.FontFace
	params.Size = textLabel.TextSize
	params.Width = width
	local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
	if ok then
		return math.ceil((bounds :: Vector2).Y) + 2
	end
	-- Rough fallback: about 0.55 of the text size per letter.
	local perLine = math.max(1, math.floor(width / (textLabel.TextSize * 0.55)))
	return math.ceil((utf8.len(line) or #line) / perLine) * (textLabel.TextSize + 4)
end

-- Sizes the window to the line and the answers: one column for a single answer (centred),
-- two columns otherwise, and no empty band when there are no answers at all.
local function fit(line: string, count: number)
	local textH = math.max(textHeight(line), MIN_TEXT)
	local rows = math.ceil(count / 2)
	local optionsH = if rows > 0 then rows * ROW + (rows - 1) * ROW_GAP else 0
	local height = PAD_TOP + textH + (if rows > 0 then GAP + optionsH else 0) + PAD_BOTTOM
	textLabel.Size = UDim2.new(1, -PAD_SIDE * 2, 0, textH)
	textLabel.Position = UDim2.fromOffset(PAD_SIDE, PAD_TOP)
	skip.Size = UDim2.new(1, 0, 0, PAD_TOP + textH)
	options.Size = UDim2.new(1, -24, 0, optionsH)
	options.Position = UDim2.new(0, 12, 1, -PAD_BOTTOM)
	options.Visible = rows > 0
	window.Size = UDim2.fromOffset(window.Size.X.Offset, height)
end

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
	local count = if answers then #answers else 0
	fit(line, count)
	if token ~= mine then
		return -- another line came in while measuring this one
	end
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
	window = Ui.find(gui, "Window")
	skip = Ui.find(gui, "Window.Skip")
	textLabel.TextScaled = false
	textLabel.TextWrapped = true
end

function DialogController:Start()
	-- Tap the text to show it all at once.
	skip.Activated:Connect(function()
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
