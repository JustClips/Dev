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
local INK = Color3.fromRGB(23, 25, 30)
local STEP = 360 / 8
local BUYS = { Buy1 = "WheelSpin1", Buy5 = "WheelSpin5", Buy10 = "WheelSpin10" }

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

local function setButton(button: GuiButton, text: string, color: Color3, labelColor: Color3?)
	Ui.setText(button, text)
	button.BackgroundColor3 = color
	local studs = button:FindFirstChild("Studs") :: ImageLabel?
	if studs then
		studs.ImageColor3 = color
	end
	local label = button:FindFirstChild("Label") :: TextLabel?
	if label then
		label.TextColor3 = labelColor or WHITE
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
		setButton(spinButton, if def and def.Id ~= 0 then `SPIN  {Ui.ROBUX} {def.Price}` else "No spins", GOLD, INK)
	end
end

-- Icon, label and tint for one wedge (the same words the Gifts window uses).
local function describe(seg: Rewards.WheelSegment): (string, string, Color3?)
	local image, label, tint = C.RewardsController.Describe(seg.Reward)
	return image, seg.Label or label, tint
end

local function fill()
	local total = Rewards.wheelTotal()
	for i, seg in Rewards.Wheel.Segments do
		local image, label, tint = describe(seg)
		local slot = Ui.find(gui, `Window.WheelArea.Spinner.Seg{i}`)
		local icon = slot:FindFirstChild("Icon") :: ImageLabel
		icon.Image = AssetLibrary.image(image)
		icon.ImageColor3 = tint or WHITE
		;(slot:FindFirstChild("Label") :: TextLabel).Text = label
		local row = Ui.find(gui, `Window.Side.Odds.List.Odds{i}`)
		local rowIcon = row:FindFirstChild("Icon") :: ImageLabel
		rowIcon.Image = AssetLibrary.image(image)
		rowIcon.ImageColor3 = tint or WHITE
		local _, fullName = C.RewardsController.Describe(seg.Reward)
		local pct = seg.Weight / total * 100
		;(row:FindFirstChild("Label") :: TextLabel).Text = `{fullName}  {if pct >= 1 then string.format("%d", pct) else string.format("%.1f", pct)}%`
	end
	for name, key in BUYS do
		local button = Ui.find(gui, `Window.Side.Buy.{name}`) :: GuiButton
		local def = Products.ProductByKey[key]
		button.Visible = def ~= nil and def.Id ~= 0
		if def then
			;(button:FindFirstChild("Price") :: TextLabel).Text = `{Ui.ROBUX} {def.Price}`
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
	railBadge = Ui.find(Ui.screen("Hud"), "Rail.SpinButton"):FindFirstChild("Badge") :: Frame?
end

function WheelController:Start()
	fill()
	Ui.button(Ui.find(Ui.screen("Hud"), "Rail.SpinButton"), function()
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
