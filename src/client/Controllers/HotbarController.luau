--!strict
-- Our own hotbar, working like Roblox's backpack (the default one is hidden):
--   1 = your sweeping tool (equip / put away)
--   2 = your car (spawn under you / put away). With no car it opens the Cars tab in Gear.
--   3-8 = pets and egg stacks (one slot per rarity; potions stay in the bag). Something
--     new goes into the first free slot; when they're all full it goes in the bag. Open
--     the bag to drag things between the bag and the hotbar, or between slots
--     (InventoryController). The layout is saved. Phones have 3 of these slots.
--   Bag (B or `) = the bag. A badge counts what's new in it since you last opened it.
--   G = drop the egg on your head. Only shown while you carry one.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local BagItems = require(Client.BagItems)
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Net = require(Shared.Net)
local Tools = require(Shared.Config.Tools)

local INK = Color3.fromRGB(27, 31, 58)
local GREY = Color3.fromRGB(150, 156, 176)
local MINT = Color3.fromRGB(124, 245, 200)

local HotbarController = {}

local C: any
local player = Players.LocalPlayer
local toolSlot: TextButton
local carSlot: TextButton
local bagSlot: TextButton
local dropSlot: TextButton
local dropping = false

local setSelected: (TextButton, boolean) -> ()

local SLOTS = 6
local ITEM_KEYS = { Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight }
local itemSlots: { TextButton } = {}
local slotKeys: { string } = { "", "", "", "", "", "" } -- what's in slots 3-8
local shownKeys: { string } = {} -- what each slot is drawing (to skip rebuilding models)
local known: { [string]: boolean }? = nil -- keys we've already placed somewhere
local saveToken = 0
local bagOpen = false
local markedSlot: number? = nil -- lit by the bag (picked slot, or the slot you drag over)

local function visibleSlots(): number
	return if Ui.compact() then 3 else SLOTS
end

local function save()
	saveToken += 1
	local token = saveToken
	task.delay(1.5, function()
		if token == saveToken then
			Net.event("SetSetting"):FireServer("Hotbar", table.clone(slotKeys))
		end
	end)
end

-- Keeps slots in step with the bag: things that are gone leave their slot, new things
-- take the first free slot (or stay in the bag when there's none).
local function syncSlots(data): boolean
	local changed = false
	if not known then
		local saved = data.Settings and data.Settings.Hotbar
		if type(saved) == "table" then
			for i = 1, SLOTS do
				slotKeys[i] = if type(saved[i]) == "string" then saved[i] else ""
			end
		end
	end
	for i = 1, SLOTS do
		local key = slotKeys[i]
		-- Gone, or a potion (those are only used from the bag).
		if key ~= "" and (string.sub(key, 1, 2) == "I:" or not BagItems.resolve(data, key)) then
			slotKeys[i] = ""
			changed = true
		end
	end
	local now: { [string]: boolean } = {}
	for _, e in BagItems.fillOrder(data) do
		now[e.key] = true
		local isNew = known == nil or not (known :: any)[e.key]
		if isNew and not table.find(slotKeys, e.key) then
			-- First load with a saved layout: what isn't in it stays in the bag.
			local savedLayout = known == nil and data.Settings and data.Settings.Hotbar ~= nil
			if not savedLayout then
				local free = HotbarController:FreeSlot()
				if free then
					slotKeys[free] = e.key
					changed = true
				end
			end
		end
	end
	known = now
	if changed then
		save()
	end
	return changed
end

local justDragged = 0

-- The bag says a drag just ended (so the slot's click that follows is ignored).
function HotbarController:DragEnded()
	justDragged = os.clock()
end

-- Puts a hotbar key in a slot (1-6). If it's already in another slot the two swap.
function HotbarController:SetSlot(index: number, key: string)
	if index < 1 or index > SLOTS then
		return
	end
	local from = table.find(slotKeys, key)
	if from == index then
		return
	end
	if from then
		slotKeys[from] = slotKeys[index]
	end
	slotKeys[index] = key
	save()
	HotbarController:Refresh()
end

-- Takes something out of the hotbar (it stays in the bag).
function HotbarController:Remove(key: string)
	local i = table.find(slotKeys, key)
	if i then
		slotKeys[i] = ""
		save()
		HotbarController:Refresh()
	end
end

-- True when a key sits in a slot you can see (the bag doesn't list those).
function HotbarController:InHotbar(key: string): boolean
	local i = table.find(slotKeys, key)
	return i ~= nil and i <= visibleSlots()
end

function HotbarController:FreeSlot(): number?
	for i = 1, visibleSlots() do
		if slotKeys[i] == "" then
			return i
		end
	end
	return nil
end

function HotbarController:SlotKey(index: number): string
	return slotKeys[index] or ""
end

-- The slot button under a screen point (for dragging from the bag), if any.
function HotbarController:SlotAt(point: Vector2): number?
	for i = 1, visibleSlots() do
		local slot = itemSlots[i]
		if slot and slot.Visible then
			local p, sz = slot.AbsolutePosition, slot.AbsoluteSize
			if point.X >= p.X and point.X <= p.X + sz.X and point.Y >= p.Y and point.Y <= p.Y + sz.Y then
				return i
			end
		end
	end
	return nil
end

function HotbarController:SlotButton(index: number): TextButton?
	return itemSlots[index]
end

-- Lights one item slot (the bag uses it for the picked slot and drag targets).
function HotbarController:MarkSlot(index: number?)
	if markedSlot ~= index then
		markedSlot = index
		HotbarController:Refresh()
	end
end

-- While the bag is open, empty slots show too (as places to drop things).
function HotbarController:SetBagOpen(open: boolean)
	bagOpen = open
	HotbarController:Refresh()
end

local function useSlot(index: number)
	local data = State.data
	local key = slotKeys[index]
	if not data or not key or key == "" then
		return
	end
	local entry = BagItems.resolve(data, key)
	if entry then
		Ui.sound("Click")
		BagItems.use(C, entry)
	end
end

local function renderItems(data)
	local count = visibleSlots()
	for i = 1, SLOTS do
		local slot = itemSlots[i]
		local key = slotKeys[i]
		local entry = if key ~= "" and i <= count then BagItems.resolve(data, key) else nil
		slot.Visible = i <= count and (entry ~= nil or bagOpen)
		local nameLabel = slot:FindFirstChild("Name") :: TextLabel
		local countLabel = slot:FindFirstChild("Count") :: TextLabel
		local viewport = slot:FindFirstChild("Viewport") :: ViewportFrame
		local icon = slot:FindFirstChild("Icon") :: ImageLabel
		if entry then
			nameLabel.Text = entry.name
			nameLabel.TextColor3 = entry.color
			countLabel.Visible = entry.count > 1
			countLabel.Text = `x{entry.count}`
			if shownKeys[i] ~= key then
				shownKeys[i] = key
				BagItems.show(viewport, icon, entry, data)
			end
			setSelected(slot, markedSlot == i or BagItems.isHeld(C, data, entry, true))
		else
			shownKeys[i] = nil
			nameLabel.Text = ""
			countLabel.Visible = false
			viewport.Visible = false
			for _, child in viewport:GetChildren() do
				if child:IsA("Model") or child:IsA("WorldModel") then
					child:Destroy()
				end
			end
			icon.Visible = false
			setSelected(slot, markedSlot == i)
		end
	end
end

local function humanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function sweepTool(container: Instance?): Tool?
	if not container then
		return nil
	end
	for _, child in container:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("SweepTool") then
			return child
		end
	end
	return nil
end

-- Asks the server for a fresh tool in your hands (the same fix as equipping another tool
-- in Gear and back, which Dev found).
local rebuilding = false
local function rebuildTool()
	if rebuilding then
		return
	end
	rebuilding = true
	task.spawn(function()
		pcall(function()
			Net.func("EquipTool"):InvokeServer()
		end)
		rebuilding = false
	end)
end

local function usable(tool: Tool?): boolean
	return tool ~= nil and tool:FindFirstChild("Handle") ~= nil
end

local function toggleTool()
	local h = humanoid()
	local character = player.Character
	if not h or not character or h.SeatPart or h.Health <= 0 then
		return
	end
	local held = sweepTool(character)
	if held then
		if usable(held) then
			h:UnequipTools()
		else
			rebuildTool() -- in your hands but broken (no Handle)
		end
		return
	end
	local tool = sweepTool(player:FindFirstChildOfClass("Backpack"))
	if not usable(tool) then
		rebuildTool() -- missing or broken
		return
	end
	h:EquipTool(tool :: Tool)
	-- If it didn't make it into your hands (the server swapped the tool at the same moment),
	-- get a fresh one.
	task.delay(0.6, function()
		if player.Character == character and not sweepTool(character) and not h.SeatPart and h.Health > 0 then
			local again = sweepTool(player:FindFirstChildOfClass("Backpack"))
			if again ~= tool or not usable(again) then
				rebuildTool()
			elseif again then
				h:EquipTool(again)
			end
		end
	end)
end

local function toggleCar()
	local data = State.data
	if data and not data.BestVehicle and not data.InVehicle then
		C.HudController:Toast("No car yet! Pick one in Tools.", "Info")
		C.GarageController:Open("Cars")
		return
	end
	local ok, message = Net.func("ToggleVehicle"):InvokeServer()
	if not ok and message then
		C.HudController:Toast(message, "Bad")
	end
end

local function dropEgg()
	local data = State.data
	if dropping or not data or #(data.CarriedEggs or {}) == 0 then
		return
	end
	dropping = true
	local ok, message = Net.func("Inventory"):InvokeServer("DropEgg")
	dropping = false
	if message then
		C.HudController:Toast(message, if ok then "Info" else "Bad")
	end
end

-- Controller LB / RB: the previous / next slot (your tool, then the filled pet and egg
-- slots), like Roblox's own backpack.
function HotbarController:Cycle(direction: number)
	local data = State.data
	local h = humanoid()
	if not data or not h or h.SeatPart or h.Health <= 0 then
		return
	end
	local list: { number } = { 0 } -- 0 = the tool, 1-6 = item slots
	local current = if sweepTool(player.Character) then 1 else nil
	for i = 1, visibleSlots() do
		local key = slotKeys[i]
		local entry = if key ~= "" then BagItems.resolve(data, key) else nil
		if entry then
			table.insert(list, i)
			if BagItems.isHeld(C, data, entry, true) then
				current = #list
			end
		end
	end
	local nextIndex = if current then (current - 1 + direction) % #list + 1 elseif direction > 0 then 1 else #list
	if nextIndex == current then
		return
	end
	local target = list[nextIndex]
	if target == 0 then
		toggleTool()
	else
		useSlot(target)
	end
end

function HotbarController:ToggleCar()
	task.spawn(toggleCar)
end

function HotbarController:DropEgg()
	task.spawn(dropEgg)
end

-- Key hints on the slots: keyboard keys, or the controller buttons.
local function keyHints()
	local pad = Ui.gamepad()
	local function set(slot: TextButton, keyboard: string, gamepad: string)
		local label = slot:FindFirstChild("Key") and (slot:FindFirstChild("Key") :: Frame):FindFirstChild("Label") :: TextLabel?
		if label then
			label.Text = if pad then gamepad else keyboard
		end
	end
	set(toolSlot, "1", "")
	set(carSlot, "2", "↑")
	set(bagSlot, "B", "Y")
	set(dropSlot, "G", "↓")
	for i, slot in itemSlots do
		set(slot, tostring(i + 2), "")
	end
end

-- The selected slot gets a thick mint outline instead of the navy one.
function setSelected(slot: TextButton, on: boolean)
	local stroke = slot:FindFirstChild("Stroke") :: UIStroke?
	if stroke then
		stroke.Color = if on then MINT else INK
		stroke.Thickness = if on then 6 else 4
	end
end

local function render(_: any?)
	local data = State.data
	if not data then
		return
	end
	local tool = Tools.get(data.EffectiveTier or data.ToolTier)
	;(toolSlot:FindFirstChild("Name") :: TextLabel).Text = tool.Name
	;(toolSlot:FindFirstChild("Icon") :: ImageLabel).Image = AssetLibrary.toolIcon(tool.Id)
	local car = Tools.vehicle(data.BestVehicle or "")
	local carName = carSlot:FindFirstChild("Name") :: TextLabel
	local carIcon = carSlot:FindFirstChild("Icon") :: ImageLabel
	carName.Text = if car then car.Name else "No car"
	carName.TextColor3 = if car then INK else GREY
	carIcon.Image = if car then AssetLibrary.carIcon(car.Id) else AssetLibrary.image("Icon_Lock")
	setSelected(carSlot, data.InVehicle)
	-- Badge: what's new in the bag since you last opened it (ready eggs in your park have
	-- their own badge on the Eggs button, so they don't count here).
	Ui.setBadge(bagSlot:FindFirstChild("Badge") :: Frame, C.InventoryController:NewCount())
	setSelected(toolSlot, not data.InVehicle and sweepTool(player.Character) ~= nil)
	syncSlots(data)
	renderItems(data)
	local carrying = #(data.CarriedEggs or {})
	dropSlot.Visible = carrying > 0
	;(dropSlot:FindFirstChild("Name") :: TextLabel).Text = if carrying > 1 then `Drop 1 of {carrying}` else "Drop egg"
end

local function hideDefaultBackpack()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			return
		end
		task.wait(1)
	end
end

function HotbarController:Init(controllers)
	C = controllers
	local hud = Ui.screen("Hud")
	toolSlot = Ui.find(hud, "Hotbar.ToolSlot")
	carSlot = Ui.find(hud, "Hotbar.CarSlot")
	bagSlot = Ui.find(hud, "Hotbar.BagSlot")
	dropSlot = Ui.find(hud, "Hotbar.DropSlot")
	for i = 1, SLOTS do
		itemSlots[i] = Ui.find(hud, "Hotbar.Item" .. i)
	end
end

function HotbarController:Refresh()
	render()
end

function HotbarController:Start()
	-- Slots drawn before the pet/egg models loaded show placeholders: redraw once they're in.
	AssetLibrary.onCoreReady(function()
		table.clear(shownKeys)
		HotbarController:Refresh()
	end)
	task.spawn(hideDefaultBackpack)
	Ui.button(toolSlot, toggleTool)
	Ui.button(carSlot, toggleCar)
	Ui.button(bagSlot, function()
		C.InventoryController:Toggle()
	end)
	Ui.button(dropSlot, function()
		task.spawn(dropEgg)
	end)
	for i, slot in itemSlots do
		Ui.button(slot, function()
			if os.clock() - justDragged < 0.3 then
				return -- that was the end of a drag
			end
			useSlot(i)
		end)
		-- With the bag open, slots can be dragged (to another slot, or back into the bag).
		slot.InputBegan:Connect(function(input)
			local touch = input.UserInputType == Enum.UserInputType.Touch
			if bagOpen and slotKeys[i] ~= "" and (touch or input.UserInputType == Enum.UserInputType.MouseButton1) then
				C.InventoryController:BeginDrag(slotKeys[i], i, input)
			end
		end)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local itemIndex = table.find(ITEM_KEYS, input.KeyCode)
		if input.KeyCode == Enum.KeyCode.One then
			toggleTool()
		elseif input.KeyCode == Enum.KeyCode.Two then
			toggleCar()
		elseif itemIndex then
			useSlot(itemIndex)
		elseif input.KeyCode == Enum.KeyCode.B or input.KeyCode == Enum.KeyCode.Backquote then
			C.InventoryController:Toggle()
		elseif input.KeyCode == Enum.KeyCode.G then
			task.spawn(dropEgg)
		end
	end)
	State.observe(render)
	keyHints()
	UserInputService.LastInputTypeChanged:Connect(function()
		task.defer(keyHints)
	end)
	-- Eggs turn ready on their own: refresh the badge now and then.
	task.spawn(function()
		while true do
			task.wait(1)
			render()
		end
	end)
	-- You spawn holding your sweeping tool (Dev, 2026-10-30: after a rejoin it sat in the
	-- bag). The server equips it too, but that can land before the character is ready, so
	-- the client makes sure: for the first seconds after spawning, a tool in the backpack
	-- goes into your hands unless you're already holding something or sitting in a car.
	local function autoEquip(character: Model)
		local deadline = os.clock() + 15
		while os.clock() < deadline and character.Parent and player.Character == character do
			local h = character:FindFirstChildOfClass("Humanoid")
			if sweepTool(character) or character:FindFirstChildOfClass("Tool") then
				return
			end
			local tool = sweepTool(player:FindFirstChildOfClass("Backpack"))
			if h and h.Health > 0 and not h.SeatPart and tool and character:IsDescendantOf(game:GetService("Workspace")) then
				h:EquipTool(tool)
			end
			task.wait(0.5)
		end
	end
	-- Equipping happens on the character; refresh the highlight when tools move.
	local function watch(character: Model)
		character.ChildAdded:Connect(render)
		character.ChildRemoved:Connect(render)
		render()
		task.spawn(autoEquip, character)
	end
	if player.Character then
		watch(player.Character)
	end
	player.CharacterAdded:Connect(watch)
end

return HotbarController
