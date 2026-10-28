--!strict
-- Owns the dust tiles. Tiles are generated at server start from Config/Zones (nothing is
-- stored in the repo) and tracked by HP. Clears go to clients in compact batches for VFX;
-- the tile visuals themselves replicate as normal part properties.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Zones = require(Shared.Config.Zones)
local Grid = require(Shared.Grid)
local Net = require(Shared.Net)

local TAG = "Dust"
local REGROW_CHECK_SECONDS = 0.5

local DustService = {}

local S: any
local parts: { [number]: BasePart } = {}
local hp: { [number]: number } = {}
local zoneOf: { [number]: any } = {} -- id -> ZoneDef
local clearedBatch: { number } = {}
-- One FIFO per zone (same regrow delay per zone, so entries come out in order).
type RegrowQueue = { items: { [number]: { id: number, at: number } }, head: number, tail: number }
local regrowQueues: { [string]: RegrowQueue } = {}

local moonTotal = 0
local moonClearedSinceReset = 0

local function buildTiles()
	local root = Instance.new("Folder")
	root.Name = "DustTiles"
	for _, zg in Grid.Zones do
		local zone = zg.Zone
		local folder = Instance.new("Folder")
		folder.Name = zone.Id
		local size = Vector3.new(zone.TileSize - 0.25, Zones.TileHeight, zone.TileSize - 0.25)
		for index in zg.Exists do
			local id = zg.FirstId + index
			local position = Grid.tilePosition(id) :: Vector3
			local part = Instance.new("Part")
			part.Name = tostring(id)
			part.Size = size
			part.CFrame = CFrame.new(position)
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Material = Enum.Material.Sand
			-- Slight checker variation so the field doesn't look flat.
			local shade = if (index + (index // zg.Cols)) % 2 == 0 then 1 else 0.94
			part.Color = Color3.new(zone.DustColor.R * shade, zone.DustColor.G * shade, zone.DustColor.B * shade)
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			CollectionService:AddTag(part, TAG)
			part.Parent = folder
			parts[id] = part
			hp[id] = zone.DustHP
			zoneOf[id] = zone
			if zone.IsMoon then
				moonTotal += 1
			end
		end
		regrowQueues[zone.Id] = { items = {}, head = 1, tail = 0 }
		folder.Parent = root
	end
	root.Parent = Workspace
end

local function restore(id: number)
	local zone = zoneOf[id]
	if not zone or hp[id] > 0 then
		return
	end
	hp[id] = zone.DustHP
	local part = parts[id]
	part.Transparency = 0
	CollectionService:AddTag(part, TAG)
end

function DustService:GetZone(id: number)
	return zoneOf[id]
end

function DustService:IsCleared(id: number): boolean
	return (hp[id] or 0) <= 0
end

-- Applies damage. Returns true if this hit cleared the tile.
function DustService:Damage(id: number, power: number): boolean
	local current = hp[id]
	if not current or current <= 0 then
		return false
	end
	current -= power
	hp[id] = current
	if current > 0 then
		return false
	end
	hp[id] = 0
	local part = parts[id]
	part.Transparency = 1
	CollectionService:RemoveTag(part, TAG)
	table.insert(clearedBatch, id)

	local zone = zoneOf[id]
	if zone.IsMoon then
		moonClearedSinceReset += 1
	end
	local queue = regrowQueues[zone.Id]
	queue.tail += 1
	queue.items[queue.tail] = { id = id, at = os.clock() + zone.RegrowSeconds }
	return true
end

-- 0..1 progress of the shared "Moon Clean" bar.
function DustService:GetMoonProgress(): number
	if moonTotal == 0 then
		return 0
	end
	return math.clamp(moonClearedSinceReset / (moonTotal * Economy.Shower.FillFraction), 0, 1)
end

function DustService:ResetMoonProgress()
	moonClearedSinceReset = 0
end

function DustService:RespawnAll()
	for id in parts do
		restore(id)
	end
	for zoneId in regrowQueues do
		regrowQueues[zoneId] = { items = {}, head = 1, tail = 0 }
	end
end

-- Random tile position in Moon zones (for Meteor Shower eggs).
function DustService:GetRandomMoonPosition(rng: Random): Vector3
	local moonZones = {}
	for _, zg in Grid.Zones do
		if zg.Zone.IsMoon then
			table.insert(moonZones, zg)
		end
	end
	for _ = 1, 30 do
		local zg = moonZones[rng:NextInteger(1, #moonZones)]
		local index = rng:NextInteger(0, zg.Cols * zg.Rows - 1)
		if zg.Exists[index] then
			return Grid.tilePosition(zg.FirstId + index) :: Vector3
		end
	end
	return Vector3.new(0, 1, -40)
end

function DustService:Init(services)
	S = services
	buildTiles()
	S.StateService:GetServerState():SetAttribute("MoonTiles", moonTotal)
end

function DustService:Start()
	task.spawn(function()
		while true do
			task.wait(Economy.TileBatchInterval)
			if #clearedBatch > 0 then
				local batch = clearedBatch
				clearedBatch = {}
				Net.fireAll("TilesCleared", Grid.pack(batch))
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(REGROW_CHECK_SECONDS)
			local now = os.clock()
			for _, queue in regrowQueues do
				while queue.head <= queue.tail and queue.items[queue.head].at <= now do
					restore(queue.items[queue.head].id)
					queue.items[queue.head] = nil
					queue.head += 1
				end
				if queue.head > queue.tail then
					queue.head, queue.tail = 1, 0
				end
			end
		end
	end)
end

return DustService
