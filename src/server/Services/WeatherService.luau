--!strict
-- Live weather (Config/Weather): every few minutes the server rolls a weather for everyone.
-- State goes out as ServerState attributes (Weather, WeatherStartedAt, WeatherEndsAt);
-- the client WeatherController draws the sky, VFX and sounds from them.
-- Other services ask this one for the weather's bonuses (cash, luck, golden piles, Huge,
-- mutations). Admins can start one with the chat command "/weather <id>" (any id from
-- Config/Weather, or "off"), and an Egg Rain with "/eggrain".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Weather = require(Shared.Config.Weather)
local Zones = require(Shared.Config.Zones)

type WeatherDef = Weather.WeatherDef

local WeatherService = {}

local S: any
local rng = Random.new()
local current: WeatherDef? = nil
local endsAt = 0
local nextAt = 0

local function publish()
	local state = S.StateService:GetServerState()
	state:SetAttribute("Weather", if current then current.Id else "")
	state:SetAttribute("WeatherEndsAt", endsAt)
end

local function stop()
	if not current then
		return
	end
	current = nil
	endsAt = 0
	nextAt = os.time() + rng:NextInteger(Weather.GapMin, Weather.GapMax)
	publish()
end

-- Starts a weather now (replacing the current one). Returns false for an unknown id.
function WeatherService:Begin(id: string, seconds: number?): boolean
	local def = Weather.ById[id]
	if not def then
		return false
	end
	current = def
	endsAt = os.time() + (seconds or def.Duration)
	publish() -- every client shows the banner, sky and effects (WeatherController)
	return true
end

function WeatherService:Stop()
	stop()
end

function WeatherService:GetCurrent(): WeatherDef?
	return current
end

function WeatherService:GetCashMult(): number
	return if current and current.CashMult then current.CashMult else 1
end

function WeatherService:GetLuckMult(): number
	return if current and current.LuckMult then current.LuckMult else 1
end

function WeatherService:GetGoldenMult(): number
	return if current and current.GoldenMult then current.GoldenMult else 1
end

function WeatherService:GetHugeMult(): number
	return if current and current.HugeMult then current.HugeMult else 1
end

-- The weather's own mutation, rolled once per hatch (nil most of the time).
function WeatherService:RollMutation(r: Random): string?
	local def = current
	if def and def.Mutation and def.MutationChance and r:NextNumber() < def.MutationChance then
		return def.Mutation
	end
	return nil
end

-- Thunderstorm: a bolt hits a random spot on the field (often near a player, so people
-- see it) and turns a few piles there golden.
local function strike()
	local position: Vector3? = nil
	local players = Players:GetPlayers()
	if #players > 0 and rng:NextNumber() < 0.6 then
		local character = players[rng:NextInteger(1, #players)].Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local offset = Vector3.new(rng:NextNumber(-40, 40), 0, rng:NextNumber(-40, 40))
			local spot = root.Position + offset
			-- Only on the field (the bases and plaza have no piles).
			for _, zone in Zones.List do
				if spot.X >= zone.Min.X and spot.X <= zone.Max.X and spot.Z >= zone.Min.Y and spot.Z <= zone.Max.Y then
					position = Vector3.new(spot.X, root.Position.Y - 3, spot.Z)
					break
				end
			end
		end
	end
	if not position then
		local zone = Zones.List[rng:NextInteger(1, #Zones.List)]
		position = S.DustService:GetRandomTilePosition(zone.Id, rng)
	end
	if not position then
		return
	end
	Net.fireAll("WeatherStrike", position)
	task.delay(0.15, function()
		S.DustService:StrikeGolden(position, 9, Weather.StrikeGolden)
	end)
end

local function isAdmin(player: Player): boolean
	return RunService:IsStudio() or table.find(Weather.Admins, player.UserId) ~= nil
end

local function onChat(player: Player, message: string)
	if not isAdmin(player) then
		return
	end
	local args = string.split(string.lower(message), " ")
	if args[1] == "/weather" then
		local wanted = args[2] or ""
		if wanted == "off" or wanted == "stop" then
			stop()
			return
		end
		for _, def in Weather.List do
			if string.lower(def.Id) == wanted then
				WeatherService:Begin(def.Id, tonumber(args[3]))
				return
			end
		end
		local ids = {}
		for _, def in Weather.List do
			table.insert(ids, def.Id)
		end
		Net.fire("Notify", player, "Weathers: " .. table.concat(ids, ", ") .. ", off", "Info")
	elseif args[1] == "/eggrain" then
		S.EventService:TriggerShower(player)
	end
end

function WeatherService:Init(services)
	S = services
end

function WeatherService:Start()
	nextAt = os.time() + Weather.FirstDelay
	publish()
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
		local nextStrike = 0
		local last: string? = nil
		while true do
			task.wait(0.5)
			local now = os.time()
			local def = current
			if def then
				if now >= endsAt then
					last = def.Id
					stop()
				elseif def.Strikes and os.clock() >= nextStrike then
					nextStrike = os.clock() + rng:NextNumber(Weather.StrikeEvery[1], Weather.StrikeEvery[2])
					strike()
				end
			elseif now >= nextAt and S.EventService:GetState() == "Filling" then
				-- Never during an Egg Rain (it has its own sky); never the same one twice in a row.
				WeatherService:Begin(Weather.pick(rng, last).Id)
			end
		end
	end)
end

return WeatherService
