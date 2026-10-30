--!strict
-- Codes players type in the Codes window (social media codes). Each player can use each
-- code once; codes can expire.
--
-- Two sources:
--   src/server/Config/Codes.luau  codes that ship with the game
--   the "GameCodes" DataStore     codes admins add in-game (admin panel, Codes tab). They
--                                 work in every server: a MessagingService ping makes all
--                                 servers reload, and every server reloads each minute.
--
-- Remotes: RedeemCode(code) -> ok, message (players)
--          Admin("CodeAdd" | "CodeRemove" | "CodeList", payload) via AdminService
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Admin = require(Shared.Config.Admin)
local Eggs = require(Shared.Config.Eggs)
local Items = require(Shared.Config.Items)
local MockDataStore = require(script.Parent.Parent.Lib.MockDataStore)
local Net = require(Shared.Net)
local Rewards = require(Shared.Config.Rewards)
local BuiltIn = require(script.Parent.Parent.Config.Codes)

local STORE = "GameCodes_v1"
local KEY = "Codes"
local TOPIC = "CodesChanged"
local RELOAD_SECONDS = 60
-- Wrong guesses: after this many in a minute, the player waits a bit.
local MAX_WRONG = 6

export type StoredCode = {
	Rewards: { Rewards.Reward },
	ExpiresAt: number?,
	By: string?,
	CreatedAt: number?,
}

local CodeService = {}

local S: any
local store: any = nil
local custom: { [string]: StoredCode } = {}
local builtIn: { [string]: StoredCode } = {}
local wrong: { [Player]: { count: number, since: number } } = {}

-- "  release " -> "RELEASE". Letters and digits only.
local function normalize(text: any): string?
	if type(text) ~= "string" then
		return nil
	end
	local clean = string.upper((string.gsub(string.sub(text, 1, 60), "[^%w]", "")))
	if clean == "" or #clean > Admin.MaxCodeLength then
		return nil
	end
	return clean
end

local function getStore(): any
	if store then
		return store
	end
	if S.DataService.UsingMock or game.GameId == 0 then
		store = MockDataStore.new()
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE)
	end)
	store = if ok then result else MockDataStore.new()
	return store
end

local function reload()
	local ok, result = pcall(function()
		return getStore():GetAsync(KEY)
	end)
	if ok then
		custom = if type(result) == "table" then result else {}
	else
		warn("[Codes] couldn't load admin codes: " .. tostring(result))
	end
end

local function find(code: string): StoredCode?
	return custom[code] or builtIn[code]
end

-- Checks a reward from the admin panel. Returns a clean copy or nil.
local function cleanReward(r: any): Rewards.Reward?
	if type(r) ~= "table" then
		return nil
	end
	if r.Kind == "Cash" then
		local minutes = tonumber(r.Minutes)
		if not minutes or minutes ~= minutes then
			return nil
		end
		minutes = math.clamp(math.floor(minutes), 1, 24 * 60)
		return { Kind = "Cash", Seconds = minutes * 60, Floor = math.clamp(minutes / 20, 0.1, 4) }
	elseif r.Kind == "Item" then
		local item = type(r.Item) == "string" and Items.ById[r.Item]
		local amount = tonumber(r.Amount)
		if not item or not amount or amount ~= amount then
			return nil
		end
		return { Kind = "Item", Item = item.Id, Amount = math.clamp(math.floor(amount), 1, 50) }
	elseif r.Kind == "Egg" then
		local rarity = type(r.Rarity) == "string" and Eggs.ByName[r.Rarity]
		if not rarity then
			return nil
		end
		return { Kind = "Egg", Rarity = r.Rarity }
	end
	return nil
end

local function tellServers()
	task.spawn(function()
		pcall(function()
			MessagingService:PublishAsync(TOPIC, "reload")
		end)
	end)
end

-------------------------------------------------------------------------- players

local function redeem(player: Player, text: any): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return false, "Still loading, try again in a second"
	end
	local now = os.time()
	local tries = wrong[player]
	if tries and now - tries.since < 60 and tries.count >= MAX_WRONG then
		return false, `Too many tries. Wait {60 - (now - tries.since)} s`
	end
	local code = normalize(text)
	local def = code and find(code)
	if not code or not def then
		if not tries or now - tries.since >= 60 then
			tries = { count = 0, since = now }
			wrong[player] = tries
		end
		tries.count += 1
		return false, "That code doesn't exist. Check the spelling!"
	end
	if data.RedeemedCodes[code] then
		return false, "You already used this code"
	end
	if def.ExpiresAt and def.ExpiresAt <= now then
		return false, "This code has expired"
	end
	data.RedeemedCodes[code] = now
	local got = {}
	for i, reward in def.Rewards do
		local label = S.RewardService:Grant(player, reward, `Code_{code}_{i}`)
		if label ~= "" then
			table.insert(got, label)
		end
	end
	S.StateService:Mark(player)
	S.AnalyticsService:Custom(player, "CodeRedeemed", 1, { Code = code })
	return true, `Code redeemed! You got {table.concat(got, " + ")}`
