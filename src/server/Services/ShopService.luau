--!strict
-- Robux purchases: idempotent ProcessReceipt, gamepass checks, gifting, and what every
-- product grants. Products with Id 0 aren't created yet: their buttons stay hidden.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local LimitedEgg = require(Shared.Config.LimitedEgg)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Tools = require(Shared.Config.Tools)
local Zones = require(Shared.Config.Zones)

local ShopService = {}

local S: any
-- buyer -> pending gift choice, set when the server opens the purchase prompt.
local pendingGifts: { [Player]: { productId: number, toUserId: number, at: number } } = {}

local function notify(player: Player, text: string, kind: string?)
	Net.fire("Notify", player, text, kind or "Good")
end

local CASH_PACKS = { "Cash1", "Cash2", "Cash3", "Cash4", "Cash5" }
-- Dev Academy tip ("build many purchase pathways"): the 3rd "not enough cash" in a session
-- opens the Shop at Cash, then every SHORTFALL_EVERY more, at most SHORTFALL_MAX_OPENS
-- times a session and never twice within SHOP_OPEN_COOLDOWN seconds.
local SHORTFALL_OPENS_AT = 3
local SHORTFALL_EVERY = 5
local SHORTFALL_MAX_OPENS = 3
local SHOP_OPEN_COOLDOWN = 180

-- The next thing the player is saving up for: next tool, else the next car they can buy,
-- else a slice of the rebirth cost.
local function nextGoalPrice(data): number
	if data.ToolTier < Tools.MaxTier then
		return Tools.get(data.ToolTier + 1).Price
	end
	for _, car in Tools.Vehicles do
		if not Tools.hasVehicle(data.Vehicles, car.Id) and data.Rebirths >= car.RequiredRebirths then
			return car.Price
		end
	end
	return BigNum.toNumber(S.RebirthService:GetCost(data)) * 0.1
end

-- Cash packs scale with the player: Seconds of their earnings (pets + selling), and at
-- least FloorFactor x the next thing they're saving for.
local function cashPackAmount(player: Player, product): number
	local data = S.DataService:GetData(player)
	if not data then
		return 100
	end
	local rate = S.AlienService:GetIncomePerSec(player) + S.BackpackService:GetEarnRate(player)
	local floor = nextGoalPrice(data) * (product.FloorFactor or 1)
	return math.floor(math.max(rate * (product.Seconds or 600), floor, 100))
end

-- Same scaling as cash packs, for free rewards (daily, playtime, group).
function ShopService:CashFor(player: Player, seconds: number, floorFactor: number?): number
	return cashPackAmount(player, { Seconds = seconds, FloorFactor = floorFactor or 0 })
end

function ShopService:GetCashPackAmounts(player: Player): { [string]: number }
	local amounts = {}
	for _, key in CASH_PACKS do
		local def = Products.ProductByKey[key]
		if def and def.Id ~= 0 then
			amounts[key] = cashPackAmount(player, def)
		end
	end
	-- What the Starter Pack's cash comes to for this player (shown on its banner).
	local pack = Economy.StarterPack
	amounts.StarterPack = cashPackAmount(player, { Seconds = pack.CashSeconds, FloorFactor = pack.CashFloor })
	return amounts
end

-- The player tried to buy something they can't afford: open the purchase prompt for the
-- smallest cash pack that covers the gap (or the biggest one if none does).
function ShopService:OfferCashFor(player: Player, _shortfall: any)
	local session = S.DataService:GetSession(player)
	if not session then
		return
	end
	local runtime = session.Runtime
	local now = os.clock()
	local count = (runtime.Shortfalls or 0) + 1
	runtime.Shortfalls = count
	local due = count == SHORTFALL_OPENS_AT or (count > SHORTFALL_OPENS_AT and (count - SHORTFALL_OPENS_AT) % SHORTFALL_EVERY == 0)
	if not due or (runtime.ShopOpens or 0) >= SHORTFALL_MAX_OPENS or now - (runtime.ShopOpenedAt or -math.huge) < SHOP_OPEN_COOLDOWN then
		return
	end
	runtime.ShopOpens = (runtime.ShopOpens or 0) + 1
	runtime.ShopOpenedAt = now
	S.AnalyticsService:Custom(player, "CashShortfallOffer", 0, { Product = "OpenShop" })
	Net.fire("OpenShop", player, "Cash")
end

