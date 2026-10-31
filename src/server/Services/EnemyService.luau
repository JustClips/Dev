--!strict
-- Enemies in the world (Config/Enemies): spawning, moving, health, defeat rewards and
-- respawning. The fighting itself (pet teams, hits, knock-outs) is CombatService.
--
-- Each enemy is one invisible anchored part (its spot and heading on the ground) in
-- workspace.Enemies, named by a short id, with attributes clients read:
--   Enemy (def id), Zone, Hp, MaxHp, Running, Fighting, Boss
-- Clients draw the real model on it, smooth its movement, and show its health bar and
-- damage numbers (EnemyController).
--
-- Dust bunnies (the first enemy) used to pop from one sweep; now pets fight them. They
-- still run from players until something hits them, then turn and fight back.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Combat = require(Shared.Combat)
local Enemies = require(Shared.Config.Enemies)
local Format = require(Shared.Format)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Upgrades = require(Shared.Config.Upgrades)
local Zones = require(Shared.Config.Zones)

local STEP = 0.1
local ANGRY_SECONDS = 3 -- after a hit, a Hopper fights back this long even with no pets on it
local FIGHT_GAP = 6 -- a fighting enemy closes in until its target is this close

export type Enemy = {
	name: string,
	def: Enemies.EnemyDef,
	zone: any,
	anchor: BasePart,
	alive: boolean,
	hp: number,
	maxHp: number,
	ground: number,
	position: Vector3,
	home: Vector3?,
	heading: Vector3,
	turnAt: number,
	phase: number,
	resting: boolean,
	lastHurt: number,
	angryAt: Player?,
	hurtBy: { [Player]: number },
	nextAttack: number,
}

local EnemyService = {}

local S: any
local folder: Folder
local rng = Random.new()
local enemies: { Enemy } = {}
local byName: { [string]: Enemy } = {}
local nextId = 0

local function flat(v: Vector3): Vector3
	return v * Vector3.new(1, 0, 1)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function setAttr(enemy: Enemy, name: string, value: any)
	if enemy.anchor:GetAttribute(name) ~= value then
		enemy.anchor:SetAttribute(name, value)
	end
end

local function build(def: Enemies.EnemyDef, zone: any, home: Vector3?): Enemy
	nextId += 1
	local name = "E" .. nextId
	local anchor = Instance.new("Part")
	anchor.Name = name
	anchor.Size = Vector3.new(3, 3, 3)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor:SetAttribute("Enemy", def.Id)
	anchor:SetAttribute("Zone", zone.Id)
	anchor:SetAttribute("Running", false)
	anchor:SetAttribute("Fighting", false)
	anchor:SetAttribute("Boss", def.Boss == true)
	local maxHp = Combat.enemyMaxHp(def, zone.Id)
	local enemy: Enemy = {
		name = name,
		def = def,
		zone = zone,
		anchor = anchor,
		alive = false,
		hp = maxHp,
		maxHp = maxHp,
		ground = 0,
		position = Vector3.zero,
		home = home,
		heading = Vector3.new(0, 0, -1),
		turnAt = 0,
		phase = rng:NextNumber(0, 6),
		resting = false,
		lastHurt = 0,
		angryAt = nil,
		hurtBy = {},
		nextAttack = 0,
	}
	byName[name] = enemy
	return enemy
end

local function draw(enemy: Enemy)
	local look = flat(enemy.heading)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	enemy.anchor.CFrame = CFrame.lookAt(enemy.position, enemy.position + look.Unit)
end

local function place(enemy: Enemy)
	local spot = enemy.home or S.DustService:GetRandomTilePosition(enemy.zone.Id, rng)
	if not spot then
		return
	end
	enemy.ground = spot.Y - 0.2
	enemy.position = Vector3.new(spot.X, enemy.ground, spot.Z)
	enemy.hp = enemy.maxHp
	enemy.alive = true
	enemy.lastHurt = 0
	enemy.angryAt = nil
	table.clear(enemy.hurtBy)
	enemy.anchor:SetAttribute("MaxHp", enemy.maxHp)
	enemy.anchor:SetAttribute("Hp", enemy.hp)
	enemy.anchor:SetAttribute("Fighting", false)
	draw(enemy)
	enemy.anchor.Parent = folder
end

local function clampToZone(enemy: Enemy, position: Vector3): Vector3
	local zone = enemy.zone
	local x = math.clamp(position.X, zone.Min.X + 4, zone.Max.X - 4)
	local z = math.clamp(position.Z, zone.Min.Y + 4, zone.Max.Y - 4)
	return Vector3.new(x, enemy.ground, z)
end

local function nearestPlayer(position: Vector3): (Vector3?, number)
	local best, bestDistance = nil, math.huge
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root then
			local d = flat(root.Position - position).Magnitude
			if d < bestDistance then
				best, bestDistance = root.Position, d
			end
		end
	end
	return best, bestDistance
end

