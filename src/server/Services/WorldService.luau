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

local function find(parent: Instance, path: { string }): Instance
	local current = parent
	for _, name in path do
		current = current:WaitForChild(name, 15) :: Instance
		assert(current, `World is missing {table.concat(path, ".")}`)
	end
	return current
end

function WorldService:Init(services)
	S = services
	moon = Workspace:WaitForChild("Moon", 30) :: Model
	assert(moon, "Workspace.Moon is missing. Is LiveSync connected?")
	local basesFolder = find(moon, { "Bases" })
	for i = 1, World.BaseCount do
		bases[i] = find(basesFolder, { "Base" .. i }) :: Model
	end
	local started = os.clock()
	local okLight, errLight = pcall(MapBuilder.setupLighting)
	if not okLight then
		warn("[WorldService] lighting failed: " .. tostring(errLight))
	end
	local ok, err = pcall(MapBuilder.buildTerrain)
	if not ok then
		warn("[WorldService] terrain build failed: " .. tostring(err))
	end
	local okS, errS = pcall(MapBuilder.buildStructures)
	if not okS then
		warn("[WorldService] structures failed: " .. tostring(errS))
	end
	-- The loading screen waits for these.
	Workspace:SetAttribute("TerrainReady", true)
	print(string.format("[WorldService] terrain and structures built in %.1f s", os.clock() - started))
end

function WorldService:Start()
	task.spawn(function()
		S.AssetService:WaitReady(90)
		local ok, err = pcall(MapBuilder.buildProps)
		if not ok then
			warn("[WorldService] props failed: " .. tostring(err))
		end
		Workspace:SetAttribute("PropsReady", true)
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

-- Updates the sign over a base's arch (name + avatar, or "Free Base").
function WorldService:SetOwnerName(index: number, name: string?, userId: number?)
	local sign = MapBuilder.getBaseSign(index)
	if not sign then
		return
	end
	for _, title in sign.Titles do
		title.Text = if name then `{name}'s Base` else "Free Base"
	end
	for _, sub in sign.Subs do
		sub.Text = if name then "Hatching pets" else "Claim it by joining!"
	end
	for _, avatar in sign.Avatars do
		avatar.Visible = userId ~= nil
		avatar.Image = if userId then `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150` else ""
	end
end

return WorldService
