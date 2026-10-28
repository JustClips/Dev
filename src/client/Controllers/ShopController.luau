--!strict
-- Shop screen: deals (featured Starter Pack + server luck), tools (cash + Robux skips),
-- eggs, gamepasses, cash. Cars are sold in the Garage (GarageController). Cash prices are green buttons, Robux prices are
-- gold with the Robux glyph. Robux items whose ID is still 0 are hidden.
-- Giftable items have a pink gift button.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Tools = require(Shared.Config.Tools)

local TABS = { "Deals", "Tools", "Eggs", "Passes", "Cash" }
local GREEN = Color3.fromRGB(61, 220, 90)
local GREY = Color3.fromRGB(166, 174, 194)
local ROBUX = Color3.fromRGB(255, 200, 60)
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(27, 31, 58)
local MINT = Color3.fromRGB(124, 245, 200)
local TAB_BLUE = Color3.fromRGB(59, 79, 168)
local LIST_TOP = 80
local FEATURED_HEIGHT = 160

type Item = {
	Name: string,
	Desc: string,
	Price: string,
	Color: Color3,
	Enabled: boolean,
	OnBuy: (() -> ())?,
	GiftKey: string?,
	Icon: string?,
}

local ShopController = {}

local C: any
local gui: ScreenGui
local list: ScrollingFrame
local template: Frame
local emptyLabel: TextLabel
local featured: Frame
local giftPicker: Frame
local giftList: ScrollingFrame
local giftTemplate: TextButton
local giftEmpty: TextLabel
local currentTab = "Deals"
local tabButtons: { [string]: TextButton } = {}

local function toast(ok: boolean, message: string?)
	if message and message ~= "" then
		C.HudController:Toast(message, if ok then "Good" else "Bad")
	end
end

local function prompt(key: string, giftTo: number?)
	local ok, message = Net.func("PromptPurchase"):InvokeServer(key, giftTo)
	if not ok then
		toast(false, message)
	end
end

local function robuxPrice(price: number): string
	return `{Ui.ROBUX} {price}`
end

local function robuxItem(key: string, desc: string?, iconName: string?): Item?
	local def = Products.ProductByKey[key]
	if not def or def.Id == 0 then
		return nil
	end
	return {
		Name = def.Name,
		Desc = desc or "",
		Price = robuxPrice(def.Price),
		Icon = iconName,
		Color = ROBUX,
		Enabled = true,
		OnBuy = function()
			prompt(key)
		end,
		GiftKey = if def.Giftable then key else nil,
	}
end

local function toolItems(data): { Item }
	local items: { Item } = {}
	for tier = 2, Tools.MaxTier do
		local def = Tools.get(tier)
		local desc = `Radius {def.Radius} · Power {def.Power} · Holds {Format.number(def.Capacity)}`
		if tier <= data.ToolTier then
			table.insert(items, { Name = def.Name, Desc = desc, Price = "Owned", Color = GREY, Enabled = false, Icon = "Icon_Tool_" .. def.Id })
		elseif tier == data.ToolTier + 1 then
			local affordable = BigNum.gte(data.Cash, def.Price)
			table.insert(items, {
				Name = def.Name,
				Desc = desc,
				Price = Format.cash(def.Price),
				Color = if affordable then GREEN else GREY,
				Enabled = true,
				Icon = "Icon_Tool_" .. def.Id,
				OnBuy = function()
					toast(Net.func("BuyNextTool"):InvokeServer())
				end,
			})
			local skip = robuxItem("ToolSkip" .. tier, "Skip the grind: get it right now.", "Icon_Tool_" .. def.Id)
			if skip then
				table.insert(items, skip)
			end
		else
			table.insert(items, { Name = def.Name, Desc = desc, Price = "Locked", Color = GREY, Enabled = false, Icon = "Icon_Lock" })
		end
	end
	return items
end

local function starterPackOnSale(data): boolean
	local def = Products.ProductByKey.StarterPack
	return def ~= nil and def.Id ~= 0 and not data.Flags.StarterPackBought
end

local function dealItems(_data): { Item }
	local items: { Item } = {}
	for _, key in { "ServerLuck2", "ServerLuck4", "ServerLuck8", "ServerLuck16" } do
		local item = robuxItem(key, "Better eggs and mutations for EVERYONE here. Time stacks.", "Icon_Luck")
		if item then
			table.insert(items, item)
		end
	end
	local shower = robuxItem("MeteorShower", "Start a Meteor Shower for the whole server!", "Icon_Meteor")
	if shower then
		table.insert(items, shower)
	end
	return items
