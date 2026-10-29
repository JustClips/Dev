--!strict
-- Keeps every player's hand tool above the floor. The hold and use animations are made for
-- the default avatar (art/anim/tool_anims.py), so on a shorter avatar, or when an animation
-- can't load, the tool would dip into the ground. Each frame this tilts the tool up around
-- the hand, just enough that its lowest corner stays above the floor the player stands on.
-- It only changes the grip weld on this client, so it's purely visual.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ToolGroundController = {}

local MAX_DISTANCE = 160 -- studs from the camera
local CLEARANCE = 0.05 -- studs kept between the tool and the floor
local STEP = math.rad(3)
local MAX_TILT = math.rad(110)
local EASE_DOWN = 12 -- how fast the tool settles back when it no longer needs the lift

type Info = { handle: BasePart, corners: { Vector3 }, tip: Vector3, tilt: number }
local infos: { [Tool]: Info } = setmetatable({}, { __mode = "k" }) :: any

-- Every corner of the tool's visible parts, in the handle's space (the parts are welded to
-- the handle, so this never changes).
local function measure(tool: Tool, handle: BasePart): Info
	local corners = {}
	for _, part in tool:GetDescendants() do
		if part:IsA("BasePart") and (part.Transparency < 1 or part == handle) then
			local rel = handle.CFrame:ToObjectSpace(part.CFrame)
			local h = part.Size / 2
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						table.insert(corners, rel * Vector3.new(x * h.X, y * h.Y, z * h.Z))
					end
				end
			end
		end
	end
	local tipAttachment = handle:FindFirstChild("Tip")
	local tip = if tipAttachment and tipAttachment:IsA("Attachment") then tipAttachment.Position else Vector3.new(0, 0, -2)
	return { handle = handle, corners = corners, tip = tip, tilt = 0 }
end

local function lowest(info: Info, frame: CFrame): number
	local low = math.huge
	for _, c in info.corners do
		local y = (frame * c).Y
		if y < low then
			low = y
		end
	end
	return low
end

local function floorY(root: BasePart, humanoid: Humanoid): number
	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else 0
	return root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight - legs
end

local function update(character: Model, dt: number)
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool or not tool:GetAttribute("SweepTool") then
		return
	end
	local handle = tool:FindFirstChild("Handle")
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not handle or not handle:IsA("BasePart") or not hand or not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	local weld = hand:FindFirstChild("RightGrip")
	if not weld or not weld:IsA("Weld") or weld.Part1 ~= handle then
		return
	end
	local info = infos[tool]
	if not info or info.handle ~= handle then
		info = measure(tool, handle)
		infos[tool] = info
	end

	-- Where the tool would be with its normal grip, and the smallest tilt that clears the floor.
	local grip = hand.CFrame * weld.C0
	local plain = grip * tool.Grip:Inverse()
	local floor = floorY(root, humanoid) + CLEARANCE
	local need = 0
	local pivot = grip.Position
	local out = plain * info.tip - pivot
	local axis = out:Cross(Vector3.yAxis)
	if axis.Magnitude < 0.01 then
		axis = root.CFrame.RightVector
	end
	axis = axis.Unit
	local function tilted(angle: number): CFrame
		return CFrame.new(pivot) * CFrame.fromAxisAngle(axis, angle) * CFrame.new(-pivot) * plain
	end
	if lowest(info, plain) < floor then
		need = MAX_TILT
		for angle = STEP, MAX_TILT, STEP do
			if lowest(info, tilted(angle)) >= floor then
				need = angle
				break
			end
		end
	end
	-- Lift right away, settle back down smoothly.
	if need >= info.tilt then
		info.tilt = need
	else
		info.tilt += (need - info.tilt) * math.min(1, dt * EASE_DOWN)
	end
	local c1 = if info.tilt < 0.002 then tool.Grip else tilted(info.tilt):Inverse() * grip
	if weld.C1 ~= c1 then
		weld.C1 = c1
	end
end

function ToolGroundController:Start()
	RunService.RenderStepped:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if character and root and root:IsA("BasePart") and (root.Position - eye).Magnitude < MAX_DISTANCE then
				update(character, dt)
			end
		end
	end)
end

return ToolGroundController
