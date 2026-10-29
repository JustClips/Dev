--!strict
-- Validates sweep ticks from clients and applies them. The client only says "I'm sweeping
-- at P"; the server checks rate, distance and zone, then uses the server's tool stats.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Grid = require(Shared.Grid)
local Net = require(Shared.Net)
local Upgrades = require(Shared.Config.Upgrades)

local BURST = 3
local rng = Random.new()

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
	-- Every client shows this player's tool effects while ticks keep coming (ToolFxController).
	(character :: Model):SetAttribute("SweepAt", Workspace:GetServerTimeNow())
	local zone = Grid.zoneAt(position)
	if not zone or not S.ZoneService:IsUnlocked(player, zone.Id) then
		return
	end

	S.DustBunnyService:TryCatch(player, position, tool.Radius)
	local cleared = {}
	Grid.forEachInRadius(position, tool.Radius, function(id)
		if S.DustService:Damage(id, tool.Power, player) then
			table.insert(cleared, id)
		end
	end)
	if #cleared == 0 then
		return
	end

	-- Combo: keep clearing dust without a break to push the cash multiplier up to x3
	-- (higher and longer with the upgrade tree).
	local levels = session.Data.Upgrades
	local combo = Economy.Combo
	if now - (runtime.ComboAt or 0) > combo.Timeout + Upgrades.stat(levels, "ComboTime") then
		runtime.Combo = 1
	end
	runtime.Combo = math.min(combo.Max + Upgrades.stat(levels, "ComboMax"), (runtime.Combo or 1) + combo.Step)
	runtime.ComboAt = now

	-- Lucky Sweep (upgrade tree): each tile has a small chance to pay several times over.
	local critChance = Upgrades.stat(levels, "Crit")
	local critMult = Upgrades.CritBaseMult + Upgrades.stat(levels, "CritMult")
	local goldenMult = Economy.Golden.Mult * Upgrades.multiplier(levels, "Golden")

	local totalDust, totalValue, goldenHits, critHits, trashHits = 0, 0, 0, 0, 0
	local trashKind: string? = nil
	local weatherMult = S.WeatherService:GetCashMult()
	for _, id in cleared do
		local tileZone = S.DustService:GetZone(id)
		local mult = runtime.Combo * weatherMult
		if S.DustService:TakeGolden(id) then
			mult *= goldenMult
			goldenHits += 1
		end
		-- Trash (cans, bottles...) lying among the leaves pays more.
		local trash = Grid.trashKind(id)
		if trash then
			mult *= Economy.TrashMult
			trashHits += 1
			trashKind = trash
		end
		if critChance > 0 and rng:NextNumber() < critChance then
			mult *= critMult
			critHits += 1
		end
		local units, value = S.BackpackService:AddDust(player, tileZone, tool.Power, mult)
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
		Combo = runtime.Combo,
		Golden = goldenHits,
		Crit = critHits,
		Trash = trashHits,
		TrashKind = trashKind,
		CritMult = critMult,
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
	-- Volume sliders (settings window), saved with the profile.
	Net.onEvent("SetSetting", function(player, key, value)
		local data = S.DataService:GetData(player)
		if data and (key == "Music" or key == "Sfx") and type(value) == "number" and value == value then
			data.Settings[key] = math.clamp(math.floor(value * 100 + 0.5) / 100, 0, 1)
		elseif data and key == "Hotbar" and type(value) == "table" then
			-- What sits in hotbar slots 3-8 ("P:<uid>", "E:<rarity>", "I:<item>" or "").
			local slots = {}
			for i = 1, 6 do
				local v = value[i]
				slots[i] = if type(v) == "string" and #v <= 48 and (v == "" or string.match(v, "^[PEI]:[%w_%-]+$")) then v else ""
			end
			data.Settings.Hotbar = slots
		end
	end)
end

return SweepService
