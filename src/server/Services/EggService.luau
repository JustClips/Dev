--!strict
-- Egg rolls on cleared tiles, egg pickups on the ground, carrying, and delivery to your base.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local AssetLibrary = require(Shared.AssetLibrary)
local Eggs = require(Shared.Config.Eggs)
local Upgrades = require(Shared.Config.Upgrades)
local World = require(Shared.Config.World)
local Net = require(Shared.Net)
local Touch = require(script.Parent.Parent.Lib.Touch)

local EggService = {}

local S: any
local rng = Random.new()
local eggFolder: Folder

function EggService:GetCarryLimit(player: Player): number
	local data = S.DataService:GetData(player)
	if data and data.Gamepasses.Carry3 then
		return Economy.CarryLimitPass
	end
	return Economy.CarryLimit
end

-- Picks a rarity up to maxRarity. Luck multiplies the weight of everything above Common.
function EggService:RollRarity(maxRarity: string, luck: number): string
	local maxOrder = Eggs.order(maxRarity)
	local total = 0
	local weights = {}
	for _, r in Eggs.Rarities do
		if r.Order <= maxOrder and r.Weight > 0 then
			local w = r.Weight * (if r.Order > 1 then luck else 1)
			total += w
			table.insert(weights, { name = r.Name, w = w })
		end
	end
	local pick = rng:NextNumber() * total
	for _, entry in weights do
		pick -= entry.w
		if pick <= 0 then
			return entry.name
		end
	end
	return weights[#weights].name
end

function EggService:RollShowerRarity(luck: number): string
	local total = 0
	local list = {}
	for name, weight in Eggs.ShowerWeights do
		local w = weight * (if Eggs.order(name) > Eggs.order("Rare") then luck else 1)
		total += w
		table.insert(list, { name = name, w = w })
	end
	local pick = rng:NextNumber() * total
	for _, entry in list do
		pick -= entry.w
		if pick <= 0 then
			return entry.name
		end
	end
	return "Rare"
end

local function refreshCarryVisual(player: Player)
	local session = S.DataService:GetSession(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not session or not character or not head then
		return
	end
	local old = character:FindFirstChild("CarriedEggs")
	if old then
		old:Destroy()
	end
	local carried = session.Runtime.Carried or {}
	if #carried == 0 then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "CarriedEggs"
	for i, rarity in carried do
		-- A smaller copy of the egg model, welded above the head.
		local egg = AssetLibrary.egg(rarity)
		egg:ScaleTo(0.6)
		egg:PivotTo(head.CFrame * CFrame.new(0, 0.8 + (i - 1) * 1.6, 0))
		for _, part in egg:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.Massless = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = head
				weld.Part1 = part
				weld.Parent = part
			end
		end
		egg.Parent = folder
	end
	folder.Parent = character
end

local function setCarried(player: Player, carried: { string })
	local session = S.DataService:GetSession(player)
	if not session then
		return
	end
	session.Runtime.Carried = carried
	refreshCarryVisual(player)
	S.StateService:Mark(player)
end

local function pickup(player: Player, egg: BasePart)
	local session = S.DataService:GetSession(player)
	if not session or not egg.Parent then
		return
	end
	local owner = egg:GetAttribute("OwnerUserId")
	local freeAt = egg:GetAttribute("FreeAt") or 0
	if owner and owner ~= player.UserId and os.time() < freeAt then
		return
	end
	local carried = table.clone(session.Runtime.Carried or {})
	if #carried >= EggService:GetCarryLimit(player) then
		if (session.Runtime.CarryWarnAt or 0) < os.clock() then
			session.Runtime.CarryWarnAt = os.clock() + 4
			Net.fire("Notify", player, "Hands full! Take your egg to your base.", "Bad")
		end
		return
	end
	local rarity = egg:GetAttribute("Rarity") :: string
	egg:Destroy()
	table.insert(carried, rarity)
	if session.Runtime.TutorialEgg == egg then
		session.Runtime.TutorialEgg = nil
		session.Runtime.TutorialEggPosition = nil
	end
	setCarried(player, carried)
	Net.fire("Notify", player, `Picked up a {rarity} egg! Bring it to your base.`, "Egg")
end

-- Spawns a physical egg. owner gets it exclusively for EggOwnerSeconds.
function EggService:SpawnEgg(position: Vector3, rarity: string, owner: Player?): BasePart
	local def = Eggs.ByName[rarity]
	-- The egg entity is an invisible touch box; the Blender egg model sits inside it.
	local egg = Instance.new("Part")
	egg.Name = rarity .. "Egg"
	egg.Size = Vector3.new(3, 3.4, 3)
	egg.CFrame = CFrame.new(position + Vector3.new(0, 1.7, 0))
	egg.Anchored = true
	egg.CanCollide = false
	egg.CanQuery = false
	egg.Transparency = 1
	local visual = AssetLibrary.egg(rarity)
	visual:PivotTo(CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	visual.Parent = egg
	local light = Instance.new("PointLight")
	light.Color = def.Color
	light.Range = 10
	light.Brightness = 2
	light.Parent = egg
	egg:SetAttribute("Rarity", rarity)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(160, 44)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.MaxDistance = 90
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold)
	label.TextColor3 = def.Color
	label.TextStrokeTransparency = 0.2
	label.Text = if owner then `{rarity} Egg\n{owner.DisplayName}'s` else `{rarity} Egg`
	label.Parent = billboard
	billboard.Parent = egg

	if owner then
		egg:SetAttribute("OwnerUserId", owner.UserId)
		egg:SetAttribute("FreeAt", os.time() + Economy.EggOwnerSeconds)
		task.delay(Economy.EggOwnerSeconds, function()
			if egg.Parent then
				label.Text = `{rarity} Egg\nFree!`
			end
		end)
	end

	egg.Touched:Connect(Touch.debounced(0.3, function(player)
		pickup(player, egg)
	end))
	egg.Parent = eggFolder
	task.delay(Economy.EggDespawnSeconds, function()
		if egg.Parent then
			egg:Destroy()
		end
	end)
	return egg
end

local function foundEgg(player: Player, position: Vector3, rarity: string)
	local session = S.DataService:GetSession(player)
	if not session then
		return
	end
	local egg = EggService:SpawnEgg(position, rarity, player)
	session.Data.Stats.EggsFound += 1
	session.Runtime.TutorialEggSpawned = true
	if session.Data.Stats.Hatches == 0 and #session.Data.Hatching == 0 and not session.Runtime.TutorialEgg then
		session.Runtime.TutorialEgg = egg
		session.Runtime.TutorialEggPosition = egg.Position
		egg.Destroying:Connect(function()
			if session.Runtime.TutorialEgg == egg then
				session.Runtime.TutorialEgg = nil
				session.Runtime.TutorialEggPosition = nil
				S.StateService:Mark(player)
			end
		end)
	end
	S.AnalyticsService:Funnel(player, "FirstEgg")
	S.StateService:Mark(player)
	Net.fire("Notify", player, `You found a {rarity} egg!`, "Egg")
end

-- Called by SweepService for every tile this player cleared.
function EggService:OnTileCleared(player: Player, zone, position: Vector3)
	local session = S.DataService:GetSession(player)
	if not session then
		return
	end
	local stats = session.Data.Stats
	stats.TilesCleared += 1
	-- Tutorial: the first egg is guaranteed early (GAME_PLAN §4).
	if stats.EggsFound == 0 and not session.Runtime.TutorialEggSpawned and stats.TilesCleared >= Economy.TutorialEggTile then
		foundEgg(player, position, "Common")
		return
	end
	local luck = S.BoostService:GetServerLuck() * Upgrades.multiplier(session.Data.Upgrades, "Luck")
	local runtime = session.Runtime
	runtime.TilesSinceEgg = (runtime.TilesSinceEgg or 0) + 1
	-- Pity timer: long dry streaks feel broken to new players, so one is guaranteed.
	if rng:NextNumber() < zone.EggChance * luck or runtime.TilesSinceEgg >= Economy.EggPityTiles then
		runtime.TilesSinceEgg = 0
		foundEgg(player, position, EggService:RollRarity(zone.MaxRarity, luck))
	end
end

-- Gives an egg without a pickup (products). Hatches right away if a slot is free.
function EggService:GiveEgg(player: Player, rarity: string)
	if S.HatchService:StartHatch(player, rarity) then
		return
	end
	local session = S.DataService:GetSession(player)
	if session then
		local carried = table.clone(session.Runtime.Carried or {})
		table.insert(carried, rarity)
		setCarried(player, carried)
		Net.fire("Notify", player, `Your base is full. Free a slot to hatch your {rarity} egg.`, "Bad")
	end
end

local function deliver(player: Player, baseIndex: number)
	local session = S.DataService:GetSession(player)
	if not session or session.Runtime.BaseIndex ~= baseIndex then
		return
	end
	local carried = table.clone(session.Runtime.Carried or {})
	if #carried == 0 then
		return
	end
	local remaining = {}
	for _, rarity in carried do
		if not S.HatchService:StartHatch(player, rarity) then
			table.insert(remaining, rarity)
		end
	end
	if #remaining > 0 then
		Net.fire("Notify", player, "Your base is full! Get more slots to hatch more.", "Bad")
	end
	setCarried(player, remaining)
end

function EggService:Init(services)
	S = services
	eggFolder = Instance.new("Folder")
	eggFolder.Name = "Eggs"
	eggFolder.Parent = Workspace
	S.BaseService.CharacterReady:Connect(function(player)
		task.wait(0.5)
		refreshCarryVisual(player)
	end)
end

-- Eggs are delivered by walking onto your own hatchery (a distance check, like selling).
local DELIVER_EVERY = 0.25
local DELIVER_COOLDOWN = 1.5

function EggService:Start()
	local lastTry: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < DELIVER_EVERY then
			return
		end
		acc = 0
		local now = os.clock()
		for player, session in S.DataService:GetSessions() do
			local carried = session.Runtime.Carried
			local index = session.Runtime.BaseIndex
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not carried or #carried == 0 or not index or not root or (lastTry[player] or 0) + DELIVER_COOLDOWN > now then
				continue
			end
			local center = World.baseCFrame(index) * World.Base.Hatchery
			local offset = root.Position - center
			if Vector2.new(offset.X, offset.Z).Magnitude <= World.Base.HatcheryRadius + 1.5 and math.abs(offset.Y) < 10 then
				lastTry[player] = now
				deliver(player, index)
			end
		end
	end)
end

return EggService
