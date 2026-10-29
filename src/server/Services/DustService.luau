--!strict
-- Owns the leaf tiles. Tiles are generated at server start from Config/Zones (nothing is
-- stored in the repo) and tracked by HP. The server keeps only data: every client draws
-- the leaves, litter and trash near it (LeafController) from a snapshot (GetDust) plus
-- compact batches: TilesCleared, TilesRestored (regrown) and TilesGolden (golden piles).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Grid = require(Shared.Grid)
local Net = require(Shared.Net)

local REGROW_CHECK_SECONDS = 0.5
local GOLDEN_OFF = 32768 -- TilesGolden: id = turned golden, id + GOLDEN_OFF = back to normal

local DustService = {}

local S: any
local hp: { [number]: number } = {}
local zoneOf: { [number]: any } = {} -- id -> ZoneDef
local zoneTiles: { [string]: { number } } = {}
-- Golden dust piles: a few per zone at a time, worth Economy.Golden.Mult x cash.
local golden: { [number]: boolean } = {}
local goldenCount: { [string]: number } = {}
local clearedBatch: { number } = {}
-- Cleared tiles by who swept them (UserId), so each client flies the leaves to the right
-- player's tool or backpack. 0: nobody in particular.
local clearedBy: { [number]: { number } } = {}
local restoredBatch: { number } = {}
local goldenBatch: { number } = {}
-- One FIFO per zone (same regrow delay per zone, so entries come out in order).
type RegrowQueue = { items: { [number]: { id: number, at: number } }, head: number, tail: number }
local regrowQueues: { [string]: RegrowQueue } = {}

local moonTotal = 0
local moonClearedSinceReset = 0

local function buildTiles()
	for _, zg in Grid.Zones do
		local zone = zg.Zone
		for index in zg.Exists do
			local id = zg.FirstId + index
			zoneTiles[zone.Id] = zoneTiles[zone.Id] or {}
			table.insert(zoneTiles[zone.Id], id)
			hp[id] = zone.DustHP
			zoneOf[id] = zone
			if zone.IsMoon then
				moonTotal += 1
			end
		end
		regrowQueues[zone.Id] = { items = {}, head = 1, tail = 0 }
	end
	assert(Grid.MaxId < GOLDEN_OFF, "tile ids must stay below GOLDEN_OFF")
end

local function restore(id: number)
	local zone = zoneOf[id]
	if not zone or hp[id] > 0 then
		return
	end
	hp[id] = zone.DustHP
	table.insert(restoredBatch, id)
end

function DustService:GetZone(id: number)
	return zoneOf[id]
end

local function setGolden(id: number, on: boolean)
	local zone = zoneOf[id]
	if (golden[id] == true) == on then
		return
	end
	golden[id] = if on then true else nil
	goldenCount[zone.Id] = (goldenCount[zone.Id] or 0) + (if on then 1 else -1)
	table.insert(goldenBatch, if on then id else id + GOLDEN_OFF)
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

-- Applies damage. Returns true if this hit cleared the tile. by: the sweeping player.
function DustService:Damage(id: number, power: number, by: Player?): boolean
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
	local who = if by then by.UserId else 0
	local list = clearedBy[who]
	if not list then
		list = {}
		clearedBy[who] = list
	end
	table.insert(list, id)
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
	for id in hp do
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

-- What a joining client needs to draw the field: every cleared tile and every golden pile.
local function snapshot(): (buffer, buffer)
	local cleared, gold = {}, {}
	for id, value in hp do
		if value <= 0 then
			table.insert(cleared, id)
		end
	end
	for id in golden do
		table.insert(gold, id)
	end
	return Grid.pack(cleared), Grid.pack(gold)
end

function DustService:Init(services)
	S = services
	buildTiles()
	Net.onInvoke("GetDust", function()
		return snapshot()
	end)
	S.StateService:GetServerState():SetAttribute("MoonTiles", moonTotal)
end

function DustService:Start()
	task.spawn(function()
		while true do
			task.wait(Economy.TileBatchInterval)
			if #clearedBatch > 0 then
				local byPlayer = clearedBy
				clearedBatch = {}
				clearedBy = {}
				for userId, ids in byPlayer do
					Net.fireAll("TilesCleared", Grid.pack(ids), userId)
				end
			end
			if #restoredBatch > 0 then
				local batch = restoredBatch
				restoredBatch = {}
				Net.fireAll("TilesRestored", Grid.pack(batch))
			end
			if #goldenBatch > 0 then
				local batch = goldenBatch
				goldenBatch = {}
				Net.fireAll("TilesGolden", Grid.pack(batch))
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
			-- Leaf Storm (Config/Weather RegrowMult): leaves blow back in faster.
			local regrowMult = S.WeatherService:GetRegrowMult()
			for zoneId, queue in regrowQueues do
				local zone = zoneTiles[zoneId] and zoneOf[zoneTiles[zoneId][1]]
				local early = if zone then zone.RegrowSeconds * (1 - regrowMult) else 0
				while queue.head <= queue.tail and queue.items[queue.head].at - early <= now do
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
