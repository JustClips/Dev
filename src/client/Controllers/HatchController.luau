--!strict
-- Hatch cutscene: egg shake -> crack flash -> alien reveal with rarity color and name ->
-- flies to its base slot. Also counts down the timers above hatching eggs.
local CollectionService = game:GetService("CollectionService")
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
local Aliens = require(Shared.Config.Aliens)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local REVEAL_SECONDS = 3

local HatchController = {}

local gui: ScreenGui
local stage: Frame
local stageScale: UIScale
local viewport: ViewportFrame
local flash: Frame
local nameLabel: TextLabel
local subLabel: TextLabel
local newLabel: TextLabel
local hintLabel: TextLabel
local queue = {}
local playing = false
local skipRequested = false

local function clearViewport()
	for _, child in viewport:GetChildren() do
		if not child:IsA("Camera") then
			child:Destroy()
		end
	end
end

local function slotScreenPosition(slot: number): UDim2
	local camera = Workspace.CurrentCamera
	local data = State.data
	local moon = Workspace:FindFirstChild("Moon")
	local bases = moon and moon:FindFirstChild("Bases")
	local base = data and bases and bases:FindFirstChild("Base" .. data.BaseIndex)
	local slots = base and base:FindFirstChild("Slots")
	local marker = slots and slots:FindFirstChild("Slot" .. slot) :: BasePart?
	if camera and marker then
		local point, visible = camera:WorldToViewportPoint(marker.Position)
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
	local egg = Instance.new("Part")
	egg.Size = Vector3.new(2.2, 2.9, 2.2)
	egg.Color = rarity.Color
	egg.Material = Enum.Material.SmoothPlastic
	egg.CFrame = CFrame.new(0, 1.45, 0)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = egg
	egg.Parent = viewport
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 2.2, -7), Vector3.new(0, 1.4, 0))

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
		egg.CFrame = CFrame.new(0, 1.45, 0) * CFrame.Angles(0, 0, math.rad(angle * (i / 6)))
		task.wait(0.12)
	end

	-- 2. Crack + light burst
	Ui.sound("Hatch")
	flash.BackgroundTransparency = 0
	TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	egg:Destroy()

	-- 3. Reveal
	local model = AlienModel.build(info.AlienId, info.Mutation)
	model:PivotTo(CFrame.new(0, 0, 0))
	model.Parent = viewport
	local size = def and def.Size or 2
	camera.CFrame = CFrame.lookAt(Vector3.new(0, size * 0.8, -size * 2.6), Vector3.new(0, size * 0.5, 0))
	local spin = RunService.RenderStepped:Connect(function(dt)
		model:PivotTo(model:GetPivot() * CFrame.Angles(0, dt * 1.5, 0))
	end)

	nameLabel.Text = AlienModel.displayName(info.AlienId, info.Mutation)
	nameLabel.TextColor3 = rarity.Color
	local income = def and def.Income or 0
	local mutation = info.Mutation and Eggs.MutationByName[info.Mutation]
	if mutation then
		income *= mutation.IncomeMult
	end
	subLabel.Text = `{info.Rarity} · {Format.cash(income)}/s`
	newLabel.Visible = info.IsNew == true
	hintLabel.Visible = true
	waitOrSkip(REVEAL_SECONDS)

	-- 4. Fly to the slot
	local fly = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(stage, fly, { Position = slotScreenPosition(info.Slot) }):Play()
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
			label.Text = if left > 0 then `🥚 {Format.time(left)}` else "Hatching!"
		end
	end
end

function HatchController:Init()
	gui = Ui.screen("Hatch")
	stage = Ui.find(gui, "Stage")
	stageScale = Ui.find(gui, "Stage.AutoScale")
	viewport = Ui.find(gui, "Stage.Viewport")
	flash = Ui.find(gui, "Flash")
	nameLabel = Ui.find(gui, "Stage.Name")
	subLabel = Ui.find(gui, "Stage.Sub")
	newLabel = Ui.find(gui, "Stage.New")
	hintLabel = Ui.find(gui, "Stage.Hint")
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
	while true do
		updateTimers()
		task.wait(0.25)
	end
end

return HatchController
