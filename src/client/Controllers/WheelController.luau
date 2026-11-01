--!strict
-- Lucky Wheel window (screen "Wheel", tools/gen_ui.py wheel()). Opened from the blue Spin
-- button on the HUD or the big wheel in the plaza (prompt Opens = "Wheel"). One free spin a
-- day (the SPIN button counts down to it), plus spins from quests, packs or Robux (Products,
-- Kind "WheelSpins"). The Lucky Cat panel counts down to the guaranteed wheel-only pet.
-- The server picks the prize (Rewards remote, "Spin" -> ok, message, segment index); this
-- only turns the wheel so it lands on that wedge, then shows the prize.
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local ModelView = require(Client.ModelView)
local State = require(Client.State)
local Ui = require(Client.Ui)
local Prices = require(Client.Prices)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Rewards = require(Shared.Config.Rewards)

local GREEN = Color3.fromRGB(61, 220, 90)
local GOLD = Color3.fromRGB(255, 200, 60)
local GREY = Color3.fromRGB(166, 174, 194)
local WHITE = Color3.new(1, 1, 1)
local STEP = 360 / 8
local BUYS = { Buy1 = "WheelSpin1", Buy5 = "WheelSpin5" }

local WheelController = {}

local C: any
local gui: ScreenGui
local spinner: Frame
local spinButton: GuiButton
local railBadge: Frame?
local spinsReady = false
local spinning = false
local rotation = 0

local function info(): { [string]: any }?
	local data = State.data
	return data and data.Rewards
end

-- Spins you can use right now (the free one counts).
local function available(r): number
	return (r.Spins or 0) + (if r.FreeSpin then 1 else 0)
end

-- White text with the dark outline on every colour (dark text on the gold button blurred
-- into its outline).
local function setButton(button: GuiButton, text: string, color: Color3)
	Ui.setText(button, text)
	button.BackgroundColor3 = color
	local studs = button:FindFirstChild("Studs") :: ImageLabel?
	if studs then
		studs.ImageColor3 = color
	end
	local label = button:FindFirstChild("Label") :: TextLabel?
	if label then
		label.TextColor3 = WHITE
	end
end

local function render()
	local r = info()
	if not r then
		return
	end
	local count = available(r)
	spinsReady = count > 0
	if railBadge then
		Ui.setBadge(railBadge, if count > 0 then count else nil)
	end
	-- Buttons keep their labels (Dev, 2026-10-31: no button turning into a timer); the
	-- countdown lives in the line above the SPIN button, as "23h 12m 5s".
	local freeIn = if type(r.FreeSpinAt) == "number" then math.max(0, r.FreeSpinAt - State.now()) else nil
	if not Ui.isOpen(gui) then
		return
	end
	;(Ui.find(gui, "Window.Side.Spins") :: TextLabel).Text = `Spins: {r.Spins or 0}`
	local timer = if freeIn and freeIn > 0 then `Free spin in {Format.dhms(freeIn)}` else nil
	local note = Ui.find(gui, "Window.Side.FreeNote") :: TextLabel
	if r.FreeSpin then
		note.Text = "Your FREE spin is ready!"
		note.TextColor3 = Color3.fromRGB(30, 158, 58)
	elseif timer then
		note.Text = timer
		note.TextColor3 = Color3.fromRGB(91, 96, 112)
	else
		note.Text = "A free spin every day!"
		note.TextColor3 = Color3.fromRGB(91, 96, 112)
	end
	if spinning then
		setButton(spinButton, "Spinning...", GREY)
	elseif r.FreeSpin then
		setButton(spinButton, "FREE SPIN!", GREEN)
	elseif (r.Spins or 0) > 0 then
		setButton(spinButton, "SPIN!", GREEN)
	else
		setButton(spinButton, "No spins", GREY)
	end
	-- Lucky Cat pity: spins left until it's guaranteed, and a bar that fills toward it.
	local pity = Ui.find(gui, "Window.Side.Pity") :: Frame
	local left = tonumber(r.WheelPityLeft) or Rewards.Wheel.Pity
	;(pity:FindFirstChild("Sub") :: TextLabel).Text = if left <= 1
		then "Guaranteed on your NEXT spin!"
		else `Guaranteed in {left} spins`
	local fill = Ui.find(pity, "Bar.Fill") :: Frame
	fill.Size = UDim2.fromScale(math.clamp(1 - (left - 1) / Rewards.Wheel.Pity, 0, 1), 1)
end

