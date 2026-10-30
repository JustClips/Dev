--!strict
-- Live weather, Grow a Garden 2 style (see Config/Weather for the rules and numbers):
-- a 10 minute day/night cycle, one weighted weather roll per day, a moon roll each night.
-- State goes out as ServerState attributes:
--   CycleStart (server time the current cycle began, Workspace:GetServerTimeNow()),
--   Weather / WeatherEndsAt, Moon.
-- The client WeatherController draws the sky, VFX and sounds from them.
--
-- While a weather or moon runs it upgrades the unopened eggs growing in every park
-- (mutations by chance, lightning / falling stars that hit eggs), makes eggs grow faster,
-- and other services ask here for its bonuses (cash, luck, golden piles, Huge, regrow).
-- Admin chat commands: "/weather <id>" (any weather or moon id, or "off"), "/night"
-- (skip to sunset), "/day", "/eggrain", "/hatchtest <rarity> [huge] [mutation]" (hatch show only),
-- "/eggvariants [rarity]" (a row of that egg in every weather variant for 2 minutes).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Aliens = require(Shared.Config.Aliens)
local AssetLibrary = require(Shared.AssetLibrary)
local Eggs = require(Shared.Config.Eggs)
local Net = require(Shared.Net)
local Items = require(Shared.Config.Items)
local Upgrades = require(Shared.Config.Upgrades)
local Weather = require(Shared.Config.Weather)
local World = require(Shared.Config.World)
local Zones = require(Shared.Config.Zones)

type WeatherDef = Weather.WeatherDef

local WeatherService = {}

local S: any
local rng = Random.new()
local cycleStart = 0 -- server time (float)
local weather: WeatherDef? = nil
local weatherEnds = 0 -- os.time()
local moon: WeatherDef? = nil
local scheduled: WeatherDef? = nil -- today's weather, waiting for its start time
local scheduledAt = 0

local function publish()
	local state = S.StateService:GetServerState()
	state:SetAttribute("CycleStart", cycleStart)
	state:SetAttribute("Weather", if weather then weather.Id else "")
	state:SetAttribute("WeatherEndsAt", weatherEnds)
	state:SetAttribute("Moon", if moon then moon.Id else "")
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function active(): { WeatherDef }
	local list = {}
	if weather then
		table.insert(list, weather)
	end
	if moon then
		table.insert(list, moon)
	end
	return list
end

local function product(field: string): number
	local mult = 1
	for _, def in active() do
		local value = (def :: any)[field]
		if type(value) == "number" then
			mult *= value
		end
	end
	return mult
end

function WeatherService:GetCashMult(): number
	return product("CashMult")
end

function WeatherService:GetLuckMult(): number
	return product("LuckMult")
end

function WeatherService:GetGoldenMult(): number
	return product("GoldenMult")
end

function WeatherService:GetHugeMult(): number
	return product("HugeMult")
end

function WeatherService:GetRegrowMult(): number
	return product("RegrowMult")
end

function WeatherService:GetWeather(): WeatherDef?
	return weather
end

-- Starts a weather (or sets a moon) now. Returns false for an unknown id.
function WeatherService:Begin(id: string, seconds: number?): boolean
	local def = Weather.ById[id]
	if not def then
		return false
	end
	if def.Kind == "Moon" then
		moon = def
	else
		weather = def
		weatherEnds = os.time() + (seconds or def.Duration)
		scheduled = nil
	end
	publish()
	return true
end

function WeatherService:Stop()
	weather = nil
	weatherEnds = 0
	scheduled = nil
	publish()
end

-- Eggs ------------------------------------------------------------------------------------

-- An egg weather can hit: growing in a park (uid), or lying in a leaf field (part; its
-- finder is `player`, nil for Egg Rain eggs).
type GrowingEgg = { player: Player?, uid: string?, part: BasePart?, rarity: string, position: Vector3, mutated: boolean }

-- Every unopened egg in every park and every egg lying in the fields, with where it is.
local function growingEggs(): { GrowingEgg }
	local list = {}
	for _, entry in S.EggService:GroundEggs() do
		local part = entry.egg
		if part.Parent then
			local rarity = part:GetAttribute("Rarity")
			table.insert(list, {
				player = if entry.owner then Players:GetPlayerByUserId(entry.owner) else nil,
				part = part,
				rarity = if type(rarity) == "string" then rarity else "Common",
				position = part.Position - Vector3.new(0, 1.7, 0),
				mutated = part:GetAttribute("Mutation") ~= nil,
			})
		end
	end
	for _, player in Players:GetPlayers() do
		local session = S.DataService:GetSession(player)
		local index = session and session.Runtime.BaseIndex
		if not session or not index then
			continue
		end
		local baseCf = World.baseCFrame(index)
		for _, entry in session.Data.Hatching do
			local position = (baseCf * CFrame.new(entry.X or 0, 0.2, entry.Z or 0)).Position
			table.insert(list, { player = player, uid = entry.Uid, rarity = entry.Rarity, position = position, mutated = entry.Mutation ~= nil })
		end
	end
	return list
