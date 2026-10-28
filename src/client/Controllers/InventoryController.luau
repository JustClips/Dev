--!strict
-- Inventory window (hotbar slot 3, key 3 or B): every pet, egg and item you own, with
-- filter tabs (All / Pets / Eggs / Items). Pick a card to see it on the right and act on
-- it: place or pick up a pet, sell it, place an egg in an incubator, use a potion.
-- Equip Best, Place Eggs and Open Ready work on everything at once.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local ModelView = require(Client.ModelView)
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AlienModel = require(Shared.AlienModel)
local AssetLibrary = require(Shared.AssetLibrary)
local Aliens = require(Shared.Config.Aliens)
local Economy = require(Shared.Config.Economy)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Zones = require(Shared.Config.Zones)

local TABS = { "All", "Pets", "Eggs", "Items" }
local MINT = Color3.fromRGB(124, 245, 200)
local TAB_BLUE = Color3.fromRGB(59, 79, 168)
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(27, 31, 58)
local GREEN = Color3.fromRGB(61, 220, 90)
local BLUE = Color3.fromRGB(76, 141, 255)
local RED = Color3.fromRGB(255, 77, 94)
local GOLD = Color3.fromRGB(255, 200, 60)
local GREY = Color3.fromRGB(166, 174, 194)

type Entry = {
	kind: string, -- "Pet" | "Egg" | "Item"
	key: string, -- pet/egg uid or item id
	order: number,
}

local InventoryController = {}

local C: any
local gui: ScreenGui
local grid: ScrollingFrame
local template: Frame
local emptyLabel: TextLabel
local countsLabel: TextLabel
local detail: Frame
local primary: TextButton
local secondary: TextButton
local tabButtons: { [string]: TextButton } = {}
local currentTab = "All"
local selected: Entry? = nil
local cards: { [string]: Frame } = {}
local lastSignature = ""
local primaryAction: (() -> ())? = nil
local secondaryAction: (() -> ())? = nil

local function toast(ok: boolean, message: string?)
	if message and message ~= "" then
		C.HudController:Toast(message, if ok then "Good" else "Bad")
	end
end

local function act(action: string, arg: string?)
	local ok, message = Net.func("Inventory"):InvokeServer(action, arg)
	toast(ok, message)
	return ok
end

local function zoneName(zoneId: string?): string
	local zone = Zones.ById[zoneId or "Landing"]
	return if zone then zone.Name else "Landing Site"
end

local function petName(pet): string
	return (if pet.Huge then "Huge " else "") .. AlienModel.displayName(pet.Id, pet.Mutation)
end

local function entries(data): { Entry }
	local list: { Entry } = {}
	if currentTab == "All" or currentTab == "Pets" then
		for uid, pet in data.Pets or {} do
			local def = Aliens.ById[pet.Id]
			local rarity = def and Eggs.order(def.Rarity) or 0
			-- Placed first, then by income.
			local order = (if pet.Placed then 0 else 1e9) - math.min(Aliens.income(pet), 1e9 - 1) / 1e9 * 1e8 - rarity
			table.insert(list, { kind = "Pet", key = uid, order = order })
		end
	end
	if currentTab == "All" or currentTab == "Eggs" then
		for uid, egg in data.Eggs or {} do
			table.insert(list, { kind = "Egg", key = uid, order = 2e9 - Eggs.order(egg.Rarity) })
		end
	end
	if currentTab == "All" or currentTab == "Items" then
		for i, def in Items.List do
			if (data.Items and data.Items[def.Id] or 0) > 0 then
				table.insert(list, { kind = "Item", key = def.Id, order = 3e9 + i })
			end
		end
	end
	table.sort(list, function(a, b)
		if a.order == b.order then
			return a.key < b.key
		end
		return a.order < b.order
	end)
	return list
end

local function setButton(button: TextButton, text: string?, color: Color3?, labelColor: Color3?)
	button.Visible = text ~= nil
	if text then
		Ui.setText(button, text)
		button.BackgroundColor3 = color or GREEN
		local label = button:FindFirstChild("Label") :: TextLabel?
		if label then
			label.TextColor3 = labelColor or WHITE
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Enabled = (labelColor or WHITE) == WHITE
			end
		end
	end
end

local function setChip(chip: Frame, text: string, color: Color3)
	chip.BackgroundColor3 = color
	local studs = chip:FindFirstChild("Studs") :: ImageLabel?
	if studs then
		studs.ImageColor3 = color
	end
	Ui.setText(chip, text)
end

