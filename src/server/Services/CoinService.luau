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
local Net = require(Shared.Net)

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
	return Economy.Coins.MagnetBase + Economy.Coins.MagnetPerLevel * magnet
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
	S.StateService:Mark(player)
end

-- Drops `amount` cash as `count` coins flying out of `origin` and landing around `center`
-- (between minR and maxR studs away).
function CoinService:Drop(player: Player, amount: number, origin: Vector3, center: Vector3, count: number, minR: number, maxR: number)
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
	local sent = {}
	for _ = 1, count do
		nextId += 1
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(minR, maxR)
		local pos = Vector3.new(center.X + math.cos(a) * r, center.Y, center.Z + math.sin(a) * r)
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
