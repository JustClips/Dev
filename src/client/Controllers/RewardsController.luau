--!strict
-- Daily window (pink calendar on the left rail): 7 daily cards with Claim, the group reward
-- and the event sign-up. Playtime window (green Gifts button, shows the time to the next
-- gift): 6 gifts that unlock as you play. Also:
--   the stay offer: opening the Roblox menu pops "Stay 5 more minutes for a free potion",
--   the event board in the plaza (its prompt signs you up),
--   the badge on the rail button when something can be claimed.
local GuiService = game:GetService("GuiService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
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
	end
	return "Icon_Gift", "", nil
end

local function fillCard(card: GuiButton, reward: Rewards.Reward)
	local image, label, tint = describe(reward)
	local icon = card:FindFirstChild("Icon") :: ImageLabel
	icon.Image = AssetLibrary.image(image)
	icon.ImageColor3 = tint or WHITE
	;(card:FindFirstChild("Reward") :: TextLabel).Text = label
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

local function renderDaily(info)
	for i, reward in Rewards.Daily do
		local card = Ui.find(gui, `Window.Days.Day{i}`) :: GuiButton
		fillCard(card, reward)
		local claimed = if info.DailyReady then i < info.DailyIndex else i <= info.DailyIndex
		-- A new streak (DailyIndex 1 while ready) shows no ticks.
		if info.DailyReady and info.DailyIndex == 1 then
			claimed = false
		end
		local isToday = i == info.DailyIndex
		;(card:FindFirstChild("Done") :: Frame).Visible = claimed
		setCardColor(card, if isToday then TODAY else WHITE)
		local stroke = card:FindFirstChild("Stroke") :: UIStroke?
		if stroke then
			stroke.Color = if isToday and info.DailyReady then GOLD else INK
			stroke.Thickness = if isToday and info.DailyReady then 5 else 3
		end
	end
	;(Ui.find(gui, "Window.Streak") :: TextLabel).Text = `Streak: {info.DailyStreak} day{if info.DailyStreak == 1 then "" else "s"}`
	local claim = Ui.find(gui, "Window.ClaimDaily") :: GuiButton
	if info.DailyReady then
		setButton(claim, `Claim Day {info.DailyIndex}`, GREEN)
	else
		local tomorrow = (Rewards.day(info.Now) + 1) * 86400
		local left = tomorrow - (info.Now + (os.clock() - playtimeAt))
		setButton(claim, `Next in {Format.countdown(left)}`, GREY)
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
	group.Visible = info.GroupId ~= 0
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
	-- With no group reward the event panel takes the whole row.
	eventFrame.Size = if group.Visible then UDim2.new(0.5, -18, 0, 100) else UDim2.new(1, -24, 0, 100)
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

local function renderStay()
	local chip = Ui.find(stayGui, "Chip") :: Frame
	local left = stayEndsAt and stayEndsAt - os.clock()
	-- Hidden while a window (shop, bag...) is open: it sat on top of them.
	chip.Visible = left ~= nil and left > 0 and not Ui.anyWindowOpen()
	if chip.Visible and left then
		Ui.setText(chip, `Free potion in {Format.time(left)}`)
		-- A small chip right next to the cash counter, out of the way of the game.
		local hud = Ui.screen("Hud")
		local wallet = hud:FindFirstChild("Wallet") :: GuiObject?
		local first = wallet and wallet:FindFirstChild("CashPanel") :: GuiObject?
		if wallet and first then
			local at = first.AbsolutePosition - hud.AbsolutePosition
			chip.AnchorPoint = Vector2.new(0, 0.5)
			chip.Position = UDim2.fromOffset(at.X + first.AbsoluteSize.X + math.ceil(10 * Ui.scale()), at.Y + first.AbsoluteSize.Y / 2)
		end
	end
end

local function offerStay()
	local info = State.data and State.data.Rewards
	if not info or not info.StayAvailable or stayEndsAt then
		return
	end
	local popup = Ui.find(stayGui, "Popup") :: Frame
	popup.Visible = true
	Ui.popFrame(Ui.find(popup, "Window"))
end

local function bobBoard()
	local structures = Workspace:WaitForChild("Structures", 60)
	local board = structures and structures:WaitForChild("EventBoard", 30)
	local holo = board and board:WaitForChild("Hologram", 30)
	local billboard = holo and holo:FindFirstChildOfClass("BillboardGui")
	if not billboard or Ui.reducedMotion() then
		return
	end
	local info = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(billboard, info, { StudsOffset = Vector3.new(0, 0.8, 0) }):Play()
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
	local hud = Ui.screen("Hud")
	badge = Ui.find(hud, "Rail.RewardsButton.Badge")
	giftsButton = Ui.find(hud, "Rail.GiftsButton")
	giftsBadge = Ui.find(giftsButton, "Badge")
end

function RewardsController:Start()
	Ui.button(Ui.find(Ui.screen("Hud"), "Rail.RewardsButton"), function()
		RewardsController:Toggle()
	end)
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Daily")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Daily")
	end)
	Ui.button(Ui.find(gui, "Window.ClaimDaily"), function()
		act("ClaimDaily")
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
	for i in Rewards.Playtime do
		Ui.button(Ui.find(giftsGui, `Window.Gifts.Gift{i}`), function()
			act("ClaimPlaytime", i)
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

	local popup = Ui.find(stayGui, "Popup") :: Frame
	Ui.button(Ui.find(popup, "Window.Close"), function()
		popup.Visible = false
	end)
	Ui.button(Ui.find(popup, "Window.Stay"), function()
		popup.Visible = false
		act("StartStay")
	end)
	GuiService.MenuOpened:Connect(offerStay)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("Opens") == "Event" then
			local event = Rewards.currentOrNextEvent(State.now())
			local info = State.data and State.data.Rewards
			if event and info and not info.EventSignedUp then
				act("SignUp", event.Id)
			else
				RewardsController:Toggle()
			end
		end
	end)
	task.spawn(bobBoard)

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
		end
	end)
end

return RewardsController
