--!strict
-- Small UI helpers shared by controllers. Layouts live in src/gui (*.model.json);
-- controllers only find elements by name, so the art can be swapped freely.
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Sounds"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Assets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Assets"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

-- Modal screens: only one is open at a time.
local MODALS = { "Shop", "Index", "Rebirth", "Garage", "Upgrades", "Inventory", "Daily", "Playtime", "Events", "Settings", "Dialog", "GroupReward", "BasePicker", "Quests" }
local POP = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PRESS = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local Ui = {}

local soundCache: { [string]: Sound } = {}
-- HUD scale (edge clusters) and window scale (modals); see rescale() at the bottom.
local currentScale = 1
local windowScale = 1
local compactLayout = false
local scaleListeners: { (number, boolean) -> () } = {}

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

-- StarterGui only copies into PlayerGui once the character spawns (after the save loads),
-- so this can take a while on join; wait without the "infinite yield" warning.
function Ui.screen(name: string): ScreenGui
	local gui = playerGui:FindFirstChild(name)
	while not gui do
		playerGui.ChildAdded:Wait()
		gui = playerGui:FindFirstChild(name)
	end
	return gui :: ScreenGui
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

local handlers: { [GuiButton]: () -> () } = setmetatable({}, { __mode = "k" }) :: any

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
	handlers[button] = fn
	button.Activated:Connect(function()
		Ui.sound("Click")
		fn()
	end)
end

-- What Ui.button runs for a button (GamepadController presses Close buttons with B).
function Ui.handler(button: GuiButton): (() -> ())?
	return handlers[button]
end

-- True while the player plays with a controller (console, or a gamepad on PC/phone).
local GAMEPADS = {
	[Enum.UserInputType.Gamepad1] = true,
	[Enum.UserInputType.Gamepad2] = true,
	[Enum.UserInputType.Gamepad3] = true,
	[Enum.UserInputType.Gamepad4] = true,
}
local usingGamepad = GuiService:IsTenFootInterface() or GAMEPADS[UserInputService:GetLastInputType()] == true
UserInputService.LastInputTypeChanged:Connect(function(kind)
	if GAMEPADS[kind] then
		usingGamepad = true
	elseif kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.Keyboard or kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.MouseMovement then
		usingGamepad = false
	end
end)
function Ui.gamepad(): boolean
	return usingGamepad
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
	-- Modal windows use the window scale (they fit the screen), not the HUD scale.
	local window = gui:FindFirstChild("Window") :: GuiObject?
	local scale = window and window:FindFirstChild("AutoScale") :: UIScale?
	local dim = gui:FindFirstChild("Dim") :: GuiObject?
	if window and not homePosition[window] then
		homePosition[window] = window.Position
	end
	return window, scale, dim
end

-- Big pages (shop, index, rebirth...) get an "opening" feel: the camera zooms out a little
-- and the world behind blurs. Side panels and the backpack don't.
local FOCUS_SCREENS = {
	Shop = true,
	Index = true,
	Rebirth = true,
	Garage = true,
	Upgrades = true,
	Daily = true,
	Playtime = true,
	Events = true,
	Settings = true,
}
local FOCUS_IN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FOCUS_OUT = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FOCUS_BLUR = 12
local FOCUS_FOV = 8
local focused = false
local baseFov: number? = nil

local function focusBlur(): BlurEffect
	local blur = Lighting:FindFirstChild("WindowBlur") :: BlurEffect?
	if not blur then
		local made = Instance.new("BlurEffect")
		made.Name = "WindowBlur"
		made.Size = 0
		made.Parent = Lighting
		blur = made
	end
	return blur :: BlurEffect
end

