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
local MODALS = { "Shop", "Index", "Rebirth", "Garage", "Upgrades", "Inventory", "Daily", "Playtime", "Events", "Settings" }
local POP = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PRESS = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local Ui = {}

local soundCache: { [string]: Sound } = {}
local currentScale = 1

-- The "SFX" and "Music" sound groups (volume sliders in the settings window).
function Ui.soundGroup(name: string): SoundGroup
	local group = SoundService:FindFirstChild(name)
	if group and group:IsA("SoundGroup") then
		return group
	end
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Volume = 1
	g.Parent = SoundService
	return g
end

-- Plays a sound effect from Config/Sounds. speed changes the pitch (combo blips).
function Ui.sound(name: string, speed: number?)
	local def = Sounds.Sfx[name]
	if not def or def.Id == "" then
		return
	end
	local sound = soundCache[name]
	if not sound then
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = def.Id
		s.Volume = def.Volume
		s.PlaybackSpeed = def.Speed or 1
		s.SoundGroup = Ui.soundGroup("SFX")
		s.Parent = SoundService
		soundCache[name] = s
		sound = s
	end
	-- A fresh copy per play, so sounds can overlap and still follow the SFX slider.
	local copy = sound:Clone()
	copy.PlaybackSpeed = (def.Speed or 1) * (speed or 1)
	copy.Parent = SoundService
	copy.Ended:Once(function()
		copy:Destroy()
	end)
	copy:Play()
	task.delay(12, function()
		if copy.Parent then
			copy:Destroy()
		end
	end)
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

-- Open/close motion for screens with a "Window" (and optional "Dim" backdrop):
-- the window pops up from 60 % with a small overshoot and the backdrop fades in. Closing
-- shrinks the window away while the backdrop fades out, then disables the screen. The
-- window never moves, only scales, so nothing slides around. A token per screen lets a
-- new open cancel a running close (and the other way round).
local OPEN = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local FADE_IN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OPEN_FROM = 0.6
local CLOSE_TO = 0.05
local DIM_ALPHA = 0.6

local motionToken: { [ScreenGui]: number } = setmetatable({}, { __mode = "k" }) :: any
local homePosition: { [GuiObject]: UDim2 } = setmetatable({}, { __mode = "k" }) :: any
local closing: { [ScreenGui]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function parts(gui: ScreenGui): (GuiObject?, UIScale?, GuiObject?)
	local window = gui:FindFirstChild("Window") :: GuiObject?
	local scale = window and window:FindFirstChild("AutoScale") :: UIScale?
	local dim = gui:FindFirstChild("Dim") :: GuiObject?
	if window and not homePosition[window] then
		homePosition[window] = window.Position
	end
	return window, scale, dim
end

local function bump(gui: ScreenGui): number
	local token = (motionToken[gui] or 0) + 1
	motionToken[gui] = token
	return token
end

local function settle(gui: ScreenGui)
	local window, scale, dim = parts(gui)
	if window then
		window.Position = homePosition[window]
	end
	if scale then
		scale.Scale = currentScale
	end
	if dim then
		dim.BackgroundTransparency = DIM_ALPHA
	end
end

-- Enables a screen and plays the open motion.
function Ui.show(gui: ScreenGui)
	bump(gui)
	closing[gui] = nil
	gui.Enabled = true
	settle(gui)
	if Ui.reducedMotion() then
		return
	end
	local _, scale, dim = parts(gui)
	if scale then
		scale.Scale = currentScale * OPEN_FROM
		TweenService:Create(scale, OPEN, { Scale = currentScale }):Play()
	end
	if dim then
		dim.BackgroundTransparency = 1
		TweenService:Create(dim, FADE_IN, { BackgroundTransparency = DIM_ALPHA }):Play()
	end
end

-- Plays the close motion, then disables the screen.
function Ui.hide(gui: ScreenGui, instant: boolean?)
	local token = bump(gui)
	if not gui.Enabled then
		closing[gui] = nil
		return
	end
	if instant or Ui.reducedMotion() then
		closing[gui] = nil
		gui.Enabled = false
		settle(gui)
		return
	end
	closing[gui] = true
	local _, scale, dim = parts(gui)
	if scale then
		TweenService:Create(scale, CLOSE, { Scale = currentScale * CLOSE_TO }):Play()
	end
	if dim then
		TweenService:Create(dim, FADE_OUT, { BackgroundTransparency = 1 }):Play()
	end
	task.delay(CLOSE.Time, function()
		if motionToken[gui] == token then
			closing[gui] = nil
			gui.Enabled = false
			settle(gui)
		end
	end)
end

-- True while the screen is shown and not on its way out.
function Ui.isOpen(gui: ScreenGui): boolean
	return gui.Enabled and not closing[gui]
end

function Ui.open(name: string)
	for _, other in MODALS do
		if other ~= name then
			local gui = playerGui:FindFirstChild(other) :: ScreenGui?
			if gui then
				Ui.hide(gui, true)
			end
		end
	end
	local gui = Ui.screen(name)
	if not Ui.isOpen(gui) then
		Ui.show(gui)
	end
end

function Ui.close(name: string)
	local gui = playerGui:FindFirstChild(name) :: ScreenGui?
	if gui then
		Ui.hide(gui)
	end
end

function Ui.toggle(name: string)
	local gui = Ui.screen(name)
	if Ui.isOpen(gui) then
		Ui.close(name)
	else
		Ui.open(name)
	end
end

function Ui.scale(): number
	return currentScale
end

-- Small pop for dropdowns (a frame with an AutoScale UIScale).
function Ui.popFrame(frame: GuiObject)
	local scale = frame:FindFirstChild("AutoScale") :: UIScale?
	if not scale or Ui.reducedMotion() then
		return
	end
	scale.Scale = currentScale * 0.85
	TweenService:Create(scale, OPEN, { Scale = currentScale }):Play()
end

-- Kept for older callers: same as Ui.show on an already enabled screen.
function Ui.popIn(gui: ScreenGui)
	Ui.show(gui)
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
