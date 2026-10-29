--!strict
-- Upgrade Tree window (Upgrade Station on the south plaza, or the rail button), Slime RNG
-- style: a dark board of hexagon nodes you drag around (pinch / mouse wheel / +- to zoom)
-- and a detail card on the right for the selected node. Buying a node opens its neighbours;
-- nodes further out show as "?" until you get next to them, rebirth-gated ones show a lock.
-- Also keeps the rail button's badge (how many nodes you can buy right now) and bobs the
-- floating arrow over the station.
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local BigNum = require(Shared.BigNum)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Upgrades = require(Shared.Config.Upgrades)
local Types = require(Shared.Types)

type UpgradeDef = Types.UpgradeDef

local GREEN = Color3.fromRGB(61, 220, 90)
local GREY = Color3.fromRGB(166, 174, 194)
local GOLD = Color3.fromRGB(255, 200, 60)
local PURPLE = Color3.fromRGB(155, 107, 255)
local INK_TEXT = Color3.fromRGB(23, 25, 30)
local WHITE = Color3.new(1, 1, 1)

-- Node tile colours by state.
local TILE = {
	Open = Color3.fromRGB(247, 248, 250),
	Owned = Color3.fromRGB(139, 224, 78),
	Max = Color3.fromRGB(255, 200, 60),
	Rebirth = Color3.fromRGB(122, 96, 196),
	Mystery = Color3.fromRGB(74, 80, 96),
}
local LINK_ON = Color3.fromRGB(139, 224, 78)
local LINK_OPEN = Color3.fromRGB(216, 220, 230)
local LINK_OFF = Color3.fromRGB(74, 80, 96)

local SPACING = 66 -- hex grid size (centre to corner) in canvas pixels
local LINK_TRIM = 70 -- link length hidden under the two hexes it joins
local ZOOM_MIN, ZOOM_MAX, ZOOM_START = 0.45, 1.4, 0.8
local DRAG_THRESHOLD = 8 -- screen pixels before a press becomes a drag

local UpgradeController = {}

local C: any
local gui: ScreenGui
local tree: Frame
local canvas: Frame
local zoom: UIScale
local detail: Frame

local nodes: { [string]: ImageButton } = {}
local nodeSize = UDim2.fromOffset(80, 92)
local railBadge: GuiObject? = nil
local links: { [string]: Frame } = {} -- keyed by the child node id
local selected = Upgrades.Root
local pan = Vector2.zero
local extent = Vector2.new(400, 400) -- half size of the whole tree in canvas pixels

local function hexToPixel(q: number, r: number): Vector2
	return Vector2.new(SPACING * math.sqrt(3) * (q + r / 2), SPACING * 1.5 * r)
end

-- ---------------------------------------------------------------- state of each node

-- "Open" (buy level 1), "Owned" (1+), "Max", "Rebirth" (needs more rebirths),
-- "Mystery" ("?" next to something you can see), "Hidden" (not drawn yet).
local function computeStates(data): { [string]: string }
	local levels = data.Upgrades
	local states = {}
	for _, def in Upgrades.List do -- parents always come before their children
		local level = levels[def.Id] or 0
		local state
		if level >= def.MaxLevel then
			state = "Max"
		elseif level > 0 then
			state = "Owned"
		elseif def.Parent and (levels[def.Parent] or 0) < 1 then
			local parentState = states[def.Parent]
			state = if parentState == "Open" or parentState == "Rebirth" then "Mystery" else "Hidden"
		elseif (data.Rebirths or 0) < def.RequiredRebirths then
			state = "Rebirth"
		else
			state = "Open"
		end
		states[def.Id] = state
	end
	return states
end

local function canBuy(def: UpgradeDef, data, state: string): boolean
	if state ~= "Open" and state ~= "Owned" then
		return false
	end
	return BigNum.gte(data.Cash, Upgrades.cost(def, data.Upgrades[def.Id] or 0))
end

