--!strict
-- Flying rewards (Dev, 2026-10-31, from a Pet Sim style reference): what you get pops out as
-- icons that fly into the HUD spot it belongs to. Cash turns into coins that zip into the
-- coin on the wallet; items and eggs fly into the Bag button on the hotbar. The target
-- icon punches each time one lands.
--
--   FlyController:Coins(fromPx, count)        coins from a point on the screen (Hud px)
--   FlyController:CoinsFromWorld(pos, count)  coins from a spot in the world
--   FlyController:ToBag(image, fromPx?, tint?) one icon into the bag
--   FlyController.CashTarget()                where coins land (Hud px), for other pops
--
-- New items and eggs are noticed here by comparing the bag between snapshots, so every
-- way of getting one (drops, rewards, codes, the wheel, the merchant) flies the same.
local Players = game:GetService("Players")
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
local Items = require(Shared.Config.Items)

local FlyController = {}

local MAX_LIVE = 40
local COIN_PX = 38
local ITEM_PX = 58

type Flyer = {
	gui: ImageLabel,
	from: Vector2,
	burst: Vector2, -- where it pops out to before flying
	target: () -> Vector2?,
	start: number,
	popTime: number,
	flyTime: number,
	size: number,
	onLand: () -> (),
}

local hud: ScreenGui
local layer: Frame
local flyers: { Flyer } = {}
local cashIcon: GuiObject
local bagSlot: GuiObject
local bagIcon: GuiObject

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

function FlyController.CashTarget(): Vector2
	return centre(cashIcon)
end

-- Screen (absolute) point <-> this layer's px, for pops drawn in other ScreenGuis.
function FlyController.ToLayer(absolute: Vector2): Vector2
	return absolute - layer.AbsolutePosition
end

function FlyController.CashAbsolute(): Vector2
	return cashIcon.AbsolutePosition + cashIcon.AbsoluteSize / 2
end

function FlyController.BagAbsolute(): Vector2
	local target = if shown(bagSlot) then bagSlot else bagIcon
	return target.AbsolutePosition + target.AbsoluteSize / 2
end

local function bagTarget(): Vector2
	if shown(bagSlot) then
		return centre(bagSlot)
	end
	return centre(bagIcon)
end

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

local function launch(image: string, from: Vector2, target: () -> Vector2?, size: number, spread: number, delay: number,
	tint: Color3?, onLand: () -> ())
	if #flyers >= MAX_LIVE then
		return
	end
	local gui = Instance.new("ImageLabel")
	gui.Name = "Flyer"
	gui.BackgroundTransparency = 1
	gui.Image = image
	gui.ImageColor3 = tint or Color3.new(1, 1, 1)
	gui.ScaleType = Enum.ScaleType.Fit
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Size = UDim2.fromOffset(0, 0)
	gui.Position = UDim2.fromOffset(from.X, from.Y)
	gui.ZIndex = 60
	gui.Parent = layer
	local angle = math.random() * math.pi * 2
	local r = spread * (0.4 + math.random() * 0.6)
	table.insert(flyers, {
		gui = gui,
		from = from,
		burst = from + Vector2.new(math.cos(angle) * r, math.sin(angle) * r - spread * 0.3),
		target = target,
		start = os.clock() + delay,
		popTime = 0.28,
		flyTime = 0.5 + math.random() * 0.12,
		size = size,
		onLand = onLand,
	})
end

local lastCoinSound = 0
local function coinLanded()
	punch(cashIcon)
	local now = os.clock()
	if now - lastCoinSound > 0.07 then
		lastCoinSound = now
		Ui.sound("Coin", 1.25 + math.random() * 0.2)
	end
end

-- Coins from a point (Hud px) into the wallet.
function FlyController:Coins(from: Vector2, count: number?)
	local n = math.clamp(count or 6, 1, 14)
	local s = Ui.scale()
	for i = 1, n do
		launch(AssetLibrary.image("Icon_Cash"), from, FlyController.CashTarget, COIN_PX * s, 70 * s, (i - 1) * 0.035, nil,
			coinLanded)
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

-- Coins from a spot in the world (coin pickups, coin pouches). Throttled: a pile of coins
-- sends a steady stream instead of a hundred icons.
local lastWorld = 0
function FlyController:CoinsFromWorld(pos: Vector3, count: number?)
	local now = os.clock()
	if (count or 1) <= 1 and now - lastWorld < 0.06 then
		return
	end
	lastWorld = now
	local from = worldToLayer(pos)
	if from then
		local s = Ui.scale()
		for i = 1, math.clamp(count or 1, 1, 10) do
			launch(AssetLibrary.image("Icon_Cash"), from, FlyController.CashTarget, COIN_PX * s, (if (count or 1) > 1 then 50 else 18) * s,
				(i - 1) * 0.04, nil, coinLanded)
		end
	end
end

local function playerPoint(): Vector2
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local at = worldToLayer(head.Position + Vector3.new(0, 1.5, 0))
		if at then
			return at
		end
	end
	return layer.AbsoluteSize / 2
end

-- One item into the bag, from a point (Hud px) or from above your head.
function FlyController:ToBag(image: string, from: Vector2?, tint: Color3?)
	local s = Ui.scale()
	launch(image, from or playerPoint(), bagTarget, ITEM_PX * s, 60 * s, 0, tint, function()
		punch(if shown(bagSlot) then bagSlot else bagIcon)
		Ui.sound("Pop", 1.3)
	end)
end

local function step()
	local now = os.clock()
	for i = #flyers, 1, -1 do
		local f = flyers[i]
		local t = now - f.start
		if t < 0 then
			continue
		end
		local gui = f.gui
		if t < f.popTime then
			-- Pops out of where it came from with a little overshoot.
			local k = t / f.popTime
			local ease = 1 - (1 - k) ^ 3
			local p = f.from:Lerp(f.burst, ease)
			local size = f.size * (if k < 0.7 then k / 0.7 * 1.25 else 1.25 - (k - 0.7) / 0.3 * 0.25)
			gui.Position = UDim2.fromOffset(p.X, p.Y)
			gui.Size = UDim2.fromOffset(size, size)
			continue
		end
		local k = math.clamp((t - f.popTime) / f.flyTime, 0, 1)
		local goal = f.target() or f.burst
		-- Curves on the way: starts slow, speeds into the target, shrinks a little.
		local ease = k * k
		local bend = Vector2.new(0, -math.sin(k * math.pi) * 60 * Ui.scale())
		local p = f.burst:Lerp(goal, ease) + bend * (1 - ease)
		local size = f.size * (1 - 0.35 * ease)
		gui.Position = UDim2.fromOffset(p.X, p.Y)
		gui.Size = UDim2.fromOffset(size, size)
		gui.Rotation = math.sin(k * math.pi) * 20
		if k >= 1 then
			gui:Destroy()
			table.remove(flyers, i)
			f.onLand()
		end
	end
end

-- Bag watching: new items (counts that went up) and new eggs fly into the bag.
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
	cashIcon = Ui.find(hud, "Wallet.CashPanel.Icon")
	bagSlot = Ui.find(hud, "Hotbar.BagSlot")
	bagIcon = Ui.find(hud, "Wallet.BackpackPanel.Icon")
	local f = Instance.new("Frame")
	f.Name = "FlyLayer"
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = 60
	f.Parent = hud
	layer = f
end

function FlyController:Start()
	RunService.RenderStepped:Connect(step)
	State.observe(watchBag)
end

return FlyController
