--!strict
-- Draws the dust bunnies that hop around the leaf fields. The server moves one invisible
-- anchor part per bunny at 10 Hz (DustBunnyService); here each anchor gets the voxel
-- bunny model (Mob_DustBunny), which follows it smoothly and plays idle / hop / run
-- animations to match how fast it is moving.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Zones = require(Shared.Config.Zones)

local MODEL = "Mob_DustBunny"
local FOLLOW = 10 -- how fast the model catches up with its anchor (per second)
local DRAW_DISTANCE = 180

type Visual = {
	anchor: BasePart,
	model: Model,
	real: boolean, -- the voxel model (false: the ball placeholder until it loads)
	cframe: CFrame,
	tracks: { [string]: AnimationTrack },
	playing: string?,
	speed: number,
}

local DustBunnyController = {}

local visuals: { [BasePart]: Visual } = {}
local holder: Folder

local function placeholder(zoneId: string?): Model
	local model = Instance.new("Model")
	local zone = zoneId and Zones.ById[zoneId]
	local fur = if zone then (zone.DustColor :: Color3):Lerp(Color3.new(1, 1, 1), 0.55) else Color3.fromRGB(240, 230, 214)
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(2.6, 2.6, 2.6)
	body.Color = fur
	body.Material = Enum.Material.Sand
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CFrame = CFrame.new(0, 1.3, 0)
	body.Parent = model
	for _, x in { -0.5, 0.5 } do
		local ear = body:Clone()
		ear.Name = "Ear"
		ear.Shape = Enum.PartType.Block
		ear.Size = Vector3.new(0.45, 1.5, 0.3)
		ear.CFrame = CFrame.new(x, 2.9, 0.1)
		ear.Parent = model
	end
	local root = Instance.new("Part")
	root.Name = "RootPart"
	root.Transparency = 1
	root.Size = Vector3.new(1, 1, 1)
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root
	return model
end

local function makeModel(visual: Visual)
	if visual.model then
		visual.model:Destroy()
	end
	table.clear(visual.tracks)
	visual.playing = nil
	local model = AssetLibrary.get(MODEL)
	visual.real = model ~= nil
	if not model then
		model = placeholder(visual.anchor:GetAttribute("Zone") :: string?)
	end
	model.Name = "DustBunny"
	model:PivotTo(visual.cframe)
	model.Parent = holder
	visual.model = model
	if visual.real then
		for _, key in { "Idle", "Walk", "Run" } do
			local track = AssetLibrary.loadTrack(model, `{MODEL}_{key}`)
			if track then
				track.Looped = true
				visual.tracks[key] = track
			end
		end
	end
end

local function play(visual: Visual, key: string)
	if visual.playing == key then
		return
	end
	local old = visual.playing and visual.tracks[visual.playing]
	if old then
		old:Stop(0.15)
	end
	local track = visual.tracks[key]
	if track then
		track:Play(0.15)
	end
	visual.playing = key
end

local function add(anchor: Instance)
	if not anchor:IsA("BasePart") or visuals[anchor] then
		return
	end
	local visual: Visual = {
		anchor = anchor,
		model = nil :: any,
		real = false,
		cframe = anchor.CFrame,
		tracks = {},
		playing = nil,
		speed = 0,
	}
	visuals[anchor] = visual
	makeModel(visual)
end

local function remove(anchor: Instance)
	local visual = visuals[anchor :: BasePart]
	if visual then
		visual.model:Destroy()
		visuals[anchor :: BasePart] = nil
	end
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	local focus = if camera then camera.Focus.Position else Vector3.zero
	local alpha = 1 - math.exp(-FOLLOW * dt)
	for anchor, visual in visuals do
		local target = anchor.CFrame
		local far = (target.Position - focus).Magnitude > DRAW_DISTANCE
		if (target.Position - visual.cframe.Position).Magnitude > 12 then
			visual.cframe = target -- respawned somewhere else: jump there
		end
		local before = visual.cframe.Position
		visual.cframe = visual.cframe:Lerp(target, alpha)
		local moved = ((visual.cframe.Position - before) * Vector3.new(1, 0, 1)).Magnitude / math.max(dt, 1e-3)
		visual.speed += (moved - visual.speed) * math.min(1, dt * 8)
		if far then
			if visual.model.Parent ~= nil then
				visual.model.Parent = nil
				visual.playing = nil
			end
			continue
		end
		if visual.model.Parent ~= holder then
			visual.model.Parent = holder
		end
		visual.model:PivotTo(visual.cframe)
		if visual.real then
			if anchor:GetAttribute("Running") == true then
				play(visual, "Run")
			elseif visual.speed > 0.6 then
				play(visual, "Walk")
			else
				play(visual, "Idle")
			end
		end
	end
end

function DustBunnyController:Start()
	holder = Instance.new("Folder")
	holder.Name = "DustBunnyModels"
	holder.Parent = Workspace
	local folder = Workspace:WaitForChild("DustBunnies")
	folder.ChildAdded:Connect(add)
	folder.ChildRemoved:Connect(remove)
	for _, anchor in folder:GetChildren() do
		add(anchor)
	end
	-- Swap the placeholders for the voxel bunny once it has loaded.
	task.spawn(function()
		while not AssetLibrary.has(MODEL) do
			task.wait(1)
		end
		for _, visual in visuals do
			if not visual.real then
				makeModel(visual)
			end
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return DustBunnyController
