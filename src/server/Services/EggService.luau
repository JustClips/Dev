--!strict
-- Egg rolls on cleared tiles, egg pickups on the ground, carrying, and delivery to your base.
-- Delivered eggs go into your inventory (InventoryService); you place them in incubators
-- yourself. Carried eggs are { Rarity, Zone } so they hatch from the zone they came from.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local AssetLibrary = require(Shared.AssetLibrary)
local Eggs = require(Shared.Config.Eggs)
local Grid = require(Shared.Grid)
local Upgrades = require(Shared.Config.Upgrades)
local World = require(Shared.Config.World)
local Zones = require(Shared.Config.Zones)
local Net = require(Shared.Net)

local EggService = {}

local S: any
local rng = Random.new()
local PICKUP_HOLD = 0.35 -- seconds to hold the egg prompt
local PICKUP_DISTANCE = 10 -- studs
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
	for i, entry in carried do
		-- A smaller copy of the egg model, welded above the head.
		local egg = AssetLibrary.egg(entry.Rarity)
		AssetLibrary.applyMutation(egg, entry.Mutation)
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

type Carried = { Rarity: string, Zone: string, Mutation: string? }

local function setCarried(player: Player, carried: { Carried })
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
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - egg.Position).Magnitude > PICKUP_DISTANCE + 8 then
		return
	end
	local owner = egg:GetAttribute("OwnerUserId")
	if owner and owner ~= player.UserId then
		return -- someone else's find (their client is the only one that shows it)
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
	local zone = (egg:GetAttribute("Zone") or "Landing") :: string
	local mutation = egg:GetAttribute("Mutation")
	egg:Destroy()
	table.insert(carried, { Rarity = rarity, Zone = zone, Mutation = if type(mutation) == "string" then mutation else nil })
	if session.Runtime.TutorialEgg == egg then
		session.Runtime.TutorialEgg = nil
		session.Runtime.TutorialEggPosition = nil
	end
	setCarried(player, carried)
	Net.fire("Notify", player, `Picked up a {rarity} egg! Bring it to your base.`, "Egg")
end

-- Eggs on the ground, oldest first, so there's a cap on how many lie around (Dev: an Egg
-- Rain littered the whole field).
local ground: { { egg: BasePart, owner: number? } } = {}

local function makeRoom(owner: Player?)
	local function removeAt(i: number)
		local entry = table.remove(ground, i)
		if entry and entry.egg.Parent then
			entry.egg:Destroy()
		end
	end
	if owner then
		local mine = 0
		for _, entry in ground do
			if entry.owner == owner.UserId then
				mine += 1
			end
		end
		if mine >= Economy.MaxGroundEggsPerPlayer then
			for i, entry in ground do
				if entry.owner == owner.UserId then
					removeAt(i)
					break
				end
			end
		end
	end
	while #ground >= Economy.MaxGroundEggs do
		-- Oldest Egg Rain egg first, then the oldest of all.
		local pick = 1
		for i, entry in ground do
			if entry.owner == nil then
				pick = i
				break
			end
		end
		removeAt(pick)
	end
end

-- Rare and better eggs get a beam of light in their colour, taller for rarer eggs, so you
-- can tell what's lying around from far away. One neon part each: cheap on phones.
local BEAM_FROM = Eggs.order("Rare")

local function addBeam(egg: BasePart, base: Vector3, def)
	if def.Order < BEAM_FROM then
		return
	end
	local step = def.Order - BEAM_FROM
	local height = 14 + step * 8
	local width = 0.6 + step * 0.18
	local beam = Instance.new("Part")
	beam.Name = "Beam"
	beam.Shape = Enum.PartType.Cylinder
	beam.Size = Vector3.new(height, width, width)
	beam.CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	beam.Material = Enum.Material.Neon
	beam.Color = def.Color
	beam.Transparency = 0.45
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Parent = egg
end

