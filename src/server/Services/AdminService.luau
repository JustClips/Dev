--!strict
-- The admin panel's server side. Only the players in Config/Admin can call it; every call
-- is checked here (the client panel is just buttons).
--
-- Net.func("Admin"):InvokeServer(action, payload) -> ok, message
--   Give        { Target, Kind, Id?, Amount?, Mutation?, Huge?, Minutes? }
--               Kind: Cash | Egg | Pet | Item | Tool | Vehicle | Boost
--   ServerLuck  { Mult, Minutes }
--   Command     { Text }               weather/time/egg rain chat commands (WeatherService)
--   EggRain     {}
--   DropEggs    { Rarity, Count }      eggs fall from the sky around the map
--   Announce    { Text, Seconds }
--   PollStart   { Question, Options, Seconds }
--   PollEnd     {}
--   Goto / Bring / Respawn / Kick { Target, Reason? }
-- Target is "me", "all" or a UserId. Everything is for this server only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Admin = require(Shared.Config.Admin)
local Aliens = require(Shared.Config.Aliens)
local BigNum = require(Shared.BigNum)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Tools = require(Shared.Config.Tools)
local Weights = require(Shared.Config.Weights)

local AdminService = {}

local S: any
local rng = Random.new()

---------------------------------------------------------------------------- helpers

local function targets(caller: Player, who: any): { Player }
	if who == "me" or who == nil then
		return { caller }
	elseif who == "all" then
		return Players:GetPlayers()
	elseif type(who) == "number" then
		local p = Players:GetPlayerByUserId(who)
		return if p then { p } else {}
	end
	return {}
end

local function whole(value: any, min: number, max: number, default: number): number
	local n = tonumber(value)
	if not n or n ~= n then
		return default
	end
	return math.clamp(math.floor(n), min, max)
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
	local clean = string.upper(string.gsub(text, "[%s,$]", ""))
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
	text = string.sub(string.gsub(text, "^%s+", ""), 1, maxLength)
	if text == "" then
		return nil
	end
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	return if ok then result else nil
end

local function notify(player: Player, text: string)
	Net.fire("Notify", player, text, "Good")
end

local function log(caller: Player, text: string)
	print(`[Admin] {caller.Name} ({caller.UserId}): {text}`)
end

------------------------------------------------------------------------------- give

local function givePet(player: Player, petId: string, mutation: string?, huge: boolean): boolean
	local data = S.DataService:GetData(player)
	local def = Aliens.ById[petId]
	if not data or not def then
		return false
	end
	local uid = S.DataService:NewUid(data, "p")
	data.Pets[uid] = {
		Id = def.Id,
		Mutation = mutation,
		Huge = if huge then true else nil,
		Weight = Weights.rollPet(rng, def.Rarity, def.Rarity, nil),
	}
	data.Index[def.Id] = true
	return true
end

