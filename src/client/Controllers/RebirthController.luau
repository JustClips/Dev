--!strict
-- Rebirth screen: cost, multiplier now -> after, rebirth button and the Robux skip.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)

local RebirthController = {}

local C: any
local gui: ScreenGui
local multLabel: TextLabel
local costLabel: TextLabel
local rebirthButton: TextButton
local skipButton: TextButton

local function skipKey(): string
	local skip = State.data and Products.skipRebirthFor(State.data.Rebirths)
	return if skip then skip.Key else "SkipRebirth"
end

local function render()
	local data = State.data
	if not data then
		return
	end
	local now = 1 + data.Rebirths * Economy.RebirthCashBonus
	local after = now + Economy.RebirthCashBonus
	multLabel.Text = `Cash x{now} → x{after}`
	local affordable = BigNum.gte(data.Cash, data.RebirthCost)
	costLabel.Text = `Cost: {Format.cash(data.RebirthCost)}  (you have {Format.cash(data.Cash)})`
	-- Can't afford: the price turns red, the button goes grey.
	costLabel.TextColor3 = if affordable then Color3.fromRGB(27, 31, 58) else Color3.fromRGB(255, 77, 94)
	rebirthButton.BackgroundColor3 = if affordable then Color3.fromRGB(61, 220, 90) else Color3.fromRGB(166, 174, 194)
	-- The skip price grows with each rebirth (Products.skipRebirthFor).
	local skip = Products.skipRebirthFor(data.Rebirths)
	skipButton.Visible = skip ~= nil
	if skip then
		Ui.setText(skipButton, `Skip for {Ui.ROBUX} {skip.Price}`)
	end
end

function RebirthController:Toggle()
	Ui.toggle("Rebirth")
	render()
end

function RebirthController:Init(controllers)
	C = controllers
	gui = Ui.screen("Rebirth")
	multLabel = Ui.find(gui, "Window.Mult")
	costLabel = Ui.find(gui, "Window.Cost")
	rebirthButton = Ui.find(gui, "Window.RebirthButton")
	skipButton = Ui.find(gui, "Window.SkipButton")
end

function RebirthController:Start()
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Rebirth")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Rebirth")
	end)
	Ui.button(rebirthButton, function()
		local ok, message = Net.func("Rebirth"):InvokeServer()
		C.HudController:Toast(message or "", if ok then "Good" else "Bad")
		if ok then
			Ui.close("Rebirth")
		end
	end)
	Ui.button(skipButton, function()
		local ok, message = Net.func("PromptPurchase"):InvokeServer(skipKey())
		if not ok and message then
			C.HudController:Toast(message, "Bad")
		end
	end)
	State.Changed:Connect(function()
		if gui.Enabled then
			render()
		end
	end)
end

return RebirthController
