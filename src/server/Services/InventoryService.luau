--!strict
-- The inventory (Steal an Egg style): eggs you brought home, pets you hatched and items
-- (potions). Nothing hatches or gets placed on its own: players hold an egg and put it
-- down in their pet park (HatchService), open it when ready, and place or pick up pets on
-- their base. Eggs get their size and weight (Config/Weights) when they're added.
-- One remote, Inventory(action, arg, position?), handles every button in the inventory
-- window and the prompts on the base.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Aliens = require(Shared.Config.Aliens)
local Economy = require(Shared.Config.Economy)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Weights = require(Shared.Config.Weights)

local InventoryService = {}

local S: any
local rng = Random.new()

local function count(map: { [string]: any }): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

-- Marks the inventory as changed: the next state snapshot carries the full tables.
function InventoryService:Touch(player: Player)
	local session = S.DataService:GetSession(player)
	if session then
		session.Runtime.InvVersion = (session.Runtime.InvVersion or 0) + 1
	end
	S.StateService:Mark(player)
end

function InventoryService:GetVersion(player: Player): number
	local session = S.DataService:GetSession(player)
	return if session then session.Runtime.InvVersion or 0 else 0
end

function InventoryService:PetCount(player: Player): number
	local data = S.DataService:GetData(player)
	return if data then count(data.Pets) else 0
end

function InventoryService:EggCount(player: Player): number
	local data = S.DataService:GetData(player)
	return if data then count(data.Eggs) else 0
end

-- Adds an egg to the inventory. force = true ignores the bag limit (purchases).
function InventoryService:AddEgg(player: Player, rarity: string, zone: string?, force: boolean?): boolean
	local data = S.DataService:GetData(player)
	if not data or not Eggs.ByName[rarity] then
		return false
	end
	if not force and count(data.Eggs) >= Economy.EggBagSize then
		return false
	end
	local luck = S.BoostService:GetServerLuck() * S.BoostService:GetPersonalLuck(player)
	local size, weight = Weights.rollEgg(rng, rarity, luck)
	data.Eggs[S.DataService:NewUid(data, "e")] = { Rarity = rarity, Zone = zone or "Landing", Weight = weight, Size = size }
	InventoryService:Touch(player)
	return true
end

function InventoryService:AddItem(player: Player, itemId: string, amount: number?)
	local data = S.DataService:GetData(player)
	if not data or not Items.ById[itemId] then
		return
	end
	data.Items[itemId] = (data.Items[itemId] or 0) + (amount or 1)
	InventoryService:Touch(player)
end

local function changedBase(player: Player)
	InventoryService:Touch(player)
	S.AlienService:RefreshBase(player)
end

function InventoryService:PlacePet(player: Player, uid: string): (boolean, string?)
	local data = S.DataService:GetData(player)
	local pet = data and data.Pets[uid]
	if not pet then
		return false, "That pet is gone"
	end
	if pet.Placed then
		return true, nil
	end
	local slots = S.AlienService:GetSlotCount(player)
	if S.AlienService:PlacedCount(player) >= slots then
		return false, `Your base is full ({slots} pets)! Pick one up first, or rebirth for more room.`
	end
	pet.Placed = true
	changedBase(player)
	return true, nil
end

function InventoryService:PickUpPet(player: Player, uid: string): (boolean, string?)
	local data = S.DataService:GetData(player)
	local pet = data and data.Pets[uid]
	if not pet or not pet.Placed then
		return false, "That pet isn't on your base"
	end
	pet.Placed = nil
	changedBase(player)
	return true, nil
end

-- Places the highest-earning pets until the base is full (and takes weaker ones back).
function InventoryService:EquipBest(player: Player): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return false, "Still loading"
	end
	local list = {}
	for uid, pet in data.Pets do
		table.insert(list, { uid = uid, pet = pet, income = Aliens.income(pet) })
	end
	table.sort(list, function(a, b)
		return a.income > b.income
	end)
	local slots = S.AlienService:GetSlotCount(player)
	for i, entry in list do
		entry.pet.Placed = if i <= slots then true else nil
	end
	changedBase(player)
	return true, `Placed your best {math.min(slots, #list)} pets!`
end

