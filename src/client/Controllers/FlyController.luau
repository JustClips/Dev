--!strict
-- Flying rewards (Dev, 2026-10-31, from Pet Sim style references): what you get pops up as
-- icons at random spots on the screen, each showing its share ("+$1.2K"), and then flies
-- into the HUD spot it belongs to:
--   cash            -> the coin on the wallet, with a "+$X" over the wallet that counts up
--                      as the coins land
--   swept leaves    -> the bag bar on the wallet, with its own "+$X" next to the bar (this
--                      replaced the "+$12" / "TRASH x5" / "LUCKY x5" numbers over your head)
--   items and eggs  -> the Bag button on the hotbar
-- The target punches each time one lands.
--
--   FlyController:Cash(amount, count?)             coins worth `amount` in total
--   FlyController:CoinsFromWorld(pos, count?, value?) coins from a spot in the world
--   FlyController:Leaves(value, special?)          a sweep's worth, batched
--   FlyController:ToBag(image, fromPx?, tint?)     one icon into the bag
--
-- New items and eggs are noticed here by comparing the bag between snapshots, so every
-- way of getting one (drops, rewards, codes, the wheel, the merchant) flies the same.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local BagItems = require(Client.BagItems)
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local BigNum = require(Shared.BigNum)
local Format = require(Shared.Format)
local Items = require(Shared.Config.Items)

local FlyController = {}

local MAX_LIVE = 45
local COIN_PX = 40
local ITEM_PX = 60
local HEAVY = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
local GOLD_TEXT = ColorSequence.new(Color3.fromRGB(255, 250, 200), Color3.fromRGB(255, 170, 20))

type Counter = {
	label: TextLabel,
	scale: UIScale,
	total: any, -- BigNum
	shown: any, -- BigNum
	last: number,
	place: () -> (),
}

type Flyer = {
	gui: ImageLabel,
	from: Vector2,
	target: () -> Vector2?,
	start: number,
	popTime: number,
	hold: number,
	flyTime: number,
	size: number,
	onLand: () -> (),
}

local hud: ScreenGui
local layer: Frame
local flyers: { Flyer } = {}
local wallet: GuiObject
local cashIcon: GuiObject
local bagSlot: GuiObject
local bagIcon: GuiObject
local bagPanel: GuiObject
local cashCounter: Counter
local leafCounter: Counter

local function centre(object: GuiObject): Vector2
	return object.AbsolutePosition + object.AbsoluteSize / 2 - layer.AbsolutePosition
end

local function shown(object: GuiObject): boolean
	local o: Instance? = object
	while o and o:IsA("GuiObject") do
		if not o.Visible then
			return false
		end
		o = o.Parent
	end
	return object.AbsoluteSize.X > 1
end

function FlyController.Layer(): Frame
	return layer
end

-- Screen (absolute) point -> this layer's px, for pops drawn in other ScreenGuis.
function FlyController.ToLayer(absolute: Vector2): Vector2
	return absolute - layer.AbsolutePosition
end

function FlyController.CashAbsolute(): Vector2
	return cashIcon.AbsolutePosition + cashIcon.AbsoluteSize / 2
end

local function bagTarget(): Vector2
	if shown(bagSlot) then
		return centre(bagSlot)
	end
	return centre(bagIcon)
end

function FlyController.BagAbsolute(): Vector2
	return bagTarget() + layer.AbsolutePosition
end

local function cashTarget(): Vector2
	return centre(cashIcon)
end

local function leafTarget(): Vector2
	return centre(bagIcon)
end

-- A random spot in the middle of the screen (away from the edges and the HUD).
local function randomPoint(): Vector2
	local size = layer.AbsoluteSize
	return Vector2.new(size.X * (0.22 + math.random() * 0.56), size.Y * (0.26 + math.random() * 0.42))
end
FlyController.RandomPoint = randomPoint

