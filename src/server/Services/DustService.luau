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
local baseColor: { [number]: Color3 } = {}
local baseMaterial: { [number]: Enum.Material } = {}
local zoneTiles: { [string]: { number } } = {}
-- Golden dust piles: a few per zone at a time, worth Economy.Golden.Mult x cash.
local golden: { [number]: boolean } = {}
local goldenCount: { [string]: number } = {}
local GOLD = Color3.fromRGB(255, 205, 60)
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
			part.Material = zone.DustMaterial or Enum.Material.Sand
			-- Each tile takes a colour from the zone's palette (a mix of leaves), with a
			-- slight checker shade so the field doesn't look flat.
			local palette = zone.DustPalette
			local color = if palette then palette[((id * 1103515245 + 12345) // 65536) % #palette + 1] else zone.DustColor
			local shade = if (index + (index // zg.Cols)) % 2 == 0 then 1 else 0.94
			part.Color = Color3.new(color.R * shade, color.G * shade, color.B * shade)
			baseColor[id] = part.Color
			baseMaterial[id] = part.Material
			zoneTiles[zone.Id] = zoneTiles[zone.Id] or {}
			table.insert(zoneTiles[zone.Id], id)
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

local function setGolden(id: number, on: boolean)
	local part = parts[id]
	local zone = zoneOf[id]
	if (golden[id] == true) == on then
		return
	end
	golden[id] = if on then true else nil
	goldenCount[zone.Id] = (goldenCount[zone.Id] or 0) + (if on then 1 else -1)
	part.Color = if on then GOLD else baseColor[id]
	part.Material = if on then Enum.Material.Foil else baseMaterial[id]
	local sparkle = part:FindFirstChild("Gold")
	if on and not sparkle then
		local e = Instance.new("ParticleEmitter")
		e.Name = "Gold"
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(GOLD)
		e.Size = NumberSequence.new(0.6, 0)
		e.Rate = 5
		e.Lifetime = NumberRange.new(0.8, 1.2)
		e.Speed = NumberRange.new(1, 2)
		e.LightEmission = 1
		e.Parent = part
	elseif not on and sparkle then
		sparkle:Destroy()
	end
	part:SetAttribute("Golden", if on then true else nil)
end

-- True (once) if this tile was a golden pile; the pile turns back into normal dust.
function DustService:TakeGolden(id: number): boolean
	if golden[id] then
		setGolden(id, false)
		return true
	end
	return false
end

-- Lightning strike (Thunderstorm): turns up to `count` standing piles around a spot golden.
function DustService:StrikeGolden(position: Vector3, radius: number, count: number): number
	local made = 0
	Grid.forEachInRadius(position, radius, function(id)
		if made < count and hp[id] and hp[id] > 0 and not golden[id] then
			setGolden(id, true)
			made += 1
		end
	end)
	return made
end

-- Tops every zone up to Economy.Golden.PerZone golden piles on standing dust
-- (more during Golden Hour).
function DustService:RefreshGolden(rng: Random)
	local perZone = math.floor(Economy.Golden.PerZone * S.WeatherService:GetGoldenMult())
	for zoneId, ids in zoneTiles do
		local tries = 0
		while (goldenCount[zoneId] or 0) < perZone and tries < 20 * perZone / Economy.Golden.PerZone do
			tries += 1
			local id = ids[rng:NextInteger(1, #ids)]
			if hp[id] > 0 and not golden[id] then
				setGolden(id, true)
			end
		end
	end
end

-- A random standing tile position in a zone (for dust bunnies).
function DustService:GetRandomTilePosition(zoneId: string, rng: Random): Vector3?
	local ids = zoneTiles[zoneId]
	if not ids then
		return nil
	end
	return Grid.tilePosition(ids[rng:NextInteger(1, #ids)])
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
		local rng = Random.new()
		while true do
			DustService:RefreshGolden(rng)
			task.wait(Economy.Golden.CheckSeconds)
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