-- Spawns a physical egg. With an owner it's their find: only they see it and can pick it
-- up (EggLabelController hides it for everyone else). zone decides which pet set it
-- hatches from (defaults to the zone under the egg).
function EggService:SpawnEgg(position: Vector3, rarity: string, owner: Player?, zone: string?): BasePart
	makeRoom(owner)
	local def = Eggs.ByName[rarity]
	local zoneDef = Zones.ById[zone or ""] or Grid.zoneAt(position)
	local zoneId = if zoneDef then zoneDef.Id else "Landing"
	local title = if zoneId == "Landing" then `{rarity} Egg` else `{zoneDef.Name} {rarity} Egg`
	-- The egg entity is an invisible box holding the pick-up prompt; the Blender egg model sits inside it.
	local egg = Instance.new("Part")
	egg.Name = rarity .. "Egg"
	egg.Size = Vector3.new(3, 3.4, 3)
	egg.CFrame = CFrame.new(position + Vector3.new(0, 1.7, 0))
	egg.Anchored = true
	egg.CanCollide = false
	egg.CanQuery = false
	egg.CanTouch = false
	egg.Transparency = 1
	local visual = AssetLibrary.egg(rarity)
	visual:PivotTo(CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	visual.Parent = egg
	if visual:GetAttribute("Placeholder") then
		-- Spawned before the models finished loading: swap in the real egg once they have.
		task.spawn(function()
			if not AssetLibrary.waitFor("EggsReady", 180) or visual.Parent ~= egg then
				return
			end
			local real = AssetLibrary.egg(rarity)
			if real:GetAttribute("Placeholder") then
				real:Destroy()
				return
			end
			real:PivotTo(visual:GetPivot())
			for _, d in real:GetDescendants() do
				if d:IsA("Light") then
					d:Destroy()
				end
			end
			real.Parent = egg
			visual:Destroy()
		end)
	end
	-- No lights on eggs lying around (Dev: a field full of them was far too bright).
	for _, d in visual:GetDescendants() do
		if d:IsA("Light") then
			d:Destroy()
		end
	end
	egg:SetAttribute("Rarity", rarity)
	egg:SetAttribute("Zone", zoneId)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(130, 36)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.MaxDistance = 90
	-- Clients only show the labels of the few eggs nearest to them (EggLabelController).
	billboard.Enabled = false
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold)
	label.TextColor3 = def.Color
	label.TextStrokeTransparency = 0.2
	label.Text = title
	label.Parent = billboard
	billboard.Parent = egg
	addBeam(egg, position, def)

	if owner then
		egg:SetAttribute("OwnerUserId", owner.UserId)
	end

	-- Picked up on purpose: walk up to it and hold the prompt (E, or press and hold on touch).
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickUp"
	prompt.ActionText = "Pick up"
	prompt.ObjectText = title
	prompt.HoldDuration = PICKUP_HOLD
	prompt.MaxActivationDistance = PICKUP_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = egg
	prompt.Triggered:Connect(function(player)
		pickup(player, egg)
	end)
	egg.Parent = eggFolder
	local entry = { egg = egg, owner = if owner then owner.UserId else nil }
	table.insert(ground, entry)
	egg.Destroying:Connect(function()
		local i = table.find(ground, entry)
		if i then
			table.remove(ground, i)
		end
	end)
	task.delay(if owner then Economy.EggDespawnSeconds else Economy.EggRainDespawnSeconds, function()
		if egg.Parent then
			egg:Destroy()
		end
	end)
	return egg
end

-- Eggs lying in the field (weather can hit them too, WeatherService). Owner is the player
-- who found it (nil for Egg Rain eggs anyone can grab).
function EggService:GroundEggs(): { { egg: BasePart, owner: number? } }
	return ground
end

-- Weather gives a field egg a mutation: shown on the egg, kept when it's picked up, placed
-- and hatched. False if it already has one.
function EggService:MutateGroundEgg(egg: BasePart, mutation: string): boolean
	if not egg.Parent or egg:GetAttribute("Mutation") then
		return false
	end
	egg:SetAttribute("Mutation", mutation)
	for _, child in egg:GetChildren() do
		if child:IsA("Model") then
			AssetLibrary.applyMutation(child, mutation)
		end
	end
	local label = egg:FindFirstChild("Label")
	local text = label and label:FindFirstChildOfClass("TextLabel")
	local def = Eggs.MutationByName[mutation]
	if text and def then
		text.Text = `{def.Label} {text.Text}`
	end
	return true
end

local TUTORIAL_GRAB = 7 -- studs: the tutorial egg picks itself up this close

