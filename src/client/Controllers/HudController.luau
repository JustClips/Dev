--!strict
-- Main HUD (stud style, see docs/UI_STYLE.md): left rail (Shop / Index / Rebirth),
-- top teleport pills (Base / Sell / Zones), Moon Clean bar + event, boost chips,
-- wallet (cash + backpack) bottom-left, next-tool card + Auto on the right,
-- the mobile SWEEP button, toasts and server announcements.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local BigNum = require(Shared.BigNum)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Rewards = require(Shared.Config.Rewards)
local Tools = require(Shared.Config.Tools)
local Zones = require(Shared.Config.Zones)

local MAX_TOASTS = 4
local TOAST_SECONDS = 3
local TOAST_COLORS: { [string]: Color3 } = {
	Good = Color3.fromRGB(124, 245, 200),
	Bad = Color3.fromRGB(255, 120, 130),
	Sell = Color3.fromRGB(255, 200, 60),
	Egg = Color3.fromRGB(255, 190, 255),
	Info = Color3.fromRGB(255, 255, 255),
}
local LUCK_TIERS = { 16, 8, 4, 2 }
local GREEN = Color3.fromRGB(61, 220, 90)
local GREY = Color3.fromRGB(166, 174, 194)
local DANGER = Color3.fromRGB(255, 77, 94)
local LOCKED = Color3.fromRGB(255, 150, 160) -- readable on the blue zone rows
local SAND = Color3.fromRGB(233, 201, 139)
local NAVY = Color3.fromRGB(20, 26, 51)
local MINT = Color3.fromRGB(124, 245, 200)
local ZONE_ORDER = { "Landing", "Crater", "DarkSide", "Mars", "Europa" }

local HudController = {}

local C: any
local hud: ScreenGui
local el: { [string]: any } = {}
local toasts: { TextLabel } = {}
local pulseTween: Tween? = nil

