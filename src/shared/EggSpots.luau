--!strict
-- Where eggs may go in a pet park (base local X/Z studs). Shared so the server checks the
-- exact rules the client's placement ghost shows (green = ok, red = not here).
local World = require(script.Parent.Config.World)

local EggSpots = {}

EggSpots.Spacing = 4.5 -- studs between eggs
EggSpots.Margin = 3 -- studs from the fence

type Entry = { Uid: string, X: number?, Z: number? }

-- Why an egg can't go at (x, z), or nil if it can.
function EggSpots.problem(hatching: { Entry }, x: number, z: number, ignoreUid: string?): string?
	local min, max = World.Base.ParkMin, World.Base.ParkMax
	local m = EggSpots.Margin
	if x < min.X + m or x > max.X - m or z < min.Y + m or z > max.Y - m then
		return "Put it inside your pet park"
	end
	local p = Vector2.new(x, z)
	for _, prop in World.Base.ParkProps do
		if (p - Vector2.new(prop.Position.X, prop.Position.Z)).Magnitude < prop.Radius + 1.5 then
			return "Too close to something, try an open spot"
		end
	end
	for _, entry in hatching do
		if entry.Uid ~= ignoreUid and entry.X and entry.Z and (p - Vector2.new(entry.X, entry.Z)).Magnitude < EggSpots.Spacing then
			return "Too close to another egg"
		end
	end
	return nil
end

-- A free spot near the park gate (Place Eggs, and eggs saved before free placement).
function EggSpots.auto(hatching: { Entry }, ignoreUid: string?): (number?, number?)
	local min, max = World.Base.ParkMin, World.Base.ParkMax
	local front = Vector2.new(0, min.Y + 8)
	local best, bestDistance = nil, math.huge
	for x = min.X + 6, max.X - 6, 5 do
		for z = min.Y + 6, max.Y - 6, 5 do
			local d = (Vector2.new(x, z) - front).Magnitude
			if d < bestDistance and not EggSpots.problem(hatching, x, z, ignoreUid) then
				best, bestDistance = Vector2.new(x, z), d
			end
		end
	end
	if best then
		return best.X, best.Y
	end
	return nil, nil
end

return EggSpots
