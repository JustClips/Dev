--!strict
-- Main HUD (stud style, see docs/UI_STYLE.md): left rail (Shop / Index / Rebirth),
-- top teleport pills (Base / Sell / Zones), Moon Clean bar + event, boost chips,
-- wallet (cash + bag) bottom-left, Auto Sweep / Auto Sell switches on the right,
-- toasts and server announcements.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Admin = require(Shared.Config.Admin)
local AssetLibrary = require(Shared.AssetLibrary)
local BigNum = require(Shared.BigNum)
local Format = require(Shared.Format)
local Economy = require(Shared.Config.Economy)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Rewards = require(Shared.Config.Rewards)
local Weather = require(Shared.Config.Weather)
local Zones = require(Shared.Config.Zones)

local MAX_TOASTS = 4
local TOAST_SECONDS = 3
local TOAST_COLORS: { [string]: Color3 } = {
	Good = Color3.fromRGB(124, 255, 140),
	Bad = Color3.fromRGB(255, 92, 104),
	Sell = Color3.fromRGB(255, 214, 72),
	Egg = Color3.fromRGB(255, 170, 255),
	Rare = Color3.fromRGB(255, 205, 60), -- rare finds (leaf drops, treasure)
	Info = Color3.fromRGB(255, 255, 255),
}
local LUCK_TIERS = { 16, 8, 4, 2 }
local GREEN = Color3.fromRGB(61, 220, 90)
local DANGER = Color3.fromRGB(255, 77, 94)
local LOCKED = Color3.fromRGB(255, 150, 160) -- readable on the blue zone rows
local LEAF = Color3.fromRGB(255, 154, 60)
local NAVY = Color3.fromRGB(20, 26, 51)
local MINT = Color3.fromRGB(139, 224, 78) -- leaf green: the World Cleaned bar
local ZONE_ORDER = { "Landing", "Crater", "DarkSide", "Mars", "Europa" }

local HudController = {}

local C: any
local hud: ScreenGui
local el: { [string]: any } = {}
local toasts: { Frame } = {}
local pulseTween: Tween? = nil

local TOAST_ICONS: { [string]: string } = {
	Sell = "Icon_Cash",
	Egg = "Icon_Egg",
	Rare = "Icon_Gift",
}