function HudController:Toast(text: string, kind: string?)
	if text == "" then
		return
	end
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
	if not Ui.reducedMotion() then
		local pop = Instance.new("UIScale")
		pop.Scale = 0.7
		pop.Parent = toast
		TweenService:Create(pop, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	task.delay(TOAST_SECONDS, function()
		if toast.Parent then
			local stroke = toast:FindFirstChildOfClass("UIStroke")
			local fade = TweenInfo.new(0.35)
			TweenService:Create(toast, fade, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			if stroke then
				TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
			end
			task.wait(0.35)
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
	el.AnnouncementText.Text = text
	el.Announcement.Visible = true
	Ui.sound("Announce")
	task.delay(5, function()
		if token == announceToken then
			el.Announcement.Visible = false
		end
	end)
end

-- Pulses a HUD element (tutorial pointer for UI targets).
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
	local button = el.NextToolButton :: GuiButton
	button.Rotation = 0
	if name == "NextTool" and not Ui.reducedMotion() then
		pulseTween = TweenService:Create(button, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 3 })
		pulseTween:Play()
	end
end

local function setButton(button: GuiButton, enabled: boolean, color: Color3)
	-- Stays clickable: the server answers "need $X" which is more useful than nothing.
	button.BackgroundColor3 = if enabled then color else GREY
end

local function renderZones(data)
	for _, zoneId in ZONE_ORDER do
		local row = el.ZoneRows[zoneId]
		local zone = Zones.ById[zoneId]
		if row and zone then
			local unlocked = zoneId == "Landing" or data.ZonesUnlocked[zoneId] == true
			local price = row:FindFirstChild("Price") :: TextLabel
			local rowIcon = row:FindFirstChild("Icon") :: ImageLabel
			rowIcon.Image = AssetLibrary.image(if unlocked then "Icon_Zones" else "Icon_Lock")
			if unlocked then
				price.Text = "Go!"
				price.TextColor3 = GREEN
			elseif zone.RequiredRebirths > data.Rebirths then
				price.Text = `Rebirth {zone.RequiredRebirths}`
				price.TextColor3 = LOCKED
			else
				price.Text = Format.cash(zone.UnlockCost)
				price.TextColor3 = if BigNum.gte(data.Cash, zone.UnlockCost) then GREEN else LOCKED
			end
		end
	end
end

-- One line telling new players what to do next (server-confirmed tutorial steps).
local HINTS: { [string]: string } = {
	Sweep = "Sweep the moon dust to find an egg!",
	Egg = "You found an egg! Walk into it to pick it up.",
	Base = "Carry the egg home to your hatchery!",
	Place = "Press F at your hatchery to put the egg in an incubator!",
	Hatching = "Your egg is hatching...",
	Open = "Your egg is ready! Press E on it to open it.",
	PlacePet = "Open your Bag (3) and place your pet on your base!",
	Sell = "Sell your dust at the Rocket for cash!",
	Shop = "Buy the Broom: it sweeps faster!",
}

-- After the tutorial: only nudges for things that are waiting on the player.
local function nextStepHint(data): string?
	for _, entry in data.Hatching do
		if entry.EndsAt <= State.now() then
			return "An egg is ready! Open it at your hatchery."
		end
	end
	return nil
end

local function render(data)
	el.Cash.Text = Format.cash(data.Cash)
	el.Income.Text = `+{Format.cash(data.IncomePerSec)}/s`

	local fraction = if data.Capacity > 0 then math.clamp(data.Backpack / data.Capacity, 0, 1) else 0
	el.BackpackFill.Size = UDim2.fromScale(math.max(fraction, 0.04), 1)
	el.BackpackAmount.Text = `{Format.number(data.Backpack)} / {Format.number(data.Capacity)}`
	el.BackpackFull.Visible = fraction >= 1
	el.BackpackFill.BackgroundColor3 = if fraction >= 1 then DANGER else SAND

	local nextTier = data.ToolTier + 1
	if nextTier <= Tools.MaxTier then
		local def = Tools.get(nextTier)
		local affordable = BigNum.gte(data.Cash, def.Price)
		el.NextTool.Visible = true
		el.NextToolName.Text = def.Name
		el.NextToolIcon.Image = AssetLibrary.toolIcon(def.Id)
		Ui.setText(el.NextToolButton, `Buy {Format.cash(def.Price)}`)
		setButton(el.NextToolButton, affordable, GREEN)
		el.NextToolHint.Text = `Sweeps {def.Radius} wide, holds {Format.number(def.Capacity)}`
	else
		el.NextTool.Visible = false
	end

	el.AutoButton.Visible = data.Gamepasses.AutoSweep == true
	Ui.setText(el.AutoButton, if data.AutoSweep then "Auto: ON" else "Auto: OFF")
	el.AutoButton.BackgroundColor3 = if data.AutoSweep then Color3.fromRGB(30, 158, 120) else NAVY

	if el.ZonePicker.Visible then
		renderZones(data)
	end

	local hint = HINTS[data.TutorialStep]
	if not hint and data.TutorialStep == "Done" then
		hint = nextStepHint(data)
	end
	el.Hint.Visible = hint ~= nil
	if hint then
		el.HintText.Text = hint
	end
end

local function renderServer()
	local eventState = State.server("EventState") or "Filling"
	local endsAt = State.server("EventEndsAt") or 0
	local left = math.max(0, endsAt - State.now())
	if eventState == "Countdown" then
		el.MoonLabel.Text = `Meteor Shower in {Format.time(left)}`
		el.MoonFill.Size = UDim2.fromScale(1, 1)
		el.MoonFill.BackgroundColor3 = Color3.fromRGB(255, 154, 60)
		el.MoonIcon.Image = AssetLibrary.image("Icon_Meteor")
	elseif eventState == "Shower" then
		el.MoonLabel.Text = `METEOR SHOWER {Format.time(left)}`
		el.MoonFill.Size = UDim2.fromScale(math.clamp(left / 60, 0, 1), 1)
		el.MoonFill.BackgroundColor3 = Color3.fromRGB(255, 154, 60)
		el.MoonIcon.Image = AssetLibrary.image("Icon_Meteor")
	else
		local clean = State.server("MoonClean") or 0
		el.MoonLabel.Text = `Moon Clean {Format.percent(clean)}`
		el.MoonFill.Size = UDim2.fromScale(math.max(clean, 0.03), 1)
		el.MoonFill.BackgroundColor3 = MINT
		el.MoonIcon.Image = AssetLibrary.image("Icon_Star")
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
	local entries: { { string } } = {}
	for _, tier in LUCK_TIERS do
		local ends = State.server("Luck" .. tier) or 0
		if ends > now then
			table.insert(entries, { `{tier}x Server Luck  {Format.time(ends - now)}`, "Icon_Luck" })
		end
	end
	local event = Rewards.activeEvent(now)
	if event then
		table.insert(entries, { `{event.Name}: {event.LuckMult}x Luck  {Format.time(event.EndsAt - now)}`, "Icon_Event" })
	end
	local data = State.data
	if data and (data.Boosts.Cash2x or 0) > now then
		table.insert(entries, { `2x Cash  {Format.time(data.Boosts.Cash2x - now)}`, "Icon_Cash" })
	end
	if data and (data.Boosts.Luck2x or 0) > now then
		table.insert(entries, { `2x Egg Luck  {Format.time(data.Boosts.Luck2x - now)}`, "Icon_PotionLuck" })
	end
	if data and (data.Boosts.Speed or 0) > now then
		table.insert(entries, { `Speed  {Format.time(data.Boosts.Speed - now)}`, "Icon_PotionSpeed" })
	end
	for i, entry in entries do
		local label = template:Clone()
		label.Name = "Boost"
		label.Text = entry[1]
		local icon = label:FindFirstChild("Icon") :: ImageLabel?
		if icon then
			icon.Image = AssetLibrary.image(entry[2])
		end
		label.LayoutOrder = i
		label.Visible = true
		label.Parent = template.Parent
	end
end

local function teleport(target: string)
	el.ZonePicker.Visible = false
	local ok, message = Net.func("Teleport"):InvokeServer(target)
	if message and message ~= "" then
		HudController:Toast(message, if ok then "Info" else "Bad")
	end
end

-- Phones: the move thumbstick owns the bottom-left corner, so the wallet goes top-left.
local function layoutForTouch()
	if not UserInputService.TouchEnabled then
		return
	end
	el.Wallet.AnchorPoint = Vector2.new(0, 0)
	el.Wallet.Position = UDim2.new(0, 14, 0, 6)
	local layout = el.Wallet:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.VerticalAlignment = Enum.VerticalAlignment.Top
	end
	-- Phones are short: the rail becomes two columns under the wallet.
	local list = el.Rail:FindFirstChildOfClass("UIListLayout")
	if list then
		list:Destroy()
	end
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(84, 84)
	grid.CellPadding = UDim2.fromOffset(12, 26)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = el.Rail
	el.Rail.Size = UDim2.fromOffset(180, 330)
	el.Rail.AnchorPoint = Vector2.new(0, 0)
	el.Rail.Position = UDim2.new(0, 14, 0, math.floor(6 + 140 * Ui.scale()))
	el.SweepButton.Visible = true
	local boosts = (el.BoostTemplate :: Instance).Parent :: Frame
	boosts.AnchorPoint = Vector2.new(1, 0)
	boosts.Position = UDim2.new(1, -14, 0, 6)
	local boostLayout = boosts:FindFirstChildOfClass("UIListLayout")
	if boostLayout then
		boostLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	end
end

function HudController:Init(controllers)
	C = controllers
	hud = Ui.screen("Hud")
	el.Rail = Ui.find(hud, "Rail")
	el.Wallet = Ui.find(hud, "Wallet")
	el.Cash = Ui.find(hud, "Wallet.CashPanel.Cash")
	el.Income = Ui.find(hud, "Wallet.CashPanel.Income")
	el.PlusButton = Ui.find(hud, "Wallet.CashPanel.PlusButton")
	el.BackpackFill = Ui.find(hud, "Wallet.BackpackPanel.Bar.Fill")
	el.BackpackAmount = Ui.find(hud, "Wallet.BackpackPanel.Bar.Amount")
	el.BackpackFull = Ui.find(hud, "Wallet.BackpackPanel.Full")
	el.MoonLabel = Ui.find(hud, "MoonPanel.Label")
	el.MoonFill = Ui.find(hud, "MoonPanel.Bar.Fill")
	el.MoonIcon = Ui.find(hud, "MoonPanel.Icon")
	el.Announcement = Ui.find(hud, "Announcement")
	el.AnnouncementText = Ui.find(hud, "Announcement.Text")
	el.BoostTemplate = Ui.find(hud, "Boosts.Template")
	el.NextTool = Ui.find(hud, "Right.NextTool")
	el.NextToolButton = Ui.find(hud, "Right.NextTool.Button")
	el.NextToolHint = Ui.find(hud, "Right.NextTool.Hint")
	el.NextToolName = Ui.find(hud, "Right.NextTool.ToolName")
	el.NextToolIcon = Ui.find(hud, "Right.NextTool.Icon")
	el.AutoButton = Ui.find(hud, "Right.AutoButton")
	el.SweepButton = Ui.find(hud, "SweepButton")
	el.ToastTemplate = Ui.find(hud, "Toasts.Template")
	el.ZonePicker = Ui.find(hud, "ZonePicker")
	el.Hint = Ui.find(hud, "Hint")
	el.HintText = Ui.find(hud, "Hint.Text")
	el.Combo = Ui.find(hud, "Combo")
	el.ComboFill = Ui.find(hud, "Combo.Bar.Fill")
	el.ComboLabel = Ui.find(hud, "Combo.Label")
	el.ZoneRows = {}
	for _, zoneId in ZONE_ORDER do
		el.ZoneRows[zoneId] = Ui.find(hud, "ZonePicker.List.Zone_" .. zoneId)
	end
end

-- Sweep combo meter (x1 -> x3 cash). Shows while you keep sweeping, hides after a pause.
local comboToken = 0
function HudController:SetCombo(combo: number)
	comboToken += 1
	local token = comboToken
	el.Combo.Visible = combo > 1.05
	el.ComboLabel.Text = string.format("COMBO x%.1f", combo)
	el.ComboFill.Size = UDim2.fromScale(math.clamp((combo - 1) / 2, 0, 1), 1)
	task.delay(1.8, function()
		if comboToken == token then
			el.Combo.Visible = false
		end
	end)
end

function HudController:GetSweepButton(): GuiButton
	return el.SweepButton
end

function HudController:Start()
	layoutForTouch()

	Ui.button(Ui.find(hud, "Rail.ShopButton"), function()
		C.ShopController:Toggle()
	end)
	Ui.button(Ui.find(hud, "Rail.IndexButton"), function()
		C.IndexController:Toggle()
	end)
	Ui.button(Ui.find(hud, "Rail.UpgradesButton"), function()
		C.UpgradeController:Toggle()
	end)
	Ui.button(Ui.find(hud, "Rail.RebirthButton"), function()
		C.RebirthController:Toggle()
	end)
	Ui.button(el.PlusButton, function()
		C.ShopController:Open("Cash")
	end)
	Ui.button(Ui.find(hud, "Pills.BaseButton"), function()
		teleport("Base")
	end)
	Ui.button(Ui.find(hud, "Pills.SellButton"), function()
		teleport("Rocket")
	end)
	Ui.button(Ui.find(hud, "Pills.ZonesButton"), function()
		el.ZonePicker.Visible = not el.ZonePicker.Visible
		if el.ZonePicker.Visible then
			Ui.popFrame(el.ZonePicker)
		end
		if el.ZonePicker.Visible and State.data then
			renderZones(State.data)
		end
	end)
	for zoneId, row in el.ZoneRows do
		Ui.button(row, function()
			teleport(if zoneId == "Landing" then "Rocket" else zoneId)
		end)
	end
	Ui.button(el.NextToolButton, function()
		local ok, message = Net.func("BuyNextTool"):InvokeServer()
		HudController:Toast(message or "", if ok then "Good" else "Bad")
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