local function updateFocus()
	local want = false
	for name in FOCUS_SCREENS do
		local gui = playerGui:FindFirstChild(name) :: ScreenGui?
		if gui and gui.Enabled and not closing[gui] then
			want = true
			break
		end
	end
	if want == focused then
		return
	end
	focused = want
	local camera = Workspace.CurrentCamera
	local still = Ui.reducedMotion()
	local blur = focusBlur()
	TweenService:Create(blur, if want then FOCUS_IN else FOCUS_OUT, { Size = if want then FOCUS_BLUR else 0 }):Play()
	if not camera or still or camera.CameraType ~= Enum.CameraType.Custom then
		if not want and camera and baseFov then
			camera.FieldOfView = baseFov
		end
		if not want then
			baseFov = nil
		end
		return
	end
	if want then
		-- Keep the old base when switching straight from one page to another.
		baseFov = baseFov or camera.FieldOfView
		TweenService:Create(camera, FOCUS_IN, { FieldOfView = (baseFov :: number) + FOCUS_FOV }):Play()
	elseif baseFov then
		local tween = TweenService:Create(camera, FOCUS_OUT, { FieldOfView = baseFov })
		tween.Completed:Connect(function()
			if not focused then
				baseFov = nil
			end
		end)
		tween:Play()
	end
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
		scale.Scale = windowScale
	end
	if dim then
		dim.BackgroundTransparency = DIM_ALPHA
	end
end

-- Moves a window's resting place (windows that sit next to a HUD button instead of the
-- screen centre): Ui.show puts the window back here every time it opens.
function Ui.setHome(window: GuiObject, position: UDim2)
	homePosition[window] = position
	window.Position = position
end

-- Enables a screen and plays the open motion.
function Ui.show(gui: ScreenGui)
	bump(gui)
	closing[gui] = nil
	gui.Enabled = true
	settle(gui)
	updateFocus()
	if Ui.reducedMotion() then
		return
	end
	local _, scale, dim = parts(gui)
	if scale then
		scale.Scale = windowScale * OPEN_FROM
		TweenService:Create(scale, OPEN, { Scale = windowScale }):Play()
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
		updateFocus()
		return
	end
	closing[gui] = true
	updateFocus()
	local _, scale, dim = parts(gui)
	if scale then
		TweenService:Create(scale, CLOSE, { Scale = windowScale * CLOSE_TO }):Play()
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
		Ui.report("Open", name)
	end
end

-- Tells the server's AnalyticsService something only the client knows (never yields).
function Ui.report(kind: string, arg: string?)
	task.spawn(function()
		pcall(function()
			Net.event("Analytics"):FireServer(kind, arg)
		end)
	end)
end

-- The open full window's screen, if any.
function Ui.openModal(): ScreenGui?
	for _, name in MODALS do
		local gui = playerGui:FindFirstChild(name) :: ScreenGui?
		if gui and Ui.isOpen(gui) then
			return gui
		end
	end
	return nil
end

-- True while any full window (shop, inventory, panels...) is open.
function Ui.anyWindowOpen(): boolean
	for _, name in MODALS do
		local gui = playerGui:FindFirstChild(name) :: ScreenGui?
		if gui and Ui.isOpen(gui) then
			return true
		end
	end
	return false
end

-- Closes every open window (a HUD menu opening over a window would be shut by it again).
function Ui.closeWindows()
	for _, name in MODALS do
		local gui = playerGui:FindFirstChild(name) :: ScreenGui?
		if gui and Ui.isOpen(gui) then
			Ui.hide(gui)
		end
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

-- The scale full windows open at (fits the screen).
function Ui.windowScale(): number
	return windowScale
end

function Ui.scale(): number
	return currentScale
end

-- Scale of modal windows (shop, settings...): they fit the screen on phones.
function Ui.windowScale(): number
	return windowScale
end

-- True on short screens (phones in landscape): HUD clusters move to their phone spots.
function Ui.compact(): boolean
	return compactLayout
end

-- Calls fn(hudScale, compact) now and every time the screen size changes.
function Ui.onScale(fn: (number, boolean) -> ())
	table.insert(scaleListeners, fn)
	task.spawn(fn, currentScale, compactLayout)
end

local function isModal(scale: UIScale): boolean
	local parent = scale.Parent
	return parent ~= nil and (parent.Name == "Window" or parent:GetAttribute("Modal") == true)
