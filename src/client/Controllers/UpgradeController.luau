--!strict
-- Upgrade Tree (Upgrade Station on the south plaza, or the rail button), Slime RNG style:
-- full screen over the dimmed world, a honeycomb of flat-top hexagons with icon, name and
-- price inside. Opening a board blooms its hexes out from the middle one ring at a time;
-- buying a hex pops the hexes it opens into view, and newly opened hexes flash with a NEW!
-- tag until you look at them. Hover a hex (PC) or tap it (phones) for a tooltip; tap /
-- click it again to buy. Hexes next to what you own show as "?" until you get
-- next to them; rebirth-gated ones show a lock. Lab hexes (Egg Lab, Lucky Lab, Pet Lab)
-- cost cash once, then tapping them flies into that lab's own honeycomb; BACK returns.
-- Drag to look around, pinch / mouse wheel / +- to zoom. Every other UI hides while the
-- tree is open. Also keeps the rail button's badge (how many hexes you can buy)
-- and bobs the floating arrow over the station.
local ContentProvider = game:GetService("ContentProvider")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
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
local Tools = require(Shared.Config.Tools)
local Upgrades = require(Shared.Config.Upgrades)
local Types = require(Shared.Types)

type UpgradeDef = Types.UpgradeDef

local WHITE = Color3.new(1, 1, 1)
local RED = Color3.fromRGB(255, 77, 94)
local GREEN = Color3.fromRGB(61, 220, 90)
local GOLD_TEXT = Color3.fromRGB(255, 214, 90)
local INFO_GREEN = Color3.fromRGB(124, 245, 138)

-- Hex colours by state (the Fill hexagon's three bars).
local TILE = {
	Open = Color3.fromRGB(42, 49, 66),
	Owned = Color3.fromRGB(47, 155, 255),
	Max = Color3.fromRGB(47, 155, 255), -- bought: blue like Slime RNG
	Lab = Color3.fromRGB(255, 196, 40), -- an unlocked lab: gold with "Open" (Slime RNG)
	Back = Color3.fromRGB(235, 30, 45), -- a lab's centre hex: red, takes you back
	Rebirth = Color3.fromRGB(91, 74, 143),
	Mystery = Color3.fromRGB(58, 63, 75),
}

local SPACING = 79 -- hex grid size (centre to corner) in board pixels; hexes are 150 wide
local FLASH = Color3.fromRGB(255, 236, 140) -- newly opened hexes pulse towards this
local ZOOM_MIN, ZOOM_MAX = 0.5, 1.5
local DRAG_THRESHOLD = 10 -- screen pixels before a press becomes a drag

local UpgradeController = {}

local gui: ScreenGui
local canvas: Frame
local zoom: UIScale
local title: TextLabel
local tip: Frame
local backHexes: { [string]: TextButton } = {} -- each lab's red centre hex

local boards: { [string]: Frame } = {}
local nodes: { [string]: TextButton } = {}
local nodeSize = UDim2.fromOffset(150, 130)
local extents: { [string]: Vector2 } = {}
local current = "Main"
-- Each board's zoom and pan, kept while you play so closing and reopening the window (or
-- going into a lab and back) doesn't reset your view (Dev, 2026-10-30).
local views: { [string]: { zoom: number, pan: Vector2 } } = {}
local hovered: string? = nil -- mouse is over this hex
local selected: string? = nil -- tapped once: tooltip stays, the next tap buys

-- Phones: the first tap shows the tooltip, so buying takes a second tap. With a mouse or a
-- controller the tooltip is already up from hovering, so one click buys (Dev, 2026-10-31).
-- Phones: the first tap shows the tooltip (the exact numbers), the second buys. With a mouse
-- the tooltip is up from hovering, so one click buys (Dev, 2026-10-31).
local function twoTaps(): boolean
	return UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

local flashText: string? = nil -- a short message in the tooltip (e.g. "Need $50 more")
local flashUntil = 0
local pan = Vector2.zero
local railBadge: GuiObject? = nil
local useImage = false -- the HexTile image loaded; until then hexes are drawn with frames

-- Flat-top hexes (Slime RNG): {0,-1} is straight up, {1,0} down-right.
local function hexToPixel(q: number, r: number): Vector2
	return Vector2.new(SPACING * 1.5 * q, SPACING * math.sqrt(3) * (r + q / 2))
end

