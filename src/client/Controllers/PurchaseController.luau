--!strict
-- Purchase celebration (Dev, 2026-10-31: "some kinda feedback after you bought smth so people
-- would instantly feel that"). The server fires Net "Purchased" (product or pass key, gift
-- info) right after a Robux buy is granted. A full-screen moment plays: the screen flashes,
-- rays spin up behind what you bought, it pops in with a bounce, a tilted sticker drops in
-- ("PURCHASED!", "GIFT FOR YOU!", "GIFT SENT!"), confetti bursts out and falls, then the
-- thing shrinks away toward your bag. Tap anywhere to skip. Several buys queue up.
-- Built in code (it's one moment, not a window). Reduced Motion: no spin, no confetti.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local ModelView = require(Client.ModelView)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Eggs = require(Shared.Config.Eggs)
local Items = require(Shared.Config.Items)
local LimitedEgg = require(Shared.Config.LimitedEgg)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Tools = require(Shared.Config.Tools)

local HEAVY = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
local INK = Color3.fromRGB(23, 25, 30)
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 200, 60)
local YELLOW = Color3.fromRGB(255, 227, 77)
local GREEN = Color3.fromRGB(76, 209, 55)
local PURPLE = Color3.fromRGB(178, 77, 255)
local CONFETTI = {
	Color3.fromRGB(255, 77, 94),
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(76, 209, 55),
	Color3.fromRGB(62, 155, 255),
	Color3.fromRGB(178, 77, 255),
	Color3.fromRGB(255, 126, 182),
}
local SHOW_SECONDS = 2.8

local PASS_ICONS: { [string]: string } = {
	FastWalk = "Icon_Speed",
	BigBag = "Icon_Backpack",
	Cash2x = "Icon_Cash",
	Carry3 = "Icon_Egg",
	AutoSweep = "Icon_Auto",
	Lucky = "Icon_LuckyClover",
	ExtraSlots = "Icon_Alien",
	SellAnywhere = "Icon_Sell",
	FasterHatch = "Icon_Timer",
	VIP = "Icon_Star",
}
local KIND_ICONS: { [string]: string } = {
	StarterPack = "Icon_Gift",
	ServerLuck = "Icon_Luck",
	MeteorShower = "Icon_Meteor",
	SkipHatch = "Icon_Timer",
	CashPack = "Icon_Cash",
	SkipRebirth = "Icon_Rebirth",
	DoubleOffline = "Icon_Cash",
	WheelSpins = "Icon_Spin",
	MerchantRestock = "Icon_Merchant",
	VehicleUnlock = "Icon_Vehicle",
	VehicleRental = "Icon_Vehicle",
}

local PurchaseController = {}

local C: any
local gui: ScreenGui
local queue: { { key: string, info: any } } = {}
local playing = false

type Look = { name: string, icon: string?, egg: string?, eggZone: string?, color: Color3, toBag: boolean }

-- What to show for a product or pass key: a picture (icon or 3D egg), its name and colour.
local function lookFor(key: string): Look
	local pass = Products.PassByKey[key]
	if pass then
		return { name = pass.Name, icon = PASS_ICONS[key] or "Icon_Star", color = PURPLE, toBag = false }
	end
	local def = Products.ProductByKey[key]
	if not def then
		return { name = "Thank you!", icon = "Icon_Star", color = GOLD, toBag = false }
	end
	local kind = def.Kind
	if kind == "EggPack" or kind == "LimitedEgg" then
		local rarity = if kind == "LimitedEgg" then LimitedEgg.EggRarity else def.Rarity or "Epic"
		local tier = Eggs.ByName[rarity]
		return { name = def.Name, egg = rarity, eggZone = if kind == "LimitedEgg" then LimitedEgg.Id else nil,
			color = if tier then tier.Color else GOLD, toBag = true }
	elseif kind == "ItemPack" then
		for _, item in Items.List do
			if item.Id == def.Item then
				return { name = def.Name, icon = item.Icon, color = Color3.fromRGB(46, 184, 160), toBag = true }
			end
		end
	elseif kind == "ToolSkip" and def.Tier then
		return { name = def.Name, icon = "Icon_Tool_" .. Tools.get(def.Tier).Id, color = GREEN, toBag = false }
	elseif kind == "GiftPass" and def.Pass then
		return { name = def.Name, icon = PASS_ICONS[def.Pass] or "Icon_Gift", color = PURPLE, toBag = false }
	elseif (kind == "VehicleUnlock" or kind == "VehicleRental") and def.Vehicle then
		local icon = "Icon_Car_" .. def.Vehicle
		return { name = def.Name, icon = if AssetLibrary.image(icon) ~= "" then icon else "Icon_Vehicle", color = GREEN, toBag = false }
	end
	local color = if kind == "CashPack" then GREEN elseif kind == "ServerLuck" then GREEN else GOLD
	return { name = def.Name, icon = KIND_ICONS[kind] or "Icon_Star", color = color, toBag = kind == "StarterPack" }
