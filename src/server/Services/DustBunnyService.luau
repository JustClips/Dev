--!strict
-- Dust bunnies: little fluff balls that hop around every zone and run from players.
-- Sweep one (it's inside your tool's reach) to pop it: you get cash (some seconds of your
-- earnings), sometimes a potion, rarely an egg from that zone. They come back later.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Upgrades = require(Shared.Config.Upgrades)
local Zones = require(Shared.Config.Zones)

local STEP = 0.1

-- Each bunny is one invisible anchored part (its spot and heading on the ground) plus a
-- Running attribute. Clients draw the voxel bunny on it, smooth its movement and play
-- its hop animations (DustBunnyController).
type Bunny = {
	model: BasePart,
	zone: any,
	ground: number,
	position: Vector3,
	heading: Vector3,
	turnAt: number,
	phase: number,
	resting: boolean,
}

local DustBunnyService = {}

local S: any
local folder: Folder
local rng = Random.new()
local bunnies: { Bunny } = {}

local function build(zone): Bunny
	local anchor = Instance.new("Part")
	anchor.Name = "DustBunny"
	anchor.Size = Vector3.new(3, 3, 3)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor:SetAttribute("Zone", zone.Id)
	anchor:SetAttribute("Running", false)
	anchor.Parent = folder
	return {
		model = anchor,
		zone = zone,
		ground = 0,
		position = Vector3.zero,
		heading = Vector3.new(0, 0, -1),
		turnAt = 0,
		phase = rng:NextNumber(0, 6),
		resting = false,
	}
end

