--!strict
-- Upgrade Tree (Upgrade Station on the south plaza, or the rail button), Slime RNG style:
-- full screen over the dimmed world, a honeycomb of hexagons with icon, name and price
-- inside. Tap a hex to buy a level. Hexes next to what you own show as "?" until you get
-- next to them; rebirth-gated ones show a lock. Lab hexes (Egg Lab, Lucky Lab, Pet Lab)
-- cost cash once, then tapping them flies into that lab's own honeycomb; BACK returns.
-- Drag to look around, pinch / mouse wheel / +- to zoom. Hovering (or tapping) a hex shows
-- what it does above CLOSE. Also keeps the rail button's badge (how many hexes you can buy)
-- and bobs the floating arrow over the station.
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

local WHITE = Color3.new(1, 1, 1)
local RED = Color3.fromRGB(255, 77, 94)
local GOLD_TEXT = Color3.fromRGB(255, 214, 90)
local INFO_GREEN = Color3.fromRGB(124, 245, 138)

-- Hex colours by state (the tile image is white with a dark outline; this tints it).
local TILE = {
	Open = Color3.fromRGB(42, 49, 66),
	Owned = Color3.fromRGB(47, 155, 255),
	Max = Color3.fromRGB(255, 190, 50),
	Lab = Color3.fromRGB(61, 200, 90),
	Rebirth = Color3.fromRGB(91, 74, 143),
	Mystery = Color3.fromRGB(58, 63, 75),
}

local SPACING = 79 -- hex grid size (centre to corner) in board pixels; hexes are 150 tall
local ZOOM_MIN, ZOOM_MAX = 0.5, 1.5
local DRAG_THRESHOLD = 10 -- screen pixels before a press becomes a drag

local UpgradeController = {}

local C: any
local gui: ScreenGui
local canvas: Frame
local zoom: UIScale
local title: TextLabel
local tip: Frame
local backButton: TextButton

local boards: { [string]: Frame } = {}
local nodes: { [string]: ImageButton } = {}
local nodeSize = UDim2.fromOffset(130, 150)
local extents: { [string]: Vector2 } = {}
local current = "Main"
local hovered: string? = nil
local pan = Vector2.zero
local railBadge: GuiObject? = nil

local function hexToPixel(q: number, r: number): Vector2
	return Vector2.new(SPACING * math.sqrt(3) * (q + r / 2), SPACING * 1.5 * r)
end

-- ---------------------------------------------------------------- state of each node

-- "Open" (buy level 1), "Owned" (1+), "Max", "Rebirth" (needs more rebirths),
-- "Mystery" ("?" next to something you can see), "Hidden" (not drawn yet).
-- A lab's sub-tree root is open as soon as you can enter the lab.
local function computeStates(data): { [string]: string }
	local levels = data.Upgrades
	local states = {}
	for _, def in Upgrades.List do -- parents always come before their children
		local level = levels[def.Id] or 0
		local need = def.Parent
		local state
		if level >= def.MaxLevel then
			state = "Max"
		elseif level > 0 then
			state = "Owned"
		elseif need and (levels[need] or 0) < 1 then
			local parentState = states[need]
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

local function price(def: UpgradeDef, data): number
	return Upgrades.cost(def, data.Upgrades[def.Id] or 0)
end

-- Can be bought right now (sub-tree roots also need their lab).
local function canBuy(def: UpgradeDef, data, state: string): boolean
	if state ~= "Open" and state ~= "Owned" then
		return false
	end
	local need = Upgrades.requires(def)
	if need and (data.Upgrades[need] or 0) < 1 then
		return false
	end
	return BigNum.gte(data.Cash, price(def, data))
end

-- ---------------------------------------------------------------- pan and zoom

local function viewSize(): Vector2
	local camera = Workspace.CurrentCamera
	local view = if camera then camera.ViewportSize else Vector2.new(1456, 820)
	return view / math.max(Ui.scale(), 0.01)
end

