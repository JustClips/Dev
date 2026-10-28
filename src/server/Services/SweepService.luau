--!strict
-- Validates sweep ticks from clients and applies them. The client only says "I'm sweeping
-- at P"; the server checks rate, distance and zone, then uses the server's tool stats.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Grid = require(Shared.Grid)
local Net = require(Shared.Net)

local BURST = 3

local SweepService = {}

local S: any
local warned: { [string]: boolean } = {}

local function warnOnce(player: Player, reason: string)
	local key = player.UserId .. reason
	if not warned[key] then
		warned[key] = true
		warn(`[SweepService] ignoring sweeps from {player.Name}: {reason}`)
	end
end

local function isFiniteVector(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < 1e5 and math.abs(v.Y) < 1e5 and math.abs(v.Z) < 1e5
end

local function onSweep(player: Player, position: any)
	if typeof(position) ~= "Vector3" or not isFiniteVector(position) then
		return
	end
	local session = S.DataService:GetSession(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not session or not root then
		return
	end
	-- Token bucket: 10 ticks/s on average, small bursts allowed for network jitter.
	local runtime = session.Runtime
	local now = os.clock()
	local tokens = math.min(BURST, (runtime.SweepTokens or BURST) + (now - (runtime.SweepAt or now)) * Economy.SweepMaxPerSecond)
	runtime.SweepAt = now
	if tokens < 1 then
		runtime.SweepTokens = tokens
		warnOnce(player, "too many ticks")
		return
	end
	runtime.SweepTokens = tokens - 1

	local tool = S.ToolService:GetSweepTool(player)
	local offset = (position - root.Position) * Vector3.new(1, 0, 1)
	if offset.Magnitude > tool.Radius + Economy.SweepDistanceSlack then
		warnOnce(player, "too far from character")
		return
	end
	local zone = Grid.zoneAt(position)
	if not zone or not S.ZoneService:IsUnlocked(player, zone.Id) then
		return
	end

	local cleared = {}
	Grid.forEachInRadius(position, tool.Radius, function(id)
		if S.DustService:Damage(id, tool.Power) then
			table.insert(cleared, id)
		end
	end)
	if #cleared == 0 then
		return
	end

	local totalDust, totalValue = 0, 0
	for _, id in cleared do
		local tileZone = S.DustService:GetZone(id)
		local units, value = S.BackpackService:AddDust(player, tileZone, tool.Power)
		totalDust += units
		totalValue += value
		S.EggService:OnTileCleared(player, tileZone, Grid.tilePosition(id) :: Vector3)
	end
	S.AnalyticsService:Funnel(player, "FirstSweep")
	S.StateService:Mark(player)
	Net.fire("SweepResult", player, {
		Dust = totalDust,
		Value = totalValue * S.BoostService:GetCashMultiplier(player),
		Full = S.BackpackService:IsFull(player),
		Tiles = #cleared,
	})
end

function SweepService:Init(services)
	S = services
	Net.onEvent("SweepTick", onSweep)
	Net.onEvent("SetAutoSweep", function(player, enabled)
		local data = S.DataService:GetData(player)
		if data and type(enabled) == "boolean" then
			data.Settings.AutoSweep = enabled
			S.StateService:Mark(player)
		end
	end)
end

return SweepService
