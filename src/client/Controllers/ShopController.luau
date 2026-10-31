--!strict
-- Shop (Robux things only), redesigned for kids (Dev, 2026-10-31: the old one-long-scroll
-- shop was "hella clustered"). Tabs down the left switch PAGES, one at a time:
--   Deals   - Starter Pack and the limited pack as big banners whose contents are
--             pictures, plus limited offers the game made you in the last few minutes
--   Eggs    - one tile per rarity (Epic .. Cosmic); Buy opens a "How many?" picker
--             (x1 / x3 MOST POPULAR / x10 BEST VALUE), then hatch skips for eggs growing
--   Passes  - gamepasses, cheapest first, owned ones last
--   Boosts  - the Server Luck card (level now > next, shared timer) and other server buys
--   Potions - small buys that go to your bag
--   Cash    - cash packs, Skip Rebirth, the next tool skip
-- A tile is a big picture, a short name, one short line and one price button; giftable
-- tiles get a pink gift corner. Layout templates come from tools/gen_ui.py shop().
-- Free / cash things (tools, cars) are in the Gear window and base skins in the base picker.
-- Robux items whose ID is still 0 are hidden. The rail Shop button and the Deals tab show
-- a badge while a special offer is up.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local ModelView = require(Client.ModelView)
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Tools = require(Shared.Config.Tools)

local GREY = Color3.fromRGB(166, 174, 194)
local ROBUX = Color3.fromRGB(255, 200, 60)
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(27, 31, 58)

local LUCK_H = 132 -- SHOP_LUCK_H in tools/gen_ui.py

type Tile = {
	Name: string,
	Sub: string,
	Price: string,
	PriceColor: Color3?,
	Enabled: boolean,
	OnBuy: (() -> ())?,
	GiftKey: string?,
	Icon: string?,
	Rarity: string?, -- egg tiles show the 3D egg
	Tag: string?,
}

type Chip = { Icon: string?, Rarity: string?, Caption: string }

type Page = {
	Key: string,
	Title: string,
	Icon: string,
	Color: Color3,
	Note: string,
}

local PAGES: { Page } = {
	{ Key = "Deals", Title = "Deals", Icon = "Icon_Star", Color = Color3.fromRGB(255, 77, 94), Note = "Big savings, not here for long!" },
	{ Key = "Eggs", Title = "Eggs", Icon = "Icon_Egg", Color = Color3.fromRGB(255, 95, 162), Note = "Hatch rare pets!" },
	{ Key = "Passes", Title = "Passes", Icon = "Icon_Star", Color = Color3.fromRGB(155, 107, 255), Note = "Yours forever" },
	{ Key = "Boosts", Title = "Boosts", Icon = "Icon_Luck", Color = Color3.fromRGB(255, 128, 48), Note = "The whole server gets it!" },
	{ Key = "Potions", Title = "Potions", Icon = "Icon_PotionLuck", Color = Color3.fromRGB(46, 184, 160), Note = "Goes to your bag" },
	{ Key = "Cash", Title = "Cash", Icon = "Icon_Cash", Color = Color3.fromRGB(47, 191, 85), Note = "More cash right now" },
}
local PAGE_BY_KEY: { [string]: Page } = {}
for _, page in PAGES do
	PAGE_BY_KEY[page.Key] = page
end
-- Old section names other code may still open.
local PAGE_ALIAS = { Tools = "Cash", Offers = "Deals" }

local PASS_INFO: { [string]: { Icon: string, Sub: string, Tag: string? } } = {
	FastWalk = { Icon = "Icon_Speed", Sub = "Walk 30% faster", Tag = "NEW" },
	BigBag = { Icon = "Icon_Backpack", Sub = "2x bag space", Tag = "NEW" },
	Cash2x = { Icon = "Icon_Cash", Sub = "2x cash forever" },
	Carry3 = { Icon = "Icon_Egg", Sub = "Carry 3 eggs" },
	AutoSweep = { Icon = "Icon_Auto", Sub = "Sweeps for you" },
	Lucky = { Icon = "Icon_LuckyClover", Sub = "+50% egg luck", Tag = "NEW" },
	ExtraSlots = { Icon = "Icon_Alien", Sub = "+3 pets on your base" },
	SellAnywhere = { Icon = "Icon_Sell", Sub = "Sell from anywhere" },
	FasterHatch = { Icon = "Icon_Timer", Sub = "Eggs hatch 2x faster" },
	VIP = { Icon = "Icon_Star", Sub = "Daily gift, luck, cash" },
}

