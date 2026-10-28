--!strict
-- Hatch cutscene: egg shake -> crack flash -> the alien pops out and does its happy dance
-- (rarity colour + name) -> "Place on base" or "Keep in bag" -> flies off. Also counts
-- down the timers above incubating eggs and adds the owner's prompts on the base:
-- Skip Hatch (Robux) while an egg is hatching, Open when it's ready, and Place Eggs on
-- the hatchery pad.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AlienModel = require(Shared.AlienModel)
local AssetLibrary = require(Shared.AssetLibrary)
local Aliens = require(Shared.Config.Aliens)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local World = require(Shared.Config.World)

local REVEAL_SECONDS = 3

local HatchController = {}

local C: any
local choice: Frame
local chosen: string? = nil

local gui: ScreenGui
local stage: Frame
local stageScale: UIScale
local viewport: ViewportFrame
local worldModel: WorldModel
local glow: ImageLabel
local flash: Frame
local nameLabel: TextLabel
local subLabel: TextLabel
local newLabel: TextLabel
local hintLabel: TextLabel
local queue = {}
local playing = false
local skipRequested = false

local function clearViewport()
	worldModel:ClearAllChildren()
end

-- Where your pet park is on screen (the alien flies there after the reveal).
local function parkScreenPosition(): UDim2
	local camera = Workspace.CurrentCamera
	local data = State.data
	if camera and data and data.BaseIndex then
		local center = (World.Base.ParkMin + World.Base.ParkMax) / 2
		local world = World.baseCFrame(data.BaseIndex) * Vector3.new(center.X, 2, center.Y)
		local point, visible = camera:WorldToViewportPoint(world)
		if visible then
			return UDim2.fromOffset(point.X, point.Y)
		end
	end
	return UDim2.fromScale(0.5, 1.2)
end

local function waitOrSkip(seconds: number)
	local deadline = os.clock() + seconds
	while os.clock() < deadline and not skipRequested do
		task.wait()
	end
end

local function play(info)
	playing = true
	skipRequested = false
	local def = Aliens.ById[info.AlienId]
	local rarity = Eggs.ByName[info.Rarity]
	local camera = viewport.CurrentCamera :: Camera
	clearViewport()

	-- 1. Egg shake
	local egg = AssetLibrary.egg(info.Rarity)
	egg:PivotTo(CFrame.new())
	egg.Parent = worldModel
	local _, eggSize = egg:GetBoundingBox()
	local eggHeight = math.max(eggSize.Y, 2)
	camera.CFrame = CFrame.lookAt(Vector3.new(0, eggHeight * 0.75, -eggHeight * 2.6), Vector3.new(0, eggHeight * 0.48, 0))
	glow.ImageColor3 = rarity.Color

	nameLabel.Text = ""
	subLabel.Text = ""
	newLabel.Visible = false
	hintLabel.Visible = false
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stageScale.Scale = Ui.scale()
	gui.Enabled = true
	Ui.popIn(gui)

	for i = 1, 6 do
		local angle = if i % 2 == 0 then 18 else -18
		egg:PivotTo(CFrame.Angles(0, 0, math.rad(angle * (i / 6))))
		task.wait(0.12)
	end

	-- 2. Crack + light burst
	Ui.sound("Hatch")
	flash.BackgroundTransparency = 0
	TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	egg:Destroy()

	-- 3. Reveal: the alien hops out and plays its happy animation, then idles while turning.
	local model = AssetLibrary.alien(info.AlienId, info.Mutation)
	model:PivotTo(CFrame.new())
	model.Parent = worldModel
	local _, size3 = model:GetBoundingBox()
	local size = math.max(size3.X, size3.Y, size3.Z, 1.5)
	camera.CFrame = CFrame.lookAt(Vector3.new(size * 0.35, size * 0.7, -size * 2.4), Vector3.new(0, size * 0.42, 0))
	local happy = AssetLibrary.loadTrack(model, "Pet_Happy")
	local idle = AssetLibrary.loadTrack(model, "Pet_Idle")
	if idle then
		idle:Play()
	end
	if happy then
		happy:Play(0.05)
	end
	local yaw = 0
	local spin = RunService.RenderStepped:Connect(function(dt)
		if happy and happy.IsPlaying then
			return
		end
		yaw += dt * 1.2
		model:PivotTo(CFrame.Angles(0, yaw, 0))
	end)

	if info.Huge then
		model:ScaleTo(Aliens.HugeScale)
	end
	nameLabel.Text = (if info.Huge then "HUGE " else "") .. AlienModel.displayName(info.AlienId, info.Mutation)
	nameLabel.TextColor3 = rarity.Color
	local income = info.Income or (def and def.Income or 0)
	subLabel.Text = `{info.Rarity} · {Format.cash(income)}/s`
	newLabel.Visible = info.IsNew == true
	hintLabel.Visible = true
	waitOrSkip(REVEAL_SECONDS)

	-- Place it on the base right away, or keep it in the bag (only offered with room).
	if info.FreeSlot and info.Uid then
		hintLabel.Visible = false
		chosen = nil
		choice.Visible = true
		local deadline = os.clock() + 8
		while chosen == nil and os.clock() < deadline do
			task.wait()
		end
		choice.Visible = false
		if chosen == "Place" then
			local ok, message = Net.func("Inventory"):InvokeServer("PlacePet", info.Uid)
			if not ok and message then
				C.HudController:Toast(message, "Bad")
			end
		else
			C.HudController:Toast("Saved in your bag (press 3 or B).", "Info")
		end
	else
		C.HudController:Toast("Added to your bag (press 3 or B).", "Info")
	end

	-- 4. Fly to the pet park
	local fly = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(stage, fly, { Position = parkScreenPosition() }):Play()
	local shrink = TweenService:Create(stageScale, fly, { Scale = 0.05 })
	shrink:Play()
	shrink.Completed:Wait()
	spin:Disconnect()
	gui.Enabled = false
	clearViewport()
	playing = false
