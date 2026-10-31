--!strict
-- Loading screen. Shown first thing (Init runs before every other controller) and held
-- until the game is ready: the place has loaded, the terrain and map are built, the
-- 3D models are in ReplicatedStorage.Assets, every UI image is downloaded, and our
-- player data and character have arrived. Gives up after TIMEOUT so nobody is stuck.
-- Dev (2026-10-31): it closed at about 50% and assets were often not loaded yet. Now every
-- step waits for the real thing (caps only so nobody is stuck forever): models, props, every
-- UI image and the models' meshes/textures download before it closes, then the content
-- queue drains. The bar never goes backwards. Skip shows after SKIP_AFTER seconds.
-- Look (remade 2026-10-31, Dev: "make it better"): sky gradient with scrolling studs, autumn
-- leaves drifting down, the logo bobbing, a light sweep over the bar and a broom riding the
-- end of the fill. Root is a TextButton so clicks never reach the HUD behind it.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Config.Assets)

local TIMEOUT = 60
local TERRAIN_MAX = 15
local MODELS_MAX = 25
local PROPS_MAX = 15
local QUEUE_MAX = 6
local SKIP_AFTER = 3
local TIPS = {
	"Bigger tools sweep wider and hold more leaves.",
	"Dump your trash into the green bins by the market to get cash.",
	"Carry eggs to the pet park on your base.",
	"Pets on your base earn cash even while you sweep.",
	"Buy a car in Gear and drive it from hotbar slot 2.",
	"Open Upgrades for Running Shoes, Egg Luck and more.",
	"Rebirth to earn a permanent cash multiplier.",
}

local LEAF_COLORS = {
	Color3.fromRGB(255, 140, 40),
	Color3.fromRGB(235, 80, 50),
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(190, 110, 40),
	Color3.fromRGB(140, 200, 70),
}

local LoadingController = {}

local player = Players.LocalPlayer
local gui: ScreenGui?
local done = false
local shown = 0

local function find(path: string): any
	local current: Instance? = gui
	for part in string.gmatch(path, "[^%.]+") do
		current = current and current:FindFirstChild(part)
	end
	return current
end

