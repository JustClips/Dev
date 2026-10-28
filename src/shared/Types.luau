--!strict
-- Shared type definitions for configs, saved data and replicated state.

export type BigNum = { m: number, e: number }

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Cosmic"
export type Mutation = "Golden" | "Rainbow" | "MoonDusted"

export type ToolDef = {
	Tier: number,
	Id: string,
	Name: string,
	Radius: number,
	Power: number,
	Capacity: number,
	Price: number,
	IsVehicle: boolean,
	Color: Color3,
	Scale: number, -- placeholder model size
}

export type VehicleDef = {
	Order: number,
	Id: string,
	Name: string,
	Radius: number,
	Power: number,
	Capacity: number,
	Price: number,
	RequiredRebirths: number,
	Color: Color3,
	Scale: number,
	Speed: number,
	RentKey: string, -- Robux "this run" rental product
	UnlockKey: string, -- Robux unlock product (until rebirth, like cash)
}

export type UpgradeDef = {
	Id: string,
	Name: string,
	Icon: string,
	MaxLevel: number,
	BaseCost: number,
	CostGrowth: number,
	PerLevel: number, -- effect per level (see Config/Upgrades)
	Format: string, -- how the effect is shown: "percent" or "plus"
	Description: string,
}

export type Exclusion = { Center: Vector2, Radius: number }

export type ZoneDef = {
	Id: string,
	Name: string,
	Planet: string,
	IsMoon: boolean,
	UnlockCost: number,
	RequiredRebirths: number,
	Min: Vector2, -- XZ corner
	Max: Vector2,
	GroundY: number,
	TileSize: number,
	DustHP: number,
	DustPerTile: number, -- backpack units per cleared tile, multiplied by tool power
	CashMult: number, -- cash per dust unit when sold
	EggChance: number,
	MaxRarity: Rarity,
	RegrowSeconds: number,
	DustColor: Color3,
	-- What lies on the ground: tiles pick a colour from DustPalette (leaves, litter, snow...).
	DustMaterial: Enum.Material?,
	DustPalette: { Color3 }?,
	Exclusions: { Exclusion },
}

export type AlienDef = {
	Id: string,
	Name: string,
	Rarity: Rarity,
	Income: number,
	Color: Color3,
	Size: number,
	Zone: string?, -- the zone whose eggs hatch it (nil = Landing)
	Base: string?, -- zone variants: the Landing alien whose model they remix
}

export type RarityDef = {
	Name: Rarity,
	Order: number,
	Weight: number,
	HatchSeconds: number,
	Color: Color3,
}

export type MutationDef = {
	Name: Mutation,
	Label: string,
	Chance: number, -- 1 in N
	IncomeMult: number,
	Color: Color3,
}

export type ProductKind =
	"StarterPack"
	| "ServerLuck"
	| "SkipHatch"
	| "ToolSkip"
	| "VehicleRental"
	| "VehicleUnlock"
	| "CashPack"
	| "EggPack"
	| "SkipRebirth"
	| "DoubleOffline"
	| "MeteorShower"
	| "GiftPass"

export type ProductDef = {
	Key: string,
	Id: number,
	Price: number,
	Name: string,
	Kind: ProductKind,
	Category: string,
	Giftable: boolean,
	-- optional parameters, depending on Kind
	Mult: number?,
	Minutes: number?,
	Rarity: Rarity?,
	Tier: number?,
	Vehicle: string?,
	Count: number?,
	Seconds: number?,
	FloorFactor: number?,
	Rebirth: number?,
	Pass: string?,
}

export type GamepassDef = {
	Key: string,
	Id: number,
	Price: number,
	Name: string,
	Description: string,
}

-- A pet you own. Placed pets live in your pet park and earn cash; the rest wait in
-- your inventory. Keyed by a uid string ("p12") in ProfileData.Pets.
export type PetInstance = {
	Id: string,
	Mutation: Mutation?,
	Huge: boolean?,
	Placed: boolean?,
	Weight: number?, -- kg (Config/Weights); nil on pets from before weights = average
}

-- An unhatched egg in your inventory, keyed by uid ("e7") in ProfileData.Eggs.
export type EggInstance = {
	Rarity: Rarity,
	Zone: string, -- where it was found: decides which pets it can hatch
	Weight: number?, -- kg; bigger eggs hatch heavier pets (Config/Weights)
	Size: string?, -- size class: Normal, Big, Heavy, Giant, Colossal
}

-- An egg placed in an incubator on your base. Ready to open once EndsAt has passed.
export type HatchEntry = {
	Uid: string,
	Rarity: Rarity,
	Zone: string,
	Spot: number, -- legacy incubator spot (eggs placed before free placement)
	X: number?, -- where the egg sits in the pet park (base local studs)
	Z: number?,
	Weight: number?,
	Size: string?,
	StartsAt: number?, -- when it was put down (the egg grows from then until EndsAt)
	EndsAt: number,
}

export type ProfileData = {
	Version: number,
	Cash: BigNum,
	TotalDust: BigNum,
	Rebirths: number,
	Backpack: number,
	BackpackValue: number,
	ToolTier: number,
	OwnedTools: { [number]: boolean },
	Vehicles: { [string]: boolean },
	Upgrades: { [string]: number },
	ZonesUnlocked: { [string]: boolean },
	Pets: { [string]: PetInstance },
	Eggs: { [string]: EggInstance },
	Items: { [string]: number },
	NextUid: number,
	Hatching: { HatchEntry },
	Index: { [string]: boolean },
	Boosts: { [string]: number },
	Gamepasses: { [string]: boolean },
	-- Passes a friend gifted (gift products); count as owned for good.
	GiftedPasses: { [string]: boolean },
	Daily: { Streak: number, LastDay: number },
	ReceiptsGranted: { [string]: string },
	ReceiptOrder: { string },
	LastOnline: number,
	Flags: { [string]: any },
	Stats: { [string]: number },
	Settings: { [string]: any },
}

-- What the server sends to the owning client (see StateService).
export type PlayerSnapshot = {
	Cash: BigNum,
	Backpack: number,
	Capacity: number,
	ToolTier: number,
	EffectiveTier: number,
	Vehicles: { [string]: boolean },
	RentedVehicle: string?,
	BestVehicle: string?,
	InVehicle: boolean,
	Upgrades: { [string]: number },
	WalkSpeed: number,
	Rebirths: number,
	RebirthCost: BigNum,
	ZonesUnlocked: { [string]: boolean },
	-- Inventory tables are only sent when they change (InvVersion); the client keeps the
	-- last copy otherwise (State.luau).
	InvVersion: number,
	Pets: { [string]: PetInstance }?,
	Eggs: { [string]: EggInstance }?,
	Items: { [string]: number }?,
	Hatching: { HatchEntry },
	Incubators: number,
	PetBagSize: number,
	EggBagSize: number,
	PlacedCount: number,
	Index: { [string]: boolean },
	Boosts: { [string]: number },
	Gamepasses: { [string]: boolean },
	Daily: { Streak: number, LastDay: number },
	-- RewardService:Snapshot (daily card, session playtime, stay offer, group, event)
	Rewards: { [string]: any }?,
	Flags: { [string]: any },
	Stats: { [string]: number },
	Slots: number,
	IncomePerSec: number,
	CashPacks: { [string]: number },
	CashMultiplier: number,
	CarriedEggs: { Rarity },
	CarryLimit: number,
	BaseIndex: number,
	TutorialStep: string,
	TutorialTarget: Vector3?,
	AutoSweep: boolean,
	Settings: { Music: number?, Sfx: number? },
	ServerTime: number,
}

return {}
