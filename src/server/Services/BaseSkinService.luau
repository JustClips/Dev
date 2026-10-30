--!strict
-- Base skins (Config/BaseSkins): unlock when the requirements are met (checked here, never
-- trusted from the client), equip one, and show it on the owner's base for everyone.
-- Net.func("BaseSkin"):InvokeServer(action, skinId) -> ok, message
--   "Unlock"   requirements met -> owned
--   "Equip"    owned -> shown on your base
--   "Preview"  shows any skin on your base for PREVIEW_SECONDS, then puts yours back
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Aliens = require(Shared.Config.Aliens)
local BaseSkins = require(Shared.Config.BaseSkins)
local Net = require(Shared.Net)
local World = require(Shared.Config.World)
local MapBuilder = require(script.Parent.Parent.Lib.MapBuilder)

local BaseSkinService = {}

local S: any
local PREVIEW_SECONDS = 10

local function rarityOf(id: string): string?
	local def = Aliens.ById[id]
	return if def then def.Rarity else nil
end

local function skinData(data)
	data.BaseSkins = data.BaseSkins or { Owned = { Classic = true }, Equipped = BaseSkins.Default }
	data.BaseSkins.Owned = data.BaseSkins.Owned or {}
	data.BaseSkins.Owned[BaseSkins.Default] = true
	if not BaseSkins.ById[data.BaseSkins.Equipped or ""] then
		data.BaseSkins.Equipped = BaseSkins.Default
	end
	return data.BaseSkins
end

function BaseSkinService:GetProgress(player: Player, skinId: string): BaseSkins.Progress?
	local data = S.DataService:GetData(player)
	local def = BaseSkins.ById[skinId]
	if not data or not def then
		return nil
	end
	return BaseSkins.progress(def, data.Rebirths, data.Index, rarityOf)
end

-- Shows the owner's equipped skin on their base (or the classic base when it's empty).
local function show(index: number, skinId: string?)
	local ok, err = pcall(MapBuilder.applySkin, index, skinId or BaseSkins.Default)
	if not ok then
		warn("[BaseSkinService] applySkin failed: " .. tostring(err))
	end
end

local function refresh(player: Player)
	local data = S.DataService:GetData(player)
	local index = S.BaseService:GetBaseIndex(player)
	if data and index then
		show(index, skinData(data).Equipped)
	end
end

local ACTIONS: { [string]: (Player, string) -> (boolean, string) } = {
	Unlock = function(player, skinId)
		local data = S.DataService:GetData(player)
		local def = BaseSkins.ById[skinId]
		local skins = skinData(data)
		if skins.Owned[skinId] then
			return false, "You already own this base"
		end
		local progress = BaseSkins.progress(def, data.Rebirths, data.Index, rarityOf)
		if not progress.Met then
			return false, "You don't meet the requirements yet"
		end
		skins.Owned[skinId] = true
		skins.Equipped = skinId
		refresh(player)
		S.AnalyticsService:Custom(player, "BaseSkinUnlocked", 0, { Skin = skinId })
		S.StateService:Mark(player)
		return true, `{def.Name} unlocked and equipped!`
	end,
	Equip = function(player, skinId)
		local data = S.DataService:GetData(player)
		local skins = skinData(data)
		if not skins.Owned[skinId] then
			return false, "Unlock this base first"
		end
		skins.Equipped = skinId
		refresh(player)
		S.StateService:Mark(player)
		return true, `{BaseSkins.ById[skinId].Name} equipped`
	end,
	Preview = function(player, skinId)
		local index = S.BaseService:GetBaseIndex(player)
		local session = S.DataService:GetSession(player)
		if not index or not session then
			return false, "No base yet"
		end
		local token = os.clock()
		session.Runtime.SkinPreview = token
		show(index, skinId)
		task.delay(PREVIEW_SECONDS, function()
			if session.Runtime.SkinPreview == token and player.Parent then
				session.Runtime.SkinPreview = nil
				refresh(player)
			end
		end)
		return true, `Previewing {BaseSkins.ById[skinId].Name}`
	end,
}

function BaseSkinService:Init(services)
	S = services
	Net.onInvoke("BaseSkin", function(player, action: any, skinId: any)
		if type(action) ~= "string" or type(skinId) ~= "string" or not ACTIONS[action] or not BaseSkins.ById[skinId] then
			return false, "Unknown base"
		end
		if not S.DataService:GetData(player) then
			return false, "Still loading"
		end
		return ACTIONS[action](player, skinId)
	end)
end

function BaseSkinService:Start()
	-- Owners get their skin as soon as the props exist; empty bases go back to classic.
	S.DataService.ProfileLoaded:Connect(function(player: Player)
		task.defer(refresh, player)
	end)
	S.DataService.ProfileReleasing:Connect(function(_player: Player, session)
		local index = session.Runtime.BaseIndex
		if index then
			show(index, nil)
		end
	end)
	MapBuilder.onPropsReady(function()
		for i = 1, World.BaseCount do
			local owner = S.BaseService:GetOwner(i)
			if owner then
				refresh(owner)
			end
		end
	end)
end

return BaseSkinService