-- Where a hex is drawn. A lab's centre spot is its red Back hex (Slime RNG), so each lab
-- board is shifted one step: its root sits next to the Back hex, nothing sits on it.
local shift: { [string]: { q: number, r: number } } = {}
do
	local spots: { [string]: { [string]: boolean } } = {}
	for _, def in Upgrades.List do
		spots[def.Tree] = spots[def.Tree] or {}
		spots[def.Tree][`{def.Hex.q},{def.Hex.r}`] = true
	end
	local dirs = {
		{ q = 0, r = 1 },
		{ q = 0, r = -1 },
		{ q = 1, r = 0 },
		{ q = -1, r = 0 },
		{ q = 1, r = -1 },
		{ q = -1, r = 1 },
	}
	for treeId in Upgrades.Trees do
		shift[treeId] = { q = 0, r = 0 }
		-- Generated lab boards already leave the centre free (tools/gen_upgrade_tree.py).
		if treeId ~= "Main" and (spots[treeId] or {})["0,0"] then
			for _, d in dirs do
				if not (spots[treeId] or {})[`{-d.q},{-d.r}`] then
					shift[treeId] = d
					break
				end
			end
		end
	end
end

local function hexOf(def: UpgradeDef): { q: number, r: number }
	local d = shift[def.Tree]
	return { q = def.Hex.q + d.q, r = def.Hex.r + d.r }
end

-- Rings from the middle of a board (0 = the centre hex).
local function hexDistance(a: { q: number, r: number }, b: { q: number, r: number }): number
	local dq, dr = a.q - b.q, a.r - b.r
	return math.max(math.abs(dq), math.abs(dr), math.abs(dq + dr))
end

-- ---------------------------------------------------------------- animation state

local lastState: { [string]: string } = {} -- each hex's state the last time it was drawn
local fresh: { [string]: boolean } = {} -- newly opened: flashes with NEW! until looked at
local baseColor: { [string]: Color3 } = {} -- the tile colour renderBoard picked
local glowMode: { [string]: string? } = {} -- "select", "buy" or nil
local popToken: { [string]: number } = {} -- newer animations cancel older delayed ones
local lastBought: UpgradeDef? = nil -- new hexes pop in rippling out from here

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

-- An owned hex whose next tier needs more rebirths: the rebirth it waits for (else nil).
local function waitsForRebirth(def: UpgradeDef, data): number?
	local level = data.Upgrades[def.Id] or 0
	if level <= 0 or level >= def.MaxLevel then
		return nil
	end
	local need = Upgrades.requiredRebirths(def, level)
	return if (data.Rebirths or 0) < need then need else nil
end

local function levelText(def: UpgradeDef, level: number): string
	return `{level}/{def.MaxLevel}`
end

local function price(def: UpgradeDef, data): number
	local level = data.Upgrades[def.Id] or 0
	local cost = Upgrades.cost(def, level)
	if def.Id == "Power" and level == 0 then
		return Tools.tutorialPrice(cost, BigNum.toNumber(data.Cash), data.Flags.TutorialDone == true)
	end
	return cost
end

-- Can be bought right now (sub-tree roots also need their lab).
local function canBuy(def: UpgradeDef, data, state: string): boolean
	if state ~= "Open" and state ~= "Owned" then
		return false
	end
	if waitsForRebirth(def, data) then
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
	local limit =
		Vector2.new(math.max(0, extent.X * k - size.X / 2 + 120), math.max(0, extent.Y * k - size.Y / 2 + 160))
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
			or (
				active.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseButton1
			)
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