local EGG_TIERS = {
	{ Rarity = "Epic", Sub = "A sure Epic pet" },
	{ Rarity = "Legendary", Sub = "A sure Legendary pet" },
	{ Rarity = "Mythic", Sub = "A sure Mythic pet" },
	{ Rarity = "Cosmic", Sub = "A sure Cosmic pet" },
}

-- Small buys that go to your bag, cheapest first.
local POTIONS = {
	{ Key = "LeafBomb3", Icon = "Icon_LeafBomb", Sub = "Clears leaves around you" },
	{ Key = "LuckyClover1", Icon = "Icon_LuckyClover", Sub = "Next hatch: rarer!" },
	{ Key = "LuckPotion3", Icon = "Icon_PotionLuck", Sub = "2x luck, 10 min each" },
	{ Key = "CashPotion3", Icon = "Icon_PotionCash", Sub = "2x cash, 10 min each" },
	{ Key = "MutationSpray1", Icon = "Icon_MutationSpray", Sub = "Mutates a growing egg" },
	{ Key = "SuperLuckPotion1", Icon = "Icon_PotionSuperLuck", Sub = "3x luck, 15 min" },
	{ Key = "MegaCashPotion1", Icon = "Icon_PotionMegaCash", Sub = "3x cash, 15 min" },
	{ Key = "HugeCharm1", Icon = "Icon_HugeCharm", Sub = "Next hatch: 10x Huge" },
}

local ShopController = {}

local C: any
local gui: ScreenGui
local list: ScrollingFrame
local templates: { [string]: GuiObject } = {}
local emptyLabel: TextLabel
local giftPicker: Frame
local giftList: ScrollingFrame
local giftTemplate: TextButton
local giftEmpty: TextLabel
local qtyPicker: Frame
local qtyOptions: Frame
local shopBadge: Frame?
local tabList: ScrollingFrame
local tabTemplate: TextButton
local tabs: { [string]: TextButton } = {}
local currentPage = "Deals"
local luckCard: Frame? = nil
-- Labels that count down every second while their page is open.
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
		-- Dark text on gold, white text on green/grey.
		label.TextColor3 = if color == ROBUX then INK else WHITE
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = color ~= ROBUX
		end
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

