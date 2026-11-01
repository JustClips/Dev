--!strict
-- What's in your bag, for the bag window (InventoryController) and the hotbar
-- (HotbarController): names, rarity colours, sort order, hotbar keys, and the main action
-- (hold a pet or an egg out, use a potion).
--
-- Hotbar keys: "P:<pet uid>", "E:<rarity>" (a stack of every egg of that rarity; using it
-- holds the heaviest one) and "I:<item id>".
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent
local ModelView = require(Client.ModelView)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AlienModel = require(Shared.AlienModel)
local AssetLibrary = require(Shared.AssetLibrary)
local Aliens = require(Shared.Config.Aliens)
local Eggs = require(Shared.Config.Eggs)
local Items = require(Shared.Config.Items)
local LimitedEgg = require(Shared.Config.LimitedEgg)
local Net = require(Shared.Net)
local Weights = require(Shared.Config.Weights)

local BagItems = {}

export type Entry = {
	kind: string, -- "Pet" | "Egg" | "Item"
	id: string, -- pet uid, egg uid (best egg for a stack), item id
	key: string, -- hotbar key
	name: string,
	color: Color3,
	order: number,
	count: number, -- eggs in a stack, potions owned; 1 for pets / single eggs
	rarity: string?,
	mutation: string?, -- eggs: a weather mutation it got in the field (its own stack)
	zone: string?, -- eggs: LimitedEgg.Id for the limited egg
}

local WHITE = Color3.new(1, 1, 1)

function BagItems.petName(pet): string
	return (if pet.Huge then "Huge " else "") .. AlienModel.displayName(pet.Id, pet.Mutation)
end

-- The mutation's label ("Rainbow"), or "" for a plain egg.
local function mutationLabel(mutation: string?): string
	local def = mutation and Eggs.MutationByName[mutation]
	return if def then def.Label .. " " elseif mutation then mutation .. " " else ""
end

function BagItems.eggName(egg): string
	if LimitedEgg.isEgg(egg) then
		return LimitedEgg.Name
	end
	local size = egg.Size or "Normal"
	return mutationLabel(egg.Mutation) .. (if size ~= "Normal" then size .. " " else "") .. `{egg.Rarity} Egg`
end

-- Eggs stack by rarity, and mutated eggs get their own stack per mutation (Dev, 2026-10-31:
-- a Rainbow egg hid in the plain Common stack). "Common" or "Common:Rainbow".
function BagItems.eggStack(egg): string
	return if LimitedEgg.isEgg(egg) then LimitedEgg.Id
		elseif egg.Mutation then `{egg.Rarity}:{egg.Mutation}` else egg.Rarity
end

function BagItems.petWeight(pet): number
	local def = Aliens.ById[pet.Id]
	return pet.Weight or Weights.petKg(def and def.Rarity or "Common")
end

function BagItems.eggWeight(egg): number
	return egg.Weight or Weights.eggKg(egg.Rarity)
end

function BagItems.rarityColor(rarity: string?): Color3
	local def = rarity and Eggs.ByName[rarity]
	return if def then def.Color else WHITE
end

local function petEntry(uid: string, pet): Entry
	local def = Aliens.ById[pet.Id]
	local rarity = def and def.Rarity or "Common"
	local income = math.min(Aliens.income(pet), 1e12)
	return {
		kind = "Pet",
		id = uid,
		key = "P:" .. uid,
		name = BagItems.petName(pet),
		color = BagItems.rarityColor(rarity),
		order = 1e9 - Eggs.order(rarity) * 1e7 - math.min(income, 1e7 - 1),
		count = 1,
		rarity = rarity,
	}
end

local function eggEntry(uid: string, egg): Entry
	return {
		kind = "Egg",
		id = uid,
		key = "E:" .. BagItems.eggStack(egg),
		name = BagItems.eggName(egg),
		color = BagItems.rarityColor(egg.Rarity),
		-- Mutated stacks sit just before the plain stack of their rarity.
		order = 2e9 - Eggs.order(egg.Rarity) * 1000 - (if egg.Mutation then 999 else math.min(BagItems.eggWeight(egg), 998)),
		count = 1,
		rarity = egg.Rarity,
		mutation = egg.Mutation,
		zone = egg.Zone,
	}
end