local function showModel(viewport: ViewportFrame, icon: ImageLabel, kind: string, key: string, data, zoom: number?)
	icon.Visible = kind == "Item"
	viewport.Visible = kind ~= "Item"
	if kind == "Pet" then
		local pet = data.Pets[key]
		ModelView.show(viewport, AssetLibrary.alien(pet.Id, pet.Mutation), "Alien_" .. pet.Id, zoom)
	elseif kind == "Egg" then
		local egg = data.Eggs[key]
		ModelView.show(viewport, AssetLibrary.egg(egg.Rarity), "Egg_" .. egg.Rarity, zoom)
	else
		local def = Items.ById[key]
		icon.Image = AssetLibrary.image(def.Icon)
	end
end

local function renderDetail()
	local data = State.data
	local viewport = detail:FindFirstChild("Viewport") :: ViewportFrame
	local icon = detail:FindFirstChild("Icon") :: ImageLabel
	local nameLabel = detail:FindFirstChild("Name") :: TextLabel
	local chip = detail:FindFirstChild("Rarity") :: Frame
	local info = detail:FindFirstChild("Info") :: TextLabel
	primaryAction, secondaryAction = nil, nil
	local entry = selected
	local exists = entry ~= nil
		and data ~= nil
		and (
			(entry.kind == "Pet" and data.Pets ~= nil and data.Pets[entry.key] ~= nil)
			or (entry.kind == "Egg" and data.Eggs ~= nil and data.Eggs[entry.key] ~= nil)
			or (entry.kind == "Item" and data.Items ~= nil and (data.Items[entry.key] or 0) > 0)
		)
	if not entry or not exists or not data then
		selected = nil
		viewport.Visible = false
		icon.Visible = false
		nameLabel.Text = "Pick something"
		chip.Visible = false
		info.Text = "Tap a pet, egg or potion to see what you can do with it."
		setButton(primary, nil)
		setButton(secondary, nil)
		return
	end
	chip.Visible = true
	showModel(viewport, icon, entry.kind, entry.key, data, 1.15)
	if entry.kind == "Pet" then
		local pet = data.Pets[entry.key]
		local def = Aliens.ById[pet.Id]
		local rarity = Eggs.ByName[def.Rarity]
		nameLabel.Text = petName(pet)
		setChip(chip, def.Rarity, rarity.Color)
		local income = Aliens.income(pet) * (data.CashMultiplier or 1)
		info.Text = `+{Format.cash(income)}/s on your base\nFrom {zoneName(def.Zone)}`
		if pet.Placed then
			setButton(primary, "Pick up", BLUE)
			primaryAction = function()
				act("PickUpPet", entry.key)
			end
		else
			local full = data.PlacedCount >= data.Slots
			setButton(primary, if full then `Base full ({data.Slots})` else "Place on base", if full then GREY else GREEN)
			primaryAction = function()
				act("PlacePet", entry.key)
			end
		end
		local sellValue = Aliens.income(pet) * Economy.PetSellSeconds
		setButton(secondary, `Sell for {Format.cash(sellValue)}`, RED)
		secondaryAction = function()
			if act("SellPet", entry.key) then
				selected = nil
			end
		end
	elseif entry.kind == "Egg" then
		local egg = data.Eggs[entry.key]
		local rarity = Eggs.ByName[egg.Rarity]
		nameLabel.Text = `{egg.Rarity} Egg`
		setChip(chip, egg.Rarity, rarity.Color)
		info.Text = `Found in {zoneName(egg.Zone)}\nHatches in {Format.time(rarity.HatchSeconds)}`
		local free = data.Incubators - #data.Hatching
		setButton(primary, if free > 0 then "Place in incubator" else "Incubators full", if free > 0 then GREEN else GREY)
		primaryAction = function()
			act("PlaceEgg", entry.key)
		end
		setButton(secondary, nil)
	else
		local def = Items.ById[entry.key]
		nameLabel.Text = def.Name
		setChip(chip, `x{data.Items[entry.key]}`, def.Color)
		info.Text = def.Description
		setButton(primary, "Use", GOLD, INK)
		primaryAction = function()
			act("UseItem", entry.key)
		end
		setButton(secondary, nil)
	end
end

