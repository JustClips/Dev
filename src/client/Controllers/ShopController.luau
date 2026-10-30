--!strict
-- Shop: category tabs down the left and one scrolling page on the right. Special offers
-- sit on top (the Starter Pack banner and any limited offer the game made you in the last
-- few minutes), then server boosts, gamepasses, tools, eggs, and cash packs at the bottom.
-- A tab scrolls to its section, and the tab of the section in view stays lit. Cards are
-- tinted in their section's colour. Cars are sold in
-- the Garage. Cash prices are green buttons, Robux prices are gold with the Robux glyph.
-- Robux items whose ID is still 0 are hidden. Giftable items have a pink gift button.
-- The Shop button on the rail shows how many special offers are up right now.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Aliens = require(Shared.Config.Aliens)
local BaseSkins = require(Shared.Config.BaseSkins)
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Tools = require(Shared.Config.Tools)

local GREEN = Color3.fromRGB(61, 220, 90)
local GREY = Color3.fromRGB(166, 174, 194)
local ROBUX = Color3.fromRGB(255, 200, 60)
local WHITE = Color3.new(1, 1, 1)
local BLUE = Color3.fromRGB(76, 141, 255)
local INK = Color3.fromRGB(27, 31, 58)

-- Layout numbers shared with tools/gen_ui.py shop().
local LIST_GAP = 16
local LIST_TOP_PAD = 4
local FEATURED_H = 150
local OFFER_H = 104
local HEADER_H = 56
local CELL_H = 232 -- SHOP_CELL in tools/gen_ui.py
local CELL_GAP = 12
local COLUMNS = 3

type Item = {
	Name: string,
	Desc: string,
	Price: string,
	Color: Color3,
	Enabled: boolean,
	OnBuy: (() -> ())?,
	GiftKey: string?,
	Icon: string?,
	Tag: string?,
	-- small square button on the right instead of the gift button (base skin Preview)
	Alt: { Icon: string, Color: Color3, OnClick: () -> () }?,
}

type Section = {
	Key: string,
	Title: string,
	Icon: string,
	Color: Color3,
	Note: string,
	Items: { Item },
}

local TAGS = {
	ServerLuck8 = "POPULAR",
	ServerLuck16 = "BEST",
	CosmicEgg3 = "BEST VALUE",
	Cash3 = "POPULAR",
	Cash5 = "BEST VALUE",
	VIP = "POPULAR",
}

-- Short names for the tabs (the section titles are too long for them).
local TAB_NAMES = { Boosts = "Boosts", Passes = "Passes", Bases = "Bases", Tools = "Tools", Eggs = "Eggs", Cash = "Cash", Offers = "Offers" }

local PASS_ICONS = {
	Cash2x = "Icon_Cash",
	AutoSweep = "Icon_Auto",
	ExtraSlots = "Icon_Alien",
	Carry3 = "Icon_Egg",
	VIP = "Icon_Star",
	FasterHatch = "Icon_Timer",
	SellAnywhere = "Icon_Sell",
}

local ShopController = {}

local C: any
local gui: ScreenGui
local list: ScrollingFrame
local cardTemplate: Frame
local sectionTemplate: Frame
local offerTemplate: Frame
local emptyLabel: TextLabel
local featured: Frame
local giftPicker: Frame
local giftList: ScrollingFrame
local giftTemplate: TextButton
local giftEmpty: TextLabel
local shopBadge: Frame?
local tabList: Frame
local tabTemplate: TextButton
local tabs: { { key: string, button: TextButton } } = {}
local litTab: string? = nil
local sectionTop: { [string]: number } = {}
local offerTimers: { { Label: TextLabel, Expires: number } } = {}

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

local function robuxItem(key: string, desc: string?, iconName: string?): Item?
	local def = Products.ProductByKey[key]
	if not def or def.Id == 0 then
		return nil
	end
	return {
		Name = def.Name,
		Desc = desc or "",
		Price = robuxPrice(def.Price),
		Icon = iconName,
		Color = ROBUX,
		Enabled = true,
		Tag = TAGS[key],
		OnBuy = function()
			prompt(key)
		end,
		GiftKey = if def.Giftable then key else nil,
	}
end

