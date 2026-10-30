--!strict
-- Validates sweep ticks from clients and applies them. The client only says "I'm sweeping
-- at P"; the server checks rate, distance and zone, then uses the server's tool stats.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Grid = require(Shared.Grid)
local Net = require(Shared.Net)
local Items = require(Shared.Config.Items)
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

-- Clears this player's leaves within `radius` of `position` (hitting them with `damage`,
-- default `power`; `power` also sets the leaves you get), pays them out
-- (combo, golden piles, trash, lucky sweeps), rolls leaf drops and eggs, and tells the
-- client. Used by sweep ticks and the Leaf Bomb.
local function sweepArea(player: Player, session, position: Vector3, radius: number, power: number, now: number, damage: number?): number
	local runtime = session.Runtime
	local levels = session.Data.Upgrades
	-- Bunny Net (Lucky Lab) catches dust bunnies from further away.
	S.DustBunnyService:TryCatch(player, position, radius * Upgrades.multiplier(levels, "BunnyReach"))
	local cleared = {}
	Grid.forEachInRadius(position, radius, function(id)
		if S.DustService:Damage(id, damage or power, player) then
			table.insert(cleared, id)
		end
	end)
	if #cleared == 0 then
		return 0
	end

	-- Combo: keep clearing dust without a break to push the cash multiplier up to x3
	-- (higher and longer with the upgrade tree). Second Wind keeps part of a broken combo.
	local combo = Economy.Combo
	local maxCombo = combo.Max + Upgrades.stat(levels, "ComboMax")
	if now - (runtime.ComboAt or 0) > combo.Timeout + Upgrades.stat(levels, "ComboTime") then
		local keep = math.clamp(Upgrades.stat(levels, "ComboKeep"), 0, 0.9)
		runtime.Combo = 1 + ((runtime.Combo or 1) - 1) * keep
	end
	runtime.Combo = math.min(maxCombo, (runtime.Combo or 1) + combo.Step)
	runtime.ComboAt = now

	-- Lucky Sweep (upgrade tree): each tile has a small chance to pay several times over.
	local critChance = Upgrades.stat(levels, "Crit")
	local critMult = Upgrades.CritBaseMult + Upgrades.stat(levels, "CritMult")
	local goldenMult = Economy.Golden.Mult * Upgrades.multiplier(levels, "Golden")
	local goldenCombo = Upgrades.stat(levels, "GoldenCombo")
	-- Leaf drops (Config/Items): Lucky Finds raises the chance.
	local dropChance = Items.DropChance * Upgrades.multiplier(levels, "ItemFind")

	local totalDust, totalValue, goldenHits, critHits, trashHits = 0, 0, 0, 0, 0
	local trashKind: string? = nil
	local weatherMult = S.WeatherService:GetCashMult()
	for _, id in cleared do
		local tileZone = S.DustService:GetZone(id)
		local mult = runtime.Combo * weatherMult
		if S.DustService:TakeGolden(id) then
			mult *= goldenMult
			goldenHits += 1
			-- Golden Combo (Lucky Lab): a golden pile pushes your combo up.
			if goldenCombo > 0 then
				runtime.Combo = math.min(maxCombo, runtime.Combo + goldenCombo)
			end
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
		local units, value = S.BackpackService:AddDust(player, tileZone, power, mult)
		totalDust += units
		totalValue += value
		local tilePos = Grid.tilePosition(id) :: Vector3
		S.EggService:OnTileCleared(player, tileZone, tilePos)
		S.DropService:OnTileCleared(player, id, tilePos)
		if rng:NextNumber() < dropChance then
			S.DropService:LeafDrop(player, tilePos)
		end
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
	return #cleared
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
	if not zone then
		return
	end
	if not S.ZoneService:IsUnlocked(player, zone.Id) then
		-- Say why nothing happens (Dev, 2026-10-30: new players swept locked leaves).
		if now - (runtime.LockedWarnAt or 0) > 6 then
			runtime.LockedWarnAt = now
			Net.fire("Notify", player, `These leaves are locked! Unlock {zone.Name or "this area"} first.`, "Bad")
		end
		return
	end

	sweepArea(player, session, position, tool.Radius, tool.Power, now)
end

-- Leaf Bomb (item): clears every leaf within `radius` of you at once, paid like sweeping.
function SweepService:Blast(player: Player, radius: number): (boolean, string?)
	local session = S.DataService:GetSession(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not session or not root then
		return false, "Still loading"
	end
	local zone = Grid.zoneAt(root.Position)
	if not zone or not S.ZoneService:IsUnlocked(player, zone.Id) then
		return false, "Stand in a leaf field to use it"
	end
	if S.BackpackService:IsFull(player) then
		return false, "Your bag is full! Sell first."
	end
	local tool = S.ToolService:GetSweepTool(player)
	-- Strong enough to clear any pile in one hit.
	local count = sweepArea(player, session, root.Position, radius, tool.Power, os.clock(), math.huge)
	if count == 0 then
		return false, "No leaves around you"
	end
	Net.fireAll("LeafBomb", root.Position, radius)
	return true, `BOOM! Leaf Bomb cleared {count} piles!`
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