local function cardFor(entry: Entry, data): Frame
	local card = template:Clone()
	card.Name = entry.key
	card.Visible = true
	local viewport = card:FindFirstChild("Viewport") :: ViewportFrame
	local icon = card:FindFirstChild("Icon") :: ImageLabel
	local nameLabel = card:FindFirstChild("Name") :: TextLabel
	local sub = card:FindFirstChild("Sub") :: TextLabel
	local strip = card:FindFirstChild("Rarity") :: Frame
	local placed = card:FindFirstChild("Placed") :: Frame
	local count = card:FindFirstChild("Count") :: Frame
	showModel(viewport, icon, entry.kind, entry.key, data)
	if entry.kind == "Pet" then
		local pet = data.Pets[entry.key]
		local def = Aliens.ById[pet.Id]
		nameLabel.Text = petName(pet)
		sub.Text = `+{Format.cash(Aliens.income(pet) * (data.CashMultiplier or 1))}/s`
		strip.BackgroundColor3 = Eggs.ByName[def.Rarity].Color
		placed.Visible = pet.Placed == true
	elseif entry.kind == "Egg" then
		local egg = data.Eggs[entry.key]
		nameLabel.Text = `{egg.Rarity} Egg`
		sub.Text = if egg.Zone == "Landing" then "" else zoneName(egg.Zone)
		sub.TextColor3 = Color3.fromRGB(74, 81, 112)
		strip.BackgroundColor3 = Eggs.ByName[egg.Rarity].Color
	else
		local def = Items.ById[entry.key]
		nameLabel.Text = def.Name
		sub.Text = ""
		strip.BackgroundColor3 = def.Color
		count.Visible = true
		Ui.setText(count, `x{data.Items[entry.key]}`)
	end
	local select = card:FindFirstChild("Select") :: TextButton
	select.Activated:Connect(function()
		Ui.sound("Click")
		selected = entry
		for key, other in cards do
			local stroke = other:FindFirstChild("Stroke") :: UIStroke?
			if stroke then
				stroke.Color = if key == entry.key then MINT else INK
				stroke.Thickness = if key == entry.key then 6 else 4
			end
		end
		renderDetail()
	end)
	return card
end

local function signature(data): string
	return table.concat({ currentTab, data.InvVersion or 0, data.PlacedCount, data.Slots, #data.Hatching, data.Incubators }, "|")
end

local function render(force: boolean?)
	local data = State.data
	if not data or not gui.Enabled then
		return
	end
	local sig = signature(data)
	if sig == lastSignature and not force then
		return
	end
	lastSignature = sig
	for name, button in tabButtons do
		local on = name == currentTab
		button.BackgroundColor3 = if on then MINT else TAB_BLUE
		local label = button:FindFirstChild("Label") :: TextLabel?
		if label then
			label.TextColor3 = if on then INK else WHITE
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Enabled = not on
			end
		end
	end
	for _, card in cards do
		card:Destroy()
	end
	table.clear(cards)
	local list = entries(data)
	for i, entry in list do
		local card = cardFor(entry, data)
		card.LayoutOrder = i
		if selected and selected.key == entry.key then
			local stroke = card:FindFirstChild("Stroke") :: UIStroke?
			if stroke then
				stroke.Color = MINT
				stroke.Thickness = 6
			end
		end
		card.Parent = grid
		cards[entry.key] = card
	end
	emptyLabel.Visible = #list == 0
	local petCount, eggCount = 0, 0
	for _ in data.Pets or {} do
		petCount += 1
	end
	for _ in data.Eggs or {} do
		eggCount += 1
	end
	countsLabel.Text = `Pets {petCount}/{data.PetBagSize} · On base {data.PlacedCount}/{data.Slots}\nEggs {eggCount}/{data.EggBagSize} · Incubators {#data.Hatching}/{data.Incubators}`
	renderDetail()
end

function InventoryController:Open(tab: string?)
	currentTab = tab or currentTab
	Ui.open("Inventory")
	render(true)
end

function InventoryController:Toggle()
	if Ui.isOpen(gui) then
		Ui.close("Inventory")
	else
		InventoryController:Open()
	end
end

function InventoryController:Init(controllers)
	C = controllers
	gui = Ui.screen("Inventory")
	grid = Ui.find(gui, "Window.Grid")
	template = Ui.find(gui, "Window.Grid.Template")
	emptyLabel = Ui.find(gui, "Window.Empty")
	countsLabel = Ui.find(gui, "Window.Counts")
	detail = Ui.find(gui, "Window.Detail")
	primary = Ui.find(gui, "Window.Detail.Primary")
	secondary = Ui.find(gui, "Window.Detail.Secondary")
	for _, name in TABS do
		tabButtons[name] = Ui.find(gui, "Window.Tabs.Tab" .. name)
	end
end

function InventoryController:Start()
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Inventory")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Inventory")
	end)
	for name, button in tabButtons do
		Ui.button(button, function()
			currentTab = name
			render(true)
		end)
	end
	Ui.button(primary, function()
		if primaryAction then
			primaryAction()
		end
	end)
	Ui.button(secondary, function()
		if secondaryAction then
			secondaryAction()
		end
	end)
	Ui.button(Ui.find(gui, "Window.Bar.EquipBest"), function()
		act("EquipBest")
	end)
	Ui.button(Ui.find(gui, "Window.Bar.PlaceEggs"), function()
		act("PlaceBestEggs")
	end)
	Ui.button(Ui.find(gui, "Window.Bar.OpenReady"), function()
		if act("OpenReady") then
			Ui.close("Inventory")
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.B then
			InventoryController:Toggle()
		end
	end)
	State.Changed:Connect(function()
		render(false)
	end)
end

return InventoryController
