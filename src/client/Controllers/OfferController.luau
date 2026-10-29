--!strict
-- Shows the server's contextual offers and the "welcome back" offline income screen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local Ui = require(Client.Ui)

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
local gainedGui: ScreenGui
local current: { Key: string, Product: string }? = nil
local showToken = 0
local specials: { [string]: any } = {}

-- What the offer gives, as big icons with a short caption each (kids read pictures).
type Item = { icon: string, caption: string }

local function itemsFor(product: string): { Item }
	if product == "StarterPack" then
		local pack = Economy.StarterPack
		return {
			{ icon = AssetLibrary.image("Icon_Cash"), caption = Format.cash(pack.Cash) },
			{ icon = AssetLibrary.image("Icon_Egg"), caption = `{pack.EggRarity} Egg` },
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
	local icons = { AutoSweep = "Icon_Auto", Carry3 = "Icon_Egg", Cash2x = "Icon_Cash", VIP = "Icon_Star" }
	return { { icon = AssetLibrary.image(icons[product] or "Icon_Star"), caption = "" } }
end

local TAG_TEXT = { StarterPack = "BEST DEAL!" }

-- The card slides in next to the left rail (on phones the rail sits under the wallet).
local function placeCard(window: GuiObject)
	local hud = Ui.screen("Hud")
	local rail = hud:FindFirstChild("Rail") :: GuiObject?
	local s = Ui.scale()
	local height = 222 * s
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
	Ui.find(offerGui, "Window.Text").Text = offer.Text
	Ui.setText(Ui.find(offerGui, "Window.Buy"), `{Ui.ROBUX} {offer.Price}`)
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

-- Cash pops: a big green "+$4.2K" that bounces in, floats up and fades, with a small line
-- saying where it came from. Several at once fan out a little so they don't cover each other.
local SOURCE_TEXT = {
	OfflineIncome = "Offline cash",
	DoubleOffline = "Offline cash x2",
	DustBunny = "Dust bunny!",
	TutorialReward = "Tutorial reward",
	SellDust = "Sold",
	SellPet = "Sold pet",
}
local POP_SECONDS = 1.6
local livePops = 0

local function sourceText(source: string?): string
	if not source then
		return ""
	end
	local product = Products.ProductByKey[source]
	if product then
		return product.Name
	end
	return SOURCE_TEXT[source] or ""
end

function OfferController:ShowGained(amount: any, source: string?)
	local template = Ui.find(gainedGui, "Template") :: Frame
	local pop = template:Clone()
	pop.Name = "Pop"
	local slot = livePops
	livePops += 1
	local x = if slot == 0 then 0 else (if slot % 2 == 1 then 1 else -1) * (40 + 30 * math.floor((slot - 1) / 2))
	local y = 0.36 + math.min(slot, 4) * 0.04
	pop.Position = UDim2.new(0.5, x, y, 0)
	pop.Rotation = math.random(-6, 6)
	local amountLabel = pop:FindFirstChild("Amount") :: TextLabel
	local sourceLabel = pop:FindFirstChild("Source") :: TextLabel
	amountLabel.Text = "+" .. Format.cash(amount)
	sourceLabel.Text = sourceText(source)
	local scale = pop:FindFirstChild("Pop") :: UIScale
	local auto = pop:FindFirstChild("AutoScale") :: UIScale
	auto.Scale = Ui.scale()
	scale.Scale = 0.2
	pop.Visible = true
	pop.Parent = gainedGui
	Ui.sound("Sell")
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.25 }):Play()
	task.delay(0.22, function()
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
	end)
	TweenService:Create(pop, TweenInfo.new(POP_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = pop.Position - UDim2.fromOffset(0, 90),
		Rotation = 0,
	}):Play()
	task.delay(POP_SECONDS - 0.45, function()
		local fade = TweenInfo.new(0.45)
		TweenService:Create(amountLabel, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(sourceLabel, fade, { TextTransparency = 1 }):Play()
		for _, stroke in pop:GetDescendants() do
			if stroke:IsA("UIStroke") then
				TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
			end
		end
	end)
	task.delay(POP_SECONDS, function()
		pop:Destroy()
		livePops -= 1
	end)
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
	gainedGui = Ui.screen("Gained")
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
		if offer then
			prompt(offer.Product)
		end
	end)
	Ui.button(Ui.find(welcomeGui, "Window.Close"), function()
		Ui.hide(welcomeGui)
	end)
	Ui.button(Ui.find(welcomeGui, "Window.Collect"), function()
		Ui.hide(welcomeGui)
		if welcomeAmount then
			OfferController:ShowGained(welcomeAmount, "OfflineIncome")
			welcomeAmount = nil
		end
	end)
	Net.event("CashGained").OnClientEvent:Connect(function(info)
		OfferController:ShowGained(info.Amount, info.Source)
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
