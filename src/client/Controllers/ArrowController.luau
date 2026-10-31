--!strict
-- Guide path (tutorial and helpful nudges): a trail of flat arrows on the ground from your
-- feet toward the target, sliding forward, and a big bouncing arrow over it, with the
-- distance. Steps come from the server
-- (State.data.TutorialStep): dust -> egg -> home -> your growing egg -> leaf dump. After the tutorial it still points home when you carry an egg, at a
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

local FIELD_INSET = 14 -- studs into the leaf field for the "sweep" guide
local REACHED = 9 -- hide the guide this close to the target
local COLOR = Color3.fromRGB(255, 226, 92)
local TRAIL_ARROWS = 12 -- arrows on the ground
local TRAIL_GAP = 5 -- studs between them
local TRAIL_START = 4 -- studs in front of you to the first one
local TRAIL_SPEED = 4 -- studs per second they slide toward the target
local ARROW_SIZE = 2.6

local ArrowController = {}

local C: any
local player = Players.LocalPlayer
local targetPart: Part
local trail: Folder
local arrows: { BasePart } = {}
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
	elseif step == "Hatch" then
		return eggSpot(data, false)
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
	-- After the tutorial the Gear button wiggles until you take the free Broom.
	C.HudController:Highlight(if data.TutorialStep == "Done" and data.ToolTier < 2 then "Tools" else nil)
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

-- One flat arrow: an invisible thin part lying down with the arrow image on its front
-- face (which faces the sky). Its UpVector is where the arrow points.
local function makeArrow(): BasePart
	local part = Instance.new("Part")
	part.Name = "PathArrow"
	part.Size = Vector3.new(ARROW_SIZE, ARROW_SIZE, 0.05)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = part
	local image = Instance.new("ImageLabel")
	image.Name = "Arrow"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Image = AssetLibrary.image("ArrowDown")
	image.Rotation = 180 -- the image points down; turn it to point ahead
	image.ImageColor3 = COLOR
	image.Parent = gui
	part.Parent = trail
	return part
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
	-- Lying flat: front face (LookVector) up, UpVector along the path.
	local right = dir:Cross(Vector3.new(0, -1, 0))
	for i = 1, TRAIL_ARROWS do
		local arrow = arrows[i]
		if not arrow then
			arrow = makeArrow()
			arrows[i] = arrow
		end
		local along = TRAIL_START + (i - 1) * TRAIL_GAP + slide
		if along > length - 3 then
			arrow.Parent = nil
			continue
		end
		local spot = root.Position + dir * along
		local y = groundAt(spot, feet) + 0.12
		arrow.CFrame = CFrame.fromMatrix(Vector3.new(spot.X, y, spot.Z), right, dir, Vector3.new(0, -1, 0))
		-- Fade in near you and out at the far end of the trail.
		local reach = TRAIL_START + (TRAIL_ARROWS - 1) * TRAIL_GAP
		local fade = math.max(1 - (along - TRAIL_START) / 2, (along - reach) / TRAIL_GAP, 0)
		local image = (arrow:FindFirstChildOfClass("SurfaceGui") :: SurfaceGui):FindFirstChild("Arrow") :: ImageLabel
		image.ImageTransparency = math.clamp(0.1 + fade, 0.1, 1)
		arrow.Parent = trail
	end
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
