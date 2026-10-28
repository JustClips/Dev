--!strict
-- The two panels from Steal an Egg, opened from the Eggs / Pets buttons on the right. Each
-- is a normal window (PetsPanel / EggsPanel screens, same size as every other window):
--   Pets ("3/4 Active"): pets on your base with Unequip, then pets in your bag with Equip,
--     + Slots (the slots pass, or rebirth once you own it) and Equip Best.
--   Eggs ("Growing Eggs"): every egg in an incubator with its timer, Open when ready or
--     Skip for Robux, Open All, and Place Eggs (fills free incubators from your bag).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local ModelView = require(Client.ModelView)
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AlienModel = require(Shared.AlienModel)
local AssetLibrary = require(Shared.AssetLibrary)
local Aliens = require(Shared.Config.Aliens)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)

local GREEN = Color3.fromRGB(61, 220, 90)
local RED = Color3.fromRGB(255, 77, 94)
local GOLD = Color3.fromRGB(255, 200, 60)
local GREY = Color3.fromRGB(166, 174, 194)
local INK = Color3.fromRGB(27, 31, 58)
local WHITE = Color3.new(1, 1, 1)
local MAX_ROWS = 60

local BasePanelsController = {}

local SCREENS = { Active = "PetsPanel", Growing = "EggsPanel" }

local C: any
local gui: ScreenGui
local buttons: Frame
local screens: { [string]: ScreenGui } = {}
local panels: { [string]: Frame } = {}
local templates: { [string]: Frame } = {}
local lists: { [string]: ScrollingFrame } = {}
local empties: { [string]: TextLabel } = {}
local eggsBadge: Frame
local petsBadge: Frame
local open: string? = nil
local signatures: { [string]: string } = {}
-- Growing rows, refreshed every second for the timers.
local eggRows: { { row: Frame, uid: string } } = {}

local function act(action: string, arg: string?): boolean
	local ok, message = Net.func("Inventory"):InvokeServer(action, arg)
	if message and message ~= "" then
		C.HudController:Toast(message, if ok then "Good" else "Bad")
	end
	return ok
end

local function setButton(button: TextButton, text: string, color: Color3, labelColor: Color3?)
	Ui.setText(button, text)
	button.BackgroundColor3 = color
	local label = button:FindFirstChild("Label") :: TextLabel?
	if label then
		label.TextColor3 = labelColor or WHITE
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = (labelColor or WHITE) == WHITE
		end
	end
end

local function clear(name: string)
	for _, child in lists[name]:GetChildren() do
		if child:IsA("Frame") and child ~= templates[name] then
			child:Destroy()
		end
	end
end

local function newRow(name: string, order: number): Frame
	local row = templates[name]:Clone()
	row.Visible = true
	row.LayoutOrder = order
	row.Parent = lists[name]
	return row
end

-------------------------------------------------------------------------- Pets panel

local function renderPets(data)
	local panel = panels.Active
	local placed, bag = {}, {}
	for uid, pet in data.Pets or {} do
		table.insert(if pet.Placed then placed else bag, { uid = uid, pet = pet, income = Aliens.income(pet) })
	end
	local byIncome = function(a, b)
		if a.income == b.income then
			return a.uid < b.uid
		end
		return a.income > b.income
	end
	table.sort(placed, byIncome)
	table.sort(bag, byIncome)
	Ui.setText(Ui.find(panel, "Header.Title"), `{data.PlacedCount}/{data.Slots} Active`)
	local sig = table.concat({ data.InvVersion or 0, data.PlacedCount, data.Slots, data.CashMultiplier or 1 }, "|")
	if signatures.Active == sig then
		return
	end
	signatures.Active = sig
	clear("Active")
	local full = data.PlacedCount >= data.Slots
	local count = 0
	local function add(entry, isPlaced: boolean)
		count += 1
		if count > MAX_ROWS then
			return
		end
		local def = Aliens.ById[entry.pet.Id]
		local row = newRow("Active", count)
		local nameLabel = row:FindFirstChild("Name") :: TextLabel
		nameLabel.Text = (if entry.pet.Huge then "Huge " else "") .. AlienModel.displayName(entry.pet.Id, entry.pet.Mutation)
		nameLabel.TextColor3 = Eggs.ByName[def.Rarity].Color
		;(row:FindFirstChild("Sub") :: TextLabel).Text = `{Format.cash(entry.income * (data.CashMultiplier or 1))}/s`
		ModelView.show(row:FindFirstChild("Viewport") :: ViewportFrame, AssetLibrary.alien(entry.pet.Id, entry.pet.Mutation), "Alien_" .. entry.pet.Id)
		local button = row:FindFirstChild("Action") :: TextButton
		if isPlaced then
			setButton(button, "Unequip", RED)
			Ui.button(button, function()
				act("PickUpPet", entry.uid)
			end)
		else
			setButton(button, if full then "Full" else "Equip", if full then GREY else GREEN)
			Ui.button(button, function()
				act("PlacePet", entry.uid)
			end)
		end
	end
	for _, entry in placed do
		add(entry, true)
	end
	for _, entry in bag do
		add(entry, false)
	end
	empties.Active.Visible = count == 0
	empties.Active.Text = "No pets yet. Bring eggs home and hatch them!"
