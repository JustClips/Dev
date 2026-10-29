--!strict
-- The upgrade tree (Config/Upgrades). Other services read stats through
-- Upgrades.multiplier / Upgrades.stat; this service sells levels, applies walk speed to the
-- character and clears the tree on rebirth.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Upgrades = require(Shared.Config.Upgrades)

local UpgradeService = {}

local S: any

local function applyWalkSpeed(player: Player)
	local data = S.DataService:GetData(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if data and humanoid then
		humanoid.WalkSpeed = Upgrades.walkSpeed(data.Upgrades) + S.BoostService:GetSpeedBonus(player)
	end
end

-- Re-applies walk speed (Moon Boots + Speed potion).
function UpgradeService:ApplyWalkSpeed(player: Player)
	applyWalkSpeed(player)
end

function UpgradeService:GetLevel(player: Player, id: string): number
	local data = S.DataService:GetData(player)
	return if data then data.Upgrades[id] or 0 else 0
end

-- Buys up to `count` levels of a tree node (count > 1 = the "Max" button: as many as you
-- can afford, up to that many). Returns ok and a message for the toast.
function UpgradeService:Buy(player: Player, id: string, count: number?): (boolean, string)
	local data = S.DataService:GetData(player)
	local def = if type(id) == "string" then Upgrades.ById[id] else nil
	if not data or not def then
		return false, "Unknown upgrade"
	end
	local want = if type(count) == "number" and count == count then math.clamp(math.floor(count), 1, 100) else 1
	local bought = 0
	for _ = 1, want do
		local level = data.Upgrades[def.Id] or 0
		local blocked = Upgrades.blocked(def, data.Upgrades, data.Rebirths)
		if blocked then
			if bought == 0 then
				return false, if blocked == "Maxed" then `{def.Name} is maxed!` else blocked
			end
			break
		end
		local cost = Upgrades.cost(def, level)
		if not S.BackpackService:TrySpend(player, cost, "Upgrade_" .. def.Id, bought > 0) then
			if bought == 0 then
				return false, `Need {Format.cash(cost)}`
			end
			break
		end
		data.Upgrades[def.Id] = level + 1
		bought += 1
	end
	if def.Stat == "Speed" then
		applyWalkSpeed(player)
	elseif def.Stat == "Incubators" or def.Stat == "PetIncome" then
		S.AlienService:RefreshBase(player)
	end
	S.StateService:Mark(player)
	local level = data.Upgrades[def.Id]
	if def.Opens then
		return true, `{def.Name} unlocked! Tap it to go inside`
	end
	if level == 1 and #Upgrades.Children[def.Id] > 0 then
		return true, `{def.Name} unlocked! New upgrades opened`
	end
	return true, `{def.Name} level {level}: {Upgrades.describe(def, level)}`
end

function UpgradeService:ResetForRebirth(player: Player)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	table.clear(data.Upgrades)
	applyWalkSpeed(player)
	S.StateService:Mark(player)
end

function UpgradeService:Init(services)
	S = services
	Net.onInvoke("BuyUpgrade", function(player, id, count)
		return UpgradeService:Buy(player, id, count)
	end)
	S.BaseService.CharacterReady:Connect(function(player: Player, character: Model)
		character:WaitForChild("Humanoid", 10)
		applyWalkSpeed(player)
	end)
end

-- The Speed potion runs out on its own: re-apply speed when it ends.
function UpgradeService:Start()
	task.spawn(function()
		while true do
			task.wait(2)
			for player, session in S.DataService:GetSessions() do
				local fast = S.BoostService:GetSpeedBonus(player) > 0
				if session.Runtime.SpeedPotion ~= fast then
					session.Runtime.SpeedPotion = fast
					applyWalkSpeed(player)
				end
			end
		end
	end)
end

return UpgradeService
