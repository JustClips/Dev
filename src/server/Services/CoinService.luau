--!strict
-- Coins from selling (Dev, 2026-10-30, like Pet Simulator / Slime RNG). Selling leaves
-- bursts coins out (from the leaf dump, or around you with Sell Anywhere). Only you see
-- your coins (CoinController): walk near them and they fly into you. The Money Magnet
-- upgrades widen the pickup range. The server keeps the cash until a coin is collected,
-- and pays out any coin still lying around after Economy.Coins.AutoCollectSeconds (it
-- flies to you), so nobody loses money by walking away or being AFK.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Grid = require(Shared.Grid)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local World = require(Shared.Config.World)

local CoinService = {}

local S: any

type Coin = { value: number, pos: Vector3, expires: number }
local pending: { [Player]: { [number]: Coin } } = {}
local nextId = 0
local rng = Random.new()

-- Pickup range in studs: grows with the Money Magnet line of upgrades.
function CoinService:MagnetRange(player: Player): number
	local data = S.DataService:GetData(player)
	local levels = if data then data.Upgrades else {}
	local magnet = 0
	for _, id in Economy.Coins.MagnetUpgrades do
		magnet += levels[id] or 0
	end
	local potion = if S.BoostService:IsBoostActive(player, "Magnet") then Items.MagnetBonus else 0
	return Economy.Coins.MagnetBase + Economy.Coins.MagnetPerLevel * magnet + potion
end

local function credit(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	data.Cash = BigNum.add(data.Cash, amount)
	S.LeaderboardService:AddEarned(player, amount)
	S.StateService:Mark(player)
end

-- Leaf tiles between minR and maxR studs from center (and, with facing, only in front of
-- it) where coins may land: only on the leaf field, never on the market hall or the dumps
-- (Dev, 2026-10-30).
local HALL_CLEAR = World.RocketClearRadius + 5
local function landingTiles(center: Vector3, minR: number, maxR: number, facing: Vector3?): { number }
	local tiles = {}
	local hall = Vector2.new(World.RocketPosition.X, World.RocketPosition.Z)
	Grid.forEachInRadius(center, maxR, function(id)
		local pos = Grid.tilePosition(id)
		if not pos then
			return
		end
		local d = Vector3.new(pos.X - center.X, 0, pos.Z - center.Z)
		if d.Magnitude < minR or (Vector2.new(pos.X, pos.Z) - hall).Magnitude < HALL_CLEAR then
			return
		end
		if facing and d.Magnitude > 0 and d.Unit:Dot(facing) < 0.3 then
			return
		end
		table.insert(tiles, id)
	end)
	return tiles
end

-- Drops `amount` cash as `count` coins flying out of `origin` and landing on leaf tiles
-- around `center` (between minR and maxR studs away; with `facing`, only in front). With no
-- leaf tiles nearby (Sell Anywhere at your base) they land in a ring around center.
-- `ring`: land in a plain circle around `center` (minR..maxR) instead of on leaf tiles
-- (the leaf dumps: coins pile up around the bin, Dev 2026-11-01).
function CoinService:Drop(player: Player, amount: number, origin: Vector3, center: Vector3, count: number, minR: number, maxR: number, facing: Vector3?, ring: boolean?)
	if amount <= 0 then
		return
	end
	if not player.Parent then
		credit(player, amount) -- leaving: straight into the save
		return
	end
	local mine = pending[player]
	if not mine then
		mine = {}
		pending[player] = mine
	end
	player:SetAttribute("CoinMagnet", CoinService:MagnetRange(player))
	count = math.max(1, count)
	local each = amount / count
	local expires = os.clock() + Economy.Coins.AutoCollectSeconds
	local flat = if facing then Vector3.new(facing.X, 0, facing.Z) else nil
	local tiles = if ring then {} else landingTiles(center, minR, maxR, if flat and flat.Magnitude > 0 then flat.Unit else nil)
	local sent = {}
	for _ = 1, count do
		nextId += 1
		local pos: Vector3
		local tile = if #tiles > 0 then Grid.tilePosition(tiles[rng:NextInteger(1, #tiles)]) else nil
		if tile then
			local zone = Grid.zoneAt(tile)
			local jitter = (if zone then zone.TileSize else 4) * 0.35
			pos = tile + Vector3.new(rng:NextNumber(-jitter, jitter), 0, rng:NextNumber(-jitter, jitter))
		else
			local a = rng:NextNumber(0, math.pi * 2)
			if ring and flat and flat.Magnitude > 0 then
				-- The front half only (round the side the player stands on, clear of the
				-- market hall or the Pet Trader behind the bin).
				a = math.atan2(flat.Z, flat.X) + rng:NextNumber(-1.9, 1.9)
			end
			local r = if ring then rng:NextNumber(minR, maxR) else rng:NextNumber(math.min(minR, 3), math.min(maxR, 9))
			pos = Vector3.new(center.X + math.cos(a) * r, center.Y, center.Z + math.sin(a) * r)
		end
		mine[nextId] = { value = each, pos = pos, expires = expires }
		table.insert(sent, { Id = nextId, Pos = pos, Value = each })
	end
	Net.fire("CoinsDropped", player, origin, sent)
end

-- Pays out everything still lying around (leaving, or the server closing).
local function collectAll(player: Player)
	local mine = pending[player]
	pending[player] = nil
	if not mine then
		return
	end
	local total = 0
	for _, coin in mine do
		total += coin.value
	end
	credit(player, total)
end

function CoinService:Init(services)
	S = services
	Net.onEvent("CoinsCollect", function(player: Player, ids: any)
		local mine = pending[player]
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not mine or not root or type(ids) ~= "table" then
			return
		end
		-- A little slack for lag and for coins flying to you on the way in.
		local reach = CoinService:MagnetRange(player) + 12
		local total = 0
		for i, id in ids do
			if i > 60 then
				break
			end
			local coin = type(id) == "number" and mine[id] or nil
			if coin then
				local d = root.Position - coin.pos
				if Vector2.new(d.X, d.Z).Magnitude <= reach then
					mine[id] = nil
					total += coin.value
				end
			end
		end
		credit(player, total)
	end)
	-- Before the save is written and released.
	S.DataService.ProfileReleasing:Connect(function(player)
		collectAll(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)
end

function CoinService:Start()
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for player, mine in pending do
				local due = {}
				local total = 0
				for id, coin in mine do
					if coin.expires <= now then
						mine[id] = nil
						total += coin.value
						table.insert(due, id)
					end
				end
				if #due > 0 then
					credit(player, total)
					Net.fire("CoinsAuto", player, due)
				end
			end
		end
	end)
end

return CoinService
