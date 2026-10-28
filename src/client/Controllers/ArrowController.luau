--!strict
-- Guidance beam (GAME_PLAN §4): dust -> egg -> base pad -> rocket -> shop.
-- Steps come from the server (State.data.TutorialStep). After the tutorial it still
-- points home when you carry an egg, and to the Rocket when the backpack is full.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local State = require(Client.State)

local DUST_AHEAD = 30 -- studs from your base toward the Rocket

local ArrowController = {}

local C: any
local player = Players.LocalPlayer
local targetPart: Part
local beam: Beam
local moon: Instance

local function basePad(index: number): BasePart?
	local bases = moon:FindFirstChild("Bases")
	local base = bases and bases:FindFirstChild("Base" .. index)
	return base and base:FindFirstChild("Pad") :: BasePart?
end

local function targetFor(data): Vector3?
	local step = data.TutorialStep
	local pad = basePad(data.BaseIndex)
	local rocketModel = moon:FindFirstChild("Rocket")
	local rocket = rocketModel and rocketModel:FindFirstChild("SellPad") :: BasePart?
	if step == "Sweep" and pad then
		local toCenter = (Vector3.zero - pad.Position) * Vector3.new(1, 0, 1)
		return pad.Position + toCenter.Unit * DUST_AHEAD
	elseif step == "Egg" then
		return data.TutorialTarget
	elseif (step == "Base" or step == "Hatching") and pad then
		return pad.Position
	elseif step == "Sell" and rocket then
		return if data.Backpack > 0 then rocket.Position else nil
	end
	-- After the tutorial: helpful hints only.
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
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not data or not root then
		beam.Enabled = false
		return
	end
	C.HudController:Highlight(if data.TutorialStep == "Shop" then "NextTool" else nil)
	local target = targetFor(data)
	if not target or (target - (root :: BasePart).Position).Magnitude < 8 then
		beam.Enabled = false
		return
	end
	targetPart.Position = target + Vector3.new(0, 1, 0)
	local attachment = root:FindFirstChild("ArrowAttachment") :: Attachment?
	if not attachment then
		local a = Instance.new("Attachment")
		a.Name = "ArrowAttachment"
		a.Position = Vector3.new(0, -2, 0)
		a.Parent = root
		attachment = a
	end
	beam.Attachment0 = attachment
	beam.Enabled = true
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
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 230, 90))
	beam.Width0 = 1.2
	beam.Width1 = 1.2
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureMode = Enum.TextureMode.Static
	beam.TextureLength = 3
	beam.TextureSpeed = 2
	beam.Transparency = NumberSequence.new(0.2)
	beam.Segments = 2
	beam.Enabled = false
	beam.Parent = targetPart
end

function ArrowController:Start()
	moon = Workspace:WaitForChild("Moon")
	State.Changed:Connect(update)
	while true do
		update()
		task.wait(0.5)
	end
end

return ArrowController
