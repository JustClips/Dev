--!strict
-- Admin panel (only for the players in Config/Admin; the server checks every call too,
-- see AdminService). An ADMIN button at the top of the screen (or F2) opens it.
-- Tabs: Give (cash, eggs, pets, potions, tools, cars, boosts to you, everyone or one
-- player), Server (server luck, weather, day/night, egg rain, egg drops), Message
-- (a server-wide announcement), Poll (ask everyone a question) and Players (go to, bring,
-- respawn, kick). Everything is for this server only.
-- Built in code, not gen_ui, so the panel never ships in other players' StarterGui.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Admin = require(Shared.Config.Admin)
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

local FONT = "rbxasset://fonts/families/Montserrat.json"
local BG = Color3.fromRGB(16, 19, 34)
local PANEL = Color3.fromRGB(28, 33, 56)
local CHIP = Color3.fromRGB(52, 60, 92)
local PICKED = Color3.fromRGB(76, 141, 255)
local GREEN = Color3.fromRGB(64, 196, 99)
local RED = Color3.fromRGB(226, 72, 72)
local GOLD = Color3.fromRGB(255, 196, 46)
local PURPLE = Color3.fromRGB(150, 90, 230)
local WHITE = Color3.new(1, 1, 1)
local SUB = Color3.fromRGB(170, 180, 210)

local W, H = 660, 430
local TAB_W = 118

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

