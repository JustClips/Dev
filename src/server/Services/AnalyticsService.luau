--!strict
-- Thin wrapper around Roblox AnalyticsService. Every call is pcall'd so analytics can
-- never break gameplay. What it logs (Creator Hub > Analytics):
--   * Onboarding funnel (new players only, once each): join, loading done, broom in hand,
--     first sweep, then every tutorial step, ending at "Tutorial done".
--   * One-time funnels per player: Tools (tier reached), Zones (zone unlocked), Rebirths,
--     Playtime (total minutes played, new players only).
--   * Recurring funnels: Session (how long each visit lasts), Store (shop opened ->
--     purchase prompt -> bought), Wheel (wheel opened -> spun -> bought spins).
--   * Economy events (Cash in / out) and custom events (windows opened, eggs, hatches,
--     upgrades, purchases, where people were when they left).
local HttpService = game:GetService("HttpService")
local RobloxAnalytics = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Net = require(Shared.Net)
local Zones = require(Shared.Config.Zones)

-- Onboarding funnel, in order. The tutorial keys (Sweep...Done) come from
-- StateService's tutorialStep: reaching a tutorial step means the one before it is done,
-- so each is logged under what the player just did.
local ONBOARDING: { { key: string, name: string } } = {
	{ key = "Spawn", name = "Joined" },
	{ key = "Loaded", name = "Loading screen done" },
	{ key = "ToolEquipped", name = "Tool in hand" },
	{ key = "FirstSweep", name = "First sweep" },
	{ key = "Egg", name = "Tutorial egg appeared" },
	{ key = "Base", name = "Picked up egg" },
	{ key = "Place", name = "Brought egg home" },
	{ key = "Hatching", name = "Placed egg" },
	{ key = "Open", name = "Egg ready to open" },
	{ key = "PlacePet", name = "Hatched egg" },
	{ key = "Sell", name = "Pet placed (auto)" },
	{ key = "Shop", name = "First sell" },
	{ key = "Upgrade", name = "Got free Broom" },
	{ key = "Wheel", name = "Got free Sweep Power" },
	{ key = "Quest", name = "Spun wheel" },
	{ key = "Done", name = "Accepted first quest / tutorial done" },
}
local ONBOARDING_INDEX: { [string]: number } = {}
for i, step in ONBOARDING do
	ONBOARDING_INDEX[step.key] = i
end

-- Recurring "Session" funnel: minutes into this visit.
local SESSION_MINUTES = { 0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120 }
-- One-time "Playtime" funnel: total minutes played (new players only).
local PLAYTIME_MINUTES = { 2, 5, 10, 15, 30, 45, 60, 90, 120, 180, 300, 600 }
local MAX_REBIRTH_STEP = 50

-- Windows the client may report as opened (screen names in src/gui).
local WINDOWS: { [string]: boolean } = {
	Shop = true,
	Index = true,
	Rebirth = true,
	Garage = true,
	Upgrades = true,
	Inventory = true,
	Daily = true,
	Playtime = true,
	Events = true,
	Settings = true,
	PetsPanel = true,
	EggsPanel = true,
	GroupReward = true,
	BasePicker = true,
	Codes = true,
	Merchant = true,
	Wheel = true,
}
-- A Store/Wheel funnel visit stays the same visit this long after the window opened.
local VISIT_SECONDS = 300

local CURRENCY = "Cash"

local AnalyticsService = {}

local S: any
local incomeBuffer: { [Player]: number } = {}

type Visit = { id: string, at: number }
type Runtime = {
	sessionId: string,
	sessionStep: number,
	store: Visit?,
	wheel: Visit?,
	lastWindow: string?,
	windows: number,
}
local runtime: { [Player]: Runtime } = {}

