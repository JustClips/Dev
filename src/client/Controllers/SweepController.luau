--!strict
-- Sweeping input and feel. Hold mouse / touch the SWEEP button / gamepad R2 while the tool is
-- equipped; Auto Sweep (gamepass) and vehicles sweep while moving. Sends at most 10 ticks/s.
-- Cleared tiles from the server get dust puffs; sweep results get pooled "+$" numbers.
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
local AssetLibrary = require(Shared.AssetLibrary)
local Assets = require(Shared.Config.Assets)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Grid = require(Shared.Grid)
local Net = require(Shared.Net)

local TICK = 1 / Economy.SweepMaxPerSecond
local PUFF_DISTANCE = 140
local MAX_PUFFS_PER_BATCH = 80
local NUMBER_POOL = 12
local MOVING_SPEED = 2

local SweepController = {}

local C: any
local player = Players.LocalPlayer
local holding = false
local touchHolding = false
local emitter: ParticleEmitter
local emitterPart: Part
local numberPool: { { attachment: Attachment, gui: BillboardGui, label: TextLabel } } = {}
local nextNumber = 1
local tickCount = 0
local tracks: { [string]: AnimationTrack } = {}
local trackHumanoid: Humanoid? = nil

local function character(): (Model?, BasePart?, Humanoid?)
	local char = player.Character
	if not char then
		return nil, nil, nil
	end
	return char, char:FindFirstChild("HumanoidRootPart") :: BasePart?, char:FindFirstChildOfClass("Humanoid")
end

local function toolEquipped(char: Model): boolean
	local tool = char:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool:GetAttribute("SweepTool") == true
end

local function track(humanoid: Humanoid, name: string): AnimationTrack?
	local t = tracks[name]
	if not t then
		t = AssetLibrary.loadTrack(humanoid, name)
		if t then
			tracks[name] = t
		end
	end
	return t
end

local function setTrack(t: AnimationTrack?, on: boolean, fadeIn: number, fadeOut: number)
	if not t then
		return
	end
	if on and not t.IsPlaying then
		t:Play(fadeIn)
	elseif not on and t.IsPlaying then
		t:Stop(fadeOut)
	end
end

-- Tool in hand: each tool has its own hold and use animation (Tool_<Id>_Hold / _Use, see
-- art/anim/tool_anims.py); tools without them fall back to the broom pair.
local currentPair: { hold: string, use: string }? = nil
local toolActive = false

local function animPair(char: Model?): { hold: string, use: string }?
	local tool = char and char:FindFirstChildOfClass("Tool")
	local id = tool and tool:GetAttribute("ToolId")
	if type(id) ~= "string" then
		return nil
	end
	local hold, use = `Tool_{id}_Hold`, `Tool_{id}_Use`
	if Assets.Animations[hold] and Assets.Animations[use] then
		return { hold = hold, use = use }
	end
	return { hold = "Player_Hold", use = "Player_Sweep" }
end

local function setToolAnimation(equipped: boolean, sweeping: boolean)
	local char, _, humanoid = character()
	if humanoid ~= trackHumanoid then
		for _, t in tracks do
			t:Stop(0)
		end
		tracks = {}
		trackHumanoid = humanoid
	end
	if not humanoid or not (equipped or next(tracks)) then
		return
	end
	local pair = if equipped then animPair(char) else currentPair
	if currentPair and pair and (pair.hold ~= currentPair.hold) then
		-- Switched tools: put the old tool's animations away.
		for name, t in tracks do
			if name == currentPair.hold or name == currentPair.use then
				t:Stop(0.15)
			end
		end
	end
	currentPair = pair
	if not pair then
		return
	end
	setTrack(track(humanoid, pair.hold), equipped, 0.2, 0.2)
	setTrack(track(humanoid, pair.use), equipped and sweeping, 0.15, 0.25)
end

local function shouldSweep(): (boolean, Vector3?)
	local char, root, humanoid = character()
	if not char or not root or not humanoid or humanoid.Health <= 0 then
		return false, nil
	end
	local data = State.data
	local moving = root.AssemblyLinearVelocity.Magnitude > MOVING_SPEED
	local inVehicle = humanoid.SeatPart ~= nil and humanoid.SeatPart:IsA("VehicleSeat")
	local auto = data ~= nil and data.Gamepasses.AutoSweep == true and data.AutoSweep
	local active = inVehicle and moving
		or (holding or touchHolding) and toolEquipped(char)
		or auto and moving
	if not active then
		return false, nil
	end
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	local offset = if look.Magnitude > 0.01 then look.Unit * Economy.SweepForwardOffset else Vector3.zero
	return true, root.Position + offset
end

local function makeEmitter()
	emitterPart = Instance.new("Part")
	emitterPart.Name = "DustPuffs"
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.CanQuery = false
	emitterPart.CanTouch = false
	emitterPart.Transparency = 1
	emitterPart.Size = Vector3.new(3, 0.2, 3)
	emitterPart.Parent = Workspace
	emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.35, 0.7)
	emitter.Speed = NumberRange.new(3, 7)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, -6, 0)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2.4) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	emitter.Color = ColorSequence.new(Color3.fromRGB(225, 205, 165))
	emitter.LightInfluence = 0.6
	emitter.Parent = emitterPart
end