-- Bold outlined text under the Moon bar, with an icon for cash and eggs. The same message
-- again while it's still up bumps a "x2" counter instead of stacking a copy.
function HudController:Toast(text: string, kind: string?)
	if text == "" then
		return
	end
	local k = kind or "Info"
	for _, existing in toasts do
		if existing:GetAttribute("Message") == text and existing.Parent then
			local n = (existing:GetAttribute("Count") or 1) + 1
			existing:SetAttribute("Count", n)
			existing:SetAttribute("Until", os.clock() + TOAST_SECONDS)
			local count = existing:FindFirstChild("Count") :: TextLabel
			count.Text = `x{n}`
			count.Visible = true
			local pop = existing:FindFirstChild("Pop") :: UIScale?
			if pop and not Ui.reducedMotion() then
				pop.Scale = 1.18
				TweenService:Create(pop, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
			return
		end
	end
	if k == "Bad" then
		Ui.sound("Error")
	end
	local template = el.ToastTemplate :: Frame
	local toast = template:Clone()
	toast.Name = "Toast"
	toast:SetAttribute("Message", text)
	toast:SetAttribute("Until", os.clock() + TOAST_SECONDS)
	local label = toast:FindFirstChild("Text") :: TextLabel
	label.Text = text
	label.TextColor3 = TOAST_COLORS[k] or TOAST_COLORS.Info
	local iconName = TOAST_ICONS[k]
	local iconLabel = toast:FindFirstChild("Icon") :: ImageLabel
	iconLabel.Visible = iconName ~= nil
	if iconName then
		iconLabel.Image = AssetLibrary.image(iconName)
	end
	toast.Visible = true
	toast.LayoutOrder = os.clock() * 100 // 1
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Scale = if Ui.reducedMotion() then 1 else 0.5
	pop.Parent = toast
	toast.Parent = template.Parent
	TweenService:Create(pop, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	table.insert(toasts, toast)
	while #toasts > MAX_TOASTS do
		table.remove(toasts, 1):Destroy()
	end
	task.spawn(function()
		while toast.Parent and os.clock() < (toast:GetAttribute("Until") or 0) do
			task.wait(0.1)
		end
		if not toast.Parent then
			return
		end
		local fade = TweenInfo.new(0.3)
		for _, child in toast:GetDescendants() do
			if child:IsA("TextLabel") then
				TweenService:Create(child, fade, { TextTransparency = 1 }):Play()
			elseif child:IsA("ImageLabel") then
				TweenService:Create(child, fade, { ImageTransparency = 1 }):Play()
			elseif child:IsA("UIStroke") then
				TweenService:Create(child, fade, { Transparency = 1 }):Play()
			end
		end
		TweenService:Create(pop, fade, { Scale = 0.85 }):Play()
		task.wait(0.3)
		local i = table.find(toasts, toast)
		if i then
			table.remove(toasts, i)
		end
		toast:Destroy()
	end)
end

local layout: (number, boolean) -> ()

local announceToken = 0
local GLOBAL_COLOR = Color3.fromRGB(255, 126, 182) -- rare hatches from other servers
local ANNOUNCE_COLOR: Color3? = nil
local function announce(text: string, kind: string?)
	announceToken += 1
	local token = announceToken
	ANNOUNCE_COLOR = ANNOUNCE_COLOR or el.AnnouncementText.TextColor3
	el.AnnouncementText.TextColor3 = if kind == "Global" then GLOBAL_COLOR else ANNOUNCE_COLOR :: Color3
	el.AnnouncementText.Text = text
	el.Announcement.Visible = true
	layout(Ui.scale(), Ui.compact()) -- toasts move down under it
	Ui.sound("Announce")
	task.delay(5, function()
		if token == announceToken then
			el.Announcement.Visible = false
			layout(Ui.scale(), Ui.compact())
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
	local button = Ui.find(Ui.screen("BasePanels"), "Buttons.ToolsButton") :: GuiButton
	button.Rotation = 0
	if name == "Tools" and not Ui.reducedMotion() then
		pulseTween = TweenService:Create(button, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 3 })
		pulseTween:Play()
	end
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

-- Auto Sweep / Auto Sell switch: shown once you own the pass, green ON tag or grey OFF.
local function setToggle(button: GuiButton, owned: boolean, on: boolean)
	button.Visible = owned
	local state = button:FindFirstChild("State") :: Frame?
	local label = state and state:FindFirstChild("Label") :: TextLabel?
	if state and label then
		state.BackgroundColor3 = if on then GREEN else Color3.fromRGB(181, 186, 198)
		label.Text = if on then "ON" else "OFF"
	end
	button.BackgroundColor3 = if on then Color3.fromRGB(30, 120, 70) else NAVY
end

-- New players see the left rail fill in as the tutorial goes (Dev, 2026-10-30: too many
-- buttons at once on phones). Shop is always there; Index after the first pet, Upgrades
-- at the step that uses it, Rebirth / Daily / Gifts / Spin once the tutorial is done.
local STEP_ORDER = { Sweep = 1, Egg = 2, Base = 3, Place = 4, Hatching = 5, Open = 6, PlacePet = 7, Sell = 8, Shop = 9, Upgrade = 10, Wheel = 11 }
local function revealRail(data)
	local step = STEP_ORDER[data.TutorialStep] or 99
	local done = step == 99 or data.Rebirths > 0
	local show = {
		IndexButton = step >= 7,
		UpgradesButton = step >= 10,
		RebirthButton = done,
		RewardsButton = done,
		GiftsButton = done,
		SpinButton = done,
	}
	local changed = false
	for name, visible in show do
		local button = el.Rail:FindFirstChild(name) :: GuiObject?
		if button and button.Visible ~= visible then
			button.Visible = visible
			changed = true
		end
	end
	return changed
end

-- One line telling new players what to do next (server-confirmed tutorial steps).
local function render(data)
	el.Cash.Text = Format.cash(data.Cash)
	el.Income.Text = `+{Format.cash(data.IncomePerSec)}/s`

	local fraction = if data.Capacity > 0 then math.clamp(data.Backpack / data.Capacity, 0, 1) else 0
	el.BackpackFill.Size = UDim2.fromScale(math.max(fraction, 0.04), 1)
	el.BackpackAmount.Text = `{Format.number(data.Backpack)} / {Format.number(data.Capacity)}`
	el.BackpackFull.Visible = fraction >= 1
	-- Leave room for the FULL tag on the right end of the bar.
	el.BackpackAmount.Size = if fraction >= 1 then UDim2.new(1, -70, 1, 0) else UDim2.new(1, -12, 1, 0)
	el.BackpackFill.BackgroundColor3 = if fraction >= 1 then DANGER else LEAF

	setToggle(el.AutoButton, data.Gamepasses.AutoSweep == true, data.AutoSweep)
	setToggle(el.AutoSellButton, data.Gamepasses.SellAnywhere == true, data.AutoSell)
	revealRail(data)

	if el.ZonePicker.Visible then
		renderZones(data)
	end

	-- The step card above the hotbar belongs to TutorialController.
end

local ORANGE = Color3.fromRGB(255, 154, 60)
local lastClean = -1

local function renderServer()
	local eventState = State.server("EventState") or "Filling"
	local endsAt = State.server("EventEndsAt") or 0
	local left = math.max(0, endsAt - State.now())
	local fill = el.MoonFill :: Frame
	local function setFill(fraction: number)
		TweenService:Create(fill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(math.clamp(fraction, 0.02, 1), 1) }):Play()
	end
	if eventState == "Countdown" then
		el.MoonTitle.Text = "EGG RAIN IN"
		el.MoonTitle.TextColor3 = ORANGE
		el.MoonValue.Text = Format.time(left)
		setFill(1)
		fill.BackgroundColor3 = ORANGE
		el.MoonIcon.Image = AssetLibrary.image("Icon_Meteor")
	elseif eventState == "Shower" then
		el.MoonTitle.Text = "EGG RAIN!"
		el.MoonTitle.TextColor3 = ORANGE
		el.MoonValue.Text = Format.time(left)
		setFill(left / 60)
		fill.BackgroundColor3 = ORANGE
		el.MoonIcon.Image = AssetLibrary.image("Icon_Meteor")
	else
		local clean = State.server("MoonClean") or 0
		el.MoonTitle.Text = "WORLD CLEANED"
		el.MoonTitle.TextColor3 = Color3.new(1, 1, 1)
		el.MoonValue.Text = Format.percent(clean)
		setFill(clean)
		fill.BackgroundColor3 = MINT
		el.MoonIcon.Image = AssetLibrary.image("Icon_Star")
		-- A little bump on the panel each time the server's Moon gets cleaner.
		if lastClean >= 0 and math.floor(clean * 100) > math.floor(lastClean * 100) and not Ui.reducedMotion() then
			local scale = el.MoonScale :: UIScale
			scale.Scale = Ui.scale() * 1.06
			TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = Ui.scale() }):Play()
		end
		lastClean = clean
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
	-- endsAt 0 = no timer (friend boost lasts while they're here).
	;(tip:FindFirstChild("Text") :: TextLabel).Text = if entry.endsAt > 0
		then `{entry.text}\n{Format.countdown(entry.endsAt - State.now())} left`
		else entry.text
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
	local okEvents, adminEvents = pcall(function()
		return HttpService:JSONDecode(State.server("AdminEvents") or "[]")
	end)
	if not okEvents or type(adminEvents) ~= "table" then
		adminEvents = {}
	end
	local weather = Weather.ById[State.server("Weather") or ""]
	local weatherEnds = State.server("WeatherEndsAt") or 0
	if weather and weatherEnds > now then
		-- An admin weather event shows only here (one chip), titled as an admin event.
		local byAdmin = false
		for _, e in adminEvents do
			if e.Type == "Weather" and e.Value == weather.Id and (tonumber(e.EndsAt) or 0) > now then
				byAdmin = true
			end
		end
		local title = if byAdmin then `Admin event: {weather.Name}` else weather.Name
		add("Weather", "Icon_Weather_" .. weather.Id, Weather.chipLabel(weather), weatherEnds, title, weather.Blurb)
	end
	-- Special moons last the whole night.
	local moon = Weather.ById[State.server("Moon") or ""]
	local cycleStart = State.server("CycleStart")
	if moon and moon.Blurb ~= "" and type(cycleStart) == "number" then
		local cycles = math.floor((now - cycleStart) / Weather.CycleSeconds)
		local nightEnds = math.floor(cycleStart + (cycles + 1) * Weather.CycleSeconds)
		add("Moon", "Icon_Weather_" .. moon.Id, Weather.chipLabel(moon), nightEnds, moon.Name, moon.Blurb)
	end
	-- Admin events (AdminService), each its own chip. Weather ones already show as the
	-- weather chip above, so they don't get a second one.
	for _, e in adminEvents do
		local def = Admin.Events[e.Type]
		if def and e.Type ~= "Weather" and (tonumber(e.EndsAt) or 0) > now then
			local label = if def.Unit == "x" then `{e.Value}x` elseif def.Unit == "+" then `+{e.Value}` else ""
			local name = if label ~= "" then `{label} {def.Name}` else def.Name
			add("Admin" .. tostring(e.Id), def.Icon, label, e.EndsAt, `Admin event: {name}`, def.Blurb)
		end
	end
	local data = State.data
	if data and (data.Boosts.Cash3x or 0) > now then
		add("Cash3x", "Icon_PotionMegaCash", `{Items.MegaCashMult}x`, data.Boosts.Cash3x, "Mega Cash Potion", `Your pets and selling earn {Items.MegaCashMult}x cash.`)
	elseif data and (data.Boosts.Cash2x or 0) > now then
		add("Cash2x", "Icon_Cash", "2x", data.Boosts.Cash2x, "2x Cash", "Your pets and selling earn double cash.")
	end
	if data and (data.Boosts.Luck3x or 0) > now then
		add("Luck3x", "Icon_PotionSuperLuck", `{Items.SuperLuckMult}x`, data.Boosts.Luck3x, "Super Luck Potion", `Your eggs hatch rarer pets {Items.SuperLuckMult}x more often, and you find bigger eggs.`)
	elseif data and (data.Boosts.Luck2x or 0) > now then
		add("Luck2x", "Icon_PotionLuck", `{Items.LuckMult}x`, data.Boosts.Luck2x, "Luck Potion", `Your eggs hatch rarer pets {Items.LuckMult}x more often, and you find bigger eggs.`)
	end
	if data and (data.Boosts.Leaf2x or 0) > now then
		add("Leaf2x", "Icon_PotionLeaf", `{Items.LeafMult}x`, data.Boosts.Leaf2x, "Leaf Potion", `Every pile gives you {Items.LeafMult}x leaves.`)
	end
	if data and (data.Boosts.BigBag or 0) > now then
		add("BigBag", "Icon_PotionBag", `+{math.floor((Items.BigBagMult - 1) * 100 + 0.5)}%`, data.Boosts.BigBag, "Big Bag Potion", "Your bag holds more leaves.")
	end
	if data and (data.Boosts.Magnet or 0) > now then
		add("Magnet", "Icon_PotionMagnet", `+{Items.MagnetBonus}`, data.Boosts.Magnet, "Magnet Potion", "You grab coins and drops from much further away.")
	end
	-- Charms waiting for your next hatch (no timer).
	local charms = if data and data.Flags then data.Flags.Charms else nil
	if charms and (charms.Huge or 0) > 0 then
		add("CharmHuge", "Icon_HugeCharm", `x{charms.Huge}`, 0, "Huge Charm", `Your next hatch is {Items.HugeCharmMult}x more likely to be Huge.`)
	end
	if charms and (charms.Clover or 0) > 0 then
		add("CharmClover", "Icon_LuckyClover", `x{charms.Clover}`, 0, "Lucky Clover", "Your next hatch is 3x more likely to go up a rarity.")
	end
	if data and (data.Boosts.Speed or 0) > now then
		add("Speed", "Icon_PotionSpeed", `+{Items.SpeedBonus}`, data.Boosts.Speed, "Speed Potion", `You run {Items.SpeedBonus} faster.`)
	end
	-- Friend boost: +10% luck per friend in this server, no timer ("+20%").
	local friends = if data then math.min(data.FriendsHere or 0, Economy.FriendLuckMaxFriends) else 0
	if friends > 0 then
		local pct = math.floor(friends * Economy.FriendLuckPerFriend * 100 + 0.5)
		local each = math.floor(Economy.FriendLuckPerFriend * 100 + 0.5)
		add("Friends", "Icon_Group", `+{pct}%`, 0, "Friend Boost",
			`{friends} friend{if friends == 1 then "" else "s"} in this server: +{pct}% egg luck. Every friend here adds {each}%.`)
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
		local label = c:FindFirstChild("Label") :: TextLabel?
		if label then
			local left = if entry.endsAt > 0 then Format.countdown(entry.endsAt - now) else ""
			label.Text = if entry.label == "" then left elseif left == "" then entry.label else `{entry.label} {left}`
		end
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

-- Places the HUD clusters for the current scale. Offsets are not scaled by UIScale, so
-- stacked pieces (pills -> clean bar -> toasts) are spaced by scale here.
-- Phones (Ui.compact): the thumbstick owns the bottom-left corner and the jump button the
-- bottom-right, so the wallet goes top-left with the rail under it, the Eggs/Pets
-- buttons go top-right (BasePanelsController) with the boost chips under them.
-- The left rail and the right-hand stack (Eggs/Pets buttons, then Next Tool + Auto) are
-- centred on the same line, RAIL_CENTRE px from the screen's middle.
local RAIL_CENTRE = -30
-- Phones: how far the side button columns sit below their top spot (gui px before scale).
HudController.SIDE_DROP = 44
local SIDE_DROP = HudController.SIDE_DROP
local STACK_BUTTONS, STACK_GAP, STACK_RIGHT = 324, 16, 50

function HudController.rightStackTop(s: number): number
	return RAIL_CENTRE - math.ceil((STACK_BUTTONS + STACK_GAP + STACK_RIGHT) * s / 2)
end

layout = function(s: number, compact: boolean)
	local top = 6
	-- The pills row is as wide as the pills showing (the Free pill comes and goes).
	local shown = 0
	for _, child in el.Pills:GetChildren() do
		if child:IsA("GuiButton") and child.Visible then
			shown += 1
		end
	end
	el.Pills.Size = UDim2.fromOffset(math.max(1, shown) * 136 + math.max(0, shown - 1) * 12, el.Pills.Size.Y.Offset)
	local pillsH = math.ceil(52 * s)
	-- Pills go up into Roblox's top bar row when they fit between its buttons and the
	-- ADMIN button. Centred if they can be (Dev, 2026-10-30), otherwise moved right just
	-- past Roblox's buttons. Our settings gear sits under the top bar row, so it isn't in
	-- the way.
	local inset = GuiService.TopbarInset
	local shift = 0
	if inset.Height >= pillsH and hud.AbsoluteSize.X > 2 then
		local w = math.ceil(el.Pills.Size.X.Offset * s)
		local guiMid = hud.AbsolutePosition.X + hud.AbsoluteSize.X / 2
		local freeLeft = math.max(inset.Min.X, 104) + 8
		local freeRight = inset.Max.X - 8 - (if Admin.isAdmin(Players.LocalPlayer.UserId) then 100 else 0)
		local x0 = math.max(guiMid - w / 2, freeLeft)
		if x0 + w <= freeRight then
			top = -math.floor(inset.Height) + math.floor((inset.Height - pillsH) / 2)
			shift = math.floor(x0 + w / 2 - guiMid)
		end
	end
	el.Pills.Position = UDim2.new(0.5, shift, 0, top)
	local barY = top + pillsH + math.ceil(8 * s)
	HudController.barY = barY
	el.MoonPanel.Position = UDim2.new(0.5, 0, 0, barY)
	el.ZonePicker.Position = UDim2.new(0.5, 0, 0, barY)
	el.Announcement.Position = UDim2.new(0.5, 0, 0, barY + math.ceil(52 * s))
	el.Toasts.Position = UDim2.new(0.5, 0, 0, barY + math.ceil(54 * s) + (if el.Announcement.Visible then math.ceil(50 * s) else 0))
	local hotbarTop = 12 + math.ceil(88 * s)
	el.Hint.Position = UDim2.new(0.5, 0, 1, -(hotbarTop + math.ceil(12 * s)))
	local walletLayout = el.Wallet:FindFirstChildOfClass("UIListLayout")
	local boosts = (el.BoostTemplate :: Instance).Parent :: Frame
	local boostLayout = boosts:FindFirstChildOfClass("UIListLayout")
	local railGrid = el.Rail:FindFirstChildOfClass("UIGridLayout")
	-- Phones: pieces hug the screen edges (Ui.edges pulls them out of most of the safe
	-- area), the Eggs/Pets/Tools column is the right edge (BasePanelsController) and the
	-- boost chips and Auto switches sit in a second column left of it.
	local left, right = Ui.edges(hud)
	local column = right + math.ceil(80 * s) + 10
	if compact then
		-- Phones: the wallet sits in the bottom-left corner (the thumbstick still works
		-- under it) and the rail hugs the left edge right under Roblox's top bar.
		el.Wallet.AnchorPoint = Vector2.new(0, 1)
		el.Wallet.Position = UDim2.new(0, left, 1, -6)
		if walletLayout then
			walletLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		end
		el.Rail.AnchorPoint = Vector2.new(0, 0)
		-- A bit lower than right under the top bar (Dev, 2026-10-30).
		el.Rail.Position = UDim2.new(0, left, 0, 6 + math.ceil(SIDE_DROP * s))
		el.Rail.Size = UDim2.fromOffset(180, 378)
		if railGrid then
			railGrid.CellPadding = UDim2.fromOffset(12, 14)
		end
		boosts.AnchorPoint = Vector2.new(1, 0)
		boosts.Position = UDim2.new(1, -column, 0, 8)
		if boostLayout then
			boostLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		end
	else
		el.Rail.Size = UDim2.fromOffset(180, 414)
		if railGrid then
			railGrid.CellPadding = UDim2.fromOffset(12, 26)
		end
		el.Wallet.AnchorPoint = Vector2.new(0, 1)
		el.Wallet.Position = UDim2.new(0, 14, 1, -14)
		if walletLayout then
			walletLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		end
		el.Rail.AnchorPoint = Vector2.new(0, 0.5)
		el.Rail.Position = UDim2.new(0, 14, 0.5, RAIL_CENTRE)
		boosts.AnchorPoint = Vector2.new(1, 1)
		boosts.Position = UDim2.new(1, -14, 1, -14)
		if boostLayout then
			boostLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		end
	end
	-- The Eggs/Pets/Tools column starts level with the clean bar (BasePanelsController).
	if C.BasePanelsController and C.BasePanelsController.Relayout then
		task.defer(C.BasePanelsController.Relayout, C.BasePanelsController)
	end
	local rightFrame = el.Right :: Frame
	local rightList = rightFrame:FindFirstChildOfClass("UIListLayout")
	if compact then
		-- Second column, above the jump button.
		rightFrame.AnchorPoint = Vector2.new(1, 1)
		rightFrame.Position = UDim2.new(1, -column, 1, -(26 + math.ceil(108 * s)))
		if rightList then
			rightList.VerticalAlignment = Enum.VerticalAlignment.Bottom
		end
	else
		rightFrame.AnchorPoint = Vector2.new(1, 0)
		rightFrame.Position = UDim2.new(1, -14, 0.5, HudController.rightStackTop(s) + math.ceil((STACK_BUTTONS + STACK_GAP) * s))
		if rightList then
			rightList.VerticalAlignment = Enum.VerticalAlignment.Top
		end
	end
end

function HudController:Init(controllers)
	C = controllers
	hud = Ui.screen("Hud")
	el.Rail = Ui.find(hud, "Rail")
	el.Right = Ui.find(hud, "Right")
	el.Wallet = Ui.find(hud, "Wallet")
	el.Cash = Ui.find(hud, "Wallet.CashPanel.Cash")
	el.Income = Ui.find(hud, "Wallet.CashPanel.Income")
	el.PlusButton = Ui.find(hud, "Wallet.CashPanel.PlusButton")
	el.BackpackFill = Ui.find(hud, "Wallet.BackpackPanel.Bar.Fill")
	el.BackpackAmount = Ui.find(hud, "Wallet.BackpackPanel.Bar.Amount")
	el.BackpackFull = Ui.find(hud, "Wallet.BackpackPanel.Full")
	el.MoonTitle = Ui.find(hud, "MoonPanel.Title")
	el.MoonValue = Ui.find(hud, "MoonPanel.Value")
	el.MoonScale = Ui.find(hud, "MoonPanel.AutoScale")
	el.MoonShine = Ui.find(hud, "MoonPanel.Bar.Fill.Shine")
	el.MoonFill = Ui.find(hud, "MoonPanel.Bar.Fill")
	el.MoonIcon = Ui.find(hud, "MoonPanel.Icon")
	el.Announcement = Ui.find(hud, "Announcement")
	el.AnnouncementText = Ui.find(hud, "Announcement.Text")
	el.BoostTemplate = Ui.find(hud, "Boosts.Template")
	el.BoostTip = Ui.find(hud, "BoostTip")
	el.AutoButton = Ui.find(hud, "Right.AutoButton")
	el.AutoSellButton = Ui.find(hud, "Right.AutoSellButton")
	el.ToastTemplate = Ui.find(hud, "Toasts.Template")
	el.ZonePicker = Ui.find(hud, "ZonePicker")
	el.Pills = Ui.find(hud, "Pills")
	el.MoonPanel = Ui.find(hud, "MoonPanel")
	el.Toasts = Ui.find(hud, "Toasts")
	el.Hint = Ui.find(hud, "Hint")
	el.Combo = Ui.find(hud, "Combo")
	el.ComboFill = Ui.find(hud, "Combo.Bar.Fill")
	el.ComboScale = Ui.find(hud, "Combo.AutoScale")
	el.ComboLabel = Ui.find(hud, "Combo.Label")
	el.ZoneRows = {}
	for _, zoneId in ZONE_ORDER do
		el.ZoneRows[zoneId] = Ui.find(hud, "ZonePicker.List.Zone_" .. zoneId)
	end
end

-- Sweep combo (x1 -> x3 cash): a big tilted "x2.4" next to your character. It pops and
-- chimes higher each time it climbs, goes white -> gold -> orange -> pink, and the bar
-- under it runs down until the combo drops.
local COMBO_HOLD = 1.8
local COMBO_COLORS = {
	{ at = 1, color = Color3.fromRGB(255, 255, 255) },
	{ at = 1.5, color = Color3.fromRGB(255, 214, 72) },
	{ at = 2.2, color = Color3.fromRGB(255, 154, 60) },
	{ at = 2.8, color = Color3.fromRGB(255, 90, 200) },
}
local comboToken = 0
local comboShown = 1
local comboEnds = 0
local lastComboSound = 0
function HudController:SetCombo(combo: number)
	comboToken += 1
	local token = comboToken
	local frame = el.Combo :: Frame
	local label = el.ComboLabel :: TextLabel
	if combo <= 1.05 then
		frame.Visible = false
		comboShown = 1
		return
	end
	local color = COMBO_COLORS[1].color
	for _, step in COMBO_COLORS do
		if combo >= step.at then
			color = step.color
		end
	end
	label.Text = string.format("x%.1f", combo)
	label.TextColor3 = color
	el.ComboFill.BackgroundColor3 = color
	comboEnds = os.clock() + COMBO_HOLD
	if not frame.Visible then
		frame.Visible = true
	end
	-- Pop + rising chime each time it goes up a notch.
	if combo >= comboShown + 0.1 then
		comboShown = combo
		if not Ui.reducedMotion() then
			local scale = el.ComboScale :: UIScale
			scale.Scale = Ui.scale() * 1.35
			TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = Ui.scale() }):Play()
		end
		if os.clock() - lastComboSound > 0.18 then
			lastComboSound = os.clock()
			Ui.sound("Combo", 0.8 + (combo - 1) * 0.35)
		end
	end
	task.delay(COMBO_HOLD, function()
		if comboToken == token then
			frame.Visible = false
			comboShown = 1
		end
	end)
