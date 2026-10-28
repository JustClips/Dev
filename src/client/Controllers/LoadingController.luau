--!strict
-- Loading screen. Shown first thing (Init runs before every other controller) and held
-- until the game is ready: the place has loaded, the terrain and map are built, the
-- 3D models are in ReplicatedStorage.Assets, every UI image is downloaded, and our
-- player data and character have arrived. Gives up after TIMEOUT so nobody is stuck.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local State = require(Client.State)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Config.Assets)

local TIMEOUT = 45
local TIPS = {
	"Tip: bigger tools sweep wider and hold more dust.",
	"Tip: sell your dust at the rocket in the middle of the map.",
	"Tip: carry alien eggs to the hatchery on your base.",
	"Tip: aliens on your base earn cash even while you sweep.",
	"Tip: buy a car at the Garage and drive it from hotbar slot 2.",
	"Tip: the Upgrade Station sells Moon Boots, Egg Luck and more.",
	"Tip: rebirth to earn a permanent cash multiplier.",
}

local LoadingController = {}

local player = Players.LocalPlayer
local gui: ScreenGui?
local done = false

local function find(path: string): any
	local current: Instance? = gui
	for part in string.gmatch(path, "[^%.]+") do
		current = current and current:FindFirstChild(part)
	end
	return current
end

local function setProgress(fraction: number, status: string)
	local fill = find("Root.Center.Bar.Track.Fill") :: Frame?
	local percent = find("Root.Center.Bar.Percent") :: TextLabel?
	local label = find("Root.Center.Status") :: TextLabel?
	fraction = math.clamp(fraction, 0.02, 1)
	if fill then
		TweenService:Create(fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
			Size = UDim2.fromScale(fraction, 1),
		}):Play()
	end
	if percent then
		percent.Text = `{math.floor(fraction * 100)}%`
	end
	if label then
		label.Text = status
	end
end

local function waitFor(check: () -> boolean, deadline: number)
	while not check() and os.clock() < deadline do
		task.wait(0.1)
	end
end

local function assetsFolder(): Instance?
	return ReplicatedStorage:FindFirstChild("Assets")
end

local function modelCount(): number
	local count = 0
	for _ in Assets.Models or {} do
		count += 1
	end
	return count
end

local function preloadImages(deadline: number, from: number, to: number)
	local ids = {}
	for _, id in Assets.Images do
		if type(id) == "string" and id ~= "" then
			table.insert(ids, id)
		end
	end
	local total = math.max(#ids, 1)
	local loaded = 0
	-- Preload in small batches so the bar moves and the timeout still applies.
	local batch = 8
	for i = 1, #ids, batch do
		if os.clock() >= deadline then
			return
		end
		local slice = table.move(ids, i, math.min(i + batch - 1, #ids), 1, {})
		pcall(function()
			ContentProvider:PreloadAsync(slice)
		end)
		loaded += #slice
		setProgress(from + (to - from) * loaded / total, `Loading images ({loaded}/{total})`)
	end
end

local function fadeOut()
	local root = find("Root") :: Frame?
	if not gui or not root then
		return
	end
	local info = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(root, info, { BackgroundTransparency = 1 }):Play()
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") then
			TweenService:Create(d, info, { TextTransparency = 1 }):Play()
		elseif d:IsA("ImageLabel") then
			TweenService:Create(d, info, { ImageTransparency = 1 }):Play()
		elseif d:IsA("Frame") then
			TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		end
	end
	task.wait(0.55)
	gui:Destroy()
	gui = nil
end

local function run()
	local deadline = os.clock() + TIMEOUT

	setProgress(0.03, "Connecting to the Moon...")
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	setProgress(0.1, "Building the Moon surface...")
	waitFor(function()
		return Workspace:GetAttribute("TerrainReady") == true
	end, deadline)

	setProgress(0.2, "Loading 3D models...")
	local wanted = modelCount()
	while os.clock() < deadline do
		local f = assetsFolder()
		if f and f:GetAttribute("Ready") == true then
			break
		end
		local have = if f then #f:GetChildren() else 0
		if wanted > 0 then
			setProgress(0.2 + 0.3 * math.min(have / wanted, 1), `Loading 3D models ({have}/{wanted})`)
		end
		task.wait(0.2)
	end

	setProgress(0.5, "Placing rocks, bases and gates...")
	waitFor(function()
		return Workspace:GetAttribute("PropsReady") == true
	end, deadline)

	preloadImages(deadline, 0.55, 0.85)

	setProgress(0.88, "Loading your save...")
	waitFor(function()
		return State.data ~= nil
	end, deadline)

	setProgress(0.95, "Landing your astronaut...")
	waitFor(function()
		local character = player.Character
		return character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil
	end, deadline)

	setProgress(1, "Ready!")
	task.wait(0.35)
	done = true
	fadeOut()
end

local function cycleTips()
	local tip = find("Root.Center.Tip") :: TextLabel?
	local i = math.random(#TIPS)
	while not done and tip and tip.Parent do
		tip.Text = TIPS[i]
		i = i % #TIPS + 1
		task.wait(3.5)
	end
end

function LoadingController:IsDone(): boolean
	return done
end

function LoadingController:Init()
	local template = StarterGui:WaitForChild("Loading", 5)
	if not template then
		done = true
		return
	end
	local screen = template:Clone() :: ScreenGui
	screen.Name = "LoadingScreen"
	screen.ResetOnSpawn = false
	screen.Enabled = true
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
end

function LoadingController:Start()
	if done then
		return
	end
	task.spawn(cycleTips)
	local ok, err = pcall(run)
	if not ok then
		warn("loading screen:", err)
		done = true
		if gui then
			gui:Destroy()
			gui = nil
		end
	end
end

return LoadingController
