--!strict
-- The admin panel's server side. Only the players in Config/Admin can call it; every call
-- is checked here (the client panel is just buttons).
--
-- Net.func("Admin"):InvokeServer(action, payload) -> ok, message
-- Every payload can carry Global = true: then it runs in every server of the game
-- (MessagingService), not only this one ("admin abuse" events).
--   Give       { Target, Kind, Id?, Amount?, Mutation?, Huge?, Minutes? }
--              Kind: Cash | Egg | Pet | Item | Tool | Vehicle | Boost
--              Target: "me", "all" or a UserId (in global mode "all" is everyone everywhere)
--   Event      { Type, Value?, Minutes, Rarity?, Rate? }  timed events, any number at once:
--              Luck / Cash / Huge / Hatch (x multipliers), Speed (+walk speed),
--              Weather (Value = weather id), EggRain, Drops (eggs fall all over the map)
--   StopEvent  { Id }
--   Time       { Value = "day" | "night" }
--   Announce   { Text, Seconds }
--   PollStart  { Question, Options, Seconds } / PollEnd {}
--
-- Global timed events are also kept in a MemoryStore hash map until they end, so servers
-- that start later pick them up too.
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Admin = require(Shared.Config.Admin)
local Aliens = require(Shared.Config.Aliens)
local BaseSkins = require(Shared.Config.BaseSkins)
local BigNum = require(Shared.BigNum)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Tools = require(Shared.Config.Tools)
local Weather = require(Shared.Config.Weather)
local Weights = require(Shared.Config.Weights)

local AdminService = {}

local S: any
local rng = Random.new()
local TOPIC = "AdminGlobal"
local JOB = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)

---------------------------------------------------------------------------- helpers

local function whole(value: any, min: number, max: number, default: number): number
	local n = tonumber(value)
	if not n or n ~= n then
		return default
	end
	return math.clamp(math.floor(n), min, max)
end

local function number(value: any, min: number, max: number, default: number): number
	local n = tonumber(value)
	if not n or n ~= n then
		return default
	end
	return math.clamp(n, min, max)
end

-- "1.5T", "250k", "1e30", "42" -> BigNum
local SUFFIX = { K = 3, M = 6, B = 9, T = 12, QA = 15, QI = 18, SX = 21, SP = 24, OC = 27, NO = 30, DC = 33 }
local function parseCash(text: any): BigNum.BigNum?
	if type(text) == "number" then
		return if text > 0 and text < math.huge then BigNum.from(text) else nil
	end
	if type(text) ~= "string" then
		return nil
	end
	local clean = string.upper((string.gsub(text, "[%s,$]", "")))
	local m, e = string.match(clean, "^([%d%.]+)E(%d+)$")
	if m and e then
		local mm = tonumber(m)
		return if mm and mm > 0 then BigNum.new(mm, tonumber(e) :: number) else nil
	end
	local num, suffix = string.match(clean, "^([%d%.]+)(%a*)$")
	local n = num and tonumber(num)
	if not n or n <= 0 then
		return nil
	end
	if suffix == nil or suffix == "" then
		return BigNum.from(n)
	end
	local exp = SUFFIX[suffix]
	return if exp then BigNum.new(n, exp) else nil
end

-- Admin text is still player text: it goes through Roblox's filter before anyone sees it.
local function filter(player: Player, text: any, maxLength: number): string?
	if type(text) ~= "string" then
		return nil
	end
	text = string.sub((string.gsub(text, "^%s+", "")), 1, maxLength)
	if text == "" then
		return nil
	end
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	return if ok then result else nil
end

local function log(who: string, text: string)
	print(`[Admin] {who}: {text}`)
end

local onGlobal: (raw: any) -> ()
local subscribed = false

-- Sends a message to every server (this one too). If MessagingService isn't working, this
-- server still runs it, and the result is false so the admin hears about it.
local function broadcast(message: { [string]: any }): boolean
	message.Job = JOB
	local json = HttpService:JSONEncode(message)
	local ok, err = pcall(function()
		MessagingService:PublishAsync(TOPIC, json)
	end)
	if not ok then
		warn("[Admin] global publish failed: " .. tostring(err))
	end
	if not ok or not subscribed then
		-- Our own subscription delivers it here normally; without one, run it now.
		task.spawn(onGlobal, { Data = json })
	end
	return ok
