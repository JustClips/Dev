--!strict
-- Admin panel (only for the players in Config/Admin; the server checks every call too,
-- see AdminService). The ADMIN button at the top right (or F2) opens it.
--
-- A switch at the top says where everything runs: THIS SERVER or ALL SERVERS (for admin
-- abuse events). Tabs:
--   Events   timed boosts (egg luck, cash, Huge chance, hatch speed, walk speed), weather,
--            Egg Rain and egg drops, each with its own value and duration; any number can
--            run at once, and the running ones are listed with a Stop button
--   Give     cash, eggs, pets, potions, tools, cars and boosts to you, everyone or a player
--   Message  an announcement card for everyone
--   Poll     a question everyone votes on
-- Built in code in the game's style (white panels, thick dark outlines, stud buttons), not
-- gen_ui, so the panel never ships in other players' StarterGui.
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Admin = require(Shared.Config.Admin)
local AssetLibrary = require(Shared.AssetLibrary)
local Aliens = require(Shared.Config.Aliens)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Tools = require(Shared.Config.Tools)
local Weather = require(Shared.Config.Weather)

local AdminController = {}

local C: any
local player = Players.LocalPlayer

-- The game's UI style (tools/gen_ui.py).
local FONT = "rbxasset://fonts/families/Montserrat.json"
local SURFACE = Color3.fromRGB(247, 248, 250)
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(23, 25, 30)
local SUB = Color3.fromRGB(91, 96, 112)
local CHIP = Color3.fromRGB(228, 232, 240)
local BLUE = Color3.fromRGB(76, 141, 255)
local GREEN = Color3.fromRGB(61, 220, 90)
local RED = Color3.fromRGB(255, 77, 94)
local ORANGE = Color3.fromRGB(255, 140, 50)
local GOLD = Color3.fromRGB(255, 200, 60)
local PURPLE = Color3.fromRGB(155, 107, 255)

local W, H = 820, 520 -- every window in the game is this size
local TAB_W = 150

---------------------------------------------------------------------------- building

-- Things show in the order they're made (lists sort by LayoutOrder).
local made = 0
local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local obj = Instance.new(class)
	if obj:IsA("GuiObject") and props.LayoutOrder == nil then
		made += 1
		obj.LayoutOrder = made
	end
	for k, v in props do
		(obj :: any)[k] = v
	end
	if parent then
		obj.Parent = parent
	end
	return obj
end

local function outline(parent: Instance, thickness: number?)
	make("UIStroke", {
		Thickness = thickness or 3,
		Color = INK,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Miter,
	}, parent)
end

local function shade(parent: Instance, dark: Color3?)
	make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, WHITE),
			ColorSequenceKeypoint.new(0.55, WHITE),
			ColorSequenceKeypoint.new(1, dark or Color3.fromRGB(201, 208, 222)),
		}),
		Rotation = 90,
	}, parent)
end

local function text(parent: Instance, value: string, size: UDim2, ts: number, color: Color3?, weight: Enum.FontWeight?): TextLabel
	return make("TextLabel", {
		Size = size,
		BackgroundTransparency = 1,
		Text = value,
		TextColor3 = color or INK,
		FontFace = Font.new(FONT, weight or Enum.FontWeight.Bold),
		TextSize = ts,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	}, parent)
end

-- A panel with a dark outline.
local function panel(parent: Instance, size: UDim2, tint: Color3?): Frame
	local f = make("Frame", { Size = size, BackgroundColor3 = tint or WHITE, BorderSizePixel = 0 }, parent)
	outline(f, 3)
	return f
end

local function light(color: Color3): boolean
	return color.R * 0.3 + color.G * 0.59 + color.B * 0.11 > 0.72
end