local function percent(weight: number): string
	local pct = weight / Rewards.wheelTotal() * 100
	return if pct >= 1 then `{math.floor(pct + 0.5)}%` else `{string.format("%.1f", pct)}%`
end

-- On the wheel: just the prize icon and its chance (names didn't fit). The full names are
-- in the Prize chances list.
local function fill()
	for i, seg in Rewards.Wheel.Segments do
		local image, name, tint = C.RewardsController.Describe(seg.Reward)
		local slot = Ui.find(gui, `Window.WheelArea.Spinner.Seg{i}`)
		local icon = slot:FindFirstChild("Icon") :: ImageLabel
		icon.Image = AssetLibrary.image(image)
		icon.ImageColor3 = tint or WHITE
		-- Egg prizes show the real brick egg (Dev, 2026-11-01: the tinted egg icons looked bad).
		local model = slot:FindFirstChild("Model") :: ViewportFrame?
		local rarity = seg.Reward.Kind == "Egg" and seg.Reward.Rarity
		if model and rarity then
			ModelView.show(model, AssetLibrary.egg(rarity), "Egg_" .. rarity)
			model.Visible = true
			icon.Visible = false
		end
		local chance = slot:FindFirstChild("Label") :: TextLabel
		chance.Text = percent(seg.Weight)
		local row = Ui.find(gui, `Window.Side.Odds.List.Odds{i}`)
		local rowIcon = row:FindFirstChild("Icon") :: ImageLabel
		rowIcon.Image = AssetLibrary.image(image)
		rowIcon.ImageColor3 = tint or WHITE
		local nameLabel = row:FindFirstChild("Name") :: TextLabel
		-- JACKPOT sits on the chance line (Dev, 2026-10-31: "Legendary Egg (JACKPOT)" spilled
		-- out of the row).
		nameLabel.Text = name
		local chanceLabel = row:FindFirstChild("Chance") :: TextLabel
		chanceLabel.Text = if seg.Weight <= 1 then `{percent(seg.Weight)}  JACKPOT!` else percent(seg.Weight)
		chanceLabel.TextColor3 = if seg.Weight <= 1 then Color3.fromRGB(255, 110, 200) else chanceLabel.TextColor3
	end
	for name, key in BUYS do
		local button = Ui.find(gui, `Window.Side.Buy.{name}`) :: GuiButton
		local def = Products.ProductByKey[key]
		button.Visible = def ~= nil and def.Id ~= 0
		if def then
			(button:FindFirstChild("Price") :: TextLabel).Text = `{Ui.ROBUX} {Prices.of(def)}`
		end
	end
end

local function buy(key: string)
	local ok, message = Net.func("PromptPurchase"):InvokeServer(key)
	if not ok and message then
		C.HudController:Toast(message, "Bad")
	end
end

-- Pops the wedge that won.
local function celebrate(index: number)
	local slot = Ui.find(gui, `Window.WheelArea.Spinner.Seg{index}`) :: Frame
	local scale = slot:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = slot
	scale.Scale = 1.5
	TweenService:Create(scale, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- The win over the wheel (Dev 2026-10-31: the plain "YOU WON!" card was boring): spinning
-- rays, a tilted title sticker that bounces in, the prize big in the middle with a bob,
-- confetti bursting out, and the prize name on a solid plate. A jackpot goes pink with more
-- confetti. Square corners, Montserrat, like the rest of the UI.
local prizeCard: Frame?
local prizeToken = 0
local HEAVY = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
local PINK = Color3.fromRGB(255, 90, 200)
local CONFETTI = {
	Color3.fromRGB(255, 212, 59),
	Color3.fromRGB(255, 90, 200),
	Color3.fromRGB(76, 168, 255),
	Color3.fromRGB(92, 214, 92),
	Color3.fromRGB(255, 154, 60),
	Color3.fromRGB(197, 155, 255),
}

local function label(parent: Instance, name: string, size: UDim2, pos: UDim2, textSize: number, z: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = pos
	l.Size = size
	l.FontFace = HEAVY
	l.TextScaled = true
	l.TextColor3 = WHITE
	l.ZIndex = z
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = textSize
	fit.Parent = l
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(23, 25, 30)
	stroke.Parent = l
	l.Parent = parent
	return l
end

local function makePrizeCard(): Frame
	local area = Ui.find(gui, "Window.WheelArea") :: Frame
	local card = Instance.new("Frame")
	card.Name = "PrizeCard"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(400, 400)
	card.BackgroundTransparency = 1
	card.ZIndex = 20
	card.Visible = false
	local scale = Instance.new("UIScale")
	scale.Parent = card
	-- A dark square behind it all so the wheel steps back.
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.AnchorPoint = Vector2.new(0.5, 0.5)
	back.Position = UDim2.fromScale(0.5, 0.52)
	back.Size = UDim2.fromOffset(290, 290)
	back.BackgroundColor3 = Color3.fromRGB(30, 34, 52)
	back.BorderSizePixel = 0
	back.ZIndex = 20
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Thickness = 5
	edge.Color = GOLD
	edge.Parent = back
	back.Parent = card
	local rays = Instance.new("ImageLabel")
	rays.Name = "Rays"
	rays.BackgroundTransparency = 1
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.48)
	rays.Size = UDim2.fromOffset(330, 330)
	rays.Image = AssetLibrary.image("Rays")
	rays.ImageColor3 = GOLD
	rays.ImageTransparency = 0.25
	rays.ZIndex = 21
	rays.Parent = card
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.48)
	icon.Size = UDim2.fromOffset(150, 150)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 23
	icon.Parent = card
	-- Title sticker, tilted, on top edge.
	local sticker = Instance.new("Frame")
	sticker.Name = "Sticker"
	sticker.AnchorPoint = Vector2.new(0.5, 0.5)
	sticker.Position = UDim2.fromScale(0.5, 0.17)
	sticker.Size = UDim2.fromOffset(250, 58)
	sticker.BackgroundColor3 = GOLD
	sticker.BorderSizePixel = 0
	sticker.Rotation = -6
	sticker.ZIndex = 24
	local sStroke = Instance.new("UIStroke")
	sStroke.Thickness = 4
	sStroke.Color = Color3.fromRGB(23, 25, 30)
	sStroke.Parent = sticker
	sticker.Parent = card
	local stickerScale = Instance.new("UIScale")
	stickerScale.Parent = sticker
	label(sticker, "Title", UDim2.new(1, -12, 1, -6), UDim2.fromScale(0.5, 0.5), 38, 25)
	-- Prize name plate along the bottom.
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.8)
	plate.Size = UDim2.fromOffset(270, 54)
	plate.BackgroundColor3 = Color3.fromRGB(61, 220, 90)
	plate.BorderSizePixel = 0
	plate.ZIndex = 24
	local pStroke = Instance.new("UIStroke")
	pStroke.Thickness = 4
	pStroke.Color = Color3.fromRGB(23, 25, 30)
	pStroke.Parent = plate
	plate.Parent = card
	label(plate, "PrizeName", UDim2.new(1, -14, 1, -8), UDim2.fromScale(0.5, 0.5), 30, 25)
	local confetti = Instance.new("Frame")
	confetti.Name = "Confetti"
	confetti.BackgroundTransparency = 1
	confetti.Size = UDim2.fromScale(1, 1)
	confetti.ZIndex = 26
	confetti.Parent = card
	card.Parent = area
	return card
