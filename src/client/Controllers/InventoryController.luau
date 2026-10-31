--!strict
-- The bag: a copy of Roblox's backpack inventory (B, `, or the Bag button on the hotbar).
-- The hotbar (slots 3-8, 3 on phones; HotbarController) holds pets and eggs you use most;
-- everything else is in here, in a see-through panel above the hotbar with a search box
-- and a grid of tiles in the hotbar's style. Things in the hotbar aren't listed, and the
-- counts at the top are only what's in the bag.
--   Tap a tile to use it: hold a pet or an egg out, or use a potion (after "Use item?").
--   Drag a tile onto a hotbar slot to put it there (what was there comes back to the bag),
--   drag a hotbar slot onto the panel to put it back in the bag, or onto another slot to
--   swap. Hover a tile (PC) to see its rarity, weight and passive at the top.
-- Pets on your base aren't in the bag (the Pets button manages those). Sell pets at the
-- Pet Trader on your base (TraderController).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local BagItems = require(Client.BagItems)
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Aliens = require(Shared.Config.Aliens)
local PetPassives = require(Shared.PetPassives)
local Weights = require(Shared.Config.Weights)

local INK = Color3.fromRGB(23, 25, 30)
local HELD = Color3.fromRGB(124, 245, 200)
local DRAG_START = 8 -- pixels the pointer moves before a press becomes a drag

local InventoryController = {}

local C: any
local gui: ScreenGui
local window: Frame
local grid: ScrollingFrame
local template: TextButton
local emptyLabel: TextLabel
local infoLabel: TextLabel
local searchBox: TextBox
local tiles: { [string]: { frame: TextButton, entry: BagItems.Entry } } = {}
local lastSignature = ""
local tabsFrame: Frame
local filter = "All" -- All / Pets / Eggs / Items (the buttons at the top)
local FILTER_KIND = { Pets = "Pet", Eggs = "Egg", Items = "Item" }
local TAB_ON = Color3.fromRGB(47, 191, 85)
local TAB_OFF = Color3.fromRGB(76, 141, 255)
local justDragged = 0
local fresh: { [string]: boolean } = {} -- keys tagged NEW while the bag is open ("new" badge below)

type Drag = { key: string, slot: number?, start: Vector2, ghost: Frame?, input: InputObject, name: string, color: Color3 }
local drag: Drag? = nil

local function at(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y)
end

local function inside(frame: GuiObject, point: Vector2): boolean
	local p, s = frame.AbsolutePosition, frame.AbsoluteSize
	return point.X >= p.X and point.X <= p.X + s.X and point.Y >= p.Y and point.Y <= p.Y + s.Y
end

------------------------------------------------------------------ info line

local function describe(entry: BagItems.Entry, data): string
	if entry.kind == "Pet" then
		local pet = data.Pets[entry.id]
		local def = Aliens.ById[pet.Id]
		local passive = def and def.Passive
		local short = PetPassives.short(pet.Id, pet.Huge, pet.Mutation, PetPassives.seasons())
		return `{entry.name} · {entry.rarity} · {Weights.format(BagItems.petWeight(pet))}`
			.. (if passive and short then ` · {passive.Name}: {short}` else "")
	elseif entry.kind == "Egg" then
		return `{entry.name} x{entry.count} · plant it in your park to hatch it`
	end
	return `{entry.name} x{entry.count} · tap to use`
end

-- The tile under the pointer (PC) shows in place of the filter buttons.
local function showInfo(text: string?)
	infoLabel.Text = text or ""
	infoLabel.Visible = text ~= nil
	tabsFrame.Visible = text == nil
end

------------------------------------------------------------------ tiles

local function markHeld()
	local data = State.data
	if not data then
		return
	end
	for _, t in tiles do
		local stroke = t.frame:FindFirstChild("Stroke") :: UIStroke?
		if stroke then
			local held = BagItems.isHeld(C, data, t.entry, true)
			stroke.Color = if held then HELD else INK
			stroke.Thickness = if held then 5 else 3
		end
	end
end

local function useEntry(entry: BagItems.Entry)
	BagItems.use(C, entry)
	if entry.kind == "Egg" and C.PlacementController:IsHolding() then
		Ui.close("Inventory") -- go click a spot in your park
	end
	task.defer(markHeld)
end

