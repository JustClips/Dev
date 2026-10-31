--!strict
-- Traveling Merchant window (screen "Merchant", tools/gen_ui.py merchant()), opened from
-- the prompt on his cart in the plaza (Opens = "Merchant"). The server (MerchantService)
-- owns the wares and prices: "Merchant" remote ("Get") / ("Buy", wareId) -> ok, message,
-- state. Also puts a big sign over the cart that says when he's here or when he's back,
-- so players can see it from across the plaza.
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local BagItems = require(Client.BagItems)
local ModelView = require(Client.ModelView)
local State = require(Client.State)
local Ui = require(Client.Ui)
local Prices = require(Client.Prices)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local BigNum = require(Shared.BigNum)
local Format = require(Shared.Format)
local Items = require(Shared.Config.Items)
local Merchant = require(Shared.Config.Merchant)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local World = require(Shared.Config.World)

local GREEN = Color3.fromRGB(61, 220, 90)
local GREY = Color3.fromRGB(166, 174, 194)
local WHITE = Color3.new(1, 1, 1)

local MerchantController = {}

local C: any
local gui: ScreenGui
local current: { [string]: any }? = nil
local busy = false
local shownVisit = -1
local sign: TextLabel? = nil

local function paint(button: GuiButton, label: string, color: Color3)
	Ui.setText(button, label)
	button.BackgroundColor3 = color
	local studs = button:FindFirstChild("Studs") :: ImageLabel?
	if studs then
		studs.ImageColor3 = color
	end
end

local function fillCard(card: Frame, ware)
	local icon = card:FindFirstChild("Icon") :: ImageLabel
	local model = card:FindFirstChild("Model") :: ViewportFrame
	local stripe = card:FindFirstChild("Stripe") :: Frame
	local name, rarity, info, color
	if ware.Item then
		local def = Items.ById[ware.Item]
		name = def and def.Name or ware.Item
		rarity = def and def.Rarity or "Common"
		info = def and def.Description or ""
		color = Items.RarityColors[rarity] or WHITE
		icon.Image = if def then AssetLibrary.image(def.Icon) else ""
		icon.Visible = true
		model.Visible = false
	else
		rarity = ware.Egg or "Rare"
		name = `{rarity} Egg`
		info = "Hatches a pet from your best field that can drop it."
		color = BagItems.rarityColor(rarity)
		icon.Visible = false
		model.Visible = true
		if model:GetAttribute("Egg") ~= rarity then
			model:SetAttribute("Egg", rarity)
			ModelView.show(model, AssetLibrary.egg(rarity), "Egg_" .. rarity)
		end
	end
	stripe.BackgroundColor3 = color
	;(card:FindFirstChild("Name") :: TextLabel).Text = name
	local rarityLabel = card:FindFirstChild("Rarity") :: TextLabel
	rarityLabel.Text = rarity
	rarityLabel.TextColor3 = color:Lerp(Color3.new(0, 0, 0), 0.25)
	;(card:FindFirstChild("Info") :: TextLabel).Text = info
	;(card:FindFirstChild("Left") :: TextLabel).Text = if ware.Left > 0 then `{ware.Left} of {ware.Stock} left` else "Sold out"
	local buy = card:FindFirstChild("Buy") :: GuiButton
	local data = State.data
	if ware.Left <= 0 then
		paint(buy, "Sold out", GREY)
	else
		local afford = data ~= nil and BigNum.gte(data.Cash, ware.Price)
		paint(buy, Format.cash(ware.Price), if afford then GREEN else GREY)
	end
end

