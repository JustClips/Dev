--!strict
-- Background music and the Settings window. Music shuffles through Config/Sounds.Music in
-- the "Music" sound group; every sound effect plays in "SFX" (Ui.sound). The gear button
-- sits in Roblox's top bar right after its own buttons and opens Settings, where two
-- sliders set the volume of each group. The values are saved with the profile.
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Sounds = require(Shared.Config.Sounds)

local AudioController = {}

local musicGroup: SoundGroup
local sfxGroup: SoundGroup
local gui: ScreenGui
local trackLabel: TextLabel
local volumes = { Music = Sounds.DefaultMusic, Sfx = Sounds.DefaultSfx }
local beforeMute = { Music = Sounds.DefaultMusic, Sfx = Sounds.DefaultSfx }
local loaded = false
local rows: { [string]: Frame } = {}
local dragging: string? = nil
local currentName = ""
local duck = 1 -- playlist volume share (WeatherController turns it down for the disco)
local currentSound: Sound? = nil

local function applyVolumes()
	musicGroup.Volume = volumes.Music
	sfxGroup.Volume = volumes.Sfx
	for key, row in rows do
		local value = volumes[key]
		local track = row:FindFirstChild("Track") :: Frame
		;(track:FindFirstChild("Fill") :: Frame).Size = UDim2.fromScale(value, 1)
		;(track:FindFirstChild("Knob") :: Frame).Position = UDim2.fromScale(value, 0.5)
		;(row:FindFirstChild("Value") :: TextLabel).Text = `{math.floor(value * 100 + 0.5)}%`
		local mute = row:FindFirstChild("Mute") :: GuiButton
		mute.BackgroundColor3 = if value <= 0 then Color3.fromRGB(166, 174, 194) else Color3.fromRGB(59, 79, 168)
	end
	if trackLabel then
		trackLabel.Text = if currentName ~= "" and volumes.Music > 0 then `Now playing: {currentName} (APM Music)` else ""
	end
end

local saveQueued: { [string]: boolean } = {}
local function save(key: string)
	if saveQueued[key] then
		return
	end
	saveQueued[key] = true
	task.delay(0.6, function()
		saveQueued[key] = nil
		Net.event("SetSetting"):FireServer(key, volumes[key])
	end)
end

local function setVolume(key: string, value: number)
	volumes[key] = math.clamp(value, 0, 1)
	if volumes[key] > 0 then
		beforeMute[key] = volumes[key]
	end
	applyVolumes()
	save(key)
end

-- Shuffled playlist that never repeats a track twice in a row.
local function playMusic()
	local order: { number } = {}
	local last = 0
	while true do
		if #order == 0 then
			for i = 1, #Sounds.Music do
				table.insert(order, i)
			end
			for i = #order, 2, -1 do
				local j = math.random(1, i)
				order[i], order[j] = order[j], order[i]
			end
			if order[1] == last and #order > 1 then
				order[1], order[#order] = order[#order], order[1]
			end
		end
		local index = table.remove(order, 1) :: number
		last = index
		local def = Sounds.Music[index]
		local sound = Instance.new("Sound")
		sound.Name = "Music"
		sound.SoundId = def.Id
		sound.Volume = 0
		sound.SoundGroup = musicGroup
		sound.Parent = SoundService
		currentName = def.Name
		applyVolumes()
		if not sound.IsLoaded then
			local ok = false
			local conn = sound.Loaded:Once(function()
				ok = true
			end)
			local deadline = os.clock() + 10
			while not ok and os.clock() < deadline do
				task.wait(0.2)
			end
			conn:Disconnect()
			if not sound.IsLoaded then
				-- Couldn't load (removed or blocked): skip it.
				sound:Destroy()
				task.wait(1)
				continue
			end
		end
		sound:Play()
		currentSound = sound
		TweenService:Create(sound, TweenInfo.new(2), { Volume = Sounds.MusicVolume * duck }):Play()
		local length = sound.TimeLength
		local fadeAt = math.max(1, length - 2.5)
		while sound.Parent and sound.IsPlaying and sound.TimePosition < fadeAt do
			task.wait(0.5)
		end
		TweenService:Create(sound, TweenInfo.new(2), { Volume = 0 }):Play()
		task.wait(2)
		sound:Destroy()
		task.wait(1.5)
	end
end

-- Turns the playlist down (0-1 share of its normal volume), e.g. while the disco plays.
function AudioController:SetMusicDuck(share: number)
	duck = math.clamp(share, 0, 1)
	local sound = currentSound
	if sound and sound.Parent then
		TweenService:Create(sound, TweenInfo.new(1.5), { Volume = Sounds.MusicVolume * duck }):Play()
	end
end

-- Keeps the gear right after Roblox's own top bar buttons, the same size as them.
local function placeGear(gear: GuiObject)
	local inset = GuiService.TopbarInset
	local height = inset.Height
	if height <= 0 then
		height = 58
	end
	local size = math.floor(math.clamp(height - 14, 32, 48))
	gear.Size = UDim2.fromOffset(size, size)
	-- Roblox's own buttons sit low in the top bar (12 px down in the 58 px bar, 2 px above
	-- its bottom), not centred, so the gear does the same to line up with them (Dev,
	-- 2026-11-01: it sat ~5 px higher on phones and PC).
	gear.Position = UDim2.fromOffset(math.max(inset.Min.X, 104) + 4, inset.Min.Y + math.max(height - size - 2, 0))