-- How many levels you can afford right now (for the Buy Max button).
local function affordableLevels(def: UpgradeDef, data): number
	local level = data.Upgrades[def.Id] or 0
	local total = 0
	local count = 0
	while level + count < def.MaxLevel do
		total += Upgrades.cost(def, level + count)
		if not BigNum.gte(data.Cash, total) then
			break
		end
		count += 1
	end
	return count
end

-- ---------------------------------------------------------------- pan and zoom

local function clampPan()
	local k = zoom.Scale
	local size = tree.AbsoluteSize / math.max(Ui.windowScale(), 0.01)
	local limit = Vector2.new(math.max(0, extent.X * k - size.X / 2 + 60), math.max(0, extent.Y * k - size.Y / 2 + 60))
	pan = Vector2.new(math.clamp(pan.X, -limit.X, limit.X), math.clamp(pan.Y, -limit.Y, limit.Y))
	canvas.Position = UDim2.new(0.5, pan.X, 0.5, pan.Y)
end

local function setZoom(value: number)
	local old = zoom.Scale
	local new = math.clamp(value, ZOOM_MIN, ZOOM_MAX)
	-- Keep the middle of the board where it is.
	pan *= new / old
	zoom.Scale = new
	clampPan()
end

-- Centres the board on a node (or the root).
local function focus(id: string, instant: boolean?)
	local def = Upgrades.ById[id]
	local p = hexToPixel(def.Hex.q, def.Hex.r) * zoom.Scale
	pan = -p
	local before = canvas.Position
	clampPan()
	if not instant and not Ui.reducedMotion() then
		local target = canvas.Position
		canvas.Position = before
		TweenService:Create(canvas, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target }):Play()
	end
end

local function overTree(position: any): boolean
	local p = Vector2.new(position.X, position.Y)
	local a, s = tree.AbsolutePosition, tree.AbsoluteSize
	return p.X >= a.X and p.Y >= a.Y and p.X <= a.X + s.X and p.Y <= a.Y + s.Y
end

local dragInput: InputObject? = nil
local dragFrom = Vector2.zero
local panFrom = Vector2.zero
local dragged = false
local draggedAt = 0