end

local function pump()
	if playing then
		return
	end
	local info = table.remove(queue, 1)
	if info then
		task.spawn(function()
			play(info)
			pump()
		end)
	end
end

local function updateTimers()
	local now = State.now()
	for _, label in CollectionService:GetTagged("HatchTimer") do
		if label:IsA("TextLabel") then
			local endsAt = label:GetAttribute("EndsAt") or 0
			local left = endsAt - now
			label.Text = if left > 0 then Format.time(left) else "READY!"
		end
	end
end

local function invoke(action: string, arg: string?)
	local ok, message = Net.func("Inventory"):InvokeServer(action, arg)
	if message and message ~= "" then
		C.HudController:Toast(message, if ok then "Good" else "Bad")
	end
end

-- Owner prompts on incubating eggs: Skip (Robux) while hatching, Open when ready.
local function updateEggPrompts()
	local me = Players.LocalPlayer.UserId
	local now = State.now()
	for _, egg in CollectionService:GetTagged("HatchingEgg") do
		if not egg:IsA("Model") or egg:GetAttribute("OwnerUserId") ~= me then
			continue
		end
		local root = egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")
		if not root then
			continue
		end
		local prompt = root:FindFirstChild("EggPrompt") :: ProximityPrompt?
		if not prompt then
			local p = Instance.new("ProximityPrompt")
			p.Name = "EggPrompt"
			p.MaxActivationDistance = 12
			p.RequiresLineOfSight = false
			p.HoldDuration = 0.25
			p.Parent = root
			local uid = egg:GetAttribute("Uid") :: string
			p.Triggered:Connect(function()
				if p:GetAttribute("Ready") then
					invoke("OpenEgg", uid)
				else
					invoke("SkipHatch", uid)
				end
			end)
			prompt = p
		end
		local ready = (egg:GetAttribute("EndsAt") or 0) <= now
		local rarity = egg:GetAttribute("Rarity") :: string
		local p = prompt :: ProximityPrompt
		p:SetAttribute("Ready", ready)
		p.ObjectText = `{rarity} Egg`
		if ready then
			p.ActionText = "Open"
		else
			local product = Products.ProductByKey["SkipHatch" .. rarity]
			p.ActionText = if product and product.Id ~= 0 then `Skip Hatch {Ui.ROBUX}{product.Price}` else "Hatching..."
			p.Enabled = product ~= nil and product.Id ~= 0
		end
		if ready then
			p.Enabled = true
		end
	end
end

-- "Place Eggs" on your own hatchery pad while you have eggs and a free incubator.
local padPrompt: ProximityPrompt? = nil
local function updatePadPrompt()
	local data = State.data
	if not data or not data.BaseIndex or data.BaseIndex == 0 then
		return
	end
	if not padPrompt then
		local moon = Workspace:FindFirstChild("Moon")
		local bases = moon and moon:FindFirstChild("Bases")
		local base = bases and bases:FindFirstChild("Base" .. data.BaseIndex)
		local pad = base and base:FindFirstChild("Pad") :: BasePart?
		if not pad then
			return
		end
		local p = Instance.new("ProximityPrompt")
		p.Name = "PlaceEggs"
		p.ActionText = "Place Eggs"
		p.ObjectText = "Incubators"
		p.KeyboardKeyCode = Enum.KeyCode.F
		p.MaxActivationDistance = 14
		p.RequiresLineOfSight = false
		p.UIOffset = Vector2.new(0, 60)
		p.Parent = pad
		p.Triggered:Connect(function()
			invoke("PlaceBestEggs")
		end)
		padPrompt = p
	end
	local eggs = 0
	for _ in data.Eggs or {} do
		eggs += 1
	end
	local prompt = padPrompt :: ProximityPrompt
	prompt.Enabled = eggs > 0 and #data.Hatching < data.Incubators
	prompt.ObjectText = `{eggs} in your bag`
end

function HatchController:Init(controllers)
	C = controllers
	gui = Ui.screen("Hatch")
	stage = Ui.find(gui, "Stage")
	stageScale = Ui.find(gui, "Stage.AutoScale")
	viewport = Ui.find(gui, "Stage.Viewport")
	glow = Ui.find(gui, "Stage.Glow")
	-- Animations only play inside a WorldModel.
	worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport
	flash = Ui.find(gui, "Flash")
	nameLabel = Ui.find(gui, "Stage.Name")
	subLabel = Ui.find(gui, "Stage.Sub")
	newLabel = Ui.find(gui, "Stage.New")
	hintLabel = Ui.find(gui, "Stage.Hint")
	choice = Ui.find(gui, "Stage.Choice")
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

function HatchController:Start()
	Net.event("HatchCompleted").OnClientEvent:Connect(function(info)
		table.insert(queue, info)
		pump()
	end)
	UserInputService.InputBegan:Connect(function(input)
		if playing and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			skipRequested = true
		end
	end)
	Ui.button(Ui.find(choice, "Place"), function()
		chosen = "Place"
	end)
	Ui.button(Ui.find(choice, "Keep"), function()
		chosen = "Keep"
	end)
	while true do
		updateTimers()
		updateEggPrompts()
		updatePadPrompt()
		task.wait(0.25)
	end
end

return HatchController
