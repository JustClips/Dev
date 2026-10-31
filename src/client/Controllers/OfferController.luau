--!strict
-- Shows the server's contextual offers and the "welcome back" offline income screen.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local Ui = require(Client.Ui)
local Prices = require(Client.Prices)
local State = require(Client.State)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Tools = require(Shared.Config.Tools)
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

-- What the offer gives, as big icons with a short caption each (kids read pictures).
type Item = { icon: string, caption: string }

local function itemsFor(product: string): { Item }
	if product == "StarterPack" then
		local pack = Economy.StarterPack
		local data = State.data
		local cash = data and data.CashPacks and data.CashPacks.StarterPack
		return {
			{ icon = AssetLibrary.image("Icon_Cash"), caption = if cash then Format.cash(cash) else "Cash" },
			{ icon = AssetLibrary.image("Icon_Egg"), caption = `{pack.EggRarity} Egg` },
			{ icon = AssetLibrary.image("Icon_PotionLuck"), caption = `{pack.LuckPotions} Luck Potions` },
			{ icon = AssetLibrary.image("Icon_PotionCash"), caption = `2x Cash {pack.Cash2xMinutes}m` },
		}
	end
	local tier = tonumber(string.match(product, "^ToolSkip(%d+)$"))
	if tier then
		local tool = Tools.get(tier)
		return { { icon = AssetLibrary.toolIcon(tool.Id), caption = tool.Name } }
	end
	if string.find(product, "^SkipHatch") then
		return {
			{ icon = AssetLibrary.image("Icon_Egg"), caption = "Your egg" },
			{ icon = AssetLibrary.image("Icon_Timer"), caption = "Hatch now!" },
		}
	end
	if string.find(product, "^ServerLuck") then
		return { { icon = AssetLibrary.image("Icon_Luck"), caption = "Server Luck" } }
	end
	local icons = { SellAnywhere = "Icon_Sell", AutoSweep = "Icon_Auto", Carry3 = "Icon_Egg", Cash2x = "Icon_Cash", VIP = "Icon_Star" }
	return { { icon = AssetLibrary.image(icons[product] or "Icon_Star"), caption = "" } }
end

local TAG_TEXT = { StarterPack = "BEST DEAL!" }
-- A short line under the icons (the icons already say what's inside).
local LINE_TEXT = { StarterPack = "Leaving soon! Huge value!" }

-- The card slides in next to the left rail (on phones the rail sits under the wallet).
local function placeCard(window: GuiObject)
	local hud = Ui.screen("Hud")
	local rail = hud:FindFirstChild("Rail") :: GuiObject?
	local s = Ui.scale()
	local height = 244 * s
	local view = offerGui.AbsoluteSize
	local x, y = 210 * s, view.Y / 2
	if rail then
		local at = rail.AbsolutePosition - hud.AbsolutePosition
		x = at.X + rail.AbsoluteSize.X + math.ceil(12 * s)
		y = at.Y + rail.AbsoluteSize.Y / 2
	end
	y = math.clamp(y, height / 2 + 8, math.max(height / 2 + 8, view.Y - height / 2 - 8))
	window.AnchorPoint = Vector2.new(0, 0.5)
	window.Position = UDim2.fromOffset(x, y)
end

local cardMotion = 0

local function showCard()
	local window = Ui.find(offerGui, "Window") :: GuiObject
	local scale = window:FindFirstChild("AutoScale") :: UIScale
	cardMotion += 1
	placeCard(window)
	local home = window.Position
	offerGui.Enabled = true
	scale.Scale = Ui.scale()
	-- Slide in from the left with a little bounce.
	window.Position = home - UDim2.fromOffset(window.AbsolutePosition.X + window.AbsoluteSize.X + 20, 0)
	TweenService:Create(window, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = home }):Play()
	Ui.sound("Notify")
end

local function hideCard()
	if not offerGui.Enabled then
		return
	end
	cardMotion += 1
	local token = cardMotion
	local window = Ui.find(offerGui, "Window") :: GuiObject
	local away = window.Position - UDim2.fromOffset(window.AbsolutePosition.X + window.AbsoluteSize.X + 20, 0)
	TweenService:Create(window, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = away }):Play()
	task.delay(0.26, function()
		if token == cardMotion then
			offerGui.Enabled = false
		end
	end)
