--!strict
-- Aliens on your base: slot count, income every second, offline income on join,
-- what the pet park shows (aliens + hatching eggs) and the top-3 follower list.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Aliens = require(Shared.Config.Aliens)
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Eggs = require(Shared.Config.Eggs)
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

-- A small navy plate over a hatching egg (text on a plate, never straight on the world).
local function label(parent: Instance, text: string, color: Color3, height: number, tag: string?, endsAt: number?)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(110, 34)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	billboard.MaxDistance = 70
	billboard.LightInfluence = 0
	local plate = Instance.new("Frame")
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = Color3.fromRGB(20, 26, 51)
	plate.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = plate
	local text1 = Instance.new("TextLabel")
	text1.Size = UDim2.fromScale(1, 1)
	text1.BackgroundTransparency = 1
	text1.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold)
	text1.TextSize = 22
	text1.TextColor3 = color
	text1.Text = text
	text1.Parent = plate
	if tag then
		-- The client counts these down (HatchController).
		text1:SetAttribute("EndsAt", endsAt)
		CollectionService:AddTag(text1, tag)
	end
	billboard.Parent = parent
end

-- Publishes this player's aliens to their base (one Folder per alien with attributes;
-- every client renders and animates them in the pet park, see PetController) and builds
-- the hatching eggs on the hatchery pad.
function AlienService:RefreshBase(player: Player)
	local session = S.DataService:GetSession(player)
	local index = session and session.Runtime.BaseIndex
	if not session or not index then
		return
	end
	local base = S.WorldService:GetBase(index)
	for _, name in { "Aliens", "Hatching" } do
		local old = base:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local data = session.Data
	local mult = S.BoostService:GetCashMultiplier(player)
	local aliens = Instance.new("Folder")
	aliens.Name = "Aliens"
	for i, alien in data.Aliens do
		local def = Aliens.ById[alien.Id]
		if def then
			local entry = Instance.new("Folder")
			entry.Name = tostring(alien.Slot or i)
			entry:SetAttribute("AlienId", alien.Id)
			entry:SetAttribute("Mutation", alien.Mutation)
			entry:SetAttribute("Income", alienIncome(alien) * mult)
			entry.Parent = aliens
		end
	end
	aliens:SetAttribute("OwnerUserId", player.UserId)
	aliens.Parent = base

	local hatching = Instance.new("Folder")
	hatching.Name = "Hatching"
	for i, entry in data.Hatching do
		local rarity = Eggs.ByName[entry.EggRarity]
		local spot = S.WorldService:GetHatchSpot(index, i)
		local egg = AssetLibrary.egg(entry.EggRarity)
		egg:PivotTo(spot)
		egg:SetAttribute("EndsAt", entry.EndsAt)
		egg:SetAttribute("OwnerUserId", player.UserId)
		CollectionService:AddTag(egg, "HatchingEgg")
		local primary = egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")
		if primary then
			label(primary, "", rarity.Color, 3.4, "HatchTimer", entry.EndsAt)
		end
		egg.Parent = hatching
	end
	hatching.Parent = base

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
	player:SetAttribute("AlienCount", #data.Aliens)
	player:SetAttribute("SlotCount", AlienService:GetSlotCount(player))
end

local function clearBase(session)
	local index = session.Runtime.BaseIndex
	if not index then
		return
	end
	local base = S.WorldService:GetBase(index)
	for _, name in { "Aliens", "Hatching" } do
		local old = base:FindFirstChild(name)
		if old then
			old:Destroy()
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
