--!strict
-- Leaf drops (Slime RNG style, Dev asked 2026-10-30) and Treasure Map chests.
--
-- Leaf drops: every leaf pile you clear has a small chance (Config/Items DropChance, more
-- with the Lucky Finds hex) to drop something: mostly coin pouches, sometimes potions, now
-- and then something rare. It pops out of the pile and lies on the ground with a glow in
-- its rarity's colour; walk near it (your coin magnet range) and it flies into you. Only
-- you see your drops (DropController). Left alone for Items.DropSeconds, it comes to you.
--
-- Treasure Map: marks a buried chest on a leaf pile in your field. Sweep that pile to dig
-- it up: cash, an item and sometimes an egg.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Grid = require(Shared.Grid)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Format = require(Shared.Format)

local DropService = {}

local S: any
local rng = Random.new()
local MAX_PENDING = 40
local REACH_SLACK = 12

type Drop = { item: string?, cash: number?, pos: Vector3, expires: number }
local pending: { [Player]: { [number]: Drop } } = {}
local lastDrop: { [Player]: number } = {}
local nextId = 0

local TREASURE_MIN, TREASURE_MAX = 28, 75 -- studs from you
local CHEST_CASH_SECONDS = 300 -- 5 min of earnings
local CHEST_EGG_CHANCE = 0.35

local function grant(player: Player, drop: Drop, auto: boolean)
	if drop.item then
		local def = Items.ById[drop.item]
		if not def then
			return
		end
		S.InventoryService:AddItem(player, def.Id, 1)
		if not auto then
			Net.fire("Notify", player, `Found a {def.Name}! It's in your bag.`, if def.Rarity == "Common" then "Good" else "Rare")
		end
		-- Big finds are news for the whole server.
		if def.Rarity == "Legendary" then
			Net.fireAll("Announce", `{player.DisplayName} found a {def.Name} in the leaves!`, "Event")
		end
	elseif drop.cash then
		S.BackpackService:GiveCash(player, drop.cash, "LeafDrop")
	end
end

-- Rolls one leaf drop at a tile (SweepService, on the Lucky Finds chance).
function DropService:LeafDrop(player: Player, at: Vector3)
	local now = os.clock()
	if now - (lastDrop[player] or -math.huge) < Items.DropGap then
		return
	end
	lastDrop[player] = now
	local mine = pending[player]
	if not mine then
		mine = {}
		pending[player] = mine
	end
	local count = 0
	for _ in mine do
		count += 1
	end
	if count >= MAX_PENDING then
		return
	end
	local roll = Items.rollDrop(rng)
	local drop: Drop = { pos = at + Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)), expires = os.clock() + Items.DropSeconds }
	if roll.Item then
		drop.item = roll.Item
	else
		drop.cash = S.ShopService:CashFor(player, roll.Cash or 10, 0)
	end
	nextId += 1
	mine[nextId] = drop
	Net.fire("ItemsDropped", player, { { Id = nextId, Pos = drop.pos, Item = drop.item, Cash = drop.cash } })
end

local function collectAll(player: Player)
	local mine = pending[player]
	pending[player] = nil
	for _, drop in mine or {} do
		grant(player, drop, true)
	end
end

-- Treasure ---------------------------------------------------------------------------------

local function treasureOf(player: Player): (number?, Vector3?)
	local data = S.DataService:GetData(player)
	local id = data and data.Flags.TreasureTile
	if type(id) ~= "number" then
		return nil, nil
	end
	return id, Grid.tilePosition(id)
end

local function showTreasure(player: Player)
	local _, pos = treasureOf(player)
	Net.fire("Treasure", player, pos)
end