-- The zone bought eggs come from: the best one you've opened (same pets free players find).
local function bestZone(player: Player): string
	local data = S.DataService:GetData(player)
	local zone = "Landing"
	for _, z in Zones.List do
		if data and data.ZonesUnlocked[z.Id] then
			zone = z.Id
		end
	end
	return zone
end

-- VIP daily gift: once every Economy.VIPGift.Hours, given on join and while playing.
local function vipGift(player: Player)
	local data = S.DataService:GetData(player)
	local gift = Economy.VIPGift
	if not data or not data.Gamepasses.VIP or os.time() - (data.Flags.VIPGiftAt or 0) < gift.Hours * 3600 then
		return
	end
	data.Flags.VIPGiftAt = os.time()
	for item, count in gift.Items do
		S.InventoryService:AddItem(player, item, count)
	end
	if gift.Spins > 0 then
		S.RewardService:AddSpins(player, gift.Spins)
	end
	S.StateService:Mark(player)
	notify(player, "VIP daily gift: 2 Luck Potions, a Cash Potion and a free wheel spin!")
end

local function applyPassEffects(player: Player)
	local data = S.DataService:GetData(player)
	player:SetAttribute("VIP", data and data.Gamepasses.VIP == true or nil)
	S.AlienService:RefreshBase(player)
	S.UpgradeService:ApplyWalkSpeed(player)
	vipGift(player)
	S.StateService:Mark(player)
end