local function setupDragging()
	UserInputService.InputBegan:Connect(function(input)
		if not gui.Enabled or dragInput then
			return
		end
		local kind = input.UserInputType
		if (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) and overTree(input.Position) then
			dragInput = input
			dragFrom = Vector2.new(input.Position.X, input.Position.Y)
			panFrom = pan
			dragged = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not gui.Enabled then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel and overTree(input.Position) then
			setZoom(zoom.Scale * (if input.Position.Z > 0 then 1.12 else 1 / 1.12))
			return
		end
		local active = dragInput
		if not active then
			return
		end
		local matches = if active.UserInputType == Enum.UserInputType.Touch
			then input == active
			else input.UserInputType == Enum.UserInputType.MouseMovement
		if not matches then
			return
		end
		local delta = Vector2.new(input.Position.X, input.Position.Y) - dragFrom
		if not dragged and delta.Magnitude < DRAG_THRESHOLD then
			return
		end
		dragged = true
		pan = panFrom + delta / math.max(Ui.windowScale(), 0.01)
		clampPan()
	end)
	UserInputService.InputEnded:Connect(function(input)
		local active = dragInput
		if not active then
			return
		end
		if input == active or (active.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then
			dragInput = nil
			if dragged then
				draggedAt = os.clock()
			end
		end
	end)
	local pinchFrom = ZOOM_START
	UserInputService.TouchPinch:Connect(function(positions, scale, _velocity, state)
		if not gui.Enabled or #positions < 2 then
			return
		end
		if state == Enum.UserInputState.Begin then
			pinchFrom = zoom.Scale
			dragInput = nil
		elseif state == Enum.UserInputState.Change and overTree((positions[1] + positions[2]) / 2) then
			setZoom(pinchFrom * scale)
		end
	end)
end

-- ---------------------------------------------------------------- drawing

local function setLevelText(node: ImageButton, value: string?)
	local plate = node:FindFirstChild("Level") :: Frame
	plate.Visible = value ~= nil
	if value then
		(plate:FindFirstChild("Label") :: TextLabel).Text = value
	end
end

local renderDetail: () -> ()

local function renderNodes(data, states: { [string]: string })
	for _, def in Upgrades.List do
		local node = nodes[def.Id]
		local state = states[def.Id]
		local level = data.Upgrades[def.Id] or 0
		node.Visible = state ~= "Hidden"
		node.ImageColor3 = TILE[state] or TILE.Mystery
		local icon = node:FindFirstChild("Icon") :: ImageLabel
		local lock = node:FindFirstChild("Lock") :: ImageLabel
		local question = node:FindFirstChild("Question") :: TextLabel
		icon.Visible = state == "Open" or state == "Owned" or state == "Max"
		icon.ImageTransparency = if state == "Open" and not canBuy(def, data, state) then 0.35 else 0
		lock.Visible = state == "Rebirth"
		question.Visible = state == "Mystery"
		if state == "Max" then
			setLevelText(node, "MAX")
		elseif state == "Rebirth" then
			setLevelText(node, `R{def.RequiredRebirths}`)
		elseif state == "Mystery" then
			setLevelText(node, nil)
		else
			setLevelText(node, `{level}/{def.MaxLevel}`)
		end
		local glow = node:FindFirstChild("Glow") :: ImageLabel
		if def.Id == selected and state ~= "Hidden" then
			glow.Visible = true
			glow.ImageColor3 = WHITE
		elseif canBuy(def, data, state) then
			glow.Visible = true
			glow.ImageColor3 = GREEN
		else
			glow.Visible = false
		end

		local link = links[def.Id]
		if link then
			local parentState = states[def.Parent :: string]
			link.Visible = state ~= "Hidden" and parentState ~= "Hidden"
			link.BackgroundColor3 = if state == "Owned" or state == "Max"
				then LINK_ON
				elseif state == "Open" then LINK_OPEN
				else LINK_OFF
		end
	end
end

local function render()
	local data = State.data
	if not data or not gui.Enabled then
		return
	end
	local states = computeStates(data)
	if states[selected] == "Hidden" then
		selected = Upgrades.Root
	end
	renderNodes(data, states)
	renderDetail()
end

renderDetail = function()
	local data = State.data
	if not data then
		return
	end
	local def = Upgrades.ById[selected]
	local states = computeStates(data)
	local state = states[def.Id]
	local level = data.Upgrades[def.Id] or 0
	local statDef = Upgrades.Stats[def.Stat]
	local mystery = state == "Mystery"

	local icon = detail:FindFirstChild("Icon") :: ImageLabel
	icon.Image = AssetLibrary.image(if mystery then "Icon_Lock" else def.Icon)
	;(detail:FindFirstChild("Name") :: TextLabel).Text = if mystery then "???" else def.Name
	;(detail:FindFirstChild("Level") :: TextLabel).Text = if mystery then "Not found yet" else `Level {level} / {def.MaxLevel}`
	;(detail:FindFirstChild("Desc") :: TextLabel).Text = if mystery
		then "Buy the upgrade next to it to see what this is."
		else def.Description

	local box = detail:FindFirstChild("EffectBox") :: Frame
	local effect = box:FindFirstChild("Effect") :: TextLabel
	local total = box:FindFirstChild("Total") :: TextLabel
	box.Visible = not mystery
	if level >= def.MaxLevel then
		effect.Text = Upgrades.describe(def, level)
	else
		effect.Text = `{Upgrades.describe(def, level)} > {Upgrades.describe(def, level + 1)}`
	end
	total.Text = `{statDef.Name} total: {Upgrades.describeStat(def.Stat, Upgrades.stat(data.Upgrades, def.Stat))}`

	local status = detail:FindFirstChild("Status") :: TextLabel
	local cost = detail:FindFirstChild("Cost") :: TextLabel
	local buy = detail:FindFirstChild("Buy") :: TextButton
	local max = detail:FindFirstChild("Max") :: TextButton
	status.Text = ""
	status.TextColor3 = Color3.fromRGB(255, 77, 94)
	cost.Text = ""
	max.Visible = false
	if state == "Max" then
		Ui.setText(buy, "MAXED")
		buy.BackgroundColor3 = GOLD
		status.TextColor3 = Color3.fromRGB(30, 158, 58)
		status.Text = "Fully upgraded!"
	elseif mystery then
		Ui.setText(buy, "Locked")
		buy.BackgroundColor3 = GREY
	elseif state == "Rebirth" then
		Ui.setText(buy, `Rebirth {def.RequiredRebirths}`)
		buy.BackgroundColor3 = PURPLE
		status.Text = `Rebirth {def.RequiredRebirths} time{if def.RequiredRebirths == 1 then "" else "s"} to open this`
		cost.Text = `Cost: {Format.cash(Upgrades.cost(def, level))}`
	else
		local price = Upgrades.cost(def, level)
		local affordable = BigNum.gte(data.Cash, price)
		cost.Text = `Cost: {Format.cash(price)}`
		Ui.setText(buy, if level == 0 then "Unlock" else "Buy")
		buy.BackgroundColor3 = if affordable then GREEN else GREY
		if not affordable then
			status.Text = `Need {Format.cash(BigNum.sub(price, data.Cash))} more`
		end
		local count = affordableLevels(def, data)
		if count >= 2 then
			max.Visible = true
			Ui.setText(max, `Buy Max (x{count})`)
		end
	end
	cost.TextColor3 = INK_TEXT
end

local function selectNode(id: string)
	selected = id
	render()
end

local function buy(count: number)
	local def = Upgrades.ById[selected]
	local ok, message = Net.func("BuyUpgrade"):InvokeServer(def.Id, count)
	if message and message ~= "" then
		C.HudController:Toast(message, if ok then "Good" else "Bad")
	end
	if ok then
		Ui.sound("Coin")
		local node = nodes[def.Id]
		if node and not Ui.reducedMotion() then
			local grow = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
			node.Size = nodeSize
			local big = UDim2.fromOffset(nodeSize.X.Offset * 1.18, nodeSize.Y.Offset * 1.18)
			TweenService:Create(node, grow, { Size = big }):Play()
		end
	end
end

-- Builds every node and link once from Config/Upgrades.
local function build()
	local nodeTemplate = canvas:FindFirstChild("NodeTemplate") :: ImageButton
	local linkTemplate = canvas:FindFirstChild("LinkTemplate") :: Frame
	nodeSize = nodeTemplate.Size
	local nodeFolder = canvas:FindFirstChild("Nodes") :: Frame
	local linkFolder = canvas:FindFirstChild("Links") :: Frame
	local maxX, maxY = 0, 0
	for i, def in Upgrades.List do
		local p = hexToPixel(def.Hex.q, def.Hex.r)
		maxX, maxY = math.max(maxX, math.abs(p.X)), math.max(maxY, math.abs(p.Y))
		local node = nodeTemplate:Clone()
		node.Name = def.Id
		node.Position = UDim2.fromOffset(p.X, p.Y)
		node.LayoutOrder = i
		node.Visible = false
		;(node:FindFirstChild("Icon") :: ImageLabel).Image = AssetLibrary.image(def.Icon)
		node.Parent = nodeFolder
		nodes[def.Id] = node
		node.Activated:Connect(function()
			-- A drag that started on a node shouldn't select it.
			if dragged and os.clock() - draggedAt < 0.2 then
				return
			end
			Ui.sound("Click")
			selectNode(def.Id)
		end)

		if def.Parent then
			local parent = Upgrades.ById[def.Parent]
			local a = hexToPixel(parent.Hex.q, parent.Hex.r)
			local mid = (a + p) / 2
			local d = p - a
			local link = linkTemplate:Clone()
			link.Name = def.Id
			link.Position = UDim2.fromOffset(mid.X, mid.Y)
			link.Size = UDim2.fromOffset(math.max(10, d.Magnitude - LINK_TRIM), linkTemplate.Size.Y.Offset)
			link.Rotation = math.deg(math.atan2(d.Y, d.X))
			link.Visible = false
			link.Parent = linkFolder
			links[def.Id] = link
		end
	end
	extent = Vector2.new(maxX + 50, maxY + 56)

	-- Affordable nodes breathe so the board shows what you can buy.
	if not Ui.reducedMotion() then
		local pulse = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		for _, node in nodes do
			local glow = node:FindFirstChild("Glow") :: ImageLabel
			TweenService:Create(glow, pulse, { ImageTransparency = 0.45 }):Play()
		end
	end
end

-- ---------------------------------------------------------------- open / badge

function UpgradeController:Toggle()
	Ui.toggle("Upgrades")
	render()
end

function UpgradeController:Open()
	Ui.open("Upgrades")
	render()
end

local function updateBadge(data)
	local badge = railBadge
	if not badge then
		return
	end
	local states = computeStates(data)
	local count = 0
	for _, def in Upgrades.List do
		if canBuy(def, data, states[def.Id]) then
			count += 1
		end
	end
	Ui.setBadge(badge, if count > 0 then count else nil)
end

local function bobHologram()
	local structures = Workspace:WaitForChild("Structures", 60)
	local station = structures and structures:WaitForChild("UpgradeStation", 30)
	local holo = station and station:WaitForChild("Hologram", 30)
	local billboard = holo and holo:FindFirstChildOfClass("BillboardGui")
	if not billboard or Ui.reducedMotion() then
		return
	end
	local info = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(billboard, info, { StudsOffset = Vector3.new(0, 0.8, 0) }):Play()
end

function UpgradeController:Init(controllers)
	C = controllers
	gui = Ui.screen("Upgrades")
	tree = Ui.find(gui, "Window.Tree")
	canvas = Ui.find(gui, "Window.Tree.Canvas")
	zoom = Ui.find(gui, "Window.Tree.Canvas.Zoom")
	detail = Ui.find(gui, "Window.Detail")
end

function UpgradeController:Start()
	build()
	zoom.Scale = ZOOM_START
	focus(Upgrades.Root, true)
	setupDragging()

	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Upgrades")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Upgrades")
	end)
	Ui.button(Ui.find(tree, "ZoomIn"), function()
		setZoom(zoom.Scale + 0.15)
	end)
	Ui.button(Ui.find(tree, "ZoomOut"), function()
		setZoom(zoom.Scale - 0.15)
	end)
	Ui.button(Ui.find(tree, "Home"), function()
		zoom.Scale = ZOOM_START
		focus(Upgrades.Root)
	end)
	Ui.button(Ui.find(detail, "Buy"), function()
		buy(1)
	end)
	Ui.button(Ui.find(detail, "Max"), function()
		buy(100)
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("Opens") == "Upgrades" then
			UpgradeController:Open()
		end
	end)
	task.spawn(bobHologram)
	task.spawn(function()
		railBadge = Ui.find(Ui.screen("Hud"), "Rail.UpgradesButton"):FindFirstChild("Badge") :: GuiObject?
		if State.data then
			updateBadge(State.data)
		end
	end)

	-- Redraw when levels, rebirths or what you can afford change (not on every cash tick).
	local lastSignature = ""
	State.Changed:Connect(function(data)
		local parts = { tostring(data.Rebirths or 0), selected }
		for _, def in Upgrades.List do
			local level = data.Upgrades[def.Id] or 0
			table.insert(parts, `{level}:{BigNum.gte(data.Cash, Upgrades.cost(def, level))}`)
		end
		local def = Upgrades.ById[selected]
		table.insert(parts, tostring(affordableLevels(def, data)))
		local signature = table.concat(parts, "|")
		if signature ~= lastSignature then
			lastSignature = signature
			updateBadge(data)
			render()
		end
	end)
end

return UpgradeController
