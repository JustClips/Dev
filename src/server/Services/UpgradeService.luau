--!strict
-- The upgrade tree (Config/Upgrades). Other services read stats through
-- Upgrades.multiplier / Upgrades.stat; this service sells levels, applies walk speed to the
-- character and clears the tree on rebirth.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Economy = require(Shared.Config.Economy)
local Tools = require(Shared.Config.Tools)
local Upgrades = require(Shared.Config.Upgrades)

local UpgradeService = {}

local S: any

local function applyWalkSpeed(player: Player)
	local data = S.DataService:GetData(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if data and humanoid then
		local pass = if data.Gamepasses.FastWalk then Economy.FastWalkMult else 1
		humanoid.WalkSpeed = Upgrades.walkSpeed(data.Upgrades) * pass + S.BoostService:GetSpeedBonus(player)
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
				return false, if blocked == "Maxed" then `{Upgrades.name(def, level)} is maxed!` else blocked
			end
			break
		end
		local cost = Upgrades.cost(def, level)
		if def.Id == "Power" and level == 0 then
			cost = Tools.tutorialPrice(cost, BigNum.toNumber(data.Cash), data.Flags.TutorialDone == true)
		end
		if not S.BackpackService:TrySpend(player, cost, "Upgrade_" .. def.Id, bought > 0) then
			if bought == 0 then
				return false, `Need {Format.cash(cost)}`
			end
			break
		end
		data.Upgrades[def.Id] = level + 1
		data.Stats.Upgrades = (data.Stats.Upgrades or 0) + 1 -- quests
		bought += 1
	end
	if def.Stat == "Speed" then
		applyWalkSpeed(player)
	elseif def.Stat == "Incubators" or def.Stat == "PetIncome" or def.Stat == "PassivePower" then
		S.AlienService:RefreshBase(player)
	elseif def.Stat == "Cash" then
		player:SetAttribute("CoinMagnet", S.CoinService:MagnetRange(player))
	end
	S.StateService:Mark(player)
	local level = data.Upgrades[def.Id]
	S.AnalyticsService:Custom(player, "UpgradeBought", level, { Upgrade = def.Id })
	if def.Opens then
		return true, `{def.Name} unlocked! Tap it to go inside`
	end
	if level == 1 and #Upgrades.Children[def.Id] > 0 then
		return true, `{def.Name} unlocked! New upgrades opened`
	end
	if level >= def.MaxLevel then
		return true, `{def.Name} maxed! {Upgrades.describe(def, level)} {Upgrades.Stats[def.Stat].Name}`
	end
	return true, `{def.Name} {level}/{def.MaxLevel}: {Upgrades.describe(def, level)} {Upgrades.Stats[def.Stat].Name}`
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

-- Tree remakes: hexes removed in the 2026-10-30 remake (Retired) and every level bought
-- before the 2026-10-31 rebuild (OldTree, when Flags.UpgradeTreeV is behind) are paid back
-- in cash, and the player starts the new tree fresh.
local function refundRetired(player: Player, session)
	local data = session.Data
	local levels = data.Upgrades
	local rebuilt = (data.Flags.UpgradeTreeV or 0) < Upgrades.Version
	local total = 0
	for id, level in levels do
		if Upgrades.Retired[id] then
			total += Upgrades.retiredRefund(id, level)
			levels[id] = nil
		elseif rebuilt then
			total += Upgrades.oldTreeRefund(id, level)
			levels[id] = nil
		elseif not Upgrades.ById[id] then
			levels[id] = nil
		end
	end
	data.Flags.UpgradeTreeV = Upgrades.Version
	if total > 0 then
		S.BackpackService:GiveCash(player, total, "UpgradeRefund")
		task.delay(6, function()
			if player.Parent then
				Net.fire(
					"Notify",
					player,
					`The upgrade tree got rebuilt! You got back {Format.cash(total)} to spend on it.`,
					"Good"
				)
			end
		end)
	end
	if rebuilt then
		applyWalkSpeed(player)
	end
end

function UpgradeService:Init(services)
	S = services
	S.DataService.ProfileLoaded:Connect(refundRetired)
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
				-- Potions and admin speed events change the bonus; re-apply when it does.
				local bonus = S.BoostService:GetSpeedBonus(player)
				if session.Runtime.SpeedBonus ~= bonus then
					session.Runtime.SpeedBonus = bonus
					applyWalkSpeed(player)
				end
			end
		end
	end)
end

return UpgradeService