local function productTile(key: string, sub: string, iconName: string?, tag: string?): Tile?
	local def = Products.ProductByKey[key]
	if not def or def.Id == 0 then
		return nil
	end
	return {
		Name = def.Name,
		Sub = sub,
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

local function addTitle(page: Page)
	local row = clone("PageTitle")
	Ui.find(row, "Title").Text = page.Title
	Ui.find(row, "Note").Text = page.Note
	Ui.find(row, "Icon").Image = AssetLibrary.image(page.Icon)
	Ui.find(row, "Rule").BackgroundColor3 = page.Color
	place(row)
end

local function buildTile(item: Tile, color: Color3): Frame
	local card = clone("Tile")
	tint(card, if item.Enabled then color else GREY)
	Ui.find(card, "Name").Text = item.Name
	Ui.find(card, "Sub").Text = item.Sub
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
	return card
end

local function addGrid(items: { Tile }, color: Color3)
	if #items == 0 then
		return
	end
	local grid = clone("Grid")
	for i, item in items do
		local tile = buildTile(item, color)
		tile.LayoutOrder = i
		tile.Parent = grid
	end
	place(grid)
end

-- A big banner: tag, title, what's inside as pictures, a timer and the price.
local function addBanner(opts: {
	Tag: string,
	TagColor: Color3?,
	Title: string,
	TitleColor: Color3?,
	Color: Color3,
	Art: string?,
	Chips: { Chip },
	Ends: number?,
	TimerWord: string,
	Worth: number?,
	Price: number,
	OnBuy: () -> (),
})
	local banner = clone("Banner")
	tint(banner, opts.Color)
	local art = Ui.find(banner, "Art") :: ImageLabel
	art.Image = if opts.Art then AssetLibrary.image(opts.Art) else ""
	art.Visible = opts.Art ~= nil
	Ui.find(banner, "Tag.Label").Text = opts.Tag
	if opts.TagColor then
		tint(Ui.find(banner, "Tag"), opts.TagColor)
	end
	local titleLabel = Ui.find(banner, "Title") :: TextLabel
	titleLabel.Text = opts.Title
	if opts.TitleColor then
		titleLabel.TextColor3 = opts.TitleColor
	end
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
	local word = opts.TimerWord
	local function tick(): boolean
		if not ends then
			timer.Text = ""
			return false
		end
		local left = ends - workspace:GetServerTimeNow()
		timer.Text = if left > 0 then `{word} {Format.time(left)}` else "Gone!"
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
	timer.Text = if level > 1 and left > 0 then `Ends in {Format.time(left)}` else `Lasts {minutes} min`
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

-------------------------------------------------------------------------- deals

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
		+ (if Products.limitedPackEnds(data, now) then 1 else 0)
		+ #liveOffers(data)
end

-- Short names so banner captions stay big enough to read.
local SHORT_NAMES: { [string]: string } = {
	SuperLuckPotion = "Super Luck",
	MegaCashPotion = "Mega Cash",
	LuckPotion = "Luck",
	CashPotion = "Cash x2",
}

local function itemChips(chips: { Chip }, items: { [string]: number })
	-- Fixed order so the banner doesn't shuffle between renders.
	for _, def in Items.List do
		local count = items[def.Id]
		if count then
			local name = SHORT_NAMES[def.Id] or def.Name
			table.insert(chips, { Icon = def.Icon, Caption = if count > 1 then `{name} x{count}` else name })
		end
	end
end

local function buildDeals(data)
	local now = workspace:GetServerTimeNow()
	local limitedEnds = Products.limitedPackEnds(data, now)
	if limitedEnds then
		local pack = Economy.LimitedPack
		local def = Products.ProductByKey.HalloweenPack
		local chips: { Chip } = {}
		for _, rarity in { "Cosmic", "Mythic", "Legendary", "Epic" } do
			if pack.Eggs[rarity] then
				table.insert(chips, { Rarity = rarity, Caption = rarity })
			end
		end
		itemChips(chips, pack.Items)
		table.insert(chips, { Icon = "Icon_Spin", Caption = `{pack.Spins} Spins` })
		-- Halloween look (Dev, 2026-10-31): night purple with pumpkin orange.
		addBanner({
			Tag = "HALLOWEEN",
			TagColor = Color3.fromRGB(255, 128, 32),
			Title = pack.Name,
			TitleColor = Color3.fromRGB(255, 166, 48),
			Color = Color3.fromRGB(92, 45, 145),
			Chips = chips,
			Ends = limitedEnds,
			TimerWord = "Leaves in",
			Worth = pack.Worth,
			Price = def.Price,
			OnBuy = function()
				prompt("HalloweenPack")
			end,
		})
	end
	local starterEnds = Products.starterPackEnds(data, now)
	if starterEnds then
		local pack = Economy.StarterPack
		local cash = data.CashPacks and data.CashPacks.StarterPack
		addBanner({
			Tag = "SPECIAL OFFER",
			Title = "Starter Pack",
			Color = Color3.fromRGB(255, 77, 94),
			Chips = {
				{ Icon = "Icon_Cash", Caption = if cash then Format.cash(cash) else "Cash" },
				{ Rarity = pack.EggRarity, Caption = `{pack.EggRarity} Egg` },
				{ Icon = "Icon_PotionLuck", Caption = `{pack.LuckPotions}x Luck` },
				{ Icon = "Icon_PotionCash", Caption = `2x Cash {pack.Cash2xMinutes}m` },
			},
			Ends = starterEnds,
			TimerWord = "Leaves in",
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
			label.Text = if left > 0 then `Ends in {Format.time(left)}` else "Ended"
			return left <= 0
		end
		tick()
		table.insert(timers, tick)
		place(row)
	end
end

-------------------------------------------------------------------------- other pages

local function buildEggs(data, color: Color3)
	local tiles: { Tile } = {}
	for _, tier in EGG_TIERS do
		local packs = Products.eggPacks(tier.Rarity)
		if #packs > 0 then
			local rarity = tier.Rarity
			table.insert(tiles, {
				Name = `{rarity} Egg`,
				Sub = tier.Sub,
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
			local tile = productTile("SkipHatch" .. entry.Rarity, `Hatch your {entry.Rarity} egg now`, "Icon_Timer", "INSTANT")
			if tile then
				tile.Name = "Skip Hatch"
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
				Name = pass.Name,
				Sub = if info then info.Sub else "",
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
		{ "WeatherTotem1", "Lucky weather for all", "Icon_WeatherTotem" },
		{ "MeteorShower", "Eggs fall for everyone", "Icon_Meteor" },
	} do
		local tile = productTile(entry[1], entry[2], entry[3])
		if tile then
			table.insert(tiles, tile)
		end
	end
	addGrid(tiles, color)
end

local function buildPotions(_data, color: Color3)
	local tiles: { Tile } = {}
	for _, entry in POTIONS do
		local tile = productTile(entry.Key, entry.Sub, entry.Icon, entry.Tag)
		if tile then
			table.insert(tiles, tile)
		end
	end
	addGrid(tiles, color)
end

local function buildCash(data, color: Color3)
	local tiles: { Tile } = {}
	for _, key in { "Cash1", "Cash2", "Cash3", "Cash4", "Cash5" } do
		-- The server works out each pack's amount for this player (it grows with progress).
		local amount = data.CashPacks and data.CashPacks[key]
		local tile = productTile(key, if amount then `+{Format.cash(amount)}` else "Grows with you", "Icon_Cash")
		if tile then
			table.insert(tiles, tile)
		end
	end
	local tier = data.ToolTier + 1
	if tier <= Tools.MaxTier and tier > Tools.FreeTier then
		local def = Tools.get(tier)
		local skip = productTile("ToolSkip" .. tier, "Your next tool now", "Icon_Tool_" .. def.Id, "INSTANT")
		if skip then
			skip.Name = def.Name
			table.insert(tiles, skip)
		end
	end
	local skipDef = Products.skipRebirthFor(data.Rebirths)
	local skip = skipDef and productTile(skipDef.Key, `Jump to Rebirth {data.Rebirths + 1}`, "Icon_Rebirth")
	if skip then
		skip.Name = "Skip Rebirth"
		table.insert(tiles, skip)
	end
	addGrid(tiles, color)
end

local BUILDERS: { [string]: (any, Color3) -> () } = {
	Deals = function(data)
		buildDeals(data)
	end,
	Eggs = buildEggs,
	Passes = buildPasses,
	Boosts = buildBoosts,
	Potions = buildPotions,
	Cash = buildCash,
}

-------------------------------------------------------------------------- render

local function pageVisible(key: string, data): boolean
	if key == "Deals" then
		return specialCount(data) > 0
	end
	return true
end

local function setLit(key: string)
	for k, button in tabs do
		local on = k == key
		local lit = button:FindFirstChild("Lit") :: GuiObject?
		if lit then
			lit.Visible = on
		end
		local stroke = button:FindFirstChild("Stroke") :: UIStroke?
		if stroke then
			stroke.Color = if on then WHITE else INK
		end
	end
end

local render: () -> ()

local function buildTabs()
	for i, page in PAGES do
		local button = tabTemplate:Clone()
		button.Name = "Tab_" .. page.Key
		button.LayoutOrder = i
		button.Visible = true
		tint(button, page.Color)
		Ui.setText(button, page.Title)
		Ui.find(button, "Icon").Image = AssetLibrary.image(page.Icon)
		button.Parent = tabList
		local key = page.Key
		Ui.button(button, function()
			if currentPage ~= key then
				currentPage = key
				list.CanvasPosition = Vector2.zero
				render()
			end
		end)
		tabs[key] = button
	end
end

function render()
	local data = State.data
	if not data then
		return
	end
	local specials = specialCount(data)
	Ui.setBadge(shopBadge, specials)
	local dealsTab = tabs.Deals
	if dealsTab then
		dealsTab.Visible = specials > 0
		Ui.setBadge(dealsTab:FindFirstChild("Badge") :: Frame?, specials)
	end
	if not gui.Enabled then
		return
	end
	if not pageVisible(currentPage, data) then
		currentPage = "Eggs"
	end
	for _, child in list:GetChildren() do
		if child:GetAttribute("Built") then
			child:Destroy()
		end
	end
	table.clear(timers)
	luckCard = nil
	nextOrder = 0
	local page = PAGE_BY_KEY[currentPage]
	addTitle(page)
	BUILDERS[page.Key](data, page.Color)
	emptyLabel.Visible = nextOrder <= 1
	setLit(page.Key)
end

local function tickTimers(): boolean
	local expired = false
	for _, tick in timers do
		expired = tick() or expired
	end
	return expired
end

local function open(section: string?)
	local key = section and (PAGE_ALIAS[section] or section)
	local data = State.data
	if key and PAGE_BY_KEY[key] then
		currentPage = key
	elseif data then
		-- Deals first while there's a deal; otherwise eggs (what kids come for).
		currentPage = if specialCount(data) > 0 then "Deals" else "Eggs"
	end
	giftPicker.Visible = false
	qtyPicker.Visible = false
	render()
	list.CanvasPosition = Vector2.zero
end

function ShopController:Toggle()
	Ui.toggle("Shop")
	if gui.Enabled then
		open(nil)
	end
end

-- Opens the shop at a page ("Deals", "Eggs", "Passes", "Boosts", "Potions", "Cash").
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
	list = Ui.find(gui, "Window.List")
	for _, name in { "PageTitle", "Banner", "Chip", "Offer", "LuckCard", "Grid", "Tile" } do
		templates[name] = Ui.find(gui, "Window." .. name)
	end
	emptyLabel = Ui.find(gui, "Window.Empty")
	giftPicker = Ui.find(gui, "Window.GiftPicker")
	giftList = Ui.find(gui, "Window.GiftPicker.List")
	giftTemplate = Ui.find(gui, "Window.GiftPicker.List.Template")
	giftEmpty = Ui.find(gui, "Window.GiftPicker.Empty")
	qtyPicker = Ui.find(gui, "Window.QtyPicker")
	qtyOptions = Ui.find(gui, "Window.QtyPicker.Options")
	templates.Option = Ui.find(qtyOptions, "Option")
	shopBadge = Ui.find(Ui.screen("Hud"), "Rail.ShopButton.Badge")
	tabList = Ui.find(gui, "Window.Tabs.List")
	tabTemplate = Ui.find(gui, "Window.Tabs.List.Template")
end

function ShopController:Start()
	buildTabs()
	Ui.button(Ui.find(gui, "Window.Close"), function()
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
	-- Dev Academy tip: the server opens the Shop at Cash on the 3rd "not enough cash".
	Net.event("OpenShop").OnClientEvent:Connect(function(section: any)
		if not gui.Enabled then
			ShopController:Open(if type(section) == "string" then section else "Cash")
		end
	end)
	-- Income changes cash every second; only rebuild when something the page shows changed.
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
			tostring(data.Flags.LimitedPackBought),
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