local function makeNumberPool()
	local holder = Instance.new("Part")
	holder.Name = "FloatingNumbers"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new()
	holder.Parent = Workspace
	for i = 1, NUMBER_POOL do
		local attachment = Instance.new("Attachment")
		attachment.Name = "Number" .. i
		attachment.Parent = holder
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(140, 36)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.Enabled = false
		gui.Adornee = attachment
		gui.Parent = holder
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold)
		label.TextColor3 = Color3.fromRGB(255, 225, 90)
		label.TextStrokeTransparency = 0.2
		label.Parent = gui
		table.insert(numberPool, { attachment = attachment, gui = gui, label = label })
	end
end

local function floatNumber(text: string, position: Vector3, color: Color3?)
	local entry = numberPool[nextNumber]
	nextNumber = nextNumber % NUMBER_POOL + 1
	entry.attachment.WorldPosition = position
	entry.label.Text = text
	entry.label.TextColor3 = color or Color3.fromRGB(255, 225, 90)
	entry.label.TextTransparency = 0
	entry.gui.StudsOffsetWorldSpace = Vector3.zero
	entry.gui.Enabled = true
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(entry.gui, info, { StudsOffsetWorldSpace = Vector3.new(0, 4, 0) }):Play()
	local fade = TweenService:Create(entry.label, info, { TextTransparency = 1 })
	fade:Play()
	fade.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			entry.gui.Enabled = false
		end
	end)
end

local function onTilesCleared(packed: buffer)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.Focus.Position
	local puffs = 0
	for _, id in Grid.unpack(packed) do
		local position = Grid.tilePosition(id)
		if position and (position - origin).Magnitude < PUFF_DISTANCE then
			emitterPart.Position = position
			emitter:Emit(3)
			puffs += 1
			if puffs >= MAX_PUFFS_PER_BATCH then
				break
			end
		end
	end
end

local fullWarnAt = 0
local function onSweepResult(result)
	local _, root = character()
	if not root then
		return
	end
	if result.Value and result.Value > 0 then
		floatNumber("+" .. Format.cash(result.Value), root.Position + Vector3.new(math.random() * 2 - 1, 3, math.random() * 2 - 1))
	end
	if result.Golden and result.Golden > 0 then
		floatNumber("GOLDEN!", root.Position + Vector3.new(0, 5, 0))
		Ui.sound("Coin")
	end
	-- Lucky Sweep from the upgrade tree.
	if result.Crit and result.Crit > 0 then
		floatNumber(`LUCKY x{result.CritMult or 5}!`, root.Position + Vector3.new(0, 6.5, 0), Color3.fromRGB(120, 255, 140))
		Ui.sound("Coin", 1.25)
	end
	if result.Combo then
		C.HudController:SetCombo(result.Combo)
	end
	if result.Full and os.clock() > fullWarnAt then
		fullWarnAt = os.clock() + 6
		C.HudController:Toast("Backpack full! Tap Sell to go to the Recycler", "Bad")
	end
end

-- Meteor Shower: a glowing rock falls where an egg is about to land.
local function onMeteor(position: Vector3)
	local camera = Workspace.CurrentCamera
	if not camera or (position - camera.Focus.Position).Magnitude > 400 then
		return
	end
	local meteor = Instance.new("Part")
	meteor.Name = "Meteor"
	meteor.Shape = Enum.PartType.Ball
	meteor.Size = Vector3.new(4, 4, 4)
	meteor.Material = Enum.Material.Neon
	meteor.Color = Color3.fromRGB(255, 140, 60)
	meteor.Anchored = true
	meteor.CanCollide = false
	meteor.CanQuery = false
	meteor.CanTouch = false
	meteor.CastShadow = false
	meteor.Position = position + Vector3.new(30, 160, 30)
	local light = Instance.new("PointLight")
	light.Color = meteor.Color
	light.Range = 20
	light.Parent = meteor
	meteor.Parent = Workspace
	local fall = TweenService:Create(meteor, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = position })
	fall:Play()
	fall.Completed:Connect(function()
		meteor:Destroy()
		emitterPart.Position = position
		emitter:Emit(25)
	end)
end

-- True while you're using your hand tool (for its effects, ToolFxController).
function SweepController:IsToolActive(): boolean
	return toolActive
end

function SweepController:Init(controllers)
	C = controllers
	makeEmitter()
	makeNumberPool()
end

function SweepController:Start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			holding = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			holding = false
		end
	end)
	local sweepButton = C.HudController:GetSweepButton()
	sweepButton.MouseButton1Down:Connect(function()
		touchHolding = true
	end)
	sweepButton.MouseButton1Up:Connect(function()
		touchHolding = false
	end)
	sweepButton.MouseLeave:Connect(function()
		touchHolding = false
	end)

	Net.event("TilesCleared").OnClientEvent:Connect(onTilesCleared)
	Net.event("SweepResult").OnClientEvent:Connect(onSweepResult)
	Net.event("MeteorImpact").OnClientEvent:Connect(onMeteor)
	Net.event("BunnyPop").OnClientEvent:Connect(function(position: Vector3)
		local camera = Workspace.CurrentCamera
		if camera and (position - camera.Focus.Position).Magnitude < 200 then
			emitterPart.Position = position
			emitter:Emit(30)
			Ui.sound("Pop")
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < TICK then
			return
		end
		acc = 0
		local active, position = shouldSweep()
		local char, _, humanoid = character()
		local onFoot = humanoid ~= nil and humanoid.SeatPart == nil
		local equipped = onFoot and char ~= nil and toolEquipped(char :: Model)
		setToolAnimation(equipped, active and equipped)
		toolActive = active and equipped
		if active and position then
			Net.event("SweepTick"):FireServer(position)
			tickCount += 1
			if tickCount % 3 == 0 then
				Ui.sound("Sweep")
			end
		end
	end)
end

return SweepController
