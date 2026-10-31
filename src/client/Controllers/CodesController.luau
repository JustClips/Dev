--!strict
-- Codes: the box at the end of the Shop (Dev, 2026-10-31: moved there from Settings; the
-- Shop's Codes button jumps to it). Type a code from a social post and press Redeem (or Enter). The server checks it (CodeService): each
-- code works once per player, and some expire.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local GREY = Color3.fromRGB(166, 174, 194)
local SUCCESS = Color3.fromRGB(61, 220, 90)

local CodesController = {}

local C: any
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

local HINT = ""
local WHITE = Color3.new(1, 1, 1)

local function redeem()
	if busy then
		return
	end
	local code = input.Text
	if string.gsub(code, "%s", "") == "" then
		status.Text = "Type a code first"
		status.TextColor3 = Color3.fromRGB(255, 120, 130)
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
	status.TextColor3 = if ok then Color3.fromRGB(140, 255, 150) else Color3.fromRGB(255, 120, 130)
	if ok then
		input.Text = ""
		Ui.sound("Sell")
		if message and message ~= "" then
			C.HudController:Toast(message, "Good")
		end
	end
end

-- Opens the Shop at the codes box.
function CodesController:Open()
	status.Text = HINT
	status.TextColor3 = WHITE
	C.ShopController:Open("Codes")
end

function CodesController:Init(controllers)
	C = controllers
	local box = Ui.find(Ui.screen("Shop"), "Window.Panel.List.CodesBox")
	input = Ui.find(box, "Input") :: TextBox
	status = Ui.find(box, "Status") :: TextLabel
	redeemButton = Ui.find(box, "Redeem") :: GuiButton
end

function CodesController:Start()
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
