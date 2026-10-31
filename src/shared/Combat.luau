--!strict
-- Pet combat numbers, shared by the server (CombatService, EnemyService) and clients
-- (health bars, damage numbers).
--
-- A pet's power is its income (Aliens.income: rarity, zone set, weight, mutation, Huge), so
-- every pet that earns more also hits harder and takes more hits, with no extra table to
-- keep in step. Damage per hit = power x the PetDamage stat (tree / passives can add it
-- later). Max health = power x PetHpPerPower.
--
-- Enemies scale by zone with zonePower (average Common pet income of that zone, Backyard
-- = 1), so they keep pace with the pets each zone hatches.
local Aliens = require(script.Parent.Config.Aliens)
local Enemies = require(script.Parent.Config.Enemies)
local Upgrades = require(script.Parent.Config.Upgrades)

local Combat = {
	FighterCount = 3, -- the pets that follow you (your top 3 placed pets) are your fighters
	PetAttackInterval = 1, -- seconds between a pet's hits
	PetFirstHitDelay = 0.6, -- time to run over before the first hit
	PetHpPerPower = 12,
	CritChance = 0.1,
	CritMult = 2,
	SleepSeconds = 10, -- a knocked-out pet sleeps this long, then wakes up with full health
	RegenDelay = 4, -- out of a fight this long: pets heal
	RegenPerSecond = 0.35, -- share of max health healed per second
	EngageRange = 18, -- an enemy this close to you: your pets go for it
	TapRange = 55, -- tap an enemy up to this far away to send your pets (under LeashRange)
	LeashRange = 60, -- walk further than this from the enemy and your pets come back
	SweepHitCooldown = 0.4, -- per player per enemy
	TickSeconds = 0.2,
}

local zonePowerCache: { [string]: number } = {}

-- How strong a zone's pets are compared with the Backyard (average Common income).
function Combat.zonePower(zoneId: string?): number
	local key = zoneId or "Landing"
	local cached = zonePowerCache[key]
	if cached then
		return cached
	end
	local function avg(zone: string): number
		local pool = Aliens.Pools[zone]
		local list = pool and pool.Common
		if not list or #list == 0 then
			return 0
		end
		local sum = 0
		for _, def in list do
			sum += def.Income
		end
		return sum / #list
	end
	local base = avg("Landing")
	local here = avg(key)
	local power = if base > 0 and here > 0 then here / base else 1
	zonePowerCache[key] = power
	return power
end

function Combat.petPower(pet: { Id: string, Mutation: string?, Huge: boolean?, Weight: number? }): number
	return math.max(Aliens.income(pet), 0.5)
end

function Combat.petDamage(pet: any, levels: { [string]: number }?): number
	return Combat.petPower(pet) * Upgrades.multiplier(levels, "PetDamage")
end

function Combat.petMaxHp(pet: any, levels: { [string]: number }?): number
	return Combat.petPower(pet) * Combat.PetHpPerPower * Upgrades.multiplier(levels, "PetHealth")
end

function Combat.enemyMaxHp(def: Enemies.EnemyDef, zoneId: string?): number
	return def.Hp * Combat.zonePower(zoneId)
end

function Combat.enemyDamage(def: Enemies.EnemyDef, zoneId: string?): number
	return def.Damage * Combat.zonePower(zoneId)
end

return Combat
