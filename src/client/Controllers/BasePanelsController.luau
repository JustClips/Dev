--!strict
-- The two panels from Steal an Egg, opened from the Eggs / Pets buttons on the right (the
-- Tools button under them opens the Tools window). Each is a small popup beside the
-- buttons (PetsPanel / EggsPanel screens); a click outside closes it:
--   Pets ("3/4 Active"): pets on your base with Unequip (bag pets stay in the Bag),
--     +1 Slot for cash (Economy.SlotCashPrices), +3 Slots for Robux (the pass) and Equip Best.
--   Eggs ("Growing Eggs"): every egg in an incubator with its timer, Open when ready or
--     Skip for Robux, and Open All. Eggs are planted from the bag (tap one, tap the park).
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
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Tools = require(Shared.Config.Tools)

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
local toolsBadge: Frame
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
	-- Slot buttons say what you get and what it costs.
	local buySlot = Ui.find(panel, "BuySlot") :: TextButton
	local price = data.SlotCashPrice
	if price then
		setButton(buySlot, `+1 Slot {Format.cash(price)}`, if BigNum.gte(data.Cash, price) then GREEN else GREY)
	else
		setButton(buySlot, "Rebirth: more slots", GREY)
	end
	local addSlot = Ui.find(panel, "AddSlot") :: TextButton
	local pass = Products.PassByKey.ExtraSlots
	if data.Gamepasses.ExtraSlots or not pass then
		setButton(addSlot, "+3 Slots: owned", GREY)
	else
		setButton(addSlot, `+{Economy.GamepassSlots} Slots {Ui.ROBUX}{pass.Price}`, GOLD, INK)
	end
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
		-- Tap the pet itself for its info card.
		local select = row:FindFirstChild("Select") :: TextButton?
		if select then
			local uid = entry.uid
			Ui.button(select, function()
				C.PetInfoController:Open(uid)
			end)
		end
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
	-- Only equipped pets (Dev): pets in the bag are in the Bag; Equip Best puts the best out.
	for _, entry in placed do
		add(entry, true)
	end
	empties.Active.Visible = count == 0
	empties.Active.Text = if #bag > 0
		then "No pets equipped. Tap Equip Best to put your best pets out!"
		else "No pets yet. Bring eggs home and hatch them!"
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
	local eggCount = 0
	for _ in data.Eggs or {} do
		eggCount += 1
	end
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
	end
	empties.Growing.Visible = #data.Hatching == 0
	empties.Growing.Text = if eggCount > 0
		then "No eggs growing. Tap an egg in your bag, then tap your park to plant it!"
		else "No eggs growing. Sweep leaves to find eggs!"
	for _, item in eggRows do
		local entry = hatchEntry(data, item.uid)
		if entry then
			updateEggRow(item.row, entry)
		end
	end
end

-------------------------------------------------------------------------- shared

local function renderBadges(data)
	-- Eggs: only eggs ready to open, which are what the panel shows (counting eggs still in
	-- the bag put a number on the button with nothing to see inside).
	local ready = 0
	for _, entry in data.Hatching do
		if entry.EndsAt <= State.now() then
			ready += 1
		end
	end
	Ui.setBadge(eggsBadge, ready)
	-- Pets: the panel only lists equipped pets, so no count (a number with nothing new
	-- inside confused Dev on the Eggs button).
	Ui.setBadge(petsBadge, nil)
	-- Tools: a badge when the next tool is affordable.
	local nextTool = Tools.get(data.ToolTier + 1)
	Ui.setBadge(toolsBadge, if data.ToolTier < Tools.MaxTier and BigNum.gte(data.Cash, nextTool.Price) then 1 else nil)
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

-- Eggs / Pets / Tools stacked on the right edge. Phones: from the top right corner, hugging
-- the edge (Ui.edges), with HudController's boost chips in a column left of them; PC:
-- above the next-tool card.
-- Each button is placed by its centre instead of by a list layout, so a button growing on
-- hover or press doesn't push the other one around.
local function layoutButtons(_scale: number, compact: boolean)
	local list = buttons:FindFirstChildOfClass("UIListLayout")
	if list then
		list:Destroy()
	end
	local eggsButton = buttons:FindFirstChild("EggsButton") :: GuiObject
	local petsButton = buttons:FindFirstChild("PetsButton") :: GuiObject
	eggsButton.AnchorPoint = Vector2.new(0.5, 0.5)
	petsButton.AnchorPoint = Vector2.new(0.5, 0.5)
	local toolsButton = buttons:FindFirstChild("ToolsButton") :: GuiObject
	toolsButton.AnchorPoint = Vector2.new(0.5, 0.5)
	local s = _scale
	if compact then
		local screenGui = buttons:FindFirstAncestorOfClass("ScreenGui") :: ScreenGui
		local _, right = Ui.edges(screenGui)
		buttons.AnchorPoint = Vector2.new(1, 0)
		buttons.Position = UDim2.new(1, -right, 0, 10)
		buttons.Size = UDim2.fromOffset(80, 280)
		eggsButton.Position = UDim2.fromOffset(40, 40)
		petsButton.Position = UDim2.fromOffset(40, 136)
		toolsButton.Position = UDim2.fromOffset(40, 232)
		-- Popups open to the left of the column.
		for _, panel in panels do
			panel.AnchorPoint = Vector2.new(1, 0)
			Ui.setHome(panel, UDim2.new(1, -(right + math.ceil(80 * s) + 10), 0, 4))
		end
	else
		-- Top of the right-hand stack (Eggs, Pets, Tools, Auto), centred on the same line
		-- as the left rail (HudController.rightStackTop).
		buttons.AnchorPoint = Vector2.new(1, 0)
		buttons.Position = UDim2.new(1, -14, 0.5, C.HudController.rightStackTop(s))
		buttons.Size = UDim2.fromOffset(80, 324)
		eggsButton.Position = UDim2.fromOffset(40, 68)
		petsButton.Position = UDim2.fromOffset(40, 176)
		toolsButton.Position = UDim2.fromOffset(40, 284)
		-- Popups open to the left of the buttons.
		for _, panel in panels do
			panel.AnchorPoint = Vector2.new(1, 0.5)
			Ui.setHome(panel, UDim2.new(1, -math.ceil(14 + 96 * s), 0.5, -30))
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
	toolsBadge = Ui.find(gui, "Buttons.ToolsButton.Badge")
end

function BasePanelsController:Start()
	Ui.button(Ui.find(gui, "Buttons.PetsButton"), function()
		BasePanelsController:Toggle("Active")
	end)
	Ui.button(Ui.find(gui, "Buttons.EggsButton"), function()
		BasePanelsController:Toggle("Growing")
	end)
	Ui.button(Ui.find(gui, "Buttons.ToolsButton"), function()
		BasePanelsController:Show(nil)
		C.GarageController:Toggle()
	end)
	for name, screen in screens do
		local function close()
			if open == name then
				BasePanelsController:Show(nil)
			end
		end
		Ui.button(Ui.find(screen, "Window.Close"), close)
		Ui.button(Ui.find(screen, "ClickAway"), close)
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
	Ui.button(Ui.find(panels.Active, "BuySlot"), function()
		local data = State.data
		if data and not data.SlotCashPrice then
			C.HudController:Toast("Rebirth for more pet slots!", "Info")
			C.RebirthController:Toggle()
			return
		end
		act("BuySlot")
	end)
	Ui.button(Ui.find(panels.Growing, "OpenAll"), function()
		act("OpenReady")
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
