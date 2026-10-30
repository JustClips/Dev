--!strict
-- Rare hatches in the chat window, Sol's RNG style (Dev, 2026-10-30: the on-screen "X
-- hatched" strip was annoying). How far a hatch is shown depends on how rare it is:
--   1 in SERVER_ODDS or rarer (or Mythic+, or a Huge): a coloured line in this server's chat.
--   1 in GLOBAL_ODDS or rarer: a [GLOBAL] line in every server's chat.
-- The line is coloured like the pet's rarity (ChatController draws it).
--
-- MessagingService has per-server limits, so this server sends at most one global report
-- every SEND_GAP seconds (the rarest one waiting), and shows at most one from elsewhere
-- every SHOW_GAP seconds (rarest first, older ones dropped).
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Aliens = require(Shared.Config.Aliens)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local TOPIC = "RareHatch"
local SERVER_ODDS = 1_000 -- this server's chat
local GLOBAL_ODDS = 25_000 -- every server's chat
local SEND_GAP = 4
local SHOW_GAP = 3
local QUEUE_MAX = 4
local JOB = if game.JobId ~= "" then game.JobId else "studio"

local HatchFeedService = {}

type Report = { Text: string, Odds: number, Job: string, Rarity: string }

local outbox: Report? = nil
local inbox: { Report } = {}
local lastSent = 0
local lastShown = 0

-- "1 in N" for a hatch from this egg at no luck: rarity step x Huge x rolled mutation.
function HatchFeedService:Odds(eggRarity: string, petRarity: string, huge: boolean, mutation: string?): number
	local odds = Eggs.hatchOdds(eggRarity, 1)
	local pct = odds[Eggs.order(petRarity)] or 0
	local n = if pct > 0 then 100 / pct else 1
	if huge then
		n /= Aliens.HugeChance
	end
	local m = mutation and Eggs.MutationByName[mutation]
	if m and not m.WeatherOnly and m.Chance > 0 then
		n *= m.Chance
	end
	return n
end

local function oddsText(n: number): string
	if n >= 1_000_000 then
		return `{math.floor(n / 100_000 + 0.5) / 10}M`
	end
	return Format.number(math.floor(n + 0.5))
end

-- Called by HatchService after every hatch. Only rare ones are shown.
function HatchFeedService:Report(player: Player, pet: { Name: string, Rarity: string }, eggRarity: string, huge: boolean, mutation: string?)
	local odds = HatchFeedService:Odds(eggRarity, pet.Rarity, huge, mutation)
	if odds < SERVER_ODDS and not huge and Eggs.order(pet.Rarity) < Eggs.order("Mythic") then
		return
	end
	local m = mutation and Eggs.MutationByName[mutation]
	local label = (if huge then "HUGE " else "") .. (if m then m.Label .. " " else "")
	local text = `{player.DisplayName} hatched a {label}{pet.Name} ({pet.Rarity}), 1 in {oddsText(odds)}!`
	Net.fireAll("ChatHatch", text, pet.Rarity)
	if odds >= GLOBAL_ODDS and (not outbox or odds > outbox.Odds) then
		outbox = { Text = text, Odds = odds, Job = JOB, Rarity = pet.Rarity }
	end
end

local function receive(message: any)
	local ok, report = pcall(function()
		return HttpService:JSONDecode(message.Data)
	end)
	if not ok or type(report) ~= "table" or type(report.Text) ~= "string" or report.Job == JOB then
		return
	end
	local rarity = if type(report.Rarity) == "string" and Eggs.ByName[report.Rarity] then report.Rarity else "Mythic"
	table.insert(inbox, { Text = string.sub(report.Text, 1, 160), Odds = tonumber(report.Odds) or 0, Job = tostring(report.Job), Rarity = rarity })
	table.sort(inbox, function(a, b)
		return a.Odds > b.Odds
	end)
	while #inbox > QUEUE_MAX do
		table.remove(inbox)
	end
end

function HatchFeedService:Start()
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(TOPIC, receive)
		end)
		if not ok then
			warn("[HatchFeed] subscribe failed: " .. tostring(err))
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			if outbox and now - lastSent >= SEND_GAP then
				local report = outbox
				outbox = nil
				lastSent = now
				task.spawn(function()
					pcall(function()
						MessagingService:PublishAsync(TOPIC, HttpService:JSONEncode(report))
					end)
				end)
			end
			if #inbox > 0 and now - lastShown >= SHOW_GAP then
				lastShown = now
				local report = table.remove(inbox, 1) :: Report
				Net.fireAll("ChatHatch", "[GLOBAL] " .. report.Text, report.Rarity)
			end
		end
	end)
end

return HatchFeedService