end

------------------------------------------------------------------------------- give

local function givePet(player: Player, petId: string, mutation: string?, huge: boolean)
	local data = S.DataService:GetData(player)
	local def = Aliens.ById[petId]
	if not data or not def then
		return
	end
	data.Pets[S.DataService:NewUid(data, "p")] = {
		Id = def.Id,
		Mutation = mutation,
		Huge = if huge then true else nil,
		Weight = Weights.rollPet(rng, def.Rarity, def.Rarity, nil),
	}
	data.Index[def.Id] = true
end

-- Checks a gift and returns what it is plus a function that gives it to one player.
local function prepareGift(p: any): (string?, ((Player) -> ())?)
	local kind = p.Kind
	if kind == "Cash" then
		local amount = parseCash(p.Amount)
		if not amount then
			return "Type an amount like 500, 25k, 1.5T or 1e30", nil
		end
		return Format.cash(amount), function(target)
			S.BackpackService:GiveCash(target, amount, "Admin")
		end
	elseif kind == "Egg" then
		local rarity = p.Id
		if type(rarity) ~= "string" or not Eggs.ByName[rarity] then
			return "Pick an egg", nil
		end
		local count = whole(p.Amount, 1, Admin.MaxEggs, 1)
		return `{count} {rarity} Egg{if count > 1 then "s" else ""}`, function(target)
			for _ = 1, count do
				S.InventoryService:AddEgg(target, rarity, nil, true)
			end
		end
	elseif kind == "Pet" then
		local def = type(p.Id) == "string" and Aliens.ById[p.Id]
		if not def then
			return "Pick a pet", nil
		end
		local mutation = if type(p.Mutation) == "string" and Eggs.MutationByName[p.Mutation] then p.Mutation else nil
		local huge = p.Huge == true
		local count = whole(p.Amount, 1, Admin.MaxPets, 1)
		return `{count}x {if huge then "Huge " else ""}{if mutation then mutation .. " " else ""}{def.Name}`, function(target)
			for _ = 1, count do
				givePet(target, def.Id, mutation, huge)
			end
			S.InventoryService:Touch(target)
		end
	elseif kind == "Item" then
		local def = type(p.Id) == "string" and Items.ById[p.Id]
		if not def then
			return "Pick a potion", nil
		end
		local count = whole(p.Amount, 1, Admin.MaxItems, 1)
		return `{count}x {def.Name}`, function(target)
			S.InventoryService:AddItem(target, def.Id, count)
		end
	elseif kind == "Tool" then
		local tier = whole(p.Id, 1, Tools.MaxTier, 1)
		return `the {Tools.get(tier).Name}`, function(target)
			S.ToolService:SetTier(target, tier)
		end
	elseif kind == "Vehicle" then
		local car = type(p.Id) == "string" and Tools.vehicle(p.Id)
		if not car then
			return "Pick a car", nil
		end
		return `the {car.Name}`, function(target)
			S.ToolService:GrantVehicle(target, car.Id)
		end
	elseif kind == "BaseSkin" then
		local skin = type(p.Id) == "string" and BaseSkins.ById[p.Id]
		if not skin then
			return "Pick a base", nil
		end
		return `the {skin.Name} base`, function(target)
			S.BaseSkinService:Grant(target, skin.Id)
		end
	elseif kind == "Boost" then
		if type(p.Id) ~= "string" or not table.find(Admin.Boosts, p.Id) then
			return "Pick a boost", nil
		end
		local minutes = whole(p.Minutes, 1, Admin.MaxBoostMinutes, 15)
		return `{p.Id} for {minutes} min`, function(target)
			S.BoostService:AddPersonalBoost(target, p.Id, minutes)
		end
	end
	return "Unknown gift", nil
end