local function draw(bunny: Bunny)
	local look = Vector3.new(bunny.heading.X, 0, bunny.heading.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	bunny.model.CFrame = CFrame.lookAt(bunny.position, bunny.position + look.Unit)
end

local function place(bunny: Bunny)
	local spot = S.DustService:GetRandomTilePosition(bunny.zone.Id, rng)
	if not spot then
		return
	end
	bunny.ground = spot.Y - 0.2
	bunny.position = Vector3.new(spot.X, bunny.ground, spot.Z)
	draw(bunny)
	bunny.model.Parent = folder
end

local function clampToZone(bunny: Bunny, position: Vector3): Vector3
	local zone = bunny.zone
	local x = math.clamp(position.X, zone.Min.X + 4, zone.Max.X - 4)
	local z = math.clamp(position.Z, zone.Min.Y + 4, zone.Max.Y - 4)
	return Vector3.new(x, bunny.ground, z)
end

local function nearestPlayer(position: Vector3): (Vector3?, number)
	local best, bestDistance = nil, math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local d = ((root.Position - position) * Vector3.new(1, 0, 1)).Magnitude
			if d < bestDistance then
				best, bestDistance = root.Position, d
			end
		end
	end
	return best, bestDistance
end

local function update(bunny: Bunny, now: number)
	if bunny.model.Parent == nil then
		return
	end
	local cfg = Economy.Bunnies
	local threat, distance = nearestPlayer(bunny.position)
	if distance > 160 then
		return -- nobody close enough to see it: don't spend replication on it
	end
	local speed = 0
	if threat and distance < cfg.FleeRadius then
		local away = (bunny.position - threat) * Vector3.new(1, 0, 1)
		if away.Magnitude > 0.01 then
			-- Run away, with a little zig-zag so they're fun to chase.
			local side = Vector3.new(-away.Z, 0, away.X).Unit * math.sin(now * 3 + bunny.phase) * 0.6
			bunny.heading = (away.Unit + side).Unit
		end
		speed = cfg.Speed
		bunny.resting = false
		bunny.turnAt = now + 1
	else
		if now >= bunny.turnAt then
			-- Wander: hop off somewhere, or sit and sniff around for a bit.
			bunny.resting = rng:NextNumber() < 0.45
			if not bunny.resting then
				local a = rng:NextNumber(0, math.pi * 2)
				bunny.heading = Vector3.new(math.cos(a), 0, math.sin(a))
			end
			bunny.turnAt = now + (if bunny.resting then rng:NextNumber(2.5, 6) else rng:NextNumber(1.5, 4))
		end
		speed = if bunny.resting then 0 else cfg.Speed * 0.25
	end
	local nextPosition = clampToZone(bunny, bunny.position + bunny.heading * speed * STEP)
	if speed > 0 and (nextPosition - bunny.position).Magnitude < speed * STEP * 0.3 then
		-- Stuck on the zone edge: turn around.
		bunny.heading = -bunny.heading
		bunny.turnAt = now + 1
	end
	bunny.position = nextPosition
	local running = speed > cfg.Speed * 0.5
	if bunny.model:GetAttribute("Running") ~= running then
		bunny.model:SetAttribute("Running", running)
	end
	draw(bunny)
end

local function reward(player: Player, bunny: Bunny)
	local cfg = Economy.Bunnies
	local zone = bunny.zone
	local roll = rng:NextNumber()
	if roll < cfg.EggChance then
		local luck = S.BoostService:GetServerLuck() * S.BoostService:GetPersonalLuck(player)
		local rarity = S.EggService:RollRarity(zone.MaxRarity, luck)
		if S.InventoryService:AddEgg(player, rarity, zone.Id) then
			Net.fire("Notify", player, `The Dust Bunny dropped a {rarity} egg! It's in your bag.`, "Good")
			return
		end
	elseif roll < cfg.EggChance + cfg.PotionChance then
		local item = Items.rollItem(rng, "Uncommon")
		S.InventoryService:AddItem(player, item.Id, 1)
		Net.fire("Notify", player, `The Dust Bunny dropped a {item.Name}! It's in your bag.`, "Good")
		return
	end
	local earnings = S.AlienService:GetIncomePerSec(player) + S.BackpackService:GetEarnRate(player)
	local data = S.DataService:GetData(player)
	local cash = math.max(zone.CashMult * cfg.MinCashPerZoneMult, earnings * cfg.CashSeconds)
		* Upgrades.multiplier(data and data.Upgrades, "Bunny")
	S.BackpackService:GiveCash(player, cash, "DustBunny")
	Net.fire("Notify", player, `You caught a Dust Bunny! +{Format.cash(cash)}`, "Good")
end

-- Called by SweepService for every valid sweep: pops a bunny inside the sweep circle.
function DustBunnyService:TryCatch(player: Player, position: Vector3, radius: number): boolean
	for _, bunny in bunnies do
		if bunny.model.Parent ~= nil then
			local d = ((bunny.position - position) * Vector3.new(1, 0, 1)).Magnitude
			if d <= radius + Economy.Bunnies.CatchSlack then
				bunny.model.Parent = nil
				Net.fireAll("BunnyPop", bunny.position + Vector3.new(0, 1.5, 0))
				reward(player, bunny)
				local data = S.DataService:GetData(player)
				if data then
					data.Stats.Bunnies = (data.Stats.Bunnies or 0) + 1
				end
				task.delay(Economy.Bunnies.RespawnSeconds, function()
					place(bunny)
				end)
				return true
			end
		end
	end
	return false
end

function DustBunnyService:Count(): number
	local n = 0
	for _, bunny in bunnies do
		if bunny.model.Parent ~= nil then
			n += 1
		end
	end
	return n
end

function DustBunnyService:Init(services)
	S = services
	folder = Instance.new("Folder")
	folder.Name = "DustBunnies"
	folder.Parent = Workspace
end

function DustBunnyService:Start()
	for _, zone in Zones.List do
		for _ = 1, Economy.Bunnies.PerZone do
			local bunny = build(zone)
			place(bunny)
			table.insert(bunnies, bunny)
		end
	end
	task.spawn(function()
		while true do
			task.wait(STEP)
			local now = os.clock()
			for _, bunny in bunnies do
				update(bunny, now)
			end
		end
	end)
end

return DustBunnyService