local function clampPan()
	local k = zoom.Scale
	local extent = extents[current] or Vector2.new(300, 300)
	local size = viewSize()
	local limit = Vector2.new(math.max(0, extent.X * k - size.X / 2 + 120), math.max(0, extent.Y * k - size.Y / 2 + 160))
	pan = Vector2.new(math.clamp(pan.X, -limit.X, limit.X), math.clamp(pan.Y, -limit.Y, limit.Y))
	canvas.Position = UDim2.new(0.5, pan.X, 0.5, pan.Y)
end

local function setZoom(value: number)
	local old = zoom.Scale
	local new = math.clamp(value, ZOOM_MIN, ZOOM_MAX)
	pan *= new / old -- keep the middle of the board where it is
	zoom.Scale = new
	clampPan()
end

-- Zoom that fits a whole board on screen between the title and CLOSE (never above 1).
local function fitZoom(): number
	local extent = extents[current] or Vector2.new(300, 300)
	local size = viewSize()
	local k = math.min((size.X - 120) / (extent.X * 2), (size.Y - 330) / (extent.Y * 2), 1)
	return math.clamp(k, ZOOM_MIN, 1)
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
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
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
		if input.UserInputType == Enum.UserInputType.MouseWheel then
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
		pan = panFrom + delta / math.max(Ui.scale(), 0.01)
		clampPan()
	end)
	UserInputService.InputEnded:Connect(function(input)
		local active = dragInput
		if not active then
			return
		end
		if
			input == active
			or (active.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1)
		then
			dragInput = nil
			if dragged then
				draggedAt = os.clock()
			end
		end
	end)
	local pinchFrom = 1
	UserInputService.TouchPinch:Connect(function(positions, scale, _velocity, state)
		if not gui.Enabled or #positions < 2 then
			return
		end
		if state == Enum.UserInputState.Begin then
			pinchFrom = zoom.Scale
			dragInput = nil
			dragged = true
			draggedAt = os.clock()
		elseif state == Enum.UserInputState.Change then
			setZoom(pinchFrom * scale)
			draggedAt = os.clock()
		end
	end)
end

-- ---------------------------------------------------------------- drawing

local function setTip(id: string?)
	local data = State.data
	local nameLabel = tip:FindFirstChild("Name") :: TextLabel
	local info = tip:FindFirstChild("Info") :: TextLabel
	local desc = tip:FindFirstChild("Desc") :: TextLabel
	info.TextColor3 = INFO_GREEN
	if not data or not id then
		nameLabel.Text = Upgrades.Trees[current].Name
		info.Text = "Tap a hexagon to buy it"
		desc.Text = if current == "Main" then "Labs open their own upgrade trees" else "BACK returns to the main tree"
		return
	end
	local def = Upgrades.ById[id]
	local state = computeStates(data)[id]
	local level = data.Upgrades[id] or 0
	if state == "Mystery" then
		nameLabel.Text = "???"
		info.Text = "Buy the upgrade next to it to find out"
		desc.Text = ""
		return
	end
	nameLabel.Text = def.Name
	desc.Text = def.Description
	if def.Opens then
		info.Text = if level > 0 then "Tap to go inside" else `Unlock for {Format.cash(price(def, data))}`
	elseif state == "Rebirth" then
		info.TextColor3 = RED
		info.Text = `Rebirth {def.RequiredRebirths} time{if def.RequiredRebirths == 1 then "" else "s"} to open this`
	elseif state == "Max" then
		info.TextColor3 = GOLD_TEXT
		info.Text = `MAX  {Upgrades.describe(def, level)} {Upgrades.Stats[def.Stat].Name}`
	else
		local stat = Upgrades.Stats[def.Stat]
		info.Text = `Level {level}/{def.MaxLevel}  ·  {Upgrades.describe(def, level)} > {Upgrades.describe(def, level + 1)} {stat.Name}`
	end
end