-- Gives to the targets that are in this server. Returns how many got it.
local function giveHere(p: any, from: string, callerId: number?): number
	local label, each = prepareGift(p)
	if not each or not label then
		return 0
	end
	local list: { Player } = {}
	if p.Target == "all" then
		list = Players:GetPlayers()
	elseif p.Target == "me" then
		local me = callerId and Players:GetPlayerByUserId(callerId)
		list = if me then { me } else {}
	elseif type(p.Target) == "number" then
		local one = Players:GetPlayerByUserId(p.Target)
		list = if one then { one } else {}
	end
	local given = 0
	for _, target in list do
		if S.DataService:GetData(target) then
			each(target)
			given += 1
			S.StateService:Mark(target)
			if target.UserId ~= callerId then
				Net.fire("Notify", target, `{from} gave you {label}!`, "Good")
			end
		end
	end
	return given
end

local function give(caller: Player, p: any): (boolean, string)
	local label, each = prepareGift(p)
	if not each then
		return false, label or "Unknown gift"
	end
	if p.Global and p.Target ~= "me" then
		local ok = broadcast({ Kind = "Give", Payload = p, From = caller.DisplayName, Caller = caller.UserId })
		log(caller.Name, `gave {label} to {p.Target} in every server`)
		return true, if ok then `Giving {label} in every server` else `Gave {label} here only (other servers unreachable)`
	end
	local given = giveHere(p, caller.DisplayName, caller.UserId)
	log(caller.Name, `gave {label} to {given} player(s)`)
	if given == 0 then
		return false, "That player isn't here"
	end
	return true, if p.Target == "me" then `Gave yourself {label}` else `Gave {label} to {given} player(s)`
end

----------------------------------------------------------------------------- events

type Event = {
	Id: string,
	Type: string,
	Value: any,
	EndsAt: number,
	From: string,
	Global: boolean,
	Rarity: string?,
	Rate: number?,
}
local active: { [string]: Event } = {}
local started: { [string]: boolean } = {} -- one-off effects already run here (weather, egg rain)

local EVENT_TYPES = Admin.Events

local function publishEvents()
	local list = {}
	for _, e in active do
		table.insert(list, { Id = e.Id, Type = e.Type, Value = e.Value, EndsAt = e.EndsAt, Global = e.Global, Rarity = e.Rarity })
	end
	S.StateService:GetServerState():SetAttribute("AdminEvents", HttpService:JSONEncode(list))
end

-- Highest running value of a multiplier event (1 when none).
function AdminService:Mult(kind: string): number
	local best = 1
	local now = os.time()
	for _, e in active do
		if e.Type == kind and e.EndsAt > now and type(e.Value) == "number" then
			best = math.max(best, e.Value)
		end
	end
	return best
end

-- Highest running value of an additive event (0 when none).
function AdminService:Add(kind: string): number
	local best = 0
	local now = os.time()
	for _, e in active do
		if e.Type == kind and e.EndsAt > now and type(e.Value) == "number" then
			best = math.max(best, e.Value)
		end
	end
	return best
end

local function eventLabel(e: Event): string
	local def = EVENT_TYPES[e.Type]
	if e.Type == "Weather" then
		local w = Weather.ById[e.Value]
		return if w then w.Name else "Weather"
	elseif def and def.Unit == "x" then
		return `{e.Value}x {def.Name}`
	elseif def and def.Unit == "+" then
		return `+{e.Value} {def.Name}`
	end
	return if def then def.Name else e.Type
end

-- Starts what an event does once (weather, egg rain) and drops eggs while it runs.
local function runEvent(e: Event)
	if started[e.Id] then
		return
	end
	started[e.Id] = true
	local left = e.EndsAt - os.time()
	if left <= 0 then
		return
	end
	if e.Type == "Weather" then
		local def = Weather.ById[e.Value]
		if def and def.Kind == "Moon" then
			S.WeatherService:RunCommand(nil, "/weather " .. string.lower(def.Id))
		elseif def then
			S.WeatherService:Begin(def.Id, left)
		end
	elseif e.Type == "EggRain" then
		S.EventService:AdminShower(left)
	elseif e.Type == "Drops" then
		task.spawn(function()
			local gap = 60 / math.max(1, e.Rate or 20)
			while active[e.Id] and os.time() < e.EndsAt do
				S.EventService:DropEgg(nil, e.Rarity)
				task.wait(gap)
			end
		end)
	end
end

