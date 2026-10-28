--!strict
-- Hatching on base slots. Timers are saved as unix EndsAt so they keep running offline.
-- Mutations roll at hatch time and scale with server luck.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Aliens = require(Shared.Config.Aliens)
local Eggs = require(Shared.Config.Eggs)
local Net = require(Shared.Net)

local CHECK_SECONDS = 0.5

local HatchService = {}

local S: any
local rng = Random.new()

local function usedSlots(data): { [number]: boolean }
	local used = {}
	for _, alien in data.Aliens do
		used[alien.Slot] = true
	end
	for _, entry in data.Hatching do
		used[entry.Slot] = true
	end
	return used
end

local function alienIncome(alien): number
	local def = Aliens.ById[alien.Id]
	local mutation = alien.Mutation and Eggs.MutationByName[alien.Mutation]
	return (if def then def.Income else 0) * (if mutation then mutation.IncomeMult else 1)
end

-- Lowest free slot. If the base is full, an egg of a higher rarity replaces the weakest
-- lower-rarity alien (the index keeps it), so players never get stuck.
local function claimSlot(player: Player, data, rarity: string): number?
	local count = S.AlienService:GetSlotCount(player)
	local used = usedSlots(data)
	for slot = 1, count do
		if not used[slot] then
			return slot
		end
	end
	local order = Eggs.order(rarity)
	local weakestIndex, weakestIncome = nil, math.huge
	for i, alien in data.Aliens do
		local def = Aliens.ById[alien.Id]
		if def and Eggs.order(def.Rarity) < order and alienIncome(alien) < weakestIncome then
			weakestIndex, weakestIncome = i, alienIncome(alien)
		end
	end
	if weakestIndex then
		local released = table.remove(data.Aliens, weakestIndex)
		local def = Aliens.ById[released.Id]
		Net.fire("Notify", player, `Released {def and def.Name or "an alien"} to make room.`, "Info")
		return released.Slot
	end
	return nil
end

function HatchService:StartHatch(player: Player, rarity: string): boolean
	local data = S.DataService:GetData(player)
	local rarityDef = Eggs.ByName[rarity]
	if not data or not rarityDef then
		return false
	end
	local slot = claimSlot(player, data, rarity)
	if not slot then
		return false
	end
	local seconds = rarityDef.HatchSeconds
	if data.Gamepasses.FasterHatch then
		seconds *= Eggs.FasterHatchMult
	end
	if (data.Flags.FreeSkips or 0) > 0 then
		data.Flags.FreeSkips -= 1
		seconds = 0
	end
	table.insert(data.Hatching, { EggRarity = rarity, EndsAt = os.time() + math.ceil(seconds), Slot = slot })
	S.AlienService:RefreshBase(player)
	S.StateService:Mark(player)
	if rarityDef.Order >= Eggs.order("Rare") and seconds > 0 then
		S.OfferService:OnRareHatchStarted(player, rarity)
	end
	return true
end

local function rollMutation(luck: number): string?
	for _, mutation in Eggs.Mutations do
		if rng:NextNumber() < math.min(1, luck / mutation.Chance) then
			return mutation.Name
		end
	end
	return nil
end

local function complete(player: Player, data, entry)
	local pool = Aliens.ByRarity[entry.EggRarity] or Aliens.ByRarity.Common
	local def = pool[rng:NextInteger(1, #pool)]
	local mutation = rollMutation(S.BoostService:GetServerLuck())
	local isNew = not data.Index[def.Id]
	data.Index[def.Id] = true
	table.insert(data.Aliens, { Id = def.Id, Mutation = mutation, Slot = entry.Slot })
	data.Stats.Hatches += 1

	S.AnalyticsService:Funnel(player, "FirstHatch")
	S.AlienService:RefreshBase(player)
	S.StateService:Mark(player)
	Net.fire("HatchCompleted", player, {
		AlienId = def.Id,
		Mutation = mutation,
		Rarity = def.Rarity,
		IsNew = isNew,
		Slot = entry.Slot,
	})
	if mutation or Eggs.order(def.Rarity) >= Eggs.order("Mythic") then
		local label = if mutation then Eggs.MutationByName[mutation].Label .. " " else ""
		Net.fireAll("Announce", `{player.DisplayName} hatched a {label}{def.Name} ({def.Rarity})!`, "Hatch")
	end
	S.OfferService:OnHatch(player)
end

-- Skip Hatch product: finishes the matching egg now, else any egg, else banks a free skip.
function HatchService:Skip(player: Player, rarity: string?)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	local target = nil
	for _, entry in data.Hatching do
		if entry.EggRarity == rarity then
			target = entry
			break
		end
	end
	target = target or data.Hatching[1]
	if target then
		target.EndsAt = os.time()
	else
		data.Flags.FreeSkips = (data.Flags.FreeSkips or 0) + 1
		Net.fire("Notify", player, "Saved a free skip for your next egg!", "Good")
	end
	S.StateService:Mark(player)
end

function HatchService:Init(services)
	S = services
end

function HatchService:Start()
	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			local now = os.time()
			for player, session in S.DataService:GetSessions() do
				local hatching = session.Data.Hatching
				local i = 1
				while i <= #hatching do
					local entry = hatching[i]
					if entry.EndsAt <= now then
						table.remove(hatching, i)
						local ok, err = pcall(complete, player, session.Data, entry)
						if not ok then
							warn("[HatchService] " .. tostring(err))
						end
					else
						i += 1
					end
				end
			end
		end
	end)
end

return HatchService
