--!strict
-- Rare hatch lines in the chat window (HatchFeedService, remote "ChatHatch"), Sol's RNG
-- style: a system message in the pet's rarity colour. "[GLOBAL]" lines come from other
-- servers.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Eggs = require(Shared.Config.Eggs)
local Net = require(Shared.Net)

local ChatController = {}

local channel: TextChannel? = nil

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function getChannel(): TextChannel?
	if channel and channel.Parent then
		return channel
	end
	local channels = TextChatService:FindFirstChild("TextChannels")
	local found = channels and channels:FindFirstChild("RBXGeneral")
	channel = if found and found:IsA("TextChannel") then found else nil
	return channel
end

local function show(text: any, rarity: any)
	if type(text) ~= "string" then
		return
	end
	local target = getChannel()
	if not target then
		return
	end
	local def = type(rarity) == "string" and Eggs.ByName[rarity] or nil
	local color = if def then def.Color:ToHex() else "FFFFFF"
	local line = `<font color="#{color}"><b>{escape(text)}</b></font>`
	pcall(function()
		target:DisplaySystemMessage(line)
	end)
end

function ChatController:Init() end

function ChatController:Start()
	Net.event("ChatHatch").OnClientEvent:Connect(show)
	-- VIP pass owners get a gold [VIP] tag in chat (the server sets the VIP attribute).
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local source = message.TextSource
		local speaker = source and Players:GetPlayerByUserId(source.UserId)
		if speaker and speaker:GetAttribute("VIP") then
			local props = Instance.new("TextChatMessageProperties")
			props.PrefixText = `<font color="#FFC83C"><b>[VIP]</b></font> {message.PrefixText}`
			return props
		end
		return nil
	end
end

return ChatController
