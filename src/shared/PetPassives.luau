--!strict
-- Pet passives: every pet kind has one (Config/Aliens Passive). While a pet is placed on
-- the base, its passive adds to an upgrade-tree stat, so the game reads it through
-- Upgrades.stat like any tree bonus. Each kind counts once (its best copy), so collecting
-- different pets matters more than stacking one kind. A Huge copy counts double.
--
-- Mutations (Config/Eggs) make passives stronger:
--   * PassiveMult, always (Golden x1.5, Rainbow x2, Sparkly x3, weather ones x1.25-x3).
--   * "In season": while the mutation's own weather or moon is live (Disco pets during
--     Disco, Frozen pets during Snowfall, Sparkly pets every night...), the passive gets
--     SeasonMult more, the pet adds its mutation's SeasonPerk stat, and SeasonIncome
--     multiplies its cash.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Aliens = require(script.Parent.Config.Aliens)
local Eggs = require(script.Parent.Config.Eggs)
local Upgrades = require(script.Parent.Config.Upgrades)
local Weather = require(script.Parent.Config.Weather)

local PetPassives = {}

PetPassives.HugeMult = 2
PetPassives.SeasonMult = 3
-- Most a stat can get from pets alone (chances that would break the game past this).
PetPassives.Caps = { Crit = 0.35, ComboKeep = 0.6 } :: { [string]: number }

type Pet = { Id: string, Placed: boolean?, Huge: boolean?, Mutation: string? }
export type Seasons = { [string]: boolean }

-- What is live right now: the weather id, the moon id and "Night". Reads the ServerState
-- attributes (WeatherService), so it works the same on server and client.
function PetPassives.seasons(): Seasons
	local live: Seasons = {}
	local state = ReplicatedStorage:FindFirstChild("ServerState")
	if not state then
		return live
	end
	local weather = state:GetAttribute("Weather")
	if type(weather) == "string" and weather ~= "" then
		live[weather] = true
	end
	local start = state:GetAttribute("CycleStart")
	if type(start) == "number" then
		local phase = Weather.phase(Workspace:GetServerTimeNow() - start)
		if phase == "Night" then
			live.Night = true
			local moon = state:GetAttribute("Moon")
			if type(moon) == "string" and moon ~= "" then
				live[moon] = true
			end
		end
	end
	return live
end

-- Is a pet with this mutation powered up right now?
function PetPassives.inSeason(mutation: string?, seasons: Seasons?): boolean
	local def = mutation and Eggs.MutationByName[mutation]
	if not (def and def.Seasons and seasons) then
		return false
	end
	for _, id in def.Seasons do
		if seasons[id] then
			return true
		end
	end
	return false
end

-- "during Disco", "during Golden Hour or Gold Moon", "every night".
function PetPassives.seasonText(mutation: string?): string?
	local def = mutation and Eggs.MutationByName[mutation]
	if not (def and def.Seasons) then
		return nil
	end
	if def.SeasonText then
		return def.SeasonText
	end
	local names = {}
	for _, id in def.Seasons do
		local w = Weather.ById[id]
		table.insert(names, if w then w.Name else id)
	end
	return "during " .. table.concat(names, " or ")
end

-- Passive strength of one pet copy.
function PetPassives.value(alienId: string, huge: boolean?, mutation: string?, seasons: Seasons?): number
	local def = Aliens.ById[alienId]
	local passive = def and def.Passive
	if not passive then
		return 0
	end
	local value = passive.Value * (if huge then PetPassives.HugeMult else 1)
	local mut = mutation and Eggs.MutationByName[mutation]
	if mut and mut.PassiveMult then
		value *= mut.PassiveMult
	end
	if PetPassives.inSeason(mutation, seasons) then
		value *= PetPassives.SeasonMult
	end
	-- Whole-number stats (Eggs at Once) stay whole.
	if passive.Stat == "Incubators" then
		value = math.floor(value)
	end
	return value
end

