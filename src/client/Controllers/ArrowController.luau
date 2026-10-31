--!strict
-- Guide path (tutorial and helpful nudges): a path of glowing 3D arrows from your feet to
-- the target, sliding toward it (Dev, 2026-10-31: one path instead of two arrows), with
-- the distance shown over the target. Steps come from the server
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
local World = require(Shared.Config.World)

local FIELD_INSET = 14 -- studs into the leaf field for the "sweep" guide
local REACHED = 9 -- hide the guide this close to the target
local COLOR = Color3.fromRGB(255, 226, 92)
local TRAIL_ARROWS = 16 -- arrows in the path
local TRAIL_GAP = 4.5 -- studs between them
local TRAIL_START = 3 -- studs in front of you to the first one
local TRAIL_SPEED = 6 -- studs per second they slide toward the target
local TRAIL_HEIGHT = 1.4 -- studs above the ground (over the leaf piles)
local ARM_LENGTH = 2.6 -- each side of the ">" chevron
local ARM_WIDTH = 0.7
local ARM_HEIGHT = 0.4

local ArrowController = {}

local C: any
local player = Players.LocalPlayer
local targetPart: Part
local trail: Folder
local arrows: { Model } = {}
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
	local step = State.tutorialStep(data)
	local hasBase = data.BaseIndex and data.BaseIndex ~= 0
	local pad = if hasBase then basePad(data.BaseIndex) else nil
	-- The nearest leaf dump's standing spot.
	local me = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local _, dumpSpot = World.nearestDump(if me then me.Position else World.RocketPosition)
	if step == "Sweep" then
		-- The nearest spot a little way into the leaf field.
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return nil
		end
		local min, max = World.Field.Min, World.Field.Max
		local x = math.clamp(root.Position.X, min.X + FIELD_INSET, max.X - FIELD_INSET)
		local z = math.clamp(root.Position.Z, min.Y + FIELD_INSET, max.Y - FIELD_INSET)
		local spot = Vector3.new(x, 0, z)
		local rocket = Vector3.new(World.RocketPosition.X, 0, World.RocketPosition.Z)
		local away = spot - rocket
		if away.Magnitude < World.RocketClearRadius + 6 then
			spot = rocket + (if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)) * (World.RocketClearRadius + 6)
		end
		return spot
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
	elseif step == "Sell" then
		return if data.Backpack > 0 then dumpSpot else nil
	end
	if step ~= "Done" then
		return nil
	end
	-- After the tutorial: helpful nudges only.
	if #data.CarriedEggs > 0 and pad then
		return pad.Position
	end
	if data.Backpack >= data.Capacity and not data.Gamepasses.SellAnywhere then
		return dumpSpot
	end
	-- A finished Quest Master job: the path leads to him to claim it.
	local quests = data.Quests
	if hasBase and quests and quests.Job and quests.Job.Done then
		return (World.questCFrame(data.BaseIndex) * CFrame.new(0, 0, -4.5)).Position
	end
	-- A zone quest giver: a finished step nearby, or the one you pressed Go for.
	if me then
		return C.QuestController:GuideTarget(me.Position)
	end
	return nil
end

local function update()
	local data = State.data
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not data or not root then
		board.Enabled = false
		current = nil
		return
	end
	C.HudController:Highlight(if data.TutorialStep == "Shop" then "Tools" else nil)
	local target = targetFor(data)
	if not target or (target - root.Position).Magnitude < REACHED then
		board.Enabled = false
		current = nil
		return
	end
	current = target
	targetPart.Position = target + Vector3.new(0, 0.6, 0)
	board.Enabled = true
end

-- One 3D chevron (">"), two glowing bars meeting at the tip. placeArrow moves it.
local function makeArrow(): Model
	local model = Instance.new("Model")
	model.Name = "PathArrow"
	for _, side in { "Left", "Right" } do
		local part = Instance.new("Part")
		part.Name = side
		part.Size = Vector3.new(ARM_WIDTH, ARM_HEIGHT, ARM_LENGTH)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = COLOR
		part.Parent = model
	end
	model.Parent = trail
	return model
end

-- Local spots of the two bars: the tip is at the origin pointing -Z (forward).
local HALF = ARM_LENGTH / 2 / math.sqrt(2)
local LEFT_ARM = CFrame.lookAt(Vector3.new(-HALF, 0, HALF), Vector3.new(-HALF, 0, HALF) + Vector3.new(-1, 0, 1))
local RIGHT_ARM = CFrame.lookAt(Vector3.new(HALF, 0, HALF), Vector3.new(HALF, 0, HALF) + Vector3.new(1, 0, 1))

local function placeArrow(model: Model, tip: CFrame, transparency: number)
	local left = model:FindFirstChild("Left") :: BasePart
	local right = model:FindFirstChild("Right") :: BasePart
	left.CFrame = tip * LEFT_ARM
	right.CFrame = tip * RIGHT_ARM
	left.Transparency = transparency
	right.Transparency = transparency
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundAt(position: Vector3, fallback: number): number
	local hit = Workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -24, 0), rayParams)
	return if hit then hit.Position.Y else fallback
end

-- Lays the arrows from your feet toward the target, sliding forward.
local function drawTrail()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local target = current
	if not root or not target or not board.Enabled then
		for _, arrow in arrows do
			arrow.Parent = nil
		end
		return
	end
	local flat = (target - root.Position) * Vector3.new(1, 0, 1)
	local length = flat.Magnitude
	if length < 1 then
		return
	end
	local dir = flat / length
	local exclude: { Instance } = { trail }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	rayParams.FilterDescendantsInstances = exclude
	local feet = root.Position.Y - 3
	local slide = (os.clock() * TRAIL_SPEED) % TRAIL_GAP
	local reach = TRAIL_START + (TRAIL_ARROWS - 1) * TRAIL_GAP
	for i = 1, TRAIL_ARROWS do
		local arrow = arrows[i]
		if not arrow then
			arrow = makeArrow()
			arrows[i] = arrow
		end
		local along = TRAIL_START + (i - 1) * TRAIL_GAP + slide
		if along > length - 2 then
			arrow.Parent = nil
			continue
		end
		local spot = root.Position + dir * along
		local bob = math.sin(os.clock() * 4 - along * 0.4) * 0.25
		local y = groundAt(spot, feet) + TRAIL_HEIGHT + bob
		local at = Vector3.new(spot.X, y, spot.Z)
		-- Fade in near you and out at the far end of the path.
		local fade = math.max(1 - (along - TRAIL_START) / 2, (along - reach) / TRAIL_GAP, 0)
		placeArrow(arrow, CFrame.lookAt(at, at + dir), math.clamp(0.05 + fade, 0.05, 1))
		arrow.Parent = trail
	end
end

-- True while the guide is pointing somewhere you haven't reached yet.
function ArrowController:HasTarget(): boolean
	return current ~= nil
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

	trail = Instance.new("Folder")
	trail.Name = "GuideTrail"
	trail.Parent = Workspace

	-- How far the target is, floating over it (the path does the pointing).
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
	distanceLabel = Instance.new("TextLabel")
	distanceLabel.BackgroundTransparency = 1
	distanceLabel.Size = UDim2.new(1, 0, 0, 30)
	distanceLabel.Position = UDim2.new(0, 0, 1, -30)
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
		drawTrail()
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