function DropService:StartTreasure(player: Player): (boolean, string?)
	local data = S.DataService:GetData(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not data or not root then
		return false, "Still loading"
	end
	if treasureOf(player) then
		showTreasure(player)
		return false, "Dig up your last treasure first! Follow the red X."
	end
	local zone = Grid.zoneAt(root.Position)
	if not zone or not S.ZoneService:IsUnlocked(player, zone.Id) then
		return false, "Stand in a leaf field to read the map"
	end
	local spots = {}
	Grid.forEachInRadius(root.Position, TREASURE_MAX, function(id)
		local pos = Grid.tilePosition(id)
		if pos and Grid.zoneAt(pos) == zone and not S.DustService:IsCleared(player, id) then
			local d = Vector2.new(pos.X - root.Position.X, pos.Z - root.Position.Z).Magnitude
			if d >= TREASURE_MIN then
				table.insert(spots, id)
			end
		end
	end)
	if #spots == 0 then
		return false, "No good digging spot here. Try the middle of a field!"
	end
	data.Flags.TreasureTile = spots[rng:NextInteger(1, #spots)]
	showTreasure(player)
	return true, "A chest is buried nearby! Sweep the pile under the red X."
end

local function digUp(player: Player, at: Vector3)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	data.Flags.TreasureTile = nil
	local found = {}
	local cash = S.ShopService:CashFor(player, CHEST_CASH_SECONDS, 0.2)
	S.BackpackService:GiveCash(player, cash, "TreasureChest")
	table.insert(found, Format.cash(cash))
	local item = Items.rollItem(rng, "Epic")
	S.InventoryService:AddItem(player, item.Id, 1)
	table.insert(found, item.Name)
	if rng:NextNumber() < CHEST_EGG_CHANCE then
		local zone = Grid.zoneAt(at)
		local luck = S.BoostService:GetServerLuck() * S.BoostService:GetPersonalLuck(player)
		local rarity = S.EggService:RollRarity(if zone then zone.MaxRarity else "Rare", luck * 3)
		if S.InventoryService:AddEgg(player, rarity, if zone then zone.Id else nil, true) then
			table.insert(found, `a {rarity} Egg`)
		end
	end
	Net.fire("Treasure", player, nil, at)
	Net.fire("Notify", player, `Treasure! You dug up {table.concat(found, ", ")}!`, "Rare")
	S.AnalyticsService:Custom(player, "TreasureFound", 1)
end

-- Every tile this player clears (SweepService): digs up their treasure when it's the one.
function DropService:OnTileCleared(player: Player, id: number, at: Vector3)
	local data = S.DataService:GetData(player)
	if data and data.Flags.TreasureTile == id then
		digUp(player, at)
	end
end

function DropService:Init(services)
	S = services
	Net.onEvent("ItemsCollect", function(player: Player, ids: any)
		local mine = pending[player]
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not mine or not root or type(ids) ~= "table" then
			return
		end
		local reach = S.CoinService:MagnetRange(player) + REACH_SLACK
		for i, id in ids do
			if i > 20 then
				break
			end
			local drop = type(id) == "number" and mine[id] or nil
			if drop then
				local d = root.Position - drop.pos
				if Vector2.new(d.X, d.Z).Magnitude <= reach then
					mine[id] = nil
					grant(player, drop, false)
				end
			end
		end
	end)
	S.DataService.ProfileReleasing:Connect(collectAll)
	S.DataService.ProfileLoaded:Connect(function(player)
		-- An unfinished treasure from last time: show its X again.
		task.delay(8, function()
			if player.Parent and treasureOf(player) then
				showTreasure(player)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		lastDrop[player] = nil
	end)
end

function DropService:Start()
	-- Keep each player's pickup range up to date (potions run out, upgrades change it);
	-- coins and drops fly in from this range on the client.
	task.spawn(function()
		while true do
			task.wait(2)
			for _, player in Players:GetPlayers() do
				if S.DataService:GetData(player) then
					player:SetAttribute("CoinMagnet", S.CoinService:MagnetRange(player))
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for player, mine in pending do
				local due = {}
				for id, drop in mine do
					if drop.expires <= now then
						mine[id] = nil
						grant(player, drop, true)
						table.insert(due, id)
					end
				end
				if #due > 0 then
					Net.fire("ItemsAuto", player, due)
				end
			end
		end
	end)
end

return DropService
