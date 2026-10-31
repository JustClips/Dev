--!strict
-- Shop (Robux things only). Dev, 2026-10-31, copied from a reference shop: ONE scrolling
-- list (not pages) with sections one under the other, each under a centred "-- MONEY --"
-- heading in its colour:
--   Featured - the limited egg banner (the pets you can get with their odds, buy cells
--              biggest first, each with a gift button), the Starter Pack, and limited
--              offers the game made you in the last few minutes
--   Eggs     - one card per rarity (Epic .. Cosmic); Buy opens a "How many?" picker
--              (x1 / x3 MOST POPULAR / x10 BEST VALUE), then hatch skips for eggs growing
--   Passes   - gamepasses, cheapest first, owned ones last
--   Boosts   - the Server Luck card (level now > next, shared timer) and other server buys
--   Potions  - small buys that go to your bag
--   Money    - cash packs, the next tool skip, Skip Rebirth
-- The buttons to the right of the panel jump the list to their section. A card is a big
-- picture, one line ("+$24K", "2x CASH"), a purple gift button and a green Robux button.
-- Timers read "1d 22h 12m 5s". Layout templates come from tools/gen_ui.py shop().
-- Free / cash things (tools, cars) are in the Gear window and base skins in the base picker.
-- Robux items whose ID is still 0 are hidden. The rail Shop button and the Featured button
-- show a badge while a special offer is up.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local ModelView = require(Client.ModelView)
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Aliens = require(Shared.Config.Aliens)
local AssetLibrary = require(Shared.AssetLibrary)
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local LimitedEgg = require(Shared.Config.LimitedEgg)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Tools = require(Shared.Config.Tools)

