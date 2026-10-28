--!strict
-- The tutorial, step by step (the server decides the step: State.data.TutorialStep).
--   * The step card above the hotbar: "STEP 3/9", what to do, a progress bar. Finishing a
--     step flashes it green ("Nice!") with a chime before the next one shows.
--   * Spotlight: for button steps the screen dims except a cut-out around the button, which
--     gets a pulsing ring and a bouncing arrow (your Bag for placing your pet, Next Tool for
--     the first upgrade). For world steps the target glows with an outline you can see
--     through walls (the egg, your pad, your growing egg, the Rocket's sell pad), and
--     ArrowController draws the guide path to it.
--   * Planting the first egg: walk into your pet park and the egg is already in your
--     hands, just click a green spot.
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

local NEAR_PARK = 75 -- studs from the park centre to put the egg in your hands
local NUDGE_SECONDS = 5

type Step = { key: string, text: string, touch: string?, icon: string }

local STEPS: { Step } = {
	{ key = "Sweep", text = "Sweep the leaves to find an egg!", icon = "Icon_Dust" },
	{ key = "Egg", text = "You found an egg! Walk into it to pick it up.", icon = "Icon_Egg" },
	{ key = "Base", text = "Carry the egg home to your base!", icon = "Icon_Base" },
	{
		key = "Place",
		text = "Walk into your pet park and click a green spot to plant your egg!",
		touch = "Walk into your pet park and tap a green spot to plant your egg!",
		icon = "Icon_Egg",
	},
	{ key = "Hatching", text = "Your egg is growing... watch it get bigger!", icon = "Icon_Timer" },
	{
		key = "Open",
		text = "It's ready! Walk up to your egg and press E to open it.",
		touch = "It's ready! Walk up to your egg and tap Open.",
		icon = "Icon_Egg",
	},
	{ key = "PlacePet", text = "Put your pet in your park: open your Bag (3) and press Place.", icon = "Icon_Alien" },
	{ key = "Sell", text = "Sell your leaves at the Recycler for cash!", icon = "Icon_Sell" },
	{ key = "Shop", text = "Buy a better tool. It sweeps faster!", icon = "Icon_Tool" },
}
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

local shownStep: string? = nil
local celebrating = false
local nudgeUntil = 0
local nudgeText = ""
local readySeen: { [string]: boolean } = {}
local readyPrimed = false
local wasHolding = false
local holdCooldown = 0
local pointerTarget: GuiObject? = nil

local function stepText(step: Step): string
	if UserInputService.TouchEnabled and step.touch then
		return step.touch
	end
	return step.text
end

local function showStep(step: Step)
	local index = STEP_INDEX[step.key]
	stepLabel.Visible = true
	stepLabel.Text = `STEP {index}/{#STEPS}`
	textLabel.Text = stepText(step)
	cardIcon.Image = AssetLibrary.image(step.icon)
	barFill.Parent.Visible = true
	TweenService:Create(barFill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Size = UDim2.fromScale((index - 1) / #STEPS, 1) }):Play()
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

local function pointAt(target: GuiObject?)
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
	local x0, y0 = pos.X - pad, pos.Y - pad
	local x1, y1 = pos.X + size.X + pad, pos.Y + size.Y + pad
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
	local key = data.TutorialStep
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
	elseif (key == "Hatching" or key == "Open") and base then
		local hatching = base:FindFirstChild("Hatching")
		return hatching and hatching:GetChildren()[1]
	elseif key == "Sell" and moon then
		local rocket = moon:FindFirstChild("Rocket")
		return rocket and rocket:FindFirstChild("SellPad")
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
			if readyPrimed and data.TutorialStep == "Done" then
				nudgeText = `Your {entry.Rarity} egg is ready! Open it in your pet park.`
				nudgeUntil = os.clock() + NUDGE_SECONDS
				Ui.sound("Notify")
			end
		end
	end
	readyPrimed = true
end

local function update()
	local data = State.data
	if not data then
		card.Visible = false
		return
	end
	checkReadyEggs(data)
	local key = data.TutorialStep
	local step = STEPS[STEP_INDEX[key] or 0]
	local holding = C.PlacementController:IsHolding()

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
		card.Visible = not holding
		glow.Adornee = worldTarget(data)
		glow.Enabled = glow.Adornee ~= nil
		local inventoryOpen = Ui.isOpen(Ui.screen("Inventory"))
		local onHotbar = key == "PlacePet" and not inventoryOpen
		if onHotbar then
			pointAt(Ui.find(hud, "Hotbar.BagSlot"))
		elseif key == "Shop" then
			pointAt(Ui.find(hud, "Right.NextTool.Button"))
		else
			pointAt(nil)
		end
		-- Make room for the arrow when it points at the hotbar.
		card.Position = UDim2.new(0.5, 0, 1, -cardLift(onHotbar))
		return
	end

	-- Tutorial finished.
	pointAt(nil)
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
	else
		card.Visible = false
	end
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
		local target = pointerTarget
		if not target or not target.Visible then
			pointer.Visible = false
			spot.Visible = false
			return
		end
		pointer.Visible = true
		spot.Visible = true
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