local function renderBoard()
	local data = State.data
	if not data or not gui.Enabled then
		return
	end
	local states = computeStates(data)
	for _, def in Upgrades.List do
		if def.Tree ~= current then
			continue
		end
		local node = nodes[def.Id]
		local state = states[def.Id]
		local level = data.Upgrades[def.Id] or 0
		local isLab = def.Opens ~= nil
		node.Visible = state ~= "Hidden"
		node.ImageColor3 = if isLab and level > 0 then TILE.Lab else TILE[state] or TILE.Mystery

		local known = state == "Open" or state == "Owned" or state == "Max" or state == "Rebirth"
		local icon = node:FindFirstChild("Icon") :: ImageLabel
		local nameLabel = node:FindFirstChild("Name") :: TextLabel
		local priceRow = node:FindFirstChild("Price") :: Frame
		local priceLabel = priceRow:FindFirstChild("Label") :: TextLabel
		local coin = priceRow:FindFirstChild("Coin") :: ImageLabel
		local levelLabel = node:FindFirstChild("Level") :: TextLabel
		icon.Visible = known and state ~= "Rebirth"
		nameLabel.Visible = known
		priceRow.Visible = known
		levelLabel.Visible = known and not isLab and state ~= "Rebirth"
		levelLabel.Text = `{level}/{def.MaxLevel}`
		;(node:FindFirstChild("Lock") :: ImageLabel).Visible = state == "Rebirth"
		;(node:FindFirstChild("Question") :: TextLabel).Visible = state == "Mystery"

		coin.Visible = false
		priceLabel.TextColor3 = WHITE
		if isLab and level > 0 then
			priceLabel.Text = "ENTER"
		elseif state == "Max" then
			priceLabel.Text = "MAX"
		elseif state == "Rebirth" then
			priceLabel.Text = `Rebirth {def.RequiredRebirths}`
		else
			local cost = price(def, data)
			coin.Visible = true
			priceLabel.Text = Format.big(cost)
			priceLabel.TextColor3 = if BigNum.gte(data.Cash, cost) then WHITE else RED
		end
		;(node:FindFirstChild("Glow") :: ImageLabel).Visible = canBuy(def, data, state)
	end
	setTip(hovered)
end

local function popNode(node: ImageButton)
	if Ui.reducedMotion() then
		return
	end
	node.Size = nodeSize
	local big = UDim2.fromOffset(nodeSize.X.Offset * 1.15, nodeSize.Y.Offset * 1.15)
	TweenService:Create(node, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Size = big }):Play()
end

