--!strict
-- Finds the player behind a Touched hit: their character, or the vehicle they drive.
local Players = game:GetService("Players")

local Touch = {}

function Touch.playerFromHit(hit: BasePart): Player?
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		return player
	end
	local seat = model:FindFirstChild("Seat")
	if seat and seat:IsA("VehicleSeat") and seat.Occupant then
		return Players:GetPlayerFromCharacter(seat.Occupant.Parent)
	end
	return nil
end

-- Touched fires many times per second; this lets each player through once per interval.
function Touch.debounced(interval: number, handler: (Player) -> ()): (BasePart) -> ()
	local last: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
	return function(hit: BasePart)
		local player = Touch.playerFromHit(hit)
		if not player then
			return
		end
		local now = os.clock()
		if (last[player] or 0) + interval > now then
			return
		end
		last[player] = now
		handler(player)
	end
end

return Touch
