--!strict
-- Where eggs may go in a pet park (base local X/Z studs). Shared so the server checks the
-- exact rules the client's placement ghost shows (green = ok, red = not here). The rules
-- follow what the player sees: the fence, the real footprint of each prop and other eggs.
local World = require(script.Parent.Config.World)

local EggSpots = {}

EggSpots.Spacing = 4 -- studs between egg centres
EggSpots.Margin = 2 -- studs from the fence to an egg's centre
EggSpots.EggRadius = 1.2 -- an egg's foot, kept off props

type Entry = { Uid: string, X: number?, Z: number? }

-- How far (x, z) is from the outside of a prop's footprint (negative = on top of it).
local function propGap(prop, x: number, z: number): number
	local size = prop.Size or Vector2.new(prop.Radius * 2, prop.Radius * 2)
	local frame = CFrame.new(prop.Position.X, 0, prop.Position.Z) * CFrame.Angles(0, math.rad(prop.Yaw or 0), 0)
	local p = frame:PointToObjectSpace(Vector3.new(x, 0, z))
	local dx = math.abs(p.X) - size.X / 2
	local dz = math.abs(p.Z) - size.Y / 2
	if dx <= 0 and dz <= 0 then
		return math.max(dx, dz)
	end
	return Vector2.new(math.max(dx, 0), math.max(dz, 0)).Magnitude
end

-- Why an egg can't go at (x, z), or nil if it can. pad makes every rule a bit stricter
-- (the client snaps with a little pad so the server, with none, always agrees).
function EggSpots.problem(hatching: { Entry }, x: number, z: number, ignoreUid: string?, pad: number?): string?
	local extra = pad or 0
	local min, max = World.Base.ParkMin, World.Base.ParkMax
	local m = EggSpots.Margin + extra
	if x < min.X + m or x > max.X - m or z < min.Y + m or z > max.Y - m then
		return "Put it inside your pet park"
	end
	for _, prop in World.Base.ParkProps do
		if propGap(prop, x, z) < EggSpots.EggRadius + extra then
			return "Something's in the way, try an open spot"
		end
	end
	local p = Vector2.new(x, z)
	for _, entry in hatching do
		if entry.Uid ~= ignoreUid and entry.X and entry.Z and (p - Vector2.new(entry.X, entry.Z)).Magnitude < EggSpots.Spacing + extra then
			return "Too close to another egg"
		end
	end
	return nil
end

-- The closest free spot to (x, z) within reach studs, so a click next to an egg, a rock
-- or the fence still lands. A click a little outside the fence is pulled inside first.
-- Returns nil, nil and the reason when nothing near is free.
function EggSpots.nearest(hatching: { Entry }, x: number, z: number, reach: number, pad: number?): (number?, number?, string?)
	local min, max = World.Base.ParkMin, World.Base.ParkMax
	local m = EggSpots.Margin + (pad or 0) + 0.05
	local cx = math.clamp(x, min.X + m, max.X - m)
	local cz = math.clamp(z, min.Y + m, max.Y - m)
	if (Vector2.new(cx, cz) - Vector2.new(x, z)).Magnitude > reach then
		return nil, nil, "Put it inside your pet park"
	end
	local first = EggSpots.problem(hatching, cx, cz, nil, pad)
	if not first then
		return cx, cz, nil
	end
	for r = 0.5, reach, 0.5 do
		local steps = math.max(8, math.floor(r * 6))
		for i = 0, steps - 1 do
			local a = i / steps * math.pi * 2
			local px, pz = cx + math.cos(a) * r, cz + math.sin(a) * r
			if not EggSpots.problem(hatching, px, pz, nil, pad) then
				return px, pz, nil
			end
		end
	end
	return nil, nil, first
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
