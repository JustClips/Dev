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
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Sounds"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

-- Modal screens: only one is open at a time.
local MODALS = { "Shop", "Index", "Rebirth", "Garage", "Upgrades", "Inventory", "Daily", "Playtime", "Events", "Settings", "PetsPanel", "EggsPanel", "Dialog", "GroupReward", "BasePicker", "Codes" }
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
	end
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

-- Count badges (red square, white outline, big white number). Ui.setBadge shows the count
-- (nil/0 hides it, a string such as "!" shows as is), widens the badge for 2-3 digits and
-- pops it when the count goes up. Every 10 seconds visible badges give a little wiggle
-- so they catch the eye.
local badgeCounts: { [GuiObject]: string } = setmetatable({}, { __mode = "k" }) :: any
local wiggleStarted = false

local function badgePop(badge: GuiObject)
	if Ui.reducedMotion() then
		return
	end
	local pop = badge:FindFirstChild("Pop") :: UIScale?
	if not pop then
		local s = Instance.new("UIScale")
		s.Name = "Pop"
		s.Parent = badge
		pop = s
	end
	local scale = pop :: UIScale
	scale.Scale = 1.6
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function startWiggle()
	if wiggleStarted then
		return
	end
	wiggleStarted = true
	task.spawn(function()
		while true do
			task.wait(10) -- Dev: a wiggle every few seconds was annoying
			if not Ui.reducedMotion() then
				for badge in badgeCounts do
					if badge.Parent and badge.Visible then
						badge.Rotation = -14
						TweenService:Create(badge, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
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
	host.ZIndex = if lifted then (baseZ :: number) + 1 else baseZ :: number
end

function Ui.setBadge(badge: GuiObject?, count: (number | string)?)
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
	local label = badge:FindFirstChild("Label") :: TextLabel?
	if label then
		label.Text = shown
	end
	local px = badge.Size.Y.Offset
	badge.Size = UDim2.fromOffset(px + math.max(0, #shown - 1) * math.floor(px * 0.4), px)
	local before = badgeCounts[badge]
	badgeCounts[badge] = shown
	badge.Visible = true
	liftHost(badge, true)
	if before ~= shown and (before == nil or (tonumber(shown) or 0) > (tonumber(before) or 0)) then
		badgePop(badge)
	end
	startWiggle()
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
				local extra = if compact then (d:GetAttribute("CompactScale") :: number?) or 1 else 1
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

-- One-line labels that shrink to fit their width. TextScaled with TextWrapped off let
-- long names ("Starlit Autumn Stag", "+1x Lucky Payout") run out of their tiles (Dev,
-- 2026-10-30), so this measures the text and sets TextSize itself. Call it once per
-- label; it refits whenever the text or the label's size changes.
local fitting: { [TextLabel]: { max: number, min: number } } = setmetatable({}, { __mode = "k" }) :: any
local widthAt100: { [string]: number } = {}

local function chainScale(obj: Instance): number
	local k = 1
	local node: Instance? = obj
	while node and not node:IsA("LayerCollector") do
		local scale = node:FindFirstChildOfClass("UIScale")
		if scale then
			k *= scale.Scale
		end
		node = node.Parent
	end
	return k
end

local function refit(label: TextLabel)
	local spec = fitting[label]
	if not spec then
		return
	end
	local text = label.Text
	if text == "" or label.AbsoluteSize.X < 1 then
		return
	end
	local font = label.FontFace
	local cacheKey = `{font.Family}|{font.Weight.Name}|{text}`
	local w = widthAt100[cacheKey]
	if not w then
		local params = Instance.new("GetTextBoundsParams")
		params.Text = text
		params.Font = font
		params.Size = 100
		params.Width = 1e6
		local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
		if not ok or label.Text ~= text then
			return
		end
		w = math.max((bounds :: Vector2).X, 1)
		widthAt100[cacheKey] = w
	end
	local stroke = label:FindFirstChildOfClass("UIStroke")
	local room = label.AbsoluteSize.X / math.max(chainScale(label), 0.01) - 2 - (if stroke then stroke.Thickness * 2 else 0)
	label.TextSize = math.clamp(math.floor(100 * room / (w :: number)), spec.min, spec.max)
end

function Ui.fitText(label: TextLabel, maxSize: number, minSize: number?)
	label.TextScaled = false
	label.TextWrapped = false
	label.TextSize = maxSize
	local first = fitting[label] == nil
	fitting[label] = { max = maxSize, min = minSize or 6 }
	if first then
		local function again()
			task.spawn(refit, label)
		end
		label:GetPropertyChangedSignal("Text"):Connect(again)
		label:GetPropertyChangedSignal("AbsoluteSize"):Connect(again)
	end
	task.spawn(refit, label)
end

return Ui
