--!strict
-- Pet passives: every pet kind has one (Config/Aliens Passive). While a pet is placed on
-- the base, its passive adds to an upgrade-tree stat, so the game reads it through
-- Upgrades.stat like any tree bonus. Each kind counts once (its best copy), so collecting
-- different pets matters more than stacking one kind. A Huge copy counts double.
local Aliens = require(script.Parent.Config.Aliens)
local Upgrades = require(script.Parent.Config.Upgrades)

local PetPassives = {}

PetPassives.HugeMult = 2

type Pet = { Id: string, Placed: boolean?, Huge: boolean? }

-- Stat -> total bonus from a player's placed pets.
function PetPassives.totals(pets: { [any]: Pet }?): { [string]: number }
	local best: { [string]: number } = {}
	for _, pet in pets or {} do
		if type(pet) == "table" and pet.Placed then
			local def = Aliens.ById[pet.Id]
			local passive = def and def.Passive
			if passive then
				local value = passive.Value * (if pet.Huge then PetPassives.HugeMult else 1)
				if value > (best[pet.Id] or 0) then
					best[pet.Id] = value
				end
			end
		end
	end
	local totals: { [string]: number } = {}
	for id, value in best do
		local stat = (Aliens.ById[id].Passive :: any).Stat
		totals[stat] = (totals[stat] or 0) + value
	end
	return totals
end

-- "Lucky Paws: +2% Lucky Sweep"
function PetPassives.describe(alienId: string, huge: boolean?): string?
	local def = Aliens.ById[alienId]
	local passive = def and def.Passive
	if not passive then
		return nil
	end
	local stat = Upgrades.Stats[passive.Stat]
	local value = passive.Value * (if huge then PetPassives.HugeMult else 1)
	return `{passive.Name}: {Upgrades.describeStat(passive.Stat, value)} {if stat then stat.Name else passive.Stat}`
end

-- "+2% Lucky Sweep" (for small labels like the bag cards).
function PetPassives.short(alienId: string, huge: boolean?): string?
	local def = Aliens.ById[alienId]
	local passive = def and def.Passive
	if not passive then
		return nil
	end
	local stat = Upgrades.Stats[passive.Stat]
	local value = passive.Value * (if huge then PetPassives.HugeMult else 1)
	return `{Upgrades.describeStat(passive.Stat, value)} {if stat then stat.Name else passive.Stat}`
end

-- Server only: makes Upgrades.stat include each player's pet passives. Totals are cached
-- for a second per player, since sweeping reads stats many times a second.
function PetPassives.install(getSessions: () -> { [Player]: any })
	local cache: { [any]: { at: number, totals: { [string]: number } } } = setmetatable({}, { __mode = "k" }) :: any
	Upgrades.extra = function(levels)
		for _, session in getSessions() do
			local data = session.Data
			if data and data.Upgrades == levels then
				local entry = cache[data]
				local now = os.clock()
				if not entry or now - entry.at > 1 then
					local totals = PetPassives.totals(data.Pets)
					-- Best Friends (Pet Lab) makes every passive stronger.
					local power = 1 + Upgrades.treeStat(levels, "PassivePower")
					if power ~= 1 then
						for stat, value in totals do
							totals[stat] = value * power
						end
					end
					entry = { at = now, totals = totals }
					cache[data] = entry
				end
				return entry.totals
			end
		end
		return nil
	end
end

return PetPassives
