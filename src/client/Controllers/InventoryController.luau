--!strict
-- The bag (hotbar slot 3, key 3 or B), Steal an Egg style: one solid window above the
-- hotbar with Pets / Eggs / Items tabs (tap the lit tab again for everything) and a search
-- box, and a grid of cards. No detail card: tapping a pet or an egg holds it out in your
-- hands (tap it again to put it away), tapping a potion uses it. Pets on your base aren't
-- listed (the Pets button on the right manages those). Sell pets at the Pet Trader on your
-- base (TraderController). Every pet and egg shows its weight (Config/Weights).
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
local Eggs = require(Shared.Config.Eggs)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Weights = require(Shared.Config.Weights)

local TABS = { "Pets", "Eggs", "Items" }
local TAB_ON = Color3.fromRGB(61, 220, 90)
local TAB_OFF = Color3.fromRGB(11, 14, 30)
local HELD = Color3.fromRGB(61, 220, 90)

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
local searchBox: TextBox
local tabButtons: { [string]: TextButton } = {}
local currentTab = "All"
local cards: { [string]: Frame } = {}
local lastSignature = ""

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

local function petName(pet): string
	return (if pet.Huge then "Huge " else "") .. AlienModel.displayName(pet.Id, pet.Mutation)
end

local function eggName(egg): string
	local size = egg.Size or "Normal"
	return (if size ~= "Normal" then size .. " " else "") .. `{egg.Rarity} Egg`
end

local function petWeight(pet): number
	local def = Aliens.ById[pet.Id]
	return pet.Weight or Weights.petKg(def and def.Rarity or "Common")
end

local function matches(name: string): boolean
	local q = string.lower(searchBox.Text)
	return q == "" or string.find(string.lower(name), q, 1, true) ~= nil
end

-- What's in your hands right now (pet or egg uid).
local function heldKey(): string?
	return C.PlacementController:HeldKey()
end

local function entries(data): { Entry }
	local list: { Entry } = {}
	if currentTab == "All" or currentTab == "Pets" then
		for uid, pet in data.Pets or {} do
			if not pet.Placed and matches(petName(pet)) then
				local def = Aliens.ById[pet.Id]
				local rarity = def and Eggs.order(def.Rarity) or 0
				local order = 1e9 - math.min(Aliens.income(pet), 1e9 - 1) / 1e9 * 1e8 - rarity
				table.insert(list, { kind = "Pet", key = uid, order = order })
			end
		end
	end
	if currentTab == "All" or currentTab == "Eggs" then
		for uid, egg in data.Eggs or {} do
			if matches(eggName(egg)) then
				local mult = Weights.eggMult(egg.Rarity, egg.Weight)
				table.insert(list, { kind = "Egg", key = uid, order = 2e9 - Eggs.order(egg.Rarity) * 100 - math.min(mult, 99) })
			end
		end
	end
	if currentTab == "All" or currentTab == "Items" then
		for i, def in Items.List do
			if (data.Items and data.Items[def.Id] or 0) > 0 and matches(def.Name) then
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

local function showModel(viewport: ViewportFrame, icon: ImageLabel, kind: string, key: string, data)
	icon.Visible = kind == "Item"
	viewport.Visible = kind ~= "Item"
	if kind == "Pet" then
		local pet = data.Pets[key]
		ModelView.show(viewport, AssetLibrary.alien(pet.Id, pet.Mutation), "Alien_" .. pet.Id)
	elseif kind == "Egg" then
		local egg = data.Eggs[key]
		ModelView.show(viewport, AssetLibrary.egg(egg.Rarity), "Egg_" .. egg.Rarity)
	else
		local def = Items.ById[key]
		icon.Image = AssetLibrary.image(def.Icon)
	end
end

-- The card of whatever you hold gets a green outline and a HOLDING tag.
local function markHeld()
	local key = heldKey()
	for k, card in cards do
		local on = k == key
		local stroke = card:FindFirstChild("Stroke") :: UIStroke?
		if stroke then
			stroke.Color = HELD
			stroke.Thickness = if on then 3 else 0
		end
		local tag = card:FindFirstChild("Held") :: GuiObject?
		if tag then
			tag.Visible = on
		end
	end
end

local function tapped(entry: Entry)
	local data = State.data
	if not data then
		return
	end
	Ui.sound("Click")
	if entry.kind == "Item" then
		local def = Items.ById[entry.key]
		if not def then
			return
		end
		C.ConfirmController:Ask({
			title = "Use item?",
			name = def.Name,
			text = def.Description,
			icon = def.Icon,
			yes = "Use",
		}, function()
			act("UseItem", entry.key)
		end)
		return
	end
	if heldKey() == entry.key then
		C.PlacementController:Stop()
		markHeld()
		return
	end
	if entry.kind == "Egg" then
		if not data.Eggs or not data.Eggs[entry.key] then
			return
		end
		if #data.Hatching >= data.Incubators then
			C.HudController:Toast(`Only {data.Incubators} eggs can grow at once. Open one first!`, "Bad")
			return
		end
		Ui.close("Inventory")
		C.PlacementController:Hold(entry.key)
	else
		if not data.Pets or not data.Pets[entry.key] then
			return
		end
		C.PlacementController:HoldPet(entry.key)
	end
	markHeld()
end

