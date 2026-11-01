--!strict
-- The tutorial, step by step (the server decides the step: State.data.TutorialStep).
--   * The step card above the hotbar: "STEP 3/9", what to do, a progress bar. Finishing a
--     step flashes it green ("Nice!") with a chime before the next one shows.
--   * Spotlight: for button steps the screen dims except a cut-out around the button, which
--     gets a pulsing ring and a bouncing arrow (Place for me while you hold your first egg,
--     the hotbar slot your new pet went to, Upgrade > Gear for the first tool). For world steps the target glows with an outline you can see
--     through walls (the egg, your pad, your growing egg, the Rocket's sell pad), and
--     ArrowController draws the guide path to it.
--   * Planting the first egg: walk into your pet park and the egg is already in your
--     hands; click a green spot or press Place for me.
--   * When it's done the server gives a reward and the "Tutorial done!" window shows it.
-- After the tutorial the same card pops up for a few seconds, once, when something needs
-- you (an egg just got ready).
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Format = require(Shared.Format)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Quests = require(Shared.Config.Quests)
local World = require(Shared.Config.World)

local NEAR_PARK = 75 -- studs from the park centre to put the egg in your hands
local NUDGE_SECONDS = 5

type Step = { key: string, text: string, touch: string?, pad: string?, icon: string, lesson: boolean? }

-- Written for kids (Dev, 2026-10-31): one short action line per step, the button or key
-- right in it, "FREE" where something is free. Kids skim, so the arrow, glow and
-- spotlight do the explaining, and every finished step pays a little cash (StateService)
-- with a different cheer.
local STEPS: { Step } = {
	-- The tutorial (Dev, 2026-11-01): why you're here and what to aim for. Sweep, sell,
	-- upgrade your tool, then your first upgrade tree level. No eggs until it's done.
	{
		key = "Sweep",
		text = "Hold the mouse and WALK to sweep leaves!",
		touch = "Hold the screen and WALK to sweep leaves!",
		pad = "Hold R2 and WALK to sweep leaves!",
		icon = "Icon_Dust",
	},
	{
		key = "Sell",
		text = "Leaves are money! Click BASE to sell them at your dump!",
		touch = "Leaves are money! Tap BASE to sell them at your dump!",
		pad = "Leaves are money! Walk to the leaf dump to cash them in!",
		icon = "Icon_Sell",
	},
	{
		key = "Upgrade",
		text = "Upgrade your tool! Open Upgrade, then Gear, and grab a FREE Broom!",
		pad = "Upgrade your tool! Press d-pad right, open Gear, grab a FREE Broom!",
		icon = "Icon_Tools",
	},
	{
		key = "Tree",
		text = "Open Upgrade, then Upgrades, and buy Sweep Power. FREE!",
		touch = "Open Upgrade, then Upgrades, and double-tap Sweep Power. FREE!",
		pad = "Open Upgrade, then Upgrades, and press A on Sweep Power. FREE!",
		icon = "Icon_Upgrade",
	},
	-- The egg lesson (after the tutorial, the first time you find an egg; server
	-- StateService eggLesson). Numbered on its own: "EGGS 1/4".
	{
		key = "Egg",
		text = "You found an egg! Walk to it and press E!",
		touch = "You found an egg! Walk to it and tap the button!",
		pad = "You found an egg! Walk to it and press X!",
		icon = "Icon_Egg",
		lesson = true,
	},
	{ key = "Base", text = "Take it home! Pets there make money. Follow the arrow.", icon = "Icon_Base", lesson = true },
	{
		key = "Place",
		text = "Click a green spot, or Place for me!",
		touch = "Tap a green spot, or Place for me!",
		pad = "Face a green spot and press R2, or Place for me!",
		icon = "Icon_Egg",
		lesson = true,
	},
	{ key = "Hatching", text = "It's hatching... watch it grow!", icon = "Icon_Timer", lesson = true },
	{
		key = "Open",
		text = "It's ready! Walk to it and press E!",
		touch = "It's ready! Walk to it and tap Open!",
		pad = "It's ready! Walk to it and press X!",
		icon = "Icon_Egg",
		lesson = true,
	},
}
-- The number on the card ("STEP 2/4", "EGGS 1/4"): planting is part of bringing it home.
local SHOWN_NUMBER: { [string]: number } = { Sweep = 1, Sell = 2, Upgrade = 3, Tree = 4, Egg = 1, Base = 2, Place = 2, Hatching = 3, Open = 4 }
local SHOWN_TOTAL = 4
-- A different cheer each time a step is done.
local CHEERS = { "Nice!", "Awesome!", "Great job!", "WOW!", "You rock!", "Super!", "Amazing!", "Pro move!" }
local cheerIndex = 0
local STEP_INDEX: { [string]: number } = {}
for i, step in STEPS do
	STEP_INDEX[step.key] = i
end

local TutorialController = {}

local C: any
local hud: ScreenGui
local card: Frame
local cardIcon: ImageLabel
local stepLabel: TextLabel
local textLabel: TextLabel
local barFill: Frame
local doneFrame: Frame
local doneLabel: TextLabel
local pointer: ImageLabel
local doneGui: ScreenGui
local spot: Frame
local ring: Frame
local ringStroke: UIStroke
local glow: Highlight
local holdHint: Frame
local holdPulse: Frame

local shownStep: string? = nil
local celebrating = false
local nudgeUntil = 0
local nudgeText = ""
local readySeen: { [string]: boolean } = {}
local readyPrimed = false
local wasHolding = false
local holdCooldown = 0
local pointerTarget: GuiObject? = nil
-- Sweep step: standing still while sweeping gets a "walk around" nudge.
local STILL_SECONDS = 4
local STILL_STUDS = 6
local stillFrom: Vector3? = nil
local stillSince = 0
local leavesReached = false
local sawArrow = false
local lastNeedTool = false
local textChangedAt = 0
local TEXT_MIN_SECONDS = 4

-- True while the sweeping tool is in your hands (the first step needs it).
local function toolInHand(): boolean
	local character = Players.LocalPlayer.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool:GetAttribute("SweepTool") == true
end

local function stepText(step: Step): string
	-- First step without the tool in hand: equip it first (Dev, 2026-10-30: new players
	-- held the screen with nothing in their hands and got nothing).
	if step.key == "Sweep" and not toolInHand() then
		if Ui.gamepad() then
			return "Press LB or RB to pick your Toothbrush!"
		elseif UserInputService.TouchEnabled then
			return "Tap your Toothbrush in slot 1 to hold it!"
		end
		return "Press 1 or click your Toothbrush to hold it!"
	end
	if Ui.gamepad() and step.pad then
		return step.pad
	end
	if UserInputService.TouchEnabled and step.touch then
		return step.touch
	end
	return step.text
end

local function showStep(step: Step)
	local index = SHOWN_NUMBER[step.key] or 1
	stepLabel.Visible = true
	stepLabel.Text = `{if step.lesson then "EGGS" else "STEP"} {index}/{SHOWN_TOTAL}`
	textLabel.Text = stepText(step)
	cardIcon.Image = AssetLibrary.image(step.icon)
	barFill.Parent.Visible = true
	TweenService:Create(barFill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Size = UDim2.fromScale((index - 1) / SHOWN_TOTAL, 1) }):Play()
