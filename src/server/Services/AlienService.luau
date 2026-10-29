--!strict
-- Pets placed on your base: slot count, income every second, offline income on join,
-- what the pet park shows (placed pets + incubating eggs) and the top-3 follower list.
-- Unplaced pets stay in the inventory (InventoryService) and earn nothing.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Aliens = require(Shared.Config.Aliens)
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Eggs = require(Shared.Config.Eggs)
local Net = require(Shared.Net)
local Upgrades = require(Shared.Config.Upgrades)
local Weights = require(Shared.Config.Weights)
local World = require(Shared.Config.World)

local FOLLOWER_COUNT = 3

local AlienService = {}

local S: any

local alienIncome = Aliens.income

function AlienService:GetSlotCount(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return Economy.BaseSlots
	end
	local count = Economy.BaseSlots + math.floor(data.Rebirths / Economy.RebirthsPerExtraSlot)
	if data.Gamepasses.ExtraSlots then
		count += Economy.GamepassSlots
	end
	count += math.min(data.Flags.CashSlots or 0, #Economy.SlotCashPrices)
	return math.min(count, Economy.MaxSlots)
end

function AlienService:PlacedCount(player: Player): number
	local data = S.DataService:GetData(player)
	local count = 0
	if data then
		for _, pet in data.Pets do
			if pet.Placed then
				count += 1
			end
		end
	end
	return count
end

-- Base income of the placed pets (with the tree's Pet Income), before cash multipliers.
function AlienService:GetBaseIncome(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return 0
	end
	local total = 0
	for _, pet in data.Pets do
		if pet.Placed then
			total += alienIncome(pet)
		end
	end
	return total * Upgrades.multiplier(data.Upgrades, "PetIncome")
end

function AlienService:GetIncomePerSec(player: Player): number
	return AlienService:GetBaseIncome(player) * S.BoostService:GetCashMultiplier(player)
end

-- A small navy plate over a hatching egg (text on a plate, never straight on the world).
-- Hatch timer over a growing egg: just outlined text and a thin growth bar, no panel. The
-- client counts it down, fills the bar and only shows it when you're near (HatchController).
local function label(parent: Instance, text: string, color: Color3, height: number, tag: string?, endsAt: number?)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	billboard.MaxDistance = 70
	billboard.LightInfluence = 0
	local plate = Instance.new("Frame")
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundTransparency = 1
	plate.Parent = billboard
	local text1 = Instance.new("TextLabel")
	text1.Size = UDim2.new(1, 0, 1, -10)
	text1.BackgroundTransparency = 1
	text1.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
	text1.TextSize = 24
	text1.TextColor3 = Color3.new(1, 1, 1)
	text1.Text = text
	text1.Parent = plate
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.fromRGB(16, 18, 28)
	outline.Thickness = 2.5
	outline.LineJoinMode = Enum.LineJoinMode.Miter
	outline.Parent = text1
	if tag then
		text1:SetAttribute("EndsAt", endsAt)
		CollectionService:AddTag(text1, tag)
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.Position = UDim2.new(0.5, 0, 1, -2)
		bar.Size = UDim2.new(0, 64, 0, 6)
		bar.BackgroundColor3 = Color3.fromRGB(16, 18, 28)
		bar.BackgroundTransparency = 0.3
		bar.BorderSizePixel = 0
		bar.Parent = plate
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = color
		fill.BorderSizePixel = 0
		fill.Parent = bar
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
	local mult = S.BoostService:GetCashMultiplier(player) * Upgrades.multiplier(data.Upgrades, "PetIncome")
	local aliens = Instance.new("Folder")
	aliens.Name = "Aliens"
	local placed = {}
	for uid, pet in data.Pets do
		local def = Aliens.ById[pet.Id]
		if pet.Placed and def then
			-- Folder name = pet uid, so clients can offer "Pick up" on their own pets.
			local entry = Instance.new("Folder")
			entry.Name = uid
			entry:SetAttribute("AlienId", pet.Id)
			entry:SetAttribute("Mutation", pet.Mutation)
			entry:SetAttribute("Huge", pet.Huge == true)
			entry:SetAttribute("Income", alienIncome(pet) * mult)
			entry:SetAttribute("Weight", pet.Weight or Weights.petKg(def.Rarity))
			entry:SetAttribute("WeightMult", Weights.incomeMult(def.Rarity, pet.Weight))
			entry.Parent = aliens
			table.insert(placed, pet)
		end
	end
	aliens:SetAttribute("OwnerUserId", player.UserId)
	aliens.Parent = base

	-- Growing eggs where the player put them in the park, right on the grass. The
	-- owner's client adds Skip / Open prompts; every client shows the hover info.
	S.HatchService:EnsureSpots(data)
	local hatching = Instance.new("Folder")
	hatching.Name = "Hatching"
	hatching:SetAttribute("OwnerUserId", player.UserId)
	hatching:SetAttribute("Limit", S.HatchService:GetIncubatorCount(player))
	local baseCf = World.baseCFrame(index)
	for _, entry in data.Hatching do
		local rarity = Eggs.ByName[entry.Rarity]
		local spot = baseCf * CFrame.new(entry.X or 0, 0.2, entry.Z or 0)
		local scale = Weights.visualScale(Weights.eggMult(entry.Rarity, entry.Weight))
		local egg = AssetLibrary.egg(entry.Rarity)
		egg.Name = entry.Uid
		-- Built at its current size; every client keeps growing it (HatchController).
		local fullScale = scale * 1.25
		egg:ScaleTo(fullScale * Eggs.growScale(Eggs.progress(entry.StartsAt, entry.EndsAt, os.time())))
		egg:PivotTo(spot) -- sits right on the grass (pivot is the egg's bottom)
		egg:SetAttribute("FullScale", fullScale)
		egg:SetAttribute("StartsAt", entry.StartsAt or entry.EndsAt)
		egg:SetAttribute("Uid", entry.Uid)
		egg:SetAttribute("Rarity", entry.Rarity)
		egg:SetAttribute("Zone", entry.Zone)
		egg:SetAttribute("EndsAt", entry.EndsAt)
		egg:SetAttribute("Weight", entry.Weight or Weights.eggKg(entry.Rarity))
		egg:SetAttribute("Size", entry.Size or "Normal")
		egg:SetAttribute("OwnerUserId", player.UserId)
		CollectionService:AddTag(egg, "HatchingEgg")
		for _, part in egg:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanQuery = true -- hover card
			end
		end
		local primary = egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")
		if primary then
			label(primary, "", rarity.Color, 3.4 * scale, "HatchTimer", entry.EndsAt)
			egg:SetAttribute("LabelHeight", 3.4 * scale)
		end
		egg.Parent = hatching
	end
	hatching.Parent = base

	-- Top placed pets follow the player around (rendered by each client).
	table.sort(placed, function(a, b)
		return alienIncome(a) > alienIncome(b)
	end)
	local followers = {}
	for i = 1, math.min(FOLLOWER_COUNT, #placed) do
		table.insert(followers, placed[i].Id .. ":" .. (placed[i].Mutation or "") .. ":" .. (if placed[i].Huge then "H" else ""))
	end
	player:SetAttribute("Followers", table.concat(followers, ","))
	player:SetAttribute("AlienCount", #placed)
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
		* Upgrades.multiplier(data.Upgrades, "Offline")
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