-- Pet income mult from its season (Disco pets earn 2x during Disco).
function PetPassives.incomeMult(mutation: string?, seasons: Seasons?): number
	local mut = mutation and Eggs.MutationByName[mutation]
	if mut and mut.SeasonIncome and PetPassives.inSeason(mutation, seasons) then
		return mut.SeasonIncome
	end
	return 1
end

-- Stat -> total bonus from a player's placed pets.
function PetPassives.totals(pets: { [any]: Pet }?, seasons: Seasons?): { [string]: number }
	local best: { [string]: number } = {}
	local totals: { [string]: number } = {}
	for _, pet in pets or {} do
		if type(pet) == "table" and pet.Placed and Aliens.ById[pet.Id] then
			local value = PetPassives.value(pet.Id, pet.Huge, pet.Mutation, seasons)
			if value > (best[pet.Id] or 0) then
				best[pet.Id] = value
			end
			-- Season perks add up per pet (a park full of Disco pets during Disco).
			local mut = pet.Mutation and Eggs.MutationByName[pet.Mutation]
			if mut and mut.SeasonPerk and PetPassives.inSeason(pet.Mutation, seasons) then
				local perk = mut.SeasonPerk
				totals[perk.Stat] = (totals[perk.Stat] or 0) + perk.Value * (if pet.Huge then PetPassives.HugeMult else 1)
			end
		end
	end
	for id, value in best do
		local stat = (Aliens.ById[id].Passive :: any).Stat
		totals[stat] = (totals[stat] or 0) + value
	end
	return totals
end

local function statText(stat: string, value: number): string
	local def = Upgrades.Stats[stat]
	return `{Upgrades.describeStat(stat, value)} {if def then def.Name else stat}`
end

-- "Lucky Paws: +2% Lucky Sweep"
function PetPassives.describe(alienId: string, huge: boolean?, mutation: string?, seasons: Seasons?): string?
	local def = Aliens.ById[alienId]
	local passive = def and def.Passive
	if not passive then
		return nil
	end
	return `{passive.Name}: {statText(passive.Stat, PetPassives.value(alienId, huge, mutation, seasons))}`
end

-- "+2% Lucky Sweep" (for small labels like the bag cards).
function PetPassives.short(alienId: string, huge: boolean?, mutation: string?, seasons: Seasons?): string?
	local def = Aliens.ById[alienId]
	local passive = def and def.Passive
	if not passive then
		return nil
	end
	return statText(passive.Stat, PetPassives.value(alienId, huge, mutation, seasons))
end

-- The mutation's season line for hover cards:
--   in season:   "IN SEASON! Passive x3, +15% All Cash, 2x cash"
--   otherwise:   "Passive x3 during Disco: +15% All Cash, 2x cash"
function PetPassives.seasonLine(mutation: string?, huge: boolean?, seasons: Seasons?): string?
	local mut = mutation and Eggs.MutationByName[mutation]
	if not (mut and mut.Seasons) then
		return nil
	end
	local parts = { `Passive x{PetPassives.SeasonMult}` }
	if mut.SeasonPerk then
		table.insert(parts, statText(mut.SeasonPerk.Stat, mut.SeasonPerk.Value * (if huge then PetPassives.HugeMult else 1)))
	end
	if mut.SeasonIncome then
		table.insert(parts, `{mut.SeasonIncome}x cash`)
	end
	if PetPassives.inSeason(mutation, seasons) then
		return "IN SEASON! " .. table.concat(parts, ", ")
	end
	local first = table.remove(parts, 1)
	local text = `{first} {PetPassives.seasonText(mutation)}`
	return if #parts > 0 then `{text}: {table.concat(parts, ", ")}` else text
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
					local totals = PetPassives.totals(data.Pets, PetPassives.seasons())
					-- Best Friends (Pet Lab) makes every passive stronger.
					local power = 1 + Upgrades.treeStat(levels, "PassivePower")
					for stat, value in totals do
						totals[stat] = math.min(value * power, PetPassives.Caps[stat] or math.huge)
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
