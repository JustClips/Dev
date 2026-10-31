--!strict
-- The tutorial, step by step (the server decides the step: State.data.TutorialStep).
-- Four steps: sweep, grab the egg, carry it home (it plants and hatches by itself), sell.
--   * The step card above the hotbar: "STEP 2/4", one short line, a progress bar. Finishing
--     a step flashes it green ("Nice!") with a chime before the next one shows.
--   * World steps glow the target through walls (the egg, your pad, your growing egg, the
--     leaf dump) and ArrowController draws the guide path to it. Button steps (tool slot,
--     SELL) get a pulsing ring and a bouncing arrow.
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
local World = require(Shared.Config.World)

local NUDGE_SECONDS = 5

type Step = { key: string, text: string, touch: string?, pad: string?, icon: string }

-- Remade 2026-10-31 (Dev: "too many steps"): four steps the player sees, each one short
-- line, learned by doing. The server plants and opens the first egg by itself, and the pet
-- goes on the base by itself; Gear, Upgrades and the wheel are taught later in context.
local STEPS: { Step } = {
	{
		key = "Sweep",
		text = "Hold the mouse and WALK AROUND to sweep leaves!",
		touch = "Hold the screen and WALK AROUND to sweep leaves!",
		pad = "Hold R2 and WALK AROUND to sweep leaves!",
		icon = "Icon_Dust",
	},
	{ key = "Egg", text = "You found an egg! Walk to it to grab it.", icon = "Icon_Egg" },
	{ key = "Base", text = "Carry your egg home! Follow the arrow.", icon = "Icon_Base" },
	{ key = "Hatch", text = "Your egg is hatching...", icon = "Icon_Egg" },
	{
		key = "Sell",
		text = "Your pet makes money now! Click SELL to cash in your leaves.",
		touch = "Your pet makes money now! Tap SELL to cash in your leaves.",
		pad = "Your pet makes money now! Walk to the market to sell your leaves.",
		icon = "Icon_Sell",
	},
}
-- The number shown on the card ("STEP 3/4"): hatching is part of "carry it home".
local SHOWN_NUMBER: { [string]: number } = { Sweep = 1, Egg = 2, Base = 3, Hatch = 3, Sell = 4 }
local SHOWN_TOTAL = 4
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
local pointerTarget: GuiObject? = nil
-- Sweep step: standing still while sweeping gets a "walk around" nudge.
local STILL_SECONDS = 4
local STILL_STUDS = 6
local stillFrom: Vector3? = nil
local stillSince = 0

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
	stepLabel.Text = `STEP {index}/{SHOWN_TOTAL}`
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
	local pos, size = target.AbsolutePosition, target.AbsoluteSize
	-- Whole pixels: half-pixel edges left a thin bright seam across the dimmed screen.
	local x0, y0 = math.floor(pos.X - pad), math.floor(pos.Y - pad)
	local x1, y1 = math.ceil(pos.X + size.X + pad), math.ceil(pos.Y + size.Y + pad)
	local w, h = hud.AbsoluteSize.X, hud.AbsoluteSize.Y
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
	elseif key == "Hatch" and base then
		local hatching = base:FindFirstChild("Hatching")
		return hatching and hatching:GetChildren()[1]
	elseif key == "Sell" then
		-- The nearest leaf dump.
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local index = World.nearestDump(if root then root.Position else World.RocketPosition)
		local structures = Workspace:FindFirstChild("Structures")
		return structures and structures:FindFirstChild("LeafDump" .. index)
	end
	return nil
end

-- Once per egg: a short nudge when it gets ready (after the tutorial).
local function checkReadyEggs(data)
	local now = State.now()
	for _, entry in data.Hatching do
		if entry.EndsAt <= now and not readySeen[entry.Uid] then
			readySeen[entry.Uid] = true
			if readyPrimed and data.TutorialStep == "Done" then
				nudgeText = `Your {entry.Rarity} egg is ready! Open it in your pet park.`
				nudgeUntil = os.clock() + NUDGE_SECONDS
				Ui.sound("Notify")
			end
		end
	end
	readyPrimed = true
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
		card.Visible = not holding
		glow.Adornee = worldTarget(data)
		glow.Enabled = glow.Adornee ~= nil
		local inventoryOpen = Ui.isOpen(Ui.screen("Inventory"))
		local onHotbar = false
		local needTool = key == "Sweep" and not toolInHand()
		if key == "Sweep" and not celebrating then
			local want = stepText(step)
			if not needTool and standingStill() then
				want = if UserInputService.TouchEnabled and not Ui.gamepad()
					then "Keep moving! Use the joystick to walk onto new leaves while you sweep."
					else "Keep moving! Walk onto new leaves while you sweep."
			end
			if textLabel.Text ~= want then
				textLabel.Text = want
			end
		end
		-- Phones: show where to hold a finger once the tool is out.
		holdHint.Visible = key == "Sweep" and not needTool and not celebrating and UserInputService.TouchEnabled and not Ui.gamepad()
		if needTool then
			onHotbar = true
			pointAt(Ui.find(hud, "Hotbar.ToolSlot"))
		elseif key == "Sell" and data.Backpack > 0 and not Ui.gamepad() then
			pointAt(Ui.find(hud, "Pills.SellButton"), false)
		else
			pointAt(nil)
		end
		-- Make room for the arrow when it points at the hotbar, and sit above the backpack
		-- window when it's open.
		local lift = cardLift(onHotbar)
		if inventoryOpen then
			lift = math.ceil((112 + 316) * Ui.scale()) + 10
		end
		card.Position = UDim2.new(0.5, 0, 1, -lift)
		return
	end

	-- Tutorial finished.
	pointAt(nil)
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
	barFill = Ui.find(card, "Bar.Fill")
	doneFrame = Ui.find(card, "Done")
	doneLabel = Ui.find(card, "Done.Label")
	pointer = Ui.find(hud, "Pointer")
	holdHint = Ui.find(hud, "HoldHint")
	holdPulse = Ui.find(holdHint, "Pulse")
	spot = Ui.find(hud, "Spot")
	ring = Ui.find(spot, "Ring")
	ringStroke = Ui.find(ring, "Stroke")
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
			if step and not celebrating then
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
		local at = target.AbsolutePosition
		pointer.Position = UDim2.fromOffset(at.X + target.AbsoluteSize.X / 2, at.Y - 4 - bob)
	end)
	State.Changed:Connect(update)
	while true do
		update()
		task.wait(0.25)
	end
end

return TutorialController
