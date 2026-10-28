--!strict
-- Incubators on your base's hatchery pad (Steal an Egg style). You place eggs from your
-- inventory; each one is saved with its spot and a unix EndsAt, so the timer keeps running
-- while you're offline. When it's ready you open it (prompt on the egg, or Open All in the
-- inventory) and the pet goes to your inventory. Mutations and Huge roll at opening and
-- scale with luck.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Aliens = require(Shared.Config.Aliens)
local Economy = require(Shared.Config.Economy)
local Eggs = require(Shared.Config.Eggs)
local Net = require(Shared.Net)

local HatchService = {}

local S: any
local rng = Random.new()

local function notify(player: Player, text: string, kind: string?)
	Net.fire("Notify", player, text, kind or "Bad")
end

function HatchService:GetIncubatorCount(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return Economy.Incubators
	end
	local count = Economy.Incubators + math.floor(data.Rebirths / Economy.RebirthsPerIncubator)
	return math.min(count, Economy.MaxIncubators)
end

local function freeSpot(player: Player, data): number?
	local used = {}
	for _, entry in data.Hatching do
		used[entry.Spot] = true
	end
	for spot = 1, HatchService:GetIncubatorCount(player) do
		if not used[spot] then
			return spot
		end
	end
	return nil
end

local function hatchSeconds(data, rarity: string): number
	local seconds = Eggs.ByName[rarity].HatchSeconds
	if data.Gamepasses.FasterHatch then
		seconds *= Eggs.FasterHatchMult
	end
	return math.ceil(seconds)
end

local function changed(player: Player)
	S.InventoryService:Touch(player)
	S.AlienService:RefreshBase(player)
	S.StateService:Mark(player)
end

-- Moves an egg from the inventory into a free incubator. Returns ok, message.
function HatchService:PlaceEgg(player: Player, uid: string): (boolean, string?)
	local data = S.DataService:GetData(player)
	local egg = data and data.Eggs[uid]
	if not data or not egg then
		return false, "That egg is gone"
	end
	local spot = freeSpot(player, data)
	if not spot then
		return false, "All incubators are busy! Open or wait for an egg first."
	end
	data.Eggs[uid] = nil
	local seconds = hatchSeconds(data, egg.Rarity)
	if (data.Flags.FreeSkips or 0) > 0 then
		data.Flags.FreeSkips -= 1
		seconds = 0
	end
	table.insert(data.Hatching, { Uid = uid, Rarity = egg.Rarity, Zone = egg.Zone, Spot = spot, EndsAt = os.time() + seconds })
	changed(player)
	if Eggs.order(egg.Rarity) >= Eggs.order("Rare") and seconds > 0 then
		S.OfferService:OnRareHatchStarted(player, egg.Rarity)
	end
	return true, nil
end

-- Places the rarest eggs first until the incubators are full. Returns how many.
function HatchService:PlaceBest(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return 0
	end
	local list = {}
	for uid, egg in data.Eggs do
		table.insert(list, { uid = uid, order = Eggs.order(egg.Rarity) })
	end
	table.sort(list, function(a, b)
		return a.order > b.order
	end)
	local placed = 0
	for _, entry in list do
		if not freeSpot(player, data) then
			break
		end
		if HatchService:PlaceEgg(player, entry.uid) then
			placed += 1
		end
	end
	return placed
end

local function rollMutation(luck: number): string?
	for _, mutation in Eggs.Mutations do
		if rng:NextNumber() < math.min(1, luck / mutation.Chance) then
			return mutation.Name
		end
	end
	return nil
end

-- Opens a ready egg: rolls the pet and puts it in the inventory.
function HatchService:Open(player: Player, uid: string, quiet: boolean?): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return false, "Still loading"
	end
	local index = nil
	for i, entry in data.Hatching do
		if entry.Uid == uid then
			index = i
			break
		end
	end
	local entry = index and data.Hatching[index]
	if not entry then
		return false, "That egg is gone"
	end
	if entry.EndsAt > os.time() then
		return false, "Not ready yet"
	end
	if S.InventoryService:PetCount(player) >= Economy.PetBagSize then
		return false, "Your pet bag is full! Sell or place some pets first."
	end
	table.remove(data.Hatching, index)

	local pool = Aliens.pool(entry.Zone, entry.Rarity)
	local def = pool[rng:NextInteger(1, #pool)]
	local luck = S.BoostService:GetServerLuck() * S.BoostService:GetPersonalLuck(player)
	local mutation = rollMutation(luck)
	local huge = rng:NextNumber() < math.min(1, Aliens.HugeChance * luck)
	local isNew = not data.Index[def.Id]
	data.Index[def.Id] = true
	local petUid = S.DataService:NewUid(data, "p")
	local pet = { Id = def.Id, Mutation = mutation, Huge = if huge then true else nil }
	data.Pets[petUid] = pet
	data.Stats.Hatches += 1

	S.AnalyticsService:Funnel(player, "FirstHatch")
	changed(player)
	if not quiet then
		Net.fire("HatchCompleted", player, {
			Uid = petUid,
			AlienId = def.Id,
			Mutation = mutation,
			Huge = huge,
			Rarity = def.Rarity,
			IsNew = isNew,
			Income = Aliens.income(pet),
			FreeSlot = S.AlienService:PlacedCount(player) < S.AlienService:GetSlotCount(player),
		})
	end
	if huge or mutation or Eggs.order(def.Rarity) >= Eggs.order("Mythic") then
		local label = (if huge then "HUGE " else "") .. (if mutation then Eggs.MutationByName[mutation].Label .. " " else "")
		Net.fireAll("Announce", `{player.DisplayName} hatched a {label}{def.Name} ({def.Rarity})!`, "Hatch")
	end
	S.OfferService:OnHatch(player)
	return true, nil
end

-- Opens every ready egg. The cutscene plays for the best one only.
function HatchService:OpenReady(player: Player): (number, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return 0, "Still loading"
	end
	local ready = {}
	for _, entry in data.Hatching do
		if entry.EndsAt <= os.time() then
			table.insert(ready, entry)
		end
	end
	table.sort(ready, function(a, b)
		return Eggs.order(a.Rarity) < Eggs.order(b.Rarity)
	end)
	local opened, lastError = 0, nil
	for i, entry in ready do
		local ok, err = HatchService:Open(player, entry.Uid, i < #ready)
		if ok then
			opened += 1
		else
			lastError = err
			break
		end
	end
	return opened, lastError
end

-- Skip Hatch product: finishes the egg the player picked (SkipTarget), else the slowest
-- egg of that rarity, else any egg, else banks a free skip for the next egg placed.
function HatchService:Skip(player: Player, rarity: string?, targetUid: string?)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	local target = nil
	for _, entry in data.Hatching do
		if entry.Uid == targetUid then
			target = entry
			break
		end
	end
	if not target then
		for _, entry in data.Hatching do
			if entry.Rarity == rarity and entry.EndsAt > os.time() and (not target or entry.EndsAt > target.EndsAt) then
				target = entry
			end
		end
	end
	if not target then
		for _, entry in data.Hatching do
			if entry.EndsAt > os.time() then
				target = entry
				break
			end
		end
	end
	if target then
		target.EndsAt = os.time()
		notify(player, `Your {target.Rarity} egg is ready to open!`, "Good")
	else
		data.Flags.FreeSkips = (data.Flags.FreeSkips or 0) + 1
		notify(player, "Saved a free skip for your next egg!", "Good")
	end
	changed(player)
end

-- Hatch potion: every egg in an incubator finishes `seconds` sooner.
function HatchService:SpeedUp(player: Player, seconds: number): number
	local data = S.DataService:GetData(player)
	if not data then
		return 0
	end
	local count = 0
	for _, entry in data.Hatching do
		if entry.EndsAt > os.time() then
			entry.EndsAt = math.max(os.time(), entry.EndsAt - seconds)
			count += 1
		end
	end
	if count > 0 then
		changed(player)
	end
	return count
end

function HatchService:Init(services)
	S = services
end

function HatchService:Start() end

return HatchService