local function give(caller: Player, p: any): (boolean, string)
	local list = targets(caller, p.Target)
	if #list == 0 then
		return false, "That player isn't here"
	end
	local kind = p.Kind
	local label: string
	local each: (Player) -> boolean
	if kind == "Cash" then
		local amount = parseCash(p.Amount)
		if not amount then
			return false, "Type an amount like 500, 25k, 1.5T or 1e30"
		end
		label = Format.cash(amount)
		each = function(target)
			S.BackpackService:GiveCash(target, amount, "Admin")
			return true
		end
	elseif kind == "Egg" then
		local rarity = p.Id
		if type(rarity) ~= "string" or not Eggs.ByName[rarity] then
			return false, "Pick an egg"
		end
		local count = whole(p.Amount, 1, Admin.MaxEggs, 1)
		label = `{count} {rarity} Egg{if count > 1 then "s" else ""}`
		each = function(target)
			for _ = 1, count do
				S.InventoryService:AddEgg(target, rarity, nil, true)
			end
			return true
		end
	elseif kind == "Pet" then
		local def = type(p.Id) == "string" and Aliens.ById[p.Id]
		if not def then
			return false, "Pick a pet"
		end
		local mutation = if type(p.Mutation) == "string" and Eggs.MutationByName[p.Mutation] then p.Mutation else nil
		local huge = p.Huge == true
		local count = whole(p.Amount, 1, Admin.MaxPets, 1)
		label = `{count}x {if huge then "Huge " else ""}{if mutation then mutation .. " " else ""}{def.Name}`
		each = function(target)
			for _ = 1, count do
				givePet(target, def.Id, mutation, huge)
			end
			S.InventoryService:Touch(target)
			return true
		end
	elseif kind == "Item" then
		local def = type(p.Id) == "string" and Items.ById[p.Id]
		if not def then
			return false, "Pick a potion"
		end
		local count = whole(p.Amount, 1, Admin.MaxItems, 1)
		label = `{count}x {def.Name}`
		each = function(target)
			S.InventoryService:AddItem(target, def.Id, count)
			return true
		end
	elseif kind == "Tool" then
		local tier = whole(p.Id, 1, Tools.MaxTier, 1)
		label = `the {Tools.get(tier).Name}`
		each = function(target)
			S.ToolService:SetTier(target, tier)
			return true
		end
	elseif kind == "Vehicle" then
		local car = type(p.Id) == "string" and Tools.vehicle(p.Id)
		if not car then
			return false, "Pick a car"
		end
		label = `the {car.Name}`
		each = function(target)
			S.ToolService:GrantVehicle(target, car.Id)
			return true
		end
	elseif kind == "Boost" then
		if type(p.Id) ~= "string" or not table.find(Admin.Boosts, p.Id) then
			return false, "Pick a boost"
		end
		local minutes = whole(p.Minutes, 1, Admin.MaxBoostMinutes, 15)
		label = `{p.Id} for {minutes} min`
		each = function(target)
			S.BoostService:AddPersonalBoost(target, p.Id, minutes)
			return true
		end
	else
		return false, "Unknown gift"
	end
	local given = 0
	for _, target in list do
		if S.DataService:GetData(target) and each(target) then
			given += 1
			S.StateService:Mark(target)
			if target ~= caller then
				notify(target, `An admin gave you {label}!`)
			end
		end
	end
	log(caller, `gave {label} to {given} player(s)`)
	return given > 0, if given == 1 and list[1] == caller then `Gave yourself {label}` else `Gave {label} to {given} player(s)`
end

------------------------------------------------------------------------------ polls

type Poll = {
	Id: number,
	Question: string,
	Options: { string },
	Votes: { number },
	EndsAt: number,
	From: string,
	Ended: boolean?,
}
local poll: Poll? = nil
local ballots: { [number]: number } = {} -- UserId -> option
local pollId = 0
local dirty = false

local function publishPoll()
	dirty = false
	Net.fireAll("Poll", poll)
end

