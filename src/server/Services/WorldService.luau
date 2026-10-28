--!strict
-- The map. Gameplay parts come from src/workspace/Moon (base pads, spawns, sell pad, gates,
-- walls). At start this service builds the terrain and, once AssetService has the models,
-- places every Blender prop (Lib/MapBuilder). Other services ask it for world positions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local MapBuilder = require(script.Parent.Parent.Lib.MapBuilder)

local WorldService = {}

local S: any
local moon: Model
local bases: { Model } = {}
local signs: { [number]: TextLabel } = {}

local function find(parent: Instance, path: { string }): Instance
	local current = parent
	for _, name in path do
		current = current:WaitForChild(name, 15) :: Instance
		assert(current, `World is missing {table.concat(path, ".")}`)
	end
	return current
end

-- Big owner name over the base arch (BillboardGui sized in studs, so it reads like a sign).
local function makeSign(index: number): TextLabel
	local anchor = Instance.new("Part")
	anchor.Name = "SignAnchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CFrame = World.baseCFrame(index) * CFrame.new(World.Base.Arch + Vector3.new(0, 15.5, 0))
	anchor.Parent = bases[index]
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "OwnerSign"
	billboard.Size = UDim2.new(24, 0, 4, 0)
	billboard.MaxDistance = 260
	billboard.LightInfluence = 0
	billboard.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.fromRGB(27, 31, 58)
	label.TextStrokeTransparency = 0
	label.Text = "Free Base"
	label.Parent = billboard
	return label
end

function WorldService:Init(services)
	S = services
	moon = Workspace:WaitForChild("Moon", 30) :: Model
	assert(moon, "Workspace.Moon is missing. Is LiveSync connected?")
	local basesFolder = find(moon, { "Bases" })
	for i = 1, World.BaseCount do
		bases[i] = find(basesFolder, { "Base" .. i }) :: Model
		signs[i] = makeSign(i)
	end
	local started = os.clock()
	local ok, err = pcall(MapBuilder.buildTerrain)
	if not ok then
		warn("[WorldService] terrain build failed: " .. tostring(err))
	end
	print(string.format("[WorldService] terrain built in %.1f s", os.clock() - started))
end

function WorldService:Start()
	task.spawn(function()
		S.AssetService:WaitReady(90)
		local ok, err = pcall(MapBuilder.buildProps)
		if not ok then
			warn("[WorldService] props failed: " .. tostring(err))
		end
	end)
end

function WorldService:GetMoon(): Model
	return moon
end

function WorldService:GetBase(index: number): Model
	return bases[index]
end

function WorldService:GetBaseCFrame(index: number): CFrame
	return World.baseCFrame(index)
end

-- Where a hatching egg in `slot` sits on the hatchery pad.
function WorldService:GetHatchSpot(index: number, slot: number): CFrame
	local spot = World.HatchSpots[((slot - 1) % #World.HatchSpots) + 1]
	return World.baseCFrame(index) * CFrame.new(World.Base.Hatchery + spot + Vector3.new(0, 0.9, 0))
end

function WorldService:GetPad(index: number): BasePart
	return bases[index]:FindFirstChild("Pad") :: BasePart
end

function WorldService:GetSpawnCFrame(index: number): CFrame
	local spawnPart = bases[index]:FindFirstChild("Spawn") :: BasePart
	return spawnPart.CFrame * CFrame.new(0, 4, 0)
end

function WorldService:GetSellPad(): BasePart
	return find(moon, { "Rocket", "SellPad" }) :: BasePart
end

function WorldService:GetGate(zoneId: string): BasePart?
	local gates = moon:FindFirstChild("Gates")
	return if gates then gates:FindFirstChild("Gate_" .. zoneId) :: BasePart? else nil
end

function WorldService:SetOwnerName(index: number, name: string?)
	local label = signs[index]
	if label then
		label.Text = if name then `{name}'s Base` else "Free Base"
	end
end

return WorldService
