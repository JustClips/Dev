--!strict
-- The Traveling Merchant (Config/Merchant). His cart stands in the plaza (MapBuilder); while
-- he's visiting, he stands behind the counter with his goods and the "Shop" prompt opens
-- the Merchant window (MerchantController). Every server uses the same clock and the same
-- stock, so a rare ware is news everywhere at once.
--
-- Remote "Merchant": ("Get") -> ok, message, state; ("Buy", wareId) -> ok, message, state.
-- state = { Here, Visit, ChangesAt, Wares = { {Id, Item?, Egg?, Price, Left, Stock} } }.
-- Robux "Restock" (Products Kind "MerchantRestock") rolls the buyer their own fresh stock.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Items = require(Shared.Config.Items)
local Merchant = require(Shared.Config.Merchant)
local Net = require(Shared.Net)
local Upgrades = require(Shared.Config.Upgrades)
local World = require(Shared.Config.World)
local Zones = require(Shared.Config.Zones)

local MerchantService = {}

local S: any
local SHOP_DISTANCE = 22 -- server check: you must stand near the cart to buy
local rare = { Legendary = true, Epic = true }

-- Your merchant record for this visit (purchases reset every visit).
local function record(data, visit: number)
	local m = data.Merchant
	if type(m) ~= "table" then
		m = {}
		data.Merchant = m
	end
	if m.Visit ~= visit then
		m.Visit = visit
		m.Bought = {}
		m.Reroll = nil
	end
	m.Bought = m.Bought or {}
	return m
end

local function slots(data): number
	return math.min(Merchant.MaxSlots, Merchant.Slots + math.floor(Upgrades.stat(data.Upgrades, "MerchantSlots") + 0.5))
end

local function personalSeed(player: Player, m): number
	return if m.Reroll then (player.UserId % 1_000_000) * 31 + m.Reroll else 0
end

local function price(player: Player, data, ware: Merchant.Ware): number
	local discount = math.clamp(Upgrades.stat(data.Upgrades, "MerchantDiscount"), 0, 0.5)
	local base = S.ShopService:CashFor(player, ware.Seconds, 0)
	return math.floor(math.max(Merchant.MinPrice, base) * (1 - discount))
end

