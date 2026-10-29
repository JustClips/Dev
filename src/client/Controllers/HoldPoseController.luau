--!strict
-- Arms that hold what you carry: while a character has a HeldEgg or HeldPet (welded in
-- front of the chest by the server), both arms reach forward under it with the elbows a
-- little bent, on every client. Runs after the animations each frame (Stepped), so the
-- walk cycle still moves the legs but not the arms. R15 only; other rigs keep their
-- animation.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local HoldPoseController = {}

local HELD = { "HeldEgg", "HeldPet" }
local PITCH = math.rad(68) -- arms forward (0 = hanging down)
local INWARD = math.rad(14) -- hands toward each other
local ELBOW = math.rad(22)
local BLEND_SPEED = 10

type Arms = { rs: Motor6D, ls: Motor6D, re: Motor6D?, le: Motor6D?, k: number }
local arms: { [Model]: Arms } = {}

local RIGHT = CFrame.Angles(0, INWARD, 0) * CFrame.Angles(PITCH, 0, 0)
local LEFT = CFrame.Angles(0, -INWARD, 0) * CFrame.Angles(PITCH, 0, 0)
local BEND = CFrame.Angles(ELBOW, 0, 0)

local function motor(character: Model, part: string, name: string): Motor6D?
	local p = character:FindFirstChild(part)
	local m = p and p:FindFirstChild(name)
	return if m and m:IsA("Motor6D") then m else nil
end

local function holding(character: Model): boolean
	for _, name in HELD do
		if character:FindFirstChild(name) then
			return true
		end
	end
	return false
end

local function armsOf(character: Model): Arms?
	local existing = arms[character]
	if existing then
		return existing
	end
	local rs = motor(character, "RightUpperArm", "RightShoulder")
	local ls = motor(character, "LeftUpperArm", "LeftShoulder")
	if not rs or not ls then
		return nil
	end
	local a: Arms = {
		rs = rs,
		ls = ls,
		re = motor(character, "RightLowerArm", "RightElbow"),
		le = motor(character, "LeftLowerArm", "LeftElbow"),
		k = 0,
	}
	arms[character] = a
	return a
end

function HoldPoseController:Start()
	RunService.Stepped:Connect(function(_time, dt)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if not character then
				continue
			end
			local on = holding(character)
			local a = if on or arms[character] then armsOf(character) else nil
			if not a then
				continue
			end
			-- Ease in and out of the pose instead of snapping.
			a.k = math.clamp(a.k + (if on then dt else -dt) * BLEND_SPEED, 0, 1)
			if a.k <= 0 then
				arms[character] = nil
				continue
			end
			local k = a.k
			a.rs.Transform = a.rs.Transform:Lerp(RIGHT, k)
			a.ls.Transform = a.ls.Transform:Lerp(LEFT, k)
			if a.re then
				a.re.Transform = a.re.Transform:Lerp(BEND, k)
			end
			if a.le then
				a.le.Transform = a.le.Transform:Lerp(BEND, k)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		if player.Character then
			arms[player.Character] = nil
		end
	end)
end

return HoldPoseController
