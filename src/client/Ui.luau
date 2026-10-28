--!strict
-- Small UI helpers shared by controllers. Layouts live in src/gui (*.model.json);
-- controllers only find elements by name, so the art can be swapped freely.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Sounds"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

-- Modal screens: only one is open at a time.
local MODALS = { "Shop", "Index", "Rebirth" }
local POP = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PRESS = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local Ui = {}

local soundCache: { [string]: Sound } = {}
local currentScale = 1

function Ui.sound(name: string)
	local id = (Sounds :: any)[name]
	if type(id) ~= "string" or id == "" then
		return
	end
	local sound = soundCache[name]
	if not sound then
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = Sounds.Volumes[name] or 0.5
		s.Parent = SoundService
		soundCache[name] = s
		sound = s
	end
	SoundService:PlayLocalSound(sound)
end

function Ui.screen(name: string): ScreenGui
	return playerGui:WaitForChild(name) :: ScreenGui
end

-- Ui.find(root, "Window.Header.Title")
function Ui.find(root: Instance, path: string): any
	local current = root
	for part in string.gmatch(path, "[^%.]+") do
		current = current:WaitForChild(part, 10) :: Instance
		if not current then
			error(`UI element missing: {root.Name}.{path}`)
		end
	end
	return current
end

-- The Robux glyph (renders as the Robux icon in Roblox fonts).
Ui.ROBUX = utf8.char(0xE002)

function Ui.reducedMotion(): boolean
	return GuiService.ReducedMotionEnabled
end

-- Buttons keep their text in a child "Label" (so the button outline and the text
-- stroke don't fight over one UIStroke). Falls back to the object's own Text.
function Ui.setText(object: Instance, value: string)
	local label = object:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = value
	elseif object:IsA("TextLabel") or object:IsA("TextButton") then
		object.Text = value
	end
end

local function pressScale(button: GuiButton): UIScale?
	-- A button can only have one UIScale; buttons that already scale with the screen
	-- (AutoScale) don't get the press bounce.
	local existing = button:FindFirstChildOfClass("UIScale")
	if existing then
		return if existing.Name == "Press" then existing else nil
	end
	local s = Instance.new("UIScale")
	s.Name = "Press"
	s.Parent = button
	return s
end

-- Activated + press squash, hover pop on PC, click sound.
function Ui.button(button: GuiButton, fn: () -> ())
	local scale = pressScale(button)
	if scale then
		local function to(value: number, info: TweenInfo)
			if Ui.reducedMotion() then
				scale.Scale = 1
			else
				TweenService:Create(scale, info, { Scale = value }):Play()
			end
		end
		button.MouseEnter:Connect(function()
			to(1.06, HOVER)
		end)
		button.MouseLeave:Connect(function()
			to(1, HOVER)
		end)
		button.MouseButton1Down:Connect(function()
			to(0.94, PRESS)
		end)
		button.MouseButton1Up:Connect(function()
			to(1, POP)
		end)
	end
	button.Activated:Connect(function()
		Ui.sound("Click")
		fn()
	end)
end

local function popIn(gui: ScreenGui)
	local window = gui:FindFirstChild("Window")
	local scale = window and window:FindFirstChild("AutoScale") :: UIScale?
	if scale then
		if Ui.reducedMotion() then
			scale.Scale = currentScale
			return
		end
		scale.Scale = currentScale * 0.85
		TweenService:Create(scale, POP, { Scale = currentScale }):Play()
	end
end

function Ui.open(name: string)
	for _, other in MODALS do
		if other ~= name then
			local gui = playerGui:FindFirstChild(other) :: ScreenGui?
			if gui then
				gui.Enabled = false
			end
		end
	end
	local gui = Ui.screen(name)
	if not gui.Enabled then
		gui.Enabled = true
		popIn(gui)
	end
end

function Ui.close(name: string)
	local gui = playerGui:FindFirstChild(name) :: ScreenGui?
	if gui then
		gui.Enabled = false
	end
end

function Ui.toggle(name: string)
	local gui = Ui.screen(name)
	if gui.Enabled then
		Ui.close(name)
	else
		Ui.open(name)
	end
end

function Ui.scale(): number
	return currentScale
end

function Ui.popIn(gui: ScreenGui)
	popIn(gui)
end

-- Scales every UIScale named "AutoScale" with the screen height (phones get smaller UI,
-- but layouts use 64+ px buttons so taps stay >= 44 px).
local function rescale()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local s = math.clamp(camera.ViewportSize.Y / 820, 0.7, 1.15)
	currentScale = s
	for _, gui in playerGui:GetChildren() do
		for _, d in gui:GetDescendants() do
			if d:IsA("UIScale") and d.Name == "AutoScale" then
				d.Scale = s
			end
		end
	end
end

function Ui.initScaling()
	rescale()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end
	playerGui.ChildAdded:Connect(function()
		task.defer(rescale)
	end)
end

return Ui