-- Best unlocked zone that can drop this rarity (the egg hatches into that zone's pets).
local function eggZone(data, rarity: string): string
	local best = "Landing"
	for _, zone in Zones.List do
		if data.ZonesUnlocked[zone.Id] and Eggs.order(zone.MaxRarity) >= Eggs.order(rarity) then
			best = zone.Id
		end
	end
	return best
end

local function state(player: Player): { [string]: any }?
	local data = S.DataService:GetData(player)
	if not data then
		return nil
	end
	local visit, here, changesAt = Merchant.visitAt(os.time())
	local m = record(data, visit)
	local wares = {}
	if here then
		for _, ware in Merchant.shown(visit, personalSeed(player, m), slots(data)) do
			table.insert(wares, {
				Id = ware.Id,
				Item = ware.Item,
				Egg = ware.Egg,
				Price = price(player, data, ware),
				Stock = ware.Stock,
				Left = math.max(0, ware.Stock - (m.Bought[ware.Id] or 0)),
			})
		end
	end
	return { Here = here, Visit = visit, ChangesAt = changesAt, Wares = wares, Restocked = m.Reroll ~= nil }
end

local function near(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local d = root.Position - World.Merchant.Position
	return Vector2.new(d.X, d.Z).Magnitude <= SHOP_DISTANCE
end

local function buy(player: Player, wareId: any): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data or type(wareId) ~= "string" then
		return false, "Still loading"
	end
	local visit, here = Merchant.visitAt(os.time())
	if not here then
		return false, "The merchant has left. He'll be back soon!"
	end
	if not near(player) then
		return false, "Walk up to the merchant's cart first"
	end
	local m = record(data, visit)
	local ware: Merchant.Ware? = nil
	for _, w in Merchant.shown(visit, personalSeed(player, m), slots(data)) do
		if w.Id == wareId then
			ware = w
		end
	end
	if not ware then
		return false, "He doesn't have that right now"
	end
	local bought = m.Bought[ware.Id] or 0
	if bought >= ware.Stock then
		return false, "Sold out! Come back next visit."
	end
	if ware.Egg and S.InventoryService:EggCount(player) >= Economy.EggBagSize then
		return false, "Your egg bag is full! Place some eggs first."
	end
	local cost = price(player, data, ware)
	if not S.BackpackService:TrySpend(player, cost, "Merchant_" .. ware.Id) then
		return false, `Need {Format.cash(cost)}`
	end
	m.Bought[ware.Id] = bought + 1
	local name
	if ware.Item then
		local def = Items.ById[ware.Item]
		S.InventoryService:AddItem(player, ware.Item, 1)
		name = def.Name
		if rare[def.Rarity] then
			Net.fireAll("Announce", `{player.DisplayName} bought a {def.Name} from the Traveling Merchant!`, "Event")
		end
	else
		local rarity = ware.Egg or "Rare"
		S.InventoryService:AddEgg(player, rarity, eggZone(data, rarity), true)
		name = `{rarity} Egg`
	end
	S.StateService:Mark(player)
	S.AnalyticsService:Custom(player, "MerchantBuy", 1, { Ware = ware.Id })
	return true, `Bought a {name}! It's in your bag.`
end

-- Robux restock (ShopService grant): a fresh set of wares just for this player.
function MerchantService:Restock(player: Player)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	local visit = Merchant.visitAt(os.time())
	local m = record(data, visit)
	m.Reroll = (m.Reroll or 0) + 1
	m.Bought = {}
	Net.fire("Notify", player, "The merchant unpacked new wares just for you!", "Good")
	Net.fire("MerchantRestocked", player)
end

function MerchantService:CanRestock(): boolean
	local _, here = Merchant.visitAt(os.time())
	return here
end

-- The cart: the merchant and his goods show only while he's visiting.
local goods: Folder? = nil
local merchantModel: Model? = nil
local prompt: ProximityPrompt? = nil

local function buildMerchant(): Model?
	local cart = Workspace:FindFirstChild("Structures") and (Workspace :: any).Structures:FindFirstChild("MerchantCart")
	if not cart then
		return nil
	end
	local d = Instance.new("HumanoidDescription")
	d.HeadColor = Color3.fromRGB(240, 200, 160)
	d.LeftArmColor = d.HeadColor
	d.RightArmColor = d.HeadColor
	d.TorsoColor = Color3.fromRGB(150, 60, 160)
	d.LeftLegColor = Color3.fromRGB(70, 50, 40)
	d.RightLegColor = d.LeftLegColor
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		return nil
	end
	model.Name = "Merchant"
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		model:Destroy()
		return nil
	end
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = part == root
		end
	end
	local height = if humanoid then humanoid.HipHeight + root.Size.Y / 2 else 3
	-- Behind the counter, facing the field.
	model:PivotTo(World.Merchant * CFrame.new(0, 2.3 + height, 0.4))
	return model
end

local function crate(parent: Instance, cf: CFrame, color: Color3)
	local p = Instance.new("Part")
	p.Name = "Crate"
	p.Size = Vector3.new(1.2, 1, 1.2)
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.WoodPlanks
	p.Anchored = true
	p.Parent = parent
end

local function setHere(here: boolean)
	if not goods then
		local cart = Workspace:FindFirstChild("Structures") and (Workspace :: any).Structures:FindFirstChild("MerchantCart")
		goods = cart and cart:FindFirstChild("Goods")
		local counter = cart and cart:FindFirstChild("Counter")
		prompt = counter and counter:FindFirstChild("MerchantPrompt") :: ProximityPrompt?
	end
	if prompt then
		prompt.Enabled = here
	end
	local folder = goods
	if not folder then
		return
	end
	if here and #folder:GetChildren() == 0 then
		merchantModel = buildMerchant()
		if merchantModel then
			merchantModel.Parent = folder
		end
		local base = World.Merchant
		crate(folder, base * CFrame.new(-3, 4, -1.2), Color3.fromRGB(196, 142, 92))
		crate(folder, base * CFrame.new(3.1, 4, -1.1) * CFrame.Angles(0, 0.4, 0), Color3.fromRGB(170, 120, 80))
		crate(folder, base * CFrame.new(-3.5, 2.8, 1.6), Color3.fromRGB(150, 100, 64))
	elseif not here then
		folder:ClearAllChildren()
		merchantModel = nil
	end
end

function MerchantService:Init(services)
	S = services
	-- Joining while he's visiting: tell them he's here.
	S.DataService.ProfileLoaded:Connect(function(player)
		task.delay(10, function()
			local _, here, changesAt = Merchant.visitAt(os.time())
			if player.Parent and here and changesAt - os.time() > 60 then
				Net.fire("Notify", player, "The Traveling Merchant is in the plaza right now!", "Rare")
			end
		end)
	end)
	Net.onInvoke("Merchant", function(player, action, arg)
		if action == "Get" then
			return true, nil, state(player)
		elseif action == "Buy" then
			local ok, message = buy(player, arg)
			return ok, message, state(player)
		end
		return false, "Unknown action", nil
	end)
end

function MerchantService:Start()
	task.spawn(function()
		local lastHere: boolean? = nil
		local warned = -1
		while true do
			local visit, here, changesAt = Merchant.visitAt(os.time())
			if here ~= lastHere then
				setHere(here)
				if here and lastHere ~= nil then
					-- Name the rarest ware so players know if it's worth the walk.
					local best: Merchant.Ware? = nil
					for _, ware in Merchant.shown(visit, 0, Merchant.Slots) do
						if not best or ware.Weight < best.Weight then
							best = ware
						end
					end
					local tease = ""
					if best then
						local def = best.Item and Items.ById[best.Item]
						tease = ` He has a {if def then def.Name else `{best.Egg} Egg`}!`
					end
					-- One toast for everyone (Dev, 2026-10-30: an announcement plus a toast showed
					-- the same news twice).
					Net.fireAll("Notify", `The Traveling Merchant is in the plaza for {Merchant.StaySeconds // 60} min!{tease}`, "Rare")
				end
				lastHere = here
			end
			if here and changesAt - os.time() <= 60 and warned ~= visit then
				warned = visit
				Net.fireAll("Notify", "The Traveling Merchant leaves in 1 minute!", "Good")
			end
			task.wait(1)
		end
	end)
end

return MerchantService