local punches: { [GuiObject]: UIScale } = {}
local function punch(object: GuiObject)
	if Ui.reducedMotion() then
		return
	end
	local scale = punches[object]
	if not scale then
		local s = Instance.new("UIScale")
		s.Name = "FlyPunch"
		s.Parent = object
		punches[object] = s
		scale = s
	end
	local s = scale :: UIScale
	s.Scale = 1.3
	TweenService:Create(s, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function stroke(parent: Instance, thickness: number)
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	st.Thickness = thickness
	st.Color = Color3.fromRGB(23, 25, 30)
	st.Parent = parent
end

-- Hold: rewards that arrive while something plays out (the Lucky Wheel spinning) wait and
-- fly once it's done (Dev, 2026-10-31: the prize flew before the wheel stopped).
local heldUntil = 0
local held: { any } = {}

-- An icon that pops up at `from`, waits a moment, then flies to `target`. `text` shows
-- under it (its share, "+$1.2K").
local function launch(opts: {
	image: string,
	from: Vector2,
	target: () -> Vector2?,
	size: number,
	delay: number?,
	hold: number?,
	tint: Color3?,
	text: string?,
	textColor: Color3?,
	onLand: () -> (),
})
	if heldUntil > os.clock() then
		-- Waiting for something to finish (the wheel still spinning): fly afterwards.
		table.insert(held, opts)
		return
	end
	if #flyers >= MAX_LIVE then
		opts.onLand()
		return
	end
	local gui = Instance.new("ImageLabel")
	gui.Name = "Flyer"
	gui.BackgroundTransparency = 1
	gui.Image = opts.image
	gui.ImageColor3 = opts.tint or Color3.new(1, 1, 1)
	gui.ScaleType = Enum.ScaleType.Fit
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Size = UDim2.fromOffset(0, 0)
	gui.Position = UDim2.fromOffset(opts.from.X, opts.from.Y)
	gui.ZIndex = 60
	if opts.text then
		local label = Instance.new("TextLabel")
		label.Name = "Value"
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0.9, 0)
		label.Size = UDim2.new(2.6, 0, 0.62, 0)
		label.FontFace = HEAVY
		label.TextScaled = true
		label.Text = opts.text
		label.TextColor3 = opts.textColor or Color3.fromRGB(255, 225, 90)
		label.ZIndex = 61
		stroke(label, 2.5)
		label.Parent = gui
	end
	gui.Parent = layer
	table.insert(flyers, {
		gui = gui,
		from = opts.from,
		target = opts.target,
		start = os.clock() + (opts.delay or 0),
		popTime = 0.22,
		hold = opts.hold or (0.25 + math.random() * 0.3),
		flyTime = 0.45 + math.random() * 0.12,
		size = opts.size,
		onLand = opts.onLand,
	})
end

local function release()
	heldUntil = 0
	local list = held
	held = {}
	for i, opts in list do
		opts.delay = (i - 1) * 0.05
		opts.from = randomPoint()
		launch(opts)
	end
end

-- Holds every reward flight for up to `seconds` (a safety cap); Release() lets them go.
function FlyController:Hold(seconds: number)
	heldUntil = os.clock() + seconds
	task.delay(seconds, function()
		if heldUntil > 0 and os.clock() >= heldUntil then
			release()
		end
	end)
end

function FlyController:Release()
	release()
end

------------------------------------------------------------------------ counters

local function makeCounter(name: string, place: (TextLabel) -> ()): Counter
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = HEAVY
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Visible = false
	label.ZIndex = 59
	stroke(label, 3)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = GOLD_TEXT
	gradient.Parent = label
	local scale = Instance.new("UIScale")
	scale.Parent = label
	label.Parent = layer
	local counter: Counter = {
		label = label,
		scale = scale,
		total = BigNum.zero(),
		shown = BigNum.zero(),
		last = -math.huge,
		place = function()
			place(label)
		end,
	}
	return counter
end

local COUNTER_HOLD = 1.6