local function stroke(parent: Instance, thickness: number?, color: Color3?)
	make("UIStroke", {
		Thickness = thickness or 2,
		Color = color or Color3.new(0, 0, 0),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function text(parent: Instance, value: string, size: UDim2, ts: number, color: Color3?, weight: Enum.FontWeight?): TextLabel
	local l = make("TextLabel", {
		Size = size,
		BackgroundTransparency = 1,
		Text = value,
		TextColor3 = color or WHITE,
		FontFace = Font.new(FONT, weight or Enum.FontWeight.Bold),
		TextSize = ts,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	}, parent)
	return l
end

-- A solid, square button (Dev's UI rules: no rounded corners, every button has a fill).
local function button(parent: Instance, label: string, color: Color3, size: UDim2, fn: () -> ()): TextButton
	local b = make("TextButton", {
		Size = size,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Text = label,
		TextColor3 = WHITE,
		FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
		TextSize = 15,
		TextWrapped = true,
	}, parent)
	stroke(b)
	b.Activated:Connect(function()
		Ui.sound("Click")
		fn()
	end)
	return b
end

local function input(parent: Instance, placeholder: string, size: UDim2, default: string?): TextBox
	local b = make("TextBox", {
		Size = size,
		BackgroundColor3 = Color3.fromRGB(10, 12, 24),
		BorderSizePixel = 0,
		Text = default or "",
		PlaceholderText = placeholder,
		PlaceholderColor3 = Color3.fromRGB(110, 118, 150),
		TextColor3 = WHITE,
		FontFace = Font.new(FONT, Enum.FontWeight.SemiBold),
		TextSize = 15,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, b)
	stroke(b, 1.5, Color3.fromRGB(70, 80, 120))
	return b
end

-- A section: a heading and a body that grows with what's in it.
local function section(page: Instance, title: string, order: number): Frame
	local holder = make("Frame", {
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, page)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
	local head = text(holder, string.upper(title), UDim2.new(1, 0, 0, 18), 13, SUB, Enum.FontWeight.Heavy)
	head.LayoutOrder = 0
	local body = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, holder)
	return body
end

-- A wrap of buttons where one is picked. Returns pick(value) and the current value.
type Choice = { label: string, value: any, color: Color3? }
local function chips(parent: Instance, choices: { Choice }, cell: Vector2, onPick: ((any) -> ())?)
	local grid = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, parent)
	make("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell.X, cell.Y),
		CellPadding = UDim2.fromOffset(5, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	local state = { value = nil :: any }
	local buttons: { [any]: TextButton } = {}
	local function pick(value: any)
		state.value = value
		for v, b in buttons do
			local choiceColor = b:GetAttribute("Base") :: Color3
			b.BackgroundColor3 = if v == value then PICKED else choiceColor
			local s = b:FindFirstChildOfClass("UIStroke")
			if s then
				s.Color = if v == value then WHITE else Color3.new(0, 0, 0)
			end
		end
		if onPick then
			onPick(value)
		end
	end
	for i, choice in choices do
		local b = button(grid, choice.label, choice.color or CHIP, UDim2.fromOffset(cell.X, cell.Y), function()
			pick(choice.value)
		end)
		b.LayoutOrder = i
		b.TextSize = 13
		b:SetAttribute("Base", choice.color or CHIP)
		buttons[choice.value] = b
	end
	return pick, state, grid
end

local function row(parent: Instance, height: number): Frame
	local r = make("Frame", { Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1 }, parent)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, r)
	return r
end

------------------------------------------------------------------------------- calls

local function call(action: string, payload: { [string]: any }?)
	local ok, message = Net.func("Admin"):InvokeServer(action, payload or {})
	if message and message ~= "" then
		C.HudController:Toast(message, if ok then "Good" else "Bad")
	end
	return ok
end

local function rarityColor(rarity: string): Color3
	local def = Eggs.ByName[rarity]
	return if def then def.Color:Lerp(Color3.new(0, 0, 0), 0.35) else CHIP
end

------------------------------------------------------------------------------- panel

local gui: ScreenGui
local window: Frame
local pages: { [string]: ScrollingFrame } = {}
local tabButtons: { [string]: TextButton } = {}
local target: any = "me"

local function showTab(name: string)
	for n, page in pages do
		page.Visible = n == name
	end
	for n, b in tabButtons do
		b.BackgroundColor3 = if n == name then PICKED else PANEL
	end
end

local function newPage(name: string, order: number)
	local page = make("ScrollingFrame", {
		Name = name,
		Size = UDim2.new(1, -(TAB_W + 18), 1, -58),
		Position = UDim2.fromOffset(TAB_W + 12, 50),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = false,
	}, window)
	make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, page)
	make("UIPadding", { PaddingBottom = UDim.new(0, 10), PaddingTop = UDim.new(0, 4) }, page)
	pages[name] = page
	local b = button(window, name, PANEL, UDim2.fromOffset(TAB_W - 8, 40), function()
		showTab(name)
	end)
	b.Position = UDim2.fromOffset(8, 50 + (order - 1) * 46)
	tabButtons[name] = b
	return page
end

-- "Give to": me, everyone, or one player (kept up to date as people join and leave).
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
			{ label = "Everyone", value = "all", color = GOLD:Lerp(Color3.new(0, 0, 0), 0.3) },
		}
		for _, p in Players:GetPlayers() do
			if p ~= player then
				table.insert(choices, { label = p.DisplayName, value = p.UserId })
			end
		end
		if type(target) == "number" and not Players:GetPlayerByUserId(target) then
			target = "me"
		end
		local pick = chips(holder, choices, Vector2.new(118, 30), function(v)
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
	local page = newPage("Give", 1)
	targetPicker(section(page, "Give to", 1))

	local options = section(page, "Options", 3)
	local kindBody = section(page, "What", 2)

	local function amountRow(parent: Instance, placeholder: string, default: string)
		local r = row(parent, 34)
		text(r, "Amount", UDim2.fromOffset(70, 30), 14, SUB).LayoutOrder = 1
		local box = input(r, placeholder, UDim2.fromOffset(150, 30), default)
		box.LayoutOrder = 2
		return box, r
	end

	local function giveButton(parent: Instance, build: () -> { [string]: any }?)
		local b = button(parent, "GIVE", GREEN, UDim2.fromOffset(180, 40), function()
			local payload = build()
			if payload then
				payload.Target = target
				call("Give", payload)
			end
		end)
		b.TextSize = 18
		return b
	end

	local builders: { [string]: (Instance) -> () } = {}

	builders.Cash = function(body)
		local box, r = amountRow(body, "500, 25k, 1.5T, 1e30", "1M")
		for i, quick in { "1M", "1B", "1T", "1Qa", "1e30" } do
			local q = button(r, quick, CHIP, UDim2.fromOffset(52, 30), function()
				box.Text = quick
			end)
			q.TextSize = 12
			q.LayoutOrder = 2 + i
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
		local pick, state = chips(body, list, Vector2.new(96, 30))
		pick("Common")
		local box = amountRow(body, "How many", "1")
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
		local pickPet, petState = chips(body, list, Vector2.new(110, 30))
		pickPet(sorted[1] and sorted[1].Id)
		text(body, "Mutation", UDim2.new(1, 0, 0, 18), 13, SUB)
		local mutations: { Choice } = { { label = "None", value = "" } }
		for _, m in Eggs.Mutations do
			table.insert(mutations, { label = m.Name, value = m.Name, color = PURPLE:Lerp(Color3.new(0, 0, 0), 0.3) })
		end
		local pickMut, mutState = chips(body, mutations, Vector2.new(96, 28))
		pickMut("")
		local box, r = amountRow(body, "How many", "1")
		local huge = false
		local hugeButton: TextButton
		hugeButton = button(r, "Huge: off", CHIP, UDim2.fromOffset(100, 30), function()
			huge = not huge
			hugeButton.Text = if huge then "Huge: ON" else "Huge: off"
			hugeButton.BackgroundColor3 = if huge then GOLD:Lerp(Color3.new(0, 0, 0), 0.25) else CHIP
		end)
		hugeButton.LayoutOrder = 3
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
		local pick, state = chips(body, list, Vector2.new(120, 30))
		pick(Items.List[1] and Items.List[1].Id)
		local box = amountRow(body, "How many", "5")
		giveButton(body, function()
			return { Kind = "Item", Id = state.value, Amount = box.Text }
		end)
	end

	builders.Tool = function(body)
		local list: { Choice } = {}
		for _, def in Tools.List do
			table.insert(list, { label = def.Name, value = def.Tier })
		end
		local pick, state = chips(body, list, Vector2.new(120, 30))
		pick(Tools.MaxTier)
		text(body, "Sets their best tool (every tool below it is owned too).", UDim2.new(1, 0, 0, 18), 13, SUB)
		giveButton(body, function()
			return { Kind = "Tool", Id = state.value }
		end)
	end

	builders.Vehicle = function(body)
		local list: { Choice } = {}
		for _, def in Tools.Vehicles do
			table.insert(list, { label = def.Name, value = def.Id })
		end
		local pick, state = chips(body, list, Vector2.new(120, 30))
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
		local pick, state = chips(body, list, Vector2.new(110, 30))
		pick(Admin.Boosts[1])
		local r = row(body, 34)
		text(r, "Minutes", UDim2.fromOffset(70, 30), 14, SUB).LayoutOrder = 1
		local box = input(r, "Minutes", UDim2.fromOffset(100, 30), "15")
		box.LayoutOrder = 2
		giveButton(body, function()
			return { Kind = "Boost", Id = state.value, Minutes = box.Text }
		end)
	end

	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, options)
	local kinds: { Choice } = {
		{ label = "Cash", value = "Cash" },
		{ label = "Eggs", value = "Egg" },
		{ label = "Pets", value = "Pet" },
		{ label = "Potions", value = "Item" },
		{ label = "Tools", value = "Tool" },
		{ label = "Cars", value = "Vehicle" },
		{ label = "Boosts", value = "Boost" },
	}
	local pickKind = chips(kindBody, kinds, Vector2.new(84, 32), function(kind)
		for _, child in options:GetChildren() do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		builders[kind](options)
	end)
	pickKind("Cash")
end

local function buildServer()
	local page = newPage("Server", 2)

	local luck = section(page, "Server luck", 1)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, luck)
	local pickLuck, luckState = chips(luck, {
		{ label = "2x", value = 2 },
		{ label = "4x", value = 4 },
		{ label = "8x", value = 8 },
		{ label = "16x", value = 16 },
	}, Vector2.new(70, 30))
	pickLuck(2)
	local r = row(luck, 34)
	text(r, "Minutes", UDim2.fromOffset(70, 30), 14, SUB).LayoutOrder = 1
	local minutes = input(r, "Minutes", UDim2.fromOffset(90, 30), "15")
	minutes.LayoutOrder = 2
	button(r, "START", GREEN, UDim2.fromOffset(110, 30), function()
		call("ServerLuck", { Mult = luckState.value, Minutes = minutes.Text })
	end).LayoutOrder = 3

	local weather = section(page, "Weather", 2)
	local list: { Choice } = { { label = "Off", value = "off", color = RED } }
	for _, def in Weather.List do
		table.insert(list, { label = def.Name, value = def.Id })
	end
	for _, def in Weather.Moons do
		if def.Duration > 0 then
			table.insert(list, { label = def.Name, value = def.Id, color = PURPLE:Lerp(Color3.new(0, 0, 0), 0.3) })
		end
	end
	chips(weather, list, Vector2.new(112, 30), function(id)
		call("Command", { Text = "/weather " .. string.lower(id) })
	end)

	local time = section(page, "Time", 3)
	local tr = row(time, 34)
	button(tr, "Day", GOLD:Lerp(Color3.new(0, 0, 0), 0.25), UDim2.fromOffset(100, 30), function()
		call("Command", { Text = "/day" })
	end)
	button(tr, "Night", PURPLE, UDim2.fromOffset(100, 30), function()
		call("Command", { Text = "/night" })
	end)

	local events = section(page, "Egg events", 4)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, events)
	button(events, "START EGG RAIN", GREEN, UDim2.fromOffset(180, 34), function()
		call("EggRain")
	end)
	text(events, "Drop eggs from the sky", UDim2.new(1, 0, 0, 18), 13, SUB)
	local rarities: { Choice } = { { label = "Random", value = "" } }
	for _, def in Eggs.Rarities do
		table.insert(rarities, { label = def.Name, value = def.Name, color = rarityColor(def.Name) })
	end
	local pickRarity, rarityState = chips(events, rarities, Vector2.new(96, 30))
	pickRarity("")
	local dr = row(events, 34)
	text(dr, "How many", UDim2.fromOffset(80, 30), 14, SUB).LayoutOrder = 1
	local count = input(dr, "1-40", UDim2.fromOffset(70, 30), "10")
	count.LayoutOrder = 2
	button(dr, "DROP", GREEN, UDim2.fromOffset(100, 30), function()
		call("DropEggs", { Rarity = if rarityState.value ~= "" then rarityState.value else nil, Count = count.Text })
	end).LayoutOrder = 3