local function endPoll(id: number)
	local current = poll
	if not current or current.Id ~= id or current.Ended then
		return
	end
	current.Ended = true
	current.EndsAt = os.time()
	publishPoll()
	-- The results stay up a little, then the card goes.
	task.delay(10, function()
		if poll and poll.Id == id then
			poll = nil
			publishPoll()
		end
	end)
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
	pollId += 1
	table.clear(ballots)
	local seconds = whole(p.Seconds, 10, Admin.MaxPollSeconds, 60)
	local votes = table.create(#options, 0)
	poll = {
		Id = pollId,
		Question = question,
		Options = options,
		Votes = votes,
		EndsAt = os.time() + seconds,
		From = caller.DisplayName,
	}
	local id = pollId
	task.delay(seconds, function()
		endPoll(id)
	end)
	publishPoll()
	log(caller, `started poll "{question}"`)
	return true, "Poll started"
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
		current.Votes[before] -= 1
	end
	current.Votes[choice] += 1
	ballots[player.UserId] = choice
	dirty = true
end

--------------------------------------------------------------------------- players

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function one(caller: Player, who: any): Player?
	local list = targets(caller, who)
	return if #list == 1 then list[1] else nil
end

------------------------------------------------------------------------------ calls

local ACTIONS: { [string]: (Player, any) -> (boolean, string) } = {
	Give = give,
	ServerLuck = function(caller, p)
		local mult = whole(p.Mult, 2, 16, 2)
		local minutes = whole(p.Minutes, 1, 24 * 60, 15)
		S.BoostService:AddServerLuck(mult, minutes, caller)
		log(caller, `server luck {mult}x {minutes} min`)
		return true, `{mult}x Server Luck for {minutes} min`
	end,
	Command = function(caller, p)
		if type(p.Text) ~= "string" or string.sub(p.Text, 1, 1) ~= "/" then
			return false, "Bad command"
		end
		S.WeatherService:RunCommand(caller, string.sub(p.Text, 1, 60))
		log(caller, p.Text)
		return true, "Done"
	end,
	EggRain = function(caller)
		S.EventService:TriggerShower(caller)
		log(caller, "egg rain")
		return true, "Egg Rain started"
	end,
	DropEggs = function(caller, p)
		local rarity = if type(p.Rarity) == "string" and Eggs.ByName[p.Rarity] then p.Rarity else nil
		local count = whole(p.Count, 1, 40, 10)
		for i = 1, count do
			task.delay(i * 0.15, function()
				S.EventService:DropEgg(nil, rarity)
			end)
		end
		log(caller, `dropped {count} {rarity or "random"} eggs`)
		return true, `Dropping {count} eggs`
	end,
	Announce = function(caller, p)
		local text = filter(caller, p.Text, Admin.MaxMessage)
		if not text then
			return false, "Type a message"
		end
		local seconds = whole(p.Seconds, 3, 60, 8)
		Net.fireAll("Broadcast", { Text = text, From = caller.DisplayName, Seconds = seconds })
		log(caller, `announced "{text}"`)
		return true, "Sent to everyone"
	end,
	PollStart = startPoll,
	PollEnd = function(caller)
		if not poll or poll.Ended then
			return false, "No poll running"
		end
		endPoll(poll.Id)
		log(caller, "ended the poll")
		return true, "Poll ended"
	end,
	Goto = function(caller, p)
		local target = one(caller, p.Target)
		local from, to = rootOf(caller), target and rootOf(target)
		if not from or not to then
			return false, "Can't reach them"
		end
		(caller.Character :: Model):PivotTo(to.CFrame * CFrame.new(0, 0, 4))
		return true, `Went to {(target :: Player).DisplayName}`
	end,
	Bring = function(caller, p)
		local here = rootOf(caller)
		local count = 0
		for _, target in targets(caller, p.Target) do
			if target ~= caller and here and target.Character and rootOf(target) then
				count += 1
				target.Character:PivotTo(here.CFrame * CFrame.new((count % 5 - 2) * 3, 0, -5))
			end
		end
		log(caller, `brought {count} player(s)`)
		return count > 0, if count > 0 then `Brought {count} player(s)` else "Nobody to bring"
	end,
	Respawn = function(caller, p)
		local count = 0
		for _, target in targets(caller, p.Target) do
			target:LoadCharacter()
			count += 1
		end
		return count > 0, `Respawned {count} player(s)`
	end,
	Kick = function(caller, p)
		local target = one(caller, p.Target)
		if not target or target == caller then
			return false, "Pick someone else to kick"
		end
		if Admin.isAdmin(target.UserId) then
			return false, "Admins can't be kicked"
		end
		local reason = filter(caller, p.Reason, 100) or "Kicked by an admin"
		log(caller, `kicked {target.Name}: {reason}`)
		target:Kick(reason)
		return true, `Kicked {target.DisplayName}`
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
	-- Votes are sent out at most twice a second; late joiners get the running poll.
	task.spawn(function()
		while true do
			task.wait(0.5)
			if dirty and poll then
				publishPoll()
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
			poll.Votes[choice] -= 1
			ballots[player.UserId] = nil
			dirty = true
		end
	end)
end

return AdminService