end

local function hideOffer(clicked: boolean)
	if current then
		Net.event("OfferResponse"):FireServer(current.Key, clicked)
		current = nil
	end
	hideCard()
end

local function prompt(productKey: string)
	local ok, message = Net.func("PromptPurchase"):InvokeServer(productKey)
	if not ok and message then
		C.HudController:Toast(message, "Bad")
	end
end

-- Popups that can't share the screen with an offer.
local function screenBusy(): boolean
	if C.HatchController:IsBusy() or Ui.anyWindowOpen() or Ui.isOpen(welcomeGui) then
		return true
	end
	for _, name in { "TutorialDone", "Hatch" } do
		local gui = Ui.screen(name)
		if gui.Enabled then
			return true
		end
	end
	return false
end

local pendingOffer: any = nil
local welcomeAmount: any = nil

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
	-- Wait for the hatch show, tutorial reward or open window to finish first.
	if screenBusy() then
		pendingOffer = offer
		return
	end
	pendingOffer = nil
	current = { Key = offer.Key, Product = offer.Product }
	showToken += 1
	local token = showToken
	Ui.find(offerGui, "Window.Header.Title").Text = offer.Title
	Ui.find(offerGui, "Window.Text").Text = LINE_TEXT[offer.Product] or offer.Text
	Ui.setText(Ui.find(offerGui, "Window.Buy"), `{Ui.ROBUX} {if Products.ProductByKey[offer.Product] then Prices.of(Products.ProductByKey[offer.Product]) else offer.Price}`)
	Ui.find(offerGui, "Window.Tag.Label").Text = TAG_TEXT[offer.Product] or "LIMITED!"
	local items = Ui.find(offerGui, "Window.Items") :: Frame
	local template = items:FindFirstChild("Template") :: Frame
	for _, child in items:GetChildren() do
		if child:IsA("Frame") and child ~= template then
			child:Destroy()
		end
	end
	for i, item in itemsFor(offer.Product) do
		local tile = template:Clone()
		tile.Name = "Item" .. i
		tile.LayoutOrder = i
		tile.Visible = true
		;(tile:FindFirstChild("Icon") :: ImageLabel).Image = item.icon
		;(tile:FindFirstChild("Caption") :: TextLabel).Text = item.caption
		tile.Parent = items
	end
	showCard()
	-- Auto-hides after a while. If a hatch show starts meanwhile, the offer steps aside
	-- and comes back after it.
	task.spawn(function()
		local deadline = os.clock() + AUTO_HIDE_SECONDS
		while token == showToken and Ui.isOpen(offerGui) do
			if C.HatchController:IsBusy() then
				current = nil
				cardMotion += 1
				offerGui.Enabled = false
				pendingOffer = offer
				return
			end
			if os.clock() >= deadline then
				hideOffer(false)
				return
			end
			task.wait(0.25)
		end
	end)
end

-- Cash you got (offline cash, rewards, products): coins pop up around the screen showing
-- their share and fly into the wallet, where a "+$X" counts up (FlyController; Dev
-- 2026-10-31).
function OfferController:ShowGained(amount: any, _source: string?)
	Ui.sound("Sell")
	C.FlyController:Cash(amount, 8)
end

local doublePending: number? = nil

-- Closes the welcome-back window and shows the offline cash coming in (it was already paid
-- on join; this is the reward moment).
local function claimWelcome()
	Ui.hide(welcomeGui)
	if welcomeAmount then
		OfferController:ShowGained(welcomeAmount, "OfflineIncome")
		welcomeAmount = nil
	end
end