-- A toy button: colour fill, stud texture, dark outline, white label with an outline.
local function button(parent: Instance, label: string, color: Color3, size: UDim2, fn: () -> (), ts: number?): TextButton
	local b = make("TextButton", {
		Size = size,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
	}, parent)
	outline(b, 3)
	shade(b)
	make("ImageLabel", {
		Name = "Studs",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = AssetLibrary.image("Stud"),
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(40, 40),
		ImageColor3 = color,
		ImageTransparency = 0.45,
		ZIndex = 1,
	}, b)
	local l = make("TextLabel", {
		Name = "Label",
		Size = UDim2.new(1, -8, 1, 0),
		Position = UDim2.fromOffset(4, 0),
		BackgroundTransparency = 1,
		Text = label,
		TextColor3 = if light(color) then INK else WHITE,
		FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
		TextSize = ts or 18,
		TextWrapped = true,
		ZIndex = 3,
	}, b)
	make("UIStroke", { Thickness = 2, Color = INK, Enabled = not light(color) }, l)
	b.Activated:Connect(function()
		Ui.sound("Click")
		fn()
	end)
	return b
end

local function paint(b: TextButton, color: Color3, label: string?)
	b.BackgroundColor3 = color
	local studs = b:FindFirstChild("Studs") :: ImageLabel?
	if studs then
		studs.ImageColor3 = color
	end
	local l = b:FindFirstChild("Label") :: TextLabel?
	if l then
		if label then
			l.Text = label
		end
		l.TextColor3 = if light(color) then INK else WHITE
		local s = l:FindFirstChildOfClass("UIStroke")
		if s then
			s.Enabled = not light(color)
		end
	end
end

local function input(parent: Instance, placeholder: string, size: UDim2, default: string?): TextBox
	local b = make("TextBox", {
		Size = size,
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Text = default or "",
		PlaceholderText = placeholder,
		PlaceholderColor3 = Color3.fromRGB(150, 156, 172),
		TextColor3 = INK,
		FontFace = Font.new(FONT, Enum.FontWeight.Bold),
		TextSize = 17,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, b)
	outline(b, 2.5)
	return b
end

local function vlist(parent: Instance, pad: number?)
	make("UIListLayout", { Padding = UDim.new(0, pad or 8), SortOrder = Enum.SortOrder.LayoutOrder }, parent)
end

local function row(parent: Instance, height: number): Frame
	local r = make("Frame", { Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1 }, parent)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, r)
	return r
end

-- A heading with a frame under it that grows with what's put in it.
local function section(page: Instance, title: string): Frame
	local holder = make("Frame", {
		Size = UDim2.new(1, -10, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, page)
	vlist(holder, 6)
	text(holder, string.upper(title), UDim2.new(1, 0, 0, 22), 17, SUB, Enum.FontWeight.Heavy)
	return make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, holder)
end

-- A wrap of chips where one is picked (blue). Returns pick(value) and the state.
type Choice = { label: string, value: any, color: Color3? }
local function chips(parent: Instance, choices: { Choice }, cell: Vector2, onPick: ((any) -> ())?)
	local grid = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, parent)
	make("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell.X, cell.Y),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	local state = { value = nil :: any }
	local buttons: { [any]: TextButton } = {}
	local base: { [any]: Color3 } = {}
	local function pick(value: any)
		state.value = value
		for v, b in buttons do
			paint(b, if v == value then BLUE else base[v])
			local s = b:FindFirstChildOfClass("UIStroke")
			if s then
				s.Thickness = if v == value then 4 else 3
			end
		end
		if onPick then
			onPick(value)
		end
	end
	for i, choice in choices do
		local color = choice.color or CHIP
		local b = button(grid, choice.label, color, UDim2.fromOffset(cell.X, cell.Y), function()
			pick(choice.value)
		end, 15)
		b.LayoutOrder = i
		buttons[choice.value] = b
		base[choice.value] = color
	end
	return pick, state, grid
end

local function rarityColor(rarity: string): Color3
	local def = Eggs.ByName[rarity]
	return if def then def.Color else CHIP
end

------------------------------------------------------------------------------ state

local gui: ScreenGui
local window: Frame
local pages: { [string]: ScrollingFrame } = {}
local tabButtons: { [string]: TextButton } = {}
local TAB_COLORS = { Events = ORANGE, Give = GREEN, Message = BLUE, Poll = PURPLE }
local global = false
local target: any = "me"

local function call(action: string, payload: { [string]: any }?): boolean
	local p = payload or {}
	p.Global = global
	local ok, message = Net.func("Admin"):InvokeServer(action, p)
	if message and message ~= "" then
		C.HudController:Toast(message, if ok then "Good" else "Bad")
	end
	return ok
end

local function showTab(name: string)
	for n, page in pages do
		page.Visible = n == name
	end
	for n, b in tabButtons do
		paint(b, if n == name then TAB_COLORS[n] else CHIP)
	end
end

local function newPage(name: string, order: number): ScrollingFrame
	local page = make("ScrollingFrame", {
		Name = name,
		Size = UDim2.new(1, -(TAB_W + 34), 1, -138),
		Position = UDim2.fromOffset(TAB_W + 24, 128),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = INK,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = false,
	}, window)
	vlist(page, 14)
	make("UIPadding", { PaddingBottom = UDim.new(0, 12), PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4) }, page)
	pages[name] = page
	local b = button(window, name, CHIP, UDim2.fromOffset(TAB_W, 52), function()
		showTab(name)
	end, 20)
	b.Position = UDim2.fromOffset(14, 128 + (order - 1) * 62)
	tabButtons[name] = b
	return page
