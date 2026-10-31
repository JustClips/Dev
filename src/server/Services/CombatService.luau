--!strict
-- Pet combat. The pets that follow you (your top 3 placed pets, AlienService) are your
-- team. Walk up to an enemy (or tap one) and they run over and hit it; it hits them
-- back. A pet at 0 health is knocked out and sleeps for Combat.SleepSeconds, then wakes
-- up with full health. Out of a fight, pets heal.
--
-- What clients see (all players, so everyone sees everyone's fights):
--   player attribute CombatTarget = enemy part name ("" = not fighting)
--   player attribute PetHp = "1,0.42,0" health share per follower slot
--   player attribute PetSleep = "0,0,1730390000.5" server time each slot wakes up (0 = awake)
--   CombatHits event, once per tick: every hit this tick, see shared/Combat for fields:
--     { E = enemy name, U = attacker/owner UserId, S = pet slot (0 = player sweep),
--       D = damage, C = crit?, P = true when an enemy hit a pet, K = pet knocked out? }
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Combat = require(Shared.Combat)
local Net = require(Shared.Net)

type Fighter = {
	uid: string,
	pet: any,
	hp: number,
	maxHp: number,
	sleepUntil: number, -- os.clock(); 0 = awake
	nextHit: number,
}

type Team = {
	fighters: { Fighter },
	target: any?, -- EnemyService enemy
	lastFight: number,
	sentHp: string,
	sentSleep: string,
}

local CombatService = {}

local S: any
local rng = Random.new()
local teams: { [Player]: Team } = {}
local hits: { any } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function awake(fighter: Fighter): boolean
	return fighter.sleepUntil == 0
end

local function anyAwake(team: Team): boolean
	for _, fighter in team.fighters do
		if awake(fighter) then
			return true
		end
	end
	return false
end

local function publish(player: Player, team: Team)
	local hp, sleep = {}, {}
	local clock, serverNow = os.clock(), Workspace:GetServerTimeNow()
	for i, fighter in team.fighters do
		hp[i] = string.format("%.2f", math.clamp(fighter.hp / fighter.maxHp, 0, 1))
		sleep[i] = if fighter.sleepUntil > 0 then string.format("%.1f", serverNow + (fighter.sleepUntil - clock)) else "0"
	end
	local hpText, sleepText = table.concat(hp, ","), table.concat(sleep, ",")
	if hpText ~= team.sentHp then
		team.sentHp = hpText
		player:SetAttribute("PetHp", hpText)
	end
	if sleepText ~= team.sentSleep then
		team.sentSleep = sleepText
		player:SetAttribute("PetSleep", sleepText)
	end
	local targetName = if team.target then team.target.name else ""
	if player:GetAttribute("CombatTarget") ~= targetName then
		player:SetAttribute("CombatTarget", targetName)
	end
end

-- AlienService: the follower pets changed (placed / picked up / rebirth...). Pets that
-- stay keep their health and sleep.
function CombatService:SetTeam(player: Player, list: { { uid: string, pet: any } })
	local data = S.DataService:GetData(player)
	local levels = data and data.Upgrades
	local team = teams[player]
	local old: { [string]: Fighter } = {}
	if team then
		for _, fighter in team.fighters do
			old[fighter.uid] = fighter
		end
	else
		team = { fighters = {}, target = nil, lastFight = 0, sentHp = "", sentSleep = "" }
		teams[player] = team
	end
	local t = team :: Team
	local fighters = {}
	for i, entry in list do
		local maxHp = Combat.petMaxHp(entry.pet, levels)
		local was = old[entry.uid]
		if was then
			-- Same pet: keep its health share (max can change with a new mutation).
			was.hp = math.min(maxHp, was.hp / was.maxHp * maxHp)
			was.maxHp = maxHp
			was.pet = entry.pet
			fighters[i] = was
		else
			fighters[i] = { uid = entry.uid, pet = entry.pet, hp = maxHp, maxHp = maxHp, sleepUntil = 0, nextHit = 0 }
		end
	end
	t.fighters = fighters
	if #fighters == 0 then
		t.target = nil
	end
	publish(player, t)
end

-- Sends a player's pets at an enemy. `switch`: also when they're already on another one.
function CombatService:Engage(player: Player, enemy: any, switch: boolean)
	local team = teams[player]
	if not team or #team.fighters == 0 or not anyAwake(team) then
		return
	end
	if team.target == enemy or (team.target and not switch) then
		return
	end
	team.target = enemy
	local now = os.clock()
	for i, fighter in team.fighters do
		fighter.nextHit = now + Combat.PetFirstHitDelay + (i - 1) * 0.25
	end
	publish(player, team)
end

-- Players whose pets are on this enemy.
function CombatService:AttackersOf(enemy: any): { Player }
	local list = {}
	for player, team in teams do
		if team.target == enemy then
			table.insert(list, player)
		end
	end
	return list
end

function CombatService:AddHit(hit: any)
	table.insert(hits, hit)
end

-- The enemy attacks: hits up to `count` awake pets among the teams fighting it. Returns
-- false when there was nothing to hit.
function CombatService:EnemyAttack(enemy: any, damage: number, count: number): boolean
	local pool = {}
	for player, team in teams do
		if team.target == enemy then
			for slot, fighter in team.fighters do
				if awake(fighter) then
					table.insert(pool, { player = player, team = team, slot = slot, fighter = fighter })
				end
			end
		end
	end
	if #pool == 0 then
		return false
	end
	local now = os.clock()
	for _ = 1, math.min(count, #pool) do
		local pick = table.remove(pool, rng:NextInteger(1, #pool))
		local fighter = pick.fighter
		fighter.hp -= damage
		local knocked = fighter.hp <= 0
		if knocked then
			fighter.hp = 0
			fighter.sleepUntil = now + Combat.SleepSeconds
		end
		pick.team.lastFight = now
		table.insert(hits, { E = enemy.name, U = pick.player.UserId, S = pick.slot, D = damage, P = true, K = knocked or nil })
		if knocked and not anyAwake(pick.team) then
			pick.team.target = nil -- everyone's asleep: the fight is over for this player
		end
		publish(pick.player, pick.team)
	end
	return true
end

function CombatService:OnEnemyDefeated(enemy: any)
	for player, team in teams do
		if team.target == enemy then
			team.target = nil
			publish(player, team)
		end
	end
end

local function tick()
	local now = os.clock()
	for player, team in teams do
		-- Wake up sleepers.
		for _, fighter in team.fighters do
			if fighter.sleepUntil > 0 and now >= fighter.sleepUntil then
				fighter.sleepUntil = 0
				fighter.hp = fighter.maxHp
			end
		end
		local root = rootOf(player)
		local target = team.target
		if target then
			if
				not root
				or not S.EnemyService:Get(target.name)
				or S.EnemyService:Distance(target, root.Position) > Combat.LeashRange
				or not anyAwake(team)
			then
				team.target = nil
				target = nil
			end
		end
		if not target and root and #team.fighters > 0 and anyAwake(team) then
			local near = S.EnemyService:Nearest(root.Position, Combat.EngageRange)
			if near then
				CombatService:Engage(player, near, false)
				target = team.target
			end
		end
		if target then
			team.lastFight = now
			local data = S.DataService:GetData(player)
			local levels = data and data.Upgrades
			for slot, fighter in team.fighters do
				if awake(fighter) and now >= fighter.nextHit and team.target == target then
					fighter.nextHit = now + Combat.petAttack(fighter.pet.Id).Rate
					local damage = Combat.petDamage(fighter.pet, levels)
					local crit = rng:NextNumber() < Combat.CritChance
					if crit then
						damage *= Combat.CritMult
					end
					table.insert(hits, { E = target.name, U = player.UserId, S = slot, D = damage, C = crit or nil })
					if S.EnemyService:Damage(target, player, damage) then
						break -- defeated: OnEnemyDefeated cleared the target
					end
				end
			end
		elseif now - team.lastFight > Combat.RegenDelay then
			for _, fighter in team.fighters do
				if awake(fighter) and fighter.hp < fighter.maxHp then
					fighter.hp = math.min(fighter.maxHp, fighter.hp + fighter.maxHp * Combat.RegenPerSecond * Combat.TickSeconds)
				end
			end
		end
		publish(player, team)
	end
	if #hits > 0 then
		Net.fireAll("CombatHits", hits)
		hits = {}
	end
end

function CombatService:Init(services)
	S = services
	Players.PlayerRemoving:Connect(function(player)
		teams[player] = nil
	end)
	S.DataService.ProfileReleasing:Connect(function(player)
		teams[player] = nil
	end)
end

function CombatService:Start()
	-- Tap an enemy: your pets switch to it.
	Net.onEvent("PetAttack", function(player: Player, name: any)
		if type(name) ~= "string" then
			return
		end
		local enemy = S.EnemyService:Get(name)
		local root = rootOf(player)
		if enemy and root and S.EnemyService:Distance(enemy, root.Position) <= Combat.TapRange then
			CombatService:Engage(player, enemy, true)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Combat.TickSeconds)
			tick()
		end
	end)
end

return CombatService
