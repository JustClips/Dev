--!strict
-- Shows the server's contextual offers and the "welcome back" offline income screen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)

local AUTO_HIDE_SECONDS = 15

local OfferController = {}

local C: any
local offerGui: ScreenGui
local welcomeGui: ScreenGui
local current: { Key: string, Product: string }? = nil
local showToken = 0

local function hideOffer(clicked: boolean)
	if current then
		Net.event("OfferResponse"):FireServer(current.Key, clicked)
		current = nil
	end
	offerGui.Enabled = false
end

local function prompt(productKey: string)
	local ok, message = Net.func("PromptPurchase"):InvokeServer(productKey)
	if not ok and message then
		C.HudController:Toast(message, "Bad")
	end
end

local function showOffer(offer)
	current = { Key = offer.Key, Product = offer.Product }
	showToken += 1
	local token = showToken
	Ui.find(offerGui, "Window.Title").Text = offer.Title
	Ui.find(offerGui, "Window.Text").Text = offer.Text
	Ui.find(offerGui, "Window.Buy").Text = `R$ {offer.Price}`
	offerGui.Enabled = true
	Ui.popIn(offerGui)
	task.delay(AUTO_HIDE_SECONDS, function()
		if token == showToken and offerGui.Enabled then
			hideOffer(false)
		end
	end)
end

local function showWelcome(info)
	Ui.find(welcomeGui, "Window.Amount").Text = "+" .. Format.cash(info.Amount)
	Ui.find(welcomeGui, "Window.Text").Text = `Your aliens worked for {Format.duration(info.Seconds)} while you were away.`
	local double = Products.ProductByKey.DoubleOffline
	local doubleButton = Ui.find(welcomeGui, "Window.Double") :: TextButton
	doubleButton.Visible = double ~= nil and double.Id ~= 0
	if double then
		doubleButton.Text = `2x for R$ {double.Price}`
	end
	welcomeGui.Enabled = true
	Ui.popIn(welcomeGui)
end

function OfferController:Init(controllers)
	C = controllers
	offerGui = Ui.screen("Offer")
	welcomeGui = Ui.screen("WelcomeBack")
end

function OfferController:Start()
	Ui.button(Ui.find(offerGui, "Window.Close"), function()
		hideOffer(false)
	end)
	Ui.button(Ui.find(offerGui, "Window.Buy"), function()
		local offer = current
		hideOffer(true)
		if offer then
			prompt(offer.Product)
		end
	end)
	Ui.button(Ui.find(welcomeGui, "Window.Collect"), function()
		welcomeGui.Enabled = false
	end)
	Ui.button(Ui.find(welcomeGui, "Dim"), function()
		welcomeGui.Enabled = false
	end)
	Ui.button(Ui.find(welcomeGui, "Window.Double"), function()
		welcomeGui.Enabled = false
		Net.event("OfferResponse"):FireServer("DoubleOffline", true)
		prompt("DoubleOffline")
	end)
	Net.event("ShowOffer").OnClientEvent:Connect(showOffer)
	Net.event("WelcomeBack").OnClientEvent:Connect(showWelcome)
end

return OfferController
