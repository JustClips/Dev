--!strict
-- Enemies your pets fight (Dev, 2026-10-31: "a full scalable system"). Each entry is one
-- kind of enemy; EnemyService spawns and moves them, CombatService runs the fights and
-- EnemyController draws them (model, health bar, damage numbers).
--
-- Numbers are for the Backyard. In other zones Hp and Damage are multiplied by the zone's
-- pet power (shared/Combat.zonePower: how strong that zone's Common pets are), so a team
-- of pets from a zone fights that zone's enemies about as well as Backyard pets fight
-- Backyard enemies.
--
-- Adding a boss later: add an entry with Brain = "Guard", Points = { ... } (fixed spawn
-- spots) instead of PerZone, a big Hp, Targets > 1 (hits several pets per attack), Boss =
-- true (big health bar) and its own Rewards. Nothing else needs to change.

export type EnemyRewards = {
	CashSeconds: number, -- cash = this many seconds of your earnings (pets + sweeping)
	MinCashPerZoneMult: number, -- floor: zone cash mult x this
	PotionChance: number,
	PotionRarity: string, -- Items.rollItem rarity
	EggChance: number, -- an egg from that zone (rarity rolled with your luck)
	Upgrade: string?, -- Upgrades stat that multiplies the cash ("Bunny" = Bunny Rewards)
	Stat: string?, -- data.Stats counter and quest kind to count (+1 per defeat)
}

export type EnemyDef = {
	Id: string,
	Name: string,
	Model: string, -- AssetLibrary model (a real modelled mesh), anims <Model>_Idle/_Walk/_Run
	Scale: number?,
	Brain: string, -- "Hopper": wanders, runs from players until it is hit, then fights back.
	-- "Guard": stays near its spawn spot and fights anyone who comes close (bosses).
	Hp: number,
	Damage: number, -- per attack, to one pet (x zone power)
	AttackInterval: number, -- seconds between its attacks
	Targets: number, -- pets hit per attack
	Radius: number, -- how wide it is: pets stand this far + a bit from its middle
	BarHeight: number, -- studs above its feet for the health bar
	SweepHit: number, -- one sweep hit from a player takes this share of its max Hp
	Speed: number, -- running speed (studs/s)
	FleeRadius: number?, -- Hopper: players closer than this scare it (while not fighting)
	RegenDelay: number, -- no damage for this long: it heals back up and forgets attackers
	RespawnSeconds: number,
	PerZone: number?, -- spawn this many in every zone (or use Points)
	Points: { { Zone: string, Position: Vector3 } }?,
	Boss: boolean?,
	Rewards: EnemyRewards,
}

local Economy = require(script.Parent.Economy)

local Bunny = Economy.Bunnies

local List: { EnemyDef } = {
	{
		Id = "DustBunny",
		Name = "Dust Bunny",
		Model = "Mob_DustBunny",
		Brain = "Hopper",
		Hp = 45,
		Damage = 5,
		AttackInterval = 1.5,
		Targets = 1,
		Radius = 2.2,
		BarHeight = 7,
		SweepHit = 0.06,
		Speed = Bunny.Speed,
		FleeRadius = Bunny.FleeRadius,
		RegenDelay = 6,
		RespawnSeconds = Bunny.RespawnSeconds,
		PerZone = Bunny.PerZone,
		Rewards = {
			CashSeconds = Bunny.CashSeconds,
			MinCashPerZoneMult = Bunny.MinCashPerZoneMult,
			PotionChance = Bunny.PotionChance,
			PotionRarity = "Uncommon",
			EggChance = Bunny.EggChance,
			Upgrade = "Bunny",
			Stat = "Bunnies",
		},
	},
}

local Enemies = {
	List = List,
	ById = {} :: { [string]: EnemyDef },
}

for _, def in List do
	Enemies.ById[def.Id] = def
end

return Enemies