end

------------------------------------------------------------------------------ events

local function eventCard(parent: Instance, kind: string, build: ((Frame) -> () -> { [string]: any })?)
	local def = Admin.Events[kind]
	local card = panel(parent, UDim2.new(1, 0, 0, 0), WHITE)
	card.AutomaticSize = Enum.AutomaticSize.Y
	make("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
	}, card)
	vlist(card, 6)
	local head = row(card, 42)
	make("ImageLabel", {
		Size = UDim2.fromOffset(42, 42),
		BackgroundTransparency = 1,
		Image = AssetLibrary.image(def.Icon),
		ScaleType = Enum.ScaleType.Fit,
	}, head)
	local titles = make("Frame", { Size = UDim2.new(1, -52, 1, 0), BackgroundTransparency = 1 }, head)
	vlist(titles, 0)
	text(titles, def.Name, UDim2.new(1, 0, 0, 24), 21, INK, Enum.FontWeight.Heavy)
	text(titles, def.Blurb, UDim2.new(1, 0, 0, 17), 15, SUB, Enum.FontWeight.Bold)
	local extra = if build then build(card) else nil
	local controls = row(card, 42)
	local valueBox: TextBox? = nil
	if def.Unit then
		text(controls, if def.Unit == "x" then "Multiplier  x" else "Amount  +", UDim2.fromOffset(112, 34), 16, SUB, Enum.FontWeight.Heavy)
		valueBox = input(controls, tostring(def.Default), UDim2.fromOffset(80, 36), tostring(def.Default))
	end
	text(controls, "Minutes", UDim2.fromOffset(72, 34), 16, SUB, Enum.FontWeight.Heavy)
	local minutes = input(controls, "min", UDim2.fromOffset(70, 36), tostring(def.Minutes))
	button(controls, "START", GREEN, UDim2.fromOffset(112, 40), function()
		local payload: { [string]: any } = { Type = kind, Minutes = minutes.Text }
		if valueBox then
			payload.Value = valueBox.Text
		end
		if extra then
			for k, v in extra() do
				payload[k] = v
			end
		end
		call("Event", payload)
	end, 19)
	return card
end

local runningList: Frame
local runningRows: { [string]: { row: Frame, ends: number, time: TextLabel } } = {}

local function eventName(e: any): string
	local def = Admin.Events[e.Type]
	if e.Type == "Weather" then
		local w = Weather.ById[e.Value]
		return if w then w.Name else "Weather"
	elseif e.Type == "Drops" then
		return `{e.Rarity or "Random"} Egg Drops`
	elseif def and def.Unit == "x" then
		return `{e.Value}x {def.Name}`
	elseif def and def.Unit == "+" then
		return `+{e.Value} {def.Name}`
	end
	return if def then def.Name else tostring(e.Type)