local function tileFor(entry: BagItems.Entry, data): TextButton
	local tile = template:Clone()
	tile.Name = entry.key
	tile.Visible = true
	local viewport = tile:FindFirstChild("Viewport") :: ViewportFrame
	local icon = tile:FindFirstChild("Icon") :: ImageLabel
	local nameLabel = tile:FindFirstChild("Name") :: TextLabel
	local count = tile:FindFirstChild("Count") :: TextLabel
	local passiveLabel = tile:FindFirstChild("Passive") :: TextLabel
	BagItems.show(viewport, icon, entry, data)
	nameLabel.Text = entry.name
	nameLabel.TextColor3 = entry.color
	Ui.fitText(nameLabel, 16, 7)
	Ui.fitText(passiveLabel, 14, 6)
	local newTag = tile:FindFirstChild("New") :: Frame?
	if newTag then
		newTag.Visible = fresh[entry.key] == true
	end
	count.Visible = entry.count > 1
	count.Text = `x{entry.count}`
	if entry.kind == "Pet" then
		local pet = data.Pets[entry.id]
		local passive = PetPassives.short(pet.Id, pet.Huge, pet.Mutation, PetPassives.seasons())
		passiveLabel.Visible = passive ~= nil
		passiveLabel.Text = passive or ""
	end
	Ui.button(tile, function()
		if os.clock() - justDragged < 0.3 then
			return
		end
		useEntry(entry)
	end)
	tile.MouseEnter:Connect(function()
		local d = State.data
		if d then
			showInfo(describe(entry, d))
		end
	end)
	tile.MouseLeave:Connect(function()
		showInfo(nil)
	end)
	-- Pets and eggs can be dragged onto the hotbar (potions stay in the bag).
	if entry.kind ~= "Item" then
		tile.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				InventoryController:BeginDrag(entry.key, nil, input)
			end
		end)
	end
	return tile
end

local function signature(data): string
	local hot = {}
	for i = 1, 6 do
		table.insert(hot, C.HotbarController:SlotKey(i))
	end
	return table.concat({ filter, searchBox.Text, data.InvVersion or 0, table.concat(hot, ","), tostring(Ui.compact()) }, "|")
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
	for _, t in tiles do
		t.frame:Destroy()
	end
	table.clear(tiles)
	local inHotbar = function(key: string): boolean
		return C.HotbarController:InHotbar(key)
	end
	local list = {}
	local kind = FILTER_KIND[filter]
	for _, entry in BagItems.bagEntries(data, searchBox.Text, inHotbar) do
		if not kind or entry.kind == kind then
			table.insert(list, entry)
		end
	end
	for i, entry in list do
		local tile = tileFor(entry, data)
		tile.LayoutOrder = i
		tile.Parent = grid
		tiles[entry.key] = { frame = tile, entry = entry }
	end
	-- Counts: only what's in the bag right now (not the hotbar).
	local pets, eggs, items = 0, 0, 0
	for _, entry in BagItems.bagEntries(data, nil, inHotbar) do
		if entry.kind == "Pet" then
			pets += 1
		elseif entry.kind == "Egg" then
			eggs += entry.count
		else
			items += entry.count
		end
	end
	local counts = { Pets = pets, Eggs = eggs, Items = items }
	for _, name in { "All", "Pets", "Eggs", "Items" } do
		local tab = tabsFrame:FindFirstChild(name) :: TextButton
		tab.BackgroundColor3 = if name == filter then TAB_ON else TAB_OFF
		local n = counts[name]
		Ui.setText(tab, if n and n > 0 then `{name} {n}` else name)
	end
	showInfo(nil)
	emptyLabel.Visible = #list == 0
	emptyLabel.Text = if searchBox.Text ~= ""
		then "Nothing matches."
		elseif kind then `No {string.lower(filter)} in your bag.`
		else "Your bag is empty. New pets and eggs go to the hotbar first, then here."
	markHeld()
end

------------------------------------------------------------------ dragging

local function startGhost(d: Drag)
	local ghost = Instance.new("Frame")
	ghost.Name = "DragGhost"
	ghost.Size = UDim2.fromOffset(76, 76)
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.BackgroundColor3 = Color3.fromRGB(11, 14, 30)
	ghost.BackgroundTransparency = 0.2
	ghost.ZIndex = 50
	local stroke = Instance.new("UIStroke")
	stroke.Color = HELD
	stroke.Thickness = 3
	stroke.Parent = ghost
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -6, 1, -6)
	label.Position = UDim2.fromOffset(3, 3)
	label.BackgroundTransparency = 1
	label.Text = d.name
	label.TextScaled = true
	label.TextColor3 = d.color
	label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
	label.ZIndex = 51
	label.Parent = ghost
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = INK
	textStroke.Thickness = 2
	textStroke.Parent = label
	ghost.Parent = gui
	d.ghost = ghost
	local tile = tiles[d.key]
	if tile then
		tile.frame.BackgroundTransparency = 0.8
	end
end

-- A press on a bag tile (slot = nil) or a hotbar slot (slot = its index) while the bag is
-- open. It turns into a drag once the pointer moves; a press that doesn't move is a tap.
function InventoryController:BeginDrag(key: string, slot: number?, input: InputObject)
	local data = State.data
	local entry = data and BagItems.resolve(data, key)
	if not entry then
		return
	end
	drag = { key = key, slot = slot, start = at(input), ghost = nil, input = input, name = entry.name, color = entry.color }