end

local function buildMessage()
	local page = newPage("Message", 3)
	local body = section(page, "Announcement to everyone in this server", 1)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, body)
	local box = input(body, "Type your announcement...", UDim2.new(1, 0, 0, 90))
	box.MultiLine = true
	box.TextWrapped = true
	box.TextYAlignment = Enum.TextYAlignment.Top
	text(body, "Show for", UDim2.new(1, 0, 0, 18), 13, SUB)
	local pick, state = chips(body, {
		{ label = "5 s", value = 5 },
		{ label = "10 s", value = 10 },
		{ label = "20 s", value = 20 },
		{ label = "30 s", value = 30 },
	}, Vector2.new(70, 30))
	pick(10)
	button(body, "SEND", GREEN, UDim2.fromOffset(180, 40), function()
		if call("Announce", { Text = box.Text, Seconds = state.value }) then
			box.Text = ""
		end
	end)
end

local function buildPoll()
	local page = newPage("Poll", 4)
	local body = section(page, "Ask everyone in this server", 1)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, body)
	local question = input(body, "Question", UDim2.new(1, 0, 0, 34))
	local answers = {}
	for i = 1, 4 do
		table.insert(answers, input(body, `Answer {i}` .. (if i > 2 then " (optional)" else ""), UDim2.new(1, 0, 0, 30)))
	end
	text(body, "Open for", UDim2.new(1, 0, 0, 18), 13, SUB)
	local pick, state = chips(body, {
		{ label = "30 s", value = 30 },
		{ label = "1 min", value = 60 },
		{ label = "2 min", value = 120 },
		{ label = "5 min", value = 300 },
	}, Vector2.new(70, 30))
	pick(60)
	local r = row(body, 42)
	button(r, "START POLL", GREEN, UDim2.fromOffset(160, 38), function()
		local options = {}
		for _, a in answers do
			if a.Text ~= "" then
				table.insert(options, a.Text)
			end
		end
		call("PollStart", { Question = question.Text, Options = options, Seconds = state.value })
	end)
	button(r, "END POLL", RED, UDim2.fromOffset(130, 38), function()
		call("PollEnd")
	end)
	local results = text(body, "No poll running.", UDim2.new(1, 0, 0, 0), 14, SUB)
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
			table.insert(lines, `{option}: {poll.Votes[i]} vote{if poll.Votes[i] == 1 then "" else "s"}`)
		end
		table.insert(lines, `{total} total`)
		results.Text = table.concat(lines, "\n")
	end)