local function setProgress(fraction: number, status: string)
	local fill = find("Root.Center.Bar.Track.Fill") :: Frame?
	local rider = find("Root.Center.Bar.Rider") :: ImageLabel?
	local percent = find("Root.Center.Bar.Percent") :: TextLabel?
	local label = find("Root.Center.Status") :: TextLabel?
	-- Never moves backwards.
	fraction = math.max(shown, math.clamp(fraction, 0.02, 1))
	shown = fraction
	if fill then
		TweenService:Create(fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
			Size = UDim2.fromScale(fraction, 1),
		}):Play()
	end
	if rider then
		TweenService:Create(rider, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
			Position = UDim2.new(fraction, 0, 0.5, -8),
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

local function fadeOut()
	local root = find("Root") :: GuiObject?
	if not gui or not root then
		return
	end
	local info = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	-- Clicks go through again as soon as it starts to fade.
	if root:IsA("GuiButton") then
		root.Active = false
	end
	local scale = find("Root.Center.AutoScale") :: UIScale?
	if scale then
		TweenService:Create(scale, info, { Scale = scale.Scale * 1.15 }):Play()
	end
	TweenService:Create(root, info, { BackgroundTransparency = 1 }):Play()
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") then
			TweenService:Create(d, info, { TextTransparency = 1 }):Play()
		elseif d:IsA("GuiButton") then
			TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
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

local function stepWait(check: () -> boolean, cap: number, deadline: number)
	waitFor(check, math.min(deadline, os.clock() + cap))
end

-- Downloads a list of content (ids or instances) in small batches, moving the bar from
-- `from` to `to` as each batch finishes.
local function preloadList(list: { any }, from: number, to: number, label: string, deadline: number)
	local total = #list
	if total == 0 then
		setProgress(to, label)
		return
	end
	local batch = 6
	for i = 1, total, batch do
		if os.clock() >= deadline or done then
			return
		end
		local slice = table.move(list, i, math.min(i + batch - 1, total), 1, {})
		pcall(function()
			ContentProvider:PreloadAsync(slice)
		end)
		local loaded = math.min(i + batch - 1, total)
		setProgress(from + (to - from) * loaded / total, `{label} ({loaded}/{total})`)
	end
end

local function imageIds(): { string }
	local ids = {}
	for _, id in Assets.Images do
		if type(id) == "string" and id ~= "" then
			table.insert(ids, id)
		end
	end
	return ids
end

-- Every step waits for the real thing (with a cap so nobody is stuck) and the bar only
-- moves when that step's work is actually done. Images and model meshes are downloaded
-- before the screen closes, so nothing pops in afterwards.
local function run()
	local deadline = os.clock() + TIMEOUT

	setProgress(0.02, "Connecting to the world...")
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	setProgress(0.05, "Raking up the leaves...")
	stepWait(function()
		return Workspace:GetAttribute("TerrainReady") == true
	end, TERRAIN_MAX, deadline)

	setProgress(0.12, "Loading 3D models...")
	local f = assetsFolder() or ReplicatedStorage:WaitForChild("Assets", math.max(1, deadline - os.clock()))
	local wanted = modelCount()
	local modelsBy = math.min(deadline, os.clock() + MODELS_MAX)
	while os.clock() < modelsBy do
		f = f or assetsFolder()
		if f and f:GetAttribute("Ready") == true then
			break
		end
		local have = if f then #f:GetChildren() else 0
		if wanted > 0 then
			setProgress(0.12 + 0.26 * math.min(have / wanted, 1), `Loading 3D models ({have}/{wanted})`)
		end
		task.wait(0.2)
	end

	setProgress(0.38, "Placing rocks, bases and gates...")
	stepWait(function()
		return Workspace:GetAttribute("PropsReady") == true
	end, PROPS_MAX, deadline)

	preloadList(imageIds(), 0.45, 0.72, "Loading pictures", deadline)

	local models = if f then f:GetChildren() else {}
	preloadList(models, 0.72, 0.86, "Loading textures", deadline)

	setProgress(0.88, "Loading your save...")
	-- If the save is still held by the player's last server, the server says how long until
	-- it takes it over: show that instead of a frozen bar, and wait it out.
	local lastWait, lastAt = nil, 0
	while State.data == nil do
		local wait = player:GetAttribute("SaveLockWait")
		if type(wait) == "number" then
			if wait ~= lastWait then
				lastWait, lastAt = wait, os.clock()
			end
			-- The server updates it every 5 s; count down smoothly in between.
			local left = math.max(1, math.ceil(wait - (os.clock() - lastAt)))
			setProgress(0.88, `Finishing your last session... {left}s`)
			deadline = math.max(deadline, os.clock() + wait + 15)
		elseif os.clock() >= deadline then
			break
		end
		task.wait(0.2)
	end

	setProgress(0.93, "Getting your broom ready...")
	stepWait(function()
		local character = player.Character
		return character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil
	end, 15, deadline)

	-- Whatever is still downloading (map textures, sounds) gets a few more seconds.
	setProgress(0.96, "Almost there...")
	stepWait(function()
		return ContentProvider.RequestQueueSize == 0
	end, QUEUE_MAX, deadline + QUEUE_MAX)

	if done then
		return -- skipped
	end
	setProgress(1, "Ready!")
	task.wait(0.3)
	done = true
	fadeOut()
end

-- Skip: shows after SKIP_AFTER seconds and drops you into the game right away.
local function offerSkip()
	task.wait(SKIP_AFTER)
	local skip = find("Root.SkipHolder.Skip") :: GuiButton?
	if done or not skip then
		return
	end
	skip.Visible = true
	skip.Activated:Once(function()
		if not done then
			done = true
			fadeOut()
		end
	end)
end

local function cycleTips()
	local tip = find("Root.Center.TipCard.Tip") :: TextLabel?
	local i = math.random(#TIPS)
	while not done and tip and tip.Parent do
		tip.Text = TIPS[i]
		i = i % #TIPS + 1
		task.wait(3.5)
	end
end

-- Leaves drifting down across the screen, swaying and spinning.
local function spawnLeaves()
	local layer = find("Root.Leaves") :: Frame?
	if not layer then
		return
	end
	local leaves = {}
	for _ = 1, 18 do
		local size = math.random(34, 70)
		local leaf = Instance.new("ImageLabel")
		leaf.BackgroundTransparency = 1
		leaf.AnchorPoint = Vector2.new(0.5, 0.5)
		leaf.Size = UDim2.fromOffset(size, size)
		leaf.Image = Assets.Images.LoadingLeaf or ""
		leaf.ImageColor3 = LEAF_COLORS[math.random(#LEAF_COLORS)]
		leaf.ImageTransparency = 0.1
		leaf.ZIndex = 2
		leaf.Parent = layer
		table.insert(leaves, {
			image = leaf,
			x = math.random(),
			y = math.random() * 1.2 - 0.2,
			fall = 0.035 + math.random() * 0.05,
			sway = math.random() * 6,
			spin = math.random(-60, 60),
			rot = math.random(0, 360),
		})
	end
	return leaves
end

local function animate()
	local leaves = spawnLeaves() or {}
	local studs = find("Root.Studs") :: ImageLabel?
	local logo = find("Root.Center.Logo") :: ImageLabel?
	local shine = find("Root.Center.Bar.Track.Fill.Sweep.Shine") :: UIGradient?
	local rider = find("Root.Center.Bar.Rider") :: ImageLabel?
	local still = Ui.reducedMotion()
	if logo then
		-- Pop in.
		local size = logo.Size
		logo.Size = UDim2.fromOffset(size.X.Offset * 0.6, size.Y.Offset * 0.6)
		TweenService:Create(logo, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = size }):Play()
	end
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not gui or not gui.Parent then
			connection:Disconnect()
			return
		end
		local t = os.clock() - start
		if shine then
			shine.Offset = Vector2.new(((t * 0.7) % 2) - 1, 0)
		end
		if still then
			return
		end
		if studs then
			local o = (t * 24) % 96
			studs.Position = UDim2.fromOffset(-o, -o)
		end
		if logo then
			logo.Position = UDim2.new(0.5, 0, 0, math.sin(t * 2) * 8)
			logo.Rotation = math.sin(t * 1.3) * 1.5
		end
		if rider then
			rider.Rotation = -20 + math.sin(t * 10) * 15
		end
		for _, leaf in leaves do
			leaf.y += leaf.fall * dt * 2
			if leaf.y > 1.1 then
				leaf.y = -0.1
				leaf.x = math.random()
			end
			leaf.rot += leaf.spin * dt
			local sway = math.sin(t * 1.5 + leaf.sway) * 0.03
			leaf.image.Position = UDim2.fromScale(leaf.x + sway, leaf.y)
			leaf.image.Rotation = leaf.rot + math.sin(t * 2 + leaf.sway) * 25
		end
	end)
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
	-- LiveSync keeps removed children: drop an old Frame "Root" from before the remake.
	for _, child in screen:GetChildren() do
		if child.Name == "Root" and not child:IsA("TextButton") then
			child:Destroy()
		end
	end
	screen.Name = "LoadingScreen"
	screen.ResetOnSpawn = false
	screen.Enabled = true
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
end

function LoadingController:Start()
	-- Onboarding funnel: "Loading screen done" (skipped or finished).
	task.spawn(function()
		while not done do
			task.wait(0.25)
		end
		Ui.report("Loaded")
	end)
	if done then
		return
	end
	task.spawn(cycleTips)
	task.spawn(animate)
	task.spawn(offerSkip)
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
