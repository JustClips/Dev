--!strict
-- The inventory (Steal an Egg style): eggs you brought home, pets you hatched and items
-- (potions). Nothing hatches or gets placed on its own: players hold an egg and put it
-- down in their pet park (HatchService), open it when ready, and place or pick up pets on
-- their base. Eggs get their size and weight (Config/Weights) when they're added.
-- One remote, Inventory(action, arg, position?), handles every button in the inventory
-- window and the prompts on the base.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AlienModel = require(Shared.AlienModel)
local AssetLibrary = require(Shared.AssetLibrary)
local Aliens = require(Shared.Config.Aliens)
local Economy = require(Shared.Config.Economy)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Weights = require(Shared.Config.Weights)
local Upgrades = require(Shared.Config.Upgrades)

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
-- paid: bought with Robux, so it always hatches its own rarity (Eggs.rollPetRarity is skipped).
function InventoryService:AddEgg(player: Player, rarity: string, zone: string?, force: boolean?, paid: boolean?, mutation: string?): boolean
	local data = S.DataService:GetData(player)
	if not data or not Eggs.ByName[rarity] then
		return false
	end
	if not force and count(data.Eggs) >= Economy.EggBagSize then
		return false
	end
	local luck = S.BoostService:GetServerLuck() * S.BoostService:GetPersonalLuck(player)
	local size, weight = Weights.rollEgg(rng, rarity, luck)
	data.Eggs[S.DataService:NewUid(data, "e")] = { Rarity = rarity, Zone = zone or "Landing", Weight = weight, Size = size, Paid = if paid then true else nil, Mutation = mutation }
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
	-- A pet held out that just went on the base (Equip Best, Equip) or away leaves your
	-- hands (Dev, 2026-10-30: it stayed in them after Equip Best).
	InventoryService:DropHeldIfGone(player)
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
		InventoryService:DropHeldIfGone(player)
		return true, nil
	end
	local slots = S.AlienService:GetSlotCount(player)
	if S.AlienService:PlacedCount(player) >= slots then
		return false, `Your base is full ({slots} pets)! Pick one up first, or rebirth for more room.`
	end
	if InventoryService:HeldPet(player) == uid then
		InventoryService:StopHolding(player)
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

-------------------------------------------------------------------------- holding a pet

local HELD_SCALE = 1.1

-- The pet you hold out in front of you (others see it too), to sell it at the Pet Trader or
-- put it in your park.
function InventoryService:HeldPet(player: Player): string?
	local session = S.DataService:GetSession(player)
	local uid = session and session.Runtime.HeldPet
	if uid and session.Data.Pets[uid] and not session.Data.Pets[uid].Placed then
		return uid
	end
	return nil
end

local function dropHeldModel(player: Player)
	local held = player.Character and player.Character:FindFirstChild("HeldPet")
	if held then
		held:Destroy()
	end
end

-- Drops the held pet's model when that pet is no longer in the bag (placed, sold).
function InventoryService:DropHeldIfGone(player: Player)
	local session = S.DataService:GetSession(player)
	local uid = session and session.Runtime.HeldPet
	if not session or not uid then
		return
	end
	local pet = session.Data.Pets[uid]
	if not pet or pet.Placed then
		session.Runtime.HeldPet = nil
		dropHeldModel(player)
	end
end

-- Puts away whatever the player holds (pet or egg).
function InventoryService:StopHolding(player: Player)
	local session = S.DataService:GetSession(player)
	if session then
		session.Runtime.HeldPet = nil
	end
	dropHeldModel(player)
	S.HatchService:StopHolding(player)
end

