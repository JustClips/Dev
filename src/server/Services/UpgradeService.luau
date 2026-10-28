--!strict
-- Cash upgrades (Config/Upgrades): Bigger Backpack, Sweep Power, Moon Boots, Egg Luck.
-- Other services read the levels through Upgrades.multiplier; this service sells levels,
-- applies walk speed to the character and resets everything on rebirth.
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

function UpgradeService:Buy(player: Player, id: string): (boolean, string)
	local data = S.DataService:GetData(player)
	local def = if type(id) == "string" then Upgrades.ById[id] else nil
	if not data or not def then
		return false, "Unknown upgrade"
	end
	local level = data.Upgrades[def.Id] or 0
	if level >= def.MaxLevel then
		return false, `{def.Name} is maxed!`
	end
	local cost = Upgrades.cost(def, level)
	if not S.BackpackService:TrySpend(player, cost, "Upgrade_" .. def.Id) then
		return false, `Need {Format.cash(cost)}`
	end
	data.Upgrades[def.Id] = level + 1
	if def.Id == "Speed" then
		applyWalkSpeed(player)
	end
	S.StateService:Mark(player)
	return true, `{def.Name} level {level + 1}: {Upgrades.describe(def, level + 1)}`
end

function UpgradeService:ResetForRebirth(player: Player)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	for _, def in Upgrades.List do
		data.Upgrades[def.Id] = 0
	end
	applyWalkSpeed(player)
	S.StateService:Mark(player)
end

function UpgradeService:Init(services)
	S = services
	Net.onInvoke("BuyUpgrade", function(player, id)
		return UpgradeService:Buy(player, id)
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