end

-------------------------------------------------------------------------- Eggs panel

local function skipPrice(rarity: string): number?
	local product = Products.ProductByKey["SkipHatch" .. rarity]
	return product and product.Price
end

local function updateEggRow(row: Frame, entry)
	local left = math.max(0, entry.EndsAt - State.now())
	local sub = row:FindFirstChild("Sub") :: TextLabel
	local button = row:FindFirstChild("Action") :: TextButton
	if left <= 0 then
		sub.Text = "READY!"
		sub.TextColor3 = GOLD
		setButton(button, "Open", GREEN)
	else
		sub.Text = Format.time(left)
		sub.TextColor3 = Color3.fromRGB(124, 255, 140)
		local price = skipPrice(entry.Rarity)
		setButton(button, if price then `Skip R${price}` else "Skip", GOLD, INK)
	end
end

local function hatchEntry(data, uid: string)
	for _, entry in data.Hatching do
		if entry.Uid == uid then
			return entry
		end
	end
	return nil
end

local function renderEggs(data)
	local free = data.Incubators - #data.Hatching
	local eggCount = 0
	for _ in data.Eggs or {} do
		eggCount += 1
	end
	local placeButton = Ui.find(panels.Growing, "PlaceEggs")
	setButton(placeButton, if eggCount == 0 then "No eggs in bag" else `Place Eggs ({free} free)`, if eggCount > 0 and free > 0 then Color3.fromRGB(76, 141, 255) else GREY)
	local uids = {}
	for _, entry in data.Hatching do
		table.insert(uids, entry.Uid)
	end
	local sig = table.concat(uids, ",") .. "|" .. data.Incubators
	if signatures.Growing ~= sig then
		signatures.Growing = sig
		clear("Growing")
		table.clear(eggRows)
		local sorted = table.clone(data.Hatching)
		table.sort(sorted, function(a, b)
			return a.EndsAt < b.EndsAt
		end)
		for i, entry in sorted do
			local row = newRow("Growing", i)
			local nameLabel = row:FindFirstChild("Name") :: TextLabel
			nameLabel.Text = `{entry.Rarity} Egg`
			nameLabel.TextColor3 = Eggs.ByName[entry.Rarity].Color
			ModelView.show(row:FindFirstChild("Viewport") :: ViewportFrame, AssetLibrary.egg(entry.Rarity), "Egg_" .. entry.Rarity)
			local uid = entry.Uid
			Ui.button(row:FindFirstChild("Action") :: TextButton, function()
				local current = State.data and hatchEntry(State.data, uid)
				if not current then
					return
				end
				if current.EndsAt <= State.now() then
					act("OpenEgg", uid)
				else
					act("SkipHatch", uid)
				end
			end)
			table.insert(eggRows, { row = row, uid = uid })
		end
		empties.Growing.Visible = #sorted == 0
		empties.Growing.Text = if eggCount > 0 then "Your incubators are empty. Tap Place Eggs!" else "No eggs growing. Sweep dust to find eggs!"
	end
	for _, item in eggRows do
		local entry = hatchEntry(data, item.uid)
		if entry then
			updateEggRow(item.row, entry)
		end
	end
end

-------------------------------------------------------------------------- shared