end

local function buildPlayers()
	local page = newPage("Players", 5)
	local body = section(page, "Everyone in this server", 1)
	make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, body)
	local function rebuild()
		for _, child in body:GetChildren() do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		for i, p in Players:GetPlayers() do
			local r = make("Frame", {
				Size = UDim2.new(1, 0, 0, 40),
				BackgroundColor3 = PANEL,
				BorderSizePixel = 0,
				LayoutOrder = i,
			}, body)
			stroke(r, 1.5)
			local name = text(r, `{p.DisplayName}  @{p.Name}`, UDim2.new(1, -330, 1, 0), 14, WHITE)
			name.Position = UDim2.fromOffset(10, 0)
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.TextWrapped = false
			local actions = make("Frame", {
				Size = UDim2.fromOffset(320, 32),
				Position = UDim2.new(1, -6, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				BackgroundTransparency = 1,
			}, r)
			make("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				Padding = UDim.new(0, 4),
			}, actions)
			local id = p.UserId
			if p ~= player then
				button(actions, "Go to", CHIP, UDim2.fromOffset(70, 30), function()
					call("Goto", { Target = id })
				end).TextSize = 13
				button(actions, "Bring", CHIP, UDim2.fromOffset(70, 30), function()
					call("Bring", { Target = id })
				end).TextSize = 13
			end
			button(actions, "Respawn", CHIP, UDim2.fromOffset(80, 30), function()
				call("Respawn", { Target = id })
			end).TextSize = 13
			if p ~= player and not Admin.isAdmin(id) then
				local armed = 0
				local kick: TextButton
				kick = button(actions, "Kick", RED, UDim2.fromOffset(70, 30), function()
					-- Two presses: the first one asks.
					if os.clock() - armed > 3 then
						armed = os.clock()
						kick.Text = "Sure?"
						task.delay(3, function()
							if kick.Parent then
								kick.Text = "Kick"
							end
						end)
						return
					end
					call("Kick", { Target = id })
				end)
				kick.TextSize = 13
			end
		end
		local all = make("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = 999 }, body)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, all)
		button(all, "Bring everyone", CHIP, UDim2.fromOffset(150, 32), function()
			call("Bring", { Target = "all" })
		end).TextSize = 13
	end
	rebuild()
	Players.PlayerAdded:Connect(rebuild)
	Players.PlayerRemoving:Connect(function()
		task.defer(rebuild)
	end)
end

local function setOpen(open: boolean)
	window.Visible = open
end

local function build()
	gui = make("ScreenGui", {
		Name = "AdminPanel",
		ResetOnSpawn = false,
		DisplayOrder = 60,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))

	-- The ADMIN button sits in the middle of Roblox's top bar row.
	local toggle = button(gui, "ADMIN", RED, UDim2.fromOffset(84, 30), function()
		setOpen(not window.Visible)
	end)
	toggle.AnchorPoint = Vector2.new(0.5, 0)
	toggle.Position = UDim2.new(0.5, 0, 0, 8)
	toggle.TextSize = 14

	window = make("Frame", {
		Name = "Window",
		Size = UDim2.fromOffset(W, H),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = BG,
		BorderSizePixel = 0,
		Visible = false,
		Active = true,
	}, gui)
	stroke(window, 3)
	local scale = make("UIScale", {}, window)
	Ui.onScale(function()
		local cam = workspace.CurrentCamera
		local view = if cam then cam.ViewportSize else Vector2.new(1280, 720)
		-- Fit the screen on phones, never bigger than its design size.
		scale.Scale = math.min(1, (view.X - 20) / W, (view.Y - 70) / H)
	end)

	local header = make("Frame", { Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = RED, BorderSizePixel = 0 }, window)
	stroke(header, 2)
	local title = text(header, "ADMIN PANEL", UDim2.new(1, -60, 1, 0), 20, WHITE, Enum.FontWeight.Black)
	title.Position = UDim2.fromOffset(12, 0)
	local close = button(header, "X", Color3.fromRGB(150, 30, 30), UDim2.fromOffset(34, 34), function()
		setOpen(false)
	end)
	close.Position = UDim2.new(1, -4, 0.5, 0)
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.TextSize = 18

	buildGive()
	buildServer()
	buildMessage()
	buildPoll()
	buildPlayers()
	showTab("Give")

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.F2 then
			setOpen(not window.Visible)
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
	print(`[Admin] panel ready ({Format.number(#Players:GetPlayers())} in server). Press F2 or the ADMIN button.`)
end

return AdminController