end

local function renderRunning()
	local raw = State.server("AdminEvents")
	local ok, list = pcall(function()
		return HttpService:JSONDecode(raw or "[]")
	end)
	if not ok or type(list) ~= "table" then
		list = {}
	end
	table.sort(list, function(a, b)
		return a.EndsAt < b.EndsAt
	end)
	local seen = {}
	for i, e in list do
		seen[e.Id] = true
		local entry = runningRows[e.Id]
		if not entry then
			local r = panel(runningList, UDim2.new(1, 0, 0, 54), if e.Global then Color3.fromRGB(255, 238, 220) else WHITE)
			local def = Admin.Events[e.Type]
			make("ImageLabel", {
				Size = UDim2.fromOffset(40, 40),
				Position = UDim2.new(0, 8, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				Image = AssetLibrary.image(if def then def.Icon else "Icon_Event"),
				ScaleType = Enum.ScaleType.Fit,
			}, r)
			local name = text(r, eventName(e), UDim2.new(1, -300, 0, 26), 19, INK, Enum.FontWeight.Heavy)
			name.Position = UDim2.fromOffset(56, 3)
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.TextWrapped = false
			local where = text(r, if e.Global then "ALL SERVERS" else "THIS SERVER", UDim2.new(1, -300, 0, 18), 14,
				if e.Global then Color3.fromRGB(214, 80, 20) else BLUE, Enum.FontWeight.Heavy)
			where.Position = UDim2.fromOffset(56, 30)
			local time = text(r, "", UDim2.fromOffset(100, 30), 21, INK, Enum.FontWeight.Heavy)
			time.Position = UDim2.new(1, -220, 0.5, 0)
			time.AnchorPoint = Vector2.new(0, 0.5)
			time.TextXAlignment = Enum.TextXAlignment.Right
			local id = e.Id
			local stop = button(r, "STOP", RED, UDim2.fromOffset(100, 40), function()
				call("StopEvent", { Id = id })
			end, 18)
			stop.Position = UDim2.new(1, -8, 0.5, 0)
			stop.AnchorPoint = Vector2.new(1, 0.5)
			entry = { row = r, ends = e.EndsAt, time = time }
			runningRows[e.Id] = entry
		end
		local current = runningRows[e.Id]
		current.row.LayoutOrder = i
		current.ends = e.EndsAt
	end
	for id, entry in runningRows do
		if not seen[id] then
			entry.row:Destroy()
			runningRows[id] = nil
		end
	end
	local empty = runningList:FindFirstChild("Empty") :: TextLabel?
	if empty then
		empty.Visible = next(runningRows) == nil
	end
end

local function buildEvents()
	local page = newPage("Events", 1)
	runningList = section(page, "Running now")
	vlist(runningList, 6)
	local empty = text(runningList, "Nothing running. Start as many events below as you like.", UDim2.new(1, 0, 0, 24), 16, SUB)
	empty.Name = "Empty"
	empty.LayoutOrder = -1

	local boosts = section(page, "Boost events (they stack)")
	vlist(boosts, 8)
	for _, kind in { "Luck", "Cash", "Huge", "Hatch", "Speed" } do
		eventCard(boosts, kind)
	end

	local world = section(page, "World events")
	vlist(world, 8)
	eventCard(world, "Weather", function(card)
		local list: { Choice } = {}
		for _, def in Weather.List do
			table.insert(list, { label = def.Name, value = def.Id })
		end
		for _, def in Weather.Moons do
			if def.Duration > 0 then
				table.insert(list, { label = def.Name, value = def.Id, color = PURPLE })
			end
		end
		local pick, state = chips(card, list, Vector2.new(134, 36))
		pick(list[1] and list[1].value)
		return function()
			return { Value = state.value }
		end
	end)
	eventCard(world, "EggRain")
	eventCard(world, "Drops", function(card)
		local rarities: { Choice } = { { label = "Random", value = "" } }
		for _, def in Eggs.Rarities do
			table.insert(rarities, { label = def.Name, value = def.Name, color = rarityColor(def.Name) })
		end
		local pick, state = chips(card, rarities, Vector2.new(112, 36))
		pick("")
		local r = row(card, 40)
		text(r, "Eggs a minute", UDim2.fromOffset(124, 34), 16, SUB, Enum.FontWeight.Heavy)
		local rate = input(r, "20", UDim2.fromOffset(70, 36), "20")
		return function()
			return { Rarity = if state.value ~= "" then state.value else nil, Rate = rate.Text }
		end
	end)

	local time = section(page, "Time of day")
	local tr = row(time, 48)
	button(tr, "DAY", GOLD, UDim2.fromOffset(150, 44), function()
		call("Time", { Value = "day" })
	end, 20)
	button(tr, "NIGHT", PURPLE, UDim2.fromOffset(150, 44), function()
		call("Time", { Value = "night" })
	end, 20)

	State.serverState:GetAttributeChangedSignal("AdminEvents"):Connect(renderRunning)
	renderRunning()
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = State.now()
			for _, entry in runningRows do
				entry.time.Text = Format.time(math.max(0, entry.ends - now))
			end
		end
	end)