end

local function hidePrize()
	prizeToken += 1
	if prizeCard then
		prizeCard.Visible = false
	end
end

-- Confetti: little squares that shoot out of the prize, fall and spin.
local function burstConfetti(card: Frame, amount: number)
	local holder = card:FindFirstChild("Confetti") :: Frame
	holder:ClearAllChildren()
	if Ui.reducedMotion() then
		return
	end
	for _ = 1, amount do
		local bit = Instance.new("Frame")
		bit.BorderSizePixel = 0
		bit.AnchorPoint = Vector2.new(0.5, 0.5)
		bit.BackgroundColor3 = CONFETTI[math.random(#CONFETTI)]
		local w = math.random(8, 14)
		bit.Size = UDim2.fromOffset(w, math.floor(w * 0.6))
		bit.Position = UDim2.fromScale(0.5, 0.48)
		bit.Rotation = math.random(0, 360)
		bit.ZIndex = 26
		bit.Parent = holder
		local angle = math.random() * math.pi * 2
		local dist = math.random(120, 230)
		local out = UDim2.new(0.5, math.cos(angle) * dist, 0.48, math.sin(angle) * dist - 40)
		TweenService:Create(bit, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = out,
			Rotation = bit.Rotation + math.random(-360, 360),
		}):Play()
		task.delay(0.55, function()
			if bit.Parent then
				TweenService:Create(bit, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = out + UDim2.fromOffset(math.random(-20, 20), 140),
					BackgroundTransparency = 1,
					Rotation = bit.Rotation + math.random(-360, 360),
				}):Play()
			end
		end)
	end
