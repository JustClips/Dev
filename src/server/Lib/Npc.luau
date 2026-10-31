--!strict
-- Base NPCs (the Pet Trader, the Quest Master): an R15 figure from a HumanoidDescription
-- (block figure fallback), anchored at a CFrame, with a name tag, idle breathing and a
-- "Talk" prompt whose attribute Opens says which client controller handles it.
local Players = game:GetService("Players")

local Npc = {}

export type Spec = {
	Name: string, -- model name
	Title: string, -- name tag
	Sub: string, -- line under the name
	TitleColor: Color3,
	Opens: string, -- prompt attribute
	Skin: Color3,
	Shirt: Color3,
	Pants: Color3,
	Hat: number?, -- optional accessory asset id
}

local TALK_DISTANCE = 10 -- prompt reach
local IDLE_ANIMATION = "rbxassetid://507766388" -- Roblox's default R15 idle

local function description(spec: Spec): HumanoidDescription
	local d = Instance.new("HumanoidDescription")
	d.HeadColor = spec.Skin
	d.LeftArmColor = spec.Skin
	d.RightArmColor = spec.Skin
	d.TorsoColor = spec.Shirt
	d.LeftLegColor = spec.Pants
	d.RightLegColor = spec.Pants
	if spec.Hat then
		d.HatAccessory = tostring(spec.Hat)
	end
	return d
end

-- A plain block figure, used when the avatar service can't build one (tests, outages).
local function blockFigure(spec: Spec): Model
	local model = Instance.new("Model")
	local function piece(name: string, size: Vector3, offset: Vector3, color: Color3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Anchored = true
		p.CFrame = CFrame.new(offset)
		p.Parent = model
		return p
	end
	local root = piece("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), spec.Shirt)
	root.Transparency = 1
	piece("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), spec.Shirt)
	piece("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.6, 0), spec.Skin)
	piece("Legs", Vector3.new(2, 2, 1), Vector3.new(0, 1, 0), spec.Pants)
	model.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	return model
end

local function nameTag(head: BasePart, spec: Spec)
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	-- Sized in studs so it shrinks with distance like a real sign (a fixed pixel size was
	-- huge up close), and drawn on top so the stall roof doesn't cut through it.
	gui.Size = UDim2.fromScale(4.6, 1.25)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1.9, 0)
	gui.MaxDistance = 45
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = head
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.6)
	title.BackgroundTransparency = 1
	title.Text = spec.Title
	title.TextScaled = true
	title.TextColor3 = spec.TitleColor
	title.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
	title.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(23, 25, 30)
	stroke.Parent = title
	local sub = title:Clone()
	sub.Text = spec.Sub
	sub.TextColor3 = Color3.new(1, 1, 1)
	sub.Size = UDim2.fromScale(1, 0.4)
	sub.Position = UDim2.fromScale(0, 0.6)
	sub.Parent = gui
end

-- Builds the NPC standing at cf (feet on cf's floor), parents it and returns its root part.
-- Yields (avatar building).
function Npc.build(spec: Spec, cf: CFrame, parent: Instance): BasePart?
	local ok, made = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description(spec), Enum.HumanoidRigType.R15)
	end)
	if not ok and spec.Hat then
		-- The hat failed to load: try once more without it.
		local plain = table.clone(spec)
		plain.Hat = nil
		ok, made = pcall(function()
			return Players:CreateHumanoidModelFromDescription(description(plain), Enum.HumanoidRigType.R15)
		end)
	end
	local model: Model = if ok and made then made else blockFigure(spec)
	model.Name = spec.Name
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		model:Destroy()
		return nil
	end
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = d == root
		end
	end
	local height = if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then humanoid.HipHeight + root.Size.Y / 2 else 3
	model:PivotTo(cf * CFrame.new(0, height, 0))
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		nameTag(head, spec)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TalkPrompt"
	prompt.ActionText = "Talk"
	prompt.ObjectText = spec.Title
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = TALK_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("Opens", spec.Opens)
	prompt.Parent = root
	model.Parent = parent
	-- Idle breathing so they look alive.
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
		pcall(function()
			local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
			animator.Parent = humanoid
			local animation = Instance.new("Animation")
			animation.AnimationId = IDLE_ANIMATION
			local track = (animator :: Animator):LoadAnimation(animation)
			track.Looped = true
			track:Play()
		end)
	end
	return root
end

-- True when the player's character is within reach studs of any of the roots.
function Npc.isNear(player: Player, roots: { BasePart }, reach: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	for _, npc in roots do
		if (npc.Position - root.Position).Magnitude <= reach then
			return true
		end
	end
	return false
end

return Npc