-- Who it is fighting right now: players whose pets are on it, or whoever just hit it.
local function fightTarget(enemy: Enemy, now: number): Vector3?
	local best, bestDistance = nil, math.huge
	for _, player in S.CombatService:AttackersOf(enemy) do
		local root = rootOf(player)
		if root then
			local d = flat(root.Position - enemy.position).Magnitude
			if d < bestDistance then
				best, bestDistance = root.Position, d
			end
		end
	end
	if not best and enemy.angryAt and now - enemy.lastHurt < ANGRY_SECONDS then
		local root = rootOf(enemy.angryAt)
		best = root and root.Position
	end
	return best
end

local function move(enemy: Enemy, now: number)
	local def = enemy.def
	local _, distance = nearestPlayer(enemy.position)
	if distance > 160 then
		return -- nobody close enough to see it: don't spend replication on it
	end
	local speed = 0
	local target = fightTarget(enemy, now)
	setAttr(enemy, "Fighting", target ~= nil)
	if target then
		-- Fighting: face whoever is fighting it and close in, with little side hops.
		local toward = flat(target - enemy.position)
		if toward.Magnitude > 0.01 then
			enemy.heading = toward.Unit
		end
		if toward.Magnitude > FIGHT_GAP then
			speed = def.Speed * 0.5
		end
		enemy.resting = false
		enemy.turnAt = now + 1
	elseif def.Brain == "Guard" and enemy.home then
		local back = flat(enemy.home - enemy.position)
		if back.Magnitude > 2 then
			enemy.heading = back.Unit
			speed = def.Speed * 0.4
		end
	else
		local threat, near = nearestPlayer(enemy.position)
		if threat and def.FleeRadius and near < def.FleeRadius then
			local away = flat(enemy.position - threat)
			if away.Magnitude > 0.01 then
				-- Run away, with a little zig-zag so they're fun to chase.
				local side = Vector3.new(-away.Z, 0, away.X).Unit * math.sin(now * 3 + enemy.phase) * 0.6
				enemy.heading = (away.Unit + side).Unit
			end
			speed = def.Speed
			enemy.resting = false
			enemy.turnAt = now + 1
		else
			if now >= enemy.turnAt then
				-- Wander: hop off somewhere, or sit and sniff around for a bit.
				enemy.resting = rng:NextNumber() < 0.45
				if not enemy.resting then
					local a = rng:NextNumber(0, math.pi * 2)
					enemy.heading = Vector3.new(math.cos(a), 0, math.sin(a))
				end
				enemy.turnAt = now + (if enemy.resting then rng:NextNumber(2.5, 6) else rng:NextNumber(1.5, 4))
			end
			speed = if enemy.resting then 0 else def.Speed * 0.25
		end
	end
	local nextPosition = clampToZone(enemy, enemy.position + enemy.heading * speed * STEP)
	if speed > 0 and not target and (nextPosition - enemy.position).Magnitude < speed * STEP * 0.3 then
		-- Stuck on the zone edge: turn around.
		enemy.heading = -enemy.heading
		enemy.turnAt = now + 1
	end
	enemy.position = nextPosition
	setAttr(enemy, "Running", speed > def.Speed * 0.45)
	draw(enemy)
end

local function update(enemy: Enemy, now: number)
	if not enemy.alive then
		return
	end
	move(enemy, now)
	-- Attack the pets fighting it.
	if now >= enemy.nextAttack then
		if S.CombatService:EnemyAttack(enemy, Combat.enemyDamage(enemy.def, enemy.zone.Id), enemy.def.Targets) then
			enemy.nextAttack = now + enemy.def.AttackInterval
		else
			enemy.nextAttack = now + 0.3
		end
	end
	-- Left alone for a while: heal up and forget who hit it.
	if enemy.hp < enemy.maxHp and now - enemy.lastHurt > enemy.def.RegenDelay and #S.CombatService:AttackersOf(enemy) == 0 then
		enemy.hp = math.min(enemy.maxHp, enemy.hp + enemy.maxHp * 0.5 * STEP)
		if enemy.hp >= enemy.maxHp then
			table.clear(enemy.hurtBy)
		end
		setAttr(enemy, "Hp", enemy.hp)
	end
end

local function reward(player: Player, enemy: Enemy)
	local cfg = enemy.def.Rewards
	local zone = enemy.zone
	local name = enemy.def.Name
	local roll = rng:NextNumber()
	if roll < cfg.EggChance then
		local luck = S.BoostService:GetServerLuck() * S.BoostService:GetPersonalLuck(player)
		local rarity = S.EggService:RollRarity(zone.MaxRarity, luck)
		if S.InventoryService:AddEgg(player, rarity, zone.Id) then
			Net.fire("Notify", player, `The {name} dropped a {rarity} egg! It's in your bag.`, "Good")
			return
		end
	elseif roll < cfg.EggChance + cfg.PotionChance then
		local item = Items.rollItem(rng, cfg.PotionRarity)
		S.InventoryService:AddItem(player, item.Id, 1)
		Net.fire("Notify", player, `The {name} dropped a {item.Name}! It's in your bag.`, "Good")
		return
	end
	local earnings = S.AlienService:GetIncomePerSec(player) + S.BackpackService:GetEarnRate(player)
	local data = S.DataService:GetData(player)
	local cash = math.max(zone.CashMult * cfg.MinCashPerZoneMult, earnings * cfg.CashSeconds)
	if cfg.Upgrade then
		cash *= Upgrades.multiplier(data and data.Upgrades, cfg.Upgrade)
	end
	S.BackpackService:GiveCash(player, cash, enemy.def.Id)
	Net.fire("Notify", player, `You beat the {name}! +{Format.cash(cash)}`, "Good")