-- What the tooltip says for a hex (nil = nothing to show).
local function setTip(id: string?)
	local data = State.data
	if not data or not id then
		tip.Visible = false
		return
	end
	local nameLabel = tip:FindFirstChild("Name") :: TextLabel
	local info = tip:FindFirstChild("Info") :: TextLabel
	local desc = tip:FindFirstChild("Desc") :: TextLabel
	local hint = tip:FindFirstChild("Hint") :: TextLabel
	local def = Upgrades.ById[id]
	local state = computeStates(data)[id]
	local level = data.Upgrades[id] or 0
	local pad = Ui.gamepad()
	tip.Visible = true
	info.TextColor3 = INFO_GREEN
	hint.TextColor3 = GOLD_TEXT
	hint.Text = ""
	if state == "Mystery" then
		nameLabel.Text = "???"
		info.Text = "Buy the upgrade next to it to find out"
		desc.Text = ""
	else
		nameLabel.Text = Upgrades.name(def, level)
		desc.Text = Upgrades.description(def, level)
		local wait = waitsForRebirth(def, data)
		if def.Opens then
			info.Text = if level > 0
				then (if pad then "Press A to go inside" else "Tap to go inside")
				else `Unlock for {Format.cash(price(def, data))}`
		elseif state == "Rebirth" then
			info.TextColor3 = RED
			info.Text =
				`Rebirth {def.RequiredRebirths} time{if def.RequiredRebirths == 1 then "" else "s"} to open this`
		elseif state == "Max" then
			info.TextColor3 = GOLD_TEXT
			-- The whole tree's bonus for this stat, not just this hex (Dev, 2026-10-31).
			local total = Upgrades.describeStat(def.Stat, Upgrades.treeStat(data.Upgrades, def.Stat))
			info.Text = `Bought!  Total {total} {Upgrades.Stats[def.Stat].Name}`
		elseif wait then
			info.TextColor3 = RED
			info.Text =
				`Evolves at Rebirth {wait}  ·  now {Upgrades.describe(def, level)} {Upgrades.Stats[def.Stat].Name}`
		else
			local stat = Upgrades.Stats[def.Stat]
			local after = Upgrades.describe(def, level + 1)
			if def.MaxLevel == 1 then
				-- Total for the stat now > after buying this hex (Dev: show totals, not +30 +30).
				local now = Upgrades.treeStat(data.Upgrades, def.Stat)
				local nextTotal = now + Upgrades.bonus(def, level + 1) - Upgrades.bonus(def, level)
				info.Text =
					`{stat.Name}: {Upgrades.describeStat(def.Stat, now)} > {Upgrades.describeStat(def.Stat, nextTotal)}`
			else
				info.Text = `Lv {levelText(def, level)}  ·  {Upgrades.describe(def, level)} > {after} {stat.Name}`
			end
		end
		if (state == "Open" or state == "Owned") and not (def.Opens and level > 0) and not wait then
			local cost = price(def, data)
			if not BigNum.gte(data.Cash, cost) then
				hint.TextColor3 = RED
				hint.Text = `Need {Format.cash(BigNum.sub(cost, data.Cash))} more`
			elseif twoTaps() and selected == id then
				hint.Text = "Tap again to buy"
			end
		end
	end
	if flashText and os.clock() < flashUntil and selected == id then
		hint.TextColor3 = RED
		hint.Text = flashText
	end
end

-- The tooltip follows its hex (the board can move and zoom under it).
local function placeTip()
	local id = selected or hovered
	local node = id and nodes[id]
	if not tip.Visible or not node or not node.Visible then
		return
	end
	local origin = gui.AbsolutePosition
	local at = node.AbsolutePosition - origin
	local size = node.AbsoluteSize
	local half = tip.AbsoluteSize.X / 2
	local screen = gui.AbsoluteSize
	local x = math.clamp(at.X + size.X / 2, half + 6, screen.X - half - 6)
	local y = at.Y + size.Y * 0.08
	if y - tip.AbsoluteSize.Y < 6 then
		-- No room above: show it under the hex.
		tip.AnchorPoint = Vector2.new(0.5, 0)
		y = at.Y + size.Y * 0.92
	else
		tip.AnchorPoint = Vector2.new(0.5, 1)
	end
	tip.Position = UDim2.fromOffset(x, y)
end

local function refreshTip()
	setTip(selected or hovered)
	placeTip()
end

-- Hexagons are three rotated bars (gen_ui hexagon()).
local function setHex(hex: Frame, color: Color3)
	for _, bar in hex:GetChildren() do
		if bar:IsA("Frame") then
			bar.BackgroundColor3 = color
		end
	end
end

local function pop(id: string): UIScale
	return (nodes[id] :: any).Pop
end