end

-- Count badges (Dev, 2026-10-31, from his reference): a round red badge with a white
-- border and a white number. Ui.setBadge shows the count (nil/0 hides it, a string is
-- shown as is) and pops it when the count goes up. Every 10 seconds each visible badge
-- sends out two soft red waves, a moment apart, so it catches the eye.
-- The look is applied here at runtime, so every badge in the game (gen_ui.py or older
-- place files) gets it.
local badgeCounts: { [GuiObject]: string } = setmetatable({}, { __mode = "k" }) :: any
local badgeBase: { [GuiObject]: number } = setmetatable({}, { __mode = "k" }) :: any
local pulseStarted = false
local BADGE_TOP = Color3.fromRGB(255, 72, 96) -- glossy top of the red
local BADGE_BOTTOM = Color3.fromRGB(176, 8, 40)
local BADGE_RING = Color3.fromRGB(255, 255, 255)
-- Pulse (Dev, 2026-11-01, round 3, then "only twice each 10s": "pulse twice, a gap of 0.5s ... each
-- pulse should increase by 0.2x with a tween in 0.4s", cartoony not harsh): the badge
-- circle itself bumps to 1.2x and back, twice, each bump sending out a thin ring. Every badge
-- runs on the same 10 s beat but with its own offset, so they don't all go at once.
local PULSE_EVERY = 10 -- seconds between one badge's double pulse (Dev: twice every 10 s)
local PULSE_GAP = 0.5 -- seconds between the two pulses
local PULSE_BUMP = 1.2 -- the badge's size at the top of a pulse
local PULSE_BUMP_TIME = 0.4 -- one grow-and-back
local PULSE_TIME = 1.1 -- how long one ring takes to grow and fade
local PULSE_GROW = 2.4 -- how big a ring gets, relative to the badge
local BADGE_FILL = Color3.fromRGB(214, 22, 52)
local nextPulse: { [GuiObject]: number } = setmetatable({}, { __mode = "k" }) :: any

-- Turns a badge into the cartoony round badge (once per badge): a glossy red disc with a
-- thick white rim and a thin dark outline, white number with a dark edge.
local function styleBadge(badge: GuiObject)
	if badgeBase[badge] then
		return
	end
	local px = badge.Size.Y.Offset
	badgeBase[badge] = px
	badge.Rotation = 0
	-- Centred on the button's top-right corner, a little inside it, so it reads as part of
	-- that button and never hangs half off the screen (Dev, 2026-11-01: badges looked
	-- misplaced).
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(1, -4, 0, 4)
	-- One disc: glossy red fill with a thick white rim drawn by the stroke (a red disc
	-- nested inside a white one rounded to different pixels on small screens and looked
	-- off-centre, Dev 2026-11-01).
	-- The disc is its own child so the pulse can grow it while the number stays still
	-- (Dev 2026-11-01: on phones the digits shifted left and right while the badge scaled).
	badge.BackgroundTransparency = 1
	for _, old in badge:GetChildren() do
		if old:IsA("UIStroke") or old:IsA("UIGradient") or old:IsA("UIScale") or old.Name == "Red" then
			old:Destroy()
		end
	end
	local label = badge:FindFirstChild("Label") :: TextLabel?
	local disc = badge:FindFirstChild("Disc") :: Frame? or Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(1, 1)
	disc.BorderSizePixel = 0
	disc.BackgroundColor3 = Color3.new(1, 1, 1)
	disc.BackgroundTransparency = 0
	disc.ZIndex = badge.ZIndex
	disc.Parent = badge
	local corner = disc:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = disc
	local stroke = disc:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.Color = BADGE_RING
	stroke.Thickness = math.max(2, math.floor(px / 10 + 0.5))
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = disc
	local gradient = disc:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(BADGE_TOP, BADGE_BOTTOM)
	gradient.Rotation = 90
	gradient.Parent = disc
	local pop = disc:FindFirstChild("BadgePop") :: UIScale? or Instance.new("UIScale")
	pop.Name = "BadgePop"
	pop.Scale = 1
	pop.Parent = disc
	if label then
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = false
		label.TextWrapped = false
		label.Size = UDim2.fromScale(1, 1)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.ZIndex = badge.ZIndex + 1
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
		local edge = label:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
		edge.Color = Color3.fromRGB(110, 0, 22)
		edge.Thickness = math.max(1, px / 22)
		edge.Transparency = 0
		edge.Parent = label
	end
end

-- One ring: a thin red-and-white outline circle behind the badge that grows and fades.
-- It is a sibling of the badge one layer below it (with Sibling z-order a child would draw
-- on top).
local function waveFrom(badge: GuiObject)
	local host = badge.Parent
	if not (host and host:IsA("GuiObject")) then
		return
	end
	local size = badge.Size
	local h = size.Y.Offset
	local pos, anchor = badge.Position, badge.AnchorPoint
	local w = size.X.Offset
	local ring = Instance.new("Frame")
	ring.Name = "BadgeWave"
	ring.BorderSizePixel = 0
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Size = UDim2.fromOffset(h, h)
	ring.Position = UDim2.new(
		pos.X.Scale + size.X.Scale * (0.5 - anchor.X),
		pos.X.Offset + w * (0.5 - anchor.X),
		pos.Y.Scale + size.Y.Scale * (0.5 - anchor.Y),
		pos.Y.Offset + h * (0.5 - anchor.Y)
	)
	ring.ZIndex = badge.ZIndex - 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = BADGE_FILL
	stroke.Thickness = math.max(2, math.floor(h / 9 + 0.5))
	stroke.Transparency = 0.1
	stroke.Parent = ring
	ring.Parent = host
	-- Grow the frame itself (a UIScale would also thicken the outline).
	local info = TweenInfo.new(PULSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local big = math.floor(h * PULSE_GROW + 0.5)
	TweenService:Create(ring, info, { Size = UDim2.fromOffset(big, big) }):Play()
	local fade = TweenService:Create(stroke, info, { Transparency = 1, Thickness = 1 })
	fade.Completed:Once(function()
		ring:Destroy()
	end)
	fade:Play()
end

-- One pulse: the badge bumps to 1.2x and back in 0.4 s and sends out a ring.
local function pulseOnce(badge: GuiObject)
	if not (badge.Parent and badge.Visible) then
		return
	end
	local disc = badge:FindFirstChild("Disc")
	local pop = disc and disc:FindFirstChild("BadgePop") :: UIScale?
	if pop then
		local half = PULSE_BUMP_TIME / 2
		local up = TweenService:Create(pop, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = PULSE_BUMP,
		})
		up.Completed:Once(function()
			TweenService:Create(pop, TweenInfo.new(half, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
		up:Play()
	end
	waveFrom(badge)
end

-- When each badge last pulsed. Kept while a badge hides, so a badge that flickers off and
-- on (or whose count keeps changing) can't pulse more than once per beat (Dev, 2026-11-01:
-- one badge sometimes pulsed nonstop).
local lastPulse: { [GuiObject]: number } = setmetatable({}, { __mode = "k" }) :: any

local function pulseTwice(badge: GuiObject)
	local now = os.clock()
	if now - (lastPulse[badge] or -math.huge) < PULSE_EVERY - 0.2 then
		return
	end
	lastPulse[badge] = now
	pulseOnce(badge)
	task.delay(PULSE_GAP, pulseOnce, badge)
end

local function startPulse()
	if pulseStarted then
		return
	end
	pulseStarted = true
	task.spawn(function()
		while true do
			task.wait(0.1)
			if not Ui.reducedMotion() then
				local now = os.clock()
				for badge in badgeCounts do
					local due = nextPulse[badge]
					if not due then
						-- First time: somewhere in the next beat, not in step with the others.
						nextPulse[badge] = now + 0.5 + math.random() * PULSE_EVERY
					elseif now >= due then
						nextPulse[badge] = now + PULSE_EVERY
						pulseTwice(badge)
					end
				end
			end
		end
	end)
end

-- With Sibling z-order a badge is drawn inside its button's layer, so a neighbouring
-- button drawn later covers the corner that sticks out. While a badge shows, its button
-- goes one layer up.
local function liftHost(badge: GuiObject, lifted: boolean)
	local host = badge.Parent
	if not (host and host:IsA("GuiObject")) then
		return
	end
	local baseZ = host:GetAttribute("BaseZIndex")
	if type(baseZ) ~= "number" then
		baseZ = host.ZIndex
		host:SetAttribute("BaseZIndex", baseZ)
	end
	-- A badge sticks out up and to the right, so the button to its right (or above it)
	-- would cover it if both are lifted the same. Buttons further left / lower go higher.
	local rank = 0
	if lifted then
		local at = host.AbsolutePosition
		rank = math.clamp(math.floor((at.Y - at.X + 4000) / 30), 0, 400)
	end
	host.ZIndex = if lifted then (baseZ :: number) + 1 + rank else baseZ :: number
end

-- Badge numbers are images (art: Montserrat Black, white with a dark-red edge, each cropped
-- to its own ink), not text. Text snapped to different pixels on phones' scaled HUD and sat
-- off-centre (Dev 2026-11-01); scaled images centre exactly at any size.
local DIGIT_ASPECT = {
	["0"] = 0.949, ["1"] = 0.646, ["2"] = 0.874, ["3"] = 0.874, ["4"] = 0.975, ["5"] = 0.869,
	["6"] = 0.914, ["7"] = 0.899, ["8"] = 0.934, ["9"] = 0.914, ["+"] = 0.869,
}
local function badgeDigits(badge: GuiObject, label: TextLabel?, shown: string, px: number)
	local images = Assets.Images :: { [string]: string }
	local usable = images.Digit_0 ~= nil
	for i = 1, #shown do
		if not DIGIT_ASPECT[string.sub(shown, i, i)] then
			usable = false
		end
	end
	local holder = badge:FindFirstChild("Digits") :: Frame?
	if not usable then
		if holder then
			holder.Visible = false
		end
		if label then
			label.Visible = true
		end
		return
	end
	if label then
		label.Visible = false
	end
	if not holder then
		local made = Instance.new("Frame")
		made.Name = "Digits"
		made.BackgroundTransparency = 1
		made.AnchorPoint = Vector2.new(0.5, 0.5)
		made.Position = UDim2.fromScale(0.5, 0.5)
		made.Size = UDim2.fromScale(1, 1)
		made.ZIndex = badge.ZIndex + 1
		made.Parent = badge
		holder = made
	end
	local box = holder :: Frame
	box.Visible = true
	if box:GetAttribute("Shown") == shown then
		return
	end
	box:SetAttribute("Shown", shown)
	for _, old in box:GetChildren() do
		old:Destroy()
	end
	-- Height as a share of the disc, so the row scales with the badge.
	local h = if #shown >= 3 then 0.42 elseif #shown == 2 then 0.5 else 0.56
	local total = 0
	for i = 1, #shown do
		total += DIGIT_ASPECT[string.sub(shown, i, i)]
	end
	local overlap = 0.12 -- the dark edges of neighbouring digits overlap a little
	total -= overlap * (#shown - 1)
	-- Widths are in the disc's height units; the badge is wider than tall for 2+ digits.
	local width = badge.Size.X.Offset / math.max(badge.Size.Y.Offset, 1)
	local x = 0.5 - h * total / width / 2
	for i = 1, #shown do
		local ch = string.sub(shown, i, i)
		local w = h * DIGIT_ASPECT[ch] / width
		local image = Instance.new("ImageLabel")
		image.Name = "D" .. i
		image.BackgroundTransparency = 1
		image.Image = images[if ch == "+" then "Digit_Plus" else "Digit_" .. ch]
		image.AnchorPoint = Vector2.new(0, 0.5)
		image.Position = UDim2.fromScale(x, 0.5)
		image.Size = UDim2.fromScale(w, h)
		image.ZIndex = box.ZIndex + i
		image.Parent = box
		x += w - h * overlap / width
	end
end

-- `ownBeat`: the badge only pulses on its own 10 s beat, never because its count went up
-- (core buttons that add up their menu's badges; Dev, 2026-11-01: a category pulsed every
-- time something inside it did).
function Ui.setBadge(badge: GuiObject?, count: (number | string)?, ownBeat: boolean?)
	if not badge then
		return
	end
	local shown: string? = nil
	if type(count) == "string" then
		shown = count
	elseif type(count) == "number" and count > 0 then
		shown = if count > 99 then "99+" else tostring(math.floor(count))
	end
	if not shown then
		badge.Visible = false
		badgeCounts[badge] = nil
		liftHost(badge, false)
		return
	end
	styleBadge(badge)
	local px = badgeBase[badge]
	local label = badge:FindFirstChild("Label") :: TextLabel?
	if label then
		label.Text = shown
		label.TextSize = math.floor(px * (if #shown >= 3 then 0.5 else 0.62) + 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
	end
	-- Round for one digit, a pill for "12" or "99+".
	local extra = if #shown >= 3 then 0.75 elseif #shown == 2 then 0.3 else 0
	badge.Size = UDim2.fromOffset(math.floor(px * (1 + extra) + 0.5), px)
	badgeDigits(badge, label, shown, px)
	local before = badgeCounts[badge]
	badgeCounts[badge] = shown
	badge.Visible = true
	liftHost(badge, true)
	-- A new or bigger count pulses right away and restarts that badge's 10 s beat.
	if not ownBeat and before ~= shown and (before == nil or (tonumber(shown) or 0) > (tonumber(before) or 0)) and not Ui.reducedMotion() then
		nextPulse[badge] = os.clock() + PULSE_EVERY
		task.defer(pulseTwice, badge)
	end
	startPulse()
end

-- Small pop for dropdowns and panels (a frame with an AutoScale UIScale).
function Ui.popFrame(frame: GuiObject)
	local scale = frame:FindFirstChild("AutoScale") :: UIScale?
	if not scale or Ui.reducedMotion() then
		return
	end
	local target = if isModal(scale) then windowScale else currentScale
	scale.Scale = target * 0.85
	TweenService:Create(scale, OPEN, { Scale = target }):Play()
end

-- Kept for older callers: same as Ui.show on an already enabled screen.
function Ui.popIn(gui: ScreenGui)
	Ui.show(gui)
end

-- The layouts are drawn for a 1456 x 820 screen (gen_ui.py). Every UIScale named
-- "AutoScale" follows the screen:
--   HUD clusters: the smaller of height / 820 and width / 1456, clamped. Short screens
--     (phones in landscape) get 25% more so buttons stay tappable, and Ui.compact() is
--     true so the HUD can move clusters to their phone spots.
--   Modal windows (named "Window", or with the Modal attribute): as big as the HUD scale
--     on PC, but never bigger than what fits under the Roblox top bar. One scale for all
--     of them, so every window is the same size on screen.
local DESIGN_W, DESIGN_H = 1456, 820
local WINDOW_W, WINDOW_H = 820, 520 -- gen_ui.py WIN_W / WIN_H
local COMPACT_BELOW = 560
local PHONE_H, PHONE_W = 540, 1100 -- phone layouts are drawn for this much room

local function rescale()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local view = camera.ViewportSize
	if view.X < 2 or view.Y < 2 then
		return
	end
	local inset = GuiService.TopbarInset.Height
	local compact = view.Y < COMPACT_BELOW
	local s = math.min(view.Y / DESIGN_H, view.X / DESIGN_W)
	if compact then
		-- Phones: sized by height so buttons stay big enough to read and tap (Dev: the
		-- phone HUD was tiny). 390 pt tall -> 0.72.
		s = math.min(view.Y / PHONE_H, view.X / PHONE_W)
	end
	s = math.clamp(s, 0.4, 1.15)
	local fit = math.min((view.Y - inset - 16) / WINDOW_H, (view.X - 32) / WINDOW_W)
	local w = math.max(0.3, math.min(fit, math.max(s, 1)))
	local changed = s ~= currentScale or w ~= windowScale or compact ~= compactLayout
	currentScale, windowScale, compactLayout = s, w, compact
	for _, gui in playerGui:GetChildren() do
		for _, d in gui:GetDescendants() do
			if d:IsA("UIScale") and d.Name == "AutoScale" then
				local extra = if compact
					then (d:GetAttribute("CompactScale") :: number?) or 1
					else (d:GetAttribute("PcScale") :: number?) or 1
				d.Scale = (if isModal(d) then w else s) * extra
			end
		end
	end
	if changed then
		for _, fn in scaleListeners do
			task.spawn(fn, s, compact)
		end
	end
end

-- A full-screen ScreenGui (no safe-area insets) to measure the insets against.
local probe: ScreenGui? = nil
local function fullScreen(): ScreenGui
	if not probe or not probe.Parent then
		local g = Instance.new("ScreenGui")
		g.Name = "SafeAreaProbe"
		g.ScreenInsets = Enum.ScreenInsets.None
		g.IgnoreGuiInset = true
		g.ResetOnSpawn = false
		g.Parent = playerGui
		probe = g
	end
	return probe :: ScreenGui
end

-- Same, but kept inside the device safe area (notch / camera hole), to measure that band.
local deviceProbe: ScreenGui? = nil
local function deviceSafe(): ScreenGui
	if not deviceProbe or not deviceProbe.Parent then
		local g = Instance.new("ScreenGui")
		g.Name = "DeviceSafeProbe"
		g.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
		g.IgnoreGuiInset = true
		g.ResetOnSpawn = false
		g.Parent = playerGui
		deviceProbe = g
	end
	return deviceProbe :: ScreenGui
end

-- How far below a ScreenGui's bottom edge the real screen goes (the safe-area band along
-- the bottom of phones), in px. HUD pieces at the bottom can move down into most of it
-- (Dev, 2026-11-01: the wallet and hotbar floated high on mobile).
function Ui.rightGap(gui: ScreenGui): number
	local full = fullScreen()
	return math.max(0, (full.AbsolutePosition.X + full.AbsoluteSize.X) - (gui.AbsolutePosition.X + gui.AbsoluteSize.X))
end

-- Roblox's touch jump button: how far its left edge and top edge sit from the screen's
-- right and bottom edges (px). Small screens use a 70 px button, bigger ones 120 px.
function Ui.jumpButtonArea(): (number, number)
	-- The real button when Roblox's touch controls exist (its size and spot vary a lot by
	-- device), measured against the full screen.
	local touch = playerGui:FindFirstChild("TouchGui")
	local jump = touch and touch:FindFirstChild("JumpButton", true) :: GuiObject?
	if jump and jump.AbsoluteSize.X > 0 then
		local full = fullScreen()
		local right = full.AbsolutePosition.X + full.AbsoluteSize.X
		local bottom = full.AbsolutePosition.Y + full.AbsoluteSize.Y
		return right - jump.AbsolutePosition.X, bottom - jump.AbsolutePosition.Y
	end
	local camera = workspace.CurrentCamera
	local view = if camera then camera.ViewportSize else Vector2.new(1000, 600)
	if math.min(view.X, view.Y) <= 500 then
		return 95, 90
	end
	return 170, 210
end

function Ui.bottomGap(gui: ScreenGui): number
	local full = fullScreen()
	local fullBottom = full.AbsolutePosition.Y + full.AbsoluteSize.Y
	local bottom = gui.AbsolutePosition.Y + gui.AbsoluteSize.Y
	return math.max(0, fullBottom - bottom)
end

-- How far from the left / right screen edge HUD pieces sit, as offsets inside a ScreenGui
-- that keeps out of the Roblox UI safe-area insets (negative = out into the inset). Dev
-- wanted the HUD hugging the edges (2026-10-30), so pieces move out into that inset and a
-- little into the device safe band, stopping short of where a notch / camera hole sits.
-- Each side is measured on its own (the camera hole is often on one side only).
function Ui.edges(gui: ScreenGui): (number, number)
	local full = fullScreen()
	local device = deviceSafe()
	-- We place pieces into the device safe band ourselves (see pull), so don't let Roblox
	-- clip them there.
	gui.ClipToDeviceSafeArea = false
	if gui.AbsoluteSize.X < 2 or full.AbsoluteSize.X < 2 or device.AbsoluteSize.X < 2 then
		return 14, 14
	end
	local fullL = full.AbsolutePosition.X
	local fullR = full.AbsolutePosition.X + full.AbsoluteSize.X
	local insetL = math.max(0, gui.AbsolutePosition.X - fullL)
	local insetR = math.max(0, fullR - (gui.AbsolutePosition.X + gui.AbsoluteSize.X))
	local deviceL = math.max(0, device.AbsolutePosition.X - fullL)
	local deviceR = math.max(0, fullR - (device.AbsolutePosition.X + device.AbsoluteSize.X))
	local function pull(inset: number, safe: number): number
		if inset < 1 then
			return 14
		end
		-- Distance from the real screen edge: 12 px into the device safe area. Phones
		-- report the same safe band on both sides, but the notch / camera hole only needs
		-- about 3/4 of it (iPhone notch ~30 of 47, Dynamic Island ~48 of 59), so this
		-- still clears it while sitting close to the edge. Measured on each phone.
		local fromEdge = math.max(math.clamp(inset - 30, 10, 24), safe - 12)
		return math.floor(math.min(fromEdge, inset + 14) - inset)
	end
	return pull(insetL, deviceL), pull(insetR, deviceR)
end

-- Buttons carry a tinted "Studs" texture (gen_ui.py). Controllers recolour buttons
-- (green when you can afford it, grey when not), so the studs follow the button colour.
local tinted: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function followTint(d: Instance)
	if d.Name ~= "Studs" or not d:IsA("ImageLabel") or tinted[d] then
		return
	end
	local host = d.Parent
	if not (host and host:IsA("GuiObject")) then
		return
	end
	tinted[d] = true
	local studs = d :: ImageLabel
	local hostObject = host :: GuiObject
	studs.ImageColor3 = hostObject.BackgroundColor3
	hostObject:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		studs.ImageColor3 = hostObject.BackgroundColor3
	end)
end

function Ui.initScaling()
	for _, d in playerGui:GetDescendants() do
		followTint(d)
	end
	playerGui.DescendantAdded:Connect(followTint)
	rescale()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(rescale)
	playerGui.ChildAdded:Connect(function()
		task.defer(rescale)
	end)
	-- Safe-area sizes (Ui.edges) settle a moment after the viewport changes: lay out again.
	local function relayout()
		task.wait(0.2)
		for _, fn in scaleListeners do
			task.spawn(fn, currentScale, compactLayout)
		end
	end
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.spawn(relayout)
		end)
	end
	-- And whenever the measured safe areas change (rotation, notch side, Roblox top bar).
	for _, probeGui in { fullScreen(), deviceSafe() } do
		probeGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			task.spawn(relayout)
		end)
		probeGui:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
			task.spawn(relayout)
		end)
	end
	task.spawn(relayout)
	task.delay(2, relayout)
end

function Ui.fitText(label: TextLabel, maxSize: number, minSize: number?)
	-- Roblox's own fit (TextScaled, capped by a size constraint). Setting TextSize by hand
	-- from a measured width drew small text under the HUD's UIScale with broken letter
	-- spacing on phones ("Leaf Vac uum", "No c ar", Dev 2026-11-01).
	label.TextWrapped = false
	label.TextScaled = true
	local limit = label:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.MinTextSize = minSize or 6
	limit.Parent = label
end

return Ui
