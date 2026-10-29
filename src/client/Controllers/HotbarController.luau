--!strict
-- Our own hotbar, working like Roblox's backpack (the default one is hidden):
--   1 = your sweeping tool (equip / put away)
--   2 = your car (spawn under you / put away). With no car it points you to the Garage.
--   3-8 = pets, egg stacks (one slot per rarity) and potions. Something new goes into the
--     first free slot; when they're all full it goes in the bag. Open the bag to drag
--     things between the bag and the hotbar (InventoryController). The layout is saved.
--     Phones show the first 4 of these slots.
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
	return if Ui.compact() then 4 else SLOTS
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
		if slotKeys[i] ~= "" and not BagItems.resolve(data, slotKeys[i]) then
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
				local free = table.find(slotKeys, "")
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

local function toggleTool()
	local h = humanoid()
	if not h or h.SeatPart then
		return
	end
	if sweepTool(player.Character) then
		h:UnequipTools()
	else
		local tool = sweepTool(player:FindFirstChildOfClass("Backpack"))
		if tool then
			h:EquipTool(tool)
		end
	end
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
	local tool = Tools.get(data.ToolTier)
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
			-- With the bag open, the bag handles taps (drag / move); otherwise use it.
			if bagOpen and C.InventoryController:SlotTapped(i) then
				return
			end
			useSlot(i)
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
	-- Eggs turn ready on their own: refresh the badge now and then.
	task.spawn(function()
		while true do
			task.wait(1)
			render()
		end
	end)
	-- Equipping happens on the character; refresh the highlight when tools move.
	local function watch(character: Model)
		character.ChildAdded:Connect(render)
		character.ChildRemoved:Connect(render)
		render()
	end
	if player.Character then
		watch(player.Character)
	end
	player.CharacterAdded:Connect(watch)
end

return HotbarController