end

local function showPrize(index: number)
	local seg = Rewards.Wheel.Segments[index]
	if not seg then
		return
	end
	local card = prizeCard or makePrizeCard()
	prizeCard = card
	local image, name, tint = C.RewardsController.Describe(seg.Reward)
	local icon = card:FindFirstChild("Icon") :: ImageLabel
	icon.Image = AssetLibrary.image(image)
	icon.ImageColor3 = tint or WHITE
	local jackpot = seg.Weight <= 1
	local color = if jackpot then PINK else GOLD
	local back = card:FindFirstChild("Back") :: Frame
	;(back:FindFirstChild("Edge") :: UIStroke).Color = color
	;(card:FindFirstChild("Rays") :: ImageLabel).ImageColor3 = color
	local sticker = card:FindFirstChild("Sticker") :: Frame
	sticker.BackgroundColor3 = color
	;(sticker:FindFirstChild("Title") :: TextLabel).Text = if jackpot then "JACKPOT!" else "YOU WON!"
	;(Ui.find(card, "Plate.PrizeName") :: TextLabel).Text = name
	card.Visible = true
	local scale = card:FindFirstChildOfClass("UIScale") :: UIScale
	local stickerScale = sticker:FindFirstChildOfClass("UIScale") :: UIScale
	if Ui.reducedMotion() then
		scale.Scale = 1
		stickerScale.Scale = 1
	else
		scale.Scale = 0.3
		TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		stickerScale.Scale = 0
		task.delay(0.2, function()
			TweenService:Create(stickerScale, TweenInfo.new(0.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
	end
	burstConfetti(card, if jackpot then 60 else 30)
	prizeToken += 1
	local token = prizeToken
	-- Rays turn, the prize bobs and the title wiggles while it's up.
	task.spawn(function()
		local rays = card:FindFirstChild("Rays") :: ImageLabel
		local t0 = os.clock()
		while token == prizeToken and card.Visible do
			local t = os.clock() - t0
			rays.Rotation = t * 40
			icon.Position = UDim2.new(0.5, 0, 0.48, math.sin(t * 4) * 6)
			sticker.Rotation = -6 + math.sin(t * 5) * 3
			RunService.RenderStepped:Wait()
		end
	end)
	task.delay(3.5, function()
		if token == prizeToken and card.Visible then
			card.Visible = false
		end
	end)
end

-- Turns the wheel so wedge `index` stops under the pointer (top), several turns clockwise.
local function turnTo(index: number, done: () -> ())
	local centre = (index - 0.5) * STEP
	local jitter = (math.random() - 0.5) * STEP * 0.7
	local from = rotation
	local target = math.ceil(from / 360) * 360 + 360 * 5 + (360 - centre) + jitter
	local duration = if Ui.reducedMotion() then 0.6 else Rewards.Wheel.SpinSeconds
	local start = os.clock()
	local lastTick = math.floor(from / STEP)
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / duration, 0, 1)
		local e = 1 - (1 - t) ^ 4
		rotation = from + (target - from) * e
		spinner.Rotation = rotation
		-- A click each time a divider passes the pointer.
		local tick = math.floor((rotation + STEP / 2) / STEP)
		if tick ~= lastTick then
			lastTick = tick
			Ui.sound("Click", 1 + (1 - t) * 0.4)
		end
		if t >= 1 then
			conn:Disconnect()
			rotation = rotation % 360
			spinner.Rotation = rotation
			done()
		end
	end)
end

local function spin()
	if spinning then
		return
	end
	local r = info()
	if not r then
		return
	end
	if available(r) <= 0 then
		local freeIn = if type(r.FreeSpinAt) == "number" then math.max(0, r.FreeSpinAt - State.now()) else nil
		C.HudController:Toast(
			if freeIn then `Free spin in {Format.dhms(freeIn)}. Get more spins below!` else "No spins left. Get more below!",
			"Bad"
		)
		return
	end
	spinning = true
	hidePrize()
	render()
	-- The prize is given right away on the server; its flight waits for the wheel to stop.
	C.FlyController:Hold(Rewards.Wheel.SpinSeconds + 6)
	local ok, message, index = Net.func("Rewards"):InvokeServer("Spin")
	if not ok or type(index) ~= "number" then
		C.FlyController:Release()
		spinning = false
		render()
		if message then
			C.HudController:Toast(message, "Bad")
		end
		return
	end
	Ui.sound("HatchLift")
	turnTo(index, function()
		spinning = false
		local seg = Rewards.Wheel.Segments[index]
		Ui.sound(if seg and seg.Weight <= 5 then "RareReveal" else "Reveal")
		celebrate(index)
		showPrize(index)
		if message then
			C.HudController:Toast(message, "Good")
		end
		render()
		-- Let the prize card show first, then the prize flies out to the wallet or the Bag.
		task.delay(1.2, function()
			C.FlyController:Release()
		end)
	end)
end

function WheelController:IsSpinning(): boolean
	return spinning
end

function WheelController:Open()
	if not Ui.isOpen(gui) then
		Ui.open("Wheel")
	end
	render()
end

function WheelController:Init(controllers)
	C = controllers
	gui = Ui.screen("Wheel")
	-- 2026-11-01 remake (no big window): LiveSync never deletes GUI children in Dev's Studio
	-- place, so drop the old window's header, outline and panel styling.
	local window = gui:WaitForChild("Window")
	local side = window:WaitForChild("Side")
	for _, pair in { { window, "Header" }, { window, "Stroke" }, { window, "Shade" } } do
		local stale = pair[1]:FindFirstChild(pair[2])
		if stale then
			stale:Destroy()
		end
	end
	for _, name in { "Odds", "Pity" } do
		local panel = side:FindFirstChild(name)
		for _, part in { "Stroke", "Shade" } do
			local stale = panel and panel:FindFirstChild(part)
			if stale then
				stale:Destroy()
			end
		end
	end
	spinner = Ui.find(gui, "Window.WheelArea.Spinner")
	spinButton = Ui.find(gui, "Window.Side.SpinButton")
	railBadge = Ui.find(Ui.screen("Hud"), "SpinButton"):FindFirstChild("Badge") :: Frame?
end

function WheelController:Start()
	fill()
	-- The egg models on the wheel load after the UI: draw them again once they're in.
	AssetLibrary.onCoreReady(fill)
	Ui.button(Ui.find(Ui.screen("Hud"), "SpinButton"), function()
		if Ui.isOpen(gui) then
			Ui.close("Wheel")
		else
			WheelController:Open()
		end
	end)
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Wheel")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Wheel")
	end)
	Ui.button(spinButton, spin)
	-- While you have a spin, the HUD Spin button (and the big SPIN in the window) breathes
	-- bigger and back (Dev, 2026-10-31).
	local hudSpin = Ui.find(Ui.screen("Hud"), "SpinButton") :: GuiButton
	local hudSize = hudSpin.Size
	local bigSize = spinButton.Size
	game:GetService("RunService").RenderStepped:Connect(function()
		local k = if spinsReady and not spinning and not Ui.reducedMotion() then 1 + math.abs(math.sin(os.clock() * 3.2)) * 0.12 else 1
		hudSpin.Size = UDim2.new(hudSize.X.Scale, math.floor(hudSize.X.Offset * k), hudSize.Y.Scale, math.floor(hudSize.Y.Offset * k))
		if gui.Enabled then
			spinButton.Size = UDim2.new(bigSize.X.Scale, bigSize.X.Offset * (1 + (k - 1) * 0.4), bigSize.Y.Scale,
				bigSize.Y.Offset * (1 + (k - 1) * 0.4))
		end
	end)
	-- Prize chances: swaps the spin packs for the list of prizes and back.
	local odds = Ui.find(gui, "Window.Side.Odds") :: Frame
	local packs = Ui.find(gui, "Window.Side.Buy") :: Frame
	local oddsButton = Ui.find(gui, "Window.Side.OddsButton") :: GuiButton
	local pityPanel = Ui.find(gui, "Window.Side.Pity") :: Frame
	Ui.button(oddsButton, function()
		odds.Visible = not odds.Visible
		packs.Visible = not odds.Visible
		pityPanel.Visible = not odds.Visible
		Ui.setText(oddsButton, if odds.Visible then "Back to spins" else "Prize chances")
	end)
	for name, key in BUYS do
		Ui.button(Ui.find(gui, `Window.Side.Buy.{name}`), function()
			buy(key)
		end)
	end
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("Opens") == "Wheel" then
			WheelController:Open()
		end
	end)
	State.Changed:Connect(render)
	task.spawn(function()
		while true do
			task.wait(1)
			render()
		end
	end)
end

return WheelController
