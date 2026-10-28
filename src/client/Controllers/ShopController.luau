--!strict
-- Shop screen: tools (cash + Robux skips + vehicle rentals), boosts, eggs, gamepasses, cash.
-- Robux items whose ID is still 0 are hidden. Giftable items have a gift button.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Tools = require(Shared.Config.Tools)

local TABS = { "Tools", "Boosts", "Eggs", "Passes", "Cash" }
local GREEN = Color3.fromRGB(60, 203, 114)
local GREY = Color3.fromRGB(90, 96, 120)
local ROBUX = Color3.fromRGB(46, 170, 90)

type Item = {
	Name: string,
	Desc: string,
	Price: string,
	Color: Color3,
	Enabled: boolean,
	OnBuy: (() -> ())?,
	GiftKey: string?,
}

local ShopController = {}

local C: any
local gui: ScreenGui
local list: ScrollingFrame
local template: Frame
local emptyLabel: TextLabel
local giftPicker: Frame
local giftList: ScrollingFrame
local giftTemplate: TextButton
local giftEmpty: TextLabel
local currentTab = "Tools"
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

local function robuxItem(key: string, desc: string?): Item?
	local def = Products.ProductByKey[key]
	if not def or def.Id == 0 then
		return nil
	end
	return {
		Name = def.Name,
		Desc = desc or "",
		Price = `R$ {def.Price}`,
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
		local desc = `Radius {def.Radius} · Power {def.Power} · Holds {Format.number(def.Capacity)}` .. (if def.IsVehicle then " · Vehicle!" else "")
		if tier <= data.ToolTier then
			table.insert(items, { Name = def.Name, Desc = desc, Price = "Owned", Color = GREY, Enabled = false })
		elseif tier == data.ToolTier + 1 then
			local affordable = BigNum.gte(data.Cash, def.Price)
			table.insert(items, {
				Name = def.Name,
				Desc = desc,
				Price = Format.cash(def.Price),
				Color = if affordable then GREEN else GREY,
				Enabled = true,
				OnBuy = function()
					toast(Net.func("BuyNextTool"):InvokeServer())
				end,
			})
			local skip = robuxItem("ToolSkip" .. tier, "Skip the grind: get it right now.")
			if skip then
				table.insert(items, skip)
			end
		else
			table.insert(items, { Name = def.Name, Desc = desc, Price = "Locked", Color = GREY, Enabled = false })
		end
	end
	for _, key in { "RentSweeperCart", "RentDustTruck", "RentMoonCrawler" } do
		local def = Products.ProductByKey[key]
		if def and (def.Tier or 0) > data.EffectiveTier then
			local item = robuxItem(key, "Drive it until you rebirth or leave.")
			if item then
				table.insert(items, item)
			end
		end
	end
	return items
end

local function boostItems(data): { Item }
	local items: { Item } = {}
	if not data.Flags.StarterPackBought then
		local item = robuxItem("StarterPack", "$500 + Uncommon egg + 10 min 2x cash. Once only!")
		if item then
			table.insert(items, item)
		end
	end
	for _, key in { "ServerLuck2", "ServerLuck4", "ServerLuck8", "ServerLuck16" } do
		local item = robuxItem(key, "Better eggs and mutations for EVERYONE here. Time stacks.")
		if item then
			table.insert(items, item)
		end
	end
	local shower = robuxItem("MeteorShower", "Start a Meteor Shower for the whole server!")
	if shower then
		table.insert(items, shower)
	end
	return items
end

local function eggItems(data): { Item }
	local items: { Item } = {}
	for _, key in { "CosmicEgg1", "CosmicEgg3" } do
		local item = robuxItem(key, "Hatches Cosmo the Infinite, the event alien!")
		if item then
			table.insert(items, item)
		end
	end
	local seen = {}
	for _, entry in data.Hatching do
		if not seen[entry.EggRarity] then
			seen[entry.EggRarity] = true
			local item = robuxItem("SkipHatch" .. entry.EggRarity, `Finish your {entry.EggRarity} egg right now.`)
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
				Price = if owned then "Owned" else `R$ {pass.Price}`,
				Color = if owned then GREY else ROBUX,
				Enabled = not owned,
				OnBuy = function()
					prompt(pass.Key)
				end,
			})
		end
	end
	return items
end

local function cashItems(_data): { Item }
	local items: { Item } = {}
	for _, key in { "Cash1", "Cash2", "Cash3", "Cash4", "Cash5" } do
		local item = robuxItem(key, "Scales with your progress.")
		if item then
			table.insert(items, item)
		end
	end
	local skip = robuxItem("SkipRebirth", "Rebirth now without paying the cash cost.")
	if skip then
		table.insert(items, skip)
	end
	return items
end

local BUILDERS = { Tools = toolItems, Boosts = boostItems, Eggs = eggItems, Passes = passItems, Cash = cashItems }

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
			button.Text = other.DisplayName
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
		button.BackgroundColor3 = if name == currentTab then Color3.fromRGB(79, 195, 247) else Color3.fromRGB(33, 42, 74)
	end
	local items = BUILDERS[currentTab](data)
	for i, item in items do
		local row = template:Clone()
		row.Name = "Item"
		row.LayoutOrder = i
		row.Visible = true
		;(row:FindFirstChild("Name") :: TextLabel).Text = item.Name
		;(row:FindFirstChild("Desc") :: TextLabel).Text = item.Desc
		local buy = row:FindFirstChild("Buy") :: TextButton
		buy.Text = item.Price
		buy.BackgroundColor3 = item.Color
		buy.AutoButtonColor = item.Enabled
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
	emptyLabel.Visible = #items == 0
end

function ShopController:Toggle()
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
			table.insert(hatching, entry.EggRarity)
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