end

local function eggItems(data): { Item }
	local items: { Item } = {}
	for _, key in { "CosmicEgg1", "CosmicEgg3" } do
		local item = robuxItem(key, "Hatches Cosmo the Infinite, the event alien!", "Icon_Egg")
		if item then
			table.insert(items, item)
		end
	end
	local seen = {}
	for _, entry in data.Hatching do
		if not seen[entry.Rarity] then
			seen[entry.Rarity] = true
			local item = robuxItem("SkipHatch" .. entry.Rarity, `Finish your {entry.Rarity} egg right now.`, "Icon_Timer")
			if item then
				table.insert(items, item)
			end
		end
	end
	return items
end

local function passItems(data): { Item }
	local items: { Item } = {}
	for _, pass in Products.Gamepasses do
		if pass.Id ~= 0 then
			local owned = data.Gamepasses[pass.Key] == true
			table.insert(items, {
				Name = pass.Name,
				Desc = pass.Description,
				Price = if owned then "Owned" else robuxPrice(pass.Price),
				Color = if owned then GREY else ROBUX,
				Enabled = not owned,
				Icon = "Icon_Star",
				OnBuy = function()
					prompt(pass.Key)
				end,
			})
		end
	end
	return items
end

local function cashItems(data): { Item }
	local items: { Item } = {}
	for _, key in { "Cash1", "Cash2", "Cash3", "Cash4", "Cash5" } do
		-- The server works out each pack's amount for this player (it grows with progress).
		local amount = data.CashPacks and data.CashPacks[key]
		local item = robuxItem(key, if amount then `+{Format.cash(amount)} cash` else "Scales with your progress.", "Icon_Cash")
		if item then
			table.insert(items, item)
		end
	end
	local skipDef = Products.skipRebirthFor(data.Rebirths)
	local skip = skipDef and robuxItem(skipDef.Key, `Jump to Rebirth {data.Rebirths + 1} without the cash cost.`, "Icon_Rebirth")
	if skip then
		table.insert(items, skip)
	end
	return items
end

local BUILDERS = { Deals = dealItems, Tools = toolItems, Eggs = eggItems, Passes = passItems, Cash = cashItems }

local function openGiftPicker(key: string)
	for _, child in giftList:GetChildren() do
		if child:IsA("TextButton") and child ~= giftTemplate then
			child:Destroy()
		end
	end
	local count = 0
	for _, other in Players:GetPlayers() do
		if other ~= Players.LocalPlayer then
			count += 1
			local button = giftTemplate:Clone()
			button.Name = "Player"
			Ui.setText(button, other.DisplayName)
			button.Visible = true
			button.Parent = giftList
			Ui.button(button, function()
				giftPicker.Visible = false
				prompt(key, other.UserId)
			end)
		end
	end
	giftEmpty.Visible = count == 0
	giftPicker.Visible = true
end

-- The featured well (Deals tab): the Starter Pack while it's for sale.
local function renderFeatured(data): boolean
	local show = currentTab == "Deals" and starterPackOnSale(data)
	featured.Visible = show
	if show then
		local def = Products.ProductByKey.StarterPack
		local pack = Economy.StarterPack
		Ui.find(featured, "Desc").Text = `{Format.cash(pack.Cash)} + {pack.EggRarity} egg + {pack.Cash2xMinutes} min 2x cash`
		Ui.setText(Ui.find(featured, "Buy"), robuxPrice(def.Price))
	end
	list.Position = UDim2.new(list.Position.X, UDim.new(0, if show then LIST_TOP + FEATURED_HEIGHT else LIST_TOP))
	list.Size = UDim2.new(list.Size.X, UDim.new(1, if show then -(LIST_TOP + FEATURED_HEIGHT + 12) else -(LIST_TOP + 12)))
	return show
end