-- Before the first hatch, the tutorial arrow points at the player's egg on the ground.
local function trackTutorialEgg(player: Player, session, egg: BasePart)
	if session.Data.Stats.Hatches > 0 or #session.Data.Hatching > 0 or session.Runtime.TutorialEgg then
		return
	end
	session.Runtime.TutorialEgg = egg
	session.Runtime.TutorialEggPosition = egg.Position
	-- Picked up just by walking to it (no hold): 1 in 5 new players never held the prompt.
	task.spawn(function()
		-- (Not an egg they put down themselves: it would jump straight back up.)
		while egg.Parent and session.Runtime.TutorialEgg == egg and player.Parent and egg:GetAttribute("DroppedBy") == nil do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - egg.Position).Magnitude <= TUTORIAL_GRAB then
				pickup(player, egg)
				break
			end
			task.wait(0.15)
		end
	end)
	egg.Destroying:Connect(function()
		if session.Runtime.TutorialEgg == egg then
			session.Runtime.TutorialEgg = nil
			session.Runtime.TutorialEggPosition = nil
			S.StateService:Mark(player)
		end
	end)
end

local function foundEgg(player: Player, position: Vector3, rarity: string, zone: string?)
	local session = S.DataService:GetSession(player)
	if not session then
		return
	end
	local egg = EggService:SpawnEgg(position, rarity, player, zone)
	session.Data.Stats.EggsFound += 1
	session.Runtime.TutorialEggSpawned = true
	trackTutorialEgg(player, session, egg)
	S.AnalyticsService:Custom(player, "EggFound", 1, { Rarity = rarity })
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
		foundEgg(player, position, "Common", zone.Id)
		return
	end
	local luck = S.BoostService:GetServerLuck() * Upgrades.multiplier(session.Data.Upgrades, "Luck") * S.BoostService:GetPersonalLuck(player)
	local sniff = Upgrades.multiplier(session.Data.Upgrades, "EggFind")
	if rng:NextNumber() < zone.EggChance * luck * sniff then
		foundEgg(player, position, EggService:RollRarity(zone.MaxRarity, luck), zone.Id)
	end
end

-- Puts the top egg you're carrying down on the ground in front of you. It stays yours for
-- a while (like a found egg), and you can pick it back up with the prompt.
local DROP_AHEAD = 4 -- studs in front of you

function EggService:DropCarried(player: Player): (boolean, string?)
	local session = S.DataService:GetSession(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not session or not character or not root then
		return false, "Still loading"
	end
	local carried = table.clone(session.Runtime.Carried or {})
	local entry = table.remove(carried)
	if not entry then
		return false, "You're not carrying an egg"
	end
	local ahead = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if ahead.Magnitude < 0.1 then
		ahead = Vector3.new(0, 0, -1)
	end
	local spot = root.Position + ahead.Unit * DROP_AHEAD
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, eggFolder }
	local hit = Workspace:Raycast(spot + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), params)
	local ground = if hit then hit.Position else root.Position - Vector3.new(0, 3, 0)
	local egg = EggService:SpawnEgg(ground, entry.Rarity, player, entry.Zone)
	egg:SetAttribute("DroppedBy", player.UserId)
	trackTutorialEgg(player, session, egg)
	setCarried(player, carried)
	return true, `Dropped your {entry.Rarity} egg`
end

-- Gives an egg without a pickup: straight into the inventory (ignores the bag limit).
function EggService:GiveEgg(player: Player, rarity: string, zone: string?)
	S.InventoryService:AddEgg(player, rarity, zone, true)
end

-- Walking into your hatchery with eggs puts them in your inventory.
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
	for _, entry in carried do
		if not S.InventoryService:AddEgg(player, entry.Rarity, entry.Zone, nil, nil, entry.Mutation) then
			table.insert(remaining, entry)
		end
	end
	if #remaining > 0 then
		Net.fire("Notify", player, "Your egg bag is full! Place or open some eggs first.", "Bad")
	elseif session.Data.Stats.Hatches == 0 and not session.Data.Flags.TutorialDone then
		-- Tutorial: it gets planted for you (StateService), no bag message.
		S.StateService:Mark(player)
	else
		local word = if #carried == 1 then "Egg" else `{#carried} eggs`
		Net.fire("Notify", player, `{word} added to your bag! Place it in an incubator to hatch.`, "Egg")
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
