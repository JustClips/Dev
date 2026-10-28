--!strict
-- Contextual offers (GAME_PLAN §6 "When offers appear"). The server decides when;
-- the client only shows them. Never before the first hatch, max one per 3 minutes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Tools = require(Shared.Config.Tools)

local STUCK_CHECK_SECONDS = 10

local OfferService = {}

local S: any

local function offerState(session)
	local state = session.Runtime.Offers
	if not state then
		state = { lastAny = -math.huge, lastByKey = {}, fullCount = 0, stuckSince = nil }
		session.Runtime.Offers = state
	end
	return state
end

local function isLive(productKey: string): boolean
	local def = Products.ProductByKey[productKey] or Products.PassByKey[productKey]
	return def ~= nil and def.Id ~= 0
end

-- Shows an offer if every rule allows it. ignoreGlobal is for the one-time Starter Pack.
local function show(player: Player, key: string, productKey: string, title: string, text: string, ignoreGlobal: boolean?): boolean
	local session = S.DataService:GetSession(player)
	if not session or session.Data.Stats.Hatches < 1 or not isLive(productKey) then
		return false
	end
	local state = offerState(session)
	local now = os.clock()
	if not ignoreGlobal and now - state.lastAny < Economy.Offers.GlobalCooldown then
		return false
	end
	if now - (state.lastByKey[key] or -math.huge) < Economy.Offers.PerOfferCooldown then
		return false
	end
	state.lastAny = now
	state.lastByKey[key] = now
	local def = Products.ProductByKey[productKey] or Products.PassByKey[productKey]
	Net.fire("ShowOffer", player, { Key = key, Product = productKey, Title = title, Text = text, Price = def.Price })
	S.AnalyticsService:Custom(player, "OfferShown", 1, { Offer = key })
	return true
end

function OfferService:OnHatch(player: Player)
	local data = S.DataService:GetData(player)
	if not data or data.Flags.StarterPackBought or data.Flags.StarterOfferShown then
		return
	end
	if show(player, "StarterPack", "StarterPack", "Starter Pack!", "$500 + an Uncommon egg + 10 min of 2x cash", true) then
		data.Flags.StarterOfferShown = true
	end
end

function OfferService:OnBackpackFull(player: Player)
	local session = S.DataService:GetSession(player)
	if not session then
		return
	end
	local state = offerState(session)
	state.fullCount += 1
	if state.fullCount % Economy.Offers.BackpackFullCount ~= 0 then
		return
	end
	local nextTier = session.Data.ToolTier + 1
	local skipKey = "ToolSkip" .. nextTier
	if nextTier <= Tools.MaxTier and isLive(skipKey) then
		show(player, "BackpackFull", skipKey, "Backpack full again?", `Get the {Tools.get(nextTier).Name} now: {Tools.get(nextTier).Capacity} capacity!`)
	elseif not session.Data.Gamepasses.AutoSweep then
		show(player, "BackpackFull", "AutoSweep", "Sweep on autopilot", "Auto Sweep cleans around you while you walk.")
	end
end

function OfferService:OnRareHatchStarted(player: Player, rarity: string)
	show(player, "SkipHatch", "SkipHatch" .. rarity, `{rarity} egg hatching!`, "Can't wait? Hatch it right now.")
end

function OfferService:OnToolBought(player: Player)
	local session = S.DataService:GetSession(player)
	if session then
		offerState(session).stuckSince = nil
	end
end

function OfferService:OnMoonBarHigh()
	for player in S.DataService:GetSessions() do
		show(player, "ServerLuck", "ServerLuck2", "Meteor Shower soon!", "Boost the whole server's luck for the shower.")
	end
end

-- The welcome back screen itself carries the "Double offline reward" button, so this
-- only records that the offer was shown.
function OfferService:OnWelcomeBack(player: Player)
	local data = S.DataService:GetData(player)
	if data and data.Stats.Hatches >= 1 and isLive("DoubleOffline") then
		S.AnalyticsService:Custom(player, "OfferShown", 1, { Offer = "DoubleOffline" })
	end
end

local function checkStuck()
	local now = os.clock()
	for player, session in S.DataService:GetSessions() do
		local data = session.Data
		local nextTier = data.ToolTier + 1
		if nextTier > Tools.MaxTier then
			continue
		end
		local state = offerState(session)
		if BigNum.lt(data.Cash, Tools.get(nextTier).Price) then
			state.stuckSince = state.stuckSince or now
			if now - state.stuckSince >= Economy.Offers.ToolStuckSeconds then
				if show(player, "ToolStuck", "ToolSkip" .. nextTier, `Unlock the {Tools.get(nextTier).Name}`, "Skip the grind and get it right now.") then
					state.stuckSince = now
				end
			end
		else
			state.stuckSince = nil
		end
	end
end

function OfferService:Init(services)
	S = services
	Net.onEvent("OfferResponse", function(player, key, clicked)
		if type(key) ~= "string" or #key > 40 then
			return
		end
		S.AnalyticsService:Custom(player, if clicked then "OfferClicked" else "OfferDismissed", 1, { Offer = key })
	end)
end

function OfferService:Start()
	task.spawn(function()
		while true do
			task.wait(STUCK_CHECK_SECONDS)
			checkStuck()
		end
	end)
end

return OfferService