local function render()
	local data = State.data
	if not data or not gui.Enabled then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("Frame") and child ~= template then
			child:Destroy()
		end
	end
	for name, button in tabButtons do
		local selected = name == currentTab
		button.BackgroundColor3 = if selected then MINT else TAB_BLUE
		local label = button:FindFirstChild("Label") :: TextLabel?
		if label then
			label.TextColor3 = if selected then INK else WHITE
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Enabled = not selected
			end
		end
	end
	local hasFeatured = renderFeatured(data)
	local items = BUILDERS[currentTab](data)
	for i, item in items do
		local row = template:Clone()
		row.Name = "Item"
		row.LayoutOrder = i
		row.Visible = true
		;(row:FindFirstChild("Name") :: TextLabel).Text = item.Name
		;(row:FindFirstChild("Desc") :: TextLabel).Text = item.Desc
		local rowIcon = row:FindFirstChild("Icon") :: ImageLabel
		rowIcon.Image = AssetLibrary.image(item.Icon or "Icon_Shop")
		local buy = row:FindFirstChild("Buy") :: TextButton
		Ui.setText(buy, item.Price)
		buy.BackgroundColor3 = item.Color
		local label = buy:FindFirstChild("Label") :: TextLabel?
		if label then
			-- Dark text on gold, white text on green/grey.
			label.TextColor3 = if item.Color == ROBUX then INK else WHITE
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Enabled = item.Color ~= ROBUX
			end
		end
		local onBuy = item.OnBuy
		if item.Enabled and onBuy then
			Ui.button(buy, onBuy)
		end
		local gift = row:FindFirstChild("Gift") :: TextButton
		local giftKey = item.GiftKey
		gift.Visible = giftKey ~= nil
		if giftKey then
			Ui.button(gift, function()
				openGiftPicker(giftKey)
			end)
		end
		row.Parent = list
	end
	emptyLabel.Visible = #items == 0 and not hasFeatured
end

function ShopController:Toggle()
	local data = State.data
	if not gui.Enabled and data then
		-- Lead with the featured deal while there is one, otherwise the next upgrade.
		currentTab = if starterPackOnSale(data) then "Deals" else "Tools"
	end
	Ui.toggle("Shop")
	giftPicker.Visible = false
	render()
end

function ShopController:Open(tab: string?)
	currentTab = tab or currentTab
	Ui.open("Shop")
	giftPicker.Visible = false
	render()
end

function ShopController:Init(controllers)
	C = controllers
	gui = Ui.screen("Shop")
	list = Ui.find(gui, "Window.List")
	template = Ui.find(gui, "Window.List.Template")
	emptyLabel = Ui.find(gui, "Window.Empty")
	featured = Ui.find(gui, "Window.Featured")
	giftPicker = Ui.find(gui, "Window.GiftPicker")
	giftList = Ui.find(gui, "Window.GiftPicker.List")
	giftTemplate = Ui.find(gui, "Window.GiftPicker.List.Template")
	giftEmpty = Ui.find(gui, "Window.GiftPicker.Empty")
	for _, name in TABS do
		tabButtons[name] = Ui.find(gui, "Window.Tabs.Tab" .. name)
	end
end

function ShopController:Start()
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Shop")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Shop")
	end)
	Ui.button(Ui.find(gui, "Window.Featured.Buy"), function()
		prompt("StarterPack")
	end)
	Ui.button(Ui.find(gui, "Window.GiftPicker.Close"), function()
		giftPicker.Visible = false
	end)
	for name, button in tabButtons do
		Ui.button(button, function()
			currentTab = name
			giftPicker.Visible = false
			render()
		end)
	end
	-- Income changes cash every second; only rebuild when something the list shows changed.
	local lastSignature = ""
	State.Changed:Connect(function(data)
		local nextTool = Tools.get(math.min(data.ToolTier + 1, Tools.MaxTier))
		local hatching = {}
		for _, entry in data.Hatching do
			table.insert(hatching, entry.Rarity)
		end
		local passes = {}
		for key in data.Gamepasses do
			table.insert(passes, key)
		end
		table.sort(passes)
		local signature = table.concat({
			data.ToolTier,
			data.EffectiveTier,
			tostring(BigNum.gte(data.Cash, nextTool.Price)),
			tostring(data.Flags.StarterPackBought),
			data.Rebirths,
			if currentTab == "Cash" and data.CashPacks and data.CashPacks.Cash1 then Format.cash(data.CashPacks.Cash1) else "",
			table.concat(hatching, ","),
			table.concat(passes, ","),
		}, "|")
		if signature ~= lastSignature then
			lastSignature = signature
			render()
		end
	end)
end

return ShopController
