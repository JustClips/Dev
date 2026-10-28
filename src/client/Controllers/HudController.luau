--!strict
-- Main HUD: cash, backpack, Moon bar + event, boost timers, menu buttons, next-tool
-- button, toasts and server announcements.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Tools = require(Shared.Config.Tools)

local MAX_TOASTS = 4
local TOAST_SECONDS = 3
local TOAST_COLORS: { [string]: Color3 } = {
	Good = Color3.fromRGB(140, 255, 170),
	Bad = Color3.fromRGB(255, 140, 140),
	Sell = Color3.fromRGB(255, 220, 90),
	Egg = Color3.fromRGB(255, 200, 255),
	Info = Color3.fromRGB(200, 220, 255),
}
local LUCK_TIERS = { 16, 8, 4, 2 }

local HudController = {}

local C: any
local hud: ScreenGui
local el: { [string]: any } = {}
local toasts: { TextLabel } = {}
local pulseTween: Tween? = nil

function HudController:Toast(text: string, kind: string?)
	local template = el.ToastTemplate :: TextLabel
	local toast = template:Clone()
	toast.Name = "Toast"
	toast.Text = text
	toast.TextColor3 = TOAST_COLORS[kind or "Info"] or TOAST_COLORS.Info
	toast.Visible = true
	toast.LayoutOrder = os.clock() * 100 // 1
	toast.Parent = template.Parent
	table.insert(toasts, toast)
	while #toasts > MAX_TOASTS do
		table.remove(toasts, 1):Destroy()
	end
	task.delay(TOAST_SECONDS, function()
		if toast.Parent then
			local tween = TweenService:Create(toast, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 })
			tween:Play()
			tween.Completed:Wait()
			local i = table.find(toasts, toast)
			if i then
				table.remove(toasts, i)
			end
			toast:Destroy()
		end
	end)
end

local announceToken = 0
local function announce(text: string)
	announceToken += 1
	local token = announceToken
	local label = el.Announcement :: TextLabel
	label.Text = text
	label.Visible = true
	label.TextTransparency = 0
	Ui.sound("Announce")
	task.delay(5, function()
		if token == announceToken then
			label.Visible = false
		end
	end)
end

-- Pulses a HUD button (tutorial pointer for UI targets).
local highlighted: string? = nil
function HudController:Highlight(name: string?)
	if name == highlighted then
		return
	end
	highlighted = name
	if pulseTween then
		pulseTween:Cancel()
		pulseTween = nil
	end
	local button = el.NextToolButton :: TextButton
	button.Rotation = 0
	if name == "NextTool" then
		pulseTween = TweenService:Create(button, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 3 })
		pulseTween:Play()
	end
end

local function render(data)
	el.Cash.Text = Format.cash(data.Cash)
	el.Income.Text = `+{Format.cash(data.IncomePerSec)}/s`

	local fraction = if data.Capacity > 0 then math.clamp(data.Backpack / data.Capacity, 0, 1) else 0
	el.BackpackFill.Size = UDim2.fromScale(fraction, 1)
	el.BackpackAmount.Text = `{Format.number(data.Backpack)} / {Format.number(data.Capacity)}`
	el.BackpackFull.Visible = fraction >= 1
	el.BackpackFill.BackgroundColor3 = if fraction >= 1 then Color3.fromRGB(255, 120, 110) else Color3.fromRGB(233, 201, 139)

	local nextTier = data.ToolTier + 1
	if nextTier <= Tools.MaxTier then
		local def = Tools.get(nextTier)
		local affordable = BigNum.gte(data.Cash, def.Price)
		el.NextTool.Visible = true
		el.NextToolButton.Text = `Buy {def.Name}  {Format.cash(def.Price)}`
		el.NextToolButton.BackgroundColor3 = if affordable then Color3.fromRGB(60, 203, 114) else Color3.fromRGB(90, 96, 120)
		el.NextToolHint.Text = if def.IsVehicle then `Next: vehicle! radius {def.Radius}` else `Next tool: radius {def.Radius}, holds {Format.number(def.Capacity)}`
	else
		el.NextTool.Visible = false
	end

	local current = Tools.get(data.EffectiveTier)
	el.DriveButton.Visible = current.IsVehicle
	el.DriveButton.Text = if data.InVehicle then "Exit" else "🚗 Drive"
	el.AutoButton.Visible = data.Gamepasses.AutoSweep == true
	el.AutoButton.Text = if data.AutoSweep then "Auto: ON" else "Auto: OFF"
end