-- Shows one board (Main or a lab) and frames it on screen.
local function showBoard(treeId: string, flyIn: boolean?)
	current = treeId
	for id, board in boards do
		board.Visible = id == treeId
	end
	backButton.Visible = treeId ~= "Main"
	title.Text = if treeId == "Main" then "Upgrades!" else `{Upgrades.Trees[treeId].Name}!`
	hovered = nil
	local target = fitZoom()
	zoom.Scale = target
	pan = Vector2.zero
	clampPan()
	renderBoard()
	if flyIn and not Ui.reducedMotion() then
		-- The new board grows out of the middle of the screen.
		zoom.Scale = target * 0.4
		TweenService:Create(zoom, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
	end
end

local function onNodeTapped(def: UpgradeDef)
	local data = State.data
	if not data then
		return
	end
	hovered = def.Id
	local state = computeStates(data)[def.Id]
	local level = data.Upgrades[def.Id] or 0
	if def.Opens and level > 0 then
		Ui.sound("Open")
		showBoard(def.Opens, true)
		return
	end
	if state == "Mystery" or state == "Rebirth" or state == "Max" then
		Ui.sound("Error")
		setTip(def.Id)
		return
	end
	local ok, message = Net.func("BuyUpgrade"):InvokeServer(def.Id, 1)
	if ok then
		Ui.sound("Coin")
		popNode(nodes[def.Id])
	else
		Ui.sound("Error")
		if message and message ~= "" then
			C.HudController:Toast(message, "Bad")
		end
	end
	setTip(def.Id)
end

-- Builds every board and hex once from Config/Upgrades.
local function build()
	local template = canvas:FindFirstChild("NodeTemplate") :: ImageButton
	nodeSize = template.Size
	for treeId in Upgrades.Trees do
		local board = Instance.new("Frame")
		board.Name = treeId
		board.BackgroundTransparency = 1
		board.Size = UDim2.fromOffset(0, 0)
		board.Visible = false
		board.Parent = canvas
		boards[treeId] = board
		extents[treeId] = Vector2.new(100, 100)
	end
	for i, def in Upgrades.List do
		local p = hexToPixel(def.Hex.q, def.Hex.r)
		local e = extents[def.Tree]
		extents[def.Tree] = Vector2.new(math.max(e.X, math.abs(p.X) + 70), math.max(e.Y, math.abs(p.Y) + 80))
		local node = template:Clone()
		node.Name = def.Id
		node.Position = UDim2.fromOffset(p.X, p.Y)
		node.LayoutOrder = i
		node.Visible = false
		;(node:FindFirstChild("Icon") :: ImageLabel).Image = AssetLibrary.image(def.Icon)
		;(node:FindFirstChild("Name") :: TextLabel).Text = def.Name
		node.Parent = boards[def.Tree]
		nodes[def.Id] = node
		node.Activated:Connect(function()
			-- A drag or pinch that ended on a hex shouldn't buy it.
			if dragged and os.clock() - draggedAt < 0.25 then
				return
			end
			onNodeTapped(def)
		end)
		node.MouseEnter:Connect(function()
			hovered = def.Id
			setTip(def.Id)
		end)
		node.MouseLeave:Connect(function()
			if hovered == def.Id then
				hovered = nil
				setTip(nil)
			end
		end)
	end
	-- Hexes you can afford breathe so the board shows what to buy.
	if not Ui.reducedMotion() then
		local pulse = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		for _, node in nodes do
			TweenService:Create(node:FindFirstChild("Glow") :: ImageLabel, pulse, { ImageTransparency = 0.5 }):Play()
		end
	end
end

-- ---------------------------------------------------------------- open / badge

function UpgradeController:Toggle()
	Ui.toggle("Upgrades")
	if gui.Enabled then
		showBoard("Main")
	end
end

function UpgradeController:Open()
	Ui.open("Upgrades")
	showBoard("Main")
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
	canvas = Ui.find(gui, "Board.Scaler.Canvas")
	zoom = Ui.find(canvas, "Zoom")
	title = Ui.find(gui, "Top.Title")
	tip = Ui.find(gui, "Bottom.Tip")
	backButton = Ui.find(gui, "Bottom.Back")
end

function UpgradeController:Start()
	build()
	setupDragging()

	Ui.button(Ui.find(gui, "Bottom.Close"), function()
		Ui.close("Upgrades")
	end)
	Ui.button(backButton, function()
		local lab = Upgrades.Trees[current].Portal
		showBoard("Main")
		if lab then
			-- Land on the lab hex you came out of.
			local def = Upgrades.ById[lab]
			pan = -hexToPixel(def.Hex.q, def.Hex.r) * zoom.Scale
			clampPan()
		end
	end)
	Ui.button(Ui.find(gui, "Bottom.ZoomIn"), function()
		setZoom(zoom.Scale + 0.15)
	end)
	Ui.button(Ui.find(gui, "Bottom.ZoomOut"), function()
		setZoom(zoom.Scale - 0.15)
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
		local parts = { tostring(data.Rebirths or 0) }
		for _, def in Upgrades.List do
			local level = data.Upgrades[def.Id] or 0
			table.insert(parts, `{level}:{BigNum.gte(data.Cash, Upgrades.cost(def, level))}`)
		end
		local signature = table.concat(parts, "|")
		if signature ~= lastSignature then
			lastSignature = signature
			updateBadge(data)
			renderBoard()
		end
	end)
end

return UpgradeController
