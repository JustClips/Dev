--!strict
-- Interaction prompts in the game's own style instead of Roblox's grey bubble. Every
-- ProximityPrompt is switched to the Custom style here, and each one that shows gets a
-- billboard: a square key box (E, the gamepad button, or a hand on touch screens) that
-- fills up green while you hold, next to a dark plate with the object's name and the
-- action. Tapping or clicking the billboard works like pressing the key.
local ProximityPromptService = game:GetService("ProximityPromptService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local PromptController = {}

local FONT = "rbxasset://fonts/families/Montserrat.json"
local INK = Color3.fromRGB(23, 25, 30)
local PLATE = Color3.fromRGB(39, 43, 52)
local KEY = Color3.fromRGB(247, 248, 250)
local FILL = Color3.fromRGB(61, 220, 90)
local SUB = Color3.fromRGB(181, 186, 198)
local POP = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- Dev: too big on PC. The billboard is drawn in screen pixels, so it gets a fixed scale.
local SCALE = if game:GetService("UserInputService").TouchEnabled then 0.8 else 0.62

local folder: ScreenGui
type Shown = { gui: BillboardGui, fill: Frame, scale: UIScale, holdStart: number?, conns: { RBXScriptConnection }, outline: Highlight? }
local shown: { [ProximityPrompt]: Shown } = {}

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		local name = prompt.GamepadKeyCode.Name
		return (string.gsub(name, "^Button", ""))
	end
	local name = prompt.KeyboardKeyCode.Name
	return if #name > 3 then string.sub(name, 1, 3) else name
end

local function label(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3, weight: Enum.FontWeight, maxSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.TextColor3 = color
	l.FontFace = Font.new(FONT, weight)
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = maxSize
	fit.Parent = l
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 2
	stroke.Parent = l
	return l
end

local function outline(parent: GuiObject, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = INK
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function build(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): Shown
	local gui = Instance.new("BillboardGui")
	gui.Name = "Prompt"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(250, 64)
	-- Centred on the object, like Roblox's own prompt (was floating too high).
	gui.StudsOffset = Vector3.new(prompt.UIOffset.X / 50, prompt.UIOffset.Y / 50, 0)
	gui.Adornee = prompt.Parent :: Instance
	gui.ResetOnSpawn = false
	gui.Active = true -- so taps on it reach the button
	local scale = Instance.new("UIScale")
	scale.Scale = SCALE * 0.6
	scale.Parent = gui

	local holder = Instance.new("TextButton")
	holder.Name = "Holder"
	holder.Text = ""
	holder.AutoButtonColor = false
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = gui

	-- Key box with the hold fill.
	local key = Instance.new("Frame")
	key.Name = "Key"
	key.Size = UDim2.fromOffset(56, 56)
	key.Position = UDim2.new(0, 4, 0.5, 0)
	key.AnchorPoint = Vector2.new(0, 0.5)
	key.BackgroundColor3 = KEY
	key.BorderSizePixel = 0
	key.ClipsDescendants = true
	key.ZIndex = 2
	key.Parent = holder
	outline(key, 3)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.BackgroundColor3 = FILL
	fill.BorderSizePixel = 0
	fill.ZIndex = 2
	fill.Parent = key
	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "Label"
	keyLabel.Size = UDim2.new(1, -8, 1, -8)
	keyLabel.Position = UDim2.fromOffset(4, 4)
	keyLabel.BackgroundTransparency = 1
	keyLabel.Text = keyText(prompt, inputType)
	keyLabel.TextColor3 = INK
	keyLabel.FontFace = Font.new(FONT, Enum.FontWeight.Heavy)
	keyLabel.TextScaled = true
	keyLabel.ZIndex = 3
	keyLabel.Parent = key

	-- Name + action plate.
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.Size = UDim2.new(1, -70, 0, 52)
	plate.Position = UDim2.new(0, 64, 0.5, 0)
	plate.AnchorPoint = Vector2.new(0, 0.5)
	plate.BackgroundColor3 = PLATE
	plate.BorderSizePixel = 0
	plate.Parent = holder
	outline(plate, 3)
	local object = label(plate, "Object", UDim2.new(1, -16, 0, 18), UDim2.fromOffset(10, 4), SUB, Enum.FontWeight.Bold, 16)
	local action = label(plate, "Action", UDim2.new(1, -16, 0, 26), UDim2.fromOffset(10, 22), Color3.new(1, 1, 1), Enum.FontWeight.Heavy, 24)
	local function refresh()
		object.Text = prompt.ObjectText
		object.Visible = prompt.ObjectText ~= ""
		action.Text = prompt.ActionText
		action.Position = if prompt.ObjectText ~= "" then UDim2.fromOffset(10, 22) else UDim2.fromOffset(10, 13)
	end
	refresh()

	local entry: Shown = { gui = gui, fill = fill, scale = scale, holdStart = nil, conns = {} }
	table.insert(entry.conns, prompt:GetPropertyChangedSignal("ActionText"):Connect(refresh))
	table.insert(entry.conns, prompt:GetPropertyChangedSignal("ObjectText"):Connect(refresh))
	-- Tapping / clicking the billboard presses the key.
	table.insert(entry.conns, holder.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldBegin()
		end
	end))
	table.insert(entry.conns, holder.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldEnd()
		end
	end))
	table.insert(entry.conns, prompt.PromptButtonHoldBegan:Connect(function()
		entry.holdStart = os.clock()
	end))
	table.insert(entry.conns, prompt.PromptButtonHoldEnded:Connect(function()
		entry.holdStart = nil
		fill.Size = UDim2.fromScale(1, 0)
	end))
	table.insert(entry.conns, prompt.Triggered:Connect(function()
		scale.Scale = SCALE * 1.15
		TweenService:Create(scale, POP, { Scale = SCALE }):Play()
	end))
	gui.Parent = folder
	TweenService:Create(scale, POP, { Scale = SCALE }):Play()
	return entry
end

-- A white outline on the thing the prompt is for (e.g. which of two eggs side by side).
-- Only small things: a prompt on a big building doesn't outline the building.
local function outlineFor(prompt: ProximityPrompt): Highlight?
	local parent = prompt.Parent
	local target: Instance? = nil
	local model = parent and parent:FindFirstAncestorOfClass("Model")
	if model and model ~= Workspace and model:GetExtentsSize().Magnitude < 22 and not model:FindFirstChildOfClass("Humanoid") then
		target = model
	elseif parent and parent:IsA("BasePart") and parent.Size.Magnitude < 22 and parent.Transparency < 1 then
		target = parent
	end
	if not target then
		return nil
	end
	local h = Instance.new("Highlight")
	h.Name = "PromptOutline"
	h.FillTransparency = 1
	h.OutlineColor = Color3.new(1, 1, 1)
	h.OutlineTransparency = 0.15
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = target
	h.Parent = target -- a Highlight draws when it sits in the world
	return h
end

local function hide(prompt: ProximityPrompt)
	local entry = shown[prompt]
	if not entry then
		return
	end
	shown[prompt] = nil
	for _, c in entry.conns do
		c:Disconnect()
	end
	if entry.outline then
		entry.outline:Destroy()
	end
	entry.gui:Destroy()
end

local function restyle(d: Instance)
	if d:IsA("ProximityPrompt") then
		d.Style = Enum.ProximityPromptStyle.Custom
	end
end

function PromptController:Init()
	-- Billboards only draw inside a ScreenGui (not a plain Folder) in PlayerGui.
	folder = Instance.new("ScreenGui")
	folder.Name = "Prompts"
	folder.ResetOnSpawn = false
	folder.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function PromptController:Start()
	for _, d in Workspace:GetDescendants() do
		restyle(d)
	end
	Workspace.DescendantAdded:Connect(restyle)
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		hide(prompt)
		local ok, entry = pcall(build, prompt, inputType)
		if ok then
			shown[prompt] = entry
			entry.outline = outlineFor(prompt)
		else
			-- Never leave a prompt invisible: fall back to Roblox's own look.
			warn("[PromptController]", entry)
			prompt.Style = Enum.ProximityPromptStyle.Default
		end
	end)
	ProximityPromptService.PromptHidden:Connect(hide)
	-- The hold fill.
	RunService.RenderStepped:Connect(function()
		for prompt, entry in shown do
			if entry.holdStart and prompt.HoldDuration > 0 then
				local t = math.clamp((os.clock() - entry.holdStart) / prompt.HoldDuration, 0, 1)
				entry.fill.Size = UDim2.fromScale(1, t)
			end
		end
	end)
end

return PromptController
