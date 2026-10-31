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
local Assets = require(script.Parent.Config.Assets)
local Enemies = require(script.Parent.Config.Enemies)
local Format = require(script.Parent.Format)
local Upgrades = require(script.Parent.Config.Upgrades)

local Combat = {
	FighterCount = 3, -- the pets that follow you (your top 3 placed pets) are your fighters
	PetAttackInterval = 1, -- base seconds between a pet's hits (each pet has its own, petAttack)
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

-- Attack styles (Dev, 2026-10-31: every pet animates its attack and has its own rate and
-- damage). The client plays the move (FollowerController); Impact is when in the move it
-- lands, so damage numbers show at that moment. Dps = damage per second vs. pet power.
--   Pounce: crouch, hop forward and slam down (most ground pets)
--   Bite: two quick nips (small pets: fast, weaker hits)
--   Charge: back up and ram (big pets: slow, heavy hits)
--   Dive: rise up and sting-dive at the enemy (flyers and floaters)
export type AttackStyle = { Name: string, Rate: number, Dps: number, Duration: number, Impact: number }
Combat.Styles = {
	Pounce = { Name = "Pounce", Rate = 1.1, Dps = 1, Duration = 0.42, Impact = 0.26 },
	Bite = { Name = "Bite", Rate = 0.7, Dps = 0.95, Duration = 0.28, Impact = 0.1 },
	Charge = { Name = "Charge", Rate = 1.6, Dps = 1.08, Duration = 0.55, Impact = 0.36 },
	Dive = { Name = "Dive", Rate = 1.3, Dps = 1.04, Duration = 0.6, Impact = 0.38 },
} :: { [string]: AttackStyle }

-- A small stable number from a pet id (0-1), so every pet gets its own rate and damage.
local function hash(text: string, salt: number): number
	local h = salt
	for i = 1, #text do
		h = (h * 31 + string.byte(text, i)) % 1000003
	end
	return (h % 1000) / 999
end

export type PetAttack = { Style: string, Rate: number, DamageMult: number }
local attackCache: { [string]: PetAttack } = {}

-- A pet kind's attack: style, seconds between hits and damage per hit as a multiple of its
-- power. A pet can set its own in Config/Aliens (Attack = { Style, Rate, Damage }); the rest
-- get one from their look (flyers dive, small pets bite, big pets charge) with a rate and
-- damage of their own. Faster pets hit softer, so damage per second stays fair.
function Combat.petAttack(alienId: string): PetAttack
	local cached = attackCache[alienId]
	if cached then
		return cached
	end
	local def = Aliens.ById[alienId] :: any
	local custom = def and def.Attack
	local meta = (Assets.Models :: any)["Alien_" .. alienId]
	local size = def and def.Size or 2
	local style = if custom and custom.Style
		then custom.Style
		elseif meta and meta.float then "Dive"
		elseif size >= 3 then "Charge"
		elseif size <= 1.7 then "Bite"
		else "Pounce"
	local s = Combat.Styles[style] or Combat.Styles.Pounce
	local rate = if custom and custom.Rate then custom.Rate else s.Rate * (0.85 + 0.3 * hash(alienId, 7))
	local dps = s.Dps * (0.94 + 0.12 * hash(alienId, 13))
	local attack = {
		Style = s.Name,
		Rate = rate,
		DamageMult = if custom and custom.Damage then custom.Damage else dps * rate,
	}
	attackCache[alienId] = attack
	return attack
end

-- Damage of one hit.
function Combat.petDamage(pet: any, levels: { [string]: number }?): number
	return Combat.petPower(pet) * Combat.petAttack(pet.Id).DamageMult * Upgrades.multiplier(levels, "PetDamage")
end

-- "Pounce · 12 dmg / 1.1s" for hover cards.
function Combat.describeAttack(pet: any): string
	local attack = Combat.petAttack(pet.Id)
	local damage = Combat.petPower(pet) * attack.DamageMult
	return `{attack.Style} · {Format.number(damage)} dmg / {string.format("%.1f", attack.Rate)}s`
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