function InventoryService:HoldPet(player: Player, uid: string): (boolean, string?)
	local session = S.DataService:GetSession(player)
	local pet = session and session.Data.Pets[uid]
	if not session or not pet then
		return false, "That pet is gone"
	end
	if pet.Placed then
		return false, "That pet is on your base. Use the Pets button to take it back."
	end
	InventoryService:StopHolding(player)
	session.Runtime.HeldPet = uid
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root then
		return true, nil
	end
	local def = Aliens.ById[pet.Id]
	local model = AssetLibrary.alien(pet.Id, pet.Mutation)
	model.Name = "HeldPet"
	model:SetAttribute("PetUid", uid)
	model:SetAttribute("DisplayName", (if pet.Huge then "Huge " else "") .. AlienModel.displayName(pet.Id, pet.Mutation))
	local mult = Weights.incomeMult(def and def.Rarity or "Common", pet.Weight)
	model:ScaleTo(HELD_SCALE * (if pet.Huge then Aliens.HugeScale * 0.6 else 1) * Weights.visualScale(mult))
	local _, size = model:GetBoundingBox()
	-- Carried in both arms in front of the chest, facing the same way as the player (the
	-- clients pose the arms, see HoldPoseController).
	model:PivotTo(root.CFrame * CFrame.new(0, -0.1, -(root.Size.Z / 2 + size.Z / 2 + 0.35)))
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end
	model.Parent = character
	return true, nil
end

-- What a pet sells for at the Pet Trader.
function InventoryService:PetValue(player: Player, pet): number
	local data = S.DataService:GetData(player)
	return Aliens.income(pet) * Economy.PetSellSeconds * S.BoostService:GetBaseCashMultiplier(player)
		* Upgrades.multiplier(data and data.Upgrades, "PetSell")
end

function InventoryService:SellPet(player: Player, uid: string): (boolean, string?)
	local data = S.DataService:GetData(player)
	local pet = data and data.Pets[uid]
	if not data or not pet then
		return false, "That pet is gone"
	end
	local value = InventoryService:PetValue(player, pet)
	if InventoryService:HeldPet(player) == uid then
		InventoryService:StopHolding(player)
	end
	data.Pets[uid] = nil
	S.BackpackService:GiveCash(player, value, "SellPet")
	changedBase(player)
	local def = Aliens.ById[pet.Id]
	return true, `Sold {def and def.Name or "pet"} for {Format.cash(value)}`
end

-- Every pet in the bag (pets on your base stay). Returns how many and the cash.
function InventoryService:BagPets(player: Player): ({ string }, number)
	local data = S.DataService:GetData(player)
	local uids, total = {}, 0
	for uid, pet in (data and data.Pets or {}) do
		if not pet.Placed then
			table.insert(uids, uid)
			total += InventoryService:PetValue(player, pet)
		end
	end
	return uids, total
end

