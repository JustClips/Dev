--!strict
-- The Traveling Merchant (Grow a Garden / Bee Swarm style, Dev picked it 2026-10-30). His
-- cart stands in the plaza. He visits for StaySeconds out of every CycleSeconds; the clock is
-- the same in every server (os.time), so "the merchant has a Huge Charm!" is true for
-- everyone at once. Each visit he brings Slots random wares (Bigger Cart hex: more), each
-- with a stock per player. Prices are cash, set like cash rewards: Seconds of your earnings
-- (pets + selling), so they stay fair at every stage. The Haggler hex gives a discount.
-- A boost potion costs a bit less than what it earns you if you keep playing (a Cash
-- Potion's 10 min of 2x is worth ~600 s of earnings; it costs 450), so buying is a good
-- deal for active players without being free money.
-- Robux "Restock" (Products, Kind "MerchantRestock") rolls you a fresh set right away.

export type Ware = {
	Id: string,
	Item: string?, -- Config/Items id
	Egg: string?, -- egg rarity (hatches from your best zone that can drop it)
	Weight: number, -- how often he brings it
	Stock: number, -- how many each player may buy per visit
	Seconds: number, -- price in seconds of your earnings
}

local Merchant = {}

Merchant.CycleSeconds = 20 * 60
Merchant.StaySeconds = 8 * 60
Merchant.Slots = 4
Merchant.MaxSlots = 6 -- Slots + the Bigger Cart hex
Merchant.MinPrice = 250 -- early players' earnings are tiny; nothing is cheaper than this

-- stylua: ignore
Merchant.Wares = {
	{ Id = "LuckPotion",      Item = "LuckPotion",      Weight = 30,  Stock = 3, Seconds = 120 },
	{ Id = "CashPotion",      Item = "CashPotion",      Weight = 25,  Stock = 1, Seconds = 450 },
	{ Id = "SpeedPotion",     Item = "SpeedPotion",     Weight = 22,  Stock = 3, Seconds = 60 },
	{ Id = "MagnetPotion",    Item = "MagnetPotion",    Weight = 22,  Stock = 3, Seconds = 60 },
	{ Id = "LeafPotion",      Item = "LeafPotion",      Weight = 20,  Stock = 1, Seconds = 360 },
	{ Id = "BigBagPotion",    Item = "BigBagPotion",    Weight = 20,  Stock = 2, Seconds = 200 },
	{ Id = "HatchPotion",     Item = "HatchPotion",     Weight = 20,  Stock = 3, Seconds = 180 },
	{ Id = "LeafBomb",        Item = "LeafBomb",        Weight = 14,  Stock = 2, Seconds = 300 },
	{ Id = "TreasureMap",     Item = "TreasureMap",     Weight = 12,  Stock = 2, Seconds = 360 },
	{ Id = "SuperLuckPotion", Item = "SuperLuckPotion", Weight = 10,  Stock = 1, Seconds = 600 },
	{ Id = "MegaCashPotion",  Item = "MegaCashPotion",  Weight = 8,   Stock = 1, Seconds = 1500 },
	{ Id = "LuckyClover",     Item = "LuckyClover",     Weight = 5,   Stock = 1, Seconds = 1200 },
	{ Id = "MutationSpray",   Item = "MutationSpray",   Weight = 5,   Stock = 1, Seconds = 1200 },
	{ Id = "WeatherTotem",    Item = "WeatherTotem",    Weight = 2,   Stock = 1, Seconds = 2400 },
	{ Id = "HugeCharm",       Item = "HugeCharm",       Weight = 2,   Stock = 1, Seconds = 3600 },
	{ Id = "RareEgg",         Egg = "Rare",             Weight = 12,  Stock = 2, Seconds = 300 },
	{ Id = "EpicEgg",         Egg = "Epic",             Weight = 6,   Stock = 1, Seconds = 900 },
	{ Id = "LegendaryEgg",    Egg = "Legendary",        Weight = 2.5, Stock = 1, Seconds = 2400 },
	{ Id = "MythicEgg",       Egg = "Mythic",           Weight = 0.7, Stock = 1, Seconds = 7200 },
} :: { Ware }

Merchant.ById = {} :: { [string]: Ware }
for _, ware in Merchant.Wares do
	Merchant.ById[ware.Id] = ware
end

-- Which visit `t` (unix time) falls in, whether he's here, and when that changes.
function Merchant.visitAt(t: number): (number, boolean, number)
	local visit = t // Merchant.CycleSeconds
	local into = t - visit * Merchant.CycleSeconds
	if into < Merchant.StaySeconds then
		return visit, true, visit * Merchant.CycleSeconds + Merchant.StaySeconds
	end
	return visit, false, (visit + 1) * Merchant.CycleSeconds
end

-- The wares of a visit, in slot order (MaxSlots of them, all different). `personal` is a
-- seed for a player's own Robux restock (0 = the shared stock everyone sees).
function Merchant.stock(visit: number, personal: number?): { Ware }
	local rng = Random.new(visit * 7919 + 17 + (personal or 0) * 104729)
	local pool = table.clone(Merchant.Wares)
	local out = {}
	for _ = 1, Merchant.MaxSlots do
		local total = 0
		for _, ware in pool do
			total += ware.Weight
		end
		local roll = rng:NextNumber() * total
		for i, ware in pool do
			roll -= ware.Weight
			if roll <= 0 or i == #pool then
				table.insert(out, ware)
				table.remove(pool, i)
				break
			end
		end
	end
	return out
end

-- What one player sees: the first `slots` wares of the visit, cheapest first (so kids see
-- what they can buy). The Bigger Cart hex adds slots.
function Merchant.shown(visit: number, personal: number?, slots: number): { Ware }
	local all = Merchant.stock(visit, personal)
	local out = {}
	for i = 1, math.min(slots, #all) do
		out[i] = all[i]
	end
	table.sort(out, function(a, b)
		return a.Seconds < b.Seconds
	end)
	return out
end

return Merchant
