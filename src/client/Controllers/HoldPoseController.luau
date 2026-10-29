--!strict
-- Arms that hold what you carry: while a character has a HeldEgg or HeldPet (welded in
-- front of the chest by the server), both arms reach forward under it with the elbows a
-- little bent, on every client. The arms breathe a little when you stand and bounce in
-- step when you walk, so it reads as carrying. R15 and R6.
--
-- The pose goes into the joint's own offset (Motor6D.C0, or Attachment0 on rigs that use
-- AnimationConstraints), which animations never write, so it shows no matter when the
-- Animator runs. Each frame we also fade the animation's own arm motion (Transform) out,
-- so the walk cycle moves the legs but doesn't swing the arms.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local HoldPoseController = {}

local HELD = { "HeldEgg", "HeldPet" }
local PITCH = math.rad(68) -- arms forward (0 = hanging down)
local INWARD = math.rad(14) -- hands toward each other
local ELBOW = math.rad(22)
local BLEND_SPEED = 10

-- A Motor6D on classic rigs, or an AnimationConstraint when Roblox's avatar joint upgrade
-- is on. Both have a Transform that the Animator writes.
type Joint = any
type Slot = { joint: Joint, base: CFrame }
type Arms = { rs: Slot, ls: Slot, re: Slot?, le: Slot?, k: number, r6: boolean, phase: number }
local arms: { [Model]: Arms } = {}
local warned: { [Model]: boolean } = {}

local RIGHT = CFrame.Angles(0, INWARD, 0) * CFrame.Angles(PITCH, 0, 0)
local LEFT = CFrame.Angles(0, -INWARD, 0) * CFrame.Angles(PITCH, 0, 0)
local BEND = CFrame.Angles(ELBOW, 0, 0)

-- Finds the joint that moves a limb, whatever it is called and whatever class it is.
local function jointFor(character: Model, limb: string): Joint?
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") then
			if d.Part1 and d.Part1.Name == limb then
				return d
			end
		elseif d:IsA("AnimationConstraint") then
			local a1 = d.Attachment1
			if a1 and a1.Parent and a1.Parent.Name == limb then
				return d
			end
		end
	end
	return nil
end

local function getOffset(j: Joint): CFrame
	if j:IsA("Motor6D") then
		return j.C0
	end
	local a0 = j.Attachment0
	return if a0 then a0.CFrame else CFrame.identity
end

local function setOffset(j: Joint, cf: CFrame)
	if j:IsA("Motor6D") then
		j.C0 = cf
	elseif j.Attachment0 then
		j.Attachment0.CFrame = cf
	end
end

local function slot(j: Joint?): Slot?
	return if j then { joint = j, base = getOffset(j) } else nil
end

local function alive(s: Slot?): boolean
	return s ~= nil and s.joint.Parent ~= nil
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
	-- Joints can be swapped after spawn (joint upgrade), so check they are still there.
	if existing and alive(existing.rs) and alive(existing.ls) then
		return existing
	end
	local rs = jointFor(character, "RightUpperArm")
	local ls = jointFor(character, "LeftUpperArm")
	local r6 = false
	if not rs or not ls then
		rs = jointFor(character, "Right Arm")
		ls = jointFor(character, "Left Arm")
		r6 = true
	end
	if not rs or not ls then
		if not warned[character] then
			warned[character] = true
			warn("[HoldPose] no arm joints found on", character:GetFullName())
		end
		return nil
	end
	local a: Arms = {
		rs = slot(rs) :: Slot,
		ls = slot(ls) :: Slot,
		re = if r6 then nil else slot(jointFor(character, "RightLowerArm")),
		le = if r6 then nil else slot(jointFor(character, "LeftLowerArm")),
		k = if existing then existing.k else 0,
		r6 = r6,
		phase = if existing then existing.phase else 0,
	}
	arms[character] = a
	return a
end

local function each(a: Arms, fn: (Slot) -> ())
	fn(a.rs)
	fn(a.ls)
	if a.re then
		fn(a.re)
	end
	if a.le then
		fn(a.le)
	end
end

-- Puts every joint back exactly as it was.
local function release(a: Arms)
	each(a, function(s)
		if s.joint.Parent then
			setOffset(s.joint, s.base)
		end
	end)
end

local function pose(s: Slot?, rot: CFrame, k: number)
	if not s then
		return
	end
	setOffset(s.joint, s.base * CFrame.identity:Lerp(rot, k))
end

function HoldPoseController:Start()
	-- Pose: once a frame, before rendering.
	RunService.Heartbeat:Connect(function(dt)
		for character in arms do
			if not character.Parent then
				arms[character] = nil
				warned[character] = nil
			end
		end
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
				release(a)
				arms[character] = nil
				continue
			end
			local k = a.k
			-- A little life: slow breathing standing still, a bounce in step when walking.
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local v = if root then root.AssemblyLinearVelocity else Vector3.zero
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			a.phase += dt * (if speed > 1 then 2 + speed * 0.45 else 1.6)
			local sway = if speed > 1 then math.sin(a.phase * 2) * 0.06 else math.sin(a.phase) * 0.03
			if a.r6 then
				-- R6 shoulders turn about their own Z (the old tool pose used 1.57).
				local lift = PITCH + 0.15 + sway
				pose(a.rs, CFrame.Angles(0, 0, lift), k)
				pose(a.ls, CFrame.Angles(0, 0, -lift), k)
			else
				local wobble = CFrame.Angles(sway, 0, 0)
				pose(a.rs, RIGHT * wobble, k)
				pose(a.ls, LEFT * wobble, k)
				pose(a.re, BEND, k)
				pose(a.le, BEND, k)
			end
		end
	end)
	-- Fade out the animation's arm swing. Stepped runs after the Animator, so this sticks.
	RunService.Stepped:Connect(function()
		for _, a in arms do
			local k = a.k
			each(a, function(s)
				if s.joint.Parent then
					s.joint.Transform = s.joint.Transform:Lerp(CFrame.identity, k)
				end
			end)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		if player.Character then
			arms[player.Character] = nil
			warned[player.Character] = nil
		end
	end)
end

return HoldPoseController