local function balance(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return 0
	end
	return math.min(BigNum.toNumber(data.Cash), 1e300)
end

local function try(fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn("[Analytics] " .. tostring(err))
	end
end

-- Onboarding is only tracked for players who started after it existed; older saves get
-- false so they don't flood the funnel with steps they did long ago.
local function onboardFlags(player: Player): { [string]: boolean }?
	local data = S.DataService:GetData(player)
	if not data then
		return nil
	end
	local flags = data.Flags.Onboard
	return if type(flags) == "table" then flags else nil
end

local function logOnboarding(player: Player, upTo: number)
	local flags = onboardFlags(player)
	if not flags then
		return
	end
	-- Steps skipped on the way (e.g. two tutorial steps done in one go) are logged too, so
	-- the funnel never shows more players at a later step than at an earlier one.
	for i = 1, upTo do
		local step = ONBOARDING[i]
		if not flags[step.key] then
			flags[step.key] = true
			try(function()
				RobloxAnalytics:LogOnboardingFunnelStepEvent(player, i, step.name)
			end)
		end
	end
end

-- Onboarding step by key (Spawn, Loaded, ToolEquipped, FirstSweep). Other old keys
-- (FirstEgg, FirstHatch...) are custom events now and are ignored here.
function AnalyticsService:Funnel(player: Player, step: string)
	local index = ONBOARDING_INDEX[step]
	if index then
		logOnboarding(player, index)
	end
end

-- The server-confirmed tutorial step changed (StateService).
function AnalyticsService:TutorialStep(player: Player, step: string)
	local index = ONBOARDING_INDEX[step]
	if index and index > ONBOARDING_INDEX.FirstSweep then
		-- Reaching "Egg" means the step before it ("Sweep") is done: log up to here.
		logOnboarding(player, index)
	end
end

-- One-time funnel step (Tools, Zones, Rebirths, Playtime): logged once per player.
function AnalyticsService:Progress(player: Player, funnel: string, step: number, stepName: string)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	local key = `{funnel}:{step}`
	if data.Flags.Funnel[key] then
		return
	end
	data.Flags.Funnel[key] = true
	try(function()
		RobloxAnalytics:LogFunnelStepEvent(player, funnel, nil, step, stepName)
	end)
end

local function recurring(player: Player, funnel: string, id: string, step: number, stepName: string)
	try(function()
		RobloxAnalytics:LogFunnelStepEvent(player, funnel, id, step, stepName)
	end)
end

-- The current Store/Wheel visit, or a new one (a prompt opened from an offer popup or
-- a world sign has no shop visit before it).
local function visit(rt: Runtime, which: "store" | "wheel", fresh: boolean): Visit
	local current = rt[which]
	if fresh or not current or os.clock() - current.at > VISIT_SECONDS then
		current = { id = HttpService:GenerateGUID(false), at = os.clock() }
		rt[which] = current
	end
	return current :: Visit
end

-- A Robux purchase prompt opened (ShopService). Wheel spin packs count for the Wheel funnel.
function AnalyticsService:PromptShown(player: Player, productKey: string, isWheel: boolean?)
	local rt = runtime[player]
	if not rt then
		return
	end
	if isWheel then
		recurring(player, "Wheel", visit(rt, "wheel", false).id, 3, "Buy spins prompt")
	else
		recurring(player, "Store", visit(rt, "store", false).id, 2, "Purchase prompt")
	end
	AnalyticsService:Custom(player, "PurchasePrompt", 1, { Product = productKey, From = rt.lastWindow or "World" })
end

-- A Robux purchase went through (product or gamepass).
function AnalyticsService:Purchased(player: Player, productKey: string, price: number, isWheel: boolean?)
	local rt = runtime[player]
	if not rt then
		return
	end
	if isWheel then
		recurring(player, "Wheel", visit(rt, "wheel", false).id, 4, "Bought spins")
	else
		recurring(player, "Store", visit(rt, "store", false).id, 3, "Bought")
	end
	local data = S.DataService:GetData(player)
	if data then
		data.Flags.Purchases = (data.Flags.Purchases or 0) + 1
		if data.Flags.Purchases == 1 then
			AnalyticsService:Custom(player, "FirstPurchase", price, { Product = productKey })
		end
	end
end

-- The wheel was spun (RewardService).
function AnalyticsService:WheelSpun(player: Player)
	local rt = runtime[player]
	if rt then
		recurring(player, "Wheel", visit(rt, "wheel", false).id, 2, "Spun")
	end
end

function AnalyticsService:Source(player: Player, amount: number, transactionType: Enum.AnalyticsEconomyTransactionType, sku: string?)
	if amount <= 0 then
		return
	end
	try(function()
		RobloxAnalytics:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Source, CURRENCY, math.min(amount, 1e300), balance(player), transactionType.Name, sku)
	end)
end

function AnalyticsService:Sink(player: Player, amount: number, transactionType: Enum.AnalyticsEconomyTransactionType, sku: string?)
	if amount <= 0 then
		return
	end
	try(function()
		RobloxAnalytics:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Sink, CURRENCY, math.min(amount, 1e300), balance(player), transactionType.Name, sku)
	end)
end

-- Alien income ticks every second; batch it into one event per minute.
function AnalyticsService:Income(player: Player, amount: number)
	incomeBuffer[player] = (incomeBuffer[player] or 0) + amount
end

function AnalyticsService:Custom(player: Player, eventName: string, value: number?, fields: { [string]: string }?)
	try(function()
		local customFields = nil
		if fields then
			-- Roblox accepts up to three custom fields using these keys.
			customFields = {}
			local keys = { Enum.AnalyticsCustomFieldKeys.CustomField01.Name, Enum.AnalyticsCustomFieldKeys.CustomField02.Name, Enum.AnalyticsCustomFieldKeys.CustomField03.Name }
			local i = 1
			for k, v in fields do
				if i > 3 then
					break
				end
				customFields[keys[i]] = `{k}:{v}`
				i += 1
			end
		end
		RobloxAnalytics:LogCustomEvent(player, eventName, value or 1, customFields)
	end)
end

-- Game milestones other services report. Kept here so the event names live in one place.
function AnalyticsService:ToolTier(player: Player, tier: number, name: string)
	AnalyticsService:Progress(player, "Tools", tier, `{tier} {name}`)
	if tier >= 2 then
		AnalyticsService:Custom(player, "ToolBought", tier, { Tool = name })
	end