end

-- Green flash + chime, then the next step.
local function celebrate(nextStep: Step?)
	celebrating = true
	Ui.sound("Tutorial")
	-- Hidden between celebrations: a see-through label still draws its outline.
	doneFrame.Visible = true
	doneFrame.BackgroundTransparency = 0.05
	doneLabel.TextTransparency = 0
	cheerIndex = cheerIndex % #CHEERS + 1
	doneLabel.Text = CHEERS[cheerIndex]
	TweenService:Create(barFill, TweenInfo.new(0.35), { Size = UDim2.fromScale(1, 1) }):Play()
	task.wait(0.8)
	TweenService:Create(doneFrame, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
	local fade = TweenService:Create(doneLabel, TweenInfo.new(0.25), { TextTransparency = 1 })
	fade.Completed:Connect(function()
		doneFrame.Visible = false
	end)
	fade:Play()
	if nextStep then
		showStep(nextStep)
		Ui.popFrame(card)
	end
	celebrating = false
end

-- How far above the screen bottom the step card sits: just above the hotbar, or higher
-- when the arrow points at the hotbar (matches HudController's layout).
local function cardLift(onHotbar: boolean): number
	local s = Ui.scale()
	local lift = 12 + math.ceil(88 * s) + math.ceil(12 * s)
	return if onHotbar then lift + math.ceil(62 * s) else lift
end

local pointerDim = true -- dim the rest of the screen (not while placing, so the park shows)

local function pointAt(target: GuiObject?, dim: boolean?)
	pointerDim = dim ~= false
	if target ~= pointerTarget and target then
		spot.Visible = true
		for _, name in { "Top", "Bottom", "Left", "Right" } do
			local f = spot:FindFirstChild(name) :: Frame
			f.BackgroundTransparency = 1
			TweenService:Create(f, TweenInfo.new(0.35), { BackgroundTransparency = 0.45 }):Play()
		end
	end
	pointerTarget = target
	pointer.Visible = target ~= nil
	if not target then
		spot.Visible = false
	end
end

-- Dims everything but the target button (in Hud coordinates).
local function layoutSpot(target: GuiObject)
	local scale = Ui.scale()
	local pad = 8 * scale
	-- In the spotlight's own coordinates (its screen can sit at a different origin than
	-- the target's window).
	local pos, size = target.AbsolutePosition - spot.AbsolutePosition, target.AbsoluteSize
	-- Whole pixels: half-pixel edges left a thin bright seam across the dimmed screen.
	local x0, y0 = math.floor(pos.X - pad), math.floor(pos.Y - pad)
	local x1, y1 = math.ceil(pos.X + size.X + pad), math.ceil(pos.Y + size.Y + pad)
	local w, h = spot.AbsoluteSize.X, spot.AbsoluteSize.Y
	local big = 3000
	local function put(name: string, x: number, y: number, sw: number, sh: number)
		local f = spot:FindFirstChild(name) :: Frame
		f.Position = UDim2.fromOffset(x, y)
		f.Size = UDim2.fromOffset(math.max(sw, 0), math.max(sh, 0))
	end
	put("Top", -big, -big, w + big * 2, y0 + big)
	put("Bottom", -big, y1, w + big * 2, h - y1 + big)
	put("Left", -big, y0, x0 + big, y1 - y0)
	put("Right", x1, y0, w - x1 + big, y1 - y0)
	ring.Position = UDim2.fromOffset(x0, y0)
	ring.Size = UDim2.fromOffset(x1 - x0, y1 - y0)
	ringStroke.Thickness = (3 + math.abs(math.sin(os.clock() * 5)) * 3) * scale
end

-- The thing in the world this step is about (outlined through walls).
local function worldTarget(data): Instance?
	local key = State.tutorialStep(data)
	local moon = Workspace:FindFirstChild("Moon")
	local bases = moon and moon:FindFirstChild("Bases")
	local base = bases and data.BaseIndex and bases:FindFirstChild("Base" .. data.BaseIndex)
	if key == "Egg" and data.TutorialTarget then
		local eggs = Workspace:FindFirstChild("Eggs")
		local best, bestDist = nil, 12
		for _, egg in (eggs and eggs:GetChildren() or {}) do
			local position = if egg:IsA("BasePart") then egg.Position elseif egg:IsA("Model") then egg:GetPivot().Position else nil
			if position and (position - data.TutorialTarget).Magnitude < bestDist then
				best, bestDist = egg, (position - data.TutorialTarget).Magnitude
			end
		end
		return best
	elseif key == "Base" and base then
		return base:FindFirstChild("Pad")
	elseif key == "Place" and base then
		return base:FindFirstChild("Park")
	elseif (key == "Hatching" or key == "Open") and base then
		local hatching = base:FindFirstChild("Hatching")
		return hatching and hatching:GetChildren()[1]
	elseif key == "Sell" then
		-- The nearest leaf dump.
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local index = World.nearestDump(if root then root.Position else World.RocketPosition, data.BaseIndex)
		local structures = Workspace:FindFirstChild("Structures")
		return structures and structures:FindFirstChild("LeafDump" .. index)
	end
	return nil
end

local function placeEggNearPark(data)
	local holding = C.PlacementController:IsHolding()
	if wasHolding and not holding then
		holdCooldown = os.clock() + 6 -- they put it away: don't push it back right away
	end
	wasHolding = holding
	if holding or os.clock() < holdCooldown or not data.BaseIndex or data.BaseIndex == 0 then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local c = (World.Base.ParkMin + World.Base.ParkMax) / 2
	local centre = World.baseCFrame(data.BaseIndex) * Vector3.new(c.X, 0, c.Y)
	if (root.Position - centre).Magnitude > NEAR_PARK then
		return
	end
	local uid = next(data.Eggs or {})
	if uid then
		holdCooldown = os.clock() + 2
		C.PlacementController:Hold(uid)
	end
end

-- Once per egg: a short nudge when it gets ready (after the tutorial).
local function checkReadyEggs(data)
	local now = State.now()
	for _, entry in data.Hatching do
		if entry.EndsAt <= now and not readySeen[entry.Uid] then
			readySeen[entry.Uid] = true
			if readyPrimed and data.TutorialStep == "Done" and not data.EggLesson then
				nudgeText = `Your {entry.Rarity} egg is ready! Open it in your pet park.`
				nudgeUntil = os.clock() + NUDGE_SECONDS
				Ui.sound("Notify")
			end
		end
	end
	readyPrimed = true
end

-- Where the newly hatched pet is: its hotbar slot (new pets go there first), or the Bag
-- when the hotbar was full.
local function petSlot(data): GuiObject?
	for i = 1, 6 do
		local key = C.HotbarController:SlotKey(i)
		local uid = string.match(key, "^P:(.+)$")
		local pet = uid and data.Pets and data.Pets[uid]
		if pet and not pet.Placed and C.HotbarController:InHotbar(key) then
			return C.HotbarController:SlotButton(i)
		end
	end
	for _, pet in data.Pets or {} do
		if not pet.Placed then
			return Ui.find(hud, "Hotbar.BagSlot")
		end
	end
	return nil
end

-- True when the player has stayed in one small spot for a few seconds.
local function standingStill(): boolean
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local now = os.clock()
	if not stillFrom or (root.Position - stillFrom).Magnitude > STILL_STUDS then
		stillFrom = root.Position
		stillSince = now
		return false
	end
	return now - stillSince >= STILL_SECONDS
end

-- After the tutorial: the Quest Master's first jobs (free Broom, free Sweep Power, free
-- spin) used to be tutorial steps, so the pointer still shows their button until done.
-- No dimming: the player is free to do other things.
local function jobPointer(data): GuiObject?
	local job = data.Quests and data.Quests.Job
	if not job or job.Done or (job.Number or 99) > Quests.StarterJobs then
		return nil
	end
	if job.Kind == "Tool" then
		if Ui.isOpen(Ui.screen("Garage")) then
			return C.GarageController:NextToolButton()
		end
		return C.MenuController:PointerFor("UpgradeMenu", "ToolsButton")
	elseif job.Kind == "Power" and not C.UpgradeController:IsOpen() then
		return C.MenuController:PointerFor("UpgradeMenu", "TreeButton")
	elseif job.Kind == "FreeSpin" then
		if not Ui.isOpen(Ui.screen("Wheel")) then
			return Ui.find(hud, "SpinButton")
		elseif not C.WheelController:IsSpinning() then
			return Ui.find(Ui.screen("Wheel"), "Window.Side.SpinButton")
		end
	end
	return nil
end

local function update()
	local data = State.data
	if not data then
		card.Visible = false
		return
	end
	checkReadyEggs(data)
	local key = State.tutorialStep(data)
	local step = STEPS[STEP_INDEX[key] or 0]
	-- The step card steps aside while a hatch show or an offer popup is on screen.
	local holding = C.PlacementController:IsHolding()
		or C.HatchController:IsBusy()
		or Ui.isOpen(Ui.screen("WelcomeBack"))

	if step then
		if key == "Place" then
			placeEggNearPark(data)
		end
		if shownStep ~= key and not celebrating then
			local previous = shownStep and STEP_INDEX[shownStep]
			shownStep = key
			if previous and STEP_INDEX[key] > previous then
				task.spawn(celebrate, step)
			else
				showStep(step)
				Ui.popFrame(card)
			end
		end
		-- Upgrade / Tree: the line follows where you are (menu closed, menu open, window
		-- open), so it never asks you to tap something that's already open. Right after
		-- the free Broom, Gear is still up for a second before it closes and the Upgrade
		-- menu opens (GarageController): the card and arrow stay hidden for that moment.
		local handoff = key == "Tree" and Ui.isOpen(Ui.screen("Garage"))
		if (key == "Upgrade" or key == "Tree") and not celebrating and not handoff then
			local menuOpen = C.MenuController:IsOpen("UpgradeMenu")
			local touch = UserInputService.TouchEnabled and not Ui.gamepad()
			local want
			if key == "Upgrade" then
				want = if Ui.isOpen(Ui.screen("Garage")) then "Grab your FREE Broom!"
					elseif menuOpen then "Tap Gear!"
					else stepText(step)
			else
				want = if C.UpgradeController:IsOpen() then (if Ui.gamepad() then "Press A on Sweep Power. FREE!" elseif touch then "Double-tap Sweep Power. FREE!" else "Click Sweep Power. FREE!")
					elseif menuOpen then (if touch then "Tap Upgrades!" else "Click Upgrades!")
					else stepText(step)
			end
			if textLabel.Text ~= want then
				textLabel.Text = want
			end
		end
		card.Visible = not holding and (not handoff or celebrating) -- the "Nice!" still shows
		glow.Adornee = worldTarget(data)
		glow.Enabled = glow.Adornee ~= nil
		local inventoryOpen = Ui.isOpen(Ui.screen("Inventory"))
		local petTarget = if key == "PlacePet" and not inventoryOpen and not C.PlacementController:HeldPet() then petSlot(data) else nil
		local onHotbar = petTarget ~= nil
		local autoPlace = Ui.find(Ui.screen("Placing"), "Bar.AutoPlace") :: GuiObject
		local needTool = key == "Sweep" and not toolInHand()
		-- Sweep in two parts (Dev: "first show go here with the arrow"): walk to the leaves,
		-- then hold and walk.
		-- Once you've reached the leaves the "go there" line never comes back (the arrow
		-- hides and shows again as you walk around, which flipped the text; Dev, 2026-10-31).
		local arrowOn = C.ArrowController:HasTarget()
		if key == "Sweep" and not needTool then
			if arrowOn then
				sawArrow = true
			elseif sawArrow then
				leavesReached = true
			end
		end
		local goThere = key == "Sweep" and not needTool and arrowOn and not leavesReached
		if key == "Sweep" and not celebrating then
			local want = stepText(step)
			if goThere then
				want = "Go to the leaves! Follow the arrow."
			elseif not needTool and standingStill() then
				want = if UserInputService.TouchEnabled and not Ui.gamepad()
					then "Keep moving! Use the joystick to walk onto new leaves while you sweep."
					else "Keep moving! Walk onto new leaves while you sweep."
			end
			-- A line stays up for a few seconds before it can change (unless the tool
			-- went in or out of your hands), so the card doesn't flicker.
			local toolChanged = needTool ~= lastNeedTool
			if textLabel.Text ~= want and (toolChanged or os.clock() - textChangedAt >= TEXT_MIN_SECONDS) then
				textLabel.Text = want
				textChangedAt = os.clock()
			end
			lastNeedTool = needTool
		end
		-- Phones: show where to hold a finger once the tool is out.
		holdHint.Visible = key == "Sweep" and not needTool and not goThere and not celebrating and UserInputService.TouchEnabled and not Ui.gamepad()
		if needTool then
			onHotbar = true
			pointAt(Ui.find(hud, "Hotbar.ToolSlot"))
		elseif petTarget then
			pointAt(petTarget)
		elseif key == "Place" and C.PlacementController:IsHolding() and autoPlace.Visible then
			pointAt(autoPlace, false)
		elseif key == "Sell" and data.Backpack > 0 and not Ui.gamepad() then
			-- Spotlight on BASE (it lands you on your base's leaf dump): the rest of the
			-- screen dims (Dev, 2026-10-31).
			pointAt(Ui.find(hud, "Rail.BaseButton"))
		elseif key == "Upgrade" and not Ui.isOpen(Ui.screen("Garage")) then
			pointAt(C.MenuController:PointerFor("UpgradeMenu", "ToolsButton"))
		elseif key == "Upgrade" then
			-- Gear is open: the spotlight moves onto the FREE! button of the Broom card.
			pointAt(C.GarageController:NextToolButton())
		elseif handoff then
			pointAt(nil)
		elseif key == "Tree" and not C.UpgradeController:IsOpen() then
			pointAt(C.MenuController:PointerFor("UpgradeMenu", "TreeButton"))
		elseif key == "Tree" then
			-- The tree is open: spotlight on the Sweep Power hex (it pulses too).
			pointAt(C.UpgradeController:GetNode("Power"))
		else
			pointAt(nil)
		end
		-- Make room for the arrow when it points at the hotbar, and sit above the backpack
		-- window when it's open.
		local lift = cardLift(onHotbar)
		if inventoryOpen then
			local inv = Ui.screen("Inventory")
			local window = inv:FindFirstChild("Window") :: GuiObject?
			if window then
				lift = math.ceil(inv.AbsolutePosition.Y + inv.AbsoluteSize.Y - window.AbsolutePosition.Y) + 10
			end
		end
		card.Position = UDim2.new(0.5, 0, 1, -lift)
		return
	end

	-- Tutorial finished.
	pointAt(jobPointer(data), false)
	holdHint.Visible = false
	card.Position = UDim2.new(0.5, 0, 1, -cardLift(false))
	glow.Enabled = false
	glow.Adornee = nil
	if shownStep and shownStep ~= "Done" and not celebrating then
		shownStep = "Done"
		task.spawn(celebrate, nil)
		task.delay(1.1, function()
			if shownStep == "Done" and os.clock() >= nudgeUntil then
				card.Visible = false
			end
		end)
		return
	end
	shownStep = "Done"
	if celebrating then
		return
	end
	if os.clock() < nudgeUntil and not holding then
		card.Visible = true
		stepLabel.Visible = false
		barFill.Parent.Visible = false
		cardIcon.Image = AssetLibrary.image("Icon_Egg")
		textLabel.Text = nudgeText
		return
	end
	card.Visible = false
end

local function showReward(reward)
	local window = Ui.find(doneGui, "Window")
	local cashCard = Ui.find(window, "Rewards.Cash")
	local cashIcon = cashCard:FindFirstChild("Icon") :: ImageLabel
	local cashText = cashCard:FindFirstChild("Reward") :: TextLabel
	cashIcon.Image = AssetLibrary.image("Icon_Cash")
	cashText.Text = Format.cash(reward.Cash or 0)
	local function itemCard(cardName: string, itemId: string)
		local itemCardFrame = Ui.find(window, "Rewards." .. cardName)
		local def = Items.ById[itemId]
		local amount = reward.Items and reward.Items[itemId] or 0
		itemCardFrame.Visible = def ~= nil and amount > 0
		if def then
			local iconLabel = itemCardFrame:FindFirstChild("Icon") :: ImageLabel
			local rewardLabel = itemCardFrame:FindFirstChild("Reward") :: TextLabel
			iconLabel.Image = AssetLibrary.image(def.Icon)
			rewardLabel.Text = `{amount}x {def.Name}`
		end
	end
	itemCard("Luck", "LuckPotion")
	itemCard("CashPotion", "CashPotion")
	Ui.open("TutorialDone")
	Ui.sound("Reveal")
end

function TutorialController:Init(controllers)
	C = controllers
	hud = Ui.screen("Hud")
	card = Ui.find(hud, "Hint")
	cardIcon = Ui.find(card, "Icon")
	stepLabel = Ui.find(card, "Step")
	textLabel = Ui.find(card, "Text")
	-- Dev (2026-10-31) dropped the SPIN button that sat on this card for a while.
	local staleSpin = card:FindFirstChild("Spin")
	if staleSpin then
		staleSpin:Destroy()
	end
	barFill = Ui.find(card, "Bar.Fill")
	doneFrame = Ui.find(card, "Done")
	doneLabel = Ui.find(card, "Done.Label")
	pointer = Ui.find(hud, "Pointer")
	holdHint = Ui.find(hud, "HoldHint")
	holdPulse = Ui.find(holdHint, "Pulse")
	spot = Ui.find(hud, "Spot")
	ring = Ui.find(spot, "Ring")
	ringStroke = Ui.find(ring, "Stroke")
	-- The spotlight and arrow also point at buttons inside windows (the FREE! Broom in
	-- Gear), so they live in their own screen above every window. Same insets as the HUD,
	-- so HUD coordinates still line up.
	local top = Instance.new("ScreenGui")
	top.Name = "TutorialTop"
	top.ResetOnSpawn = false
	top.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	top.DisplayOrder = 30
	top.IgnoreGuiInset = hud.IgnoreGuiInset
	top.ScreenInsets = hud.ScreenInsets
	-- The dim must reach the screen edges: by default a ScreenGui is clipped to the safe
	-- area, which left the notch strip and bottom edge bright on phones (Dev, 2026-11-01).
	top.ClipToDeviceSafeArea = false
	top.Parent = hud.Parent
	spot.Parent = top
	pointer.Parent = top
	doneGui = Ui.screen("TutorialDone")
	glow = Instance.new("Highlight")
	glow.Name = "TutorialGlow"
	glow.FillColor = Color3.fromRGB(255, 226, 92)
	glow.OutlineColor = Color3.fromRGB(255, 240, 160)
	glow.FillTransparency = 0.75
	glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	glow.Enabled = false
	glow.Parent = Workspace
end

function TutorialController:Start()
	Net.event("TutorialDone").OnClientEvent:Connect(showReward)
	-- Picking up a controller (or putting it down) swaps the step text.
	UserInputService.LastInputTypeChanged:Connect(function()
		task.defer(function()
			local step = shownStep and STEPS[STEP_INDEX[shownStep] or 0]
			-- The sweep step picks its own line in update().
			if step and step.key ~= "Sweep" and not celebrating then
				textLabel.Text = stepText(step)
			end
		end)
	end)
	local function close()
		Ui.close("TutorialDone")
	end
	Ui.button(Ui.find(doneGui, "Window.Ok"), close)
	Ui.button(Ui.find(doneGui, "Window.Close"), close)
	Ui.button(Ui.find(doneGui, "Dim"), close)
	RunService.RenderStepped:Connect(function()
		if glow.Enabled then
			glow.FillTransparency = 0.6 + math.abs(math.sin(os.clock() * 3)) * 0.3
		end
		if holdHint.Visible then
			-- A finger pressing down: the square shrinks and fills, then lets go.
			local t = (math.sin(os.clock() * 4) + 1) / 2
			local px = 92 - t * 18
			holdPulse.Size = UDim2.fromOffset(px, px)
			holdPulse.BackgroundTransparency = 0.75 - t * 0.35
		end
		local target = pointerTarget
		if not target or not target.Visible then
			pointer.Visible = false
			spot.Visible = false
			return
		end
		pointer.Visible = true
		spot.Visible = pointerDim
		layoutSpot(target)
		local bob = math.abs(math.sin(os.clock() * 5)) * 12 * Ui.scale()
		local size = 56 * Ui.scale()
		pointer.Size = UDim2.fromOffset(size, size)
		local at = target.AbsolutePosition - spot.AbsolutePosition
		pointer.Position = UDim2.fromOffset(at.X + target.AbsoluteSize.X / 2, at.Y - 4 - bob)
	end)
	State.Changed:Connect(update)
	while true do
		update()
		task.wait(0.25)
	end
end

return TutorialController
