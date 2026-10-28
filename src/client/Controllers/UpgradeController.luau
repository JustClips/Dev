--!strict
-- Upgrades window (Upgrade Station on the south plaza, or the rail button): one row per
-- upgrade with its level pips, current bonus and the price of the next level.
-- Also bobs the floating arrow over the station.
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local BigNum = require(Shared.BigNum)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Upgrades = require(Shared.Config.Upgrades)

local GREEN = Color3.fromRGB(61, 220, 90)
local GREY = Color3.fromRGB(166, 174, 194)
local GOLD = Color3.fromRGB(255, 200, 60)
local PIP_ON = Color3.fromRGB(255, 154, 60)
local PIP_OFF = Color3.fromRGB(200, 206, 222)

local UpgradeController = {}

local C: any
local gui: ScreenGui
local list: ScrollingFrame
local template: Frame

local function render()
	local data = State.data
	if not data or not gui.Enabled then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("Frame") and child ~= template then
			child:Destroy()
		end
	end
	for i, def in Upgrades.List do
		local level = data.Upgrades[def.Id] or 0
		local maxed = level >= def.MaxLevel
		local row = template:Clone()
		row.Name = def.Id
		row.LayoutOrder = i
		row.Visible = true
		;(row:FindFirstChild("Name") :: TextLabel).Text = def.Name
		;(row:FindFirstChild("Desc") :: TextLabel).Text = def.Description
		;(row:FindFirstChild("Icon") :: ImageLabel).Image = AssetLibrary.image(def.Icon)
		local effect = row:FindFirstChild("Effect") :: TextLabel
		effect.Text = if maxed
			then Upgrades.describe(def, level)
			else `{Upgrades.describe(def, level)} → {Upgrades.describe(def, level + 1)}`
		local pips = row:FindFirstChild("Pips") :: Frame
		local pipTemplate = pips:FindFirstChild("Template") :: Frame
		for n = 1, def.MaxLevel do
			local pip = pipTemplate:Clone()
			pip.Name = "Pip"
			pip.LayoutOrder = n
			pip.Visible = true
			pip.BackgroundColor3 = if n <= level then PIP_ON else PIP_OFF
			pip.Parent = pips
		end
		local buy = row:FindFirstChild("Buy") :: TextButton
		if maxed then
			Ui.setText(buy, "MAX")
			buy.BackgroundColor3 = GOLD
		else
			local cost = Upgrades.cost(def, level)
			Ui.setText(buy, Format.cash(cost))
			buy.BackgroundColor3 = if BigNum.gte(data.Cash, cost) then GREEN else GREY
			Ui.button(buy, function()
				local ok, message = Net.func("BuyUpgrade"):InvokeServer(def.Id)
				if message and message ~= "" then
					C.HudController:Toast(message, if ok then "Good" else "Bad")
				end
			end)
		end
		row.Parent = list
	end
end

function UpgradeController:Toggle()
	Ui.toggle("Upgrades")
	render()
end

function UpgradeController:Open()
	Ui.open("Upgrades")
	render()
end

local function bobHologram()
	local structures = Workspace:WaitForChild("Structures", 60)
	local station = structures and structures:WaitForChild("UpgradeStation", 30)
	local holo = station and station:WaitForChild("Hologram", 30)
	local billboard = holo and holo:FindFirstChildOfClass("BillboardGui")
	if not billboard or Ui.reducedMotion() then
		return
	end
	local info = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(billboard, info, { StudsOffset = Vector3.new(0, 0.8, 0) }):Play()
end

function UpgradeController:Init(controllers)
	C = controllers
	gui = Ui.screen("Upgrades")
	list = Ui.find(gui, "Window.List")
	template = Ui.find(gui, "Window.List.Template")
end

function UpgradeController:Start()
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Upgrades")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Upgrades")
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("Opens") == "Upgrades" then
			UpgradeController:Open()
		end
	end)
	task.spawn(bobHologram)
	local lastSignature = ""
	State.Changed:Connect(function(data)
		local parts = {}
		for _, def in Upgrades.List do
			local level = data.Upgrades[def.Id] or 0
			table.insert(parts, `{level}:{BigNum.gte(data.Cash, Upgrades.cost(def, level))}`)
		end
		local signature = table.concat(parts, "|")
		if signature ~= lastSignature then
			lastSignature = signature
			render()
		end
	end)
end

return UpgradeController
