--!strict
-- Codes window (screen "Codes"), opened from the Codes button in Settings. Type a code from
-- a social post and press Redeem (or Enter). The server checks it (CodeService): each
-- code works once per player, and some expire.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local GREEN = Color3.fromRGB(30, 158, 58)
local RED = Color3.fromRGB(214, 48, 64)
local GREY = Color3.fromRGB(166, 174, 194)
local SUCCESS = Color3.fromRGB(61, 220, 90)

local CodesController = {}

local C: any
local gui: ScreenGui
local input: TextBox
local status: TextLabel
local redeemButton: GuiButton
local busy = false

local function setRedeem(on: boolean)
	redeemButton.BackgroundColor3 = if on then SUCCESS else GREY
	local studs = redeemButton:FindFirstChild("Studs") :: ImageLabel?
	if studs then
		studs.ImageColor3 = redeemButton.BackgroundColor3
	end
end

local function redeem()
	if busy then
		return
	end
	local code = input.Text
	if string.gsub(code, "%s", "") == "" then
		status.Text = "Type a code first"
		status.TextColor3 = RED
		return
	end
	busy = true
	setRedeem(false)
	Ui.setText(redeemButton, "...")
	local ok, message = Net.func("RedeemCode"):InvokeServer(code)
	busy = false
	setRedeem(true)
	Ui.setText(redeemButton, "Redeem")
	status.Text = message or ""
	status.TextColor3 = if ok then GREEN else RED
	if ok then
		input.Text = ""
		Ui.sound("Sell")
		if message and message ~= "" then
			C.HudController:Toast(message, "Good")
		end
	end
end

function CodesController:Toggle()
	Ui.toggle("Codes")
	if Ui.isOpen(gui) then
		status.Text = ""
	end
end

function CodesController:Init(controllers)
	C = controllers
	gui = Ui.screen("Codes")
	input = Ui.find(gui, "Window.Entry.Input") :: TextBox
	status = Ui.find(gui, "Window.Entry.Status") :: TextLabel
	redeemButton = Ui.find(gui, "Window.Redeem") :: GuiButton
end

function CodesController:Start()
	Ui.button(Ui.find(Ui.screen("Settings"), "Window.Codes"), function()
		Ui.open("Codes")
		status.Text = ""
	end)
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Codes")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Codes")
	end)
	Ui.button(redeemButton, redeem)
	input.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			redeem()
		end
	end)
	-- Codes are letters and numbers: keep it upper case so it reads like the post.
	input:GetPropertyChangedSignal("Text"):Connect(function()
		local upper = string.upper(input.Text)
		if upper ~= input.Text then
			input.Text = upper
		end
	end)
end

return CodesController