end

-------------------------------------------------------------------------------- give

local function targetPicker(parent: Instance)
	local holder = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, parent)
	local function rebuild()
		holder:ClearAllChildren()
		local choices: { Choice } = {
			{ label = "Me", value = "me", color = GREEN },
			{ label = "Everyone", value = "all", color = GOLD },
		}
		for _, p in Players:GetPlayers() do
			if p ~= player then
				table.insert(choices, { label = p.DisplayName, value = p.UserId })
			end
		end
		if type(target) == "number" and not Players:GetPlayerByUserId(target) then
			target = "me"
		end
		local pick = chips(holder, choices, Vector2.new(140, 38), function(v)
			target = v
		end)
		pick(target)
	end
	rebuild()
	Players.PlayerAdded:Connect(rebuild)
	Players.PlayerRemoving:Connect(function()
		task.defer(rebuild)
	end)
end

local function buildGive()
	local page = newPage("Give", 2)
	targetPicker(section(page, "Give to (Everyone = every server when ALL SERVERS is on)"))
	local kindBody = section(page, "What")
	local options = section(page, "Options")
	vlist(options, 8)

	local function amountRow(parent: Instance, default: string, placeholder: string?)
		local r = row(parent, 42)
		text(r, "Amount", UDim2.fromOffset(80, 34), 16, SUB, Enum.FontWeight.Heavy)
		local box = input(r, placeholder or "How many", UDim2.fromOffset(170, 38), default)
		return box, r
	end
	local function giveButton(parent: Instance, build: () -> { [string]: any })
		button(parent, "GIVE", GREEN, UDim2.fromOffset(200, 50), function()
			local payload = build()
			payload.Target = target
			call("Give", payload)
		end, 22)
	end

	local builders: { [string]: (Instance) -> () } = {}
	builders.Cash = function(body)
		local box, r = amountRow(body, "1M", "500, 25k, 1.5T, 1e30")
		for _, quick in { "1M", "1B", "1T", "1Qa", "1e30" } do
			button(r, quick, CHIP, UDim2.fromOffset(58, 36), function()
				box.Text = quick
			end, 14)
		end
		giveButton(body, function()
			return { Kind = "Cash", Amount = box.Text }
		end)
	end
	builders.Egg = function(body)
		local list: { Choice } = {}
		for _, r in Eggs.Rarities do
			table.insert(list, { label = r.Name, value = r.Name, color = rarityColor(r.Name) })
		end
		local pick, state = chips(body, list, Vector2.new(112, 38))
		pick("Common")
		local box = amountRow(body, "1")
		giveButton(body, function()
			return { Kind = "Egg", Id = state.value, Amount = box.Text }
		end)
	end
	builders.Pet = function(body)
		local list: { Choice } = {}
		local sorted = table.clone(Aliens.List)
		table.sort(sorted, function(a, b)
			if a.Rarity ~= b.Rarity then
				return Eggs.order(a.Rarity) < Eggs.order(b.Rarity)
			end
			return a.Name < b.Name
		end)
		for _, def in sorted do
			table.insert(list, { label = def.Name, value = def.Id, color = rarityColor(def.Rarity) })
		end
		local pickPet, petState = chips(body, list, Vector2.new(124, 38))
		pickPet(sorted[1] and sorted[1].Id)
		text(body, "MUTATION", UDim2.new(1, 0, 0, 20), 15, SUB, Enum.FontWeight.Heavy)
		local mutations: { Choice } = { { label = "None", value = "" } }
		for _, m in Eggs.Mutations do
			table.insert(mutations, { label = m.Name, value = m.Name, color = PURPLE })
		end
		local pickMut, mutState = chips(body, mutations, Vector2.new(112, 36))
		pickMut("")
		local box, r = amountRow(body, "1")
		local huge = false
		local hugeButton: TextButton
		hugeButton = button(r, "HUGE: OFF", CHIP, UDim2.fromOffset(130, 38), function()
			huge = not huge
			paint(hugeButton, if huge then GOLD else CHIP, if huge then "HUGE: ON" else "HUGE: OFF")
		end, 16)
		giveButton(body, function()
			return {
				Kind = "Pet",
				Id = petState.value,
				Mutation = if mutState.value ~= "" then mutState.value else nil,
				Huge = huge,
				Amount = box.Text,
			}
		end)
	end
	builders.Item = function(body)
		local list: { Choice } = {}
		for _, def in Items.List do
			table.insert(list, { label = def.Name, value = def.Id })
		end
		local pick, state = chips(body, list, Vector2.new(140, 38))
		pick(Items.List[1] and Items.List[1].Id)
		local box = amountRow(body, "5")
		giveButton(body, function()
			return { Kind = "Item", Id = state.value, Amount = box.Text }
		end)
	end
	builders.Tool = function(body)
		local list: { Choice } = {}
		for _, def in Tools.List do
			table.insert(list, { label = def.Name, value = def.Tier })
		end
		local pick, state = chips(body, list, Vector2.new(140, 38))
		pick(Tools.MaxTier)
		giveButton(body, function()
			return { Kind = "Tool", Id = state.value }
		end)
	end
	builders.Vehicle = function(body)
		local list: { Choice } = {}
		for _, def in Tools.Vehicles do
			table.insert(list, { label = def.Name, value = def.Id })
		end
		local pick, state = chips(body, list, Vector2.new(140, 38))
		pick(Tools.Vehicles[1] and Tools.Vehicles[1].Id)
		giveButton(body, function()
			return { Kind = "Vehicle", Id = state.value }
		end)
	end
	builders.Boost = function(body)
		local list: { Choice } = {}
		local names = { Luck2x = "2x Luck", Cash2x = "2x Cash", Speed = "Speed" }
		for _, key in Admin.Boosts do
			table.insert(list, { label = names[key] or key, value = key })
		end
		local pick, state = chips(body, list, Vector2.new(124, 38))
		pick(Admin.Boosts[1])
		local r = row(body, 42)
		text(r, "Minutes", UDim2.fromOffset(80, 34), 16, SUB, Enum.FontWeight.Heavy)
		local minutes = input(r, "min", UDim2.fromOffset(90, 38), "15")
		giveButton(body, function()
			return { Kind = "Boost", Id = state.value, Minutes = minutes.Text }
		end)
	end

	local kinds: { Choice } = {
		{ label = "Cash", value = "Cash" },
		{ label = "Eggs", value = "Egg" },
		{ label = "Pets", value = "Pet" },
		{ label = "Potions", value = "Item" },
		{ label = "Tools", value = "Tool" },
		{ label = "Cars", value = "Vehicle" },
		{ label = "Boosts", value = "Boost" },
	}
	local pickKind = chips(kindBody, kinds, Vector2.new(86, 40), function(kind)
		for _, child in options:GetChildren() do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		builders[kind](options)
	end)
	pickKind("Cash")