end

local function upgradeEgg(egg: GrowingEgg, mutation: string, how: string)
	if egg.part then
		if not S.EggService:MutateGroundEgg(egg.part, mutation) then
			return
		end
	elseif not (egg.player and egg.uid and S.HatchService:SetEggMutation(egg.player, egg.uid, mutation)) then
		return
	end
	local label = Eggs.MutationByName[mutation] and Eggs.MutationByName[mutation].Label or mutation
	Net.fireAll("EggUpgraded", egg.position, mutation)
	if egg.player then
		local where = if egg.part then " in the field" else ""
		Net.fire("Notify", egg.player, `{how} Your {egg.rarity} Egg{where} is {label} now! The pet keeps it.`, "Good")
	end
end

-- Storm Chaser (Egg Lab): this player's eggs get weather mutations more often.
local function weatherMutMult(player: Player): number
	local data = S.DataService:GetData(player)
	return Upgrades.multiplier(data and data.Upgrades, "WeatherMut")
end

local function rollEggMutations()
	for _, def in active() do
		local mutation, chance = def.Mutation, def.EggChance
		if mutation and chance then
			for _, egg in growingEggs() do
				local mult = if egg.player then weatherMutMult(egg.player) else 1
				if not egg.mutated and rng:NextNumber() < chance * mult then
					upgradeEgg(egg, mutation, `{def.Name}!`)
				end
			end
		end
	end
end

