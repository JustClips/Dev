--!strict
-- Growing eggs in your pet park (Steal an Egg style). You hold an egg from your inventory
-- and put it down anywhere in your park (or let Place Eggs pick spots). Only so many eggs
-- can grow at once (GetIncubatorCount: 4, +1 per 2 rebirths, max 8). Each one is saved
-- with its spot and a unix EndsAt, so the timer keeps running while you're offline. When
-- it's ready you open it and the pet goes to your inventory. Pet weight, mutations and
-- Huge roll at opening and scale with luck.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local EggSpots = require(Shared.EggSpots)
local Aliens = require(Shared.Config.Aliens)
local Economy = require(Shared.Config.Economy)
local Eggs = require(Shared.Config.Eggs)
local Net = require(Shared.Net)
local Upgrades = require(Shared.Config.Upgrades)
local Weights = require(Shared.Config.Weights)
local World = require(Shared.Config.World)

local PLACE_REACH = 90 -- how far from the park centre the player may stand (client asks at 80)

local HatchService = {}

local S: any
local rng = Random.new()

local function notify(player: Player, text: string, kind: string?)
	Net.fire("Notify", player, text, kind or "Bad")
end

function HatchService:GetIncubatorCount(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return Economy.Incubators
	end
	local count = math.min(Economy.Incubators + math.floor(data.Rebirths / Economy.RebirthsPerIncubator), Economy.MaxIncubators)
	-- Upgrade tree nests go on top of the rebirth cap.
	return count + Upgrades.stat(data.Upgrades, "Incubators")
end

local function freeSpot(player: Player, data): number?
	if #data.Hatching >= HatchService:GetIncubatorCount(player) then
		return nil
	end
	local used = {}
	for _, entry in data.Hatching do
		used[entry.Spot] = true
	end
	for spot = 1, HatchService:GetIncubatorCount(player) do
		if not used[spot] then
			return spot
		end
	end
	return nil
end

-- Gives eggs from before free placement a park spot (once).
function HatchService:EnsureSpots(data)
	for _, entry in data.Hatching do
		if not entry.X then
			local x, z = EggSpots.auto(data.Hatching, entry.Uid)
			entry.X, entry.Z = x or 0, z or 0
		end
		if not entry.StartsAt then
			local def = Eggs.ByName[entry.Rarity]
			entry.StartsAt = entry.EndsAt - (if def then def.HatchSeconds else 0)
		end
	end
end

local function hatchSeconds(data, rarity: string): number
	local seconds = Eggs.ByName[rarity].HatchSeconds
	if data.Gamepasses.FasterHatch then
		seconds *= Eggs.FasterHatchMult
	end
	seconds /= Upgrades.multiplier(data.Upgrades, "HatchSpeed")
	return math.ceil(seconds)
end

local function changed(player: Player)
	S.InventoryService:Touch(player)
	S.AlienService:RefreshBase(player)
	S.StateService:Mark(player)
end

-- Puts an egg from the inventory down in the pet park to grow. `position` is where the
-- player clicked (world space); without it a free spot is picked. Returns ok, message.
function HatchService:PlaceEgg(player: Player, uid: string, position: Vector3?): (boolean, string?)
	local session = S.DataService:GetSession(player)
	local data = session and session.Data
	local egg = data and data.Eggs[uid]
	if not session or not data or not egg then
		return false, "That egg is gone"
	end
	local spot = freeSpot(player, data)
	if not spot then
		return false, `Only {HatchService:GetIncubatorCount(player)} eggs can grow at once! Open one first.`
	end
	local x, z
	if position then
		local index = session.Runtime.BaseIndex
		if not index then
			return false, "You don't have a base yet"
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local baseCf = World.baseCFrame(index)
		local centre = (World.Base.ParkMin + World.Base.ParkMax) / 2
		if not root or (root.Position - baseCf * Vector3.new(centre.X, 0, centre.Y)).Magnitude > PLACE_REACH then
			return false, "Walk closer to your pet park"
		end
		local localPos = baseCf:PointToObjectSpace(position)
		x, z = localPos.X, localPos.Z
		local problem = EggSpots.problem(data.Hatching, x, z)
		if problem then
			return false, problem
		end
	else
		x, z = EggSpots.auto(data.Hatching)
		if not x then
			return false, "No room left in your pet park"
		end
	end
	data.Eggs[uid] = nil
	HatchService:StopHolding(player)
	local seconds = hatchSeconds(data, egg.Rarity)
	if (data.Flags.FreeSkips or 0) > 0 then
		data.Flags.FreeSkips -= 1
		seconds = 0
	end
	table.insert(data.Hatching, {
		Uid = uid,
		Rarity = egg.Rarity,
		Zone = egg.Zone,
		Spot = spot,
		X = x,
		Z = z,
		Weight = egg.Weight,
		Size = egg.Size,
		StartsAt = os.time(),
		EndsAt = os.time() + seconds,
	})
	changed(player)
	if Eggs.order(egg.Rarity) >= Eggs.order("Rare") and seconds > 0 then
		S.OfferService:OnRareHatchStarted(player, egg.Rarity, uid)
	end
	return true, nil
end

-- Places the rarest eggs first until the incubators are full. Returns how many.
function HatchService:PlaceBest(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return 0
	end
	local list = {}
	for uid, egg in data.Eggs do
		table.insert(list, { uid = uid, order = Eggs.order(egg.Rarity) })
	end
	table.sort(list, function(a, b)
		return a.order > b.order
	end)
	local placed = 0
	for _, entry in list do
		if not freeSpot(player, data) then
			break
		end
		if HatchService:PlaceEgg(player, entry.uid) then
			placed += 1
		end
	end
	return placed
end

local function rollMutation(luck: number): string?
	for _, mutation in Eggs.Mutations do
		if not mutation.WeatherOnly and rng:NextNumber() < math.min(1, luck / mutation.Chance) then
			return mutation.Name
		end
	end
	return nil
end

-- Opens a ready egg: rolls the pet and puts it in the inventory.
function HatchService:Open(player: Player, uid: string, quiet: boolean?): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return false, "Still loading"
	end
	local index = nil
	for i, entry in data.Hatching do
		if entry.Uid == uid then
			index = i
			break
		end
	end
	local entry = index and data.Hatching[index]
	if not entry then
		return false, "That egg is gone"
	end
	if entry.EndsAt > os.time() then
		return false, "Not ready yet"
	end
	if S.InventoryService:PetCount(player) >= Economy.PetBagSize then
		return false, "Your pet bag is full! Sell or place some pets first."
	end
	table.remove(data.Hatching, index)

	local pool = Aliens.pool(entry.Zone, entry.Rarity)
	local def = pool[rng:NextInteger(1, #pool)]
	local luck = S.BoostService:GetServerLuck() * S.BoostService:GetPersonalLuck(player)
	-- An egg the weather upgraded while it grew hatches with that mutation.
	local mutation = entry.Mutation or rollMutation(luck)
	local huge = rng:NextNumber() < math.min(1, Aliens.HugeChance * luck * S.WeatherService:GetHugeMult())
	local isNew = not data.Index[def.Id]
	data.Index[def.Id] = true
	local petUid = S.DataService:NewUid(data, "p")
	local weight = Weights.rollPet(rng, def.Rarity, entry.Rarity, entry.Weight)
	local pet = { Id = def.Id, Mutation = mutation, Huge = if huge then true else nil, Weight = weight }
	data.Pets[petUid] = pet
	data.Stats.Hatches += 1

	S.AnalyticsService:Funnel(player, "FirstHatch")
	changed(player)
	if not quiet then
		Net.fire("HatchCompleted", player, {
			Uid = petUid,
			AlienId = def.Id,
			Mutation = mutation,
			Huge = huge,
			Rarity = def.Rarity,
			IsNew = isNew,
			Income = Aliens.income(pet),
			Weight = weight,
			EggUid = entry.Uid,
			EggRarity = entry.Rarity,
			EggWeight = entry.Weight,
			X = entry.X,
			Z = entry.Z,
			FreeSlot = S.AlienService:PlacedCount(player) < S.AlienService:GetSlotCount(player),
		})
	end
	if huge or mutation or Eggs.order(def.Rarity) >= Eggs.order("Mythic") then
		local label = (if huge then "HUGE " else "") .. (if mutation then Eggs.MutationByName[mutation].Label .. " " else "")
		-- Everyone else hears about it; the hatcher already sees their own reveal.
		for _, other in Players:GetPlayers() do
			if other ~= player then
				Net.fire("Announce", other, `{player.DisplayName} hatched a {label}{def.Name} ({def.Rarity})!`, "Hatch")
			end
		end
	end
	S.OfferService:OnHatch(player)
	return true, nil
end

-- Opens every ready egg. The cutscene plays for the best one only.
function HatchService:OpenReady(player: Player): (number, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return 0, "Still loading"
	end
	local ready = {}
	for _, entry in data.Hatching do
		if entry.EndsAt <= os.time() then
			table.insert(ready, entry)
		end
	end
	table.sort(ready, function(a, b)
		return Eggs.order(a.Rarity) < Eggs.order(b.Rarity)
	end)
	local opened, lastError = 0, nil
	for i, entry in ready do
		local ok, err = HatchService:Open(player, entry.Uid, i < #ready)
		if ok then
			opened += 1
		else
			lastError = err
			break
		end
	end
	return opened, lastError
end

-- Skip Hatch product: finishes the egg the player picked (SkipTarget), else the slowest
-- egg of that rarity, else any egg, else banks a free skip for the next egg placed.
function HatchService:Skip(player: Player, rarity: string?, targetUid: string?)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	local target = nil
	for _, entry in data.Hatching do
		if entry.Uid == targetUid then
			target = entry
			break
		end
	end
	if not target then
		for _, entry in data.Hatching do
			if entry.Rarity == rarity and entry.EndsAt > os.time() and (not target or entry.EndsAt > target.EndsAt) then
				target = entry
			end
		end
	end
	if not target then
		for _, entry in data.Hatching do
			if entry.EndsAt > os.time() then
				target = entry
				break
			end
		end
	end
	if target then
		target.EndsAt = os.time()
		notify(player, `Your {target.Rarity} egg is ready to open!`, "Good")
	else
		data.Flags.FreeSkips = (data.Flags.FreeSkips or 0) + 1
		notify(player, "Saved a free skip for your next egg!", "Good")
	end
	changed(player)
end

-- Hatch potion: every egg in an incubator finishes `seconds` sooner.
function HatchService:SpeedUp(player: Player, seconds: number): number
	local data = S.DataService:GetData(player)
	if not data then
		return 0
	end
	local count = 0
	for _, entry in data.Hatching do
		if entry.EndsAt > os.time() then
			entry.EndsAt = math.max(os.time(), entry.EndsAt - seconds)
			count += 1
		end
	end
	if count > 0 then
		changed(player)
	end
	return count
end

-------------------------------------------------------------------------- holding an egg

-- The player holds an egg out in front of them while choosing where to put it (others see
-- it too). The client shows the ghost egg and sends PlaceEggAt.
local HELD_MAX = 3.2 -- studs: big eggs are shrunk to this when carried in your arms

function HatchService:Hold(player: Player, uid: string): (boolean, string?)
	local session = S.DataService:GetSession(player)
	local egg = session and session.Data.Eggs[uid]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not session or not egg then
		return false, "That egg is gone"
	end
	HatchService:StopHolding(player)
	session.Runtime.HeldEgg = uid
	if not root or not character then
		return true, nil
	end
	local model = AssetLibrary.egg(egg.Rarity)
	model.Name = "HeldEgg"
	model:ScaleTo(Weights.visualScale(Weights.eggMult(egg.Rarity, egg.Weight)) * 0.8)
	local _, size = model:GetBoundingBox()
	local biggest = math.max(size.X, size.Y, size.Z)
	if biggest > HELD_MAX then
		model:ScaleTo(model:GetScale() * HELD_MAX / biggest)
		_, size = model:GetBoundingBox()
	end
	-- Carried in both arms in front of the chest (the clients pose the arms, see
	-- HoldPoseController). Welded to the root, not the hand, so it doesn't bob as you walk.
	model:PivotTo(root.CFrame * CFrame.new(0, -0.15, -(root.Size.Z / 2 + size.Z / 2 + 0.35)))
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end
	model.Parent = character
	return true, nil
end

function HatchService:StopHolding(player: Player)
	local session = S.DataService:GetSession(player)
	if session then
		session.Runtime.HeldEgg = nil
	end
	local held = player.Character and player.Character:FindFirstChild("HeldEgg")
	if held then
		held:Destroy()
	end
end

-- Weather (WeatherService): gives a growing egg a mutation. False if it already has one.
function HatchService:SetEggMutation(player: Player, uid: string, mutation: string): boolean
	local data = S.DataService:GetData(player)
	if not data then
		return false
	end
	for _, entry in data.Hatching do
		if entry.Uid == uid then
			if entry.Mutation then
				return false
			end
			entry.Mutation = mutation :: any
			changed(player)
			return true
		end
	end
	return false
end

-- Weather (Rain): every growing egg gets `seconds` closer to ready. Only the egg
-- attributes are updated (no rebuild), so the park doesn't flicker.
function HatchService:GrowFaster(player: Player, seconds: number, base: Instance?)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	local now = os.time()
	local any = false
	for _, entry in data.Hatching do
		if entry.EndsAt > now then
			local shift = math.min(seconds, entry.EndsAt - now)
			entry.EndsAt -= shift
			entry.StartsAt = (entry.StartsAt or entry.EndsAt) - shift
			any = true
			local folder = base and base:FindFirstChild("Hatching")
			local egg = folder and folder:FindFirstChild(entry.Uid)
			if egg then
				egg:SetAttribute("EndsAt", entry.EndsAt)
				egg:SetAttribute("StartsAt", entry.StartsAt)
				for _, d in egg:GetDescendants() do
					if d:GetAttribute("EndsAt") ~= nil then
						d:SetAttribute("EndsAt", entry.EndsAt)
					end
				end
			end
		end
	end
	if any then
		S.StateService:Mark(player)
	end
end

function HatchService:Init(services)
	S = services
end

function HatchService:Start() end

return HatchService
