--!strict
-- Aliens on base slots: slot count, income every second, offline income on join,
-- base visuals (aliens + hatching eggs) and the top-3 follower list.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AlienModel = require(Shared.AlienModel)
local Aliens = require(Shared.Config.Aliens)
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local FOLLOWER_COUNT = 3

local AlienService = {}

local S: any

local function alienIncome(alien): number
	local def = Aliens.ById[alien.Id]
	local mutation = alien.Mutation and Eggs.MutationByName[alien.Mutation]
	return (if def then def.Income else 0) * (if mutation then mutation.IncomeMult else 1)
end

function AlienService:GetSlotCount(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return Economy.BaseSlots
	end
	local count = Economy.BaseSlots + math.floor(data.Rebirths / Economy.RebirthsPerExtraSlot)
	if data.Gamepasses.ExtraSlots then
		count += Economy.GamepassSlots
	end
	return math.min(count, Economy.MaxSlots)
end

-- Base income before multipliers.
function AlienService:GetBaseIncome(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return 0
	end
	local total = 0
	for _, alien in data.Aliens do
		total += alienIncome(alien)
	end
	return total
end

function AlienService:GetIncomePerSec(player: Player): number
	return AlienService:GetBaseIncome(player) * S.BoostService:GetCashMultiplier(player)
end

local function label(parent: Instance, text: string, color: Color3, height: number, tag: string?, endsAt: number?)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(150, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	billboard.MaxDistance = 60
	billboard.LightInfluence = 0
	local text1 = Instance.new("TextLabel")
	text1.Size = UDim2.fromScale(1, 1)
	text1.BackgroundTransparency = 1
	text1.TextScaled = true
	text1.Font = Enum.Font.FredokaOne
	text1.TextColor3 = color
	text1.TextStrokeTransparency = 0.3
	text1.Text = text
	text1.Parent = billboard
	if tag then
		-- The client counts these down (HatchController).
		text1:SetAttribute("EndsAt", endsAt)
		CollectionService:AddTag(text1, tag)
	end
	billboard.Parent = parent
end

-- Rebuilds the aliens and hatching eggs shown on this player's base.
function AlienService:RefreshBase(player: Player)
	local session = S.DataService:GetSession(player)
	local index = session and session.Runtime.BaseIndex
	if not session or not index then
		return
	end
	local base = S.WorldService:GetBase(index)
	local old = base:FindFirstChild("Aliens")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Aliens"

	local data = session.Data
	for _, alien in data.Aliens do
		local model = AlienModel.build(alien.Id, alien.Mutation)
		local slotCf = S.WorldService:GetSlotCFrame(index, alien.Slot)
		if slotCf then
			model:PivotTo(slotCf)
			local def = Aliens.ById[alien.Id]
			local mult = S.BoostService:GetCashMultiplier(player)
			label(model.PrimaryPart :: BasePart, `{AlienModel.displayName(alien.Id, alien.Mutation)}\n{Format.cash(alienIncome(alien) * mult)}/s`, Eggs.ByName[def.Rarity].Color, def.Size)
			model.Parent = folder
		end
	end
	for _, entry in data.Hatching do
		local slotCf = S.WorldService:GetSlotCFrame(index, entry.Slot)
		if slotCf then
			local rarity = Eggs.ByName[entry.EggRarity]
			local egg = Instance.new("Part")
			egg.Name = "HatchingEgg"
			egg.Size = Vector3.new(2.2, 2.9, 2.2)
			egg.CFrame = slotCf * CFrame.new(0, 1.5, 0)
			egg.Anchored = true
			egg.CanCollide = false
			egg.CanQuery = false
			egg.CanTouch = false
			egg.Material = Enum.Material.Neon
			egg.Color = rarity.Color
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = egg
			egg:SetAttribute("EndsAt", entry.EndsAt)
			egg:SetAttribute("OwnerUserId", player.UserId)
			CollectionService:AddTag(egg, "HatchingEgg")
			label(egg, "", rarity.Color, 2.8, "HatchTimer", entry.EndsAt)
			egg.Parent = folder
		end
	end
	folder.Parent = base

	-- Slot markers: bright for usable slots.
	local slots = base:FindFirstChild("Slots")
	local count = AlienService:GetSlotCount(player)
	if slots then
		for _, marker in slots:GetChildren() do
			local slot = marker:GetAttribute("Slot") or 0
			(marker :: BasePart).Transparency = if slot <= count then 0.35 else 0.85
		end
	end

	-- Top aliens follow the player around (rendered by each client).
	local sorted = table.clone(data.Aliens)
	table.sort(sorted, function(a, b)
		return alienIncome(a) > alienIncome(b)
	end)
	local followers = {}
	for i = 1, math.min(FOLLOWER_COUNT, #sorted) do
		table.insert(followers, sorted[i].Id .. ":" .. (sorted[i].Mutation or ""))
	end
	player:SetAttribute("Followers", table.concat(followers, ","))
end

local function clearBase(session)
	local index = session.Runtime.BaseIndex
	if not index then
		return
	end
	local base = S.WorldService:GetBase(index)
	local old = base:FindFirstChild("Aliens")
	if old then
		old:Destroy()
	end
	local slots = base:FindFirstChild("Slots")
	if slots then
		for _, marker in slots:GetChildren() do
			(marker :: BasePart).Transparency = 0.6
		end
	end
end

local function grantOffline(player: Player, session)
	local data = session.Data
	if data.LastOnline <= 0 then
		return
	end
	local cap = if data.Gamepasses.VIP then Economy.OfflineCapSecondsVIP else Economy.OfflineCapSeconds
	local seconds = math.clamp(os.time() - data.LastOnline, 0, cap)
	local base = AlienService:GetBaseIncome(player)
	if seconds < Economy.OfflineMinSeconds or base <= 0 then
		return
	end
	local amount = base * S.BoostService:GetBaseCashMultiplier(player) * seconds * Economy.OfflineIncomeRate
	S.BackpackService:GiveCash(player, amount, "OfflineIncome")
	session.Runtime.OfflineReward = amount
	task.delay(4, function()
		if player.Parent then
			Net.fire("WelcomeBack", player, { Seconds = seconds, Amount = BigNum.from(amount) })
			S.OfferService:OnWelcomeBack(player)
		end
	end)
end

function AlienService:Init(services)
	S = services
	S.DataService.ProfileLoaded:Connect(function(player, session)
		-- Wait for BaseService to assign the base first (same frame, earlier handler).
		task.defer(function()
			AlienService:RefreshBase(player)
			grantOffline(player, session)
		end)
	end)
	S.DataService.ProfileReleasing:Connect(function(_player, session)
		clearBase(session)
	end)
end

function AlienService:Start()
	task.spawn(function()
		while true do
			task.wait(Economy.IncomeTickSeconds)
			for player, session in S.DataService:GetSessions() do
				local base = AlienService:GetBaseIncome(player)
				if base > 0 then
					local amount = base * S.BoostService:GetCashMultiplier(player) * Economy.IncomeTickSeconds
					session.Data.Cash = BigNum.add(session.Data.Cash, amount)
					S.AnalyticsService:Income(player, amount)
					S.StateService:Mark(player)
				end
			end
		end
	end)
end

return AlienService