-- Scales a hex from `from` to full size after `delay` (Back easing overshoots a little).
local function growIn(id: string, delay: number, from: number, time: number?)
	local scale = pop(id)
	popToken[id] = (popToken[id] or 0) + 1
	local token = popToken[id]
	if Ui.reducedMotion() then
		scale.Scale = 1
		return
	end
	scale.Scale = from
	task.delay(delay, function()
		if popToken[id] ~= token then
			return
		end
		TweenService
			:Create(scale, TweenInfo.new(time or 0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end)
end

-- A white hex ring that grows and fades from a hex (buying, a hex opening up).
local function shockwave(id: string, color: Color3?)
	local node = nodes[id]
	if Ui.reducedMotion() or not node then
		return
	end
	local ring = (node:FindFirstChild("Glow") :: Frame):Clone()
	ring.Name = "Shockwave"
	ring.Visible = true
	ring.Position = node.Position
	ring.ZIndex = 1
	local scale = Instance.new("UIScale")
	scale.Parent = ring
	ring.Parent = node.Parent
	local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, bar in ring:GetChildren() do
		if bar:IsA("Frame") then
			bar.BackgroundColor3 = color or WHITE
			bar.BackgroundTransparency = 0.1
			TweenService:Create(bar, info, { BackgroundTransparency = 1 }):Play()
		end
	end
	TweenService:Create(scale, info, { Scale = 1.55 }):Play()
	task.delay(0.5, function()
		ring:Destroy()
	end)
end

-- Opening a board: the centre hex first, then each ring around it, one hex after another
-- (Slime RNG's sub-category opening).
local function bloom(treeId: string)
	local list = {}
	for _, def in Upgrades.List do
		if def.Tree == treeId and nodes[def.Id].Visible then
			table.insert(list, def)
		end
	end
	local origin = { q = 0, r = 0 }
	local function angle(def: UpgradeDef): number
		local h = hexOf(def)
		local p = hexToPixel(h.q, h.r)
		return math.atan2(p.X, -p.Y) % (2 * math.pi) -- clockwise from straight up
	end
	table.sort(list, function(a, b)
		local da, db = hexDistance(hexOf(a), origin), hexDistance(hexOf(b), origin)
		if da ~= db then
			return da < db
		end
		return angle(a) < angle(b)
	end)
	local lastRing, inRing, ringStart = 0, 0, 0
	local back = backHexes[treeId]
	if back then
		-- The Back hex is the centre: it comes first.
		local scale = (back :: any).Pop :: UIScale
		scale.Scale = 0
		if Ui.reducedMotion() then
			scale.Scale = 1
		else
			TweenService
				:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
				:Play()
		end
		inRing = 1
	end
	for _, def in list do
		local ring = hexDistance(hexOf(def), origin)
		if ring ~= lastRing then
			-- Next ring starts a moment after the last one has started.
			ringStart += 0.05 + math.min(inRing, 6) * 0.02
			lastRing, inRing = ring, 0
		end
		growIn(def.Id, ringStart + math.min(inRing, 12) * 0.02, 0, 0.3)
		inRing += 1
	end
end

-- A hex just changed state while you watch: hexes that appear pop in (rippling out from
-- the hex you bought), "?" hexes that open flip to their new face and start flashing.
local function animateChange(def: UpgradeDef, before: string, now: string)
	local origin = lastBought
	local wave = if origin and origin.Tree == def.Tree then hexDistance(def.Hex, origin.Hex) else 1
	local delay = 0.1 + (wave - 1) * 0.12
	if before == "Hidden" then
		growIn(def.Id, delay, 0)
	elseif now == "Open" or now == "Rebirth" then
		growIn(def.Id, delay, 0.55, 0.38)
		if not Ui.reducedMotion() then
			task.delay(delay, shockwave, def.Id, FLASH)
		end
	end
end

local function renderBoard(silent: boolean?)
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
		-- What changed since this hex was last drawn.
		local before = lastState[def.Id]
		if before and before ~= state then
			local opened = state == "Open" and (before == "Hidden" or before == "Mystery" or before == "Rebirth")
			if opened then
				fresh[def.Id] = true
			elseif state ~= "Open" then
				fresh[def.Id] = nil
			end
			if not silent and state ~= "Hidden" and (before == "Hidden" or before == "Mystery") then
				animateChange(def, before, state)
			end
		end
		lastState[def.Id] = state
		node.Visible = state ~= "Hidden"
		local labOpen = isLab and level > 0
		local color = if labOpen then TILE.Lab else TILE[state] or TILE.Mystery
		baseColor[def.Id] = color
		local tile = node:FindFirstChild("Tile") :: ImageLabel
		tile.Visible = useImage;
		(node:FindFirstChild("Outline") :: Frame).Visible = not useImage;
		(node:FindFirstChild("Fill") :: Frame).Visible = not useImage

		local known = state == "Open" or state == "Owned" or state == "Max" or state == "Rebirth"
		local icon = node:FindFirstChild("Icon") :: ImageLabel
		local nameLabel = node:FindFirstChild("Name") :: TextLabel
		local priceRow = node:FindFirstChild("Price") :: Frame
		local priceLabel = priceRow:FindFirstChild("Label") :: TextLabel
		local coin = priceRow:FindFirstChild("Coin") :: ImageLabel
		local levelLabel = node:FindFirstChild("Level") :: TextLabel
		icon.Visible = known and state ~= "Rebirth"
		nameLabel.Visible = known
		priceRow.Visible = known and not (state == "Max" and not isLab)
		-- Owned hexes show their level as a gold number in the corner (Slime RNG).
		levelLabel.Visible = known and not isLab and level > 0 and def.MaxLevel > 1
		levelLabel.Text = tostring(level)
		nameLabel.Text = Upgrades.name(def, level) -- evolving hexes change name
		local wait = waitsForRebirth(def, data);
		(node:FindFirstChild("Lock") :: ImageLabel).Visible = state == "Rebirth"
		(node:FindFirstChild("Question") :: TextLabel).Visible = state == "Mystery"

		coin.Visible = false
		priceLabel.TextColor3 = WHITE
		if isLab and level > 0 then
			priceLabel.Text = "Open"
		elseif state == "Max" then
			priceLabel.Text = "MAX"
		elseif state == "Rebirth" then
			priceLabel.Text = `Rebirth {def.RequiredRebirths}`
		elseif wait then
			priceLabel.Text = `Rebirth {wait}`
		else
			local cost = price(def, data)
			if cost == 0 then
				priceLabel.Text = "FREE"
				priceLabel.TextColor3 = Color3.fromRGB(61, 220, 90)
			else
				coin.Visible = true
				priceLabel.Text = Format.big(cost)
				priceLabel.TextColor3 = if BigNum.gte(data.Cash, cost) then WHITE else RED
			end
		end
		-- Only the selected hex glows (Dev: don't highlight what you can buy).
		local glow = node:FindFirstChild("Glow") :: Frame
		local isSelected = selected == def.Id and state ~= "Hidden"
		glowMode[def.Id] = if isSelected then "select" else nil
		glow.Visible = isSelected
		setHex(glow, WHITE)
		if not fresh[def.Id] then
			tile.ImageColor3 = color
			setHex(node:FindFirstChild("Fill") :: Frame, color)
		end
		-- An open lab shows how many hexes inside it you can afford.
		local count = 0
		if labOpen and def.Opens then
			for _, inner in Upgrades.List do
				if inner.Tree == def.Opens and canBuy(inner, data, states[inner.Id]) then
					count += 1
				end
			end
		end
		Ui.setBadge(node:FindFirstChild("Badge") :: GuiObject?, if count > 0 then count else nil)
	end
	local back = backHexes[current]
	if back then
		(back:FindFirstChild("Tile") :: ImageLabel).Visible = useImage;
		(back:FindFirstChild("Outline") :: Frame).Visible = not useImage;
		(back:FindFirstChild("Fill") :: Frame).Visible = not useImage
	end
	refreshTip()
end

-- Looking at a hex (hover, tap, controller) stops its NEW! flash.
local function seen(id: string?)
	if id and fresh[id] then
		fresh[id] = nil
		local node = nodes[id]
		local color = baseColor[id]
		if node and color then
			local tileImage = node:FindFirstChild("Tile") :: ImageLabel
			tileImage.ImageColor3 = color
			setHex(node:FindFirstChild("Fill") :: Frame, color)
		end
	end
end

-- Every frame: newly opened hexes flash, hexes you can afford breathe their green glow.
local function animateBoard()
	local t = os.clock()
	local still = Ui.reducedMotion()
	local breathe = if still then 0.15 else 0.15 + 0.4 * (math.sin(t * 4) + 1) / 2
	local flash = if still then 0.35 else 0.55 * (math.sin(t * 7) + 1) / 2
	for _, def in Upgrades.List do
		if def.Tree ~= current then
			continue
		end
		local node = nodes[def.Id]
		if not node.Visible then
			continue
		end
		local glow = node:FindFirstChild("Glow") :: Frame
		if fresh[def.Id] then
			local color = (baseColor[def.Id] or TILE.Open):Lerp(FLASH, flash)
			local tileImage = node:FindFirstChild("Tile") :: ImageLabel
			tileImage.ImageColor3 = color
			setHex(node:FindFirstChild("Fill") :: Frame, color)
			if glowMode[def.Id] ~= "select" then
				glow.Visible = true
				setHex(glow, FLASH)
			end
		end
		if glow.Visible then
			local mode = glowMode[def.Id]
			local alpha = if mode == "select" then 0 elseif fresh[def.Id] then 1 - flash else breathe
			for _, bar in glow:GetChildren() do
				if bar:IsA("Frame") then
					bar.BackgroundTransparency = alpha
				end
			end
		end
	end
end

-- Bought: the hex squashes and springs back with a ring of light.
local function popNode(id: string)
	if Ui.reducedMotion() then
		return
	end
	growIn(id, 0, 0.82, 0.35)
	shockwave(id)
end

-- Shows one board (Main or a lab) and frames it on screen.
local function showBoard(treeId: string, flyIn: boolean?)
	local keepZoom = gui.Enabled and boards[current] ~= nil and boards[current].Visible
	if zoom and boards[current] then
		views[current] = { zoom = zoom.Scale, pan = pan }
	end
	current = treeId
	for id, board in boards do
		board.Visible = id == treeId
	end
	title.Text = if treeId == "Main" then "Upgrades!" else `{Upgrades.Trees[treeId].Name}!`
	hovered = nil
	selected = nil
	-- Controller: start on the board's first hex.
	if Ui.gamepad() then
		local first = nodes[Upgrades.Trees[treeId].Root]
		task.defer(function()
			if first and first.Visible and gui.Enabled then
				GuiService.SelectedObject = first
			end
		end)
	end
	-- The zoom stays as you set it when going into a lab and back (Dev, 2026-10-31);
	-- each board keeps its own pan.
	local saved = views[treeId]
	local target = if keepZoom
		then zoom.Scale
		elseif saved then math.clamp(saved.zoom, ZOOM_MIN, ZOOM_MAX)
		else fitZoom()
	zoom.Scale = target
	pan = if saved then saved.pan else Vector2.zero
	clampPan()
	-- Silent: hexes that opened while you were away just start flashing; the bloom below
	-- brings every hex in.
	renderBoard(true)
	bloom(treeId)
	local _ = flyIn
end

-- Out of a lab: back to the main board, looking at the lab you came from.
local function goBack()
	local lab = Upgrades.Trees[current].Portal
	Ui.sound("Click")
	showBoard("Main")
	if lab then
		local def = Upgrades.ById[lab]
		pan = -hexToPixel(def.Hex.q, def.Hex.r) * zoom.Scale
		clampPan()
	end
end

local function flash(text: string)
	flashText = text
	flashUntil = os.clock() + 2.5
end

-- First tap selects a hex (tooltip), the next tap on it buys (phones only, see twoTaps).
-- Owned labs open at once.
local function onNodeTapped(def: UpgradeDef)
	local data = State.data
	if not data then
		return
	end
	local state = computeStates(data)[def.Id]
	local level = data.Upgrades[def.Id] or 0
	if def.Opens and level > 0 then
		Ui.sound("Open")
		showBoard(def.Opens, true)
		return
	end
	seen(def.Id)
	if selected ~= def.Id then
		selected = def.Id
		flashText = nil
		if twoTaps() or state == "Mystery" then
			Ui.sound("Click")
			renderBoard()
			return
		end
	end
	if state == "Mystery" or state == "Rebirth" or state == "Max" then
		Ui.sound("Error")
		return
	end
	local ok, message = Net.func("BuyUpgrade"):InvokeServer(def.Id, 1)
	if ok then
		Ui.sound("Coin")
		lastBought = def
		popNode(def.Id)
		flashText = nil
	else
		Ui.sound("Error")
		flash(if message and message ~= "" then message else "Can't buy that")
	end
	renderBoard()
end

-- Builds every board and hex once from Config/Upgrades.
local function build()
	local template = canvas:FindFirstChild("NodeTemplate") :: TextButton
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
	-- Each lab's centre: a red hex with the lab's name and "Back".
	for treeId, tree in Upgrades.Trees do
		if treeId == "Main" then
			continue
		end
		local back = template:Clone()
		back.Name = "Back"
		back.Position = UDim2.fromOffset(0, 0)
		back.Visible = true
		if not back:FindFirstChild("Pop") then
			local scale = Instance.new("UIScale")
			scale.Name = "Pop"
			scale.Parent = back
		end
		for _, name in { "Icon", "Level", "Lock", "Question", "Badge", "Glow" } do
			local child = back:FindFirstChild(name) :: GuiObject?
			if child then
				child.Visible = false
			end
		end
		(back:FindFirstChild("Tile") :: ImageLabel).ImageColor3 = TILE.Back
		setHex(back:FindFirstChild("Fill") :: Frame, TILE.Back)
		local nameLabel = back:FindFirstChild("Name") :: TextLabel
		nameLabel.Text = tree.Name
		nameLabel.Position = UDim2.new(0.5, 0, 0, 40)
		local priceRow = back:FindFirstChild("Price") :: Frame
		priceRow.Position = UDim2.new(0.5, 0, 0, 64);
		(priceRow:FindFirstChild("Coin") :: GuiObject).Visible = false
		local label = priceRow:FindFirstChild("Label") :: TextLabel
		label.Text = "Back"
		label.TextColor3 = Color3.fromRGB(255, 205, 205)
		back.Parent = boards[treeId]
		backHexes[treeId] = back
		back.Activated:Connect(function()
			if dragged and os.clock() - draggedAt < 0.25 then
				return
			end
			goBack()
		end)
	end
	for i, def in Upgrades.List do
		local h = hexOf(def)
		local p = hexToPixel(h.q, h.r)
		local e = extents[def.Tree]
		extents[def.Tree] = Vector2.new(math.max(e.X, math.abs(p.X) + 80), math.max(e.Y, math.abs(p.Y) + 70))
		local node = template:Clone()
		node.Name = def.Id
		node.Position = UDim2.fromOffset(p.X, p.Y)
		node.LayoutOrder = i
		node.Visible = false
		-- A hex's own sticker icon, or its stat's icon until that one is uploaded.
		local image = AssetLibrary.image(def.Icon)
		if image == "" then
			image = AssetLibrary.image(Upgrades.Stats[def.Stat].Icon)
		end
		(node:FindFirstChild("Icon") :: ImageLabel).Image = image
		if not node:FindFirstChild("Pop") then
			-- Older UI without the Pop scale (LiveSync before the regenerate).
			local scale = Instance.new("UIScale")
			scale.Name = "Pop"
			scale.Parent = node
		end
		(node:FindFirstChild("Name") :: TextLabel).Text = def.Name
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
			seen(def.Id)
			refreshTip()
		end)
		node.MouseLeave:Connect(function()
			if hovered == def.Id then
				hovered = nil
				refreshTip()
			end
		end)
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

function UpgradeController:IsOpen(): boolean
	return Ui.isOpen(gui)
end

-- The hex button for a node (for tutorial spotlights). Nil until built.
function UpgradeController:GetNode(id: string): TextButton?
	return nodes[id]
end

-- Every other screen (HUD, panels) and the Roblox chat / player list hide while the tree
-- is open, and come back exactly as they were.
local hiddenGuis: { ScreenGui } = {}
local hiddenCore: { Enum.CoreGuiType } = {}
local function hideOtherUi(hide: boolean)
	if hide then
		if #hiddenGuis > 0 then
			return
		end
		for _, other in Players.LocalPlayer:WaitForChild("PlayerGui"):GetChildren() do
			if other:IsA("ScreenGui") and other ~= gui and other.Enabled then
				other.Enabled = false
				table.insert(hiddenGuis, other)
			end
		end
		for _, kind in { Enum.CoreGuiType.Chat, Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.EmotesMenu } do
			local ok, on = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, kind)
			if ok and on then
				pcall(StarterGui.SetCoreGuiEnabled, StarterGui, kind, false)
				table.insert(hiddenCore, kind)
			end
		end
	else
		for _, other in hiddenGuis do
			if other.Parent then
				other.Enabled = true
			end
		end
		for _, kind in hiddenCore do
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, kind, true)
		end
		table.clear(hiddenGuis)
		table.clear(hiddenCore)
	end
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

function UpgradeController:Init(_controllers)
	gui = Ui.screen("Upgrades")
	canvas = Ui.find(gui, "Board.Scaler.Canvas")
	zoom = Ui.find(canvas, "Zoom")
	title = Ui.find(gui, "Top.Title")
	tip = Ui.find(gui, "Tooltip")
	-- Only CLOSE stays at the bottom (Dev, 2026-10-31); a lab's centre hex is its Back.
	-- LiveSync never deletes removed UI, so clear the old buttons and the NEW! tag here.
	local bottom = Ui.find(gui, "Bottom")
	for _, name in { "Back", "ZoomIn", "ZoomOut" } do
		local old = bottom:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local oldTag = Ui.find(canvas, "NodeTemplate"):FindFirstChild("New")
	if oldTag then
		oldTag:Destroy()
	end
end

function UpgradeController:Start()
	build()
	setupDragging()

	Ui.button(Ui.find(gui, "Bottom.Close"), function()
		Ui.close("Upgrades")
	end)
	Ui.button(Ui.find(gui, "Board.Backdrop"), function()
		if dragged and os.clock() - draggedAt < 0.25 then
			return
		end
		selected = nil
		hovered = nil
		renderBoard()
	end)
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		hideOtherUi(gui.Enabled)
		if not gui.Enabled then
			selected = nil
			hovered = nil
		end
	end)
	-- Quest Master's free Sweep Power job (was the tutorial's Upgrade step): a line under
	-- the title and the Sweep Power hex pulses.
	local tutorialHint = Ui.find(gui, "Top.Hint") :: TextLabel
	local wasTeaching = false
	RunService.RenderStepped:Connect(function()
		if not gui.Enabled then
			return
		end
		if tip.Visible then
			placeTip()
		end
		animateBoard()
		local data = State.data
		local job = data and data.Quests and data.Quests.Job
		local teaching = job ~= nil
			and job.Kind == "Power"
			and not job.Done
			and (data.Upgrades.Power or 0) < 1
			and current == "Main"
		tutorialHint.Visible = teaching
		local root = nodes[Upgrades.Root]
		if teaching and root then
			local touch = UserInputService:GetLastInputType() == Enum.UserInputType.Touch
			local pad = Ui.gamepad()
			tutorialHint.Text = if pad
				then "Press A on the middle hex to buy it!"
				elseif touch and selected == Upgrades.Root then "Tap it again to buy!"
				elseif touch then "Double-tap the middle hex to buy it!"
				else "Click the middle hex to buy it!"
			local k = 1 + math.abs(math.sin(os.clock() * 4)) * 0.08
			root.Size = UDim2.fromOffset(nodeSize.X.Offset * k, nodeSize.Y.Offset * k);
			(root:FindFirstChild("Glow") :: Frame).Visible = true
		elseif root and wasTeaching then
			root.Size = nodeSize
		end
		wasTeaching = teaching
	end)
	-- Controller: the board follows the selected hex and shows its tooltip; LB / RB zoom.
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		if not gui.Enabled then
			return
		end
		local object = GuiService.SelectedObject
		local id = object and nodes[object.Name] == object and object.Name or nil
		if id then
			local h = hexOf(Upgrades.ById[id])
			hovered = id
			seen(id)
			pan = -hexToPixel(h.q, h.r) * zoom.Scale
			clampPan()
			refreshTip()
		elseif hovered and not UserInputService.MouseEnabled then
			hovered = nil
			refreshTip()
		end
	end)
	UserInputService.InputBegan:Connect(function(input)
		if not gui.Enabled then
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonR1 then
			setZoom(zoom.Scale + 0.15)
		elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
			setZoom(zoom.Scale - 0.15)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("Opens") == "Upgrades" then
			UpgradeController:Open()
		end
	end)
	task.spawn(bobHologram)
	-- Use the image tiles only if they load (no permission or moderation = frame hexagons).
	task.spawn(function()
		local tile = Ui.find(canvas, "NodeTemplate.Tile") :: ImageLabel
		if tile.Image == "" then
			return
		end
		ContentProvider:PreloadAsync({ tile.Image }, function(_id, status)
			if status == Enum.AssetFetchStatus.Success then
				useImage = true
				renderBoard()
			end
		end)
	end)
	task.spawn(function()
		railBadge = Ui.find(Ui.screen("Hud"), "UpgradeMenu.Items.TreeButton"):FindFirstChild("Badge") :: GuiObject?
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
			table.insert(parts, `{level}:{BigNum.gte(data.Cash, price(def, data))}`)
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
