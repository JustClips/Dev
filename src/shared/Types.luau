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
	Exclusions: { Exclusion },
}

export type AlienDef = {
	Id: string,
	Name: string,
	Rarity: Rarity,
	Income: number,
	Color: Color3,
	Size: number,
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
}

export type GamepassDef = {
	Key: string,
	Id: number,
	Price: number,
	Name: string,
	Description: string,
}

export type AlienInstance = {
	Id: string,
	Mutation: Mutation?,
	Slot: number,
}

export type HatchEntry = {
	EggRarity: Rarity,
	EndsAt: number,
	Slot: number,
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
	Aliens: { AlienInstance },
	Hatching: { HatchEntry },
	Index: { [string]: boolean },
	Boosts: { [string]: number },
	Gamepasses: { [string]: boolean },
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
	Aliens: { AlienInstance },
	Hatching: { HatchEntry },
	Index: { [string]: boolean },
	Boosts: { [string]: number },
	Gamepasses: { [string]: boolean },
	Flags: { [string]: any },
	Stats: { [string]: number },
	Slots: number,
	IncomePerSec: number,
	CashMultiplier: number,
	CarriedEggs: { Rarity },
	CarryLimit: number,
	BaseIndex: number,
	TutorialStep: string,
	TutorialTarget: Vector3?,
	AutoSweep: boolean,
	ServerTime: number,
}

return {}