local function renderBadges(data)
	local ready, waiting = 0, 0
	for _, entry in data.Hatching do
		if entry.EndsAt <= State.now() then
			ready += 1
		end
	end
	if #data.Hatching < data.Incubators then
		for _ in data.Eggs or {} do
			waiting += 1
		end
	end
	Ui.setBadge(eggsBadge, if ready > 0 then ready else waiting)
	local bagPets = 0
	for _, pet in data.Pets or {} do
		if not pet.Placed then
			bagPets += 1
		end
	end
	local canPlace = math.min(bagPets, data.Slots - data.PlacedCount)
	Ui.setBadge(petsBadge, canPlace)
end

local function render()
	local data = State.data
	if not data or not data.Pets then
		return
	end
	renderBadges(data)
	if open == "Active" then
		renderPets(data)
	elseif open == "Growing" then
		renderEggs(data)
	end
end

function BasePanelsController:Show(name: string?)
	open = name
	if name then
		Ui.open(SCREENS[name])
	else
		for _, screenName in SCREENS do
			Ui.close(screenName)
		end
	end
	table.clear(signatures)
	render()
end

-- Phones: the two buttons sit in a row at the top right (HudController puts the boost
-- chips under them); PC: stacked on the right edge above the next-tool card.
local function layoutButtons(_scale: number, compact: boolean)
	local list = buttons:FindFirstChildOfClass("UIListLayout")
	if compact then
		buttons.AnchorPoint = Vector2.new(1, 0)
		buttons.Position = UDim2.new(1, -14, 0, 8)
		buttons.Size = UDim2.fromOffset(188, 80)
		if list then
			list.FillDirection = Enum.FillDirection.Horizontal
			list.Padding = UDim.new(0, 16)
			list.VerticalAlignment = Enum.VerticalAlignment.Top
		end
	else
		buttons.AnchorPoint = Vector2.new(1, 1)
		buttons.Position = UDim2.new(1, -14, 0.5, -130)
		buttons.Size = UDim2.fromOffset(80, 216)
		if list then
			list.FillDirection = Enum.FillDirection.Vertical
			list.Padding = UDim.new(0, 28)
			list.VerticalAlignment = Enum.VerticalAlignment.Bottom
		end
	end
end

function BasePanelsController:Toggle(name: string)
	BasePanelsController:Show(if open == name then nil else name)
end

function BasePanelsController:Init(controllers)
	C = controllers
	gui = Ui.screen("BasePanels")
	buttons = Ui.find(gui, "Buttons")
	for name, screenName in SCREENS do
		screens[name] = Ui.screen(screenName)
		panels[name] = Ui.find(screens[name], "Window")
		lists[name] = Ui.find(panels[name], "List")
		templates[name] = Ui.find(panels[name], "List.Template")
		empties[name] = Ui.find(panels[name], "Empty")
	end
	eggsBadge = Ui.find(gui, "Buttons.EggsButton.Badge")
	petsBadge = Ui.find(gui, "Buttons.PetsButton.Badge")
end

function BasePanelsController:Start()
	Ui.button(Ui.find(gui, "Buttons.PetsButton"), function()
		BasePanelsController:Toggle("Active")
	end)
	Ui.button(Ui.find(gui, "Buttons.EggsButton"), function()
		BasePanelsController:Toggle("Growing")
	end)
	for name, screen in screens do
		local function close()
			if open == name then
				BasePanelsController:Show(nil)
			end
		end
		Ui.button(Ui.find(screen, "Window.Close"), close)
		Ui.button(Ui.find(screen, "Dim"), close)
		-- Another window opening closes this one (Ui.open); keep `open` in step.
		screen:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not screen.Enabled and open == name then
				open = nil
			end
		end)
	end
	Ui.onScale(layoutButtons)
	Ui.button(Ui.find(panels.Active, "EquipBest"), function()
		act("EquipBest")
	end)
	Ui.button(Ui.find(panels.Active, "AddSlot"), function()
		local data = State.data
		if data and not data.Gamepasses.ExtraSlots then
			Net.func("PromptPurchase"):InvokeServer("ExtraSlots")
		else
			C.HudController:Toast("Rebirth for more pet slots!", "Info")
			C.RebirthController:Toggle()
		end
	end)
	Ui.button(Ui.find(panels.Growing, "OpenAll"), function()
		act("OpenReady")
	end)
	Ui.button(Ui.find(panels.Growing, "PlaceEggs"), function()
		act("PlaceBestEggs")
	end)
	State.Changed:Connect(render)
	task.spawn(function()
		while true do
			task.wait(1)
			render()
		end
	end)
end

return BasePanelsController
