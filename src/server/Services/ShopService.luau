--!strict
-- Robux purchases: idempotent ProcessReceipt, gamepass checks, gifting, and what every
-- product grants. Products with Id 0 aren't created yet: their buttons stay hidden.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Tools = require(Shared.Config.Tools)

local ShopService = {}

local S: any
-- buyer -> pending gift choice, set when the server opens the purchase prompt.
local pendingGifts: { [Player]: { productId: number, toUserId: number, at: number } } = {}

local function notify(player: Player, text: string, kind: string?)
	Net.fire("Notify", player, text, kind or "Good")
end

local function cashPackAmount(player: Player, product): number
	local data = S.DataService:GetData(player)
	local income = S.AlienService:GetIncomePerSec(player)
	local nextTier = math.min((data and data.ToolTier or 1) + 1, Tools.MaxTier)
	local floor = Tools.get(nextTier).Price * (product.FloorFactor or 1)
	return math.max(income * (product.Seconds or 600), floor, 100)
end

-- What each product does. Runs without yielding so a receipt can't be granted twice.
local GRANTS: { [string]: (product: any, buyer: Player, recipient: Player) -> () } = {
	StarterPack = function(_product, _buyer, recipient)
		local data = S.DataService:GetData(recipient)
		local pack = Economy.StarterPack
		data.Flags.StarterPackBought = true
		S.BackpackService:GiveCash(recipient, pack.Cash, "StarterPack", Enum.AnalyticsEconomyTransactionType.IAP)
		S.BoostService:AddPersonalBoost(recipient, "Cash2x", pack.Cash2xMinutes)
		S.EggService:GiveEgg(recipient, pack.EggRarity)
		notify(recipient, `Starter Pack: cash, an {pack.EggRarity} egg and {pack.Cash2xMinutes} min of 2x cash!`)
	end,
	ServerLuck = function(product, buyer)
		S.BoostService:AddServerLuck(product.Mult, product.Minutes or Economy.ServerLuckMinutes, buyer)
	end,
	MeteorShower = function(_product, buyer)
		S.EventService:TriggerShower(buyer)
	end,
	SkipHatch = function(product, _buyer, recipient)
		S.HatchService:Skip(recipient, product.Rarity)
	end,
	EggPack = function(product, _buyer, recipient)
		for _ = 1, product.Count or 1 do
			S.EggService:GiveEgg(recipient, product.Rarity)
		end
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
		S.ToolService:Rent(recipient, product.Tier)
	end,
	CashPack = function(product, _buyer, recipient)
		local amount = cashPackAmount(recipient, product)
		S.BackpackService:GiveCash(recipient, amount, product.Key, Enum.AnalyticsEconomyTransactionType.IAP)
	end,
	SkipRebirth = function(_product, _buyer, recipient)
		S.RebirthService:DoRebirth(recipient, false)
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
	if recipient ~= buyer then
		notify(recipient, `🎁 {buyer.DisplayName} gifted you {product.Name}!`)
		notify(buyer, `Gift sent to {recipient.DisplayName}!`)
		Net.fireAll("Announce", `🎁 {buyer.DisplayName} gifted {product.Name} to {recipient.DisplayName}!`, "Gift")
		S.DataService:SaveNow(recipient)
	end
	if S.DataService:SaveNow(buyer) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function applyPassEffects(player: Player)
	S.AlienService:RefreshBase(player)
	S.StateService:Mark(player)
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
				data.Gamepasses[pass.Key] = owns or nil
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
		return true, nil
	end
	local product = Products.ProductByKey[key]
	if not product or product.Id == 0 then
		return false, "Coming soon!"
	end

	local recipient = player
	if giftToUserId ~= nil then
		if type(giftToUserId) ~= "number" or not product.Giftable then
			return false, "This can't be gifted"
		end
		local target = Players:GetPlayerByUserId(giftToUserId)
		if not target or target == player or not S.DataService:GetSession(target) then
			return false, "That player isn't here"
		end
		recipient = target
		pendingGifts[player] = { productId = product.Id, toUserId = giftToUserId, at = os.clock() }
	else
		pendingGifts[player] = nil
	end

	local targetData = S.DataService:GetData(recipient)
	if product.Kind == "StarterPack" and targetData.Flags.StarterPackBought then
		return false, "Already bought"
	elseif product.Kind == "ToolSkip" and targetData.ToolTier + 1 ~= product.Tier then
		return false, "Not the next tool"
	elseif product.Kind == "VehicleRental" and S.ToolService:GetEffectiveTier(recipient) >= product.Tier then
		return false, "Already unlocked"
	end
	MarketplaceService:PromptProductPurchase(player, product.Id)
	return true, nil
end

function ShopService:Init(services)
	S = services
	MarketplaceService.ProcessReceipt = processReceipt
	Net.onInvoke("PromptPurchase", promptPurchase)
	S.DataService.ProfileLoaded:Connect(function(player)
		checkPasses(player)
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
			notify(player, `{pass.Name} is yours!`)
			S.AnalyticsService:Custom(player, "GamepassPurchase", pass.Price, { Pass = pass.Key })
			Net.fireAll("Announce", `⭐ {player.DisplayName} got {pass.Name}!`, "Gift")
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
