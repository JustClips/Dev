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
local Items = require(Shared.Config.Items)
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

	-- The step card above the hotbar belongs to TutorialController.
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

-- Boost chips (bottom right): icon + "2x 14:52", no box. Chips are kept by key so hover
-- survives the once-a-second refresh. Hover (or tap on a phone) explains the boost.
type BoostEntry = { key: string, image: string, label: string, endsAt: number, title: string, text: string }
local boostChips: { [string]: TextButton } = {}
local boostInfo: { [string]: BoostEntry } = {}
local tipKey: string? = nil
local tipUntil = 0

local function renderTip()
	local tip = el.BoostTip :: Frame
	local entry = tipKey and boostInfo[tipKey]
	if not entry or (tipUntil > 0 and os.clock() > tipUntil) then
		tip.Visible = false
		tipKey = nil
		return
	end
	tip.Visible = true
	;(tip:FindFirstChild("Title") :: TextLabel).Text = entry.title
	;(tip:FindFirstChild("Text") :: TextLabel).Text = `{entry.text}\n{Format.countdown(entry.endsAt - State.now())} left`
	-- Sit just above the chips (below them on phones, where the chips are top right).
	local top, bottom, right = math.huge, -math.huge, 0
	for _, chip in boostChips do
		top = math.min(top, chip.AbsolutePosition.Y)
		bottom = math.max(bottom, chip.AbsolutePosition.Y + chip.AbsoluteSize.Y)
		right = math.max(right, chip.AbsolutePosition.X + chip.AbsoluteSize.X)
	end
	if top == math.huge then
		return
	end
	if UserInputService.TouchEnabled then
		tip.AnchorPoint = Vector2.new(1, 0)
		tip.Position = UDim2.fromOffset(right, bottom + 6)
	else
		tip.AnchorPoint = Vector2.new(1, 1)
		tip.Position = UDim2.fromOffset(right, top - 6)
	end
end

local function renderBoosts()
	local template = el.BoostTemplate :: TextButton
	local now = State.now()
	local entries: { BoostEntry } = {}
	local function add(key: string, image: string, label: string, endsAt: number, title: string, text: string)
		table.insert(entries, { key = key, image = image, label = label, endsAt = endsAt, title = title, text = text })
	end
	for _, tier in LUCK_TIERS do -- highest first
		local ends = State.server("Luck" .. tier) or 0
		if ends > now then
			-- only the best server luck counts
			add("ServerLuck", "Icon_Luck", `{tier}x`, ends, `{tier}x Server Luck`, `Everyone on this server finds rarer eggs, mutations and Huge pets {tier}x more often.`)
			break
		end
	end
	local event = Rewards.activeEvent(now)
	if event then
		add("Event", "Icon_Event", `{event.LuckMult}x`, event.EndsAt, event.Name, `Live event: {event.LuckMult}x egg luck for everyone.`)
	end
	local data = State.data
	if data and (data.Boosts.Cash2x or 0) > now then
		add("Cash2x", "Icon_Cash", "2x", data.Boosts.Cash2x, "2x Cash", "Your pets and selling earn double cash.")
	end
	if data and (data.Boosts.Luck2x or 0) > now then
		add("Luck2x", "Icon_PotionLuck", `{Items.LuckMult}x`, data.Boosts.Luck2x, "Luck Potion", `Your eggs hatch rarer pets {Items.LuckMult}x more often, and you find bigger eggs.`)
	end
	if data and (data.Boosts.Speed or 0) > now then
		add("Speed", "Icon_PotionSpeed", `+{Items.SpeedBonus}`, data.Boosts.Speed, "Speed Potion", `You run {Items.SpeedBonus} faster.`)
	end
	local seen = {}
	for i, entry in entries do
		seen[entry.key] = true
		boostInfo[entry.key] = entry
		local chip = boostChips[entry.key]
		if not chip then
			local newChip = template:Clone() :: TextButton
			newChip.Name = entry.key
			newChip.Visible = true
			local key = entry.key
			newChip.MouseEnter:Connect(function()
				tipKey, tipUntil = key, 0
				renderTip()
			end)
			newChip.MouseLeave:Connect(function()
				if tipKey == key and tipUntil == 0 then
					tipKey = nil
					renderTip()
				end
			end)
			newChip.Activated:Connect(function()
				-- Tap on phones: show for a few seconds (tap again to hide).
				if tipKey == key and tipUntil > 0 then
					tipKey = nil
				else
					tipKey, tipUntil = key, os.clock() + 4
				end
				renderTip()
			end)
			newChip.Parent = template.Parent
			boostChips[entry.key] = newChip
			chip = newChip
		end
		local c = chip :: TextButton
		c.Text = `{entry.label} {Format.countdown(entry.endsAt - now)}`
		c.LayoutOrder = i
		local icon = c:FindFirstChild("Icon") :: ImageLabel?
		if icon then
			icon.Image = AssetLibrary.image(entry.image)
		end
	end
	for key, chip in boostChips do
		if not seen[key] then
			chip:Destroy()
			boostChips[key] = nil
			boostInfo[key] = nil
		end
	end
	renderTip()
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
	-- Phones are short: the rail sits right under the wallet.
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
	el.BoostTip = Ui.find(hud, "BoostTip")
	el.NextTool = Ui.find(hud, "Right.NextTool")
	el.NextToolButton = Ui.find(hud, "Right.NextTool.Button")
	el.NextToolHint = Ui.find(hud, "Right.NextTool.Hint")
	el.NextToolName = Ui.find(hud, "Right.NextTool.ToolName")
	el.NextToolIcon = Ui.find(hud, "Right.NextTool.Icon")
	el.AutoButton = Ui.find(hud, "Right.AutoButton")
	el.SweepButton = Ui.find(hud, "SweepButton")
	el.ToastTemplate = Ui.find(hud, "Toasts.Template")
	el.ZonePicker = Ui.find(hud, "ZonePicker")
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
