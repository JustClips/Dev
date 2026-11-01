--!strict
-- Daily window (pink calendar on the left rail): 7 daily cards with Claim, the group reward
-- and the event sign-up. Playtime window (green Gifts button, shows the time to the next
-- gift): 6 gifts that unlock as you play. Also:
--   the leave screen: opening the Roblox menu shows "WAIT! DON'T LEAVE!" with what you earn
--   by staying, and starts a "stay 5 minutes for a free potion" countdown,
--   the event board in the plaza (its prompt signs you up),
--   the badge on the rail button when something can be claimed.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local ModelView = require(Client.ModelView)
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Aliens = require(Shared.Config.Aliens)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Rewards = require(Shared.Config.Rewards)

local GREEN = Color3.fromRGB(61, 220, 90)
local GOLD = Color3.fromRGB(255, 200, 60)
local GREY = Color3.fromRGB(166, 174, 194)
local WHITE = Color3.new(1, 1, 1)
local TODAY = Color3.fromRGB(255, 233, 150)
local INK = Color3.fromRGB(27, 31, 58)

local RewardsController = {}

local C: any
local gui: ScreenGui
local giftsGui: ScreenGui
local stayGui: ScreenGui
local leaveGui: ScreenGui
local badge: Frame
local giftsBadge: Frame
local giftsButton: GuiButton
-- Session playtime on the client: the server's count plus the time since that snapshot.
local playtimeBase = 0
local playtimeAt = os.clock()
local stayEndsAt: number? = nil

local function act(action: string, arg: any?): boolean
	local ok, message = Net.func("Rewards"):InvokeServer(action, arg)
	if message and message ~= "" then
		C.HudController:Toast(message, if ok then "Good" else "Bad")
	end
	if ok then
		Ui.sound("Sell")
	end
	return ok
end

local function playtime(): number
	return playtimeBase + (os.clock() - playtimeAt)
end