local function render()
	if not Ui.isOpen(gui) then
		return
	end
	local _, here, changesAt = Merchant.visitAt(State.now())
	local left = math.max(0, changesAt - State.now())
	local timer = Ui.find(gui, "Window.Timer") :: TextLabel
	local cards = Ui.find(gui, "Window.Cards") :: Frame
	local away = Ui.find(gui, "Window.Away") :: Frame
	local restock = Ui.find(gui, "Window.Restock") :: GuiButton
	cards.Visible = here
	away.Visible = not here
	local def = Products.ProductByKey.MerchantRestock
	restock.Visible = here and def ~= nil and def.Id ~= 0
	if def then
		Ui.setText(restock, `New wares {Ui.ROBUX}{Prices.of(def)}`)
	end
	if not here then
		timer.Text = ""
		;(Ui.find(away, "Back") :: TextLabel).Text = `Back in {Format.countdown(left)}`
		return
	end
	timer.Text = `Leaves in {Format.countdown(left)}` .. (if current and current.Restocked then " · your own wares" else "")
	local wares = if current then current.Wares else {}
	for i = 1, Merchant.MaxSlots do
		local card = Ui.find(cards, `Card{i}`) :: Frame
		local ware = wares[i]
		card.Visible = ware ~= nil
		if ware then
			fillCard(card, ware)
		end
	end
end

local function apply(ok: boolean, message: string?, state: any)
	if type(state) == "table" then
		current = state
		shownVisit = state.Visit
	end
	if message then
		C.HudController:Toast(message, if ok then "Good" else "Bad")
	end
	render()
end

local function refresh()
	task.spawn(function()
		local ok, message, state = Net.func("Merchant"):InvokeServer("Get")
		apply(ok, message, state)
	end)
end

local function buy(i: number)
	local ware = current and current.Wares[i]
	if busy or not ware or ware.Left <= 0 then
		return
	end
	busy = true
	local ok, message, state = Net.func("Merchant"):InvokeServer("Buy", ware.Id)
	busy = false
	if ok then
		Ui.sound("Reveal")
	end
	apply(ok, message, state)
end

function MerchantController:Open()
	if not Ui.isOpen(gui) then
		Ui.open("Merchant")
	end
	render()
	refresh()
end

-- A sign over the cart: "MERCHANT HERE 7:12" (seen from around the plaza) or "Merchant
-- back in 4:30" (only up close). Not on top of walls, and gone from far away (Dev).
local function buildSign()
	local anchor = Instance.new("Part")
	anchor.Name = "MerchantSignAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = World.Merchant * CFrame.new(0, 13, 0)
	anchor.Parent = Workspace
	local board = Instance.new("BillboardGui")
	board.Name = "MerchantSign"
	-- Sized in studs so it shrinks with distance like a real sign (pixels stayed huge far away).
	board.Size = UDim2.fromScale(12, 3)
	board.LightInfluence = 0
	board.Adornee = anchor
	board.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
	label.TextScaled = true
	label.TextColor3 = WHITE
	label.Parent = board
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(23, 25, 30)
	stroke.Parent = label
	sign = label
end

local function tickSign()
	local label = sign
	if not label then
		return
	end
	local _, here, changesAt = Merchant.visitAt(State.now())
	local left = Format.countdown(math.max(0, changesAt - State.now()))
	local board = label.Parent :: BillboardGui
	if here then
		label.Text = `MERCHANT HERE! {left}`
		label.TextColor3 = Color3.fromRGB(255, 200, 60)
		board.MaxDistance = 160
	else
		label.Text = `Merchant back in {left}`
		label.TextColor3 = WHITE
		board.MaxDistance = 70
	end
end

function MerchantController:Init(controllers)
	C = controllers
	gui = Ui.screen("Merchant")
end

function MerchantController:Start()
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Merchant")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Merchant")
	end)
	for i = 1, Merchant.MaxSlots do
		Ui.button(Ui.find(gui, `Window.Cards.Card{i}.Buy`), function()
			buy(i)
		end)
	end
	Ui.button(Ui.find(gui, "Window.Restock"), function()
		local ok, message = Net.func("PromptPurchase"):InvokeServer("MerchantRestock")
		if not ok and message then
			C.HudController:Toast(message, "Bad")
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("Opens") == "Merchant" then
			MerchantController:Open()
		end
	end)
	Net.event("MerchantRestocked").OnClientEvent:Connect(refresh)
	State.Changed:Connect(render)
	buildSign()
	task.spawn(function()
		while true do
			task.wait(1)
			tickSign()
			if Ui.isOpen(gui) then
				local visit = Merchant.visitAt(State.now())
				if visit ~= shownVisit then
					refresh()
				end
				render()
			end
		end
	end)
end

return MerchantController