-- What each product does. Runs without yielding so a receipt can't be granted twice.
local GRANTS: { [string]: (product: any, buyer: Player, recipient: Player) -> () } = {
	StarterPack = function(_product, _buyer, recipient)
		local data = S.DataService:GetData(recipient)
		local pack = Economy.StarterPack
		data.Flags.StarterPackBought = true
		local cash = cashPackAmount(recipient, { Seconds = pack.CashSeconds, FloorFactor = pack.CashFloor })
		S.BackpackService:GiveCash(recipient, cash, "StarterPack", Enum.AnalyticsEconomyTransactionType.IAP)
		S.BoostService:AddPersonalBoost(recipient, "Cash2x", pack.Cash2xMinutes)
		S.InventoryService:AddEgg(recipient, pack.EggRarity, "Landing", true, true)
		S.InventoryService:AddItem(recipient, "LuckPotion", pack.LuckPotions)
		notify(recipient, `Starter Pack: +{Format.cash(cash)}, an {pack.EggRarity} egg and {pack.LuckPotions} Luck Potions (in your bag), and {pack.Cash2xMinutes} min of 2x cash!`)
	end,
	ServerLuck = function(product, buyer)
		S.BoostService:AddServerLuck(product.Mult, product.Minutes or Economy.ServerLuckMinutes, buyer)
	end,
	MeteorShower = function(_product, buyer)
		S.EventService:TriggerShower(buyer)
	end,
	SkipHatch = function(product, buyer, recipient)
		-- The egg the buyer picked on their base (only when they bought it for themselves).
		local session = S.DataService:GetSession(buyer)
		local target = if session and recipient == buyer then session.Runtime.SkipTarget else nil
		if session then
			session.Runtime.SkipTarget = nil
		end
		S.HatchService:Skip(recipient, product.Rarity, target)
	end,
	EggPack = function(product, _buyer, recipient)
		local zone = bestZone(recipient)
		for _ = 1, product.Count or 1 do
			S.InventoryService:AddEgg(recipient, product.Rarity, zone, true, true)
		end
		notify(recipient, `{product.Name} added to your bag!`)
	end,
	ToolSkip = function(product, _buyer, recipient)
		local data = S.DataService:GetData(recipient)
		if data.ToolTier < product.Tier then
			S.ToolService:SetTier(recipient, product.Tier)
			notify(recipient, `{Tools.get(product.Tier).Name} unlocked!`)
		else
			-- Already owned (e.g. bought it with cash meanwhile): refund in cash.
			S.BackpackService:GiveCash(recipient, Tools.get(product.Tier).Price, product.Key, Enum.AnalyticsEconomyTransactionType.IAP)
			notify(recipient, "You already had that tool, so you got its price in cash!")
		end
	end,
	VehicleRental = function(product, _buyer, recipient)
		S.ToolService:Rent(recipient, product.Vehicle)
	end,
	VehicleUnlock = function(product, _buyer, recipient)
		local def = Tools.vehicle(product.Vehicle)
		if S.ToolService:GrantVehicle(recipient, product.Vehicle) then
			notify(recipient, `{def and def.Name or "Car"} unlocked! Tap your car slot to drive.`)
		elseif def then
			-- Already owned: refund in cash.
			S.BackpackService:GiveCash(recipient, def.Price, product.Key, Enum.AnalyticsEconomyTransactionType.IAP)
			notify(recipient, "You already had that car, so you got its price in cash!")
		end
	end,
	CashPack = function(product, _buyer, recipient)
		local amount = cashPackAmount(recipient, product)
		S.BackpackService:GiveCash(recipient, amount, product.Key, Enum.AnalyticsEconomyTransactionType.IAP)
		notify(recipient, `+{Format.cash(amount)} cash!`)
	end,
	SkipRebirth = function(_product, _buyer, recipient)
		S.RebirthService:DoRebirth(recipient, false)
	end,
	GiftPass = function(product, _buyer, recipient)
		local data = S.DataService:GetData(recipient)
		local pass = Products.PassByKey[product.Pass or ""]
		if not pass then
			error(`gift product {product.Key} has no pass`)
		end
		if data.Gamepasses[pass.Key] then
			-- Already owned (e.g. the friend left and the gift came back to the buyer): pay out in cash.
			local amount = cashPackAmount(recipient, { Seconds = 1800, FloorFactor = 1.5 })
			S.BackpackService:GiveCash(recipient, amount, product.Key, Enum.AnalyticsEconomyTransactionType.IAP)
			notify(recipient, `You already had {pass.Name}, so you got +{Format.cash(amount)} cash instead!`)
			return
		end
		data.GiftedPasses[pass.Key] = true
		data.Gamepasses[pass.Key] = true
		applyPassEffects(recipient)
	end,
	WheelSpins = function(product, _buyer, recipient)
		local got = S.RewardService:AddSpins(recipient, product.Count or 1)
		notify(recipient, `+{product.Count or 1} wheel spin{if (product.Count or 1) == 1 then "" else "s"}! You have {got} now.`)
	end,
	LimitedEgg = function(product, _buyer, recipient)
		local count = product.Count or 1
		for _ = 1, count do
			S.InventoryService:AddEgg(recipient, LimitedEgg.EggRarity, LimitedEgg.Id, true, true, LimitedEgg.EggMutation)
		end
		notify(recipient, `+{count} {LimitedEgg.Name}{if count == 1 then "" else "s"}! Hatch {if count == 1 then "it" else "them"} from your bag.`)
	end,
	ItemPack = function(product, _buyer, recipient)
		if not product.Item then
			error(`item pack {product.Key} has no item`)
		end
		S.InventoryService:AddItem(recipient, product.Item, product.Count or 1)
		notify(recipient, `{product.Name} added to your bag! Use it from Items.`)
	end,
	MerchantRestock = function(_product, _buyer, recipient)
		S.MerchantService:Restock(recipient)
	end,
	DoubleOffline = function(_product, _buyer, recipient)
		local session = S.DataService:GetSession(recipient)
		local amount = session.Runtime.OfflineReward or (S.AlienService:GetIncomePerSec(recipient) * 600)
		session.Runtime.OfflineReward = nil
		S.BackpackService:GiveCash(recipient, amount, "DoubleOffline", Enum.AnalyticsEconomyTransactionType.IAP)
	end,
}