local function addTo(counter: Counter, value: any)
	local now = os.clock()
	if now - counter.last > COUNTER_HOLD + 0.4 then
		counter.total, counter.shown = BigNum.zero(), BigNum.zero()
	end
	counter.last = now
	counter.total = BigNum.add(counter.total, value)
	counter.label.Visible = true
	counter.label.TextTransparency = 0
	if not Ui.reducedMotion() then
		counter.scale.Scale = 1.25
		TweenService:Create(counter.scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local function stepCounter(counter: Counter, now: number, dt: number)
	local label = counter.label
	if not label.Visible then
		return
	end
	counter.place()
	-- Counts up quickly toward what has landed.
	if BigNum.lt(counter.shown, counter.total) then
		local gap = BigNum.sub(counter.total, counter.shown)
		local step = BigNum.mul(gap, math.min(1, dt * 9))
		counter.shown = BigNum.add(counter.shown, step)
		if BigNum.lt(BigNum.sub(counter.total, counter.shown), BigNum.mul(counter.total, 0.002)) then
			counter.shown = counter.total
		end
	end
	label.Text = "+" .. Format.cash(BigNum.floor(counter.shown))
	local idle = now - counter.last
	if idle > COUNTER_HOLD then
		local fade = math.clamp((idle - COUNTER_HOLD) / 0.4, 0, 1)
		label.TextTransparency = fade
		if fade >= 1 then
			label.Visible = false
		end
	end
end

------------------------------------------------------------------------ coins

local lastCoinSound = 0
local function coinSound()
	local now = os.clock()
	if now - lastCoinSound > 0.07 then
		lastCoinSound = now
		Ui.sound("Coin", 1.25 + math.random() * 0.2)
	end
end

-- Cash worth `amount`: `count` coins at random spots, each showing its share, into the
-- wallet. The "+$X" over the wallet counts up as they land.
function FlyController:Cash(amount: any, count: number?)
	local total = BigNum.from(amount)
	if not BigNum.gte(total, 1) then
		return
	end
	local n = math.clamp(count or 6, 1, 12)
	local share = BigNum.div(total, n)
	local s = Ui.scale()
	for i = 1, n do
		launch({
			image = AssetLibrary.image("Icon_Cash"),
			from = randomPoint(),
			target = cashTarget,
			size = COIN_PX * s,
			delay = (i - 1) * 0.05,
			text = "+" .. Format.cash(share),
			onLand = function()
				punch(cashIcon)
				coinSound()
				addTo(cashCounter, share)
			end,
		})
	end
end

local function worldToLayer(pos: Vector3): Vector2?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local point, onScreen = camera:WorldToScreenPoint(pos)
	if not onScreen then
		return nil
	end
	-- WorldToScreenPoint is in the same space as GuiObject.AbsolutePosition.
	return Vector2.new(point.X, point.Y) - layer.AbsolutePosition
end

-- Coins from a spot in the world (coin pickups, coin pouches). Values add up into the
-- wallet counter. Throttled: a pile of coins sends a steady stream, the values still count.
local lastWorld = 0
local pendingWorld: any = BigNum.zero()
function FlyController:CoinsFromWorld(pos: Vector3, count: number?, value: any?)
	local now = os.clock()
	if value then
		pendingWorld = BigNum.add(pendingWorld, value)
	end
	if (count or 1) <= 1 and now - lastWorld < 0.06 then
		return
	end
	lastWorld = now
	local carried = pendingWorld
	pendingWorld = BigNum.zero()
	-- Pops up at a random spot like every other reward (Dev, 2026-10-31: selling should
	-- look the same), close to where it was picked up when that's on screen.
	local near = worldToLayer(pos)
	local from = if near then near:Lerp(randomPoint(), 0.6) else randomPoint()
	local s = Ui.scale()
	local n = math.clamp(count or 1, 1, 10)
	local share = BigNum.div(carried, n)
	local hasValue = BigNum.gte(share, 1)
	for i = 1, n do
		launch({
			image = AssetLibrary.image("Icon_Cash"),
			from = from + Vector2.new(math.random(-40, 40), math.random(-40, 40)) * s,
			target = cashTarget,
			size = COIN_PX * s * 0.9,
			delay = (i - 1) * 0.04,
			text = if hasValue then "+" .. Format.cash(share) else nil,
			onLand = function()
				punch(cashIcon)
				coinSound()
				if hasValue then
					addTo(cashCounter, share)
				end
			end,
		})
	end
end

------------------------------------------------------------------------ leaves

-- Sweeping fills the bag with cash worth of leaves. Each sweep's value is batched into one
-- coin every so often (a coin per sweep would flood the screen). A trash / lucky / golden
-- hit sends its own bigger coin.
local SPECIAL_COLORS: { [string]: Color3 } = {
	Trash = Color3.fromRGB(110, 210, 255),
	Lucky = Color3.fromRGB(124, 255, 140),
	Golden = Color3.fromRGB(255, 205, 40),
}
local leafPending: any = BigNum.zero()
local leafLast = 0

local function sendLeaves(value: any, special: string?)
	local s = Ui.scale()
	launch({
		image = AssetLibrary.image("Icon_Cash"),
		from = randomPoint(),
		target = leafTarget,
		size = COIN_PX * s * (if special then 1.35 else 0.9),
		hold = 0.2,
		text = "+" .. Format.cash(value),
		textColor = if special then SPECIAL_COLORS[special] else nil,
		onLand = function()
			punch(bagIcon)
			addTo(leafCounter, value)
		end,
	})
end

function FlyController:Leaves(value: any, special: string?)
	local v = BigNum.from(value)
	if not BigNum.gte(v, 1) then
		return
	end
	if special then
		sendLeaves(v, special)
		return
	end
	leafPending = BigNum.add(leafPending, v)
end

------------------------------------------------------------------------ bag

-- One item into the bag, from a point (Hud px) or a random spot.
function FlyController:ToBag(image: string, from: Vector2?, tint: Color3?)
	local s = Ui.scale()
	launch({
		image = image,
		from = from or randomPoint(),
		target = bagTarget,
		size = ITEM_PX * s,
		tint = tint,
		onLand = function()
			punch(if shown(bagSlot) then bagSlot else bagIcon)
			Ui.sound("Pop", 1.3)
		end,
	})
end

------------------------------------------------------------------------ frame step

local lastStep = os.clock()
local function step()
	local now = os.clock()
	local dt = math.min(now - lastStep, 0.1)
	lastStep = now
	if BigNum.gte(leafPending, 1) and now - leafLast > 0.14 then
		leafLast = now
		local v = leafPending
		leafPending = BigNum.zero()
		sendLeaves(v, nil)
	end
	for i = #flyers, 1, -1 do
		local f = flyers[i]
		local t = now - f.start
		if t < 0 then
			continue
		end
		local gui = f.gui
		if t < f.popTime then
			-- Pops in with a little overshoot.
			local k = t / f.popTime
			local size = f.size * (if k < 0.7 then k / 0.7 * 1.25 else 1.25 - (k - 0.7) / 0.3 * 0.25)
			gui.Size = UDim2.fromOffset(size, size)
			continue
		end
		if t < f.popTime + f.hold then
			-- Bobs where it popped up.
			local b = math.sin((t - f.popTime) * 12) * 3
			gui.Position = UDim2.fromOffset(f.from.X, f.from.Y + b)
			gui.Size = UDim2.fromOffset(f.size, f.size)
			continue
		end
		local k = math.clamp((t - f.popTime - f.hold) / f.flyTime, 0, 1)
		local goal = f.target() or f.from
		-- Curves on the way: starts slow, speeds into the target, shrinks a little.
		local ease = k * k
		local bend = Vector2.new(0, -math.sin(k * math.pi) * 50 * Ui.scale())
		local p = f.from:Lerp(goal, ease) + bend * (1 - ease)
		local size = f.size * (1 - 0.4 * ease)
		gui.Position = UDim2.fromOffset(p.X, p.Y)
		gui.Size = UDim2.fromOffset(size, size)
		gui.Rotation = math.sin(k * math.pi) * 20
		if k >= 1 then
			gui:Destroy()
			table.remove(flyers, i)
			f.onLand()
		end
	end
	stepCounter(cashCounter, now, dt)
	stepCounter(leafCounter, now, dt)
end

------------------------------------------------------------------------ bag watching

-- New items (counts that went up) and new eggs fly into the bag.
local lastItems: { [string]: number }? = nil
local lastEggs: { [string]: boolean }? = nil
local watchFrom = math.huge

local function watchBag(data)
	local items = data.Items or {}
	local eggs = data.Eggs or {}
	local prevItems, prevEggs = lastItems, lastEggs
	local itemsNow: { [string]: number } = {}
	for id, n in items do
		itemsNow[id] = n
	end
	local eggsNow: { [string]: boolean } = {}
	for uid in eggs do
		eggsNow[uid] = true
	end
	lastItems, lastEggs = itemsNow, eggsNow
	if not prevItems or not prevEggs then
		-- First snapshot: what you already had doesn't fly. The full bag can arrive a moment
		-- later (State refetches it), so wait a few seconds before watching.
		watchFrom = os.clock() + 6
		return
	end
	if os.clock() < watchFrom then
		return
	end
	local sent = 0
	for id, n in itemsNow do
		local gained = n - (prevItems[id] or 0)
		local def = Items.ById[id]
		if gained > 0 and def then
			for _ = 1, math.min(gained, 3) do
				if sent < 6 then
					sent += 1
					task.delay(sent * 0.08, function()
						FlyController:ToBag(AssetLibrary.image(def.Icon))
					end)
				end
			end
		end
	end
	for uid in eggsNow do
		if not prevEggs[uid] and sent < 6 then
			sent += 1
			local egg = eggs[uid]
			task.delay(sent * 0.08, function()
				FlyController:ToBag(AssetLibrary.image("Icon_Egg"), nil, BagItems.rarityColor(egg and egg.Rarity))
			end)
		end
	end
end

function FlyController:Init()
	hud = Ui.screen("Hud")
	wallet = Ui.find(hud, "Wallet")
	cashIcon = Ui.find(hud, "Wallet.CashPanel.Icon")
	bagSlot = Ui.find(hud, "Hotbar.BagSlot")
	bagPanel = Ui.find(hud, "Wallet.BackpackPanel")
	bagIcon = Ui.find(hud, "Wallet.BackpackPanel.Icon")
	-- Its own ScreenGui above every window, so prizes won in a window (the wheel, daily
	-- rewards) fly over it. Same insets as the HUD, so positions line up.
	local screen = Instance.new("ScreenGui")
	screen.Name = "Fly"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = hud.IgnoreGuiInset
	screen.ScreenInsets = hud.ScreenInsets
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = 40
	screen.Parent = hud.Parent
	local f = Instance.new("Frame")
	f.Name = "FlyLayer"
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = 60
	f.Parent = screen
	layer = f
	-- "+$X" just over the wallet (Dev: "above the cash"), and one right of the bag bar.
	cashCounter = makeCounter("CashGain", function(label)
		local s = Ui.scale()
		local at = wallet.AbsolutePosition - layer.AbsolutePosition
		label.AnchorPoint = Vector2.new(0, 1)
		label.Size = UDim2.fromOffset(math.floor(240 * s), math.floor(36 * s))
		label.Position = UDim2.fromOffset(at.X + 4, at.Y - 4)
	end)
	leafCounter = makeCounter("LeafGain", function(label)
		local s = Ui.scale()
		local at = bagPanel.AbsolutePosition - layer.AbsolutePosition
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.Size = UDim2.fromOffset(math.floor(170 * s), math.floor(28 * s))
		label.Position = UDim2.fromOffset(at.X + wallet.AbsoluteSize.X + 10, at.Y + bagPanel.AbsoluteSize.Y / 2)
	end)
end

function FlyController:Start()
	RunService.RenderStepped:Connect(step)
	State.observe(watchBag)
end

return FlyController
