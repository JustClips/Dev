--!strict
-- Alien index (collection book): found aliens in color, missing ones as dark silhouettes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Aliens = require(Shared.Config.Aliens)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)

local IndexController = {}

local gui: ScreenGui
local grid: ScrollingFrame
local template: Frame
local countLabel: TextLabel
local lastSignature = ""

local function render()
	local data = State.data
	if not data then
		return
	end
	local found = {}
	for id in data.Index do
		table.insert(found, id)
	end
	table.sort(found)
	local signature = table.concat(found, ",")
	if signature == lastSignature and #grid:GetChildren() > 2 then
		return
	end
	lastSignature = signature

	for _, child in grid:GetChildren() do
		if child:IsA("Frame") and child ~= template then
			child:Destroy()
		end
	end
	local count = 0
	for i, def in Aliens.List do
		local known = data.Index[def.Id] == true
		if known then
			count += 1
		end
		local rarity = Eggs.ByName[def.Rarity]
		local card = template:Clone()
		card.Name = def.Id
		card.LayoutOrder = i
		card.Visible = true
		local swatch = card:FindFirstChild("Swatch") :: Frame
		swatch.BackgroundColor3 = if known then def.Color else Color3.fromRGB(15, 15, 25)
		local stroke = swatch:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = rarity.Color
		end
		;(card:FindFirstChild("Name") :: TextLabel).Text = if known then def.Name else "???"
		;(card:FindFirstChild("Info") :: TextLabel).Text = if known then `{def.Rarity} · {Format.cash(def.Income)}/s` else def.Rarity
		;(card:FindFirstChild("Info") :: TextLabel).TextColor3 = rarity.Color
		card.Parent = grid
	end
	countLabel.Text = `{count} / {#Aliens.List}`
end

function IndexController:Toggle()
	Ui.toggle("Index")
	render()
end

function IndexController:Init()
	gui = Ui.screen("Index")
	grid = Ui.find(gui, "Window.Grid")
	template = Ui.find(gui, "Window.Grid.Template")
	countLabel = Ui.find(gui, "Window.Count")
end

function IndexController:Start()
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Index")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Index")
	end)
	State.Changed:Connect(function()
		if gui.Enabled then
			render()
		end
	end)
end

return IndexController