local function cardFor(entry: Entry, data): Frame
	local card = template:Clone()
	card.Name = entry.key
	card.Visible = true
	local viewport = card:FindFirstChild("Viewport") :: ViewportFrame
	local icon = card:FindFirstChild("Icon") :: ImageLabel
	local nameLabel = card:FindFirstChild("Name") :: TextLabel
	local count = card:FindFirstChild("Count") :: TextLabel
	showModel(viewport, icon, entry.kind, entry.key, data)
	count.Visible = true
	if entry.kind == "Pet" then
		local pet = data.Pets[entry.key]
		local def = Aliens.ById[pet.Id]
		nameLabel.Text = petName(pet)
		nameLabel.TextColor3 = Eggs.ByName[def.Rarity].Color
		count.Text = Weights.format(petWeight(pet))
	elseif entry.kind == "Egg" then
		local egg = data.Eggs[entry.key]
		nameLabel.Text = eggName(egg)
		nameLabel.TextColor3 = Eggs.ByName[egg.Rarity].Color
		count.Text = Weights.format(egg.Weight or Weights.eggKg(egg.Rarity))
	else
		local def = Items.ById[entry.key]
		nameLabel.Text = def.Name
		nameLabel.TextColor3 = def.Color
		count.Text = `x{data.Items[entry.key]}`
	end
	local select = card:FindFirstChild("Select") :: TextButton
	select.Activated:Connect(function()
		tapped(entry)
	end)
	return card
end

local function signature(data): string
	return table.concat({ currentTab, searchBox.Text, data.InvVersion or 0, data.PlacedCount, data.Slots }, "|")
end

local function render(force: boolean?)
	local data = State.data
	if not data or not gui.Enabled then
		return
	end
	local sig = signature(data)
	if sig == lastSignature and not force then
		markHeld()
		return
	end
	lastSignature = sig
	for name, button in tabButtons do
		button.BackgroundColor3 = if name == currentTab then TAB_ON else TAB_OFF
		button.BackgroundTransparency = 0
	end
	for _, card in cards do
		card:Destroy()
	end
	table.clear(cards)
	local list = entries(data)
	for i, entry in list do
		local card = cardFor(entry, data)
		card.LayoutOrder = i
		card.Parent = grid
		cards[entry.key] = card
	end
	markHeld()
	emptyLabel.Visible = #list == 0
	local petCount, eggCount, itemCount = 0, 0, 0
	for _, pet in data.Pets or {} do
		if not pet.Placed then
			petCount += 1
		end
	end
	for _ in data.Eggs or {} do
		eggCount += 1
	end
	for _, n in data.Items or {} do
		itemCount += n
	end
	countsLabel.Text = if currentTab == "Eggs"
		then `Eggs: {eggCount}/{data.EggBagSize}`
		elseif currentTab == "Items" then `Items: {itemCount}`
		else `Pets: {petCount}/{data.PetBagSize}   Eggs: {eggCount}/{data.EggBagSize}`
end

-- "New in your bag" for the hotbar badge: what's in the bag now that wasn't there the
-- last time you opened it (eggs, pets not on your base, more of a potion). Whatever you
-- already had when you joined counts as seen.
local seen: { [string]: number }? = nil

local function bagKeys(data): { [string]: number }
	local keys = {}
	for uid in data.Eggs or {} do
		keys["E" .. uid] = 1
	end
	for uid, pet in data.Pets or {} do
		if not pet.Placed then
			keys["P" .. uid] = 1
		end
	end
	for id, n in data.Items or {} do
		if n > 0 then
			keys["I" .. id] = n
		end
	end
	return keys
end

function InventoryController:NewCount(): number
	local data = State.data
	if not data then
		return 0
	end
	local now = bagKeys(data)
	if not seen then
		seen = now
		return 0
	end
	local count = 0
	for key, n in now do
		count += math.max(0, n - ((seen :: any)[key] or 0))
	end
	return count
end

local function markSeen()
	if State.data then
		seen = bagKeys(State.data)
	end
end

function InventoryController:Open(tab: string?)
	currentTab = tab or currentTab
	Ui.open("Inventory")
	markSeen()
	render(true)
end

function InventoryController:Toggle()
	if Ui.isOpen(gui) then
		Ui.close("Inventory")
	else
		InventoryController:Open()
	end
end

-- Called when what you hold changes (PlacementController).
function InventoryController:RefreshHeld()
	if gui and gui.Enabled then
		markHeld()
	end
end

function InventoryController:Init(controllers)
	C = controllers
	gui = Ui.screen("Inventory")
	grid = Ui.find(gui, "Window.Grid")
	template = Ui.find(gui, "Window.Grid.Template")
	emptyLabel = Ui.find(gui, "Window.Empty")
	countsLabel = Ui.find(gui, "Window.Count")
	searchBox = Ui.find(gui, "Window.Search")
	for _, name in TABS do
		tabButtons[name] = Ui.find(gui, "Window.Tabs.Tab" .. name)
	end
end

function InventoryController:Start()
	for name, button in tabButtons do
		Ui.button(button, function()
			currentTab = if currentTab == name then "All" else name
			render(true)
		end)
	end
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Inventory")
	end)
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		render(false)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.B then
			InventoryController:Toggle()
		end
	end)
	State.Changed:Connect(function()
		render(false)
		if gui.Enabled then
			markSeen() -- you're looking at it, so nothing in it is new
		end
	end)
end

return InventoryController