local function itemEntry(index: number, def, count: number): Entry
	return {
		kind = "Item",
		id = def.Id,
		key = "I:" .. def.Id,
		name = def.Name,
		color = def.Color,
		order = 3e9 + index,
		count = count,
	}
end

local function sortEntries(list: { Entry })
	table.sort(list, function(a, b)
		if a.order == b.order then
			return a.id < b.id
		end
		return a.order < b.order
	end)
end

-- Everything in the bag (pets on your base aren't in it). `tab` is "All", "Pets", "Eggs"
-- or "Items"; `query` filters by name.
function BagItems.list(data, tab: string, query: string?): { Entry }
	local q = string.lower(query or "")
	local function matches(name: string): boolean
		return q == "" or string.find(string.lower(name), q, 1, true) ~= nil
	end
	local list: { Entry } = {}
	if tab == "All" or tab == "Pets" then
		for uid, pet in data.Pets or {} do
			if not pet.Placed and Aliens.ById[pet.Id] then
				local e = petEntry(uid, pet)
				if matches(e.name) then
					table.insert(list, e)
				end
			end
		end
	end
	if tab == "All" or tab == "Eggs" then
		for uid, egg in data.Eggs or {} do
			local e = eggEntry(uid, egg)
			if matches(e.name) then
				table.insert(list, e)
			end
		end
	end
	if tab == "All" or tab == "Items" then
		for i, def in Items.List do
			local n = data.Items and data.Items[def.Id] or 0
			if n > 0 and matches(def.Name) then
				table.insert(list, itemEntry(i, def, n))
			end
		end
	end
	sortEntries(list)
	return list
end

-- What the bag window lists: pets one by one, eggs stacked by rarity ("Rare Egg x3",
-- like the hotbar), potions stacked. `skip(key)` leaves out what's in the hotbar.
function BagItems.bagEntries(data, query: string?, skip: ((string) -> boolean)?): { Entry }
	local q = string.lower(query or "")
	local function keep(e: Entry): boolean
		return (q == "" or string.find(string.lower(e.name), q, 1, true) ~= nil) and not (skip and skip(e.key))
	end
	local list: { Entry } = {}
	for _, e in BagItems.list(data, "Pets") do
		if keep(e) then
			table.insert(list, e)
		end
	end
	local stacks = {}
	for _, egg in data.Eggs or {} do
		local stack = BagItems.eggStack(egg)
		if not table.find(stacks, stack) then
			table.insert(stacks, stack)
		end
	end
	for _, stack in stacks do
		local e = BagItems.resolve(data, "E:" .. stack)
		if e and keep(e) then
			table.insert(list, e)
		end
	end
	for _, e in BagItems.list(data, "Items") do
		if keep(e) then
			table.insert(list, e)
		end
	end
	sortEntries(list)
	return list
end

-- How many pets (in the bag), eggs and potions there are.
function BagItems.counts(data): (number, number, number)
	local pets, eggs, items = 0, 0, 0
	for _, pet in data.Pets or {} do
		if not pet.Placed then
			pets += 1
		end
	end
	for _ in data.Eggs or {} do
		eggs += 1
	end
	for _, n in data.Items or {} do
		items += n
	end
	return pets, eggs, items
end

-- The heaviest egg of a stack (what an egg stack hands you). `stack` is a rarity, or
-- "Rarity:Mutation" for mutated eggs (BagItems.eggStack).
function BagItems.bestEgg(data, stack: string): (string?, number)
	local best, bestKg, count = nil, -1, 0
	for uid, egg in data.Eggs or {} do
		if BagItems.eggStack(egg) == stack then
			count += 1
			local kg = BagItems.eggWeight(egg)
			if kg > bestKg then
				best, bestKg = uid, kg
			end
		end
	end
	return best, count
end

-- The entry a hotbar key stands for right now (nil when it's gone).
function BagItems.resolve(data, key: string): Entry?
	local kind, id = string.match(key, "^(%a):(.+)$")
	if kind == "P" then
		local pet = data.Pets and data.Pets[id]
		if pet and not pet.Placed and Aliens.ById[pet.Id] then
			return petEntry(id :: string, pet)
		end
	elseif kind == "E" then
		local uid, count = BagItems.bestEgg(data, id :: string)
		if uid then
			local egg = data.Eggs[uid]
			local e = eggEntry(uid, egg)
			e.name = if LimitedEgg.isEgg(egg) then LimitedEgg.Name else `{mutationLabel(egg.Mutation)}{egg.Rarity} Egg`
			e.count = count
			return e
		end
	elseif kind == "I" then
		for i, def in Items.List do
			if def.Id == id then
				local n = data.Items and data.Items[def.Id] or 0
				return if n > 0 then itemEntry(i, def, n) else nil
			end
		end
	end
	return nil
end

-- Everything that can go in the hotbar (pets and egg stacks; potions stay in the bag), in
-- the order an empty hotbar fills up: egg stacks (best rarity first), then your best pets.
function BagItems.fillOrder(data): { Entry }
	local out: { Entry } = {}
	local stacks = {}
	for _, egg in data.Eggs or {} do
		local stack = BagItems.eggStack(egg)
		if not table.find(stacks, stack) then
			table.insert(stacks, stack)
		end
	end
	table.sort(stacks, function(a, b)
		local ra, rb = string.match(a, "^[^:]+") :: string, string.match(b, "^[^:]+") :: string
		if ra ~= rb then
			return Eggs.order(ra) > Eggs.order(rb)
		end
		return #a > #b -- mutated first
	end)
	for _, stack in stacks do
		local e = BagItems.resolve(data, "E:" .. stack)
		if e then
			table.insert(out, e)
		end
	end
	for _, e in BagItems.list(data, "Pets") do
		table.insert(out, e)
	end
	return out
end

-- Draws an entry's model (pets, eggs) or icon (potions).
function BagItems.show(viewport: ViewportFrame, icon: ImageLabel?, entry: Entry, data)
	local isItem = entry.kind == "Item"
	viewport.Visible = not isItem
	if icon then
		icon.Visible = isItem
	end
	if entry.kind == "Pet" then
		local pet = data.Pets[entry.id]
		ModelView.show(viewport, AssetLibrary.alien(pet.Id, pet.Mutation), "Alien_" .. pet.Id)
	elseif entry.kind == "Egg" then
		local egg = { Rarity = entry.rarity or "Common", Mutation = entry.mutation, Zone = entry.zone }
		ModelView.show(viewport, AssetLibrary.eggOf(egg), AssetLibrary.eggKey(egg))
	elseif icon then
		local def = Items.ById[entry.id]
		icon.Image = if def then AssetLibrary.image(def.Icon) else ""
	end
end

-- The main thing to do with an entry: hold a pet or an egg out (or put it away if it's
-- the one in your hands), or use a potion after a quick "are you sure?".
function BagItems.use(C: any, entry: Entry)
	local data = require(Client.State).data
	if not data then
		return
	end
	if entry.kind == "Item" then
		local def = Items.ById[entry.id]
		if not def then
			return
		end
		C.ConfirmController:Ask({ title = "Use item?", name = def.Name, text = def.Description, icon = def.Icon, yes = "Use" }, function()
			local ok, message = Net.func("Inventory"):InvokeServer("UseItem", entry.id)
			if message and message ~= "" then
				C.HudController:Toast(message, if ok then "Good" else "Bad")
			end
		end)
		return
	end
	local held = C.PlacementController:HeldKey()
	if entry.kind == "Egg" then
		-- A stack: put away if you hold any egg of this rarity.
		local heldEgg = held and data.Eggs and data.Eggs[held]
		if held == entry.id or (heldEgg and entry.key == "E:" .. BagItems.eggStack(heldEgg)) then
			C.PlacementController:Stop()
			return
		end
		if not data.Eggs or not data.Eggs[entry.id] then
			return
		end
		if #data.Hatching >= data.Incubators then
			C.HudController:Toast(`Only {data.Incubators} eggs can grow at once. Open one first!`, "Bad")
			return
		end
		C.PlacementController:Hold(entry.id)
	else
		if held == entry.id then
			C.PlacementController:Stop()
			return
		end
		C.PlacementController:HoldPet(entry.id)
	end
end

-- True when this entry is what you're holding (for a hotbar egg stack: any egg of it).
function BagItems.isHeld(C: any, data, entry: Entry, stack: boolean?): boolean
	local held = C.PlacementController:HeldKey()
	if not held then
		return false
	end
	if held == entry.id then
		return true
	end
	local egg = data.Eggs and data.Eggs[held]
	return stack == true and egg ~= nil and entry.kind == "Egg" and entry.key == "E:" .. BagItems.eggStack(egg)
end

return BagItems
