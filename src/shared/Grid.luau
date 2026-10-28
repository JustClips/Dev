--!strict
-- Deterministic dust tile grid shared by server and client.
-- Every zone is a rectangle of TileSize cells. Tile ids are global integers (fit in u16),
-- so the server can send compact batches and the client can compute positions itself.
local Zones = require(script.Parent.Config.Zones)
local Types = require(script.Parent.Types)

type ZoneDef = Types.ZoneDef

export type ZoneGrid = {
	Zone: ZoneDef,
	Cols: number,
	Rows: number,
	FirstId: number,
	LastId: number,
	Exists: { [number]: boolean }, -- local index -> tile exists (not excluded)
	Count: number,
}

local Grid = {}
Grid.Zones = {} :: { ZoneGrid }
Grid.ByZoneId = {} :: { [string]: ZoneGrid }
Grid.MaxId = 0

local nextId = 1
for _, zone in Zones.List do
	local size = zone.TileSize
	local cols = math.floor((zone.Max.X - zone.Min.X) / size)
	local rows = math.floor((zone.Max.Y - zone.Min.Y) / size)
	local exists: { [number]: boolean } = {}
	local count = 0
	for row = 0, rows - 1 do
		for col = 0, cols - 1 do
			local center = Vector2.new(zone.Min.X + (col + 0.5) * size, zone.Min.Y + (row + 0.5) * size)
			local blocked = false
			for _, ex in zone.Exclusions do
				if (center - ex.Center).Magnitude < ex.Radius then
					blocked = true
					break
				end
			end
			if not blocked then
				exists[row * cols + col] = true
				count += 1
			end
		end
	end
	local zg: ZoneGrid = {
		Zone = zone,
		Cols = cols,
		Rows = rows,
		FirstId = nextId,
		LastId = nextId + cols * rows - 1,
		Exists = exists,
		Count = count,
	}
	nextId += cols * rows
	table.insert(Grid.Zones, zg)
	Grid.ByZoneId[zone.Id] = zg
end
Grid.MaxId = nextId - 1
assert(Grid.MaxId < 65535, "Too many tiles for u16 ids")

function Grid.zoneGridOfId(id: number): ZoneGrid?
	for _, zg in Grid.Zones do
		if id >= zg.FirstId and id <= zg.LastId then
			return zg
		end
	end
	return nil
end

function Grid.exists(id: number): boolean
	local zg = Grid.zoneGridOfId(id)
	return zg ~= nil and zg.Exists[id - zg.FirstId] == true
end

function Grid.tilePosition(id: number): Vector3?
	local zg = Grid.zoneGridOfId(id)
	if not zg then
		return nil
	end
	local index = id - zg.FirstId
	local col = index % zg.Cols
	local row = index // zg.Cols
	local zone = zg.Zone
	local size = zone.TileSize
	return Vector3.new(zone.Min.X + (col + 0.5) * size, zone.GroundY + Zones.TileHeight * 0.5, zone.Min.Y + (row + 0.5) * size)
end

-- Zone that contains an XZ position (ignores height).
function Grid.zoneAt(position: Vector3): ZoneDef?
	for _, zg in Grid.Zones do
		local zone = zg.Zone
		if position.X >= zone.Min.X and position.X <= zone.Max.X and position.Z >= zone.Min.Y and position.Z <= zone.Max.Y then
			return zone
		end
	end
	return nil
end

-- Calls fn(id) for every existing tile whose center is within radius of position (XZ).
-- Grid lookup: only touches cells inside the bounding square.
function Grid.forEachInRadius(position: Vector3, radius: number, fn: (number) -> ())
	local r2 = radius * radius
	for _, zg in Grid.Zones do
		local zone = zg.Zone
		if position.X + radius < zone.Min.X or position.X - radius > zone.Max.X then
			continue
		end
		if position.Z + radius < zone.Min.Y or position.Z - radius > zone.Max.Y then
			continue
		end
		local size = zone.TileSize
		local c0 = math.max(0, math.floor((position.X - radius - zone.Min.X) / size))
		local c1 = math.min(zg.Cols - 1, math.floor((position.X + radius - zone.Min.X) / size))
		local r0 = math.max(0, math.floor((position.Z - radius - zone.Min.Y) / size))
		local r1 = math.min(zg.Rows - 1, math.floor((position.Z + radius - zone.Min.Y) / size))
		for row = r0, r1 do
			local cz = zone.Min.Y + (row + 0.5) * size - position.Z
			for col = c0, c1 do
				local cx = zone.Min.X + (col + 0.5) * size - position.X
				if cx * cx + cz * cz <= r2 then
					local index = row * zg.Cols + col
					if zg.Exists[index] then
						fn(zg.FirstId + index)
					end
				end
			end
		end
	end
end

-- Pack / unpack tile id lists for remotes.
function Grid.pack(ids: { number }): buffer
	local b = buffer.create(#ids * 2)
	for i, id in ids do
		buffer.writeu16(b, (i - 1) * 2, id)
	end
	return b
end

function Grid.unpack(b: buffer): { number }
	local ids = table.create(buffer.len(b) // 2)
	for i = 0, buffer.len(b) - 2, 2 do
		table.insert(ids, buffer.readu16(b, i))
	end
	return ids
end

return Grid