end

----------------------------------------------------------------------- message, poll

local function buildMessage()
	local page = newPage("Message", 3)
	local body = section(page, "Announcement")
	vlist(body, 8)
	local box = input(body, "Type your announcement...", UDim2.new(1, 0, 0, 110))
	box.MultiLine = true
	box.TextWrapped = true
	box.TextYAlignment = Enum.TextYAlignment.Top
	text(body, "SHOW FOR", UDim2.new(1, 0, 0, 20), 15, SUB, Enum.FontWeight.Heavy)
	local pick, state = chips(body, {
		{ label = "5 s", value = 5 },
		{ label = "10 s", value = 10 },
		{ label = "20 s", value = 20 },
		{ label = "30 s", value = 30 },
	}, Vector2.new(80, 38))
	pick(10)
	button(body, "SEND", GREEN, UDim2.fromOffset(200, 50), function()
		if call("Announce", { Text = box.Text, Seconds = state.value }) then
			box.Text = ""
		end
	end, 22)
end

local function buildPoll()
	local page = newPage("Poll", 4)
	local body = section(page, "Ask everyone")
	vlist(body, 8)
	local question = input(body, "Question", UDim2.new(1, 0, 0, 42))
	local answers = {}
	for i = 1, 4 do
		table.insert(answers, input(body, `Answer {i}` .. (if i > 2 then " (optional)" else ""), UDim2.new(1, 0, 0, 38)))
	end
	text(body, "OPEN FOR", UDim2.new(1, 0, 0, 20), 15, SUB, Enum.FontWeight.Heavy)
	local pick, state = chips(body, {
		{ label = "30 s", value = 30 },
		{ label = "1 min", value = 60 },
		{ label = "2 min", value = 120 },
		{ label = "5 min", value = 300 },
	}, Vector2.new(80, 38))
	pick(60)
	local r = row(body, 52)
	button(r, "START POLL", GREEN, UDim2.fromOffset(180, 48), function()
		local options = {}
		for _, a in answers do
			if a.Text ~= "" then
				table.insert(options, a.Text)
			end
		end
		call("PollStart", { Question = question.Text, Options = options, Seconds = state.value })
	end, 20)
	button(r, "END POLL", RED, UDim2.fromOffset(150, 48), function()
		call("PollEnd")
	end, 20)
	local results = text(body, "No poll running.", UDim2.new(1, 0, 0, 0), 16, SUB)
	results.AutomaticSize = Enum.AutomaticSize.Y
	Net.event("Poll").OnClientEvent:Connect(function(poll)
		if not poll then
			results.Text = "No poll running."
			return
		end
		local total = 0
		for _, v in poll.Votes do
			total += v
		end
		local lines = { `{poll.Question}{if poll.Ended then "  (ended)" else ""}` }
		for i, option in poll.Options do
			table.insert(lines, `{option}: {poll.Votes[i] or 0} vote{if poll.Votes[i] == 1 then "" else "s"}`)
		end
		table.insert(lines, `{total} total{if poll.Global then " · all servers" else ""}`)
		results.Text = table.concat(lines, "\n")
	end)
