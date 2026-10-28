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
-- After the popup, an offer stays in the shop's special offers for this long.
local KEEP_IN_SHOP_SECONDS = 10 * 60

local OfferController = {}

local C: any
local offerGui: ScreenGui
local welcomeGui: ScreenGui
local current: { Key: string, Product: string }? = nil
local showToken = 0
local specials: { [string]: any } = {}

local function hideOffer(clicked: boolean)
	if current then
		Net.event("OfferResponse"):FireServer(current.Key, clicked)
		current = nil
	end
	Ui.hide(offerGui)
end

local function prompt(productKey: string)
	local ok, message = Net.func("PromptPurchase"):InvokeServer(productKey)
	if not ok and message then
		C.HudController:Toast(message, "Bad")
	end
end

local function showOffer(offer)
	specials[offer.Key] = {
		Key = offer.Key,
		Product = offer.Product,
		Title = offer.Title,
		Text = offer.Text,
		Price = offer.Price,
		Expires = os.clock() + KEEP_IN_SHOP_SECONDS,
	}
	C.ShopController:Refresh()
	current = { Key = offer.Key, Product = offer.Product }
	showToken += 1
	local token = showToken
	Ui.find(offerGui, "Window.Header.Title").Text = offer.Title
	Ui.find(offerGui, "Window.Text").Text = offer.Text
	Ui.setText(Ui.find(offerGui, "Window.Buy"), `{Ui.ROBUX} {offer.Price}`)
	Ui.show(offerGui)
	task.delay(AUTO_HIDE_SECONDS, function()
		if token == showToken and Ui.isOpen(offerGui) then
			hideOffer(false)
		end
	end)
end

local function showWelcome(info)
	Ui.find(welcomeGui, "Window.Amount").Text = "+" .. Format.cash(info.Amount)
	Ui.find(welcomeGui, "Window.Text").Text = `Your pets worked for {Format.duration(info.Seconds)} while you were away.`
	local double = Products.ProductByKey.DoubleOffline
	local doubleButton = Ui.find(welcomeGui, "Window.Double") :: TextButton
	doubleButton.Visible = double ~= nil and double.Id ~= 0
	-- Collect sits next to the 2x button, or alone in the middle when 2x isn't on sale.
	local collect = Ui.find(welcomeGui, "Window.Collect") :: GuiObject
	collect.Position = UDim2.new(0.5, if doubleButton.Visible then -100 else 0, 1, -16)
	if double then
		Ui.setText(doubleButton, `2x for {Ui.ROBUX} {double.Price}`)
	end
	Ui.show(welcomeGui)
end

-- Limited offers still running (newest first), for the shop's special offers.
function OfferController:Specials(): { any }
	local out = {}
	local now = os.clock()
	for key, offer in specials do
		if offer.Expires <= now then
			specials[key] = nil
		else
			table.insert(out, offer)
		end
	end
	table.sort(out, function(a, b)
		return a.Expires > b.Expires
	end)
	return out
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
	Ui.button(Ui.find(welcomeGui, "Window.Close"), function()
		Ui.hide(welcomeGui)
	end)
	Ui.button(Ui.find(welcomeGui, "Window.Collect"), function()
		Ui.hide(welcomeGui)
	end)
	Ui.button(Ui.find(welcomeGui, "Dim"), function()
		Ui.hide(welcomeGui)
	end)
	Ui.button(Ui.find(welcomeGui, "Window.Double"), function()
		Ui.hide(welcomeGui)
		Net.event("OfferResponse"):FireServer("DoubleOffline", true)
		prompt("DoubleOffline")
	end)
	Net.event("ShowOffer").OnClientEvent:Connect(showOffer)
	Net.event("WelcomeBack").OnClientEvent:Connect(showWelcome)
end

return OfferController