local function addEvent(e: Event)
	-- One weather at a time: a new one replaces the running one.
	if e.Type == "Weather" then
		for id, other in active do
			if other.Type == "Weather" then
				active[id] = nil
			end
		end
	end
	active[e.Id] = e
	runEvent(e)
	publishEvents()
	Net.fireAll("Broadcast", {
		Text = `{eventLabel(e)} for {Format.time(math.max(0, e.EndsAt - os.time()))}{if e.Global then " in EVERY server" else ""}!`,
		From = e.From,
		Seconds = 6,
		Title = "ADMIN EVENT",
	})
end

local function removeEvent(id: string)
	local e = active[id]
	if not e then
		return
	end
	active[id] = nil
	if e.Type == "Weather" then
		S.WeatherService:Stop()
	elseif e.Type == "EggRain" then
		S.EventService:AdminStopShower()
	end
	publishEvents()
end

local globalMap: MemoryStoreHashMap? = nil
local function map(): MemoryStoreHashMap?
	if not globalMap then
		local ok, result = pcall(function()
			return MemoryStoreService:GetHashMap("AdminEvents")
		end)
		globalMap = if ok then result else nil
	end
	return globalMap
end

-- Global events that started before this server did (or messages it missed).
local function syncGlobal()
	local m = map()
	if not m then
		return
	end
	local ok, pages = pcall(function()
		return (m :: any):ListItemsAsync(50)
	end)
	if not ok or not pages then
		return
	end
	local now = os.time()
	local seen = {}
	while true do
		for _, item in pages:GetCurrentPage() do
			local e = item.value
			if type(e) == "table" and type(e.Id) == "string" and (tonumber(e.EndsAt) or 0) > now then
				seen[e.Id] = true
				if not active[e.Id] then
					active[e.Id] = e :: any
					runEvent(e :: any)
				end
			end
		end
		if pages.IsFinished then
			break
		end
		local more = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not more then
			break
		end
	end
	-- Global events stopped elsewhere.
	for id, e in active do
		if e.Global and not seen[id] then
			removeEvent(id)
		end
	end
	publishEvents()
end

local function startEvent(caller: Player, p: any): (boolean, string)
	local def = EVENT_TYPES[p.Type]
	if not def then
		return false, "Unknown event"
	end
	local minutes = number(p.Minutes, 0.25, Admin.MaxEventMinutes, def.Minutes)
	local e: Event = {
		Id = HttpService:GenerateGUID(false),
		Type = p.Type,
		Value = nil,
		EndsAt = os.time() + math.floor(minutes * 60),
		From = caller.DisplayName,
		Global = p.Global == true,
	}
	if def.Unit == "x" or def.Unit == "+" then
		e.Value = number(p.Value, def.Min, def.Max, def.Default)
	elseif p.Type == "Weather" then
		if type(p.Value) ~= "string" or not Weather.ById[p.Value] then
			return false, "Pick a weather"
		end
		e.Value = p.Value
	elseif p.Type == "Drops" then
		e.Rarity = if type(p.Rarity) == "string" and Eggs.ByName[p.Rarity] then p.Rarity else nil
		e.Rate = whole(p.Rate, 1, 120, 20)
	end
	if e.Global then
		local m = map()
		local stored = m and pcall(function()
			(m :: any):SetAsync(e.Id, e, math.max(60, e.EndsAt - os.time() + 30))
		end)
		local sent = broadcast({ Kind = "Event", Event = e })
		if not stored and not sent then
			log(caller.Name, "global event ran here only")
		end
	else
		addEvent(e)
	end
	log(caller.Name, `started {eventLabel(e)} for {minutes} min{if e.Global then " (global)" else ""}`)
	return true, `{eventLabel(e)} started{if e.Global then " in every server" else ""}`
end

local function stopEvent(caller: Player, p: any): (boolean, string)
	local e = type(p.Id) == "string" and active[p.Id]
	if not e then
		return false, "That event already ended"
	end
	if e.Global then
		local m = map()
		if m then
			pcall(function()
				(m :: any):RemoveAsync(e.Id)
			end)
		end
		broadcast({ Kind = "Stop", Id = e.Id })
	end
	removeEvent(e.Id)
	log(caller.Name, `stopped {eventLabel(e)}`)
	return true, `Stopped {eventLabel(e)}`
