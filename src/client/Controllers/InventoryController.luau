--!strict
-- The bag (B or `, or the Bag button on the hotbar). Works like Roblox's backpack: the
-- hotbar (slots 3-8, HotbarController) holds what you use most, everything else is in
-- here. Category tabs down the left (All, Pets, Eggs, Items) with counts, a search box,
-- and a grid of cards in each thing's rarity colour.
--   Drag a card onto a hotbar slot to put it there (what was there comes back to the bag).
--   Tap a card to pick it: the bar at the bottom says what it is and what you can do
--     (Hold / Plant / Use, Equip for pets, To hotbar / To bag). Tap it again to do the
--     main thing. With the bag open, tapping a hotbar slot picks what's in it, or puts the
--     picked card there.
-- Pets on your base aren't in the bag (the Pets button manages those). Sell pets at the
-- Pet Trader on your base (TraderController).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local BagItems = require(Client.BagItems)
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Aliens = require(Shared.Config.Aliens)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local PetPassives = require(Shared.PetPassives)
local Weights = require(Shared.Config.Weights)

local TABS = { "All", "Pets", "Eggs", "Items" }
local TAB_ON = Color3.fromRGB(61, 220, 90)
local TAB_OFF = Color3.fromRGB(11, 14, 30)
local INK = Color3.fromRGB(23, 25, 30)
local WHITE = Color3.new(1, 1, 1)
local GREEN = Color3.fromRGB(61, 220, 90)
local BLUE = Color3.fromRGB(76, 141, 255)
local GREY = Color3.fromRGB(150, 156, 176)
local DRAG_START = 8 -- pixels the pointer moves before a press becomes a drag

local InventoryController = {}

local C: any
local gui: ScreenGui
local window: Frame
local grid: ScrollingFrame
local template: Frame
local emptyLabel: TextLabel
local countsLabel: TextLabel
local searchBox: TextBox
local details: Frame
local hint: TextLabel
local tabButtons: { [string]: TextButton } = {}
local currentTab = "All"
local cards: { [string]: { frame: Frame, entry: BagItems.Entry } } = {}
local lastSignature = ""
local picked: BagItems.Entry? = nil
local pickedFromSlot: number? = nil
local drag: { entry: BagItems.Entry, start: Vector2, ghost: Frame?, input: InputObject }? = nil

-- Card colour: the rarity colour, darkened so white text reads on it.
local function cardColor(color: Color3): Color3
	return color:Lerp(Color3.fromRGB(20, 22, 30), 0.5)
end

local function toast(ok: boolean, message: string?)
	if message and message ~= "" then
		C.HudController:Toast(message, if ok then "Good" else "Bad")
	end
end

local function setButton(button: TextButton, text: string, color: Color3, visible: boolean?)
	Ui.setText(button, text)
	button.BackgroundColor3 = color
	button.Visible = visible ~= false
end

------------------------------------------------------------------ details bar

local function showDetails()
	local data = State.data
	local entry = picked
	details.Visible = entry ~= nil
	hint.Visible = entry == nil
	if not data or not entry then
		return
	end
	local title = Ui.find(details, "Title") :: TextLabel
	local sub = Ui.find(details, "Sub") :: TextLabel
	local primary = Ui.find(details, "Primary") :: TextButton
	local secondary = Ui.find(details, "Secondary") :: TextButton
	local move = Ui.find(details, "PinButton") :: TextButton
	title.Text = entry.name
	title.TextColor3 = entry.color
	local held = BagItems.isHeld(C, data, entry, pickedFromSlot ~= nil)
	if entry.kind == "Pet" then
		local pet = data.Pets[entry.id]
		local def = Aliens.ById[pet.Id]
		local passive = def and def.Passive
		local short = PetPassives.short(pet.Id, pet.Huge)
		sub.Text = `{entry.rarity} · {Weights.format(BagItems.petWeight(pet))}`
			.. (if passive and short then `\n{passive.Name}: {short}` else "")
		setButton(primary, if held then "Put away" else "Hold", if held then GREY else GREEN)
		local full = data.PlacedCount >= data.Slots
		setButton(secondary, if full then "Base full" else "Equip", if full then GREY else BLUE)
	elseif entry.kind == "Egg" then
		local egg = data.Eggs[entry.id]
		sub.Text = if entry.count > 1
			then `{entry.count} eggs · plant one in your park to hatch it`
			else `{entry.rarity} · {Weights.format(BagItems.eggWeight(egg))} · plant it in your park to hatch it`
		setButton(primary, if held then "Put away" else "Plant", if held then GREY else GREEN)
		secondary.Visible = false
	else
		local def = Items.ById[entry.id]
		sub.Text = if def then `{def.Description} (you have {entry.count})` else ""
		setButton(primary, "Use", GREEN)
		secondary.Visible = false
	end
	local inHotbar = C.HotbarController:InHotbar(entry.key)
	setButton(move, if inHotbar then "To bag" else "To hotbar", Color3.fromRGB(255, 200, 60))
	local viewport = Ui.find(details, "Viewport") :: ViewportFrame
	local icon = Ui.find(details, "Icon") :: ImageLabel
	if details:GetAttribute("Shown") ~= entry.key .. entry.id then
		details:SetAttribute("Shown", entry.key .. entry.id)
		BagItems.show(viewport, icon, entry, data)
	end
end

local function markCards()
	local data = State.data
	if not data then
		return
	end
	for _, c in cards do
		local on = picked ~= nil and pickedFromSlot == nil and picked.id == c.entry.id
		local stroke = c.frame:FindFirstChild("Stroke") :: UIStroke?
		if stroke then
			stroke.Color = if on then WHITE else INK
			stroke.Thickness = if on then 4 else 3
		end
		local tag = c.frame:FindFirstChild("Held") :: GuiObject?
		if tag then
			tag.Visible = BagItems.isHeld(C, data, c.entry)
		end
	end
	-- The hotbar slot you picked from stays lit while the bag is open.
	if not drag then
		C.HotbarController:MarkSlot(pickedFromSlot)
	end
end

local function pick(entry: BagItems.Entry?, slot: number?)
	picked = entry
	pickedFromSlot = slot
	showDetails()
	markCards()
end

------------------------------------------------------------------ cards and drag

local render: (boolean?) -> ()

local function primaryAction(entry: BagItems.Entry)
	Ui.sound("Click")
	BagItems.use(C, entry)
	if entry.kind == "Egg" and C.PlacementController:IsHolding() then
		Ui.close("Inventory") -- go click your park
	end
	task.defer(function()
		showDetails()
		markCards()
	end)
end


-- Pointer positions are in GUI space (InputObject.Position), like AbsolutePosition.
local function at(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y)
end

local function endDrag(point: Vector2?)
	local d = drag
	drag = nil
	if not d then
		return
	end
	local ghost = d.ghost
	if ghost then
		ghost:Destroy()
		local slot = point and C.HotbarController:SlotAt(point)
		if slot then
			Ui.sound("Pop")
			C.HotbarController:SetSlot(slot, d.entry.key)
			pick(nil)
			render(true)
		end
		C.HotbarController:MarkSlot(pickedFromSlot)
		local card = cards[d.entry.id]
		if card then
			card.frame.BackgroundTransparency = 0
		end
		return
	end
	-- A tap: pick it, or do the main thing if it was already picked.
	if picked and pickedFromSlot == nil and picked.id == d.entry.id then
		primaryAction(d.entry)
	else
		Ui.sound("Click")
		pick(d.entry)
	end
end

local function startGhost(d)
	local card = cards[d.entry.id]
	local ghost = Instance.new("Frame")
	ghost.Name = "DragGhost"
	ghost.Size = UDim2.fromOffset(84, 84)
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.BackgroundColor3 = cardColor(d.entry.color)
	ghost.BackgroundTransparency = 0.15
	ghost.ZIndex = 50
	local stroke = Instance.new("UIStroke")
	stroke.Color = WHITE
	stroke.Thickness = 3
	stroke.Parent = ghost
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -6, 1, -6)
	label.Position = UDim2.fromOffset(3, 3)
	label.BackgroundTransparency = 1
	label.Text = d.entry.name
	label.TextScaled = true
	label.TextColor3 = WHITE
	label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
	label.ZIndex = 51
	label.Parent = ghost
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = INK
	textStroke.Thickness = 2
	textStroke.Parent = label
	ghost.Parent = gui
	d.ghost = ghost
	if card then
		card.frame.BackgroundTransparency = 0.6
	end
end

local function moveGhost(point: Vector2)
	local d = drag
	if not d then
		return
	end
	if not d.ghost and (point - d.start).Magnitude > DRAG_START then
		startGhost(d)
	end
	local ghost = d.ghost
	if ghost then
		local origin = gui.AbsolutePosition
		ghost.Position = UDim2.fromOffset(point.X - origin.X, point.Y - origin.Y)
		-- Light up the slot under the pointer.
		C.HotbarController:MarkSlot(C.HotbarController:SlotAt(point))
	end
end

local function cardFor(entry: BagItems.Entry, data): Frame
	local card = template:Clone()
	card.Name = entry.id
	card.Visible = true
	card.BackgroundColor3 = cardColor(entry.color)
	local viewport = card:FindFirstChild("Viewport") :: ViewportFrame
	local icon = card:FindFirstChild("Icon") :: ImageLabel
	local nameLabel = card:FindFirstChild("Name") :: TextLabel
	local count = card:FindFirstChild("Count") :: TextLabel
	local passiveLabel = card:FindFirstChild("Passive") :: TextLabel
	local glow = card:FindFirstChild("Glow") :: ImageLabel
	glow.ImageColor3 = entry.color:Lerp(WHITE, 0.5)
	BagItems.show(viewport, icon, entry, data)
	nameLabel.Text = entry.name
	nameLabel.TextColor3 = WHITE
	if entry.kind == "Pet" then
		local pet = data.Pets[entry.id]
		count.Text = Weights.format(BagItems.petWeight(pet))
		local passive = PetPassives.short(pet.Id, pet.Huge)
		passiveLabel.Visible = passive ~= nil
		passiveLabel.Text = passive or ""
	elseif entry.kind == "Egg" then
		count.Text = Weights.format(BagItems.eggWeight(data.Eggs[entry.id]))
	else
		count.Text = `x{entry.count}`
	end
	local pin = card:FindFirstChild("Pin")
	if pin then
		pin:Destroy() -- (old pin star; moving to the hotbar is by dragging now)
	end
	local select = card:FindFirstChild("Select") :: TextButton
	select.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			drag = { entry = entry, start = at(input), ghost = nil, input = input }
		end
	end)
	return card
end

local function signature(data): string
	local hot = {}
	for i = 1, 6 do
		table.insert(hot, C.HotbarController:SlotKey(i))
	end
	return table.concat({ currentTab, searchBox.Text, data.InvVersion or 0, data.PlacedCount, data.Slots, table.concat(hot, ","), tostring(Ui.compact()) }, "|")
end

render = function(force: boolean?)
	local data = State.data
	if not data or not gui.Enabled then
		return
	end
	local sig = signature(data)
	if sig == lastSignature and not force then
		markCards()
		return
	end
	lastSignature = sig
	for name, button in tabButtons do
		button.BackgroundColor3 = if name == currentTab then TAB_ON else TAB_OFF
	end
	for _, c in cards do
		c.frame:Destroy()
	end
	table.clear(cards)
	local shown = 0
	for _, entry in BagItems.list(data, currentTab, searchBox.Text) do
		-- Things in the hotbar aren't listed (like Roblox's backpack).
		if C.HotbarController:InHotbar(entry.key) then
			continue
		end
		shown += 1
		local card = cardFor(entry, data)
		card.LayoutOrder = shown
		card.Parent = grid
		cards[entry.id] = { frame = card, entry = entry }
	end
	emptyLabel.Visible = shown == 0
	emptyLabel.Text = if currentTab == "All" and searchBox.Text == ""
		then "Nothing else in your bag. New things go to the hotbar first!"
		else "Nothing here."
	local pets, eggs, items = BagItems.counts(data)
	countsLabel.Text = `Pets {pets}/{data.PetBagSize}  ·  Eggs {eggs}/{data.EggBagSize}`
	local counts = { All = pets + eggs + items, Pets = pets, Eggs = eggs, Items = items }
	for name, button in tabButtons do
		local label = button:FindFirstChild("Count") :: TextLabel?
		if label then
			label.Text = tostring(counts[name] or 0)
		end
	end
	-- Keep the picked thing if it's still there.
	if picked then
		local still = if pickedFromSlot then BagItems.resolve(data, picked.key) else nil
		if not still and not pickedFromSlot then
			for _, entry in BagItems.list(data, "All") do
				if entry.id == picked.id then
					still = entry
					break
				end
			end
		end
		picked = still
		if not still then
			pickedFromSlot = nil
		end
	end
	showDetails()
	markCards()
end

------------------------------------------------------------------ "new" badge

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

------------------------------------------------------------------ public

function InventoryController:Open(tab: string?)
	currentTab = if tab and table.find(TABS, tab) then tab else currentTab
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
		showDetails()
		markCards()
	end
end

-- A hotbar slot was tapped while the bag is open: put the picked card there, or pick what
-- the slot holds. Returns true when it handled the tap.
function InventoryController:SlotTapped(index: number): boolean
	local data = State.data
	if not data then
		return false
	end
	if picked and pickedFromSlot == nil then
		C.HotbarController:SetSlot(index, picked.key)
		Ui.sound("Pop")
		pick(nil)
		render(true)
		return true
	end
	local key = C.HotbarController:SlotKey(index)
	local entry = if key ~= "" then BagItems.resolve(data, key) else nil
	if entry then
		if pickedFromSlot == index then
			primaryAction(entry)
		else
			Ui.sound("Click")
			pick(entry, index)
		end
		return true
	end
	return false
end

function InventoryController:Init(controllers)
	C = controllers
	gui = Ui.screen("Inventory")
	window = Ui.find(gui, "Window")
	grid = Ui.find(gui, "Window.Grid")
	template = Ui.find(gui, "Window.Grid.Template")
	emptyLabel = Ui.find(gui, "Window.Empty")
	countsLabel = Ui.find(gui, "Window.Count")
	searchBox = Ui.find(gui, "Window.Search")
	details = Ui.find(gui, "Window.Details")
	hint = Ui.find(gui, "Window.Hint")
	for _, name in TABS do
		tabButtons[name] = Ui.find(gui, "Window.Tabs.Tab" .. name)
	end
end

function InventoryController:Start()
	for name, button in tabButtons do
		Ui.button(button, function()
			currentTab = name
			render(true)
		end)
	end
	Ui.button(Ui.find(window, "Close"), function()
		Ui.close("Inventory")
	end)
	Ui.button(Ui.find(details, "Primary"), function()
		if picked then
			primaryAction(picked)
		end
	end)
	Ui.button(Ui.find(details, "Secondary"), function()
		local entry = picked
		if not entry or entry.kind ~= "Pet" then
			return
		end
		local ok, message = Net.func("Inventory"):InvokeServer("PlacePet", entry.id)
		toast(ok, if ok then "Pet put on your base!" else message)
	end)
	Ui.button(Ui.find(details, "PinButton"), function()
		local entry = picked
		if not entry then
			return
		end
		if C.HotbarController:InHotbar(entry.key) then
			C.HotbarController:Remove(entry.key)
		else
			local free = C.HotbarController:FreeSlot()
			if not free then
				toast(false, "Hotbar is full. Drag it onto a slot to swap!")
				return
			end
			C.HotbarController:SetSlot(free, entry.key)
		end
		Ui.sound("Pop")
		pick(nil)
		render(true)
	end)
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		render(false)
	end)
	UserInputService.InputChanged:Connect(function(input)
		local d = drag
		if not d then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or (input.UserInputType == Enum.UserInputType.Touch and input == d.input) then
			moveGhost(at(input))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local d = drag
		if not d then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or (input.UserInputType == Enum.UserInputType.Touch and input == d.input) then
			endDrag(at(input))
		end
	end)
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		C.HotbarController:SetBagOpen(gui.Enabled)
		if not gui.Enabled then
			endDrag(nil)
			pick(nil)
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
