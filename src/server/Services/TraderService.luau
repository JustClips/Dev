--!strict
-- The Pet Trader: an NPC behind a market stall on every base (stall: MapBuilder). Talking
-- to him (a "Talk" prompt) opens the trader dialog on the client (TraderController), which
-- sells through the Inventory remote: SellHeld, SellAllPets, Appraise. Those check IsNear.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)

local TraderService = {}

local TALK_DISTANCE = 10 -- prompt reach
local SELL_DISTANCE = 18 -- the server's check (a little looser than the prompt)
local IDLE_ANIMATION = "rbxassetid://507766388" -- Roblox's default R15 idle

local folder: Folder
local roots: { BasePart } = {}

local SKIN = Color3.fromRGB(255, 204, 153)
local SHIRT = Color3.fromRGB(74, 164, 82)
local PANTS = Color3.fromRGB(120, 84, 52)

local function description(): HumanoidDescription
	local d = Instance.new("HumanoidDescription")
	d.HeadColor = SKIN
	d.LeftArmColor = SKIN
	d.RightArmColor = SKIN
	d.TorsoColor = SHIRT
	d.LeftLegColor = PANTS
	d.RightLegColor = PANTS
	return d
end

-- A plain block figure, used when the avatar service can't build one (tests, outages).
local function blockFigure(): Model
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
	local root = piece("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), SHIRT)
	root.Transparency = 1
	piece("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), SHIRT)
	piece("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.6, 0), SKIN)
	piece("Legs", Vector3.new(2, 2, 1), Vector3.new(0, 1, 0), PANTS)
	model.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	return model
end

local function nameTag(head: BasePart)
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
	title.Text = "Pet Trader"
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 200, 60)
	title.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
	title.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(23, 25, 30)
	stroke.Parent = title
	local sub = title:Clone()
	sub.Text = "Sells your pets"
	sub.TextColor3 = Color3.new(1, 1, 1)
	sub.Size = UDim2.fromScale(1, 0.4)
	sub.Position = UDim2.fromScale(0, 0.6)
	sub.Parent = gui
end

local function build(index: number)
	local cf = World.traderCFrame(index)
	local ok, made = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description(), Enum.HumanoidRigType.R15)
	end)
	local model: Model = if ok and made then made else blockFigure()
	model.Name = "PetTrader" .. index
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		model:Destroy()
		return
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
		nameTag(head)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TalkPrompt"
	prompt.ActionText = "Talk"
	prompt.ObjectText = "Pet Trader"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = TALK_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("Opens", "Trader")
	prompt.Parent = root
	model.Parent = folder
	table.insert(roots, root)
	-- Idle breathing so he looks alive.
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
end

-- True when the player stands close to a Pet Trader.
function TraderService:IsNear(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	for _, trader in roots do
		if (trader.Position - root.Position).Magnitude <= SELL_DISTANCE then
			return true
		end
	end
	return false
end

function TraderService:Init(_services)
	folder = Instance.new("Folder")
	folder.Name = "Traders"
	folder.Parent = Workspace
end

function TraderService:Start()
	for i = 1, World.BaseCount do
		task.spawn(build, i)
	end
end

return TraderService