end

------------------------------------------------------------------------------ polls

type Poll = {
	Id: string,
	Question: string,
	Options: { string },
	Votes: { number },
	EndsAt: number,
	From: string,
	Global: boolean,
	Ended: boolean?,
}
local poll: Poll? = nil
local localVotes: { number } = {}
local remoteVotes: { [string]: { number } } = {} -- other servers' counts (global polls)
local ballots: { [number]: number } = {} -- UserId -> option
local dirty = false
local sharedDirty = false

local function totals(): { number }
	local current = poll :: Poll
	local sum = table.create(#current.Options, 0)
	for i = 1, #sum do
		sum[i] = localVotes[i] or 0
		for _, counts in remoteVotes do
			sum[i] += counts[i] or 0
		end
	end
	return sum
end

local function publishPoll()
	dirty = false
	if poll then
		poll.Votes = totals()
	end
	Net.fireAll("Poll", poll)
end

local function endPoll(id: string)
	local current = poll
	if not current or current.Id ~= id or current.Ended then
		return
	end
	current.Ended = true
	current.EndsAt = os.time()
	publishPoll()
	task.delay(12, function()
		if poll and poll.Id == id then
			poll = nil
			publishPoll()
		end
	end)
end

local function beginPoll(p: Poll)
	poll = p
	localVotes = table.create(#p.Options, 0)
	table.clear(remoteVotes)
	table.clear(ballots)
	local id = p.Id
	task.delay(math.max(1, p.EndsAt - os.time()), function()
		endPoll(id)
	end)
	publishPoll()
end

local function startPoll(caller: Player, p: any): (boolean, string)
	local question = filter(caller, p.Question, 120)
	if not question then
		return false, "Type a question"
	end
	local options = {}
	if type(p.Options) == "table" then
		for i = 1, math.min(4, #p.Options) do
			local text = filter(caller, p.Options[i], 40)
			if text then
				table.insert(options, text)
			end
		end
	end
	if #options < 2 then
		return false, "Polls need at least 2 answers"
	end
	local seconds = whole(p.Seconds, 10, Admin.MaxPollSeconds, 60)
	local newPoll: Poll = {
		Id = HttpService:GenerateGUID(false),
		Question = question,
		Options = options,
		Votes = table.create(#options, 0),
		EndsAt = os.time() + seconds,
		From = caller.DisplayName,
		Global = p.Global == true,
	}
	if newPoll.Global then
		broadcast({ Kind = "Poll", Poll = newPoll })
	else
		beginPoll(newPoll)
	end
	log(caller.Name, `started poll "{question}"`)
	return true, if newPoll.Global then "Poll started in every server" else "Poll started"
end

local function vote(player: Player, choice: any)
	local current = poll
	if not current or current.Ended or type(choice) ~= "number" then
		return
	end
	choice = math.floor(choice)
	if choice < 1 or choice > #current.Options then
		return
	end
	local before = ballots[player.UserId]
	if before == choice then
		return
	end
	if before then
		localVotes[before] = math.max(0, (localVotes[before] or 0) - 1)
	end
	localVotes[choice] = (localVotes[choice] or 0) + 1
	ballots[player.UserId] = choice
	dirty = true
	sharedDirty = current.Global
end

------------------------------------------------------------------- global messages

function onGlobal(raw: any)
	local ok, message = pcall(function()
		return HttpService:JSONDecode(raw.Data)
	end)
	if not ok or type(message) ~= "table" then
		return
	end
	local kind = message.Kind
	if kind == "Give" and type(message.Payload) == "table" then
		giveHere(message.Payload, tostring(message.From or "An admin"), tonumber(message.Caller))
	elseif kind == "Event" and type(message.Event) == "table" then
		local e = message.Event
		if not active[e.Id] and (tonumber(e.EndsAt) or 0) > os.time() then
			addEvent(e)
		end
	elseif kind == "Stop" and type(message.Id) == "string" then
		removeEvent(message.Id)
	elseif kind == "Announce" and type(message.Text) == "string" then
		Net.fireAll("Broadcast", { Text = message.Text, From = message.From, Seconds = message.Seconds, Global = true })
	elseif kind == "Poll" and type(message.Poll) == "table" then
		beginPoll(message.Poll)
	elseif kind == "PollEnd" and type(message.Id) == "string" then
		endPoll(message.Id)
	elseif kind == "Votes" and message.Job ~= JOB and poll and message.Id == poll.Id and type(message.Votes) == "table" then
		remoteVotes[message.Job] = message.Votes
		dirty = true
	elseif kind == "Time" and (message.Value == "day" or message.Value == "night") then
		S.WeatherService:RunCommand(nil, "/" .. message.Value)
	end
end

------------------------------------------------------------------------------ calls

local ACTIONS: { [string]: (Player, any) -> (boolean, string) } = {
	Give = give,
	Event = startEvent,
	StopEvent = stopEvent,
	Time = function(caller, p)
		if p.Value ~= "day" and p.Value ~= "night" then
			return false, "Day or night?"
		end
		if p.Global then
			broadcast({ Kind = "Time", Value = p.Value })
		else
			S.WeatherService:RunCommand(nil, "/" .. p.Value)
		end
		log(caller.Name, p.Value)
		return true, if p.Value == "day" then "It's day now" else "Night falls"
	end,
	Announce = function(caller, p)
		local text = filter(caller, p.Text, Admin.MaxMessage)
		if not text then
			return false, "Type a message"
		end
		local seconds = whole(p.Seconds, 3, 60, 8)
		if p.Global then
			broadcast({ Kind = "Announce", Text = text, From = caller.DisplayName, Seconds = seconds })
		else
			Net.fireAll("Broadcast", { Text = text, From = caller.DisplayName, Seconds = seconds })
		end
		log(caller.Name, `announced "{text}"`)
		return true, if p.Global then "Sent to every server" else "Sent to this server"
	end,
	PollStart = startPoll,
	PollEnd = function(caller)
		local current = poll
		if not current or current.Ended then
			return false, "No poll running"
		end
		if current.Global then
			broadcast({ Kind = "PollEnd", Id = current.Id })
		end
		endPoll(current.Id)
		log(caller.Name, "ended the poll")
		return true, "Poll ended"
	end,
}

function AdminService:Init(services)
	S = services
	Net.onInvoke("Admin", function(player, action: any, payload: any)
		if not Admin.isAdmin(player.UserId) then
			warn(`[Admin] {player.Name} ({player.UserId}) is not an admin`)
			return false, "Not allowed"
		end
		local fn = type(action) == "string" and ACTIONS[action]
		if not fn then
			return false, "Unknown action"
		end
		local ok, a, b = pcall(fn, player, if type(payload) == "table" then payload else {})
		if not ok then
			warn("[Admin] " .. tostring(a))
			return false, "That didn't work (see server output)"
		end
		return a, b
	end)
	Net.onEvent("PollVote", vote)
end

function AdminService:Start()
	publishEvents()
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(TOPIC, onGlobal)
		end)
		subscribed = ok
		if not ok then
			warn("[Admin] can't listen for global admin actions: " .. tostring(err))
		end
		syncGlobal()
	end)
	-- Ends events on time, shares poll votes with other servers, re-checks global events.
	task.spawn(function()
		local lastSync = os.clock()
		local lastShare = 0
		while true do
			task.wait(0.5)
			local now = os.time()
			local changed = false
			for id, e in active do
				if e.EndsAt <= now then
					active[id] = nil
					changed = true
				end
			end
			if changed then
				publishEvents()
			end
			if dirty and poll then
				publishPoll()
			end
			if sharedDirty and poll and poll.Global and os.clock() - lastShare > 2 then
				lastShare = os.clock()
				sharedDirty = false
				broadcast({ Kind = "Votes", Id = poll.Id, Votes = localVotes })
			end
			if os.clock() - lastSync > 20 and not RunService:IsStudio() then
				lastSync = os.clock()
				task.spawn(syncGlobal)
			end
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		if poll then
			Net.fire("Poll", player, poll)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local choice = ballots[player.UserId]
		if choice and poll and not poll.Ended then
			localVotes[choice] = math.max(0, (localVotes[choice] or 0) - 1)
			ballots[player.UserId] = nil
			dirty = true
			sharedDirty = poll.Global
		end
	end)
end

return AdminService