end

local function moveDrag(point: Vector2)
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
		C.HotbarController:MarkSlot(C.HotbarController:SlotAt(point))
	end
end

local function endDrag(point: Vector2?)
	local d = drag
	drag = nil
	if not d or not d.ghost then
		return
	end
	d.ghost:Destroy()
	justDragged = os.clock()
	C.HotbarController:DragEnded()
	C.HotbarController:MarkSlot(nil)
	local target = point and C.HotbarController:SlotAt(point)
	if target then
		-- Onto a slot: put it there (from another slot, the two swap).
		C.HotbarController:SetSlot(target, d.key)
		Ui.sound("Pop")
	elseif point and d.slot and inside(window, point) then
		-- A hotbar slot dropped on the bag: back into the bag.
		C.HotbarController:Remove(d.key)
		Ui.sound("Pop")
	end
	render(true)
end

------------------------------------------------------------------ "new" badge

-- "New in your bag": things in the bag now that weren't there (or not that many) the last
-- time you opened it. The Bag badge counts them and their tiles get a NEW tag (Dev,
-- 2026-10-30: the badge showed but you couldn't tell what was new). Counted by hotbar key
-- (P:uid, E:rarity, I:id). Things in the hotbar don't count: you can already see them.
-- Whatever you had when you joined counts as seen.
local seen: { [string]: number }? = nil

local function counts(data): { [string]: number }
	local out = {}
	for _, entry in BagItems.bagEntries(data, nil, nil) do
		out[entry.key] = entry.count
	end
	return out
end

local function inBag(key: string): boolean
	return not C.HotbarController:InHotbar(key)
end

function InventoryController:NewCount(): number
	local data = State.data
	if not data then
		return 0
	end
	local now = counts(data)
	if not seen then
		seen = now
		return 0
	end
	local count = 0
	for key, n in now do
		if inBag(key) then
			count += math.max(0, n - ((seen :: any)[key] or 0))
		end
	end
	return count
end

-- Moves what's new into `fresh` (tagged while the bag is open) and marks everything seen.
-- True when the set of tagged tiles changed.
local function markSeen(): boolean
	local data = State.data
	if not data then
		return false
	end
	local now = counts(data)
	local changed = false
	if seen then
		for key, n in now do
			if n > ((seen :: any)[key] or 0) and inBag(key) and not fresh[key] then
				fresh[key] = true
				changed = true
			end
		end
	end
	seen = now
	return changed
end

------------------------------------------------------------------ public

function InventoryController:Open(_tab: string?)
	table.clear(fresh)
	markSeen()
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

-- Called when what you hold changes (PlacementController).
function InventoryController:RefreshHeld()
	if gui and gui.Enabled then
		markHeld()
	end
end

function InventoryController:Init(controllers)
	C = controllers
	gui = Ui.screen("Inventory")
	window = Ui.find(gui, "Window")
	grid = Ui.find(gui, "Window.Grid")
	template = Ui.find(gui, "Window.Grid.Template")
	emptyLabel = Ui.find(gui, "Window.Empty")
	infoLabel = Ui.find(gui, "Window.Info")
	tabsFrame = Ui.find(gui, "Window.Tabs")
	Ui.fitText(infoLabel, 16, 7) -- one line that shrinks (it wrapped into the search box)
	searchBox = Ui.find(gui, "Window.Search")
end

function InventoryController:Start()
	-- Tiles drawn before the pet/egg models loaded show placeholders: redraw once they're in.
	AssetLibrary.onCoreReady(function()
		lastSignature = ""
		render(true)
	end)
	Ui.button(Ui.find(window, "Close"), function()
		Ui.close("Inventory")
	end)
	for _, name in { "All", "Pets", "Eggs", "Items" } do
		local tab = tabsFrame:FindFirstChild(name) :: TextButton
		Ui.fitText(tab:FindFirstChild("Label") :: TextLabel, 16, 8)
		Ui.button(tab, function()
			filter = name
			render(true)
		end)
	end
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		render(false)
	end)
	UserInputService.InputChanged:Connect(function(input)
		local d = drag
		if d and (input.UserInputType == Enum.UserInputType.MouseMovement or input == d.input) then
			moveDrag(at(input))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local d = drag
		if d and (input.UserInputType == Enum.UserInputType.MouseButton1 or input == d.input) then
			endDrag(at(input))
		end
	end)
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		C.HotbarController:SetBagOpen(gui.Enabled)
		if not gui.Enabled then
			endDrag(nil)
		end
	end)
	State.Changed:Connect(function()
		-- You're looking at it, so what arrives now is tagged NEW and then counts as seen.
		local tagged = gui.Enabled and markSeen()
		render(tagged)
	end)
end

return InventoryController