local function showWelcome(info)
	welcomeAmount = info.Amount
	Ui.find(welcomeGui, "Window.Amount").Text = "+" .. Format.cash(info.Amount)
	Ui.find(welcomeGui, "Window.Text").Text = `Your pets worked for {Format.duration(info.Seconds)} while you were away.`
	local double = Products.ProductByKey.DoubleOffline
	local doubleButton = Ui.find(welcomeGui, "Window.Double") :: TextButton
	doubleButton.Visible = double ~= nil and double.Id ~= 0
	-- Collect sits next to the 2x button, or alone in the middle when 2x isn't on sale.
	local collect = Ui.find(welcomeGui, "Window.Collect") :: GuiObject
	-- Only X moves: the window lays the buttons out at the same height (setting Y here put
	-- Collect a few px lower than 2x).
	local doubleAt = doubleButton.Position
	collect.Position = UDim2.new(0.5, if doubleButton.Visible then -100 else 0, doubleAt.Y.Scale, doubleAt.Y.Offset)
	if double then
		Ui.setText(doubleButton, `2x for {Ui.ROBUX} {Prices.of(double)}`)
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
	-- The card lives next to the left rail; keep it there when the screen changes size.
	local window = Ui.find(offerGui, "Window") :: GuiObject
	Ui.onScale(function(s: number)
		if offerGui.Enabled then
			placeCard(window)
			local autoScale = window:FindFirstChild("AutoScale") :: UIScale
			autoScale.Scale = s
		end
	end)
	-- Spinning rays behind the prize and a breathing Buy button.
	local rays = Ui.find(offerGui, "Window.Rays") :: ImageLabel
	local buy = Ui.find(offerGui, "Window.Buy") :: GuiObject
	local buySize = buy.Size
	game:GetService("RunService").RenderStepped:Connect(function()
		if not offerGui.Enabled then
			return
		end
		local t = os.clock()
		rays.Rotation = (t * 30) % 360
		local pulse = 1 + math.abs(math.sin(t * 3)) * 0.05
		buy.Size = UDim2.new(buySize.X.Scale, buySize.X.Offset * pulse, buySize.Y.Scale, buySize.Y.Offset * pulse)
	end)
	Ui.button(Ui.find(offerGui, "Window.Close"), function()
		hideOffer(false)
	end)
	Ui.button(Ui.find(offerGui, "Window.Buy"), function()
		local offer = current
		hideOffer(true)
		if offer and offer.Target and string.find(offer.Product, "^SkipHatch") then
			-- Skip the egg this offer was shown for (not just any egg of that rarity).
			local ok, message = Net.func("Inventory"):InvokeServer("SkipHatch", offer.Target)
			if not ok and message then
				C.HudController:Toast(message, "Bad")
			end
		elseif offer then
			prompt(offer.Product)
		end
	end)
	-- The welcome-back window only closes from its own buttons (Dev: a stray click shouldn't
	-- close it). Close and Collect both claim the normal reward; 2x claims it too if the
	-- purchase doesn't go through.
	Ui.button(Ui.find(welcomeGui, "Window.Close"), claimWelcome)
	Ui.button(Ui.find(welcomeGui, "Window.Collect"), claimWelcome)
	Net.event("CashGained").OnClientEvent:Connect(function(info)
		OfferController:ShowGained(info.Amount, info.Source)
	end)
	Ui.button(Ui.find(welcomeGui, "Window.Double"), function()
		local double = Products.ProductByKey.DoubleOffline
		Ui.hide(welcomeGui)
		Net.event("OfferResponse"):FireServer("DoubleOffline", true)
		local ok, message = Net.func("PromptPurchase"):InvokeServer("DoubleOffline")
		if ok and double then
			doublePending = double.Id
		else
			if message then
				C.HudController:Toast(message, "Bad")
			end
			claimWelcome()
		end
	end)
	-- 2x cancelled or failed: fall back to the normal reward. When it goes through, the
	-- server pays the extra and its own "+cash" pop shows.
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if userId ~= Players.LocalPlayer.UserId or productId ~= doublePending then
			return
		end
		doublePending = nil
		if purchased then
			welcomeAmount = nil
		else
			claimWelcome()
		end
	end)
	Net.event("ShowOffer").OnClientEvent:Connect(showOffer)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if pendingOffer and not screenBusy() then
				task.wait(1) -- a short breather after the hatch show
				if pendingOffer and not screenBusy() then
					showOffer(pendingOffer)
				end
			end
		end
	end)
	Net.event("WelcomeBack").OnClientEvent:Connect(showWelcome)
end

return OfferController
