--!strict
-- Shows the server's contextual offers and the "welcome back" offline income screen.
-- Offers (Dev, 2026-11-01): the Starter Pack still slides in as a card, from the right
-- edge, sized to fit the screen. Every other offer pops up as a round button on the right
-- (Hud.Offers, under the quest list): its icon, "SALE" and the time left. A tap opens the
-- Robux prompt.
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
-- How long a round offer button stays on the right.
local BUBBLE_SECONDS = 90
-- After the popup, an offer stays in the shop's special offers for this long.
local KEEP_IN_SHOP_SECONDS = 10 * 60

local OfferController = {}

local C: any
local offerGui: ScreenGui
local welcomeGui: ScreenGui
local current: { Key: string, Product: string, Target: any? }? = nil
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

-- The card slides in at the right edge, vertically centred, shrunk to fit small screens
-- (Dev, 2026-11-01: on phones it didn't fit and covered the left buttons).
local CARD_W, CARD_H = 340, 244 + 30 -- with the sticker sticking out on top
local function placeCard(window: GuiObject)
	local view = offerGui.AbsoluteSize
	local origin = offerGui.AbsolutePosition
	local hud = Ui.screen("Hud")
	local leftEdge, rightEdge = Ui.edges(hud)
	-- The free space between the left buttons and the quest list on the right (Dev
	-- 2026-11-01: on phones the card covered the quests and Spin).
	local left = origin.X + math.max(leftEdge, 14)
	local rail = hud:FindFirstChild("Rail") :: GuiObject?
	if rail and rail.Visible then
		left = math.max(left, rail.AbsolutePosition.X + rail.AbsoluteSize.X + 10)
	end
	local right = origin.X + view.X - (math.max(rightEdge, 14) + 4)
	local quests = hud:FindFirstChild("QuestList") :: GuiObject?
	if quests and quests.Visible and quests.AbsoluteSize.X > 0 then
		right = math.min(right, quests.AbsolutePosition.X - 10)
	end
	local room = math.max(right - left, 120)
	local s = math.min(Ui.scale(), (view.Y - 24) / CARD_H, room / (CARD_W + 10))
	local autoScale = window:FindFirstChild("AutoScale") :: UIScale
	autoScale.Scale = s
	window.AnchorPoint = Vector2.new(1, 0.5)
	window.Position = UDim2.new(0, math.floor(right - origin.X), 0.5, math.floor(14 * s))
end

local cardMotion = 0

local function showCard()
	local window = Ui.find(offerGui, "Window") :: GuiObject
	local scale = window:FindFirstChild("AutoScale") :: UIScale
	cardMotion += 1
	placeCard(window)
	local home = window.Position
	offerGui.Enabled = true
	local _ = scale
	-- Slide in from the right with a little bounce.
	window.Position = home + UDim2.fromOffset(window.AbsoluteSize.X + 40, 0)
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
	local away = window.Position + UDim2.fromOffset(window.AbsoluteSize.X + 40, 0)
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

-------------------------------------------------------------------------- round offers

local bubbles: { [string]: { Button: GuiButton, Offer: any, Ends: number } } = {}
local offersFrame: Frame

local function dropBubble(key: string, clicked: boolean)
	local b = bubbles[key]
	if not b then
		return
	end
	bubbles[key] = nil
	Net.event("OfferResponse"):FireServer(key, clicked)
	local button = b.Button
	local pop = button:FindFirstChild("Pop") :: UIScale?
	if pop then
		local shrink = TweenService:Create(pop, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
		shrink.Completed:Once(function()
			button:Destroy()
		end)
		shrink:Play()
	else
		button:Destroy()
	end
end

local buyOffer: (offer: any) -> ()

local function addBubble(offer)
	if bubbles[offer.Key] then
		bubbles[offer.Key].Ends = os.clock() + BUBBLE_SECONDS
		return
	end
	local template = offersFrame:FindFirstChild("Template") :: GuiButton
	local button = template:Clone()
	button.Name = "Offer_" .. offer.Key
	button.Visible = true
	local items = itemsFor(offer.Product)
	;(button:FindFirstChild("Icon") :: ImageLabel).Image = if items[1] then items[1].icon else AssetLibrary.image("Icon_Star")
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Scale = 0
	pop.Parent = button
	button.Parent = offersFrame
	bubbles[offer.Key] = { Button = button, Offer = offer, Ends = os.clock() + BUBBLE_SECONDS }
	Ui.button(button, function()
		local b = bubbles[offer.Key]
		if b then
			dropBubble(offer.Key, true)
			buyOffer(b.Offer)
		end
	end)
	TweenService:Create(pop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	Ui.sound("Notify")
end

local function tickBubbles()
	local now = os.clock()
	local any = false
	for key, b in bubbles do
		local left = b.Ends - now
		if left <= 0 then
			dropBubble(key, false)
		else
			any = true
			;(b.Button:FindFirstChild("Timer") :: TextLabel).Text = Format.countdown(left)
			-- A little wiggle every 5 s so it gets noticed.
			local phase = (now % 5)
			b.Button.Rotation = if phase < 0.5 and not Ui.reducedMotion() then math.sin(phase * math.pi * 6) * 10 else 0
		end
	end
	-- Other round buttons (the free potion countdown, RewardsController) also live here.
	local stay = offersFrame:FindFirstChild("StayBubble") :: GuiObject?
	offersFrame.Visible = any or (stay ~= nil and stay.Visible)
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
	-- Wait for the hatch show, tutorial reward or open window to finish first.
	if screenBusy() then
		pendingOffer = offer
		return
	end
	pendingOffer = nil
	-- Everything but the Starter Pack is a round button on the right.
	if offer.Product ~= "StarterPack" then
		addBubble(offer)
		return
	end
	current = { Key = offer.Key, Product = offer.Product, Target = offer.Target }
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

buyOffer = function(offer)
	if offer.Target and string.find(offer.Product, "^SkipHatch") then
		-- Skip the egg this offer was shown for (not just any egg of that rarity).
		local ok, message = Net.func("Inventory"):InvokeServer("SkipHatch", offer.Target)
		if not ok and message then
			C.HudController:Toast(message, "Bad")
		end
	else
		prompt(offer.Product)
	end
end

function OfferController:Init(controllers)
	C = controllers
	offerGui = Ui.screen("Offer")
	offersFrame = Ui.find(Ui.screen("Hud"), "Offers")
	welcomeGui = Ui.screen("WelcomeBack")
end

function OfferController:Start()
	-- The card lives at the right edge; keep it there when the screen changes size.
	local window = Ui.find(offerGui, "Window") :: GuiObject
	Ui.onScale(function()
		if offerGui.Enabled then
			placeCard(window)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.1)
			tickBubbles()
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
		if offer then
			buyOffer(offer)
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