local function processReceipt(info): Enum.ProductPurchaseDecision
	local buyer = Players:GetPlayerByUserId(info.PlayerId)
	local session = buyer and S.DataService:GetSession(buyer)
	if not buyer or not session then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = session.Data
	local purchaseId = tostring(info.PurchaseId)
	if data.ReceiptsGranted[purchaseId] then
		-- Granted before; just make sure it's saved.
		return if S.DataService:SaveNow(buyer) then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local product = Products.ProductById[info.ProductId]
	if not product then
		warn(`[ShopService] receipt for unknown product id {info.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local recipient = buyer
	local gift = pendingGifts[buyer]
	if gift and gift.productId == info.ProductId and os.clock() - gift.at <= Products.GiftWindowSeconds then
		pendingGifts[buyer] = nil
		local target = Players:GetPlayerByUserId(gift.toUserId)
		if target and S.DataService:GetSession(target) then
			recipient = target
		else
			notify(buyer, "Your gift's player left, so it went to you instead.", "Info")
		end
	end

	local ok, err = pcall(GRANTS[product.Kind], product, buyer, recipient)
	if not ok then
		warn(`[ShopService] grant {product.Key} failed: {err}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	S.DataService:RecordReceipt(data, purchaseId, tostring(recipient.UserId))
	S.StateService:Mark(recipient)
	S.AnalyticsService:Custom(buyer, "RobuxPurchase", product.Price, { Product = product.Key, Gift = tostring(recipient ~= buyer) })
	S.AnalyticsService:Purchased(buyer, product.Key, product.Price, product.Kind == "WheelSpins")
	-- The purchase celebration (PurchaseController): instant "you got it" feedback.
	if recipient ~= buyer then
		Net.fire("Purchased", recipient, product.Key, { From = buyer.DisplayName })
		Net.fire("Purchased", buyer, product.Key, { To = recipient.DisplayName })
		S.DataService:SaveNow(recipient)
	else
		Net.fire("Purchased", buyer, product.Key, {})
	end
	if S.DataService:SaveNow(buyer) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function checkPasses(player: Player)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	for _, pass in Products.Gamepasses do
		if pass.Id ~= 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
			if ok then
				data.Gamepasses[pass.Key] = (owns or data.GiftedPasses[pass.Key]) or nil
			elseif data.GiftedPasses[pass.Key] then
				data.Gamepasses[pass.Key] = true
			end
		end
	end
	applyPassEffects(player)
end

-- Validates and opens a purchase prompt. giftToUserId makes it a gift.
local function promptPurchase(player: Player, key: any, giftToUserId: any): (boolean, string?)
	if type(key) ~= "string" then
		return false, "Bad request"
	end
	local session = S.DataService:GetSession(player)
	if not session then
		return false, "Still loading"
	end
	local pass = Products.PassByKey[key]
	if pass then
		if pass.Id == 0 then
			return false, "Coming soon!"
		end
		if session.Data.Gamepasses[key] then
			return false, "You already own this"
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.Id)
		S.AnalyticsService:PromptShown(player, pass.Key)
		return true, nil
	end
	-- Server Luck is one card: always sell the next level up (the price climbs with it).
	if key == "ServerLuck" or string.find(key, "^ServerLuck%d") then
		local def, why = S.BoostService:NextLuckProduct()
		if not def then
			return false, why
		end
		key = def.Key
	end
	local product = Products.ProductByKey[key]
	if not product or product.Id == 0 then
		return false, "Coming soon!"
	end

	local recipient = player
	if product.Kind == "GiftPass" and giftToUserId == nil then
		return false, "Pick a friend to gift this to"
	end
	if giftToUserId ~= nil then
		if type(giftToUserId) ~= "number" or not product.Giftable then
			return false, "This can't be gifted"
		end
		local target = Players:GetPlayerByUserId(giftToUserId)
		if not target or target == player or not S.DataService:GetSession(target) then
			return false, "That player isn't here"
		end
		recipient = target
	end

	local targetData = S.DataService:GetData(recipient)
	-- Skip Rebirth is priced by rebirth: always sell the tier that fits whoever gets it
	-- (gifting it to a friend prompts the friend's tier, not yours).
	if product.Kind == "SkipRebirth" then
		local fits = Products.skipRebirthFor(targetData.Rebirths)
		if not fits then
			return false, "Coming soon!"
		end
		product = fits
	end
	if recipient ~= player then
		pendingGifts[player] = { productId = product.Id, toUserId = recipient.UserId, at = os.clock() }
	else
		pendingGifts[player] = nil
	end

	if product.Kind == "StarterPack" and targetData.Flags.StarterPackBought then
		return false, "Already bought"
	elseif product.Kind == "StarterPack" and not Products.starterPackEnds(targetData, os.time()) then
		return false, "The Starter Pack has left the shop"
	elseif product.Kind == "LimitedEgg" and not LimitedEgg.onSale(os.time()) then
		return false, `The {LimitedEgg.Name} has left the shop`
	elseif product.Kind == "ToolSkip" and targetData.ToolTier + 1 ~= product.Tier then
		return false, "Not the next tool"
	elseif (product.Kind == "VehicleRental" or product.Kind == "VehicleUnlock") and S.ToolService:OwnsVehicle(recipient, product.Vehicle) then
		return false, "Already unlocked"
	elseif product.Kind == "VehicleRental" or product.Kind == "VehicleUnlock" then
		local car = Tools.vehicle(product.Vehicle or "")
		if car and targetData.Rebirths < car.RequiredRebirths then
			return false, `Rebirth {car.RequiredRebirths} needed for the {car.Name}`
		elseif targetData.ToolTier < Economy.CarRobuxMinTier then
			-- Cars skip the whole tool ladder, so Robux cars wait until you've climbed a bit.
			return false, `Get the {Tools.get(Economy.CarRobuxMinTier).Name} first`
		end
	elseif product.Kind == "SkipRebirth" then
		-- Skip Rebirth finishes a rebirth you've worked toward instead of skipping one outright.
		local need = Economy.rebirthCost(targetData.Rebirths) * Economy.SkipRebirthMinShare
		if BigNum.lt(targetData.Cash, need) then
			return false, `Save up {Format.cash(need)} first ({math.floor(Economy.SkipRebirthMinShare * 100)}% of the rebirth)`
		end
	elseif product.Kind == "MerchantRestock" and not S.MerchantService:CanRestock() then
		return false, "The merchant isn't here right now"
	elseif product.Kind == "GiftPass" and targetData.Gamepasses[product.Pass or ""] then
		return false, `{recipient.DisplayName} already owns this`
	end
	MarketplaceService:PromptProductPurchase(player, product.Id)
	S.AnalyticsService:PromptShown(player, product.Key, product.Kind == "WheelSpins")
	return true, nil
end

-- Opens a purchase prompt from another service (e.g. Skip Hatch on one egg).
function ShopService:Prompt(player: Player, key: string, giftToUserId: number?): (boolean, string?)
	return promptPurchase(player, key, giftToUserId)
end

function ShopService:Init(services)
	S = services
	MarketplaceService.ProcessReceipt = processReceipt
	Net.onInvoke("PromptPurchase", function(player: Player, key: any, giftToUserId: any)
		-- A Skip Hatch bought straight from the shop isn't for an egg picked earlier (a
		-- cancelled Skip Hatch prompt would otherwise still point at that egg).
		local session = S.DataService:GetSession(player)
		if session and type(key) == "string" and string.find(key, "^SkipHatch") then
			session.Runtime.SkipTarget = nil
		end
		return promptPurchase(player, key, giftToUserId)
	end)
	S.DataService.ProfileLoaded:Connect(function(player, session)
		checkPasses(player)
		-- The Starter Pack's clock starts the first time you load in while still new to it.
		local data = session.Data
		local pack = Economy.StarterPack
		if data.Flags.StarterPackEnds == nil and not data.Flags.StarterPackBought and data.ToolTier < pack.HideAtToolTier and data.Rebirths == 0 then
			data.Flags.StarterPackEnds = os.time() + pack.Hours * 3600
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		pendingGifts[player] = nil
	end)