-- Mutation Spray (item): one of this player's growing eggs without a mutation gets a random
-- weather mutation (the commoner ones more often).
local SPRAY_WEIGHTS = { Wet = 30, Windswept = 26, Frozen = 18, Shocked = 12, Golden = 8, Disco = 6, Starlit = 5, Bloodlit = 3, Rainbow = 3, Starstruck = 2 }
function WeatherService:SprayEgg(player: Player): (boolean, string?)
	local mine = {}
	for _, egg in growingEggs() do
		if egg.player == player and egg.uid and not egg.mutated then
			table.insert(mine, egg)
		end
	end
	if #mine == 0 then
		return false, "Place an egg in your park first (one without a mutation)"
	end
	local total = 0
	for _, w in SPRAY_WEIGHTS do
		total += w
	end
	local roll, pick = rng:NextNumber() * total, "Wet"
	for name, w in SPRAY_WEIGHTS do
		roll -= w
		if roll <= 0 then
			pick = name
			break
		end
	end
	local egg = mine[rng:NextInteger(1, #mine)]
	if not S.HatchService:SetEggMutation(player, egg.uid :: string, pick) then
		return false, "That egg can't be sprayed right now"
	end
	local label = Eggs.MutationByName[pick] and Eggs.MutationByName[pick].Label or pick
	Net.fireAll("EggUpgraded", egg.position, pick)
	return true, `Psssht! Your {egg.rarity} Egg is {label} now! The pet keeps it.`
end

-- Weather Totem (item): starts a random lucky weather for the whole server.
function WeatherService:Totem(player: Player, minutes: number): (boolean, string?)
	if weather and weatherEnds > os.time() + 30 then
		return false, `{weather.Name} is still going. Use the totem when it's over!`
	end
	local options = Items.TotemWeathers
	local id = options[rng:NextInteger(1, #options)]
	if not WeatherService:Begin(id, minutes * 60) then
		return false, "The totem fizzled. Try again!"
	end
	local def = Weather.ById[id]
	Net.fireAll("Announce", `{player.DisplayName} used a Weather Totem: {def.Name} for {minutes} min!`, "Event")
	return true, `{def.Name} for everyone!`
end

local function growEggs(seconds: number)
	local grow = product("GrowMult")
	if grow <= 1 then
		return
	end
	for _, player in Players:GetPlayers() do
		local index = S.BaseService:GetBaseIndex(player)
		local base = index and S.WorldService:GetBase(index)
		S.HatchService:GrowFaster(player, seconds * (grow - 1), base)
	end
end

-- Strikes ---------------------------------------------------------------------------------

local function inField(spot: Vector3): boolean
	for _, zone in Zones.List do
		if spot.X >= zone.Min.X and spot.X <= zone.Max.X and spot.Z >= zone.Min.Y and spot.Z <= zone.Max.Y then
			return true
		end
	end
	return false
end

-- A random spot on the field: often near a player (so people see it), else anywhere on the map.
local function fieldSpot(nearPlayers: number): Vector3?
	local players = Players:GetPlayers()
	if #players > 0 and rng:NextNumber() < nearPlayers then
		local character = players[rng:NextInteger(1, #players)].Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local spot = root.Position + Vector3.new(rng:NextNumber(-45, 45), -3, rng:NextNumber(-45, 45))
			if inField(spot) then
				return spot
			end
		end
	end
	local zone = Zones.List[rng:NextInteger(1, #Zones.List)]
	return S.DustService:GetRandomTilePosition(zone.Id, rng)
end

local function strike(def: WeatherDef)
	local kind = def.Strikes :: string
	local targets = {}
	for _, egg in growingEggs() do
		if not egg.mutated then
			table.insert(targets, egg)
		end
	end
	if #targets > 0 and rng:NextNumber() < Weather.StrikeEggShare then
		local egg = targets[rng:NextInteger(1, #targets)]
		Net.fireAll("WeatherStrike", egg.position, kind, true)
		task.delay(if kind == "Star" then 1.1 else 0.2, function()
			upgradeEgg(egg, def.StrikeMutation or "Shocked", if kind == "Star" then "A star hit your egg!" else "Lightning hit your egg!")
		end)
		return
	end
	local position = fieldSpot(0.6)
	if not position then
		return
	end
	Net.fireAll("WeatherStrike", position, kind, false)
	task.delay(if kind == "Star" then 1.1 else 0.2, function()
		S.DustService:StrikeGolden(position, 9, Weather.StrikeGolden)
	end)
end

-- Cycle -------------------------------------------------------------------------------------

local function onDay()
	moon = nil
	-- Today's weather: one weighted roll (it may be a clear day), starting at a random time
	-- that lets it finish before sunset.
	local def = Weather.rollDay(rng)
	scheduled = def
	if def then
		local latest = math.max(20, Weather.DaySeconds - def.Duration - 10)
		scheduledAt = os.time() + rng:NextInteger(15, latest)
	end
	publish()
end

local function onNight()
	moon = Weather.rollMoon(rng)
	publish()
end

local trusted = false -- set while the admin panel runs a command (AdminService checked it)

local function isAdmin(player: Player?): boolean
	if trusted then
		return true
	end
	return player ~= nil and (RunService:IsStudio() or table.find(Weather.Admins, player.UserId) ~= nil)
end

-- Moves the cycle so it is now `t` seconds into it.
local function jumpTo(t: number)
	cycleStart = serverNow() - t
	publish()
end

local function onChat(player: Player, message: string)
	if not isAdmin(player) then
		return
	end
	local args = string.split(string.lower(message), " ")
	local command = args[1]
	if command == "/weather" then
		local wanted = args[2] or ""
		if wanted == "off" or wanted == "stop" then
			WeatherService:Stop()
			moon = nil
			publish()
			return
		end
		for id, def in Weather.ById do
			if string.lower(id) == wanted then
				if def.Kind == "Moon" then
					jumpTo(Weather.DaySeconds + Weather.SunsetSeconds + 1)
				end
				WeatherService:Begin(id, tonumber(args[3]))
				return
			end
		end
		local ids = {}
		for id in Weather.ById do
			table.insert(ids, id)
		end
		table.sort(ids)
		Net.fire("Notify", player, "Use: /weather " .. table.concat(ids, ", ") .. ", off", "Info")
	elseif command == "/night" then
		jumpTo(Weather.DaySeconds - 1)
	elseif command == "/day" then
		jumpTo(0)
	elseif command == "/eggrain" then
		S.EventService:TriggerShower(player)
	elseif command == "/eggvariants" then
		-- A row of one egg rarity in every weather variant, in front of you for 2 minutes.
		local rarity = "Rare"
		for _, def in Eggs.Rarities do
			if string.lower(def.Name) == (args[2] or "") then
				rarity = def.Name
			end
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		local folder = Instance.new("Folder")
		folder.Name = "EggVariants"
		folder.Parent = workspace
		local names = {}
		for _, m in Eggs.Mutations do
			if m.WeatherOnly or m.Name == "Golden" or m.Name == "Rainbow" then
				table.insert(names, m.Name)
			end
		end
		local face = CFrame.lookAt(root.Position, root.Position + root.CFrame.LookVector * Vector3.new(1, 0, 1))
		for i, name in names do
			local egg = AssetLibrary.egg(rarity)
			egg.Name = name
			local x = (i - (#names + 1) / 2) * 6
			local at = face * CFrame.new(x, 0, -14)
			local ray = workspace:Raycast(at.Position + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0))
			local y = if ray then ray.Position.Y else root.Position.Y - 3
			egg:PivotTo(CFrame.new(at.Position.X, y, at.Position.Z) * face.Rotation * CFrame.Angles(0, math.pi, 0))
			egg:ScaleTo(1.25)
			for _, d in egg:GetDescendants() do
				if d:IsA("BasePart") then
					d.CanCollide = false
				end
			end
			AssetLibrary.applyMutation(egg, name)
			local label = Instance.new("BillboardGui")
			label.Size = UDim2.fromOffset(160, 30)
			label.StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0)
			label.AlwaysOnTop = true
			local text = Instance.new("TextLabel")
			text.BackgroundTransparency = 1
			text.Size = UDim2.fromScale(1, 1)
			text.Text = Eggs.MutationByName[name].Label
			text.TextColor3 = Eggs.MutationByName[name].Color
			text.TextStrokeTransparency = 0
			text.TextScaled = true
			text.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
			text.Parent = label
			label.Parent = egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")
			egg.Parent = folder
		end
		task.delay(120, function()
			folder:Destroy()
		end)
	elseif command == "/hatchtest" then
		-- Plays the hatch show for a pet of that rarity without giving anything:
		-- "/hatchtest legendary", "/hatchtest mythic huge", "/hatchtest rare golden".
		local rarity: string? = nil
		for _, def in Eggs.Rarities do
			if string.lower(def.Name) == (args[2] or "") then
				rarity = def.Name
			end
		end
		local data = S.DataService:GetData(player)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local bucket = rarity and Aliens.ByRarity[rarity]
		if not rarity or not bucket or #bucket == 0 or not data or not data.BaseIndex or data.BaseIndex == 0 or not root then
			Net.fire("Notify", player, "Use: /hatchtest <common|uncommon|rare|epic|legendary|mythic|cosmic> [huge] [frozen|wet|charged|golden|...]", "Info")
			return
		end
		local def = bucket[math.random(1, #bucket)]
		local mutation: string? = nil
		for _, m in Eggs.Mutations do
			local name, label = string.lower(m.Name), string.lower(m.Label)
			if name == args[3] or name == args[4] or label == args[3] or label == args[4] then
				mutation = m.Name
			end
		end
		local huge = args[3] == "huge" or args[4] == "huge"
		local spot = World.baseCFrame(data.BaseIndex):PointToObjectSpace(root.Position + root.CFrame.LookVector * 12)
		Net.fire("HatchCompleted", player, {
			Test = true,
			AlienId = def.Id,
			Mutation = mutation,
			Huge = huge,
			Rarity = def.Rarity,
			EggRarity = def.Rarity,
			EggMutation = mutation,
			X = spot.X,
			Z = spot.Z,
		})
	end
end

-- The admin panel runs the same commands as admin chat ("/weather rain", "/night"...).
function WeatherService:RunCommand(player: Player?, message: string)
	trusted = true
	local ok, err = pcall(onChat :: any, player, message)
	trusted = false
	if not ok then
		warn("[Weather] " .. tostring(err))
	end
end

function WeatherService:Init(services)
	S = services
end

function WeatherService:Start()
	-- New servers start in the morning.
	cycleStart = serverNow()
	onDay()
	local function hook(player: Player)
		player.Chatted:Connect(function(message)
			onChat(player, message)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end

	task.spawn(function()
		local lastPhase = "Day"
		local nextStrike, nextDrop, nextEggTick, nextGrow = 0, 0, os.clock() + Weather.EggTick, os.clock() + 5
		while true do
			task.wait(0.5)
			local now = os.time()
			local clock = os.clock()
			local phase = Weather.phase(serverNow() - cycleStart)
			if phase ~= lastPhase then
				if phase == "Day" then
					onDay()
				elseif phase == "Night" then
					onNight()
				end
				lastPhase = phase
			end
			-- Today's weather starts when its time comes (never during an Egg Rain).
			if scheduled and now >= scheduledAt and S.EventService:GetState() == "Filling" then
				WeatherService:Begin(scheduled.Id)
			end
			if weather and now >= weatherEnds then
				WeatherService:Stop()
			end

			for _, def in active() do
				if def.Strikes and clock >= nextStrike then
					local every = def.StrikeEvery or Weather.StrikeEvery
					nextStrike = clock + rng:NextNumber(every[1], every[2])
					strike(def)
				end
				if def.DropEggs and clock >= nextDrop then
					nextDrop = clock + rng:NextNumber(Weather.DropEvery[1], Weather.DropEvery[2])
					S.EventService:DropEgg(fieldSpot(0.5), nil)
				end
			end
			if clock >= nextEggTick then
				nextEggTick = clock + Weather.EggTick
				rollEggMutations()
			end
			if clock >= nextGrow then
				nextGrow = clock + 5
				growEggs(5)
			end
		end
	end)
end

return WeatherService