end

-- Lays the HUD out again (after a HUD piece shows or hides).
function HudController:Relayout()
	layout(Ui.scale(), Ui.compact())
end

function HudController:Start()
	Ui.onScale(layout)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function()
		layout(Ui.scale(), Ui.compact())
	end)
	-- Per frame: the shine sliding across the Moon bar, the combo timer running down.
	RunService.RenderStepped:Connect(function()
		local t = (os.clock() % 2.6) / 2.6
		local shine = el.MoonShine :: Frame
		shine.Position = UDim2.new(-0.3 + t * 1.8, 0, 0, 0)
		local combo = el.Combo :: Frame
		if combo.Visible then
			el.ComboFill.Size = UDim2.fromScale(math.clamp((comboEnds - os.clock()) / COMBO_HOLD, 0, 1), 1)
		end
	end)

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
	-- Sell: with Sell Anywhere it sells the whole bag right here, otherwise it takes you to a
	-- leaf dump.
	Ui.button(Ui.find(hud, "Pills.SellButton"), function()
		local data = State.data
		if data and data.Gamepasses.SellAnywhere then
			if data.Backpack <= 0 then
				HudController:Toast("Your bag is empty", "Info")
				return
			end
			local ok, message = Net.func("SellNow"):InvokeServer()
			if ok then
				C.DumpController:SellBurst()
			elseif message and message ~= "" then
				HudController:Toast(message, "Bad")
			end
			return
		end
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
	Ui.button(el.AutoButton, function()
		local data = State.data
		if data then
			Net.event("SetAutoSweep"):FireServer(not data.AutoSweep)
		end
	end)
	Ui.button(el.AutoSellButton, function()
		local data = State.data
		if data then
			Net.event("SetAutoSell"):FireServer(not data.AutoSell)
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