end

local function defeat(enemy: Enemy)
	enemy.alive = false
	enemy.anchor.Parent = nil
	Net.fireAll("BunnyPop", enemy.position + Vector3.new(0, 1.5, 0))
	S.CombatService:OnEnemyDefeated(enemy)
	-- Everyone who helped gets the full reward (friendly when you fight together).
	local stat = enemy.def.Rewards.Stat
	for player in enemy.hurtBy do
		if player.Parent then
			reward(player, enemy)
			local data = S.DataService:GetData(player)
			if data and stat then
				data.Stats[stat] = (data.Stats[stat] or 0) + 1
				S.QuestService:ZoneCount(player, enemy.zone.Id, stat, 1)
			end
		end
	end
	table.clear(enemy.hurtBy)
	task.delay(enemy.def.RespawnSeconds, function()
		place(enemy)
	end)
end

function EnemyService:Get(name: string): Enemy?
	local enemy = byName[name]
	return if enemy and enemy.alive then enemy else nil
end

-- The closest live enemy within `range` of a position.
function EnemyService:Nearest(position: Vector3, range: number): Enemy?
	local best, bestDistance = nil, range
	for _, enemy in enemies do
		if enemy.alive then
			local d = flat(enemy.position - position).Magnitude
			if d <= bestDistance then
				best, bestDistance = enemy, d
			end
		end
	end
	return best
end

function EnemyService:Distance(enemy: Enemy, position: Vector3): number
	return flat(enemy.position - position).Magnitude
end

-- Hurts an enemy. Returns true if this hit defeated it.
function EnemyService:Damage(enemy: Enemy, player: Player, amount: number): boolean
	if not enemy.alive or amount <= 0 then
		return false
	end
	enemy.hp -= amount
	enemy.hurtBy[player] = (enemy.hurtBy[player] or 0) + amount
	enemy.lastHurt = os.clock()
	enemy.angryAt = player
	if enemy.hp <= 0 then
		enemy.hp = 0
		enemy.anchor:SetAttribute("Hp", 0)
		defeat(enemy)
		return true
	end
	enemy.anchor:SetAttribute("Hp", enemy.hp)
	return false
end

-- A player's sweep circle hits the enemies in it (SweepService, every valid sweep). Bunny
-- Net (Lucky Lab) widens the circle for this. Also sends your pets at it.
local sweepHits: { [Player]: { [Enemy]: number } } = {}
function EnemyService:SweepHit(player: Player, position: Vector3, radius: number)
	local now = os.clock()
	local mine = sweepHits[player]
	if not mine then
		mine = setmetatable({}, { __mode = "k" }) :: any
		sweepHits[player] = mine
	end
	for _, enemy in enemies do
		if enemy.alive and flat(enemy.position - position).Magnitude <= radius + enemy.def.Radius + 0.5 then
			if now - (mine[enemy] or 0) >= Combat.SweepHitCooldown then
				mine[enemy] = now
				local damage = enemy.maxHp * enemy.def.SweepHit
				S.CombatService:AddHit({ E = enemy.name, U = player.UserId, S = 0, D = damage })
				S.CombatService:Engage(player, enemy, false)
				EnemyService:Damage(enemy, player, damage)
			end
		end
	end
end

-- How many enemies are alive (admin/debug).
function EnemyService:Count(): number
	local n = 0
	for _, enemy in enemies do
		if enemy.alive then
			n += 1
		end
	end
	return n
end

function EnemyService:Init(services)
	S = services
	folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = Workspace
	Players.PlayerRemoving:Connect(function(player)
		sweepHits[player] = nil
		for _, enemy in enemies do
			enemy.hurtBy[player] = nil
			if enemy.angryAt == player then
				enemy.angryAt = nil
			end
		end
	end)
end

function EnemyService:Start()
	for _, def in Enemies.List do
		if def.PerZone then
			for _, zone in Zones.List do
				for _ = 1, def.PerZone do
					local enemy = build(def, zone, nil)
					place(enemy)
					table.insert(enemies, enemy)
				end
			end
		end
		for _, point in def.Points or {} do
			local zone = Zones.ById[point.Zone]
			if zone then
				local enemy = build(def, zone, point.Position)
				place(enemy)
				table.insert(enemies, enemy)
			end
		end
	end
	task.spawn(function()
		while true do
			task.wait(STEP)
			local now = os.clock()
			for _, enemy in enemies do
				update(enemy, now)
			end
		end
	end)
end

return EnemyService