local function starterPackOnSale(data): boolean
	local def = Products.ProductByKey.StarterPack
	return def ~= nil and def.Id ~= 0 and not data.Flags.StarterPackBought
end

-------------------------------------------------------------------------- sections

local function boostItems(_data): { Item }
	local items: { Item } = {}
	for _, key in { "ServerLuck2", "ServerLuck4", "ServerLuck8", "ServerLuck16" } do
		local item = robuxItem(key, "Better eggs for EVERYONE here. Time stacks.", "Icon_Luck")
		if item then
			table.insert(items, item)
		end
	end
	local shower = robuxItem("MeteorShower", "Start an Egg Rain for the whole server!", "Icon_Meteor")
	if shower then
		table.insert(items, shower)
	end
	return items
end

local function passItems(data): { Item }
	local items: { Item } = {}
	for _, pass in Products.Gamepasses do
		if pass.Id ~= 0 then
			local owned = data.Gamepasses[pass.Key] == true
			table.insert(items, {
				Name = pass.Name,
				Desc = pass.Description,
				Price = if owned then "Owned" else robuxPrice(pass.Price),
				Color = if owned then GREY else ROBUX,
				Enabled = not owned,
				Icon = PASS_ICONS[pass.Key] or "Icon_Star",
				Tag = if owned then nil else TAGS[pass.Key],
				OnBuy = function()
					prompt(pass.Key)
				end,
				-- Passes can't be gifted on Roblox; each has a gift product instead.
				GiftKey = if Products.passGift(pass.Key) then "Gift" .. pass.Key else nil,
			})
		end
	end
	return items
end

local function toolItems(data): { Item }
	local items: { Item } = {}
	local tier = data.ToolTier + 1
	if tier > Tools.MaxTier then
		return items
	end
	local def = Tools.get(tier)
	local desc = `Radius {def.Radius} · Leaves x{def.Power} · Holds {Format.number(def.Capacity)}`
	local affordable = BigNum.gte(data.Cash, def.Price)
	table.insert(items, {
		Name = def.Name,
		Desc = desc,
		Price = Format.cash(def.Price),
		Color = if affordable then GREEN else GREY,
		Enabled = true,
		Icon = "Icon_Tool_" .. def.Id,
		Tag = "NEXT",
		OnBuy = function()
			toast(Net.func("BuyNextTool"):InvokeServer())
		end,
	})
	local skip = robuxItem("ToolSkip" .. tier, "Skip the grind: get it right now.", "Icon_Tool_" .. def.Id)
	if skip then
		skip.Tag = "INSTANT"
		table.insert(items, skip)
	end
	if tier + 1 <= Tools.MaxTier then
		local after = Tools.get(tier + 1)
		table.insert(items, {
			Name = after.Name,
			Desc = `Radius {after.Radius} · Leaves x{after.Power} · Holds {Format.number(after.Capacity)}`,
			Price = "Locked",
			Color = GREY,
			Enabled = false,
			Icon = "Icon_Tool_" .. after.Id,
		})
	end
	return items
end

local function eggItems(data): { Item }
	local items: { Item } = {}
	for _, key in { "CosmicEgg1", "CosmicEgg3" } do
		local item = robuxItem(key, "Hatches Cosmo the Infinite, the event pet!", "Icon_Egg")
		if item then
			table.insert(items, item)
		end
	end
	local seen = {}
	for _, entry in data.Hatching do
		if not seen[entry.Rarity] then
			seen[entry.Rarity] = true
			local item = robuxItem("SkipHatch" .. entry.Rarity, `Finish your {entry.Rarity} egg right now.`, "Icon_Timer")
			if item then
				table.insert(items, item)
			end
		end
	end
	return items
end

local function cashItems(data): { Item }
	local items: { Item } = {}
	for _, key in { "Cash1", "Cash2", "Cash3", "Cash4", "Cash5" } do
		-- The server works out each pack's amount for this player (it grows with progress).
		local amount = data.CashPacks and data.CashPacks[key]
		local item = robuxItem(key, if amount then `+{Format.cash(amount)} cash` else "Scales with your progress.", "Icon_Cash")
		if item then
			table.insert(items, item)
		end
	end
	local skipDef = Products.skipRebirthFor(data.Rebirths)
	local skip = skipDef and robuxItem(skipDef.Key, `Jump to Rebirth {data.Rebirths + 1} without the cash cost.`, "Icon_Rebirth")
	if skip then
		table.insert(items, skip)
	end
	return items