end

-------------------------------------------------------------------------- admins

-- Every code with its source, newest custom ones first (for the admin panel list).
function CodeService:List(): { { [string]: any } }
	local out = {}
	local now = os.time()
	for code, def in custom do
		table.insert(out, {
			Code = code,
			Rewards = def.Rewards,
			ExpiresAt = def.ExpiresAt,
			Expired = def.ExpiresAt ~= nil and def.ExpiresAt <= now,
			By = def.By,
			CreatedAt = def.CreatedAt or 0,
			Custom = true,
		})
	end
	table.sort(out, function(a, b)
		return a.CreatedAt > b.CreatedAt
	end)
	for _, def in BuiltIn do
		if not custom[def.Code] then
			table.insert(out, {
				Code = def.Code,
				Rewards = def.Rewards,
				ExpiresAt = def.ExpiresAt,
				Expired = def.ExpiresAt ~= nil and def.ExpiresAt <= now,
				Custom = false,
			})
		end
	end
	return out
end

-- payload { Code, Rewards = { {Kind, Minutes? | Item, Amount? | Rarity?} }, Days? (0/nil = never) }
function CodeService:Add(caller: Player, p: any): (boolean, string)
	local code = normalize(p.Code)
	if not code then
		return false, `Type a code (letters and numbers, up to {Admin.MaxCodeLength})`
	end
	if builtIn[code] then
		return false, "That code is built into the game already"
	end
	local list = {}
	for _, r in (if type(p.Rewards) == "table" then p.Rewards else {}) do
		local clean = cleanReward(r)
		if clean and #list < Admin.MaxCodeRewards then
			table.insert(list, clean)
		end
	end
	if #list == 0 then
		return false, "Add at least one reward"
	end
	local days = tonumber(p.Days) or 0
	if days ~= days then
		days = 0
	end
	days = math.clamp(days, 0, Admin.MaxCodeDays)
	local entry: StoredCode = {
		Rewards = list,
		ExpiresAt = if days > 0 then os.time() + math.floor(days * 86400) else nil,
		By = caller.Name,
		CreatedAt = os.time(),
	}
	local ok, err = pcall(function()
		getStore():UpdateAsync(KEY, function(old)
			local all = if type(old) == "table" then old else {}
			all[code] = entry
			return all
		end)
	end)
	if not ok then
		warn("[Codes] save failed: " .. tostring(err))
		return false, "Couldn't save the code (DataStore error)"
	end
	custom[code] = entry
	tellServers()
	print(`[Codes] {caller.Name} added {code}`)
	return true, `Code {code} is live in every server`
end

function CodeService:Remove(caller: Player, p: any): (boolean, string)
	local code = normalize(p.Code)
	if not code then
		return false, "Which code?"
	end
	if not custom[code] then
		return false, if builtIn[code] then "Built-in codes are removed in Config/Codes.luau" else "No such code"
	end
	local ok, err = pcall(function()
		getStore():UpdateAsync(KEY, function(old)
			local all = if type(old) == "table" then old else {}
			all[code] = nil
			return all
		end)
	end)
	if not ok then
		warn("[Codes] delete failed: " .. tostring(err))
		return false, "Couldn't delete the code (DataStore error)"
	end
	custom[code] = nil
	tellServers()
	print(`[Codes] {caller.Name} removed {code}`)
	return true, `Code {code} deleted`
end

-------------------------------------------------------------------------- setup

function CodeService:Init(services)
	S = services
	for _, def in BuiltIn do
		local code = normalize(def.Code)
		if code then
			builtIn[code] = { Rewards = def.Rewards, ExpiresAt = def.ExpiresAt }
		end
	end
	Net.onInvoke("RedeemCode", function(player, text)
		return redeem(player, text)
	end)
end

function CodeService:Start()
	task.spawn(function()
		reload()
		pcall(function()
			MessagingService:SubscribeAsync(TOPIC, function()
				task.wait(math.random() * 2) -- don't have every server read at the same moment
				reload()
			end)
		end)
		while true do
			task.wait(RELOAD_SECONDS)
			reload()
		end
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		wrong[player] = nil
	end)
end

return CodeService