local GREY = Color3.fromRGB(166, 174, 194)
-- Robux buttons are green with white text (Dev's reference).
local ROBUX = Color3.fromRGB(76, 209, 55)
local WHITE = Color3.new(1, 1, 1)
local YELLOW = "#FFE34D"

local LUCK_H = 132 -- SHOP_LUCK_H in tools/gen_ui.py
-- The limited egg's small pet cards, most common first; the rarest gets the big card.
local PET_SIZES = { 64, 64, 75, 88, 100 }

type Tile = {
	Hi: string?, -- the yellow part of the card's line ("+$24K", "2x")
	Lo: string?, -- the white part ("CASH")
	Price: string,
	PriceColor: Color3?,
	Enabled: boolean,
	OnBuy: (() -> ())?,
	GiftKey: string?,
	Icon: string?,
	Rarity: string?, -- egg cards show the 3D egg
	Tag: string?,
}

type Chip = { Icon: string?, Rarity: string?, Caption: string }

type Section = {
	Key: string,
	Title: string,
	Icon: string,
	Heading: Color3, -- heading and nav label colour
	Card: Color3, -- card colour
}

local SECTIONS: { Section } = {
	{ Key = "Featured", Title = "Featured", Icon = "Icon_Gift", Heading = Color3.fromRGB(255, 212, 59), Card = Color3.fromRGB(255, 77, 94) },
	{ Key = "Eggs", Title = "Eggs", Icon = "Icon_Egg", Heading = Color3.fromRGB(255, 126, 182), Card = Color3.fromRGB(255, 95, 162) },
	{ Key = "Passes", Title = "Passes", Icon = "Icon_Star", Heading = Color3.fromRGB(197, 155, 255), Card = Color3.fromRGB(155, 107, 255) },
	{ Key = "Boosts", Title = "Boosts", Icon = "Icon_Luck", Heading = Color3.fromRGB(255, 154, 60), Card = Color3.fromRGB(255, 128, 48) },
	{ Key = "Potions", Title = "Items", Icon = "Icon_PotionLuck", Heading = Color3.fromRGB(94, 230, 200), Card = Color3.fromRGB(46, 184, 160) },
	{ Key = "Money", Title = "Money", Icon = "Icon_Cash", Heading = Color3.fromRGB(107, 227, 74), Card = Color3.fromRGB(76, 209, 55) },
	-- Codes: a fixed box at the end of the list (gen_ui shop(), CodesController).
	{ Key = "Codes", Title = "Codes", Icon = "Icon_Quest", Heading = Color3.fromRGB(127, 200, 255), Card = Color3.fromRGB(62, 142, 240) },
}
-- Old section names other code may still open.
local ALIAS = { Deals = "Featured", Offers = "Featured", Cash = "Money", Tools = "Money" }

local PASS_INFO: { [string]: { Icon: string, Hi: string, Lo: string, Tag: string? } } = {
	FastWalk = { Icon = "Icon_Speed", Hi = "+30%", Lo = "SPEED", Tag = "NEW" },
	BigBag = { Icon = "Icon_Backpack", Hi = "2x", Lo = "BAG", Tag = "NEW" },
	Cash2x = { Icon = "Icon_Cash", Hi = "2x", Lo = "CASH" },
	Carry3 = { Icon = "Icon_Egg", Hi = "CARRY", Lo = "3 EGGS" },
	AutoSweep = { Icon = "Icon_Auto", Hi = "AUTO", Lo = "SWEEP" },
	Lucky = { Icon = "Icon_LuckyClover", Hi = "+50%", Lo = "LUCK", Tag = "NEW" },
	ExtraSlots = { Icon = "Icon_Alien", Hi = "+3", Lo = "PET SLOTS" },
	SellAnywhere = { Icon = "Icon_Sell", Hi = "SELL", Lo = "ANYWHERE" },
	FasterHatch = { Icon = "Icon_Timer", Hi = "2x", Lo = "HATCH SPEED" },
	VIP = { Icon = "Icon_Star", Hi = "", Lo = "VIP" },
}

local EGG_TIERS = { "Epic", "Legendary", "Mythic", "Cosmic" }

-- Small buys that go to your bag, cheapest first.
local POTIONS = {
	{ Key = "LeafBomb3", Icon = "Icon_LeafBomb", Hi = "3x", Lo = "LEAF BOMB" },
	{ Key = "LuckyClover1", Icon = "Icon_LuckyClover", Hi = "", Lo = "LUCKY CLOVER" },
	{ Key = "LuckPotion3", Icon = "Icon_PotionLuck", Hi = "3x", Lo = "LUCK POTION" },
	{ Key = "CashPotion3", Icon = "Icon_PotionCash", Hi = "3x", Lo = "CASH POTION" },
	{ Key = "MutationSpray1", Icon = "Icon_MutationSpray", Hi = "", Lo = "MUTATION SPRAY" },
	{ Key = "SuperLuckPotion1", Icon = "Icon_PotionSuperLuck", Hi = "3x", Lo = "LUCK 15 MIN" },
	{ Key = "MegaCashPotion1", Icon = "Icon_PotionMegaCash", Hi = "3x", Lo = "CASH 15 MIN" },
	{ Key = "HugeCharm1", Icon = "Icon_HugeCharm", Hi = "10x", Lo = "HUGE CHANCE" },
}

local ShopController = {}

local C: any
local gui: ScreenGui
local list: ScrollingFrame
local scale: UIScale
local templates: { [string]: GuiObject } = {}
local giftPicker: Frame
local giftList: ScrollingFrame
local giftTemplate: TextButton
local giftEmpty: TextLabel
local qtyPicker: Frame
local qtyOptions: Frame
local shopBadge: Frame?
local nav: Frame
local navButtons: { [string]: GuiButton } = {}
local headings: { [string]: GuiObject } = {}
local luckCard: Frame? = nil
-- Labels that count down every second while the shop is open.
local timers: { () -> boolean } = {}

local function toast(ok: boolean, message: string?)
	if message and message ~= "" then
		C.HudController:Toast(message, if ok then "Good" else "Bad")
	end
end

local function prompt(key: string, giftTo: number?)
	local ok, message = Net.func("PromptPurchase"):InvokeServer(key, giftTo)
	if not ok then
		toast(false, message)
	end
end

-- "1d 22h 12m 5s" (the reference's timer style).
local function leftText(seconds: number, gone: string): string
	return if seconds > 0 then Format.dhms(seconds) else gone
end

local function robuxPrice(price: number): string
	return `{Ui.ROBUX} {price}`
end

local function tint(plate: GuiObject, color: Color3)
	plate.BackgroundColor3 = color
	local studs = plate:FindFirstChild("Studs") :: ImageLabel?
	if studs then
		studs.ImageColor3 = color
	end
end

local function setPrice(buy: GuiButton, price: string, color: Color3)
	Ui.setText(buy, price)
	tint(buy, color)
	local label = buy:FindFirstChild("Label") :: TextLabel?
	if label then
		label.TextColor3 = WHITE
	end
end

local function clone(name: string): any
	local object = templates[name]:Clone()
	object.Visible = true
	object:SetAttribute("Built", true)
	return object
end

-- A picture: an item icon, or the 3D egg of a rarity.
local function showPicture(root: Instance, iconName: string?, rarity: string?)
	local icon = root:FindFirstChild("Icon") :: ImageLabel?
	local model = root:FindFirstChild("Model") :: ViewportFrame?
	if rarity and model then
		model.Visible = true
		if icon then
			icon.Visible = false
		end
		ModelView.show(model, AssetLibrary.egg(rarity), "Egg_" .. rarity)
	elseif icon then
		icon.Visible = true
		icon.Image = AssetLibrary.image(iconName or "Icon_Shop")
		if model then
			model.Visible = false
		end
	end
end

local function line(hi: string?, lo: string?): string
	local parts = {}
	if hi and hi ~= "" then
		table.insert(parts, `<font color="{YELLOW}">{hi}</font>`)
	end
	if lo and lo ~= "" then
		table.insert(parts, lo)
	end
	return table.concat(parts, " ")
end

local function productTile(key: string, hi: string?, lo: string?, iconName: string?, tag: string?): Tile?
	local def = Products.ProductByKey[key]
	if not def or def.Id == 0 then
		return nil
	end
	return {
		Hi = hi,
		Lo = lo,
		Price = robuxPrice(def.Price),
		Icon = iconName,
		Enabled = true,
		Tag = tag,
		OnBuy = function()
			prompt(key)
		end,
		GiftKey = if def.Giftable then key else nil,
	}
end

-------------------------------------------------------------------------- gift + quantity pickers

local function openGiftPicker(key: string)
	for _, child in giftList:GetChildren() do
		if child:IsA("TextButton") and child ~= giftTemplate then
			child:Destroy()
		end
	end
	local count = 0
	for _, other in Players:GetPlayers() do
		if other ~= Players.LocalPlayer then
			count += 1
			local button = giftTemplate:Clone()
			button.Name = "Player"
			local label = other.DisplayName
			-- Skip Rebirth costs what the friend's next rebirth costs (the server picks it).
			local def = Products.ProductByKey[key]
			if def and def.Kind == "SkipRebirth" then
				local stats = other:FindFirstChild("leaderstats")
				local rebirths = stats and stats:FindFirstChild("Rebirths") :: IntValue?
				local fits = Products.skipRebirthFor(if rebirths then rebirths.Value else 0)
				if fits then
					label = `{label} · {Ui.ROBUX} {fits.Price}`
				end
			end
			Ui.setText(button, label)
			button.Visible = true
			button.Parent = giftList
			Ui.button(button, function()
				giftPicker.Visible = false
				prompt(key, other.UserId)
			end)
		end
	end
	giftEmpty.Visible = count == 0
	qtyPicker.Visible = false
	giftPicker.Visible = true
end

-- "How many?" for one egg rarity: x1, x3 (MOST POPULAR), x10 (BEST VALUE when it is the
-- cheapest per egg, which it is by design).
local function openQtyPicker(rarity: string)
	for _, child in qtyOptions:GetChildren() do
		if child:GetAttribute("Built") then
			child:Destroy()
		end
	end
	local packs = Products.eggPacks(rarity)
	local cheapest = math.huge
	for _, def in packs do
		cheapest = math.min(cheapest, def.Price / (def.Count or 1))
	end
	for i, def in packs do
		local count = def.Count or 1
		local option = clone("Option")
		option.LayoutOrder = i
		Ui.find(option, "Count").Text = `x{count}`
		local each = math.floor(def.Price / count + 0.5)
		Ui.find(option, "Each").Text = if count > 1 then `{Ui.ROBUX} {each} each` else "Just one"
		local tag = Ui.find(option, "Tag") :: Frame
		local tagText = if count == 3 then "MOST POPULAR" elseif count > 1 and def.Price / count <= cheapest then "BEST VALUE" else nil
		tag.Visible = tagText ~= nil
		if tagText then
			Ui.find(tag, "Label").Text = tagText
		end
		setPrice(Ui.find(option, "Buy"), robuxPrice(def.Price), ROBUX)
		local key = def.Key
		Ui.button(Ui.find(option, "Buy"), function()
			qtyPicker.Visible = false
			prompt(key)
		end)
		option.Parent = qtyOptions
		ModelView.show(Ui.find(option, "Model"), AssetLibrary.egg(rarity), "Egg_" .. rarity)
	end
	Ui.find(qtyPicker, "Header.Title").Text = `How many {rarity} Eggs?`
	giftPicker.Visible = false
	qtyPicker.Visible = true
end

-------------------------------------------------------------------------- pieces

local nextOrder = 0
local function place(object: GuiObject)
	nextOrder += 1
	object.LayoutOrder = nextOrder
	object.Parent = list
end

local function addHeading(section: Section)
	local row = clone("Heading")
	row.Name = "Heading_" .. section.Key
	local title = Ui.find(row, "Title") :: TextLabel
	title.Text = `-- {string.upper(section.Title)} --`
	title.TextColor3 = section.Heading
	headings[section.Key] = row
	place(row)
end

local function buildCard(item: Tile, color: Color3): Frame
	local card = clone("Card")
	tint(card, if item.Enabled then color else GREY)
	Ui.find(card, "Label").Text = line(item.Hi, item.Lo)
	showPicture(card, item.Icon, item.Rarity)
	local tag = Ui.find(card, "Tag") :: Frame
	tag.Visible = item.Tag ~= nil
	if item.Tag then
		Ui.find(tag, "Label").Text = item.Tag
	end
	local buy = Ui.find(card, "Buy") :: TextButton
	setPrice(buy, item.Price, item.PriceColor or (if item.Enabled then ROBUX else GREY))
	local onBuy = item.OnBuy
	if item.Enabled and onBuy then
		Ui.button(buy, onBuy)
	end
	local gift = Ui.find(card, "Gift") :: TextButton
	local giftKey = item.GiftKey
	gift.Visible = giftKey ~= nil and item.Enabled
	if giftKey then
		Ui.button(gift, function()
			openGiftPicker(giftKey)
		end)
	end
	if not gift.Visible then
		-- No gift button: the price takes the whole row.
		buy.Size = UDim2.new(1, -16, 0, buy.Size.Y.Offset)
	end
	return card
end

local function addGrid(items: { Tile }, color: Color3)
	if #items == 0 then
		return
	end
	local grid = clone("Grid")
	for i, item in items do
		local card = buildCard(item, color)
		card.LayoutOrder = i
		card.Parent = grid
	end
	place(grid)
end

-- A big banner (the Starter Pack): tag, title, what's inside as pictures, timer, price.
local function addBanner(opts: {
	Tag: string,
	Title: string,
	Color: Color3,
	Chips: { Chip },
	Ends: number?,
	Worth: number?,
	Price: number,
	OnBuy: () -> (),
})
	local banner = clone("Banner")
	tint(banner, opts.Color)
	Ui.find(banner, "Tag.Label").Text = opts.Tag
	Ui.find(banner, "Title").Text = string.upper(opts.Title)
	local row = Ui.find(banner, "Items") :: Frame
	for i, chip in opts.Chips do
		local c = clone("Chip")
		c.LayoutOrder = i
		Ui.find(c, "Caption").Text = chip.Caption
		c.Parent = row
		showPicture(c, chip.Icon, chip.Rarity)
	end
	local worth = Ui.find(banner, "Worth") :: TextLabel
	worth.Visible = opts.Worth ~= nil
	if opts.Worth then
		worth.Text = robuxPrice(opts.Worth)
	end
	setPrice(Ui.find(banner, "Buy"), robuxPrice(opts.Price), ROBUX)
	Ui.button(Ui.find(banner, "Buy"), opts.OnBuy)
	local timer = Ui.find(banner, "Timer") :: TextLabel
	local ends = opts.Ends
	local function tick(): boolean
		if not ends then
			timer.Text = ""
			return false
		end
		local left = ends - workspace:GetServerTimeNow()
		timer.Text = leftText(left, "Gone!")
		return left <= 0
	end
	tick()
	table.insert(timers, tick)
	place(banner)
end

-------------------------------------------------------------------------- server luck card

-- The Server Luck level running now (1 = none), from the server state.
local function luckLevel(): number
	local level = State.server("LuckLevel") or 1
	local ends = State.server("LuckEnds") or 0
	return if ends > State.now() then level else 1
end

-- Level now > next level, the next level's price and the shared timer. Runs every second
-- (someone else on the server can raise the level any time).
local function fillLuckCard(): boolean
	local card = luckCard
	if not card or not card.Parent then
		return false
	end
	local level = luckLevel()
	local def = Products.serverLuckNext(level)
	if not def then
		return false
	end
	local nextMult = def.Mult or level
	local levels = Ui.find(card, "Levels") :: TextLabel
	local desc = Ui.find(card, "Desc") :: TextLabel
	local minutes = def.Minutes or Economy.ServerLuckMinutes
	if nextMult > level then
		levels.Text = `{level}x <font color="#FFE34D">&gt; {nextMult}x</font>`
		desc.Text = "Rarer eggs for EVERYONE here!"
	else
		levels.Text = `<font color="#FFE34D">{level}x MAX</font>`
		desc.Text = `Top level! Buying adds {minutes} min.`
	end
	local timer = Ui.find(card, "Timer") :: TextLabel
	local left = (State.server("LuckEnds") or 0) - State.now()
	timer.Text = if level > 1 and left > 0 then leftText(left, "") else `Lasts {minutes} min`
	local priceText = robuxPrice(def.Price)
	local buy = Ui.find(card, "Buy") :: TextButton
	if buy:GetAttribute("Price") ~= priceText then
		buy:SetAttribute("Price", priceText)
		setPrice(buy, priceText, ROBUX)
	end
	return false
end

local function addLuckCard()
	if not Products.serverLuckNext(1) then
		return
	end
	local card = clone("LuckCard")
	card.Name = "ServerLuck"
	card.Size = UDim2.new(1, 0, 0, LUCK_H)
	Ui.button(Ui.find(card, "Buy"), function()
		prompt("ServerLuck")
	end)
	luckCard = card
	place(card)
	fillLuckCard()
	table.insert(timers, fillLuckCard)
end

-------------------------------------------------------------------------- limited egg

-- The limited egg banner (Dev's "Halloween Egg" reference): New! tag, title, Limited
-- Time!, timer, the egg on the left, pet cards that grow with rarity (the rarest big with
-- a rainbow border) and buy cells biggest first, each with a gift button.
local function addEggBanner(now: number)
	local packs = Products.limitedEggPacks(now)
	if #packs == 0 then
		return
	end
	local banner = clone("EggBanner")
	banner.Name = "LimitedEgg"
	Ui.find(banner, "Title").Text = string.upper(LimitedEgg.Name)
	ModelView.show(Ui.find(banner, "Egg"), AssetLibrary.egg(LimitedEgg.EggRarity), "Egg_" .. LimitedEgg.EggRarity)
	local pets = Ui.find(banner, "Pets") :: Frame
	local odds = table.clone(LimitedEgg.Odds)
	table.sort(odds, function(a, b)
		return a.Chance > b.Chance
	end)
	for i, entry in odds do
		local def = Aliens.ById[entry.Pet]
		if def then
			local rarest = i == #odds
			local card = clone(if rarest then "BigPet" else "PetCard")
			card.Name = def.Id
			card.LayoutOrder = i
			if not rarest then
				local px = PET_SIZES[math.min(i, #PET_SIZES)]
				card.Size = UDim2.fromOffset(px, px)
			end
			local chance = Ui.find(card, "Chance") :: TextLabel
			chance.Text = `{entry.Chance}%`
			local rarity = Eggs.ByName[def.Rarity]
			if rarity and Eggs.order(def.Rarity) >= Eggs.order("Mythic") then
				chance.TextColor3 = Color3.fromRGB(255, 227, 77)
			end
			card.Parent = pets
			ModelView.show(Ui.find(card, "Model"), AssetLibrary.alien(def.Id), "Alien_" .. def.Id)
		end
	end
	local single = packs[1].Price / (packs[1].Count or 1)
	local buys = Ui.find(banner, "Buys") :: Frame
	for i = #packs, 1, -1 do
		local def = packs[i]
		local count = def.Count or 1
		local cell = clone("BuyCell")
		cell.LayoutOrder = #packs - i + 1
		Ui.find(cell, "Count").Text = if count == 1 then "1 Egg" else `{count} Eggs`
		local buy = Ui.find(cell, "Buy") :: TextButton
		setPrice(buy, robuxPrice(def.Price), ROBUX)
		if i == #packs and count > 1 then
			-- The biggest pack: rainbow button with what the same eggs cost one by one.
			(Ui.find(buy, "Rainbow") :: UIGradient).Enabled = true
			tint(buy, WHITE)
			local worth = Ui.find(cell, "Worth") :: TextLabel
			worth.Visible = true
			worth.Text = robuxPrice(math.floor(single * count + 0.5))
		end
		local key = def.Key
		Ui.button(buy, function()
			prompt(key)
		end)
		local gift = Ui.find(cell, "Gift") :: TextButton
		gift.Visible = def.Giftable == true
		Ui.button(gift, function()
			openGiftPicker(key)
		end)
		cell.Parent = buys
	end
	local timer = Ui.find(banner, "Timer") :: TextLabel
	local function tick(): boolean
		local left = LimitedEgg.EndsAt - workspace:GetServerTimeNow()
		timer.Text = leftText(left, "Gone!")
		return left <= 0
	end
	tick()
	table.insert(timers, tick)
	place(banner)
end

-------------------------------------------------------------------------- featured

local function productIcon(key: string): string
	local def = Products.ProductByKey[key]
	if def and def.Kind == "ToolSkip" and def.Tier then
		return "Icon_Tool_" .. Tools.get(def.Tier).Id
	elseif def and def.Kind == "SkipHatch" then
		return "Icon_Timer"
	elseif def and def.Kind == "ServerLuck" then
		return "Icon_Luck"
	end
	local pass = PASS_INFO[key]
	return if pass then pass.Icon else "Icon_Star"
end

-- Limited offers still worth showing: not the Starter Pack (it has its own banner), not
-- a pass you own, not a tool you already have, not a hatch skip with nothing hatching.
local function liveOffers(data): { any }
	local out = {}
	for _, offer in C.OfferController:Specials() do
		local key = offer.Product
		local def = Products.ProductByKey[key]
		local owned = data.Gamepasses[key] == true
		local toolOwned = def ~= nil and def.Kind == "ToolSkip" and def.Tier ~= nil and def.Tier <= data.ToolTier
		local keep = key ~= "StarterPack" and not owned and not toolOwned
		if def and def.Kind == "SkipHatch" then
			local hatching = false
			for _, entry in data.Hatching do
				hatching = hatching or entry.Rarity == def.Rarity
			end
			keep = keep and hatching
		end
		if keep then
			table.insert(out, offer)
		end
	end
	return out
end

local function specialCount(data): number
	local now = workspace:GetServerTimeNow()
	return (if Products.starterPackEnds(data, now) then 1 else 0)
		+ (if #Products.limitedEggPacks(now) > 0 then 1 else 0)
		+ #liveOffers(data)
end

local function buildFeatured(data)
	local now = workspace:GetServerTimeNow()
	addEggBanner(now)
	local starterEnds = Products.starterPackEnds(data, now)
	if starterEnds then
		local pack = Economy.StarterPack
		local cash = data.CashPacks and data.CashPacks.StarterPack
		addBanner({
			Tag = "OFFER",
			Title = "Starter Pack",
			Color = Color3.fromRGB(255, 77, 94),
			Chips = {
				{ Icon = "Icon_Cash", Caption = if cash then Format.cash(cash) else "Cash" },
				{ Rarity = pack.EggRarity, Caption = `{pack.EggRarity} Egg` },
				{ Icon = "Icon_PotionLuck", Caption = `{pack.LuckPotions}x Luck` },
				{ Icon = "Icon_PotionCash", Caption = `2x Cash {pack.Cash2xMinutes}m` },
			},
			Ends = starterEnds,
			Price = Products.ProductByKey.StarterPack.Price,
			OnBuy = function()
				prompt("StarterPack")
			end,
		})
	end
	for _, offer in liveOffers(data) do
		local row = clone("Offer")
		row.Name = "Offer_" .. offer.Key
		Ui.find(row, "Title").Text = offer.Title
		Ui.find(row, "Desc").Text = offer.Text
		Ui.find(row, "Icon").Image = AssetLibrary.image(productIcon(offer.Product))
		setPrice(Ui.find(row, "Buy"), robuxPrice(offer.Price), ROBUX)
		local product = offer.Product
		Ui.button(Ui.find(row, "Buy"), function()
			prompt(product)
		end)
		local label = Ui.find(row, "Timer") :: TextLabel
		local expires = offer.Expires
		local function tick(): boolean
			local left = expires - os.clock()
			label.Text = leftText(left, "Ended")
			return left <= 0
		end
		tick()
		table.insert(timers, tick)
		place(row)
	end
end

-------------------------------------------------------------------------- other sections

local function buildEggs(data, color: Color3)
	local tiles: { Tile } = {}
	for _, rarity in EGG_TIERS do
		local packs = Products.eggPacks(rarity)
		if #packs > 0 then
			table.insert(tiles, {
				Hi = string.upper(rarity),
				Lo = "EGG",
				Price = robuxPrice(packs[1].Price),
				Rarity = rarity,
				Enabled = true,
				OnBuy = function()
					openQtyPicker(rarity)
				end,
				GiftKey = if packs[1].Giftable then packs[1].Key else nil,
			})
		end
	end
	local seen = {}
	for _, entry in data.Hatching do
		if not seen[entry.Rarity] then
			seen[entry.Rarity] = true
			local tile = productTile("SkipHatch" .. entry.Rarity, "SKIP", `{string.upper(entry.Rarity)} HATCH`, "Icon_Timer", "INSTANT")
			if tile then
				table.insert(tiles, tile)
			end
		end
	end
	addGrid(tiles, color)
end

local function buildPasses(data, color: Color3)
	local passes = table.clone(Products.Gamepasses)
	table.sort(passes, function(a, b)
		local ownA, ownB = data.Gamepasses[a.Key] == true, data.Gamepasses[b.Key] == true
		if ownA ~= ownB then
			return ownB
		end
		return a.Price < b.Price
	end)
	local tiles: { Tile } = {}
	for _, pass in passes do
		if pass.Id ~= 0 then
			local owned = data.Gamepasses[pass.Key] == true
			local info = PASS_INFO[pass.Key]
			table.insert(tiles, {
				Hi = if info then info.Hi else "",
				Lo = if info then info.Lo else string.upper(pass.Name),
				Price = if owned then "Owned" else robuxPrice(pass.Price),
				Enabled = not owned,
				Icon = if info then info.Icon else "Icon_Star",
				Tag = if owned or not info then nil else info.Tag,
				OnBuy = function()
					prompt(pass.Key)
				end,
				-- Passes can't be gifted on Roblox; each has a gift product instead.
				GiftKey = if Products.passGift(pass.Key) then "Gift" .. pass.Key else nil,
			})
		end
	end
	addGrid(tiles, color)
end

local function buildBoosts(_data, color: Color3)
	addLuckCard()
	local tiles: { Tile } = {}
	for _, entry in {
		{ "WeatherTotem1", "WEATHER", "TOTEM", "Icon_WeatherTotem" },
		{ "MeteorShower", "EGG", "RAIN", "Icon_Meteor" },
	} do
		local tile = productTile(entry[1], entry[2], entry[3], entry[4])
		if tile then
			table.insert(tiles, tile)
		end
	end
	addGrid(tiles, color)
end

local function buildPotions(_data, color: Color3)
	local tiles: { Tile } = {}
	for _, entry in POTIONS do
		local tile = productTile(entry.Key, entry.Hi, entry.Lo, entry.Icon)
		if tile then
			table.insert(tiles, tile)
		end
	end
	addGrid(tiles, color)
end

local function buildMoney(data, color: Color3)
	local tiles: { Tile } = {}
	for _, key in { "Cash1", "Cash2", "Cash3", "Cash4", "Cash5" } do
		-- The server works out each pack's amount for this player (it grows with progress).
		local amount = data.CashPacks and data.CashPacks[key]
		local tile = productTile(key, if amount then Format.cash(amount) else "CASH", nil, "Icon_Cash")
		if tile then
			table.insert(tiles, tile)
		end
	end
	local tier = data.ToolTier + 1
	if tier <= Tools.MaxTier and tier > Tools.FreeTier then
		local def = Tools.get(tier)
		local skip = productTile("ToolSkip" .. tier, "GET", string.upper(def.Name), "Icon_Tool_" .. def.Id, "INSTANT")
		if skip then
			table.insert(tiles, skip)
		end
	end
	local skipDef = Products.skipRebirthFor(data.Rebirths)
	local skip = skipDef and productTile(skipDef.Key, "SKIP", "REBIRTH", "Icon_Rebirth")
	if skip then
		table.insert(tiles, skip)
	end
	addGrid(tiles, color)
end

local BUILDERS: { [string]: (any, Color3) -> () } = {
	Featured = function(data)
		buildFeatured(data)
	end,
	Eggs = buildEggs,
	Passes = buildPasses,
	Boosts = buildBoosts,
	Potions = buildPotions,
	Money = buildMoney,
}

-------------------------------------------------------------------------- render

-- Scrolls the list so a section's heading is at the top.
local function jumpTo(key: string)
	local heading = headings[key]
	if not heading or not heading.Parent then
		return
	end
	local k = if scale.Scale > 0 then scale.Scale else 1
	local y = (heading.AbsolutePosition.Y - list.AbsolutePosition.Y) / k + list.CanvasPosition.Y
	list.CanvasPosition = Vector2.new(0, math.max(0, y - 4))
end

local function buildNav()
	local template = Ui.find(nav, "NavButton") :: GuiButton
	for i, section in SECTIONS do
		local button = template:Clone()
		button.Name = section.Key
		button.LayoutOrder = i
		button.Visible = true
		Ui.find(button, "Icon").Image = AssetLibrary.image(section.Icon)
		Ui.find(button, "Label").Text = section.Title
		button.Parent = nav
		local key = section.Key
		Ui.button(button, function()
			jumpTo(key)
		end)
		navButtons[key] = button
	end
end

local function render()
	local data = State.data
	if not data then
		return
	end
	local specials = specialCount(data)
	Ui.setBadge(shopBadge, specials)
	local featured = navButtons.Featured
	if featured then
		featured.Visible = specials > 0
	end
	if not gui.Enabled then
		return
	end
	local scroll = list.CanvasPosition
	for _, child in list:GetChildren() do
		if child:GetAttribute("Built") then
			child:Destroy()
		end
	end
	table.clear(timers)
	table.clear(headings)
	luckCard = nil
	nextOrder = 0
	for _, section in SECTIONS do
		if section.Key == "Codes" then
			headings.Codes = list:FindFirstChild("CodesBox") :: any
			continue
		end
		local before = nextOrder
		addHeading(section)
		BUILDERS[section.Key](data, section.Card)
		if nextOrder == before + 1 then
			-- Nothing for sale here right now: no lone heading.
			headings[section.Key]:Destroy()
			headings[section.Key] = nil
		end
	end
	list.CanvasPosition = scroll
end

local function tickTimers(): boolean
	local expired = false
	for _, tick in timers do
		expired = tick() or expired
	end
	return expired
end

local function open(section: string?)
	local key = section and (ALIAS[section] or section)
	giftPicker.Visible = false
	qtyPicker.Visible = false
	list.CanvasPosition = Vector2.zero
	render()
	if key and key ~= "Featured" then
		-- Let the list lay out before measuring where the section is.
		task.defer(function()
			task.wait()
			jumpTo(key)
		end)
	end
end

function ShopController:Toggle()
	Ui.toggle("Shop")
	if gui.Enabled then
		open(nil)
	end
end

-- Opens the shop at a section ("Featured", "Eggs", "Passes", "Boosts", "Potions", "Money",
-- "Codes").
function ShopController:Open(section: string?)
	Ui.open("Shop")
	open(section)
end

-- Called by OfferController when a new limited offer arrives.
function ShopController:Refresh()
	render()
end

function ShopController:Init(controllers)
	C = controllers
	gui = Ui.screen("Shop")
	list = Ui.find(gui, "Window.Panel.List")
	scale = Ui.find(gui, "Window.AutoScale")
	nav = Ui.find(gui, "Window.Nav")
	for _, name in { "Heading", "Grid", "Card", "Banner", "Chip", "EggBanner", "PetCard", "BigPet", "BuyCell", "Offer", "LuckCard" } do
		templates[name] = Ui.find(gui, "Window." .. name)
	end
	giftPicker = Ui.find(gui, "Window.GiftPicker")
	giftList = Ui.find(gui, "Window.GiftPicker.List")
	giftTemplate = Ui.find(gui, "Window.GiftPicker.List.Template")
	giftEmpty = Ui.find(gui, "Window.GiftPicker.Empty")
	qtyPicker = Ui.find(gui, "Window.QtyPicker")
	qtyOptions = Ui.find(gui, "Window.QtyPicker.Options")
	templates.Option = Ui.find(qtyOptions, "Option")
	shopBadge = Ui.find(Ui.screen("Hud"), "Rail.ShopButton.Badge")
end

function ShopController:Start()
	buildNav()
	Ui.button(Ui.find(gui, "Window.Panel.Header.Close"), function()
		Ui.close("Shop")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Shop")
	end)
	Ui.button(Ui.find(gui, "Window.GiftPicker.Close"), function()
		giftPicker.Visible = false
	end)
	Ui.button(Ui.find(qtyPicker, "Close"), function()
		qtyPicker.Visible = false
	end)
	-- Dev Academy tip: the server opens the Shop at Money on the 3rd "not enough cash".
	Net.event("OpenShop").OnClientEvent:Connect(function(section: any)
		if not gui.Enabled then
			ShopController:Open(if type(section) == "string" then section else "Money")
		end
	end)
	-- Income changes cash every second; only rebuild when something the shop shows changed.
	local lastSignature = ""
	State.Changed:Connect(function(data)
		local nextTool = Tools.get(math.min(data.ToolTier + 1, Tools.MaxTier))
		local hatching = {}
		for _, entry in data.Hatching do
			table.insert(hatching, entry.Rarity)
		end
		local passes = {}
		for key in data.Gamepasses do
			table.insert(passes, key)
		end
		table.sort(passes)
		local signature = table.concat({
			data.ToolTier,
			data.EffectiveTier,
			tostring(BigNum.gte(data.Cash, nextTool.Price)),
			tostring(data.Flags.StarterPackBought),
			data.Rebirths,
			if data.CashPacks and data.CashPacks.Cash1 then Format.cash(data.CashPacks.Cash1) else "",
			table.concat(hatching, ","),
			table.concat(passes, ","),
		}, "|")
		if signature ~= lastSignature then
			lastSignature = signature
			render()
		end
	end)
	-- Timers, and the badges when a limited offer runs out.
	task.spawn(function()
		local lastCount = -1
		while true do
			task.wait(1)
			local data = State.data
			if data then
				local count = specialCount(data)
				local expired = gui.Enabled and tickTimers()
				if expired or count ~= lastCount then
					lastCount = count
					render()
				end
			end
		end
	end)
end

return ShopController