-- Icon and short text for a reward ("Luck Potion", "x2", "$1.2K" is unknown client side).
local function describe(reward: Rewards.Reward): (string, string, Color3?)
	if reward.Kind == "Cash" then
		return "Icon_Cash", "Cash", nil
	elseif reward.Kind == "Item" then
		local item = Items.ById[reward.Item or ""]
		local amount = reward.Amount or 1
		local name = if item then item.Name else "Item"
		return if item then item.Icon else "Icon_Gift", if amount > 1 then `{name} x{amount}` else name, nil
	elseif reward.Kind == "Egg" then
		local rarity = Eggs.ByName[reward.Rarity or "Common"]
		return "Icon_Egg", `{reward.Rarity} Egg`, rarity and rarity.Color
	elseif reward.Kind == "Spin" then
		local amount = reward.Amount or 1
		return "Icon_Spin", if amount > 1 then `{amount} Wheel Spins` else "Wheel Spin", nil
	elseif reward.Kind == "Pet" then
		local def = Aliens.ById[reward.Pet or ""]
		-- Pets with their own icon (the wheel's Lucky Cat: Icon_LuckyCat) show it.
		local icon = if def and AssetLibrary.image("Icon_" .. def.Id) ~= "" then "Icon_" .. def.Id else "Icon_Gift"
		return icon, if def then def.Name else "Exclusive Pet", nil
	end
	return "Icon_Gift", "", nil
end

-- Like describe, with the Bonus added to the text ("Rare Egg + Huge Charm").
local function describeAll(reward: Rewards.Reward): (string, string, Color3?)
	local image, label, tint = describe(reward)
	if reward.Bonus then
		local _, extra = describe(reward.Bonus)
		label ..= " + " .. extra
	end
	return image, label, tint
end

-- The wheel window labels its prizes the same way (WheelController).
RewardsController.Describe = describe

-- petId: the day-7 card shows the player's next exclusive pet in 3D instead of an icon.
local function fillCard(card: GuiButton, reward: Rewards.Reward, petId: string?)
	if reward.Kind == "Pet" and reward.Pet == "Daily" then
		reward = table.clone(reward)
		reward.Pet = petId
	end
	local image, label, tint = describeAll(reward)
	local icon = card:FindFirstChild("Icon") :: ImageLabel
	icon.Image = AssetLibrary.image(image)
	icon.ImageColor3 = tint or WHITE
	;(card:FindFirstChild("Reward") :: TextLabel).Text = label
	local view = card:FindFirstChild("PetView") :: ViewportFrame?
	local pet = if reward.Kind == "Pet" then Aliens.ById[reward.Pet or ""] else nil
	icon.Visible = pet == nil
	if not pet then
		if view then
			view.Visible = false
		end
		return
	end
	if not view then
		local v = Instance.new("ViewportFrame")
		v.Name = "PetView"
		v.BackgroundTransparency = 1
		v.Size = icon.Size + UDim2.fromOffset(10, 10)
		v.Position = icon.Position
		v.AnchorPoint = icon.AnchorPoint
		v.ZIndex = icon.ZIndex
		v.Ambient = Color3.fromRGB(200, 200, 200)
		v.LightColor = Color3.new(1, 1, 1)
		v.Parent = card
		view = v
	end
	local shown = view :: ViewportFrame
	shown.Visible = true
	-- Redrawn once the real model has loaded (a stand-in shows until then).
	local key = pet.Id .. (if AssetLibrary.has("Alien_" .. pet.Id) then "" else "?")
	if shown:GetAttribute("PetKey") ~= key then
		shown:SetAttribute("PetKey", key)
		ModelView.show(shown, AssetLibrary.alien(pet.Id), "Alien_" .. pet.Id)
	end
	;(card:FindFirstChild("Day") :: TextLabel).TextColor3 = Color3.fromRGB(214, 140, 0)
end

local function setButton(button: GuiButton, text: string, color: Color3, labelColor: Color3?)
	Ui.setText(button, text)
	button.BackgroundColor3 = color
	local label = button:FindFirstChild("Label") :: TextLabel?
	if label then
		label.TextColor3 = labelColor or WHITE
	end
end

local function setCardColor(card: GuiButton, color: Color3)
	card.BackgroundColor3 = color
	local studs = card:FindFirstChild("Studs") :: ImageLabel?
	if studs then
		studs.ImageColor3 = color
	end
end

-- Gifts ready to claim, and seconds until the next locked one (nil when all are unlocked).
local function giftStatus(info): (number, number?)
	local ready, nextIn = 0, nil
	local played = playtime()
	for i, entry in Rewards.Playtime do
		if not info.PlaytimeClaimed[i] then
			local left = entry.Minutes * 60 - played
			if left <= 0 then
				ready += 1
			elseif nextIn == nil or left < nextIn then
				nextIn = left
			end
		end
	end
	return ready, nextIn
end

local RED = Color3.fromRGB(255, 77, 94)

local function dailyCountdown(info): number
	-- 24 hours after your last claim (server clock, ticked on locally).
	local nextAt = if type(info.DailyNextAt) == "number" and info.DailyNextAt > 0
		then info.DailyNextAt
		else (Rewards.day(info.Now) + 1) * 86400
	return math.max(0, nextAt - (info.Now + (os.clock() - playtimeAt)))
end

-- Cards like Dev's reference (2026-10-31): each has a status button. Claimed days say
-- CLAIMED, today's says CLAIM! (or counts down to it), later days say LOCKED.
local function renderDaily(info)
	local left = dailyCountdown(info)
	local nextDay = if info.DailyReady then info.DailyIndex else (info.DailyIndex % #Rewards.Daily) + 1
	for i, reward in Rewards.Daily do
		local card = Ui.find(gui, `Window.Days.Day{i}`) :: GuiButton
		fillCard(card, reward, info.DailyPet)
		local claimed = if info.DailyReady then i < info.DailyIndex else i <= info.DailyIndex
		-- A new streak (DailyIndex 1 while ready) shows no ticks; after day 7 the week
		-- starts over, so nothing shows as claimed while day 1 counts down.
		if (info.DailyReady and info.DailyIndex == 1) or (not info.DailyReady and nextDay == 1) then
			claimed = false
		end
		;(card:FindFirstChild("Done") :: Frame).Visible = claimed
		local status = card:FindFirstChild("Status") :: GuiButton
		if claimed then
			setButton(status, "CLAIMED", GREY)
		elseif i == nextDay and info.DailyReady then
			setButton(status, "CLAIM!", GREEN)
		elseif i == nextDay then
			setButton(status, Format.countdown(left), RED)
		else
			setButton(status, "LOCKED", RED)
		end
		local stroke = card:FindFirstChild("Stroke") :: UIStroke?
		if stroke then
			local hot = i == nextDay and info.DailyReady
			stroke.Color = if hot then GOLD else INK
			stroke.Thickness = if hot then 5 else 3
		end
	end
	local streak = Ui.find(gui, "Window.Streak") :: TextLabel
	streak.Text = `STREAK {info.DailyStreak}`
	local claim = Ui.find(gui, "Window.ClaimDaily") :: GuiButton
	if info.DailyReady then
		setButton(claim, "CLAIM!", GREEN)
	else
		setButton(claim, Format.countdown(left), GREY)
	end
end

local function renderGifts(info)
	local played = playtime()
	for i, entry in Rewards.Playtime do
		local card = Ui.find(giftsGui, `Window.Gifts.Gift{i}`) :: GuiButton
		fillCard(card, entry.Reward)
		local claimed = info.PlaytimeClaimed[i] == true
		local ready = not claimed and played >= entry.Minutes * 60
		local top = card:FindFirstChild("Day") :: TextLabel
		top.Text = if claimed then "Claimed" elseif ready then "CLAIM!" else Format.time(entry.Minutes * 60 - played)
		top.TextColor3 = if ready then Color3.fromRGB(30, 158, 58) else INK
		;(card:FindFirstChild("Done") :: Frame).Visible = claimed
		setCardColor(card, if ready then TODAY else WHITE)
		local stroke = card:FindFirstChild("Stroke") :: UIStroke?
		if stroke then
			stroke.Color = if ready then GOLD else INK
			stroke.Thickness = if ready then 5 else 3
		end
	end
end

local function renderBottom(info)
	local group = Ui.find(gui, "Window.Group") :: Frame
	-- The group reward has its own window now (GroupRewardController).
	group.Visible = false
	if group.Visible then
		local claim = Ui.find(group, "Claim") :: GuiButton
		if info.GroupClaimed then
			setButton(claim, "Claimed", GREY)
		else
			setButton(claim, "Claim", GREEN)
		end
		;(group:FindFirstChild("Text") :: TextLabel).Text = `Join {Rewards.Group.Name} for 2 Luck Potions + cash!`
	end
	local eventFrame = Ui.find(gui, "Window.Event") :: Frame
	local event = Rewards.currentOrNextEvent(info.Now + (os.clock() - playtimeAt))
	eventFrame.Visible = event ~= nil
	-- No event: the window ends right under the cards (Dev, 2026-10-31: no empty space).
	local window = Ui.find(gui, "Window") :: Frame
	window.Size = UDim2.fromOffset(820, if event then 520 else 406)
	if event then
		local t = info.Now + (os.clock() - playtimeAt)
		;(eventFrame:FindFirstChild("Name") :: TextLabel).Text = event.Name
		local when = if t >= event.StartsAt then `LIVE! Ends in {Format.countdown(event.EndsAt - t)}` else `Starts in {Format.countdown(event.StartsAt - t)}`
		;(eventFrame:FindFirstChild("Info") :: TextLabel).Text = `{when}. {event.Description}`
		local signUp = Ui.find(eventFrame, "SignUp") :: GuiButton
		if info.EventSignedUp then
			setButton(signUp, "Signed up!", GREY)
		else
			setButton(signUp, "Sign up", GOLD, INK)
		end
	end
end

local function render()
	local data = State.data
	local info = data and data.Rewards
	if not info then
		return
	end
	Ui.setBadge(badge, if info.DailyReady then 1 else nil)
	local ready, nextIn = giftStatus(info)
	Ui.setBadge(giftsBadge, ready)
	-- The Gifts button counts down to the next gift.
	Ui.setText(giftsButton, if ready > 0 then "Claim!" elseif nextIn then Format.time(nextIn) else "Gifts")
	if Ui.isOpen(gui) then
		renderDaily(info)
		renderBottom(info)
	end
	if Ui.isOpen(giftsGui) then
		renderGifts(info)
	end
end

-------------------------------------------------------------------------- stay offer

-- The free potion countdown is a small round button with the other offers on the right
-- (Hud.Offers), not a wide chip by the wallet (Dev, 2026-11-01: it took a lot of space).
local stayBubble: GuiButton? = nil
local function renderStay()
	local old = Ui.find(stayGui, "Chip") :: GuiObject
	old.Visible = false
	local left = stayEndsAt and stayEndsAt - os.clock()
	local show = left ~= nil and left > 0
	local offers = Ui.find(Ui.screen("Hud"), "Offers") :: Frame
	if show and not stayBubble then
		local bubble = (offers:FindFirstChild("Template") :: GuiButton):Clone()
		bubble.Name = "StayBubble"
		bubble.LayoutOrder = -1
		;(bubble:FindFirstChild("Icon") :: ImageLabel).Image = AssetLibrary.image("Icon_PotionLuck")
		;(bubble:FindFirstChild("Tag") :: TextLabel).Text = "FREE"
		bubble.BackgroundColor3 = Color3.fromRGB(92, 214, 92)
		Ui.button(bubble, function()
			local remaining = stayEndsAt and stayEndsAt - os.clock() or 0
			C.HudController:Toast(`Stay {Format.time(math.max(0, remaining))} more for a free Luck Potion!`, "Info")
		end)
		bubble.Parent = offers
		stayBubble = bubble
	elseif not show and stayBubble then
		stayBubble:Destroy()
		stayBubble = nil
	end
	if stayBubble and left then
		stayBubble.Visible = true
		;(stayBubble:FindFirstChild("Timer") :: TextLabel).Text = Format.time(left)
		offers.Visible = true
	end
end

-- The leave screen (Dev, 2026-10-31): shown while the Roblox menu is open, in red behind the
-- menu. Staying 24 hours vs a day offline (offline income stops at its cap), and the free
-- potion countdown, which starts the moment the menu opens.
local function renderLeave()
	local data = State.data
	if not leaveGui.Enabled or not data then
		return
	end
	local earn = Ui.find(leaveGui, "Leave.Earn") :: TextLabel
	local offline = Ui.find(leaveGui, "Leave.Offline") :: TextLabel
	local potion = Ui.find(leaveGui, "Leave.Potion") :: TextLabel
	local gold = '<font color="#FFD23C">'
	local perDay = (data.IncomePerSec or 0) * 86400
	if perDay > 0 then
		earn.Text = `YOU'LL EARN {gold}+{Format.cash(perDay)} COINS</font> EVERY 24 HOURS!`
		offline.Text = `OFFLINE YOU ONLY EARN {gold}+{Format.cash(data.OfflinePerDay or 0)} COINS</font> A DAY`
		offline.Visible = true
	else
		earn.Text = `STAY AND HATCH PETS THAT EARN {gold}CASH</font> EVERY SECOND!`
		offline.Visible = false
	end
	-- What the next daily reward is (retention pass 2026-11-01: a reason to come back).
	local tomorrow = leaveGui:FindFirstChild("Tomorrow", true) :: TextLabel?
	local info = data.Rewards
	if tomorrow and info then
		local day = if info.DailyReady then info.DailyIndex else (info.DailyIndex % #Rewards.Daily) + 1
		local reward = Rewards.Daily[day]
		local _, label = describeAll(reward)
		if reward and reward.Kind == "Pet" then
			local def = info.DailyPet and Aliens.ById[info.DailyPet]
			label = (if def then `exclusive {def.Name}` else "an exclusive pet") .. (if reward.Bonus then " + " .. select(2, describe(reward.Bonus)) else "")
		end
		local when = if info.DailyReady then "DON'T FORGET" else "COME BACK TOMORROW FOR"
		tomorrow.Text = `{when} {gold}DAY {day}: {string.upper(label)}</font>!`
		tomorrow.Visible = reward ~= nil
	end
	local left = stayEndsAt and stayEndsAt - os.clock()
	potion.Visible = left ~= nil and left > 0
	if left and left > 0 then
		local reward = Rewards.Stay.Reward
		local item = Items.ById[reward.Item or ""]
		potion.Text = `STAY {Format.time(left)} MORE FOR A FREE {string.upper(if item then item.Name else "potion")}!`
	end
end

-- Starts the stay countdown right away (no button to press).
local function startStay()
	local info = State.data and State.data.Rewards
	if not info or not info.StayAvailable or stayEndsAt then
		return
	end
	stayEndsAt = os.clock() + Rewards.Stay.Minutes * 60
	task.spawn(function()
		Net.func("Rewards"):InvokeServer("StartStay")
	end)
end

-------------------------------------------------------------------------- public

function RewardsController:Toggle()
	Ui.toggle("Daily")
	render()
end

function RewardsController:ToggleGifts()
	Ui.toggle("Playtime")
	render()
end

function RewardsController:Init(controllers)
	C = controllers
	gui = Ui.screen("Daily")
	giftsGui = Ui.screen("Playtime")
	stayGui = Ui.screen("Stay")
	leaveGui = Ui.screen("Leave")
	local hud = Ui.screen("Hud")
	badge = Ui.find(hud, "MoreMenu.Items.RewardsButton.Badge")
	giftsButton = Ui.find(hud, "MoreMenu.Items.GiftsButton")
	giftsBadge = Ui.find(giftsButton, "Badge")
end

function RewardsController:Start()
	Ui.button(Ui.find(Ui.screen("Hud"), "MoreMenu.Items.RewardsButton"), function()
		RewardsController:Toggle()
	end)
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Daily")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Daily")
	end)
	local function claimDaily()
		local info = State.data and State.data.Rewards
		if info and not info.DailyReady then
			C.HudController:Toast(`Next reward in {Format.countdown(dailyCountdown(info))}`, "Info")
			return
		end
		act("ClaimDaily")
	end
	Ui.button(Ui.find(gui, "Window.ClaimDaily"), claimDaily)
	for i in Rewards.Daily do
		local card = Ui.find(gui, `Window.Days.Day{i}`) :: GuiButton
		Ui.button(card, claimDaily)
		Ui.button(card:FindFirstChild("Status") :: GuiButton, claimDaily)
	end
	-- Rays spin slowly behind every prize while the window is open.
	local rays: { ImageLabel } = {}
	for i in Rewards.Daily do
		rays[i] = Ui.find(gui, `Window.Days.Day{i}.Rays`)
	end
	game:GetService("RunService").RenderStepped:Connect(function()
		if not gui.Enabled then
			return
		end
		local angle = (os.clock() * 25) % 360
		for i, ray in rays do
			ray.Rotation = if i == 7 then -angle else angle
		end
	end)
	Ui.button(giftsButton, function()
		RewardsController:ToggleGifts()
	end)
	Ui.button(Ui.find(giftsGui, "Window.Close"), function()
		Ui.close("Playtime")
	end)
	Ui.button(Ui.find(giftsGui, "Dim"), function()
		Ui.close("Playtime")
	end)
	for i, entry in Rewards.Playtime do
		Ui.button(Ui.find(giftsGui, `Window.Gifts.Gift{i}`), function()
			-- A wheel spin gift takes you straight to the wheel to use it.
			if act("ClaimPlaytime", i) and entry.Reward.Kind == "Spin" then
				Ui.close("Playtime")
				C.WheelController:Open()
			end
		end)
	end
	Ui.button(Ui.find(gui, "Window.Group.Claim"), function()
		act("ClaimGroup")
	end)
	Ui.button(Ui.find(gui, "Window.Event.SignUp"), function()
		local event = Rewards.currentOrNextEvent(State.now())
		if event then
			act("SignUp", event.Id)
		end
	end)

	-- Opening the Roblox menu is the closest thing to "about to leave" a game can see (closing
	-- the window or app can't be caught), so it plays an attention sound (Dev, 2026-10-31)
	-- and shows the leave screen, starting the free potion countdown.
	local lastAttention = -math.huge
	task.spawn(function()
		-- Loaded ahead, so the very first menu open isn't silent.
		local def = require(Shared.Config.Sounds).Sfx.Attention
		local preload = Instance.new("Sound")
		preload.SoundId = def.Id
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync({ preload })
		end)
	end)
	GuiService.MenuOpened:Connect(function()
		if os.clock() - lastAttention > 15 then
			lastAttention = os.clock()
			Ui.sound("Attention")
		end
		startStay()
		leaveGui.Enabled = true
		renderLeave()
	end)
	GuiService.MenuClosed:Connect(function()
		leaveGui.Enabled = false
	end)

	State.Changed:Connect(function(data)
		local info = data.Rewards
		if info then
			playtimeBase = info.Playtime
			playtimeAt = os.clock()
			stayEndsAt = if info.StayLeft then os.clock() + info.StayLeft else nil
		end
		render()
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			render()
			renderStay()
			renderLeave()
		end
	end)
end

return RewardsController
