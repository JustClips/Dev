--!strict
-- Guide path (tutorial and helpful nudges): a glowing chevron path from your feet to the
-- target and a big bouncing arrow over it, with the distance. Steps come from the server
-- (State.data.TutorialStep): dust -> egg -> home -> plant the egg in your pet park -> open
-- it -> rocket. After the tutorial it still points home when you carry an egg, at a
-- ready egg in your park, and at the Rocket when your backpack is full.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local State = require(Client.State)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local World = require(Shared.Config.World)

local DUST_AHEAD = 30 -- studs from your base toward the Rocket
local REACHED = 9 -- hide the guide this close to the target
local COLOR = Color3.fromRGB(255, 226, 92)

local ArrowController = {}

local C: any
local player = Players.LocalPlayer
local targetPart: Part
local beam: Beam
local board: BillboardGui
local distanceLabel: TextLabel
local moon: Instance
local current: Vector3? = nil

local function basePad(index: number): BasePart?
	local bases = moon:FindFirstChild("Bases")
	local base = bases and bases:FindFirstChild("Base" .. index)
	return base and base:FindFirstChild("Pad") :: BasePart?
end

local function parkCentre(index: number): Vector3
	local c = (World.Base.ParkMin + World.Base.ParkMax) / 2
	return World.baseCFrame(index) * Vector3.new(c.X, 0, c.Y)
end

-- The spot of your first growing egg (ready ones first).
local function eggSpot(data, readyOnly: boolean): Vector3?
	if not data.BaseIndex or data.BaseIndex == 0 then
		return nil
	end
	local best, bestEnds = nil, math.huge
	for _, entry in data.Hatching do
		local ready = entry.EndsAt <= State.now()
		if entry.X and (ready or not readyOnly) and entry.EndsAt < bestEnds then
			best, bestEnds = entry, entry.EndsAt
		end
	end
	if not best then
		return nil
	end
	return World.baseCFrame(data.BaseIndex) * Vector3.new(best.X, 0, best.Z)
end

local function targetFor(data): Vector3?
	local step = data.TutorialStep
	local hasBase = data.BaseIndex and data.BaseIndex ~= 0
	local pad = if hasBase then basePad(data.BaseIndex) else nil
	local rocketModel = moon:FindFirstChild("Rocket")
	local rocket = rocketModel and rocketModel:FindFirstChild("SellPad") :: BasePart?
	if step == "Sweep" and pad then
		local toCenter = (Vector3.zero - pad.Position) * Vector3.new(1, 0, 1)
		return pad.Position + toCenter.Unit * DUST_AHEAD
	elseif step == "Egg" then
		return data.TutorialTarget
	elseif step == "Base" and pad then
		return pad.Position
	elseif step == "Place" and hasBase then
		-- Holding the egg: the placement ring is the guide now.
		if C.PlacementController:IsHolding() then
			return nil
		end
		return parkCentre(data.BaseIndex)
	elseif step == "Hatching" then
		return eggSpot(data, false)
	elseif step == "Open" then
		return eggSpot(data, true)
	elseif step == "Sell" and rocket then
		return if data.Backpack > 0 then rocket.Position else nil
	end
	if step ~= "Done" then
		return nil
	end
	-- After the tutorial: helpful nudges only.
	if #data.CarriedEggs > 0 and pad then
		return pad.Position
	end
	if data.Backpack >= data.Capacity and rocket then
		return rocket.Position
	end
	return nil
end

local function update()
	local data = State.data
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not data or not root then
		beam.Enabled = false
		board.Enabled = false
		current = nil
		return
	end
	C.HudController:Highlight(if data.TutorialStep == "Shop" then "NextTool" else nil)
	local target = targetFor(data)
	if not target or (target - root.Position).Magnitude < REACHED then
		beam.Enabled = false
		board.Enabled = false
		current = nil
		return
	end
	current = target
	targetPart.Position = target + Vector3.new(0, 0.6, 0)
	local attachment = root:FindFirstChild("ArrowAttachment") :: Attachment?
	if not attachment then
		local a = Instance.new("Attachment")
		a.Name = "ArrowAttachment"
		a.Position = Vector3.new(0, -2.6, 0)
		a.Parent = root
		attachment = a
	end
	beam.Attachment0 = attachment
	beam.Enabled = true
	board.Enabled = true
end

function ArrowController:Init(controllers)
	C = controllers
	targetPart = Instance.new("Part")
	targetPart.Name = "ArrowTarget"
	targetPart.Anchored = true
	targetPart.CanCollide = false
	targetPart.CanQuery = false
	targetPart.CanTouch = false
	targetPart.Transparency = 1
	targetPart.Size = Vector3.new(1, 1, 1)
	targetPart.Parent = Workspace
	local endAttachment = Instance.new("Attachment")
	endAttachment.Parent = targetPart

	beam = Instance.new("Beam")
	beam.Attachment1 = endAttachment
	beam.Color = ColorSequence.new(COLOR)
	beam.Width0 = 2
	beam.Width1 = 2
	beam.FaceCamera = true
	beam.LightEmission = 0.6
	beam.LightInfluence = 0
	beam.Texture = AssetLibrary.image("Chevron")
	beam.TextureMode = Enum.TextureMode.Static
	beam.TextureLength = 3
	beam.TextureSpeed = 1.2
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.08, 0.15),
		NumberSequenceKeypoint.new(0.92, 0.15),
		NumberSequenceKeypoint.new(1, 0.6),
	})
	beam.Segments = 2
	beam.Enabled = false
	beam.Parent = targetPart

	-- Big bouncing arrow over the target, with how far it is.
	board = Instance.new("BillboardGui")
	board.Name = "GuideArrow"
	board.Size = UDim2.fromOffset(84, 110)
	board.AlwaysOnTop = true
	board.LightInfluence = 0
	board.MaxDistance = 2000
	board.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	board.Adornee = targetPart
	board.Enabled = false
	board.Parent = targetPart
	local arrow = Instance.new("ImageLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromOffset(72, 72)
	arrow.Position = UDim2.new(0.5, 0, 0, 0)
	arrow.AnchorPoint = Vector2.new(0.5, 0)
	arrow.Image = AssetLibrary.image("ArrowDown")
	arrow.ImageColor3 = Color3.fromRGB(255, 240, 160)
	arrow.Parent = board
	distanceLabel = Instance.new("TextLabel")
	distanceLabel.BackgroundTransparency = 1
	distanceLabel.Size = UDim2.new(1, 0, 0, 30)
	distanceLabel.Position = UDim2.new(0, 0, 0, 74)
	distanceLabel.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
	distanceLabel.TextSize = 22
	distanceLabel.TextColor3 = Color3.new(1, 1, 1)
	distanceLabel.Parent = board
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(27, 31, 58)
	stroke.Parent = distanceLabel
end

function ArrowController:Start()
	moon = Workspace:WaitForChild("Moon")
	State.Changed:Connect(update)
	RunService.RenderStepped:Connect(function()
		if not board.Enabled or not current then
			return
		end
		board.StudsOffsetWorldSpace = Vector3.new(0, 6 + math.abs(math.sin(os.clock() * 4)) * 1.6, 0)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			distanceLabel.Text = `{math.floor((current - root.Position).Magnitude)}m`
		end
	end)
	while true do
		update()
		task.wait(0.3)
	end
end

return ArrowController