local function renderServer()
	local eventState = State.server("EventState") or "Filling"
	local endsAt = State.server("EventEndsAt") or 0
	local left = math.max(0, endsAt - State.now())
	if eventState == "Countdown" then
		el.MoonLabel.Text = `☄️ Meteor Shower in {Format.time(left)}`
		el.MoonFill.Size = UDim2.fromScale(1, 1)
	elseif eventState == "Shower" then
		el.MoonLabel.Text = `☄️ METEOR SHOWER {Format.time(left)}`
		el.MoonFill.Size = UDim2.fromScale(math.clamp(left / 60, 0, 1), 1)
	else
		local clean = State.server("MoonClean") or 0
		el.MoonLabel.Text = `🌙 Moon Clean {Format.percent(clean)}`
		el.MoonFill.Size = UDim2.fromScale(clean, 1)
	end
end

local function renderBoosts()
	local template = el.BoostTemplate :: TextLabel
	for _, child in template.Parent:GetChildren() do
		if child:IsA("TextLabel") and child ~= template then
			child:Destroy()
		end
	end
	local now = State.now()
	local entries = {}
	for _, tier in LUCK_TIERS do
		local ends = State.server("Luck" .. tier) or 0
		if ends > now then
			table.insert(entries, `🍀 {tier}x Luck {Format.time(ends - now)}`)
		end
	end
	local data = State.data
	if data and (data.Boosts.Cash2x or 0) > now then
		table.insert(entries, `💰 2x Cash {Format.time(data.Boosts.Cash2x - now)}`)
	end
	for i, text in entries do
		local label = template:Clone()
		label.Name = "Boost"
		label.Text = text
		label.LayoutOrder = i
		label.Visible = true
		label.Parent = template.Parent
	end
end

function HudController:Init(controllers)
	C = controllers
	hud = Ui.screen("Hud")
	el.Cash = Ui.find(hud, "CashPanel.Cash")
	el.Income = Ui.find(hud, "CashPanel.Income")
	el.BackpackFill = Ui.find(hud, "BackpackPanel.Bar.Fill")
	el.BackpackAmount = Ui.find(hud, "BackpackPanel.Bar.Amount")
	el.BackpackFull = Ui.find(hud, "BackpackPanel.Full")
	el.MoonLabel = Ui.find(hud, "MoonPanel.Label")
	el.MoonFill = Ui.find(hud, "MoonPanel.Bar.Fill")
	el.Announcement = Ui.find(hud, "Announcement")
	el.BoostTemplate = Ui.find(hud, "Boosts.Template")
	el.NextTool = Ui.find(hud, "NextTool")
	el.NextToolButton = Ui.find(hud, "NextTool.Button")
	el.NextToolHint = Ui.find(hud, "NextTool.Hint")
	el.DriveButton = Ui.find(hud, "Actions.DriveButton")
	el.AutoButton = Ui.find(hud, "Actions.AutoButton")
	el.SweepButton = Ui.find(hud, "Actions.SweepButton")
	el.ToastTemplate = Ui.find(hud, "Toasts.Template")
end

function HudController:GetSweepButton(): TextButton
	return el.SweepButton
end

function HudController:Start()
	el.SweepButton.Visible = UserInputService.TouchEnabled

	Ui.button(Ui.find(hud, "Menu.ShopButton"), function()
		C.ShopController:Toggle()
	end)
	Ui.button(Ui.find(hud, "Menu.IndexButton"), function()
		C.IndexController:Toggle()
	end)
	Ui.button(Ui.find(hud, "Menu.RebirthButton"), function()
		C.RebirthController:Toggle()
	end)
	Ui.button(el.NextToolButton, function()
		local ok, message = Net.func("BuyNextTool"):InvokeServer()
		HudController:Toast(message or "", if ok then "Good" else "Bad")
	end)
	Ui.button(el.DriveButton, function()
		local ok, message = Net.func("ToggleVehicle"):InvokeServer()
		if not ok and message then
			HudController:Toast(message, "Bad")
		end
	end)
	Ui.button(el.AutoButton, function()
		local data = State.data
		if data then
			Net.event("SetAutoSweep"):FireServer(not data.AutoSweep)
		end
	end)

	Net.event("Notify").OnClientEvent:Connect(function(text: string, kind: string?)
		HudController:Toast(text, kind)
		if kind == "Sell" or kind == "Egg" then
			Ui.sound(kind)
		end
	end)
	Net.event("Announce").OnClientEvent:Connect(announce)

	State.observe(render)
	State.serverState.AttributeChanged:Connect(renderServer)
	renderServer()
	while true do
		renderBoosts()
		renderServer()
		task.wait(0.5)
	end
end

return HudController
