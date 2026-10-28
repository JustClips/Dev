--!strict
-- Meteor Shower state machine (GAME_PLAN §5.8):
-- Filling -> (Moon bar 100% or product) -> Countdown 10 s -> Shower 60 s (Rare+ eggs rain) -> respawn dust -> Filling.
-- State is published as attributes on ReplicatedStorage.ServerState.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)

local TICK = 0.5
local SKY_TWEEN = TweenInfo.new(3)

local EventService = {}

local S: any
local rng = Random.new()
local stateName = "Filling"
local stateEndsAt = 0
local normalLighting: { [string]: any } = {}

local function publish()
	local state = S.StateService:GetServerState()
	state:SetAttribute("EventState", stateName)
	state:SetAttribute("EventEndsAt", stateEndsAt)
end

local function setSky(shower: boolean)
	local goal = if shower
		then { Ambient = Color3.fromRGB(150, 90, 120), OutdoorAmbient = Color3.fromRGB(140, 80, 110), ColorShift_Top = Color3.fromRGB(255, 120, 80) }
		else normalLighting
	TweenService:Create(Lighting, SKY_TWEEN, goal):Play()
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
	setSky(true)
	Net.fireAll("Announce", "Egg Rain! Grab the rare eggs!", "Event")
end

local function endShower()
	stateName = "Filling"
	stateEndsAt = 0
	S.DustService:RespawnAll()
	S.DustService:ResetMoonProgress()
	publish()
	setSky(false)
	Net.fireAll("Announce", "The leaves are back. Start sweeping!", "Event")
end

local function dropMeteor()
	local position = S.DustService:GetRandomMoonPosition(rng)
	Net.fireAll("MeteorImpact", position)
	task.delay(1.2, function()
		local rarity = S.EggService:RollShowerRarity(S.BoostService:GetServerLuck())
		S.EggService:SpawnEgg(position, rarity, nil)
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

function EventService:GetState(): string
	return stateName
end

function EventService:Init(services)
	S = services
	normalLighting = {
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		ColorShift_Top = Lighting.ColorShift_Top,
	}
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
					dropMeteor()
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