end

local function rarityOf(id: string): string?
	local def = Aliens.ById[id]
	return if def then def.Rarity else nil
end

local function petName(id: string): string
	local def = Aliens.ById[id]
	return if def then def.Name else id
end

-- Skins whose requirements are met but that aren't unlocked yet (rail badge).
local function unlockableSkins(data): number
	local owned = data.BaseSkins and data.BaseSkins.Owned or {}
	local count = 0
	for _, def in BaseSkins.List do
		if not owned[def.Id] and def.Id ~= BaseSkins.Default and BaseSkins.progress(def, data.Rebirths, data.Index or {}, rarityOf).Met then
			count += 1
		end
	end
	return count
end

local function skinAction(action: string, id: string): boolean
	local ok, message = Net.func("BaseSkin"):InvokeServer(action, id)
	toast(ok, message)
	return ok == true
end

local function mark(ok: boolean): string
	return if ok then "✓" else "✗"
end

local function baseItems(data): { Item }
	local items: { Item } = {}
	local skins = data.BaseSkins or { Owned = { Classic = true }, Equipped = BaseSkins.Default }
	for _, def in BaseSkins.List do
		local id = def.Id
		local owned = skins.Owned[id] == true or id == BaseSkins.Default
		local equipped = (skins.Equipped or BaseSkins.Default) == id
		local p = BaseSkins.progress(def, data.Rebirths, data.Index or {}, rarityOf)
		local req = def.Requires
		local desc = def.Desc
		if not owned then
			local missing = {}
			for _, petId in req.Pets do
				if not p.Pets[petId] then
					table.insert(missing, petName(petId))
				end
			end
			if req.AnyCosmic and not p.HasCosmic then
				table.insert(missing, "any Cosmic")
			end
			desc = `{mark(p.Rebirths >= req.Rebirths)} Rebirth {math.min(p.Rebirths, req.Rebirths)}/{req.Rebirths}   {mark(p.IndexCount >= req.IndexCount)} Index {math.min(p.IndexCount, req.IndexCount)}/{req.IndexCount}\n`
				.. (if #missing == 0 then "✓ All pets found" else `✗ Find: {table.concat(missing, ", ")}`)
		end
		local item: Item = {
			Name = def.Name,
			Desc = desc,
			Price = "",
			Color = GREY,
			Enabled = true,
			Icon = def.Image or "Icon_Base",
		}
		if equipped then
			item.Price = "Equipped"
			item.Color = ROBUX
			item.Tag = "IN USE"
		elseif owned then
			item.Price = "Equip"
			item.Color = BLUE
			item.OnBuy = function()
				skinAction("Equip", id)
			end
		elseif p.Met then
			item.Price = "Unlock"
			item.Color = GREEN
			item.Tag = "READY"
			item.OnBuy = function()
				skinAction("Unlock", id)
			end
		else
			item.Price = "Locked"
			item.Enabled = false
		end
		if def.Asset and not equipped then
			item.Alt = {
				Icon = "Icon_Base",
				Color = Color3.fromRGB(155, 107, 255),
				OnClick = function()
					-- Shows it on your own base for a few seconds and takes you there.
					if skinAction("Preview", id) then
						Net.func("Teleport"):InvokeServer("Base")
						Ui.close("Shop")
					end
				end,
			}
		end
		table.insert(items, item)
	end
	return items
end

local function sections(data): { Section }
	return {
		{ Key = "Boosts", Title = "Server Boosts", Icon = "Icon_Luck", Color = Color3.fromRGB(255, 128, 48), Note = "Everyone on the server gets it!", Items = boostItems(data) },
		{ Key = "Passes", Title = "Gamepasses", Icon = "Icon_Star", Color = Color3.fromRGB(155, 107, 255), Note = "Yours forever", Items = passItems(data) },
		{ Key = "Bases", Title = "Base Skins", Icon = "Icon_Base", Color = Color3.fromRGB(242, 140, 40), Note = "Free with rebirths and your pet Index", Items = baseItems(data) },
		{ Key = "Tools", Title = "Tools", Icon = "Icon_Tool", Color = Color3.fromRGB(76, 141, 255), Note = "", Items = toolItems(data) },
		{ Key = "Eggs", Title = "Eggs", Icon = "Icon_Egg", Color = Color3.fromRGB(255, 95, 162), Note = "", Items = eggItems(data) },
		{ Key = "Cash", Title = "Cash", Icon = "Icon_Cash", Color = Color3.fromRGB(47, 191, 85), Note = "", Items = cashItems(data) },
	}
end

-------------------------------------------------------------------------- special offers

local function productIcon(key: string): string
	local def = Products.ProductByKey[key]
	if def and def.Kind == "ToolSkip" and def.Tier then
		return "Icon_Tool_" .. Tools.get(def.Tier).Id
	elseif def and def.Kind == "SkipHatch" then
		return "Icon_Timer"
	elseif def and def.Kind == "ServerLuck" then
		return "Icon_Luck"
	end
	return PASS_ICONS[key] or "Icon_Star"
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
	return (if starterPackOnSale(data) then 1 else 0) + #liveOffers(data)
end

-------------------------------------------------------------------------- render

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
	giftPicker.Visible = true
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
	buy.BackgroundColor3 = color
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

local function buildCard(item: Item, order: number, color: Color3): Frame
	local card = cardTemplate:Clone()
	card.Name = "Card"
	card.LayoutOrder = order
	card.Visible = true
	-- Locked or owned cards go grey so the ones you can buy stand out.
	tint(card, if item.Enabled then color else GREY)
	Ui.find(card, "Name").Text = item.Name
	Ui.find(card, "Desc").Text = item.Desc
	Ui.find(card, "Icon").Image = AssetLibrary.image(item.Icon or "Icon_Shop")
	local tag = Ui.find(card, "Tag") :: Frame
	tag.Visible = item.Tag ~= nil
	if item.Tag then
		Ui.find(tag, "Label").Text = item.Tag
	end
	local buy = Ui.find(card, "Buy") :: TextButton
	setPrice(buy, item.Price, item.Color)
	local onBuy = item.OnBuy
	if item.Enabled and onBuy then
		Ui.button(buy, onBuy)
	end
	local gift = Ui.find(card, "Gift") :: TextButton
	local giftKey = item.GiftKey
	local alt = item.Alt
	gift.Visible = giftKey ~= nil or alt ~= nil
	if alt then
		-- Buy button makes room for the alt button on its right.
		buy.AnchorPoint = Vector2.new(0, 1)
		buy.Position = UDim2.new(0, 8, 1, -8)
		buy.Size = UDim2.new(1, -64, 0, 46)
		gift.BackgroundColor3 = alt.Color
		local altIcon = gift:FindFirstChild("Icon") :: ImageLabel?
		if altIcon then
			altIcon.Image = AssetLibrary.image(alt.Icon)
		end
		Ui.button(gift, alt.OnClick)
	elseif giftKey then
		-- Buy button makes room for the gift button on its right.
		buy.AnchorPoint = Vector2.new(0, 1)
		buy.Position = UDim2.new(0, 8, 1, -8)
		buy.Size = UDim2.new(1, -64, 0, 46)
		Ui.button(gift, function()
			openGiftPicker(giftKey)
		end)
	end
	return card
end

local function renderFeatured(data): boolean
	local show = starterPackOnSale(data)
	featured.Visible = show
	if show then
		local def = Products.ProductByKey.StarterPack
		local pack = Economy.StarterPack
		Ui.find(featured, "Desc").Text = `{Format.cash(pack.Cash)} + {pack.EggRarity} egg + {pack.Cash2xMinutes} min 2x cash`
		Ui.setText(Ui.find(featured, "Buy"), robuxPrice(def.Price))
	end
	return show
end

local function setLit(key: string?)
	if key == litTab then
		return
	end
	litTab = key
	for _, t in tabs do
		local on = t.key == key
		local lit = t.button:FindFirstChild("Lit") :: GuiObject?
		if lit then
			lit.Visible = on
		end
		local stroke = t.button:FindFirstChild("Stroke") :: UIStroke?
		if stroke then
			stroke.Color = if on then WHITE else INK
		end
	end
end

-- Lights the tab of the section at the top of the list.
local function followScroll()
	local y = list.CanvasPosition.Y + 40
	local best, bestTop = nil, -math.huge
	for key, top in sectionTop do
		if top <= y and top > bestTop then
			best, bestTop = key, top
		end
	end
	setLit(best or (tabs[1] and tabs[1].key))
end

local scrollTo: (string?) -> ()

local function buildTabs(entries: { { key: string, title: string, icon: string, color: Color3 } })
	for _, t in tabs do
		t.button:Destroy()
	end
	table.clear(tabs)
	litTab = nil
	for i, entry in entries do
		local button = tabTemplate:Clone()
		button.Name = "Tab_" .. entry.key
		button.LayoutOrder = i
		button.Visible = true
		tint(button, entry.color)
		Ui.setText(button, TAB_NAMES[entry.key] or entry.title)
		Ui.find(button, "Icon").Image = AssetLibrary.image(entry.icon)
		button.Parent = tabList
		local key = entry.key
		Ui.button(button, function()
			scrollTo(key)
			setLit(key)
		end)
		table.insert(tabs, { key = key, button = button })
	end
	followScroll()
end

local function render()
	local data = State.data
	if not data then
		return
	end
	Ui.setBadge(shopBadge, specialCount(data) + unlockableSkins(data))
	if not gui.Enabled then
		return
	end
	for _, child in list:GetChildren() do
		if child:GetAttribute("Built") then
			child:Destroy()
		end
	end
	table.clear(sectionTop)
	table.clear(offerTimers)
	local y = LIST_TOP_PAD
	local anything = false
	local tabEntries = {}
	if renderFeatured(data) then
		sectionTop.Offers = y
		y += FEATURED_H + LIST_GAP
		anything = true
	end
	for i, offer in liveOffers(data) do
		sectionTop.Offers = sectionTop.Offers or y
		local row = offerTemplate:Clone()
		row.Name = "Offer_" .. offer.Key
		row:SetAttribute("Built", true)
		row.LayoutOrder = 1 + i
		row.Visible = true
		Ui.find(row, "Title").Text = offer.Title
		Ui.find(row, "Desc").Text = offer.Text
		Ui.find(row, "Icon").Image = AssetLibrary.image(productIcon(offer.Product))
		setPrice(Ui.find(row, "Buy"), robuxPrice(offer.Price), ROBUX)
		local product = offer.Product
		Ui.button(Ui.find(row, "Buy"), function()
			prompt(product)
		end)
		table.insert(offerTimers, { Label = Ui.find(row, "Timer"), Expires = offer.Expires })
		row.Parent = list
		y += OFFER_H + LIST_GAP
		anything = true
	end
	for i, section in sections(data) do
		if #section.Items == 0 then
			continue
		end
		anything = true
		local frame = sectionTemplate:Clone()
		frame.Name = "Section_" .. section.Key
		frame:SetAttribute("Built", true)
		frame.LayoutOrder = 100 + i
		frame.Visible = true
		Ui.find(frame, "Rule").BackgroundColor3 = section.Color
		Ui.find(frame, "Title").Text = section.Title
		Ui.find(frame, "Note").Text = section.Note
		Ui.find(frame, "Icon").Image = AssetLibrary.image(section.Icon)
		table.insert(tabEntries, { key = section.Key, title = section.Title, icon = section.Icon, color = section.Color })
		local grid = Ui.find(frame, "Grid") :: Frame
		for n, item in section.Items do
			buildCard(item, n, section.Color).Parent = grid
		end
		local rows = math.ceil(#section.Items / COLUMNS)
		local height = HEADER_H + rows * CELL_H + (rows - 1) * CELL_GAP
		frame.Size = UDim2.new(1, 0, 0, height)
		sectionTop[section.Key] = y
		y += height + LIST_GAP
		frame.Parent = list
	end
	emptyLabel.Visible = not anything
	if sectionTop.Offers then
		table.insert(tabEntries, 1, { key = "Offers", title = "Offers", icon = "Icon_Star", color = Color3.fromRGB(255, 77, 94) })
	end
	local tabSig = {}
	for _, entry in tabEntries do
		table.insert(tabSig, entry.key)
	end
	local sig = table.concat(tabSig, ",")
	if sig ~= tabList:GetAttribute("Sig") or #tabs == 0 then
		tabList:SetAttribute("Sig", sig)
		buildTabs(tabEntries)
	else
		followScroll()
	end
end

local function tickTimers()
	local now = os.clock()
	local expired = false
	for _, timer in offerTimers do
		local left = timer.Expires - now
		timer.Label.Text = if left > 0 then `Ends in {Format.time(left)}` else "Ended"
		expired = expired or left <= 0
	end
	return expired
end

function scrollTo(section: string?)
	local top = if section then sectionTop[section] else 0
	if top == nil then
		return
	end
	local target = Vector2.new(0, math.max(0, top - LIST_TOP_PAD))
	if Ui.reducedMotion() then
		list.CanvasPosition = target
	else
		list.CanvasPosition = Vector2.zero
		TweenService:Create(list, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { CanvasPosition = target }):Play()
	end
end

function ShopController:Toggle()
	Ui.toggle("Shop")
	giftPicker.Visible = false
	render()
	list.CanvasPosition = Vector2.zero
end

-- Opens the shop, optionally scrolled to a section ("Boosts", "Passes", "Bases", "Tools", "Eggs", "Cash").
function ShopController:Open(section: string?)
	Ui.open("Shop")
	giftPicker.Visible = false
	render()
	list.CanvasPosition = Vector2.zero
	if section then
		task.defer(scrollTo, section)
	end
end

-- Called by OfferController when a new limited offer arrives.
function ShopController:Refresh()
	render()
end

function ShopController:Init(controllers)
	C = controllers
	gui = Ui.screen("Shop")
	list = Ui.find(gui, "Window.List")
	sectionTemplate = Ui.find(gui, "Window.List.Section")
	offerTemplate = Ui.find(gui, "Window.List.Offer")
	featured = Ui.find(gui, "Window.List.Featured")
	cardTemplate = Ui.find(gui, "Window.Card")
	emptyLabel = Ui.find(gui, "Window.Empty")
	giftPicker = Ui.find(gui, "Window.GiftPicker")
	giftList = Ui.find(gui, "Window.GiftPicker.List")
	giftTemplate = Ui.find(gui, "Window.GiftPicker.List.Template")
	giftEmpty = Ui.find(gui, "Window.GiftPicker.Empty")
	shopBadge = Ui.find(Ui.screen("Hud"), "Rail.ShopButton.Badge")
	tabList = Ui.find(gui, "Window.Tabs.List")
	tabTemplate = Ui.find(gui, "Window.Tabs.List.Template")
end

function ShopController:Start()
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Shop")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Shop")
	end)
	Ui.button(Ui.find(featured, "Buy"), function()
		prompt("StarterPack")
	end)
	Ui.button(Ui.find(gui, "Window.GiftPicker.Close"), function()
		giftPicker.Visible = false
	end)
	list:GetPropertyChangedSignal("CanvasPosition"):Connect(followScroll)
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
		local indexCount = 0
		for _ in data.Index or {} do
			indexCount += 1
		end
		local skins = data.BaseSkins
		local owned = {}
		for id in (skins and skins.Owned) or {} do
			table.insert(owned, id)
		end
		table.sort(owned)
		local signature = table.concat({
			data.ToolTier,
			data.EffectiveTier,
			tostring(BigNum.gte(data.Cash, nextTool.Price)),
			tostring(data.Flags.StarterPackBought),
			data.Rebirths,
			if data.CashPacks and data.CashPacks.Cash1 then Format.cash(data.CashPacks.Cash1) else "",
			table.concat(hatching, ","),
			table.concat(passes, ","),
			indexCount,
			table.concat(owned, ","),
			if skins then skins.Equipped else "",
		}, "|")
		if signature ~= lastSignature then
			lastSignature = signature
			render()
		end
	end)
	-- Offer timers, and the rail badge when a limited offer runs out.
	task.spawn(function()
		local lastCount = -1
		while true do
			task.wait(1)
			local data = State.data
			if data then
				local count = specialCount(data) + unlockableSkins(data)
				if tickTimers() or count ~= lastCount then
					lastCount = count
					render()
				end
			end
		end
	end)
end

return ShopController