end

function ShopService:Start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local pass = Products.PassById[passId]
		local data = S.DataService:GetData(player)
		if purchased and pass and data then
			data.Gamepasses[pass.Key] = true
			applyPassEffects(player)
			Net.fire("Purchased", player, pass.Key, {})
			S.AnalyticsService:Custom(player, "GamepassPurchase", pass.Price, { Pass = pass.Key })
			S.AnalyticsService:Purchased(player, pass.Key, pass.Price)
		elseif not purchased and pass then
			S.AnalyticsService:Custom(player, "PurchaseCancelled", pass.Price, { Product = pass.Key })
		end
	end)
	-- Closed product prompts (bought ones are counted in processReceipt).
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		local player = Players:GetPlayerByUserId(userId)
		local product = Products.ProductById[productId]
		if player and product and not purchased then
			S.AnalyticsService:Custom(player, "PurchaseCancelled", product.Price, { Product = product.Key })
		end
	end)

	-- VIP daily gift for VIPs who stay on past the next one.
	task.spawn(function()
		while true do
			task.wait(600)
			for player in S.DataService:GetSessions() do
				vipGift(player)
			end
		end
	end)

	local missing = 0
	for _, def in Products.Products do
		if def.Id == 0 then
			missing += 1
		end
	end
	for _, def in Products.Gamepasses do
		if def.Id == 0 then
			missing += 1
		end
	end
	if missing > 0 then
		warn(`[ShopService] {missing} products/gamepasses have no ID yet (Config/Products). Their buttons are hidden until IDs are added.`)
	end
end

return ShopService