end

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local object = Instance.new(class)
	for k, v in props do
		(object :: any)[k] = v
	end
	object.Parent = parent
	return object
end

local function label(text: string, size: number, color: Color3, parent: Instance, z: number): TextLabel
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(600, size + 10),
		Text = text,
		TextColor3 = color,
		TextSize = size,
		FontFace = HEAVY,
		ZIndex = z,
	}, parent)
	make("UIStroke", { Color = INK, Thickness = math.max(2, size / 10), LineJoinMode = Enum.LineJoinMode.Round }, l)
	return l
end

local function tween(object: Instance, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- Confetti: pieces burst up from the middle, then tumble down with gravity.
local function confetti(layer: Frame, count: number)
	local pieces = {}
	for _ = 1, count do
		local w = math.random(8, 14)
		local piece = make("Frame", {
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(w, math.floor(w * 0.55)),
			Position = UDim2.fromScale(0.5, 0.45),
			BackgroundColor3 = CONFETTI[math.random(#CONFETTI)],
			ZIndex = 7,
		}, layer)
		local angle = math.rad(math.random(200, 340)) -- mostly upward
		local speed = math.random(420, 900)
		table.insert(pieces, {
			frame = piece,
			x = 0,
			y = 0,
			vx = math.cos(angle) * speed,
			vy = math.sin(angle) * speed,
			spin = math.random(-720, 720),
			rot = math.random(0, 360),
		})
	end
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - start
		if t > 2.6 or not layer.Parent then
			connection:Disconnect()
			return
		end
		for _, p in pieces do
			p.vy += 1100 * dt
			p.vx *= 1 - 1.2 * dt
			p.x += p.vx * dt
			p.y += p.vy * dt
			p.rot += p.spin * dt
			p.frame.Position = UDim2.new(0.5, p.x, 0.45, p.y)
			p.frame.Rotation = p.rot
			p.frame.BackgroundTransparency = math.clamp((t - 1.8) / 0.8, 0, 1)
		end
	end)
end

local function play(key: string, info: any)
	local look = lookFor(key)
	local still = Ui.reducedMotion()
	local gift = type(info) == "table" and (info.From or info.To) or nil
	local title = if type(info) == "table" and info.From
		then "GIFT FOR YOU!"
		elseif type(info) == "table" and info.To then "GIFT SENT!"
		else "PURCHASED!"

	local root = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
	-- Tap anywhere to skip.
	local skip = make("TextButton", {
		Size = UDim2.new(1, 400, 1, 400),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(11, 14, 30),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 1,
	}, root)
	local flash = make("Frame", {
		Size = UDim2.new(1, 400, 1, 400),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.25,
		ZIndex = 9,
	}, root)
	local stage = make("Frame", {
		Size = UDim2.fromOffset(600, 520),
		Position = UDim2.fromScale(0.5, 0.48),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, root)
	make("UIScale", { Scale = math.clamp(Ui.scale(), 0.6, 1.1) }, stage)

	local rays = make("ImageLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(0, 0),
		Image = AssetLibrary.image("Rays"),
		ImageColor3 = look.color,
		ImageTransparency = 0.2,
		ZIndex = 2,
	}, stage)
	local glow = make("ImageLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(0, 0),
		Image = AssetLibrary.image("Glow"),
		ImageColor3 = WHITE,
		ImageTransparency = 0.15,
		ZIndex = 3,
	}, stage)
	-- The thing you bought: an icon, or the 3D egg.
	local item: GuiObject
	if look.egg then
		local viewport = make("ViewportFrame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromOffset(0, 0),
			Ambient = Color3.fromRGB(200, 208, 232),
			LightColor = WHITE,
			ZIndex = 4,
		}, stage)
		local egg = { Rarity = look.egg, Zone = look.eggZone }
		ModelView.show(viewport, AssetLibrary.eggOf(egg), AssetLibrary.eggKey(egg))
		item = viewport
	else
		item = make("ImageLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromOffset(0, 0),
			Image = AssetLibrary.image(look.icon or "Icon_Star"),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 4,
		}, stage)
	end
	-- Sticker: tilted plate with the title, drops in from above.
	local sticker = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, -0.2),
		Size = UDim2.fromOffset(360, 66),
		BackgroundColor3 = if gift then PURPLE else Color3.fromRGB(255, 77, 94),
		Rotation = -5,
		ZIndex = 6,
	}, stage)
	make("UIStroke", { Color = INK, Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, sticker)
	local stickerText = label(title, 42, YELLOW, sticker, 7)
	stickerText.Size = UDim2.new(1, -10, 1, 0)
	stickerText.Position = UDim2.fromScale(0.5, 0.5)
	stickerText.TextScaled = true
	make("UITextSizeConstraint", { MaxTextSize = 42 }, stickerText)
	local name = label(look.name, 38, WHITE, stage, 6)
	name.Position = UDim2.fromScale(0.5, 0.8)
	name.TextTransparency = 1
	local nameStroke = name:FindFirstChildOfClass("UIStroke") :: UIStroke
	nameStroke.Transparency = 1
	local subText = if type(info) == "table" and info.From
		then `from {info.From}`
		elseif type(info) == "table" and info.To then `to {info.To}`
		else "Thanks for supporting the game!"
	local sub = label(subText, 24, YELLOW, stage, 6)
	sub.Position = UDim2.fromScale(0.5, 0.9)
	sub.TextTransparency = 1
	local subStroke = sub:FindFirstChildOfClass("UIStroke") :: UIStroke
	subStroke.Transparency = 1

	-- In.
	Ui.sound(if gift then "Gift" else "RareReveal")
	Ui.sound("Sparkle")
	tween(skip, 0.25, { BackgroundTransparency = 0.45 })
	tween(flash, 0.35, { BackgroundTransparency = 1 })
	tween(rays, 0.5, { Size = UDim2.fromOffset(560, 560) }, Enum.EasingStyle.Back)
	tween(glow, 0.4, { Size = UDim2.fromOffset(380, 380) })
	tween(item, 0.5, { Size = UDim2.fromOffset(250, 250) }, Enum.EasingStyle.Back)
	task.delay(0.12, function()
		tween(sticker, 0.45, { Position = UDim2.fromScale(0.5, 0.1) }, Enum.EasingStyle.Back)
	end)
	task.delay(0.25, function()
		tween(name, 0.3, { TextTransparency = 0, Position = UDim2.fromScale(0.5, 0.78) })
		tween(nameStroke, 0.3, { Transparency = 0 })
		tween(sub, 0.3, { TextTransparency = 0 })
		tween(subStroke, 0.3, { Transparency = 0 })
	end)
	if not still then
		confetti(root, 70)
	end

	-- While up: rays turn, the item bobs, the sticker wiggles.
	local start = os.clock()
	local alive = true
	local loop = RunService.RenderStepped:Connect(function()
		if still then
			return
		end
		local t = os.clock() - start
		rays.Rotation = t * 35
		item.Position = UDim2.new(0.5, 0, 0.45, math.sin(t * 3) * 8)
		item.Rotation = math.sin(t * 2.2) * 4
		sticker.Rotation = -5 + math.sin(t * 5) * 2
	end)

	local finished = Instance.new("BindableEvent")
	local function close()
		if not alive then
			return
		end
		alive = false
		-- Out: everything fades while the item shrinks toward your bag.
		local fly = if look.toBag and C.FlyController and C.FlyController.BagAbsolute then C.FlyController.BagAbsolute() else nil
		if fly then
			local abs = stage.AbsolutePosition
			local k = stage.AbsoluteSize.X / 600
			local target = UDim2.fromOffset((fly.X - abs.X) / k, (fly.Y - abs.Y) / k)
			tween(item, 0.45, { Position = target, Size = UDim2.fromOffset(40, 40) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		else
			tween(item, 0.3, { Size = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		end
		tween(rays, 0.3, { Size = UDim2.fromOffset(0, 0), ImageTransparency = 1 })
		tween(glow, 0.3, { ImageTransparency = 1 })
		tween(sticker, 0.3, { Position = UDim2.fromScale(0.5, -0.3) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		for _, l in { name, sub } do
			tween(l, 0.25, { TextTransparency = 1 })
		end
		tween(nameStroke, 0.25, { Transparency = 1 })
		tween(subStroke, 0.25, { Transparency = 1 })
		tween(skip, 0.35, { BackgroundTransparency = 1 })
		task.delay(0.5, function()
			loop:Disconnect()
			root:Destroy()
			finished:Fire()
		end)
	end
	skip.Activated:Connect(close)
	task.delay(SHOW_SECONDS, close)
	finished.Event:Wait()
	finished:Destroy()
end

local function pump()
	if playing then
		return
	end
	playing = true
	while #queue > 0 do
		local next = table.remove(queue, 1)
		if next then
			local ok, err = pcall(play, next.key, next.info)
			if not ok then
				warn("purchase celebration:", err)
			end
		end
	end
	playing = false
end

-- Plays the celebration for a product or pass key (also usable by other controllers).
function PurchaseController:Celebrate(key: string, info: any?)
	table.insert(queue, { key = key, info = info or {} })
	task.spawn(pump)
end

function PurchaseController:Init(controllers)
	C = controllers
	gui = Instance.new("ScreenGui")
	gui.Name = "Purchased"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 35 -- over windows, under the flyers (Fly is 40)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function PurchaseController:Start()
	Net.event("Purchased").OnClientEvent:Connect(function(key: any, info: any)
		if type(key) == "string" then
			PurchaseController:Celebrate(key, info)
		end
	end)
end

return PurchaseController