function InventoryService:SellPet(player: Player, uid: string): (boolean, string?)
	local data = S.DataService:GetData(player)
	local pet = data and data.Pets[uid]
	if not data or not pet then
		return false, "That pet is gone"
	end
	local value = Aliens.income(pet) * Economy.PetSellSeconds * S.BoostService:GetBaseCashMultiplier(player)
	data.Pets[uid] = nil
	S.BackpackService:GiveCash(player, value, "SellPet")
	changedBase(player)
	local def = Aliens.ById[pet.Id]
	return true, `Sold {def and def.Name or "pet"} for {Format.cash(value)}`
end

function InventoryService:UseItem(player: Player, itemId: string): (boolean, string?)
	local data = S.DataService:GetData(player)
	local def = Items.ById[itemId]
	if not data or not def or (data.Items[itemId] or 0) <= 0 then
		return false, "You don't have that"
	end
	if def.HatchSeconds then
		if S.HatchService:SpeedUp(player, def.HatchSeconds) == 0 then
			return false, "No eggs are hatching right now"
		end
	elseif def.Boost then
		S.BoostService:AddPersonalBoost(player, def.Boost, def.Minutes or 10)
		if def.Boost == "Speed" then
			S.UpgradeService:ApplyWalkSpeed(player)
		end
	end
	data.Items[itemId] -= 1
	if data.Items[itemId] <= 0 then
		data.Items[itemId] = nil
	end
	InventoryService:Touch(player)
	S.AnalyticsService:Custom(player, "ItemUsed", 1, { Item = itemId })
	return true, `{def.Name}: {def.Description}!`
end

-- Skip Hatch on one egg: remembers which egg, then opens the Robux prompt.
local function skipHatch(player: Player, uid: string): (boolean, string?)
	local session = S.DataService:GetSession(player)
	if not session then
		return false, "Still loading"
	end
	for _, entry in session.Data.Hatching do
		if entry.Uid == uid then
			if entry.EndsAt <= os.time() then
				return false, "It's ready! Open it."
			end
			session.Runtime.SkipTarget = uid
			local product = Products.ProductByKey["SkipHatch" .. entry.Rarity]
			return S.ShopService:Prompt(player, if product then product.Key else "SkipHatchCommon")
		end
	end
	return false, "That egg is gone"
end

local ACTIONS: { [string]: (Player, any, Vector3?) -> (boolean, string?) } = {
	PlaceEgg = function(player, uid)
		return S.HatchService:PlaceEgg(player, uid)
	end,
	-- Hold an egg out, then click a spot in your pet park (PlaceEggAt).
	HoldEgg = function(player, uid)
		return S.HatchService:Hold(player, uid)
	end,
	StopHolding = function(player)
		S.HatchService:StopHolding(player)
		return true, nil
	end,
	PlaceEggAt = function(player, uid, position)
		if not position then
			return false, "Bad request"
		end
		return S.HatchService:PlaceEgg(player, uid, position)
	end,
	PlaceBestEggs = function(player)
		local placed = S.HatchService:PlaceBest(player)
		if placed > 0 then
			return true, nil
		end
		if InventoryService:EggCount(player) == 0 then
			return false, "No eggs in your bag. Sweep dust to find some!"
		end
		return false, "Your park is full of eggs! Open one first."
	end,
	OpenEgg = function(player, uid)
		return S.HatchService:Open(player, uid)
	end,
	OpenReady = function(player)
		local opened, err = S.HatchService:OpenReady(player)
		if opened > 0 then
			return true, nil
		end
		return false, err or "No eggs are ready yet"
	end,
	SkipHatch = skipHatch,
	PlacePet = function(player, uid)
		return InventoryService:PlacePet(player, uid)
	end,
	PickUpPet = function(player, uid)
		return InventoryService:PickUpPet(player, uid)
	end,
	EquipBest = function(player)
		return InventoryService:EquipBest(player)
	end,
	SellPet = function(player, uid)
		return InventoryService:SellPet(player, uid)
	end,
	UseItem = function(player, itemId)
		return InventoryService:UseItem(player, itemId)
	end,
}

function InventoryService:Init(services)
	S = services
	Net.onInvoke("Inventory", function(player, action, arg, position)
		if type(action) ~= "string" or (arg ~= nil and type(arg) ~= "string") then
			return false, "Bad request"
		end
		if position ~= nil and (typeof(position) ~= "Vector3" or position.Magnitude ~= position.Magnitude) then
			return false, "Bad request"
		end
		local handler = ACTIONS[action]
		if not handler then
			return false, "Bad request"
		end
		return handler(player, arg, position)
	end)
end

function InventoryService:Start() end

return InventoryService