end

local function bindSlider(key: string, row: Frame)
	rows[key] = row
	local track = row:FindFirstChild("Track") :: Frame
	local hit = track:FindFirstChild("Hit") :: TextButton
	local function setFrom(x: number)
		local width = math.max(track.AbsoluteSize.X, 1)
		setVolume(key, (x - track.AbsolutePosition.X) / width)
	end
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = key
			setFrom(input.Position.X)
		end
	end)
	-- Controller: with the bar selected, d-pad left / right turns it down / up.
	hit.NextSelectionLeft = hit
	hit.NextSelectionRight = hit
	UserInputService.InputBegan:Connect(function(input)
		if GuiService.SelectedObject ~= hit then
			return
		end
		if input.KeyCode == Enum.KeyCode.DPadLeft then
			setVolume(key, volumes[key] - 0.1)
		elseif input.KeyCode == Enum.KeyCode.DPadRight then
			setVolume(key, volumes[key] + 0.1)
		end
	end)
	Ui.button(row:FindFirstChild("Mute") :: GuiButton, function()
		if volumes[key] > 0 then
			setVolume(key, 0)
		else
			setVolume(key, if beforeMute[key] > 0 then beforeMute[key] else 0.6)
		end
	end)
end

local C: any

-- Roblox's own feedback form. Roblox decides who can send (not the game's owner, once a
-- day per player, age limits) and shows its own "unavailable" message otherwise. It only
-- works in the published game, not in Studio.
local function leaveFeedback()
	Ui.close("Settings")
	if RunService:IsStudio() then
		C.HudController:Toast("Feedback only works in the published game, not in Studio.", "Bad")
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			(SocialService :: any):PromptFeedbackSubmissionAsync({ FeedbackType = (Enum :: any).FeedbackType.Feedback })
		end)
		if not ok then
			warn("[Feedback] " .. tostring(err))
			C.HudController:Toast("Feedback isn't available right now. Try again later!", "Bad")
		end
	end)
end

function AudioController:Init(controllers)
	C = controllers
	musicGroup = Ui.soundGroup("Music")
	sfxGroup = Ui.soundGroup("SFX")
	gui = Ui.screen("Settings")
	trackLabel = Ui.find(gui, "Window.Track")
	bindSlider("Music", Ui.find(gui, "Window.Music"))
	bindSlider("Sfx", Ui.find(gui, "Window.Sfx"))
	applyVolumes()
end

function AudioController:Start()
	local gear = Ui.find(Ui.screen("Topbar"), "Gear") :: ImageButton
	placeGear(gear)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function()
		placeGear(gear)
	end)
	gear.MouseEnter:Connect(function()
		gear.BackgroundTransparency = 0.15
	end)
	gear.MouseLeave:Connect(function()
		gear.BackgroundTransparency = 0.3
	end)
	Ui.button(gear, function()
		Ui.toggle("Settings")
	end)
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Settings")
	end)
	Ui.button(Ui.find(gui, "Window.Feedback"), leaveFeedback)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Settings")
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local row = rows[dragging]
			local track = row:FindFirstChild("Track") :: Frame
			setVolume(dragging, (input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = nil
		end
	end)
	-- Saved volumes arrive with the first state snapshot.
	local function load(data)
		if loaded or not data or not data.Settings then
			return
		end
		loaded = true
		volumes.Music = data.Settings.Music or Sounds.DefaultMusic
		volumes.Sfx = data.Settings.Sfx or Sounds.DefaultSfx
		beforeMute.Music = if volumes.Music > 0 then volumes.Music else Sounds.DefaultMusic
		beforeMute.Sfx = if volumes.Sfx > 0 then volumes.Sfx else Sounds.DefaultSfx
		applyVolumes()
	end
	State.Changed:Connect(load)
	load(State.data)
	task.spawn(playMusic)
end

return AudioController
