--!strict
-- Owns the leaf tiles. Tiles are generated at server start from Config/Zones (nothing is
-- stored in the repo). Every player has their own field (Dev, 2026-10-30): what you sweep
-- clears and regrows only for you, so a fast car can't empty the map for everyone. The
-- server keeps only data: each client draws its own field (LeafController) from a snapshot
-- (GetDust) plus compact batches sent only to that player: TilesCleared and TilesRestored
-- (regrown). Golden piles (TilesGolden) are shared: whoever sweeps one first gets it.
-- The "World Cleaned" bar counts everyone's sweeping together.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Grid = require(Shared.Grid)
local Net = require(Shared.Net)
local Upgrades = require(Shared.Config.Upgrades)

local REGROW_CHECK_SECONDS = 0.5
local GOLDEN_OFF = 32768 -- TilesGolden: id = turned golden, id + GOLDEN_OFF = back to normal

local DustService = {}

local S: any
local zoneOf: { [number]: any } = {} -- id -> ZoneDef
local zoneTiles: { [string]: { number } } = {}
-- Golden dust piles: a few per zone at a time, worth Economy.Golden.Mult x cash.
local golden: { [number]: boolean } = {}
local goldenCount: { [string]: number } = {}
local goldenBatch: { number } = {}
-- One FIFO per zone (same regrow delay per zone, so entries come out in order).
type RegrowQueue = { items: { [number]: { id: number, at: number } }, head: number, tail: number }
-- One player's field: tiles only take space here once they're hit.
type Field = {
	hp: { [number]: number }, -- damaged but standing tiles
	cleared: { [number]: boolean },
	queues: { [string]: RegrowQueue },
	clearedBatch: { number },
	restoredBatch: { number },
}
local fields: { [Player]: Field } = {}

local moonTotal = 0
local moonClearedSinceReset = 0

local function newQueues(): { [string]: RegrowQueue }
	local queues = {}
	for zoneId in zoneTiles do
		queues[zoneId] = { items = {}, head = 1, tail = 0 }
	end
	return queues
end

local function fieldOf(player: Player): Field
	local field = fields[player]
	if not field then
		field = { hp = {}, cleared = {}, queues = newQueues(), clearedBatch = {}, restoredBatch = {} }
		fields[player] = field
	end
	return field
end

local function buildTiles()
	for _, zg in Grid.Zones do
		local zone = zg.Zone
		for index in zg.Exists do
			local id = zg.FirstId + index
			zoneTiles[zone.Id] = zoneTiles[zone.Id] or {}
			table.insert(zoneTiles[zone.Id], id)
			zoneOf[id] = zone
			if zone.IsMoon then
				moonTotal += 1
			end
		end
	end
	assert(Grid.MaxId < GOLDEN_OFF, "tile ids must stay below GOLDEN_OFF")
end

local function restore(field: Field, id: number)
	if not field.cleared[id] then
		return
	end
	field.cleared[id] = nil
	table.insert(field.restoredBatch, id)
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
		if made < count and zoneOf[id] and not golden[id] then
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
			if not golden[id] then
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

function DustService:IsCleared(player: Player, id: number): boolean
	local field = fields[player]
	return field ~= nil and field.cleared[id] == true
end

-- Applies damage to this player's field. Returns true if this hit cleared the tile.
function DustService:Damage(id: number, power: number, by: Player): boolean
	local zone = zoneOf[id]
	if not zone then
		return false
	end
	local field = fieldOf(by)
	if field.cleared[id] then
		return false
	end
	local current = (field.hp[id] or zone.DustHP) - power
	if current > 0 then
		field.hp[id] = current
		return false
	end
	field.hp[id] = nil
	field.cleared[id] = true
	table.insert(field.clearedBatch, id)
	if zone.IsMoon then
		moonClearedSinceReset += 1
	end
	local queue = field.queues[zone.Id]
	queue.tail += 1
	-- Fertilizer (upgrade tree): your leaves grow back faster.
	local data = S.DataService:GetData(by)
	local regrow = Upgrades.multiplier(data and data.Upgrades, "Regrow")
	queue.items[queue.tail] = { id = id, at = os.clock() + zone.RegrowSeconds / regrow }
	return true
end

-- True when this tile has no leaves in this player's field right now.
function DustService:IsCleared(player: Player, id: number): boolean
	local field = fields[player]
	return field ~= nil and field.cleared[id] == true
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

-- Everyone's leaves grow back at once (after an Egg Rain).
function DustService:RespawnAll()
	for _, field in fields do
		for id in field.cleared do
			restore(field, id)
		end
		table.clear(field.hp)
		field.queues = newQueues()
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

-- What a joining client needs to draw its field: its cleared tiles and every golden pile.
local function snapshot(player: Player): (buffer, buffer)
	local cleared, gold = {}, {}
	local field = fields[player]
	if field then
		for id in field.cleared do
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
	Net.onInvoke("GetDust", function(player)
		return snapshot(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		fields[player] = nil
	end)
	S.StateService:GetServerState():SetAttribute("MoonTiles", moonTotal)
end

function DustService:Start()
	task.spawn(function()
		while true do
			task.wait(Economy.TileBatchInterval)
			-- Each player hears only about their own field.
			for player, field in fields do
				if #field.clearedBatch > 0 then
					local batch = field.clearedBatch
					field.clearedBatch = {}
					Net.fire("TilesCleared", player, Grid.pack(batch), player.UserId)
				end
				if #field.restoredBatch > 0 then
					local batch = field.restoredBatch
					field.restoredBatch = {}
					Net.fire("TilesRestored", player, Grid.pack(batch))
				end
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
			for _, field in fields do
				for zoneId, queue in field.queues do
					local zone = zoneTiles[zoneId] and zoneOf[zoneTiles[zoneId][1]]
					local early = if zone then zone.RegrowSeconds * (1 - regrowMult) else 0
					while queue.head <= queue.tail and queue.items[queue.head].at - early <= now do
						restore(field, queue.items[queue.head].id)
						queue.items[queue.head] = nil
						queue.head += 1
					end
					if queue.head > queue.tail then
						queue.head, queue.tail = 1, 0
					end
				end
			end
		end
	end)
end

return DustService
