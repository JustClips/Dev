--!strict
-- Lucky Wheel window (screen "Wheel", tools/gen_ui.py wheel()). Opened from the blue Spin
-- button on the rail or the big wheel in the plaza (prompt Opens = "Wheel"). One free spin,
-- then spins from the 5-minute playtime gift or Robux (Products, Kind "WheelSpins").
-- The server picks the prize (Rewards remote, "Spin" -> ok, message, segment index); this
-- only turns the wheel so it lands on that wedge, then shows the prize.
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

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
	if railBadge then
		Ui.setBadge(railBadge, if count > 0 then count else nil)
	end
	if not Ui.isOpen(gui) then
		return
	end
	;(Ui.find(gui, "Window.Side.Spins") :: TextLabel).Text = `Spins: {r.Spins or 0}`
	local note = Ui.find(gui, "Window.Side.FreeNote") :: TextLabel
	if r.FreeSpin then
		note.Text = "Your FREE spin is ready!"
		note.TextColor3 = Color3.fromRGB(30, 158, 58)
	elseif type(r.FreeSpinAt) == "number" then
		note.Text = `Next free spin in {Format.countdown(math.max(0, r.FreeSpinAt - State.now()))}`
		note.TextColor3 = Color3.fromRGB(91, 96, 112)
	else
		note.Text = "Get a free spin from Playtime Gifts!"
		note.TextColor3 = Color3.fromRGB(91, 96, 112)
	end
	if spinning then
		setButton(spinButton, "Spinning...", GREY)
	elseif r.FreeSpin then
		setButton(spinButton, "FREE SPIN!", GREEN)
	elseif (r.Spins or 0) > 0 then
		setButton(spinButton, "SPIN!", GREEN)
	else
		local def = Products.ProductByKey.WheelSpin1
		setButton(spinButton, if def and def.Id ~= 0 then `SPIN {Ui.ROBUX}{def.Price}` else "No spins", GOLD)
	end
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
		local chance = slot:FindFirstChild("Label") :: TextLabel
		chance.Text = percent(seg.Weight)
		local row = Ui.find(gui, `Window.Side.Odds.List.Odds{i}`)
		local rowIcon = row:FindFirstChild("Icon") :: ImageLabel
		rowIcon.Image = AssetLibrary.image(image)
		rowIcon.ImageColor3 = tint or WHITE
		local nameLabel = row:FindFirstChild("Name") :: TextLabel
		nameLabel.Text = if seg.Weight <= 1 then `{name} (JACKPOT)` else name
		local chanceLabel = row:FindFirstChild("Chance") :: TextLabel
		chanceLabel.Text = percent(seg.Weight)
	end
	for name, key in BUYS do
		local button = Ui.find(gui, `Window.Side.Buy.{name}`) :: GuiButton
		local def = Products.ProductByKey[key]
		button.Visible = def ~= nil and def.Id ~= 0
		if def then
			(button:FindFirstChild("Price") :: TextLabel).Text = `{Ui.ROBUX} {def.Price}`
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

-- The prize card over the wheel (Dev 2026-10-31: show what you won inside the wheel frame,
-- not only in a toast). Square, solid, Montserrat like the rest of the UI.
local prizeCard: Frame?
local prizeToken = 0

local function makePrizeCard(): Frame
	local area = Ui.find(gui, "Window.WheelArea") :: Frame
	local card = Instance.new("Frame")
	card.Name = "PrizeCard"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(250, 210)
	card.BackgroundColor3 = Color3.fromRGB(30, 34, 52)
	card.BorderSizePixel = 0
	card.ZIndex = 20
	card.Visible = false
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Edge"
	stroke.Thickness = 4
	stroke.Color = GOLD
	stroke.Parent = card
	local scale = Instance.new("UIScale")
	scale.Parent = card
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundColor3 = GOLD
	title.BorderSizePixel = 0
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Font = Enum.Font.Montserrat
	title.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
	title.Text = "YOU WON!"
	title.TextColor3 = WHITE
	title.TextSize = 26
	title.ZIndex = 21
	local tStroke = Instance.new("UIStroke")
	tStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	tStroke.Thickness = 2
	tStroke.Color = Color3.fromRGB(90, 55, 0)
	tStroke.Parent = title
	title.Parent = card
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 48)
	icon.Size = UDim2.fromOffset(104, 104)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 21
	icon.Parent = card
	local name = Instance.new("TextLabel")
	name.Name = "PrizeName"
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0, 8, 1, -54)
	name.Size = UDim2.new(1, -16, 0, 46)
	name.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
	name.TextScaled = true
	name.TextColor3 = WHITE
	name.ZIndex = 21
	local nStroke = Instance.new("UIStroke")
	nStroke.Thickness = 2
	nStroke.Color = Color3.new(0, 0, 0)
	nStroke.Parent = name
	name.Parent = card
	card.Parent = area
	return card
end

local function hidePrize()
	prizeToken += 1
	if prizeCard then
		prizeCard.Visible = false
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
	local edge = card:FindFirstChild("Edge") :: UIStroke
	edge.Color = if jackpot then Color3.fromRGB(255, 90, 200) else GOLD
	local title = card:FindFirstChild("Title") :: TextLabel
	title.Text = if jackpot then "JACKPOT!" else "YOU WON!"
	title.BackgroundColor3 = if jackpot then Color3.fromRGB(255, 90, 200) else GOLD;
	(card:FindFirstChild("PrizeName") :: TextLabel).Text = name
	card.Visible = true
	local scale = card:FindFirstChildOfClass("UIScale") :: UIScale
	if Ui.reducedMotion() then
		scale.Scale = 1
	else
		scale.Scale = 0.3
		TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	prizeToken += 1
	local token = prizeToken
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
		buy("WheelSpin1")
		return
	end
	spinning = true
	hidePrize()
	render()
	local ok, message, index = Net.func("Rewards"):InvokeServer("Spin")
	if not ok or type(index) ~= "number" then
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
	spinner = Ui.find(gui, "Window.WheelArea.Spinner")
	spinButton = Ui.find(gui, "Window.Side.SpinButton")
	railBadge = Ui.find(Ui.screen("Hud"), "SpinButton"):FindFirstChild("Badge") :: Frame?
end

function WheelController:Start()
	fill()
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
	-- Prize chances: swaps the spin packs for the list of prizes and back.
	local odds = Ui.find(gui, "Window.Side.Odds") :: Frame
	local packs = Ui.find(gui, "Window.Side.Buy") :: Frame
	local oddsButton = Ui.find(gui, "Window.Side.OddsButton") :: GuiButton
	Ui.button(oddsButton, function()
		odds.Visible = not odds.Visible
		packs.Visible = not odds.Visible
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