end

------------------------------------------------------------------------------- panel

local scopeHint: TextLabel
local scopeServer: TextButton
local scopeAll: TextButton
local header: Frame

local function setScope(all: boolean)
	global = all
	paint(scopeServer, if all then CHIP else BLUE)
	paint(scopeAll, if all then ORANGE else CHIP)
	scopeHint.Text = if all
		then "Everything you do now happens in EVERY server!"
		else "Everything you do now happens in this server only."
	scopeHint.TextColor3 = if all then Color3.fromRGB(214, 80, 20) else SUB
	header.BackgroundColor3 = if all then ORANGE else RED
end

local function build()
	gui = make("ScreenGui", {
		Name = "AdminPanel",
		ResetOnSpawn = false,
		DisplayOrder = 60,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	}, player:WaitForChild("PlayerGui"))

	-- Small ADMIN button at the top right (out of the way of the HUD pills in the middle).
	local toggle = button(gui, "ADMIN", RED, UDim2.fromOffset(86, 34), function()
		window.Visible = not window.Visible
	end, 15)
	-- Up in Roblox's top bar row, right side, so it never covers the Eggs/Pets/Tools column.
	toggle.AnchorPoint = Vector2.new(1, 0)
	local function placeToggle()
		local h = GuiService.TopbarInset.Height
		toggle.Position = if h >= 34 then UDim2.new(1, -10, 0, -math.floor(h) + math.floor((h - 34) / 2)) else UDim2.new(1, -10, 0, 6)
	end
	placeToggle()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(placeToggle)

	window = panel(gui, UDim2.fromOffset(W, H), SURFACE)
	window.Name = "Window"
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Visible = false
	window.Active = true
	local scale = make("UIScale", {}, window)
	Ui.onScale(function()
		local cam = workspace.CurrentCamera
		local view = if cam then cam.ViewportSize else Vector2.new(1280, 720)
		-- Fits the screen on phones, like every other window.
		scale.Scale = math.min(Ui.windowScale(), (view.X - 20) / W, (view.Y - 40) / H)
	end)

	header = panel(window, UDim2.new(1, 0, 0, 64), RED)
	header.Name = "Header"
	shade(header, Color3.fromRGB(220, 224, 231))
	make("ImageLabel", {
		Size = UDim2.fromOffset(46, 46),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Image = AssetLibrary.image("Icon_Star"),
		ScaleType = Enum.ScaleType.Fit,
	}, header)
	local title = text(header, "Admin Panel", UDim2.new(1, -150, 1, 0), 30, WHITE, Enum.FontWeight.Heavy)
	title.Position = UDim2.fromOffset(66, 0)
	make("UIStroke", { Thickness = 3, Color = INK }, title)
	local close = button(window, "X", RED, UDim2.fromOffset(52, 52), function()
		window.Visible = false
	end, 28)
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(1, -6, 0, 6)
	close.ZIndex = 5

	-- Where things run.
	local scope = make("Frame", {
		Size = UDim2.new(1, -28, 0, 46),
		Position = UDim2.fromOffset(14, 74),
		BackgroundTransparency = 1,
	}, window)
	text(scope, "RUN IN", UDim2.fromOffset(70, 46), 16, SUB, Enum.FontWeight.Heavy)
	scopeServer = button(scope, "THIS SERVER", BLUE, UDim2.fromOffset(170, 42), function()
		setScope(false)
	end, 17)
	scopeServer.Position = UDim2.new(0, 70, 0.5, 0)
	scopeServer.AnchorPoint = Vector2.new(0, 0.5)
	scopeAll = button(scope, "ALL SERVERS", CHIP, UDim2.fromOffset(170, 42), function()
		setScope(true)
	end, 17)
	scopeAll.Position = UDim2.new(0, 250, 0.5, 0)
	scopeAll.AnchorPoint = Vector2.new(0, 0.5)
	scopeHint = text(scope, "", UDim2.new(1, -440, 1, 0), 15, SUB, Enum.FontWeight.Heavy)
	scopeHint.Position = UDim2.fromOffset(436, 0)

	buildEvents()
	buildGive()
	buildMessage()
	buildPoll()
	setScope(false)
	showTab("Events")

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.F2 then
			window.Visible = not window.Visible
		end
	end)
end

function AdminController:Init(controllers)
	C = controllers
end

function AdminController:Start()
	if not Admin.isAdmin(player.UserId) then
		return
	end
	build()
end

return AdminController