end

function AnalyticsService:ZoneUnlocked(player: Player, zoneId: string)
	for i, zone in Zones.List do
		if zone.Id == zoneId then
			AnalyticsService:Progress(player, "Zones", i, `{i} {zone.Name}`)
			break
		end
	end
	AnalyticsService:Custom(player, "ZoneUnlocked", 1, { Zone = zoneId })
end

function AnalyticsService:Rebirthed(player: Player, rebirths: number)
	if rebirths <= MAX_REBIRTH_STEP then
		AnalyticsService:Progress(player, "Rebirths", rebirths, `Rebirth {rebirths}`)
	end
	AnalyticsService:Custom(player, "Rebirth", rebirths)
end

local function sessionMinutes(player: Player): number
	local session = S.DataService:GetSession(player)
	if not session then
		return 0
	end
	return (os.time() - session.JoinedAt) / 60
end

-- Session funnel + Playtime funnel, checked every few seconds.
local function tickTime(player: Player)
	local rt = runtime[player]
	local session = S.DataService:GetSession(player)
	if not rt or not session then
		return
	end
	local minutes = sessionMinutes(player)
	while rt.sessionStep < #SESSION_MINUTES and minutes >= SESSION_MINUTES[rt.sessionStep + 1] do
		rt.sessionStep += 1
		local at = SESSION_MINUTES[rt.sessionStep]
		recurring(player, "Session", rt.sessionId, rt.sessionStep, if at == 0 then "Joined" else `{at} min`)
	end
	if onboardFlags(player) then
		local total = (session.Data.Stats.Playtime + os.time() - session.JoinedAt) / 60
		for i, at in PLAYTIME_MINUTES do
			if total < at then
				break
			end
			AnalyticsService:Progress(player, "Playtime", i, `{at} min total`)
		end
	end
end

local function watchTools(player: Player, character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			AnalyticsService:Funnel(player, "ToolEquipped")
		end
	end)
	if character:FindFirstChildOfClass("Tool") then
		AnalyticsService:Funnel(player, "ToolEquipped")
	end
end

-- Client reports: "Loaded" (loading screen gone) and "Open" (a window opened).
local function onClient(player: Player, kind: any, arg: any)
	local rt = runtime[player]
	if not rt then
		return
	end
	if kind == "Loaded" then
		AnalyticsService:Funnel(player, "Loaded")
	elseif kind == "Open" and type(arg) == "string" and WINDOWS[arg] then
		rt.lastWindow = arg
		rt.windows += 1
		AnalyticsService:Custom(player, "WindowOpened", 1, { Window = arg })
		if arg == "Shop" then
			recurring(player, "Store", visit(rt, "store", true).id, 1, "Shop opened")
		elseif arg == "Wheel" then
			recurring(player, "Wheel", visit(rt, "wheel", true).id, 1, "Wheel opened")
		end
	end
end

local function onLoaded(player: Player, session: any)
	local data = session.Data
	if data.Flags.Onboard == nil then
		-- New enough: never swept a tile and never finished the tutorial.
		local fresh = data.Stats.TilesCleared == 0 and not data.Flags.TutorialDone
		data.Flags.Onboard = if fresh then {} else false
	end
	runtime[player] = { sessionId = HttpService:GenerateGUID(false), sessionStep = 0, windows = 0 }
	AnalyticsService:Funnel(player, "Spawn")
	tickTime(player)
	if player.Character then
		watchTools(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		watchTools(player, character)
	end)
end

local function onReleasing(player: Player, session: any)
	local pending = incomeBuffer[player]
	incomeBuffer[player] = nil
	if pending then
		AnalyticsService:Source(player, pending, Enum.AnalyticsEconomyTransactionType.Gameplay, "AlienIncome")
	end
	local rt = runtime[player]
	runtime[player] = nil
	-- Where people were when they left: tutorial step (or Done), last window opened.
	local data = session.Data
	local step = "Done"
	if not data.Flags.TutorialDone then
		step = S.StateService:GetTutorialStep(player) or "?"
	end
	local minutes = (os.time() - session.JoinedAt) / 60
	AnalyticsService:Custom(player, "SessionEnd", math.floor(minutes * 10 + 0.5) / 10, {
		Tutorial = step,
		LastWindow = if rt then rt.lastWindow or "None" else "None",
		Rebirths = tostring(math.min(data.Rebirths or 0, 10)),
	})
end

function AnalyticsService:Init(services)
	S = services
	S.DataService.ProfileLoaded:Connect(onLoaded)
	S.DataService.ProfileReleasing:Connect(onReleasing)
	Net.onEvent("Analytics", onClient)
end

function AnalyticsService:Start()
	task.spawn(function()
		while true do
			task.wait(60)
			for player, amount in incomeBuffer do
				incomeBuffer[player] = nil
				AnalyticsService:Source(player, amount, Enum.AnalyticsEconomyTransactionType.Gameplay, "AlienIncome")
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(10)
			for player in runtime do
				tickTime(player)
			end
		end
	end)
end

return AnalyticsService