function InventoryService:SellAllPets(player: Player): (boolean, string?)
	local data = S.DataService:GetData(player)
	local uids, total = InventoryService:BagPets(player)
	if not data or #uids == 0 then
		return false, "You have no pets in your bag to sell"
	end
	InventoryService:StopHolding(player)
	for _, uid in uids do
		data.Pets[uid] = nil
	end
	S.BackpackService:GiveCash(player, total, "SellPet")
	S.AnalyticsService:Custom(player, "SellAllPets", #uids)
	changedBase(player)
	return true, `Sold {#uids} pet{if #uids == 1 then "" else "s"} for {Format.cash(total)}`
end

function InventoryService:UseItem(player: Player, itemId: string): (boolean, string?)
	local data = S.DataService:GetData(player)
	local def = Items.ById[itemId]
	if not data or not def or (data.Items[itemId] or 0) <= 0 then
		return false, "You don't have that"
	end
	local message = `{def.Name}: {def.Description}!`
	if def.Kind == "Hatch" then
		if S.HatchService:SpeedUp(player, def.HatchSeconds or 300) == 0 then
			return false, "No eggs are hatching right now"
		end
	elseif def.Kind == "Boost" and def.Boost then
		-- Long Brew (upgrade tree) makes potions last longer.
		local minutes = (def.Minutes or 10) * Upgrades.multiplier(data.Upgrades, "PotionTime")
		S.BoostService:AddPersonalBoost(player, def.Boost, minutes)
		if def.Boost == "Speed" then
			S.UpgradeService:ApplyWalkSpeed(player)
		elseif def.Boost == "Magnet" then
			player:SetAttribute("CoinMagnet", S.CoinService:MagnetRange(player))
		end
		local desc = string.gsub(def.Description, "for %d+ min", "for " .. math.floor(minutes + 0.5) .. " min")
		message = `{def.Name}: {desc}!`
	elseif def.Kind == "Charm" and def.Charm then
		local charms = data.Flags.Charms or {}
		data.Flags.Charms = charms
		charms[def.Charm] = (charms[def.Charm] or 0) + 1
		message = `{def.Name} is on! It works on your next hatch.`
	elseif def.Kind == "Spray" then
		local ok, text = S.WeatherService:SprayEgg(player)
		if not ok then
			return false, text
		end
		message = text or message
	elseif def.Kind == "Bomb" then
		local ok, text = S.SweepService:Blast(player, def.Radius or 24)
		if not ok then
			return false, text
		end
		message = text or message
	elseif def.Kind == "Map" then
		local ok, text = S.DropService:StartTreasure(player)
		if not ok then
			return false, text
		end
		message = text or message
	elseif def.Kind == "Totem" then
		local ok, text = S.WeatherService:Totem(player, def.Minutes or 5)
		if not ok then
			return false, text
		end
		message = text or message
	end
	data.Items[itemId] -= 1
	data.Stats.ItemsUsed = (data.Stats.ItemsUsed or 0) + 1 -- quests
	if data.Items[itemId] <= 0 then
		data.Items[itemId] = nil
	end
	InventoryService:Touch(player)
	S.AnalyticsService:Custom(player, "ItemUsed", 1, { Item = itemId })
	return true, message
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
		InventoryService:StopHolding(player)
		return S.HatchService:Hold(player, uid)
	end,
	-- Hold a pet from the bag out in front of you.
	HoldPet = function(player, uid)
		return InventoryService:HoldPet(player, uid)
	end,
	-- Put down the egg carried on your head (EggService).
	DropEgg = function(player)
		return S.EggService:DropCarried(player)
	end,
	StopHolding = function(player)
		InventoryService:StopHolding(player)
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
			return false, "No eggs in your bag. Sweep leaves to find some!"
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
	-- One more pet slot for cash (Economy.SlotCashPrices).
	BuySlot = function(player)
		local data = S.DataService:GetData(player)
		if not data then
			return false, "Still loading"
		end
		local bought = data.Flags.CashSlots or 0
		local price = Economy.SlotCashPrices[bought + 1]
		if not price then
			return false, "You bought every cash slot. Rebirth for more!"
		end
		if not S.BackpackService:TrySpend(player, price, "PetSlot") then
			return false, `You need {Format.cash(price)}`
		end
		data.Flags.CashSlots = bought + 1
		S.AlienService:RefreshBase(player)
		S.StateService:Mark(player)
		return true, "+1 pet slot!"
	end,
	EquipBest = function(player)
		return InventoryService:EquipBest(player)
	end,
	SellPet = function(player, uid)
		return InventoryService:SellPet(player, uid)
	end,
	-- Pet Trader (TraderService checks you're at one): sell what you hold, or every bag pet.
	SellHeld = function(player)
		if not S.TraderService:IsNear(player) then
			return false, "Talk to the Pet Trader on your base"
		end
		local uid = InventoryService:HeldPet(player)
		if not uid then
			return false, "Hold a pet out first: pick one in your bag"
		end
		return InventoryService:SellPet(player, uid)
	end,
	SellAllPets = function(player)
		if not S.TraderService:IsNear(player) then
			return false, "Talk to the Pet Trader on your base"
		end
		return InventoryService:SellAllPets(player)
	end,
	-- "How much is this worth?": the held pet, or the whole bag with arg "All".
	Appraise = function(player, arg)
		local data = S.DataService:GetData(player)
		if not data then
			return false, "Still loading"
		end
		if arg == "All" then
			local uids, total = InventoryService:BagPets(player)
			if #uids == 0 then
				return false, "You have no pets in your bag"
			end
			return true, `{#uids} pet{if #uids == 1 then "" else "s"} for {Format.cash(total)}`
		end
		local uid = InventoryService:HeldPet(player)
		local pet = uid and data.Pets[uid]
		if not pet then
			return false, "You're not holding a pet"
		end
		local name = (if pet.Huge then "Huge " else "") .. AlienModel.displayName(pet.Id, pet.Mutation)
		return true, `{name}|{Format.cash(InventoryService:PetValue(player, pet))}`
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
