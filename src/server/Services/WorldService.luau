--!strict
-- Finds the static world (src/workspace/Moon) and builds the generated bits on top of it:
-- base slot markers and owner signs. Other services ask it for world positions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Zones = require(Shared.Config.Zones)

-- Slot layout on a base plot, in plot-local studs. -Z points at the Rocket.
local SLOT_COLUMNS = { -12, -6, 0, 6, 12 }
local SLOT_ROWS = { 2, 7.5, 13 }

local WorldService = {}

local moon: Model
local bases: { Model } = {}
local slotCFrames: { [number]: { CFrame } } = {}
local signs: { [number]: TextLabel } = {}

local function find(parent: Instance, path: { string }): Instance
	local current = parent
	for _, name in path do
		current = current:WaitForChild(name, 15) :: Instance
		assert(current, `World is missing {table.concat(path, ".")}`)
	end
	return current
end

local function makeSlotMarker(index: number, slot: number, cf: CFrame, parent: Instance)
	local marker = Instance.new("Part")
	marker.Name = "Slot" .. slot
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.2, 4, 4)
	marker.CFrame = cf * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90))
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CastShadow = false
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(90, 140, 200)
	marker.Transparency = 0.6
	marker:SetAttribute("Base", index)
	marker:SetAttribute("Slot", slot)
	marker.Parent = parent
end

function WorldService:Init()
	moon = Workspace:WaitForChild("Moon", 30) :: Model
	assert(moon, "Workspace.Moon is missing. Is LiveSync connected?")
	local basesFolder = find(moon, { "Bases" })
	for i = 1, Zones.BaseCount do
		local base = find(basesFolder, { "Base" .. i }) :: Model
		bases[i] = base
		local plot = find(base, { "Plot" }) :: BasePart
		local top = plot.CFrame * CFrame.new(0, plot.Size.Y / 2, 0)

		local slotFolder = Instance.new("Folder")
		slotFolder.Name = "Slots"
		slotFolder.Parent = base
		local list = {}
		for _, z in SLOT_ROWS do
			for _, x in SLOT_COLUMNS do
				if #list < Economy.MaxSlots then
					local cf = top * CFrame.new(x, 0, z)
					table.insert(list, cf)
					makeSlotMarker(i, #list, cf, slotFolder)
				end
			end
		end
		slotCFrames[i] = list

		-- Owner sign floating over the plot.
		local signAnchor = Instance.new("Attachment")
		signAnchor.Name = "SignAnchor"
		signAnchor.Position = Vector3.new(0, plot.Size.Y / 2 + 14, 6)
		signAnchor.Parent = plot
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "OwnerSign"
		billboard.Size = UDim2.fromOffset(240, 50)
		billboard.MaxDistance = 140
		billboard.LightInfluence = 0
		billboard.Adornee = signAnchor
		billboard.Parent = plot
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.3
		label.Text = "Free Base"
		label.Parent = billboard
		signs[i] = label
	end
end

function WorldService:GetMoon(): Model
	return moon
end

function WorldService:GetBase(index: number): Model
	return bases[index]
end

function WorldService:GetSlotCFrame(index: number, slot: number): CFrame
	return slotCFrames[index][slot]
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
