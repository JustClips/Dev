--!strict
-- Meteor Shower state machine (GAME_PLAN §5.8):
-- Filling -> (Moon bar 100% or product) -> Countdown 10 s -> Shower 60 s (Rare+ eggs rain) -> respawn dust -> Filling.
-- State is published as attributes on ReplicatedStorage.ServerState. The sky, the falling
-- eggs and their landing marks are drawn by the client (WeatherController).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Grid = require(Shared.Grid)
local Zones = require(Shared.Config.Zones)
local Net = require(Shared.Net)

local TICK = 0.5
-- Seconds an egg takes to fall from the sky; the real egg appears when it lands.
local FALL_SECONDS = 2.2

local EventService = {}

local S: any
local rng = Random.new()
local stateName = "Filling"
local stateEndsAt = 0

local function publish()
	local state = S.StateService:GetServerState()
	state:SetAttribute("EventState", stateName)
	state:SetAttribute("EventEndsAt", stateEndsAt)
end

local function startCountdown()
	stateName = "Countdown"
	stateEndsAt = os.time() + Economy.Shower.CountdownSeconds
	publish()
	Net.fireAll("Announce", "The world is clean! EGG RAIN incoming!", "Event")
end

local function startShower()
	stateName = "Shower"
	stateEndsAt = os.time() + Economy.Shower.DurationSeconds
	publish()
	Net.fireAll("Announce", "Egg Rain! Grab the rare eggs!", "Event")
end

local function endShower()
	stateName = "Filling"
	stateEndsAt = 0
	S.DustService:RespawnAll()
	S.DustService:ResetMoonProgress()
	publish()
	Net.fireAll("Announce", "The leaves are back. Start sweeping!", "Event")
end

-- Snaps a spot to the nearest leaf tile (nil when it isn't on the field).
local function onField(spot: Vector3): Vector3?
	local found: Vector3? = nil
	Grid.forEachInRadius(spot, 8, function(id)
		found = found or Grid.tilePosition(id)
	end)
	return found
end

-- Half the eggs land near someone so everybody gets to see (and chase) them; the rest
-- anywhere on the map, every zone.
local function dropSpot(): Vector3
	local players = Players:GetPlayers()
	if #players > 0 and rng:NextNumber() < 0.5 then
		local character = players[rng:NextInteger(1, #players)].Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local found = onField(root.Position + Vector3.new(rng:NextNumber(-35, 35), 0, rng:NextNumber(-35, 35)))
			if found then
				return found
			end
		end
	end
	local zone = Zones.List[rng:NextInteger(1, #Zones.List)]
	return S.DustService:GetRandomTilePosition(zone.Id, rng) or S.DustService:GetRandomMoonPosition(rng)
end

-- An egg falls out of the sky (every client draws the fall and the landing mark), then
-- the real, pick-up-able egg appears where it lands. Also used by the Mega Moon
-- (WeatherService) with a spot and the zone's own rarity roll.
function EventService:DropEgg(position: Vector3?, rarity: string?)
	local spot = (position and onField(position)) or dropSpot()
	local egg = rarity
	if not egg then
		if stateName == "Shower" then
			egg = S.EggService:RollShowerRarity(S.BoostService:GetServerLuck())
		else
			local zone = Grid.zoneAt(spot)
			egg = S.EggService:RollRarity(if zone then zone.MaxRarity else "Rare", S.BoostService:GetServerLuck())
		end
	end
	local finalRarity = egg :: string
	Net.fireAll("EggDrop", spot, finalRarity, FALL_SECONDS)
	task.delay(FALL_SECONDS, function()
		S.EggService:SpawnEgg(spot, finalRarity, nil)
	end)
end

-- Product: start the shower now (or make the current one longer).
function EventService:TriggerShower(buyer: Player?)
	local who = if buyer then buyer.DisplayName else "Someone"
	if stateName == "Filling" then
		Net.fireAll("Announce", `{who} called an Egg Rain for the whole server!`, "Event")
		startCountdown()
	elseif stateName == "Shower" then
		stateEndsAt += Economy.Shower.ExtendSecondsWhenBought
		publish()
		Net.fireAll("Announce", `{who} made the Egg Rain longer!`, "Event")
	end
	-- During the countdown it is already on its way; the purchase still counts.
end

-- Admin panel: an Egg Rain right now for `seconds` (longer if one is already falling).
function EventService:AdminShower(seconds: number)
	local ends = os.time() + seconds
	if stateName == "Shower" then
		stateEndsAt = math.max(stateEndsAt, ends)
		publish()
		return
	end
	stateName = "Shower"
	stateEndsAt = ends
	publish()
	Net.fireAll("Announce", "Egg Rain! Grab the rare eggs!", "Event")
end

-- Admin panel: stops a falling Egg Rain now.
function EventService:AdminStopShower()
	if stateName == "Shower" or stateName == "Countdown" then
		endShower()
	end
end

function EventService:GetState(): string
	return stateName
end

function EventService:Init(services)
	S = services
end

function EventService:Start()
	publish()
	task.spawn(function()
		local nextEgg = 0
		while true do
			task.wait(TICK)
			local progress = S.DustService:GetMoonProgress()
			S.StateService:GetServerState():SetAttribute("MoonClean", progress)
			local now = os.time()
			if stateName == "Filling" then
				if progress >= 1 then
					startCountdown()
				end
			elseif stateName == "Countdown" then
				if now >= stateEndsAt then
					startShower()
				end
			elseif stateName == "Shower" then
				if os.clock() >= nextEgg then
					nextEgg = os.clock() + Economy.Shower.EggInterval
					EventService:DropEgg()
				end
				if now >= stateEndsAt then
					endShower()
				end
			end
			if stateName == "Filling" and progress >= Economy.Offers.MoonBarFraction then
				S.OfferService:OnMoonBarHigh()
			end
		end
	end)
end

return EventService
